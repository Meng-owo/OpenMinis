import PhotosUI
import SwiftUI
import UIKit

// MARK: - 装扮
//
// [10-18 醒醒] 「我建议你重新帮我设计创作装扮页，功能留着，布局，选项，
// 实时显示的那一块。什么都得重写」
//
// ## 这一版为什么长这样
//
// 上一版的毛病不是分组名字没起好，是三件事：
//
// 1. **十六个角色平铺**。里面三个是半死或全死的（工具卡零消费、搜索栏 1 处、
//    输入框 2 处），还有一个"按钮与选中"组里只有一个 accent——分组比内容还多。
// 2. **「作用于」是混乱的根源**。每个角色 × 8 页 × 浅深两套 = 理论 240 个色值。
//    她选"聊天"再调色，只有聊天变，然后奇怪"为什么别处没变"。
// 3. **预览是假的**。手写小样，不反映气泡形状/字体/图标底；固定读全局色，
//    不跟「作用于」联动。
//
// ## 这一版怎么解
//
// - 顶部**真组件**预览（不是手写小样），改什么都真实反映。
// - 六个分组按"你看到的东西"分：文字 / 背景与卡片 / 控件 / 强调 / 聊天 / 状态。
// - 「作用于」收进「高级」，默认只有全局。
// - 摇骰子：按一套配色骨架随机，不是随机十六个色。
// - 拆两级：主界面日常用，高级放页级覆盖和原始角色表。

struct AppearanceStudioView: View {
    @ObservedObject private var studio = AppearanceStudio.shared
    @Environment(\.colorScheme) private var colorScheme

    // 编辑态
    @State private var variant: AppearanceVariant = .light
    @State private var page: AppearanceStudioPage = .palette

    // 图片选择
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
    @State private var showResetConfirm = false
    @State private var shuffleSeedNote: String?
    @State private var previewZoom: Bool = false

    @MainActor private var aiName: String {
        let n = SoulStore.cachedMetadata.name
        return n.isEmpty ? "AI" : n
    }

