import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - 外观
//
// [10-18 醒醒] 「把它装进我们的"装扮"里面，外观点进去，直接就是装扮页的效果，
// 什么功能都在里面配置，然后把装扮语言统一，不分那么多页面了，死掉的就删掉。
// 没死掉的就统一。」
//
// ## 这一版做了什么
//
// 原来有两个页面各管一摊：
//   - ContentView.swift 里的 `AppearanceSettingsView`（12 个分区，行为类）
//   - 这个 `AppearanceStudioView`（6 个分区，视觉类）
//
// 现在合成一页。**「外观」这个词保留**，但点进去直接是这一页。
//
// ## 删掉的
//
// - **Theme 跟随系统/浅色/深色** —— 跟这里的明暗切换重复，只留这里的
// - **工具预览窗口** —— `toolPreviewEnabled` 全仓零消费，是个死开关
//
// ## 搬进来的
//
// 启动会话 / 自动分组 / 回车键 / 屏幕常亮 / 回复后自动聚焦 /
// 流式展开思考 / 字号三条滑杆 / App 图标 / 语言
//
// ## 语言统一
//
// 原来混着三种：`Text("装扮")` 硬编码中文、`Text("Theme")` 英文、
// `AppLocalized("...")` 本地化键。现在全部走 `AppLocalized`，中文兜底。

struct AppearanceStudioView: View {
    @ObservedObject private var studio = AppearanceStudio.shared
    @ObservedObject private var fontSettings = FontSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var variant: AppearanceVariant = .light
    @State private var page: AppearanceStudioPage = .palette

    // 行为设置
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0
    @AppStorage("appIconMode") private var appIconMode: Int = 0
    @AppStorage("appLanguage") private var appLanguage: String = ""
    @AppStorage("launchScreen") private var launchScreen: Int = 0
    @AppStorage("returnKeyBehavior") private var returnKeyBehavior: Int = 0
    @AppStorage("keepScreenAwakeDuringTasks") private var keepScreenAwakeDuringTasks: Bool = false
    @AppStorage("chat.autoFocusAfterReply") private var autoFocusAfterReply: Bool = true
    @AppStorage("chat.autoExpandThinking") private var autoExpandThinking: Bool = true

    // 图片
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var wallpaperScope: AppearanceScope = .global
    @State private var userAvatarItem: PhotosPickerItem?
    @State private var assistantAvatarItem: PhotosPickerItem?
    // [10-19 醒醒] 视觉小说模式的角色立绘
    @State private var characterArtItem: PhotosPickerItem?
    @State private var showCharacterArtPicker = false
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
    @State private var showSTImporter = false
    @State private var stWarnings: [String] = []
    @State private var showSTWarnings = false

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
                    case .behaviour: behaviourPage
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
        .navigationTitle(AppLocalized("外观"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(AppLocalized("出错了"), isPresented: $showError) {
            Button(AppLocalized("知道了"), role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .alert(AppLocalized("恢复默认装扮？"), isPresented: $showResetConfirm) {
            Button(AppLocalized("取消"), role: .cancel) {}
            Button(AppLocalized("恢复"), role: .destructive) { studio.resetThemePack() }
        } message: {
            Text(AppLocalized("颜色、气泡形状、贴图全部回到默认。壁纸和情头不动。"))
        }
        .fullScreenCover(isPresented: $showFullPreview) { fullPreviewSheet }
        .fileImporter(isPresented: $showSTImporter,
                      allowedContentTypes: [.json, .plainText, .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importSillyTavern(url) }
            case .failure(let error):
                fail(error.localizedDescription)
            }
        }
        .alert(AppLocalized("导入完成"), isPresented: $showSTWarnings) {
            Button(AppLocalized("知道了"), role: .cancel) {}
        } message: {
            Text(stWarnings.joined(separator: "\n"))
        }
        .onChange(of: appearanceMode) { _ in applyAppearanceMode() }
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

    /// 明暗覆盖。原来在外观页里，逻辑没动，只是搬过来。
    private func applyAppearanceMode() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.windows.forEach { window in
            window.overrideUserInterfaceStyle =
                appearanceMode == 1 ? .light : appearanceMode == 2 ? .dark : .unspecified
        }
    }

    // MARK: - 预览
    //
    // 用真组件：真头像（PersonAvatarView）、真壁纸（AppearanceBackdrop）、
    // 真气泡（MinisBubbleShape）。上一版是重画的一套简化 UI，所以换了头像
    // 和壁纸这里不动——现在跟着动。

    private var previewArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(AppLocalized("预览"))
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
                .frame(height: 372)
                .clipped()
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(studio.color(.canvas, variant: variant))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(studio.color(.border, variant: variant).opacity(0.28))
                .frame(height: 0.5)
        }
    }

    private var fullPreviewSheet: some View {
        ZStack {
            AppearanceBackdrop(scope: .global).ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text(AppLocalized("预览"))
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

                AppearanceLivePreview(variant: variant, aiName: aiName, scale: 1.45)
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
            contrastCard
            ForEach(AppearanceColorRoleGroup.allCases) { group in
                paletteGroupCard(group)
            }
            advancedCard
        }
    }

