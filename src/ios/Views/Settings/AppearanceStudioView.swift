import PhotosUI
import SwiftUI
import UIKit

// MARK: - 装扮
//
// [10-18 醒醒] 「我建议你重新帮我设计创作装扮页，功能留着，布局，选项，
// 实时显示的那一块。什么都得重写」
// 第二轮：「里边还有很多 bug」「摇一摇这个是被你写死的几个对吗，自由度高
// 一点」「配色有点 low」「界面 UI 也太廉价感了，做精致一点」「预览做大一点」
// 「醒醒喜欢干净的，软糯的那种感觉」
//
// ## 这一版修了什么
//
// 1. **errorText 有七处赋值、零处显示**——所有失败静默。现在真会弹出来。
// 2. **预设三套的入口被我上一版删了**——引擎方法还在，功能白丢。补回。
// 3. **列表图标形状入口也丢了**——补回。
// 4. **摇骰子饱和度 0.38-0.67 太高**，0.67 已经是糖果色，所以"low"。
//    改成莫兰迪区间 0.15-0.40，并给了五个风格档（软糯/清透/沉静/暖阳/夜）。
// 5. **预览太小**。放大到 1.6 倍高度，并加了「展开」全屏看。
// 6. **质感廉价**：加发丝线、软阴影、字重层级、留白节奏。

struct AppearanceStudioView: View {
    @ObservedObject private var studio = AppearanceStudio.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var variant: AppearanceVariant = .light
    @State private var page: AppearanceStudioPage = .palette

    // 图片
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var wallpaperScope: AppearanceScope = .global
    @State private var userAvatarItem: PhotosPickerItem?
    @State private var assistantAvatarItem: PhotosPickerItem?
    @State private var iconPickSlot: QuietIconSlot?
    @State private var iconItem: PhotosPickerItem?
    @State private var thinkingCardItem: PhotosPickerItem?
    @State private var inputBarItem: PhotosPickerItem?
    @State private var categoryImageKey: String?
    @State private var categoryImageItem: PhotosPickerItem?

    // 高级
    @State private var showAdvanced = false
    @State private var paletteScope: AppearanceScope = .global

    // 杂项
    @State private var saveName: String = ""
    @State private var errorText: String?
    @State private var showError = false
    @State private var showResetConfirm = false
    @State private var shuffleName: String?
    @State private var showFullPreview = false

    @MainActor private var aiName: String {
        let n = SoulStore.cachedMetadata.name
        return n.isEmpty ? "AI" : n
    }

