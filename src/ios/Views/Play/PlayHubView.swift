import SwiftUI
import PhotosUI

// MARK: - Play Hub（播放）
//
// [T-playhub-rebuild 10-15 醒醒] 入口从设置搬进「播放」；页面照小家的样板间
// 重做：头像 + 名字 + 可换背景，下面预留内容入口（图片/视频/音频/文件/进化），
// 等各类文件接进来可视化。
//   • 头像 = 灵魂头像（跟聊天里同一张脸，改了处处一致）；
//   • 名字 = 灵魂名（不写死；点一下就能改，改完全 App 同步）；
//   • 背景 = 本页专用图，存进外观资源目录（备份一并带走）；
//   • 图标 = 统一模板：白底圆角 + 实心圆润矢量图形（SF Symbols），
//     颜色全部走外观变量，不写死色值。

struct PlayHubView: View {

    struct HubEntry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
    }

    private let entries: [HubEntry] = [
        HubEntry(id: "images", title: "图片", subtitle: "照片、截图都在这儿看",
                 systemImage: "photo.fill"),
        HubEntry(id: "videos", title: "视频", subtitle: "小片段、录屏都在这儿看",
                 systemImage: "video.fill"),
        HubEntry(id: "audio", title: "音频", subtitle: "语音、声音都在这儿听",
                 systemImage: "waveform"),
        HubEntry(id: "files", title: "文件", subtitle: "文档、资料都在这儿翻",
                 systemImage: "doc.fill"),
        HubEntry(id: "evolution", title: "进化", subtitle: "轨迹、经验、开关都在这儿管",
                 systemImage: "sparkles"),
    ]

    @ObservedObject private var studio = AppearanceStudio.shared
    @State private var backgroundImage: UIImage?
    @State private var soulIcon: String = ""
    @State private var displayName: String = ""
    @State private var backgroundItem: PhotosPickerItem?
    @State private var avatarItem: PhotosPickerItem?
    @State private var showNameEditor = false
    @State private var nameDraft = ""

    private static var backgroundURL: URL {
        AppearanceStudio.appearanceAssetsDirectory.appendingPathComponent("play-hub-background.jpg")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        NavigationLink {
                            destination(for: entry)
                        } label: {
                            entryRow(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                Text("入口先留好，内容会一件件接进来。")
                    .font(.system(size: 12))
                    .foregroundStyle(MinisThemeList.subtitle)
                    .padding(.top, 2)
            }
            .padding(.bottom, 28)
        }
        .background(studio.color(.canvas, scope: .home).ignoresSafeArea())
        .navigationTitle(AppLocalized("Play", comment: "Play hub page title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .soulMdChanged)) { _ in
            soulIcon = SoulStore.cachedMetadata.icon
            displayName = SoulStore.cachedMetadata.name
        }
        .onChange(of: backgroundItem) { item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = ThumbnailCache.downsampledImage(from: data, maxEdge: 1800),
                      let jpeg = image.jpegData(compressionQuality: 0.85) else {
                    backgroundItem = nil
                    return
                }
                try? jpeg.write(to: Self.backgroundURL, options: .atomic)
                backgroundImage = image
                backgroundItem = nil
            }
        }
        .onChange(of: avatarItem) { item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = ThumbnailCache.downsampledImage(from: data, maxEdge: 512) else {
                    avatarItem = nil
                    return
                }
                try? studio.setAssistantAvatar(image)
                soulIcon = SoulStore.cachedMetadata.icon
                avatarItem = nil
            }
        }
        .alert("改个名字", isPresented: $showNameEditor) {
            TextField("名字", text: $nameDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { saveName() }
        } message: {
            Text("改的是名字本身，整个 App 都会跟着换。")
        }
    }

    // MARK: - 头图（背景 + 头像 + 名字）

    private var header: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                PhotosPicker(selection: $backgroundItem, matching: .images) {
                    backgroundLayer
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if backgroundImage != nil {
                        Button("移除背景", role: .destructive) { removeBackground() }
                    }
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Color.clear, studio.color(.canvas, scope: .home)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 54)
                        .allowsHitTesting(false)
                }

                PhotosPicker(selection: $avatarItem, matching: .images) {
                    avatar
                }
                .buttonStyle(.plain)
                .offset(y: 44)
            }

            Button {
                nameDraft = displayName
                showNameEditor = true
            } label: {
                Text(displayName.isEmpty ? "轻点起个名字" : displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(displayName.isEmpty ? MinisThemeList.subtitle : MinisThemeList.title)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(MinisThemeList.rowFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 52)
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let image = backgroundImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(colors: [studio.color(.mutedSurface, scope: .home),
                                    studio.color(.canvas, scope: .home)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var avatar: some View {
        SoulIconView(icon: soulIcon, size: 88)
            .frame(width: 88, height: 88)
            .background(studio.color(.mutedSurface, scope: .home), in: Circle())
            .clipShape(Circle())
            .overlay(Circle().stroke(studio.color(.raised, scope: .home), lineWidth: 3))
            .shadow(color: studio.color(.primaryText, scope: .home).opacity(0.10), radius: 10, y: 3)
            .contentShape(Circle())
    }

    // MARK: - 入口行（统一图标模板）

    private func entryRow(_ entry: HubEntry) -> some View {
        HStack(spacing: 12) {
            iconTile(entry.systemImage)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MinisThemeList.title)
                Text(entry.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(MinisThemeList.subtitle)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(MinisThemeList.rowFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func iconTile(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(MinisThemeList.accent)
            .frame(width: 40, height: 40)
            .background(studio.color(.raised, scope: .home),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(studio.color(.border, scope: .home).opacity(0.55), lineWidth: 0.6)
            )
    }

    // MARK: - 目的地

    @ViewBuilder
    private func destination(for entry: HubEntry) -> some View {
        switch entry.id {
        case "evolution":
            EvolutionCenterView()
        default:
            PlayHubCategoryView(entry: entry)
        }
    }

    // MARK: - 数据

    private func reload() {
        backgroundImage = UIImage(contentsOfFile: Self.backgroundURL.path)
        soulIcon = SoulStore.cachedMetadata.icon
        displayName = SoulStore.cachedMetadata.name
    }

    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var soul = SoulStore.load() ?? SoulFile(metadata: .default, body: "")
        soul.metadata.name = trimmed
        try? SoulStore.save(soul)
        displayName = SoulStore.cachedMetadata.name
    }

    private func removeBackground() {
        try? FileManager.default.removeItem(at: Self.backgroundURL)
        backgroundImage = nil
    }
}

// MARK: - 内容间（先占位，等文件接进来）

private struct PlayHubCategoryView: View {
    let entry: PlayHubView.HubEntry

    @ObservedObject private var studio = AppearanceStudio.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: entry.systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(MinisThemeList.accent)
                .frame(width: 86, height: 86)
                .background(studio.color(.raised, scope: .home),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(studio.color(.border, scope: .home).opacity(0.55), lineWidth: 0.6)
                )
            Text(entry.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(MinisThemeList.title)
            Text(entry.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(MinisThemeList.subtitle)
                .multilineTextAlignment(.center)
            Text("内容接入中，先占个位。")
                .font(.system(size: 12))
                .foregroundStyle(MinisThemeList.meta)
                .padding(.top, 2)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(studio.color(.canvas, scope: .home).ignoresSafeArea())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