    private var shuffleCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalized("摇一套"))
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(studio.color(.primaryText, variant: variant))
                    Text(AppLocalized("先定一个主色，其余按莫兰迪规则推导。同一个档每次都不一样。"))
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
                        Text(AppLocalized("摇"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(studio.color(.accent, variant: variant))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(studio.color(.chip, variant: variant).opacity(studio.surfaceOpacity),
                                in: Capsule())
                    .overlay(
                        Capsule().stroke(studio.color(.border, variant: variant).opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

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
                                    Capsule().stroke(studio.color(.border, variant: variant).opacity(0.32), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .modifier(StudioCard(variant: variant))
    }

    private func roll(mood: AppearanceThemeShuffle.Mood? = nil) {
        let name = studio.shuffleTheme(mood: mood)
        withAnimation(.easeOut(duration: 0.18)) { shuffleName = name }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeIn(duration: 0.3)) { shuffleName = nil }
        }
    }

    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(AppLocalized("预设"))
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
        .modifier(StudioCard(variant: variant))
    }

    private func presetSwatchColors(_ preset: AppearancePreset) -> [String] {
        let map = variant == .light ? preset.colors.light : preset.colors.dark
        return [AppearanceColorRole.canvas, .surface, .accent, .primaryText].compactMap { map[$0] }
    }

    private func paletteGroupCard(_ group: AppearanceColorRoleGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                sectionTitle(group.title)
                Text(group.hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ForEach(Array(group.roles.enumerated()), id: \.element) { index, role in
                if index > 0 {
                    hairline
                }
                paletteRow(role)
            }
        }
        .modifier(StudioCard(variant: variant))
    }

    private var hairline: some View {
        Rectangle()
            .fill(studio.color(.border, variant: variant).opacity(0.22))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func paletteRow(_ role: AppearanceColorRole) -> some View {
        HStack(spacing: 13) {
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

    /// 对比度体检。摇骰子生成的一定过，但手动调完可能不过——
    /// 这里列出来让她自己判断，不硬改她的选择。
    private var contrastCard: some View {
        let colors = studio.allColors(variant: variant)
        let issues = AppearanceContrast.audit(colors)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: issues.isEmpty ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(issues.isEmpty
                                     ? studio.color(.success, variant: variant)
                                     : studio.color(.warning, variant: variant))
                sectionTitle(AppLocalized("对比度"))
                Spacer()
                if !issues.isEmpty {
                    Text("\(issues.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(studio.color(.warning, variant: variant), in: Capsule())
                }
            }
            if issues.isEmpty {
                Text(AppLocalized("文字和底都看得清。正文 4.5:1 以上，其余 3:1 以上。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            } else {
                ForEach(issues, id: \.self) { issue in
                    Text(issue)
                        .font(.system(size: 10.5))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .modifier(StudioCard(variant: variant))
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                    Text(AppLocalized("高级"))
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
                hairline
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocalized("给单独某一页换色。没单独调过的页跟随「全部页面」。"))
                        .font(.system(size: 11))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))

                    Picker(AppLocalized("改哪一页"), selection: $paletteScope) {
                        // 底部栏只能挂壁纸，不能调色，所以配色页不列它。
                        ForEach(AppearanceScope.allCases.filter { $0.supportsColour }) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(studio.color(.accent, variant: variant))

                    if paletteScope != .global {
                        let count = studio.overrideCount(scope: paletteScope, variant: variant)
                        HStack(spacing: 8) {
                            Text(count == 0
                                 ? AppLocalized("这一页还没有单独调过任何颜色。")
                                 : String(format: AppLocalized("这一页有 %d 项和全局不一样。"), count))
                                .font(.system(size: 11))
                                .foregroundStyle(studio.color(.secondaryText, variant: variant))
                            Spacer()
                            if count > 0 {
                                Button(AppLocalized("全部还原")) {
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

                    hairline.padding(.leading, 0).padding(.vertical, 4)

                    Button {
                        studio.resetColors()
                    } label: {
                        Text(AppLocalized("恢复默认色盘"))
                            .font(.system(size: 12))
                            .foregroundStyle(studio.color(.destructive, variant: variant))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .modifier(StudioCard(variant: variant))
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
                Text(AppLocalized("已单独调"))
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
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("气泡颜色"))
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
                sliderRow(AppLocalized("气泡透明度"), value: $studio.bubbleOpacity, range: 0.15...1)
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("形状"))
                Picker(AppLocalized("我的气泡"), selection: userStyleBinding) {
                    ForEach(AppearanceBubbleStyle.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Picker(String(format: AppLocalized("%@气泡"), aiName), selection: assistantStyleBinding) {
                    ForEach(AppearanceBubbleStyle.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Picker(AppLocalized("输入栏形状"), selection: inputBarStyleBinding) {
                    ForEach(AppearanceBubbleStyle.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Picker(AppLocalized("列表图标"), selection: listIconShapeBinding) {
                    ForEach(AppearanceListIconShape.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                sliderRow(AppLocalized("输入栏圆角"), value: inputBarRadiusBinding, range: 4...32, unit: "")
                Picker(AppLocalized("头像形状"), selection: avatarShapeBinding) {
                    ForEach(AppearanceAvatarShape.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Text(AppLocalized("头像形状同时作用于聊天、列表和情头预览。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
            .modifier(StudioCard(variant: variant))

            // 消息形态 + 行高 + 字距。这三个是 ST 主题包里能接住的部分。
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("消息形态"))
                Picker("", selection: chatDisplayBinding) {
                    ForEach(AppearanceChatDisplay.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(AppearanceChatDisplay.parse(studio.currentThemePack().chatDisplay).hint)
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))

                hairline.padding(.leading, 0).padding(.vertical, 4)

                sliderRow(AppLocalized("行高"), value: lineHeightBinding, range: 0.9...2.2, unit: "x")
                sliderRow(AppLocalized("字距"), value: letterSpacingBinding, range: -1...3, unit: "pt")
            }
            .modifier(StudioCard(variant: variant))

            // [10-19 醒醒] 视觉小说模式。立绘照 ST 的 waifuMode 做，
            // 对话框是 Galgame 那种。
            novelModeCard(variant: variant)

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("正文字体"))
                Picker(AppLocalized("正文字体"), selection: fontFamilyBinding) {
                    ForEach(AppearanceFontFamily.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Text(AppLocalized("字体只作用于聊天正文、输入框和 thinking 卡片。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
            .modifier(StudioCard(variant: variant))
        }
    }

    // MARK: - 背景

    private var backdropPage: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("壁纸"))
                Picker(AppLocalized("用于"), selection: $wallpaperScope) {
                    ForEach(AppearanceScope.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))

                ZStack(alignment: .bottomTrailing) {
                    AppearanceBackdrop(scope: wallpaperScope)
                    Text(studio.hasWallpaper(wallpaperScope)
                         ? AppLocalized("壁纸预览") : AppLocalized("纯色背景"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(studio.color(.primaryText, scope: wallpaperScope))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(studio.color(.raised, scope: wallpaperScope).opacity(0.85), in: Capsule())
                        .padding(10)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(studio.color(.border, scope: wallpaperScope).opacity(0.4), lineWidth: 0.5)
                )

                PhotosPicker(selection: $wallpaperItem, matching: .images) {
                    Label(studio.hasOwnWallpaper(wallpaperScope)
                          ? AppLocalized("换这张") : AppLocalized("选一张"),
                          systemImage: "photo")
                        .font(.system(size: 13))
                }

                if studio.hasOwnWallpaper(wallpaperScope) {
                    Button(AppLocalized("改用继承的背景")) { studio.removeWallpaper(wallpaperScope) }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }
                if studio.hasWallpaper(wallpaperScope) {
                    Button(AppLocalized("清除当前背景")) { studio.clearWallpaper(wallpaperScope) }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("透明度"))
                sliderRow(AppLocalized("壁纸压色"), value: $studio.wallpaperShade, range: 0...0.65)
                sliderRow(AppLocalized("卡片透明度"), value: $studio.surfaceOpacity, range: 0.35...1)
            }
            .modifier(StudioCard(variant: variant))
        }
    }

    // MARK: - 情头

    private var avatarsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(AppLocalized("情头"))
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
                    Text(AppLocalized("你"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
                Spacer()
            }
            .padding(.vertical, 8)

            PhotosPicker(selection: $userAvatarItem, matching: .images) {
                Label(AppLocalized("选我的头像"), systemImage: "person.crop.square").font(.system(size: 13))
            }
            if !studio.userAvatar.isEmpty {
                Button(AppLocalized("去掉我的头像")) { studio.removeUserAvatar() }
                    .font(.system(size: 12))
                    .foregroundStyle(studio.color(.destructive, variant: variant))
            }

            PhotosPicker(selection: $assistantAvatarItem, matching: .images) {
                Label(String(format: AppLocalized("选%@的头像"), aiName),
                      systemImage: "sparkles.rectangle.stack")
                    .font(.system(size: 13))
            }
            if !SoulStore.cachedMetadata.icon.isEmpty {
                Button(String(format: AppLocalized("去掉%@的头像"), aiName)) {
                    do { try studio.removeAssistantAvatar() }
                    catch { fail(error.localizedDescription) }
                }
                .font(.system(size: 12))
                .foregroundStyle(studio.color(.destructive, variant: variant))
            }

            Text(String(format: AppLocalized("两张都会裁成方的，存在这台手机上。%@的头像同时就是 Soul 图标。"), aiName))
                .font(.system(size: 10.5))
                .lineSpacing(1.5)
                .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.75))
        }
        .modifier(StudioCard(variant: variant))
    }

    // MARK: - 图标

    private var iconsPage: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("设置行图标"))
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
                            Text(studio.customIcon(for: slot.id) == nil
                                 ? AppLocalized("上传") : AppLocalized("更换"))
                                .font(.system(size: 12))
                                .foregroundStyle(studio.color(.accent, variant: variant))
                        }
                        if studio.customIcon(for: slot.id) != nil {
                            Button(AppLocalized("还原")) { studio.removeIcon(for: slot.id) }
                                .font(.system(size: 11))
                                .foregroundStyle(studio.color(.destructive, variant: variant))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("分类图标"))
                ForEach(AppearanceThemePack.categoryKeys, id: \.self) { key in
                    categoryRow(key)
                }
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("贴图"))
                PhotosPicker(selection: $thinkingCardItem, matching: .images) {
                    Label(studio.hasThinkingCardImage()
                          ? AppLocalized("换 thinking 卡片图") : AppLocalized("给 thinking 卡片贴图"),
                          systemImage: "photo.on.rectangle").font(.system(size: 13))
                }
                if studio.hasThinkingCardImage() {
                    sliderRow(AppLocalized("卡片图浓度"), value: thinkingCardOpacityBinding, range: 0.05...1)
                    Button(AppLocalized("去掉 thinking 卡片图")) { studio.removeThinkingCardImage() }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }

                PhotosPicker(selection: $inputBarItem, matching: .images) {
                    Label(studio.hasInputBarImage()
                          ? AppLocalized("换输入栏图") : AppLocalized("给输入栏贴图"),
                          systemImage: "photo.on.rectangle").font(.system(size: 13))
                }
                if studio.hasInputBarImage() {
                    sliderRow(AppLocalized("输入栏图浓度"), value: inputBarOpacityBinding, range: 0.05...1)
                    Button(AppLocalized("去掉输入栏图")) { studio.removeInputBarImage() }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("thinking 字号"))
                sliderRow(AppLocalized("标题字"), value: thinkingTitleSizeBinding, range: 10...22, unit: "")
                sliderRow(AppLocalized("正文字"), value: thinkingBodySizeBinding, range: 10...22, unit: "")
            }
            .modifier(StudioCard(variant: variant))
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
                    Text(studio.categoryImage(for: key) == nil
                         ? AppLocalized("贴图") : AppLocalized("换图"))
                        .font(.system(size: 11))
                        .foregroundStyle(studio.color(.accent, variant: variant))
                }
                if studio.categoryImage(for: key) != nil {
                    Button(AppLocalized("还原")) { studio.removeCategoryImage(for: key) }
                        .font(.system(size: 10))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }
            }
            HStack(spacing: 9) {
                TextField(AppLocalized("SF 名，空着就是默认"), text: categorySymbolBinding(key))
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
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("存这一套"))
                TextField(AppLocalized("给它起个名字"), text: $saveName)
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 13))
                Button {
                    _ = studio.saveCurrentTheme(name: saveName.isEmpty ? "未命名" : saveName)
                    saveName = ""
                } label: {
                    Text(AppLocalized("存进主题库"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(studio.color(.accent, variant: variant))
                }
                .buttonStyle(.plain)
                Text(AppLocalized("另存一份，不会冲掉正在用的。最多四十套。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.75))
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("主题库"))
                let saved = studio.savedThemes()
                if saved.isEmpty {
                    Text(AppLocalized("还没有存过的主题。"))
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
                            Button(AppLocalized("应用")) { _ = studio.applySavedTheme(id: item.id) }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(studio.color(.accent, variant: variant))
                            Button(AppLocalized("删")) { _ = studio.deleteSavedTheme(id: item.id) }
                                .font(.system(size: 11))
                                .foregroundStyle(studio.color(.destructive, variant: variant))
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("导出导入"))

                // [10-18 醒醒 第五轮] 吃 ST 小酒馆的主题包。
                //
                // 能吃的：39 个颜色字段、头像形状、消息形态、行高、字距、
                // 圆角（从 custom_css 抽众数）。
                // 吃不了的：CSS 里的伪元素、外链装饰图、按钮换图——那些是
                // 网页的能力，原生视图接不住。
                Button {
                    showSTImporter = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                        Text(AppLocalized("导入 ST 小酒馆主题包"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(studio.color(.accent, variant: variant))
                }
                .buttonStyle(.plain)
                Text(AppLocalized("选一个 ST 的主题 JSON。颜色、头像形状、消息形态、行高、字距会一起换掉。CSS 里的装饰图接不了。"))
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))

                hairline.padding(.leading, 0).padding(.vertical, 4)

                Button(AppLocalized("导出到剪贴板")) { exportPackToClipboard() }
                    .font(.system(size: 13))
                    .foregroundStyle(studio.color(.accent, variant: variant))
                Button(AppLocalized("从剪贴板贴上")) { importPackFromClipboard() }
                    .font(.system(size: 13))
                    .foregroundStyle(studio.color(.accent, variant: variant))
                Button(AppLocalized("恢复默认主题包")) { showResetConfirm = true }
                    .font(.system(size: 12))
                    .foregroundStyle(studio.color(.destructive, variant: variant))
                if studio.canUndoThemeReset {
                    Button(AppLocalized("撤销上一次恢复")) { _ = studio.undoThemeReset() }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
            }
            .modifier(StudioCard(variant: variant))
        }
    }

    // MARK: - 行为
    //
    // 这些原来在 `AppearanceSettingsView` 里。搬过来之后那一页只留一个入口。
    // 语言统一走 AppLocalized。

    private var behaviourPage: some View {
        VStack(spacing: 20) {
            // 明暗：原来在外观页有一份「跟随系统/浅色/深色」，跟这里的重复，删了那份。
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("明暗"))
                Picker("", selection: $appearanceMode) {
                    Text(AppLocalized("跟随系统")).tag(0)
                    Text(AppLocalized("浅色")).tag(1)
                    Text(AppLocalized("深色")).tag(2)
                }
                .pickerStyle(.segmented)
                Text(AppLocalized("覆盖系统外观。选「跟随系统」就跟着手机走。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("启动会话"))
                Picker("", selection: $launchScreen) {
                    Text(AppLocalized("自动")).tag(0)
                    Text(AppLocalized("上次会话")).tag(1)
                    Text(AppLocalized("新对话")).tag(2)
                    Text(AppLocalized("首页")).tag(3)
                }
                .pickerStyle(.menu)
                .tint(studio.color(.accent, variant: variant))
                Text(AppLocalized("打开 App 时显示什么。「自动」会在上次会话超过 15 分钟时开新对话。"))
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("字号"))
                FontScaleRow(label: AppLocalized("聊天输入"), level: $fontSettings.chatInputScale)
                FontScaleRow(label: AppLocalized("消息文本"), level: $fontSettings.messageBaseScale)
                FontScaleRow(label: AppLocalized("应用基础"), level: $fontSettings.appBaseScale)
                if fontSettings.isModified {
                    Button(AppLocalized("恢复默认字号")) { fontSettings.resetToDefaults() }
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.destructive, variant: variant))
                }
                Text(AppLocalized("分别缩放聊天输入框、消息正文、以及其余界面文字。改完立刻生效。"))
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("输入"))
                Picker(AppLocalized("回车键"), selection: $returnKeyBehavior) {
                    Text(AppLocalized("换行")).tag(0)
                    Text(AppLocalized("发送")).tag(1)
                }
                .pickerStyle(.segmented)
                Text(AppLocalized("回车是换行还是发送。硬件键盘的 Shift+回车 永远是换行。"))
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))

                hairline.padding(.leading, 0).padding(.vertical, 4)

                Toggle(AppLocalized("回复后自动聚焦输入框"), isOn: $autoFocusAfterReply)
                    .tint(studio.color(.accent, variant: variant))
                Text(AppLocalized("模型回复完自动弹出键盘，方便接着问。不想被键盘打断就关掉。"))
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("聊天行为"))
                Toggle(AppLocalized("流式输出时展开思考"), isOn: $autoExpandThinking)
                    .tint(studio.color(.accent, variant: variant))
                Text(AppLocalized("开着时，模型推理中的思考块自动展开，完成后收起。关掉就保持折叠，点一下才看。"))
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))

                hairline.padding(.leading, 0).padding(.vertical, 4)

                Toggle(AppLocalized("自动分组"), isOn: autoGroupingBinding)
                    .tint(studio.color(.accent, variant: variant))
                Text(AppLocalized("首次生成会话标题时，顺便归进匹配的分组。每个会话只做一次，只用你已经建好的分组。"))
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))

                hairline.padding(.leading, 0).padding(.vertical, 4)

                Toggle(AppLocalized("屏幕常亮"), isOn: $keepScreenAwakeDuringTasks)
                    .tint(studio.color(.accent, variant: variant))
                Text(AppLocalized("有会话在跑任务时不熄屏。会更费电。"))
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("选项背景"))
                HStack(spacing: 13) {
                    ColorPicker("", selection: rowBackgroundBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(studio.currentThemePack().rowBackgroundHex == nil
                             ? AppLocalized("跟随卡片色") : AppLocalized("自定义"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(studio.color(.primaryText, variant: variant))
                        Text(AppLocalized("设置页每一行的底色。不选就跟卡片走。"))
                            .font(.system(size: 10))
                            .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.75))
                    }
                    Spacer()
                    if studio.currentThemePack().rowBackgroundHex != nil {
                        Button(AppLocalized("还原")) { studio.setRowBackground(nil) }
                            .font(.system(size: 11))
                            .foregroundStyle(studio.color(.destructive, variant: variant))
                    }
                }
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("App 图标"))
                if UIApplication.shared.supportsAlternateIcons {
                    ForEach(studioIconOptions) { option in
                        Button {
                            guard appIconMode != option.id else { return }
                            appIconMode = option.id
                            UIApplication.shared.setAlternateIconName(option.iconName) { _ in }
                        } label: {
                            HStack(spacing: 14) {
                                if let img = UIImage(named: option.imageName) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(studio.color(.border, variant: variant).opacity(0.4),
                                                        lineWidth: 0.5)
                                        )
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(option.title))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(studio.color(.primaryText, variant: variant))
                                    Text(LocalizedStringKey(option.subtitle))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                                }
                                Spacer()
                                if appIconMode == option.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(studio.color(.accent, variant: variant))
                                        .font(.system(size: 16))
                                }
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text(AppLocalized("这台设备不支持换图标。"))
                        .font(.system(size: 11))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
            }
            .modifier(StudioCard(variant: variant))

            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(AppLocalized("语言"))
                ForEach(studioLanguages) { lang in
                    Button {
                        // 写 reopen 标记再翻语言——根视图会因 .id(appLanguage)
                        // 整个重建，不记下来就会掉回设置首页。
                        UserDefaults.standard.set("appearance", forKey: "pendingSettingsReopen")
                        ViewModelCache.shared.suspendAllForTreeRemount()
                        appLanguage = lang.id
                        Bundle.setLanguage(lang.id.isEmpty ? nil : lang.id)
                    } label: {
                        HStack(spacing: 12) {
                            if !lang.flag.isEmpty {
                                Text(lang.flag).font(.system(size: 17))
                            } else {
                                Image(systemName: "globe")
                                    .font(.system(size: 14))
                                    .foregroundStyle(studio.color(.secondaryText, variant: variant))
                                    .frame(width: 26)
                            }
                            Text(lang.name)
                                .font(.system(size: 13))
                                .foregroundStyle(studio.color(.primaryText, variant: variant))
                            Spacer()
                            if appLanguage == lang.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(studio.color(.accent, variant: variant))
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .modifier(StudioCard(variant: variant))
        }
    }

    private var autoGroupingBinding: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.bool(forKey: "autoGroupingEnabled") },
            set: { UserDefaults.standard.set($0, forKey: "autoGroupingEnabled") }
        )
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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(studio.color(.primaryText, variant: variant))
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
    private var avatarShapeBinding: Binding<AppearanceAvatarShape> {
        Binding(get: { AppearanceAvatarShape.parse(studio.currentThemePack().avatarShape) },
                set: { studio.setAvatarShape($0) })
    }
    private var chatDisplayBinding: Binding<AppearanceChatDisplay> {
        Binding(get: { AppearanceChatDisplay.parse(studio.currentThemePack().chatDisplay) },
                set: { studio.setChatDisplay($0) })
    }
    private var lineHeightBinding: Binding<Double> {
        Binding(get: { studio.currentThemePack().lineHeight },
                set: { studio.setLineHeight($0) })
    }
    private var letterSpacingBinding: Binding<Double> {
        Binding(get: { studio.currentThemePack().letterSpacing },
                set: { studio.setLetterSpacing($0) })
    }

    // MARK: [10-19 醒醒] 视觉小说模式

    private var novelModeBinding: Binding<AppearanceNovelMode> {
        Binding(get: { AppearanceNovelMode.parse(studio.currentThemePack().novelMode) },
                set: { studio.setNovelMode($0) })
    }

    /// 视觉小说模式卡。
    ///
    /// 立绘是照 ST 的 `waifuMode` 做的：全屏角色图 + 聊天窗压底部。
    /// 对话框是 Galgame 那种：底部半透明框，一次一句，点一下往下推。
    @ViewBuilder
    private func novelModeCard(variant: AppearanceVariant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(AppLocalized("视觉小说"))
            Picker("", selection: novelModeBinding) {
                ForEach(AppearanceNovelMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(AppearanceNovelMode.parse(studio.currentThemePack().novelMode).hint)
                .font(.system(size: 10.5))
                .lineSpacing(1.5)
                .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))

            // 只有立绘和对话框模式才用得上角色图
            if novelModeBinding.wrappedValue != .off {
                hairline.padding(.leading, 0).padding(.vertical, 2)

                HStack(spacing: 12) {
                    if let b64 = studio.currentThemePack().characterArtBase64,
                       let data = Data(base64Encoded: b64),
                       let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(studio.color(.mutedSurface, variant: variant))
                            .frame(width: 52, height: 72)
                            .overlay {
                                Image(systemName: "person.crop.rectangle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.6))
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("角色立绘")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(studio.color(.primaryText, variant: variant))
                        Text("竖图最好，底部对齐铺满。不传就用头像放大。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
                    }

                    Spacer()

                    Button {
                        showCharacterArtPicker = true
                    } label: {
                        Text(studio.currentThemePack().characterArtBase64 == nil ? "选择" : "更换")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }

                if studio.currentThemePack().characterArtBase64 != nil {
                    Button(role: .destructive) {
                        studio.setCharacterArt(nil)
                    } label: {
                        Text("移除立绘")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .modifier(StudioCard(variant: variant))
        .photosPicker(isPresented: $showCharacterArtPicker,
                      selection: $characterArtItem,
                      matching: .images)
        .onChange(of: characterArtItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let jpeg = img.jpegData(compressionQuality: 0.82) {
                    await MainActor.run {
                        studio.setCharacterArt(jpeg.base64EncodedString())
                        characterArtItem = nil
                    }
                }
            }
        }
    }
    private var rowBackgroundBinding: Binding<Color> {
        Binding(
            get: {
                let hex = studio.currentThemePack().rowBackgroundHex
                return hex.map { Color(hex: $0) } ?? studio.color(.surface, scope: .settings)
            },
            set: { studio.setRowBackground($0.hexString) }
        )
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
            fail(AppLocalized("主题包写不出来。"))
            return
        }
        UIPasteboard.general.string = text
    }

    private func importPackFromClipboard() {
        guard let text = UIPasteboard.general.string,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail(AppLocalized("剪贴板里没有能用的主题包。"))
            return
        }
        do {
            let pack = try AppearanceThemePack.decode(obj, merging: studio.currentThemePack())
            studio.applyThemePack(pack)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// 吃 ST 小酒馆的主题包。
    ///
    /// 流程：读文件 → 解析 39 字段 + 从 custom_css 抽几何 → 应用 → 报告
    /// 哪些东西没接住。**不静默吞警告**——她得知道装饰图没进来。
    private func importSillyTavern(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            fail(AppLocalized("这个文件读不出来。"))
            return
        }
        do {
            let imported = try SillyTavernTheme.parse(data)
            studio.applySillyTavern(imported)

            var notes: [String] = [String(format: AppLocalized("已应用「%@」。"), imported.name)]
            if !imported.warnings.isEmpty {
                notes.append(contentsOf: imported.warnings)
            }
            notes.append(AppLocalized("CSS 里的装饰图、伪元素、按钮换图原生接不了，这些没有导入。"))
            stWarnings = notes
            showSTWarnings = true
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
            fail(AppLocalized("选中的图读不出来。"))
            return
        }
        apply(image)
    }
}

// MARK: - 底部导航项

enum AppearanceStudioPage: String, CaseIterable, Identifiable {
    case palette, bubbles, backdrop, avatars, icons, library, behaviour
    var id: String { rawValue }
    var title: String {
        switch self {
        case .palette: return AppLocalized("配色")
        case .bubbles: return AppLocalized("气泡")
        case .backdrop: return AppLocalized("背景")
        case .avatars: return AppLocalized("情头")
        case .icons: return AppLocalized("图标")
        case .library: return AppLocalized("主题库")
        case .behaviour: return AppLocalized("行为")
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
        case .behaviour: return "switch.2"
        }
    }
}

// MARK: - 卡片样式
//
// 统一一处：18pt 圆角 + surface 底 + 0.5pt 发丝线 + 软阴影。
// 上一版这四行在 12 个地方重复。

private struct StudioCard: ViewModifier {
    let variant: AppearanceVariant
    @ObservedObject private var studio = AppearanceStudio.shared

    func body(content: Content) -> some View {
        content
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
}

// MARK: - 字号滑杆

private struct FontScaleRow: View {
    let label: String
    @Binding var level: FontScaleLevel

    private static let cases = FontScaleLevel.allCases

    private var currentIndex: Int {
        Self.cases.firstIndex(of: level) ?? 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(MinisTheme.primaryText)
            HStack(spacing: 12) {
                Button {
                    let idx = currentIndex - 1
                    if idx >= 0 { level = Self.cases[idx] }
                } label: {
                    Text("A")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MinisTheme.secondaryText)
                }
                .buttonStyle(.plain)

                SteppedSlider(value: currentIndex, steps: Self.cases.count) { newIndex in
                    if newIndex >= 0, newIndex < Self.cases.count {
                        level = Self.cases[newIndex]
                    }
                }

                Button {
                    let idx = currentIndex + 1
                    if idx < Self.cases.count { level = Self.cases[idx] }
                } label: {
                    Text("A")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(MinisTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - App 图标 / 语言选项
//
// 这两组原来在 ContentView.swift 里，是 private 的，跟这里同名不冲突。

/// 分档滑杆。`ContentView.swift` 里那个是 private，这里用不了，重写一份。
/// 逻辑一样：拖动按档位吸附，刻度点跟着填色。
private struct SteppedSlider: View {
    let value: Int
    let steps: Int
    let onChanged: (Int) -> Void

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 22
    private let tickSize: CGFloat = 6

    @State private var dragValue: Int?

    private var displayValue: Int { dragValue ?? value }

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let midY = geo.size.height / 2
            let maxStep = CGFloat(max(1, steps - 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppearanceStudio.shared.color(.mutedSurface, scope: .settings))
                    .frame(height: trackHeight)
                    .position(x: totalW / 2, y: midY)

                let fillW = totalW * CGFloat(displayValue) / maxStep
                Capsule()
                    .fill(MinisTheme.accent)
                    .frame(width: fillW, height: trackHeight)
                    .position(x: fillW / 2, y: midY)

                ForEach(0..<steps, id: \.self) { i in
                    let x = totalW * CGFloat(i) / maxStep
                    Circle()
                        .fill(i <= displayValue
                              ? MinisTheme.accent
                              : AppearanceStudio.shared.color(.mutedSurface, scope: .settings))
                        .frame(width: tickSize, height: tickSize)
                        .position(x: x, y: midY)
                }

                let thumbX = totalW * CGFloat(displayValue) / maxStep
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: thumbX, y: midY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let step = stepFromX(drag.location.x, width: totalW)
                        if step != dragValue { dragValue = step }
                    }
                    .onEnded { drag in
                        let step = stepFromX(drag.location.x, width: totalW)
                        dragValue = nil
                        onChanged(step)
                    }
            )
        }
        .frame(height: thumbSize + 8)
    }

    private func stepFromX(_ x: CGFloat, width: CGFloat) -> Int {
        guard width > 0, steps > 1 else { return 0 }
        let fraction = x / width
        let clamped = min(max(fraction, 0), 1)
        return Int((clamped * CGFloat(steps - 1)).rounded())
    }
}

private struct StudioIconOption: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let iconName: String?
    let imageName: String
}

private let studioIconOptions: [StudioIconOption] = [
    StudioIconOption(id: 0, title: "自动", subtitle: "跟随系统",
                     iconName: nil, imageName: "AlternateIcons/AppIcon-Light"),
    StudioIconOption(id: 1, title: "浅色", subtitle: "始终浅色",
                     iconName: "AppIcon-Light", imageName: "AlternateIcons/AppIcon-Light"),
    StudioIconOption(id: 2, title: "深色", subtitle: "始终深色",
                     iconName: "AppIcon-Dark", imageName: "AlternateIcons/AppIcon-Dark"),
    StudioIconOption(id: 3, title: "浅色（旧）", subtitle: "经典浅色图标",
                     iconName: "AppIcon-LegacyLight", imageName: "AlternateIcons/AppIcon-LegacyLight"),
    StudioIconOption(id: 4, title: "深色（旧）", subtitle: "经典深色图标",
                     iconName: "AppIcon-LegacyDark", imageName: "AlternateIcons/AppIcon-LegacyDark"),
]

private struct StudioLanguageOption: Identifiable {
    let id: String
    let name: String
    let flag: String
}

private let studioLanguages: [StudioLanguageOption] = [
    StudioLanguageOption(id: "",        name: "跟随系统",  flag: ""),
    StudioLanguageOption(id: "en",      name: "English",  flag: "🇺🇸"),
    StudioLanguageOption(id: "zh-Hans", name: "简体中文",  flag: "🇨🇳"),
    StudioLanguageOption(id: "zh-Hant", name: "繁體中文",  flag: "🇭🇰"),
    StudioLanguageOption(id: "ja",      name: "日本語",    flag: "🇯🇵"),
    StudioLanguageOption(id: "ko",      name: "한국어",    flag: "🇰🇷"),
    StudioLanguageOption(id: "es",      name: "Español",  flag: "🇪🇸"),
    StudioLanguageOption(id: "fr",      name: "Français", flag: "🇫🇷"),
    StudioLanguageOption(id: "de",      name: "Deutsch",  flag: "🇩🇪"),
    StudioLanguageOption(id: "ru",      name: "Русский",  flag: "🇷🇺"),
]

// MARK: - 真组件预览
//
// 全部用真组件：PersonAvatarView 真头像、AppearanceBackdrop 真壁纸、
// MinisBubbleShape 真气泡、真输入框圆角、真状态色。

private struct AppearanceLivePreview: View {
    let variant: AppearanceVariant
    let aiName: String
    var scale: CGFloat = 1.0

    @ObservedObject private var studio = AppearanceStudio.shared

    private var pack: AppearanceThemePack { studio.currentThemePack() }
    private var base: CGFloat { 12 * scale }

    var body: some View {
        ZStack {
            // 真壁纸。换了壁纸这里立刻变。
            AppearanceBackdrop(scope: .chat)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 10 * scale) {
                // AI 气泡 —— 真头像
                HStack(alignment: .top, spacing: 7 * scale) {
                    PersonAvatarView(kind: .assistant, size: 24 * scale)
                    Text(AppLocalized("今天想聊点什么？"))
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

                // 我的气泡 —— 真头像
                HStack(alignment: .top, spacing: 7 * scale) {
                    Spacer(minLength: 0)
                    Text(AppLocalized("把界面做得漂亮一点~"))
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
                    PersonAvatarView(kind: .user, size: 24 * scale)
                }

                // 消息操作栏那排图标底
                HStack(spacing: 7 * scale) {
                    ForEach(["speaker.wave.2.fill", "arrow.clockwise",
                             "doc.on.doc.fill", "trash.fill"], id: \.self) { symbol in
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
                        Text(AppLocalized("发消息…"))
                            .font(.system(size: base))
                            .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.7))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10 * scale)
                    .frame(height: 30 * scale)
                    .background(
                        studio.color(.field, variant: variant).opacity(studio.surfaceOpacity),
                        in: RoundedRectangle(cornerRadius: min(pack.inputBarRadius, 15 * scale),
                                             style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: min(pack.inputBarRadius, 15 * scale),
                                         style: .continuous)
                            .stroke(studio.color(.border, variant: variant).opacity(0.45), lineWidth: 0.5)
                    )

                    Image(systemName: "arrow.up")
                        .font(.system(size: 11 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30 * scale, height: 30 * scale)
                        .background(
                            studio.color(.accent, variant: variant),
                            in: RoundedRectangle(cornerRadius: min(pack.inputBarRadius, 15 * scale),
                                                 style: .continuous)
                        )
                }

                // 状态三色
                HStack(spacing: 6 * scale) {
                    chipSwatch(.success, AppLocalized("成功"))
                    chipSwatch(.warning, AppLocalized("警告"))
                    chipSwatch(.destructive, AppLocalized("危险"))
                    Spacer(minLength: 0)
                }
            }
            .padding(13 * scale)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.45), lineWidth: 0.5)
        )
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