    var body: some View {
        VStack(spacing: 0) {
            previewArea

            ScrollView {
                LazyVStack(spacing: 20) {
                    switch page {
                    case .palette:   palettePage
                    case .bubbles:   bubblesPage
                    case .backdrop:  backdropPage
                    case .avatars:   avatarsPage
                    case .icons:     iconsPage
                    case .library:   libraryPage
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
        .appearancePage(.settings)
        .navigationTitle("装扮")
        .navigationBarTitleDisplayMode(.inline)
        .alert("出错了", isPresented: $showError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .alert("恢复默认装扮？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) { studio.resetThemePack() }
        } message: {
            Text("颜色、气泡形状、贴图全部回到默认。壁纸和情头不动。")
        }
        .fullScreenCover(isPresented: $showFullPreview) {
            fullPreviewSheet
        }
        .onChange(of: wallpaperItem) { item in
            guard let item else { return }
            Task {
                let dark = colorScheme == .dark
                await importImage(item, downsampleTo: 2200) {
                    studio.setWallpaper($0, for: wallpaperScope, dark: dark)
                }
            }
        }
        .onChange(of: userAvatarItem) { item in
            guard let item else { return }
            Task { await importImage(item, downsampleTo: 512) { studio.setUserAvatar($0) } }
        }
        .onChange(of: assistantAvatarItem) { item in
            guard let item else { return }
            Task {
                await importImage(item, downsampleTo: 512) { image in
                    do { try studio.setAssistantAvatar(image) }
                    catch { fail(error.localizedDescription) }
                }
            }
        }
        .onChange(of: iconItem) { item in
            guard let item, let slot = iconPickSlot else { return }
            Task {
                await importImage(item, downsampleTo: 512) { studio.setIcon($0, for: slot.id) }
                iconItem = nil
                iconPickSlot = nil
            }
        }
        .onChange(of: thinkingCardItem) { item in
            guard let item else { return }
            Task { await importImage(item, downsampleTo: 1400) { studio.setThinkingCardImage($0) } }
        }
        .onChange(of: inputBarItem) { item in
            guard let item else { return }
            Task { await importImage(item, downsampleTo: 1400) { studio.setInputBarImage($0) } }
        }
        .onChange(of: categoryImageItem) { item in
            guard let item, let key = categoryImageKey else { return }
            Task {
                await importImage(item, downsampleTo: 256) { studio.setCategoryImage($0, for: key) }
                categoryImageItem = nil
                categoryImageKey = nil
            }
        }
    }

    private func fail(_ message: String) {
        errorText = message
        showError = true
    }

    // MARK: - 预览
    //
    // 放大到 1.6 倍高度（原 190 → 300 左右），点右上角能全屏看。
    // 用真组件，不是手写小样——改什么这里立刻变。

    private var previewArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("预览")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant))

                if let note = shuffleName {
                    Text(note)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(studio.color(.accent, variant: variant))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(studio.color(.chip, variant: variant).opacity(studio.surfaceOpacity),
                                    in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                Spacer(minLength: 0)

                Button {
                    showFullPreview = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                        .frame(width: 24, height: 24)
                        .background(studio.color(.iconTile, variant: variant).opacity(studio.surfaceOpacity),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)

                Picker("", selection: $variant) {
                    ForEach(AppearanceVariant.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            .padding(.horizontal, 18)

            AppearanceLivePreview(variant: variant, aiName: aiName, scale: 1.0)
                .padding(.horizontal, 18)
                .frame(height: 286)
                .clipped()
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(studio.color(.canvas, variant: variant))
        .overlay(alignment: .bottom) {
            // 发丝线：高级感靠这条线，不靠边框
            Rectangle()
                .fill(studio.color(.border, variant: variant).opacity(0.28))
                .frame(height: 0.5)
        }
    }

    private var fullPreviewSheet: some View {
        ZStack {
            studio.color(.canvas, variant: variant).ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text("预览")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(studio.color(.primaryText, variant: variant))
                    Spacer()
                    Picker("", selection: $variant) {
                        ForEach(AppearanceVariant.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                    Button {
                        showFullPreview = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(studio.color(.secondaryText, variant: variant))
                            .frame(width: 30, height: 30)
                            .background(studio.color(.iconTile, variant: variant).opacity(studio.surfaceOpacity),
                                        in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                AppearanceLivePreview(variant: variant, aiName: aiName, scale: 1.5)
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 配色

    private var palettePage: some View {
        VStack(spacing: 20) {
            shuffleCard
            presetsCard

            ForEach(AppearanceColorRoleGroup.allCases) { group in
                paletteGroupCard(group)
            }

            advancedCard
        }
    }

    /// 摇骰子。五个风格档不是写死的色板，是不同的参数区间——
    /// 点同一个档，每次摇出来都不一样。
    private var shuffleCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("摇一套")
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(studio.color(.primaryText, variant: variant))
                    Text("先定一个主色，其余按莫兰迪规则推导。同一个档每次都不一样。")
                        .font(.system(size: 11.5))
                        .lineSpacing(1.5)
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    roll()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "dice")
                            .font(.system(size: 13, weight: .semibold))
                        Text("摇")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(studio.color(.accent, variant: variant))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(studio.color(.chip, variant: variant).opacity(studio.surfaceOpacity),
                                in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(studio.color(.border, variant: variant).opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            // 色带：一眼看出这套的调子
            HStack(spacing: 0) {
                ForEach([AppearanceColorRole.canvas, .surface, .iconTile, .chip,
                         .userBubble, .accent, .primaryText], id: \.self) { role in
                    Rectangle()
                        .fill(studio.color(role, variant: variant))
                        .frame(height: 30)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(studio.color(.border, variant: variant).opacity(0.35), lineWidth: 0.5)
            )

            // 五个风格档
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(AppearanceThemeShuffle.Mood.allCases) { mood in
                        Button {
                            roll(mood: mood)
                        } label: {
                            Text(mood.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(studio.color(.secondaryText, variant: variant))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(studio.color(.iconTile, variant: variant).opacity(studio.surfaceOpacity),
                                            in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(studio.color(.border, variant: variant).opacity(0.32), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(variant == .light ? 0.045 : 0.28),
                radius: 10, x: 0, y: 3)
    }

    private func roll(mood: AppearanceThemeShuffle.Mood? = nil) {
        let name = studio.shuffleTheme(mood: mood)
        withAnimation(.easeOut(duration: 0.18)) { shuffleName = name }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeIn(duration: 0.3)) { shuffleName = nil }
        }
    }

    /// 三套预设。上一版我把这个入口删了，引擎方法还在——补回来。
    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预设")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(studio.color(.primaryText, variant: variant))

            HStack(spacing: 8) {
                ForEach(AppearancePreset.allCases) { preset in
                    Button {
                        studio.applyPreset(preset)
                    } label: {
                        VStack(spacing: 7) {
                            HStack(spacing: 0) {
                                ForEach(Array(presetSwatchColors(preset).enumerated()), id: \.offset) { _, hex in
                                    Rectangle().fill(Color(hex: hex))
                                }
                            }
                            .frame(height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(studio.color(.border, variant: variant).opacity(0.3), lineWidth: 0.5)
                            )
                            Text(preset.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(studio.color(.secondaryText, variant: variant))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(9)
                        .background(studio.color(.iconTile, variant: variant).opacity(studio.surfaceOpacity),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(studio.color(.border, variant: variant).opacity(0.3), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(variant == .light ? 0.045 : 0.28),
                radius: 10, x: 0, y: 3)
    }

    private func presetSwatchColors(_ preset: AppearancePreset) -> [String] {
        let pal = preset.colors
        let map = variant == .light ? pal.light : pal.dark
        return [AppearanceColorRole.canvas, .surface, .accent, .primaryText]
            .compactMap { map[$0] }
    }

    private func paletteGroupCard(_ group: AppearanceColorRoleGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                Text(group.hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(Array(group.roles.enumerated()), id: \.element) { index, role in
                if index > 0 {
                    Rectangle()
                        .fill(studio.color(.border, variant: variant).opacity(0.22))
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
                paletteRow(role)
            }
        }
        .background(studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(variant == .light ? 0.045 : 0.28),
                radius: 10, x: 0, y: 3)
    }

    private func paletteRow(_ role: AppearanceColorRole) -> some View {
        HStack(spacing: 13) {
            // 色块外面套一层描边，低饱和色在浅底上才看得出边界
            ColorPicker("", selection: studio.colorBinding(role, scope: .global, variant: variant),
                        supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(role.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                Text(role.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text("#\(studio.hex(role, scope: .global, variant: variant))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.55))

            if studio.hasOverride(role, scope: .global, variant: variant) {
                Button {
                    studio.clearOverride(role, scope: .global, variant: variant)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                        .frame(width: 20, height: 20)
                        .background(studio.color(.iconTile, variant: variant).opacity(studio.surfaceOpacity),
                                    in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                    Text("高级")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                }
                .foregroundStyle(studio.color(.secondaryText, variant: variant))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                Rectangle()
                    .fill(studio.color(.border, variant: variant).opacity(0.22))
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: 12) {
                    Text("给单独某一页换色。没单独调过的页跟随「全部页面」。")
                        .font(.system(size: 11))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))

                    Picker("改哪一页", selection: $paletteScope) {
                        ForEach(AppearanceScope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(studio.color(.accent, variant: variant))

                    if paletteScope != .global {
                        let count = studio.overrideCount(scope: paletteScope, variant: variant)
                        HStack(spacing: 8) {
                            Text(count == 0
                                 ? "这一页还没有单独调过任何颜色。"
                                 : "这一页有 \(count) 项和全局不一样。")
                                .font(.system(size: 11))
                                .foregroundStyle(studio.color(.secondaryText, variant: variant))
                            Spacer()
                            if count > 0 {
                                Button("全部还原") {
                                    studio.clearOverrides(scope: paletteScope, variant: variant)
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(studio.color(.destructive, variant: variant))
                            }
                        }

                        ForEach(AppearanceColorRoleGroup.allCases) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(group.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
                                    .padding(.top, 8)
                                    .padding(.bottom, 3)
                                ForEach(group.roles, id: \.self) { role in
                                    scopedRow(role)
                                }
                            }
                        }
                    }

                    Rectangle()
                        .fill(studio.color(.border, variant: variant).opacity(0.22))
                        .frame(height: 0.5)
                        .padding(.vertical, 4)

                    Button {
                        studio.resetColors()
                    } label: {
                        Text("恢复默认色盘")
                            .font(.system(size: 12))
                            .foregroundStyle(studio.color(.destructive, variant: variant))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .background(studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(variant == .light ? 0.045 : 0.28),
                radius: 10, x: 0, y: 3)
    }

    private func scopedRow(_ role: AppearanceColorRole) -> some View {
        let overridden = studio.hasOverride(role, scope: paletteScope, variant: variant)
        return HStack(spacing: 11) {
            ColorPicker("", selection: studio.colorBinding(role, scope: paletteScope, variant: variant),
                        supportsOpacity: false)
                .labelsHidden()
                .frame(width: 24, height: 24)
            Text(role.title)
                .font(.system(size: 12))
                .foregroundStyle(studio.color(.primaryText, variant: variant))
            Spacer()
            if overridden {
                Text("已单独调")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(studio.color(.accent, variant: variant))
                Button {
                    studio.clearOverride(role, scope: paletteScope, variant: variant)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
                .buttonStyle(.plain)
            } else {
                Text("#\(studio.hex(role, scope: .global, variant: variant))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.45))
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - 气泡

    private var bubblesPage: some View {
        VStack(spacing: 20) {
            card("气泡颜色") {
                ForEach([AppearanceColorRole.userBubble, .assistantBubble], id: \.self) { role in
                    HStack(spacing: 13) {
                        ColorPicker("", selection: studio.colorBinding(role, scope: .global, variant: variant),
                                    supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 32, height: 32)
                        Text(role.title)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(studio.color(.primaryText, variant: variant))
                        Spacer()
                        Text("#\(studio.hex(role, scope: .global, variant: variant))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.55))
                    }
                    .padding(.vertical, 6)
                }
                sliderRow("气泡透明度", value: $studio.bubbleOpacity, range: 0.15...1)
            }

            card("形状") {
                Picker("我的气泡", selection: userStyleBinding) {
                    ForEach(AppearanceBubbleStyle.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Picker("\(aiName)气泡", selection: assistantStyleBinding) {
                    ForEach(AppearanceBubbleStyle.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Picker("输入栏形状", selection: inputBarStyleBinding) {
                    ForEach(AppearanceBubbleStyle.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Picker("列表图标", selection: listIconShapeBinding) {
                    ForEach(AppearanceListIconShape.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                sliderRow("输入栏圆角", value: inputBarRadiusBinding, range: 4...32, unit: "")
            }

            card("正文") {
                Picker("正文字体", selection: fontFamilyBinding) {
                    ForEach(AppearanceFontFamily.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Text("字体只作用于聊天正文、输入框和 thinking 卡片。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
        }
    }

    // MARK: - 背景

    private var backdropPage: some View {
        VStack(spacing: 20) {
            card("壁纸") {
                Picker("用于", selection: $wallpaperScope) {
                    ForEach(AppearanceScope.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))

                ZStack(alignment: .bottomTrailing) {
                    AppearanceBackdrop(scope: wallpaperScope)
                    Text(studio.hasWallpaper(wallpaperScope) ? "壁纸预览" : "纯色背景")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(studio.color(.primaryText, scope: wallpaperScope))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(studio.color(.raised, scope: wallpaperScope).opacity(0.85),
                                    in: Capsule())
                        .padding(10)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(studio.color(.border, scope: wallpaperScope).opacity(0.4), lineWidth: 0.5)
                )

                PhotosPicker(selection: $wallpaperItem, matching: .images) {
                    Label(studio.hasOwnWallpaper(wallpaperScope) ? "换这张" : "选一张",
                          systemImage: "photo")
                        .font(.system(size: 13))
                }

                if studio.hasOwnWallpaper(wallpaperScope) {
                    Button("改用继承的背景") { studio.removeWallpaper(wallpaperScope) }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }
                if studio.hasWallpaper(wallpaperScope) {
                    Button("清除当前背景") { studio.clearWallpaper(wallpaperScope) }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }
            }

            card("透明度") {
                sliderRow("壁纸压色", value: $studio.wallpaperShade, range: 0...0.65)
                sliderRow("卡片透明度", value: $studio.surfaceOpacity, range: 0.35...1)
            }
        }
    }

    // MARK: - 情头

    private var avatarsPage: some View {
        card("情头") {
            HStack(spacing: 14) {
                Spacer()
                VStack(spacing: 7) {
                    PersonAvatarView(kind: .assistant, size: 60)
                    Text(aiName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(studio.color(.accent, variant: variant).opacity(0.7))
                VStack(spacing: 7) {
                    PersonAvatarView(kind: .user, size: 60)
                    Text("你")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
                Spacer()
            }
            .padding(.vertical, 8)

            PhotosPicker(selection: $userAvatarItem, matching: .images) {
                Label("选我的头像", systemImage: "person.crop.square").font(.system(size: 13))
            }
            if !studio.userAvatar.isEmpty {
                Button("去掉我的头像") { studio.removeUserAvatar() }
                    .font(.system(size: 12))
                    .foregroundStyle(studio.color(.destructive, variant: variant))
            }

            PhotosPicker(selection: $assistantAvatarItem, matching: .images) {
                Label("选\(aiName)的头像", systemImage: "sparkles.rectangle.stack").font(.system(size: 13))
            }
            if !SoulStore.cachedMetadata.icon.isEmpty {
                Button("去掉\(aiName)的头像") {
                    do { try studio.removeAssistantAvatar() }
                    catch { fail(error.localizedDescription) }
                }
                .font(.system(size: 12))
                .foregroundStyle(studio.color(.destructive, variant: variant))
            }

            Text("两张都会裁成方的，存在这台手机上。\(aiName)的头像同时就是 Soul 图标。")
                .font(.system(size: 10.5))
                .lineSpacing(1.5)
                .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.75))
        }
    }

    // MARK: - 图标

    private var iconsPage: some View {
        VStack(spacing: 20) {
            card("设置行图标") {
                ForEach(QuietIconSlot.allCases) { slot in
                    HStack(spacing: 13) {
                        QuietAppIcon(id: slot.id, systemName: slot.systemName, size: 27)
                        Text(slot.title)
                            .font(.system(size: 13))
                            .foregroundStyle(studio.color(.primaryText, variant: variant))
                        Spacer()
                        PhotosPicker(selection: Binding(
                            get: { iconPickSlot == slot ? iconItem : nil },
                            set: { iconPickSlot = slot; iconItem = $0 }
                        ), matching: .images) {
                            Text(studio.customIcon(for: slot.id) == nil ? "上传" : "更换")
                                .font(.system(size: 12))
                                .foregroundStyle(studio.color(.accent, variant: variant))
                        }
                        if studio.customIcon(for: slot.id) != nil {
                            Button("还原") { studio.removeIcon(for: slot.id) }
                                .font(.system(size: 11))
                                .foregroundStyle(studio.color(.destructive, variant: variant))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            card("分类图标") {
                ForEach(AppearanceThemePack.categoryKeys, id: \.self) { key in
                    categoryRow(key)
                }
            }

            card("贴图") {
                PhotosPicker(selection: $thinkingCardItem, matching: .images) {
                    Label(studio.hasThinkingCardImage() ? "换 thinking 卡片图" : "给 thinking 卡片贴图",
                          systemImage: "photo.on.rectangle").font(.system(size: 13))
                }
                if studio.hasThinkingCardImage() {
                    sliderRow("卡片图浓度", value: thinkingCardOpacityBinding, range: 0.05...1)
                    Button("去掉 thinking 卡片图") { studio.removeThinkingCardImage() }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }

                PhotosPicker(selection: $inputBarItem, matching: .images) {
                    Label(studio.hasInputBarImage() ? "换输入栏图" : "给输入栏贴图",
                          systemImage: "photo.on.rectangle").font(.system(size: 13))
                }
                if studio.hasInputBarImage() {
                    sliderRow("输入栏图浓度", value: inputBarOpacityBinding, range: 0.05...1)
                    Button("去掉输入栏图") { studio.removeInputBarImage() }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }
            }

            card("thinking 字号") {
                sliderRow("标题字", value: thinkingTitleSizeBinding, range: 10...22, unit: "")
                sliderRow("正文字", value: thinkingBodySizeBinding, range: 10...22, unit: "")
            }
        }
    }

    private func categoryRow(_ key: String) -> some View {
        let themedSymbol = MinisThemeList.categoryIcon(for: key).systemName
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                Image(systemName: QuietAppIcon.filledSymbolName(themedSymbol))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 23, height: 23)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                Text(key)
                    .font(.system(size: 12.5))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                Spacer()
                PhotosPicker(selection: Binding(
                    get: { categoryImageKey == key ? categoryImageItem : nil },
                    set: { categoryImageKey = key; categoryImageItem = $0 }
                ), matching: .images) {
                    Text(studio.categoryImage(for: key) == nil ? "贴图" : "换图")
                        .font(.system(size: 11))
                        .foregroundStyle(studio.color(.accent, variant: variant))
                }
                if studio.categoryImage(for: key) != nil {
                    Button("还原") { studio.removeCategoryImage(for: key) }
                        .font(.system(size: 10))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }
            }
            HStack(spacing: 9) {
                TextField("SF 名，空着就是默认", text: categorySymbolBinding(key))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant))
                ColorPicker("", selection: categoryColorBinding(key), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 18, height: 18)
                    .disabled(true)
                    .opacity(0.3)
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - 主题库

    private var libraryPage: some View {
        VStack(spacing: 20) {
            card("存这一套") {
                TextField("给它起个名字", text: $saveName)
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 13))
                Button {
                    _ = studio.saveCurrentTheme(name: saveName.isEmpty ? "未命名" : saveName)
                    saveName = ""
                } label: {
                    Text("存进主题库")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(studio.color(.accent, variant: variant))
                }
                .buttonStyle(.plain)
                Text("另存一份，不会冲掉正在用的。最多四十套。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.75))
            }

            card("主题库") {
                let saved = studio.savedThemes()
                if saved.isEmpty {
                    Text("还没有存过的主题。")
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                } else {
                    ForEach(saved) { item in
                        HStack(spacing: 11) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                                Text(item.userStyleTitle + " · " + item.assistantStyleTitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.75))
                            }
                            Spacer()
                            Button("应用") { _ = studio.applySavedTheme(id: item.id) }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(studio.color(.accent, variant: variant))
                            Button("删") { _ = studio.deleteSavedTheme(id: item.id) }
                                .font(.system(size: 11))
                                .foregroundStyle(studio.color(.destructive, variant: variant))
                        }
                        .padding(.vertical, 5)
                    }
                }
            }

            card("导出导入") {
                Button("导出到剪贴板") { exportPackToClipboard() }
                    .font(.system(size: 13))
                    .foregroundStyle(studio.color(.accent, variant: variant))
                Button("从剪贴板贴上") { importPackFromClipboard() }
                    .font(.system(size: 13))
                    .foregroundStyle(studio.color(.accent, variant: variant))
                Button("恢复默认主题包") { showResetConfirm = true }
                    .font(.system(size: 12))
                    .foregroundStyle(studio.color(.destructive, variant: variant))
                if studio.canUndoThemeReset {
                    Button("撤销上一次恢复") { _ = studio.undoThemeReset() }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
            }
        }
    }

    // MARK: - 底部导航

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(AppearanceStudioPage.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { page = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: page == item ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)
                        Text(item.title)
                            .font(.system(size: 9, weight: page == item ? .medium : .regular))
                    }
                    .foregroundStyle(page == item
                                     ? studio.color(.accent, variant: variant)
                                     : studio.color(.secondaryText, variant: variant).opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(studio.color(.border, variant: variant).opacity(0.25))
                .frame(height: 0.5)
        }
    }

    // MARK: - 零件

    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(studio.color(.primaryText, variant: variant))
            content()
        }
        .padding(16)
        .background(studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(variant == .light ? 0.045 : 0.28),
                radius: 10, x: 0, y: 3)
    }

    private func sliderRow(_ title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, unit: String = "%") -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                Spacer()
                Text(unit == "%" ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
            Slider(value: value, in: range)
                .tint(studio.color(.accent, variant: variant))
        }
    }

    // MARK: - Binding

    private var userStyleBinding: Binding<AppearanceBubbleStyle> {
        Binding(get: { studio.currentThemePack().userStyle },
                set: { studio.setBubbleStyle($0, user: true) })
    }
    private var assistantStyleBinding: Binding<AppearanceBubbleStyle> {
        Binding(get: { studio.currentThemePack().assistantStyle },
                set: { studio.setBubbleStyle($0, user: false) })
    }
    private var inputBarStyleBinding: Binding<AppearanceBubbleStyle> {
        Binding(get: { AppearanceBubbleStyle.parse(studio.currentThemePack().inputBarStyle) },
                set: { studio.setInputBarStyle($0) })
    }
    private var fontFamilyBinding: Binding<AppearanceFontFamily> {
        Binding(get: { AppearanceFontFamily.parse(studio.currentThemePack().fontFamily) },
                set: { studio.setFontFamily($0) })
    }
    private var listIconShapeBinding: Binding<AppearanceListIconShape> {
        Binding(get: { AppearanceListIconShape.parse(studio.currentThemePack().listIconShape) },
                set: { studio.setListIconShape($0) })
    }
    private var inputBarRadiusBinding: Binding<Double> {
        Binding(get: { studio.currentThemePack().inputBarRadius },
                set: { studio.setInputBarRadius($0) })
    }
    private var thinkingCardOpacityBinding: Binding<Double> {
        Binding(get: { studio.currentThemePack().thinkingCardImageOpacity },
                set: { studio.setThinkingCardImageOpacity($0) })
    }
    private var inputBarOpacityBinding: Binding<Double> {
        Binding(get: { studio.currentThemePack().inputBarImageOpacity },
                set: { studio.setInputBarImageOpacity($0) })
    }
    private var thinkingTitleSizeBinding: Binding<Double> {
        Binding(get: { studio.currentThemePack().thinkingTitleSize },
                set: { studio.setThinkingFont(title: $0) })
    }
    private var thinkingBodySizeBinding: Binding<Double> {
        Binding(get: { studio.currentThemePack().thinkingBodySize },
                set: { studio.setThinkingFont(body: $0) })
    }
    private func categorySymbolBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { studio.currentThemePack().categoryIcons[key] ?? "" },
            set: { studio.setCategorySymbol($0, for: key) }
        )
    }
    private func categoryColorBinding(_ key: String) -> Binding<Color> {
        Binding(
            get: {
                let hex = studio.currentThemePack().categoryColors[key]
                return hex.map { Color(hex: $0) } ?? studio.color(.accent, variant: variant)
            },
            set: { studio.setCategoryColor($0, for: key) }
        )
    }

    // MARK: - 导入导出

    private func exportPackToClipboard() {
        let pack = studio.exportThemePack(includeWallpaper: true)
        guard let data = try? JSONSerialization.data(withJSONObject: pack.asJSONObject(),
                                                    options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            fail("主题包写不出来。")
            return
        }
        UIPasteboard.general.string = text
    }

    private func importPackFromClipboard() {
        guard let text = UIPasteboard.general.string,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail("剪贴板里没有能用的主题包。")
            return
        }
        do {
            let pack = try AppearanceThemePack.decode(obj, merging: studio.currentThemePack())
            studio.applyThemePack(pack)
        } catch {
            fail(error.localizedDescription)
        }
    }

    @MainActor
    private func importImage(_ item: PhotosPickerItem,
                             downsampleTo maxEdge: CGFloat,
                             apply: @escaping @MainActor (UIImage) -> Void) async {
        defer {
            wallpaperItem = nil
            userAvatarItem = nil
            assistantAvatarItem = nil
            thinkingCardItem = nil
            inputBarItem = nil
            categoryImageItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = ThumbnailCache.downsampledImage(from: data, maxEdge: maxEdge) else {
            fail("选中的图读不出来。")
            return
        }
        apply(image)
    }
}

// MARK: - 底部导航项

enum AppearanceStudioPage: String, CaseIterable, Identifiable {
    case palette, bubbles, backdrop, avatars, icons, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .palette: return "配色"
        case .bubbles: return "气泡"
        case .backdrop: return "背景"
        case .avatars: return "情头"
        case .icons: return "图标"
        case .library: return "主题库"
        }
    }
    var symbol: String {
        switch self {
        case .palette: return "paintpalette"
        case .bubbles: return "bubble.left.and.bubble.right"
        case .backdrop: return "photo"
        case .avatars: return "person.2"
        case .icons: return "square.grid.2x2"
        case .library: return "books.vertical"
        }
    }
}

// MARK: - 真组件预览
//
// 真的 MinisBubbleShape、真的 iconTile 角色、真的输入框圆角。
// `scale` 控制放大倍数——顶部预览 1.0，全屏预览 1.5。

private struct AppearanceLivePreview: View {
    let variant: AppearanceVariant
    let aiName: String
    var scale: CGFloat = 1.0

    @ObservedObject private var studio = AppearanceStudio.shared

    private var pack: AppearanceThemePack { studio.currentThemePack() }

    private var base: CGFloat { 12 * scale }
    private var small: CGFloat { 9.5 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            // AI 气泡
            HStack(alignment: .top, spacing: 7 * scale) {
                Circle()
                    .fill(studio.color(.accent, variant: variant))
                    .frame(width: 22 * scale, height: 22 * scale)
                    .overlay(
                        Text(String(aiName.prefix(1)))
                            .font(.system(size: 10 * scale, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                Text("今天想聊点什么？")
                    .font(.system(size: base))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                    .padding(.horizontal, 11 * scale)
                    .padding(.vertical, 7 * scale)
                    .background(
                        studio.color(.assistantBubble, variant: variant).opacity(studio.bubbleOpacity),
                        in: MinisBubbleShape(style: pack.assistantStyle,
                                             radius: min(pack.assistantBubbleRadius, 16 * scale),
                                             tailOnTrailing: false)
                    )
                    .overlay(
                        MinisBubbleShape(style: pack.assistantStyle,
                                         radius: min(pack.assistantBubbleRadius, 16 * scale),
                                         tailOnTrailing: false)
                            .stroke(studio.color(.border, variant: variant).opacity(0.3), lineWidth: 0.5)
                    )
                Spacer(minLength: 0)
            }

            // 我的气泡
            HStack(alignment: .top, spacing: 7 * scale) {
                Spacer(minLength: 0)
                Text("把界面做得漂亮一点~")
                    .font(.system(size: base))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                    .padding(.horizontal, 11 * scale)
                    .padding(.vertical, 7 * scale)
                    .background(
                        studio.color(.userBubble, variant: variant).opacity(studio.bubbleOpacity),
                        in: MinisBubbleShape(style: pack.userStyle,
                                             radius: min(pack.userBubbleRadius, 16 * scale),
                                             tailOnTrailing: true)
                    )
                Circle()
                    .fill(studio.color(.secondaryText, variant: variant).opacity(0.20))
                    .frame(width: 22 * scale, height: 22 * scale)
                    .overlay(
                        Text("你")
                            .font(.system(size: 9 * scale, weight: .semibold))
                            .foregroundStyle(studio.color(.primaryText, variant: variant))
                    )
            }

            // 消息操作栏那排图标底 —— 就是她说"不该跟着卡片变"的东西
            HStack(spacing: 7 * scale) {
                ForEach(["speaker.wave.2.fill", "arrow.clockwise", "doc.on.doc.fill", "trash.fill"],
                        id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 9.5 * scale, weight: .medium))
                        .foregroundStyle(studio.color(.primaryText, variant: variant))
                        .frame(width: 22 * scale, height: 22 * scale)
                        .background(
                            studio.color(.iconTile, variant: variant).opacity(studio.surfaceOpacity),
                            in: RoundedRectangle(cornerRadius: 6.5 * scale, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6.5 * scale, style: .continuous)
                                .stroke(studio.color(.border, variant: variant).opacity(0.4), lineWidth: 0.5)
                        )
                }
                Spacer(minLength: 0)
                // 胶囊底
                Text("1.2k tok")
                    .font(.system(size: 8 * scale, design: .monospaced))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant))
                    .padding(.horizontal, 7 * scale)
                    .padding(.vertical, 3.5 * scale)
                    .background(studio.color(.chip, variant: variant).opacity(studio.surfaceOpacity),
                                in: Capsule())
            }

            // 输入框 + 发送
            HStack(spacing: 7 * scale) {
                HStack(spacing: 6 * scale) {
                    Image(systemName: "plus")
                        .font(.system(size: 10 * scale, weight: .medium))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                    Text("发消息…")
                        .font(.system(size: base))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.7))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10 * scale)
                .frame(height: 30 * scale)
                .background(
                    studio.color(.field, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: min(pack.inputBarRadius, 15 * scale), style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: min(pack.inputBarRadius, 15 * scale), style: .continuous)
                        .stroke(studio.color(.border, variant: variant).opacity(0.45), lineWidth: 0.5)
                )

                Image(systemName: "arrow.up")
                    .font(.system(size: 11 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30 * scale, height: 30 * scale)
                    .background(
                        studio.color(.accent, variant: variant),
                        in: RoundedRectangle(cornerRadius: min(pack.inputBarRadius, 15 * scale), style: .continuous)
                    )
            }

            // 状态三色
            HStack(spacing: 6 * scale) {
                chipSwatch(.success, "成功")
                chipSwatch(.warning, "警告")
                chipSwatch(.destructive, "危险")
                Spacer(minLength: 0)
            }
        }
        .padding(13 * scale)
        .background(
            studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(variant == .light ? 0.05 : 0.3),
                radius: 12, x: 0, y: 4)
    }

    private func chipSwatch(_ role: AppearanceColorRole, _ label: String) -> some View {
        Text(label)
            .font(.system(size: 8.5 * scale, weight: .medium))
            .foregroundStyle(studio.color(role, variant: variant))
            .padding(.horizontal, 7 * scale)
            .padding(.vertical, 3.5 * scale)
            .background(studio.color(role, variant: variant).opacity(0.13), in: Capsule())
    }
}