    var body: some View {
        VStack(spacing: 0) {
            previewArea

            Divider()
                .overlay(studio.color(.border, variant: variant).opacity(0.3))

            ScrollView {
                LazyVStack(spacing: 18) {
                    switch page {
                    case .palette:   palettePage
                    case .bubbles:   bubblesPage
                    case .backdrop:  backdropPage
                    case .avatars:   avatarsPage
                    case .icons:     iconsPage
                    case .library:   libraryPage
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
        .appearancePage(.settings)
        .navigationTitle("装扮")
        .navigationBarTitleDisplayMode(.inline)
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
                    catch { errorText = error.localizedDescription }
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
        .alert("恢复默认装扮？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) { studio.resetThemePack() }
        } message: {
            Text("颜色、气泡形状、贴图全部回到默认。壁纸和情头不动。")
        }
    }

    // MARK: - 顶部真组件预览
    //
    // 不再手写小样。这里摆的就是真聊天气泡的形状参数、真的图标底角色、
    // 真的输入框——她改什么，这块立刻变，因为它读的是同一套变量。

    private var previewArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("预览")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant))
                Spacer()
                if let note = shuffleSeedNote {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.7))
                        .transition(.opacity)
                }
                Picker("", selection: $variant) {
                    ForEach(AppearanceVariant.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            AppearanceLivePreview(variant: variant, aiName: aiName)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .background(studio.color(.canvas, variant: variant))
    }

    // MARK: - 色盘页

    private var palettePage: some View {
        VStack(spacing: 18) {
            shuffleCard

            ForEach(AppearanceColorRoleGroup.allCases) { group in
                paletteGroupCard(group)
            }

            advancedCard
        }
    }

    /// 摇骰子。放在最上面，因为它是最快的起点——
    /// 摇到喜欢的再微调，比从十六个色一个个挑快得多。
    private var shuffleCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("摇一套")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(studio.color(.primaryText, variant: variant))
                    Text("先定一个主色，其余自动配好。摇到喜欢再微调。")
                        .font(.system(size: 11))
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        studio.color(.chip, variant: variant),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            // 摇出来的色带：一眼看出这套是什么调子
            HStack(spacing: 0) {
                ForEach([AppearanceColorRole.canvas, .surface, .iconTile,
                         .userBubble, .accent, .primaryText], id: \.self) { role in
                    Rectangle()
                        .fill(studio.color(role, variant: variant))
                        .frame(height: 26)
                        .overlay(
                            Rectangle()
                                .stroke(studio.color(.border, variant: variant).opacity(0.25), lineWidth: 0.5)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(studio.color(.border, variant: variant).opacity(0.4), lineWidth: 0.5)
            )
        }
        .padding(14)
        .background(studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.4), lineWidth: 0.6)
        )
    }

    private func roll() {
        let name = studio.shuffleTheme()
        withAnimation(.easeOut(duration: 0.2)) { shuffleSeedNote = "「\(name)」" }
        // 提示两秒后淡掉，不要一直占着位置
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeIn(duration: 0.3)) { shuffleSeedNote = nil }
        }
    }

    private func paletteGroupCard(_ group: AppearanceColorRoleGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                Text(group.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(Array(group.roles.enumerated()), id: \.element) { index, role in
                if index > 0 {
                    Rectangle()
                        .fill(studio.color(.border, variant: variant).opacity(0.3))
                        .frame(height: 0.5)
                        .padding(.leading, 14)
                }
                paletteRow(role)
            }
        }
        .background(studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.4), lineWidth: 0.6)
        )
    }

    private func paletteRow(_ role: AppearanceColorRole) -> some View {
        HStack(spacing: 12) {
            // 色块。点它开系统取色器——比一行文字 + 一个色轮好点。
            ColorPicker("", selection: studio.colorBinding(role, scope: .global, variant: variant),
                        supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(role.title)
                    .font(.system(size: 13))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                Text(role.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text("#\(studio.hex(role, scope: .global, variant: variant))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.6))

            if studio.hasOverride(role, scope: .global, variant: variant) {
                Button {
                    studio.clearOverride(role, scope: .global, variant: variant)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    /// 高级：页级覆盖。默认折叠，因为它是"为什么别处没变"的最大来源。
    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                    Text("高级")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(studio.color(.secondaryText, variant: variant))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                Rectangle()
                    .fill(studio.color(.border, variant: variant).opacity(0.3))
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: 10) {
                    Text("给单独某一页换色。没单独调过的页跟随「全部页面」。")
                        .font(.system(size: 11))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))

                    Picker("改哪一页", selection: $paletteScope) {
                        ForEach(AppearanceScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(studio.color(.accent, variant: variant))

                    if paletteScope != .global {
                        let count = studio.overrideCount(scope: paletteScope, variant: variant)
                        HStack(spacing: 6) {
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
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(studio.color(.secondaryText, variant: variant))
                                    .padding(.top, 6)
                                    .padding(.bottom, 2)
                                ForEach(group.roles, id: \.self) { role in
                                    scopedRow(role)
                                }
                            }
                        }
                    }

                    Divider().opacity(0.3)

                    Button {
                        studio.resetColors()
                    } label: {
                        Text("恢复默认色盘")
                            .font(.system(size: 12))
                            .foregroundStyle(studio.color(.destructive, variant: variant))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
        }
        .background(studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.4), lineWidth: 0.6)
        )
    }

    private func scopedRow(_ role: AppearanceColorRole) -> some View {
        let overridden = studio.hasOverride(role, scope: paletteScope, variant: variant)
        return HStack(spacing: 10) {
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
                    .font(.system(size: 10))
                    .foregroundStyle(studio.color(.accent, variant: variant))
                Button {
                    studio.clearOverride(role, scope: paletteScope, variant: variant)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
                .buttonStyle(.plain)
            } else {
                Text("#\(studio.hex(role, scope: .global, variant: variant))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.5))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 气泡页

    private var bubblesPage: some View {
        VStack(spacing: 18) {
            card("气泡颜色") {
                ForEach([AppearanceColorRole.userBubble, .assistantBubble], id: \.self) { role in
                    HStack(spacing: 12) {
                        ColorPicker("", selection: studio.colorBinding(role, scope: .global, variant: variant),
                                    supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 30, height: 30)
                        Text(role.title)
                            .font(.system(size: 13))
                            .foregroundStyle(studio.color(.primaryText, variant: variant))
                        Spacer()
                        Text("#\(studio.hex(role, scope: .global, variant: variant))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.6))
                    }
                    .padding(.vertical, 5)
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
                sliderRow("输入栏圆角", value: inputBarRadiusBinding, range: 4...32, unit: "")
            }

            card("正文") {
                Picker("正文字体", selection: fontFamilyBinding) {
                    ForEach(AppearanceFontFamily.allCases) { Text($0.title).tag($0) }
                }
                .tint(studio.color(.accent, variant: variant))
                Text("字体只作用于聊天正文、输入框和 thinking 卡片。")
                    .font(.system(size: 10))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }
        }
    }

    // MARK: - 背景页

    private var backdropPage: some View {
        VStack(spacing: 18) {
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(studio.color(.raised, scope: wallpaperScope).opacity(0.85),
                                    in: Capsule())
                        .padding(8)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(studio.color(.border, scope: wallpaperScope), lineWidth: 0.6)
                )

                PhotosPicker(selection: $wallpaperItem, matching: .images) {
                    Label(studio.hasOwnWallpaper(wallpaperScope) ? "换这张" : "选一张",
                          systemImage: "photo.fill")
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

    // MARK: - 情头页

    private var avatarsPage: some View {
        card("情头") {
            HStack(spacing: 12) {
                Spacer()
                VStack(spacing: 6) {
                    PersonAvatarView(kind: .assistant, size: 56)
                    Text(aiName).font(.system(size: 11))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(studio.color(.accent, variant: variant))
                VStack(spacing: 6) {
                    PersonAvatarView(kind: .user, size: 56)
                    Text("你").font(.system(size: 11))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                }
                Spacer()
            }
            .padding(.vertical, 6)

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
                    catch { errorText = error.localizedDescription }
                }
                .font(.system(size: 12))
                .foregroundStyle(studio.color(.destructive, variant: variant))
            }

            Text("两张都会裁成方的，存在这台手机上。\(aiName)的头像同时就是 Soul 图标。")
                .font(.system(size: 10))
                .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
        }
    }

    // MARK: - 图标页

    private var iconsPage: some View {
        VStack(spacing: 18) {
            card("设置行图标") {
                ForEach(QuietIconSlot.allCases) { slot in
                    HStack(spacing: 12) {
                        QuietAppIcon(id: slot.id, systemName: slot.systemName, size: 26)
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
                        }
                        if studio.customIcon(for: slot.id) != nil {
                            Button("还原") { studio.removeIcon(for: slot.id) }
                                .font(.system(size: 11))
                                .foregroundStyle(studio.color(.destructive, variant: variant))
                        }
                    }
                    .padding(.vertical, 3)
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
        }
    }

    private func categoryRow(_ key: String) -> some View {
        let themedSymbol = MinisThemeList.categoryIcon(for: key).systemName
        return HStack(spacing: 10) {
            // 白底黑实心——和全 App 图标同一个规范
            Image(systemName: QuietAppIcon.filledSymbolName(themedSymbol))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(width: 22, height: 22)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(key)
                .font(.system(size: 12))
                .foregroundStyle(studio.color(.primaryText, variant: variant))
            Spacer()
            PhotosPicker(selection: Binding(
                get: { categoryImageKey == key ? categoryImageItem : nil },
                set: { categoryImageKey = key; categoryImageItem = $0 }
            ), matching: .images) {
                Text(studio.categoryImage(for: key) == nil ? "贴图" : "换图")
                    .font(.system(size: 11))
            }
            if studio.categoryImage(for: key) != nil {
                Button("还原") { studio.removeCategoryImage(for: key) }
                    .font(.system(size: 10))
                    .foregroundStyle(studio.color(.destructive, variant: variant))
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - 主题库页

    private var libraryPage: some View {
        VStack(spacing: 18) {
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
                    .font(.system(size: 10))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.8))
            }

            card("主题库") {
                let saved = studio.savedThemes()
                if saved.isEmpty {
                    Text("还没有存过的主题。")
                        .font(.system(size: 12))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                } else {
                    ForEach(saved) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                                Text(item.userStyleTitle + " · " + item.assistantStyleTitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(studio.color(.secondaryText, variant: variant))
                            }
                            Spacer()
                            Button("应用") { _ = studio.applySavedTheme(id: item.id) }
                                .font(.system(size: 12))
                                .foregroundStyle(studio.color(.accent, variant: variant))
                            Button("删") { _ = studio.deleteSavedTheme(id: item.id) }
                                .font(.system(size: 11))
                                .foregroundStyle(studio.color(.destructive, variant: variant))
                        }
                        .padding(.vertical, 4)
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
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: page == item ? .semibold : .regular))
                        Text(item.title)
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(page == item
                                     ? studio.color(.accent, variant: variant)
                                     : studio.color(.secondaryText, variant: variant).opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 2)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(studio.color(.border, variant: variant).opacity(0.35))
                .frame(height: 0.5)
        }
    }

    // MARK: - 小零件

    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(studio.color(.primaryText, variant: variant))
            content()
        }
        .padding(14)
        .background(studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.4), lineWidth: 0.6)
        )
    }

    private func sliderRow(_ title: String, value: Binding<Double>,
                           range: ClosedRange<Double>, unit: String = "%") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                Spacer()
                Text(unit == "%" ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant))
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

    // MARK: - 导入导出

    private func exportPackToClipboard() {
        let pack = studio.exportThemePack(includeWallpaper: true)
        guard let data = try? JSONSerialization.data(withJSONObject: pack.asJSONObject(),
                                                    options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            errorText = "主题包写不出来。"
            return
        }
        UIPasteboard.general.string = text
    }

    private func importPackFromClipboard() {
        guard let text = UIPasteboard.general.string,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorText = "剪贴板里没有能用的主题包。"
            return
        }
        do {
            let pack = try AppearanceThemePack.decode(obj, merging: studio.currentThemePack())
            studio.applyThemePack(pack)
        } catch {
            errorText = error.localizedDescription
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
            errorText = "选中的图读不出来。"
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
// 用真的形状参数（MinisThemeShape）、真的角色、真的图标底，
// 缩到小尺寸摆一屏。她改什么这里立刻变，因为它读的是同一套变量。

private struct AppearanceLivePreview: View {
    let variant: AppearanceVariant
    let aiName: String

    @ObservedObject private var studio = AppearanceStudio.shared

    private var pack: AppearanceThemePack { studio.currentThemePack() }

    var body: some View {
        VStack(spacing: 7) {
            // AI 气泡（真形状）
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(studio.color(.accent, variant: variant))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text(String(aiName.prefix(1)))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                Text("今天想聊点什么？")
                    .font(.system(size: 11.5))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        studio.color(.assistantBubble, variant: variant)
                            .opacity(studio.bubbleOpacity),
                        in: MinisBubbleShape(style: pack.assistantStyle,
                                             radius: min(pack.assistantBubbleRadius, 14),
                                             tailOnTrailing: false)
                    )
                    .overlay(
                        MinisBubbleShape(style: pack.assistantStyle,
                                         radius: min(pack.assistantBubbleRadius, 14),
                                         tailOnTrailing: false)
                            .stroke(studio.color(.border, variant: variant).opacity(0.3), lineWidth: 0.5)
                    )
                Spacer(minLength: 0)
            }

            // 我的气泡（真形状，靠右）
            HStack(alignment: .top, spacing: 6) {
                Spacer(minLength: 0)
                Text("把界面做得漂亮一点~")
                    .font(.system(size: 11.5))
                    .foregroundStyle(studio.color(.primaryText, variant: variant))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        studio.color(.userBubble, variant: variant)
                            .opacity(studio.bubbleOpacity),
                        in: MinisBubbleShape(style: pack.userStyle,
                                             radius: min(pack.userBubbleRadius, 14),
                                             tailOnTrailing: true)
                    )
                Circle()
                    .fill(studio.color(.secondaryText, variant: variant).opacity(0.22))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text("你")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(studio.color(.primaryText, variant: variant))
                    )
            }

            // 消息操作栏那排图标底（就是她说"不该跟着卡片变"的东西）
            HStack(spacing: 6) {
                ForEach(["speaker.wave.2.fill", "arrow.clockwise", "doc.on.doc.fill", "trash.fill"],
                        id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(studio.color(.primaryText, variant: variant))
                        .frame(width: 20, height: 20)
                        .background(
                            studio.color(.iconTile, variant: variant).opacity(studio.surfaceOpacity),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(studio.color(.border, variant: variant).opacity(0.4), lineWidth: 0.5)
                        )
                }
                Spacer(minLength: 0)
            }

            // 输入框 + 发送按钮
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant))
                    Text("发消息…")
                        .font(.system(size: 11))
                        .foregroundStyle(studio.color(.secondaryText, variant: variant).opacity(0.75))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    studio.color(.field, variant: variant).opacity(studio.surfaceOpacity),
                    in: RoundedRectangle(cornerRadius: min(pack.inputBarRadius, 13), style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: min(pack.inputBarRadius, 13), style: .continuous)
                        .stroke(studio.color(.border, variant: variant).opacity(0.5), lineWidth: 0.5)
                )

                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        studio.color(.accent, variant: variant),
                        in: RoundedRectangle(cornerRadius: min(pack.inputBarRadius, 13), style: .continuous)
                    )
            }

            // 状态三色 + 胶囊底
            HStack(spacing: 5) {
                chipSwatch(.success, "成功")
                chipSwatch(.warning, "警告")
                chipSwatch(.destructive, "危险")
                Spacer(minLength: 0)
                Text("1.2k tok")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(studio.color(.secondaryText, variant: variant))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(studio.color(.chip, variant: variant).opacity(studio.surfaceOpacity),
                                in: Capsule())
            }
        }
        .padding(10)
        .background(
            studio.color(.surface, variant: variant).opacity(studio.surfaceOpacity),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(studio.color(.border, variant: variant).opacity(0.5), lineWidth: 0.6)
        )
    }

    private func chipSwatch(_ role: AppearanceColorRole, _ label: String) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(studio.color(role, variant: variant))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(studio.color(role, variant: variant).opacity(0.14), in: Capsule())
    }
}
