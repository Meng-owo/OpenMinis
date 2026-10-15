import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Play Hub（播放）
//
// [T-playhub-rebuild 10-15 醒醒] v2：五格胶囊开关（图片/视频/音频/文件/进化），
// 点什么下面就换什么；数据真接——会话桶、共享夹、媒体库、rootfs 里的文件全部
// 扫进来分桶展示，不再是空占位。
//   • 头像/名字/背景仍可编辑（v1 保留）；
//   • 图标仍是统一模板：白底圆角 + 实心圆润矢量图形；
//   • 颜色全部走外观变量（canvas/surface/raised/mutedSurface/accent/border），
//     不写死任何色值。

struct PlayHubView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case images, videos, audio, files, evolution
        var id: String { rawValue }
        var title: String {
            switch self {
            case .images: return "图片"
            case .videos: return "视频"
            case .audio: return "音频"
            case .files: return "文件"
            case .evolution: return "进化"
            }
        }
        var systemImage: String {
            switch self {
            case .images: return "photo.fill"
            case .videos: return "video.fill"
            case .audio: return "waveform"
            case .files: return "doc.fill"
            case .evolution: return "sparkles"
            }
        }
        var emptyText: String {
            switch self {
            case .images: return "还没有攒下图片——聊天里收发的图会聚到这里。"
            case .videos: return "还没有视频——发过的片段会聚到这里。"
            case .audio: return "还没有声音——语音和朗读会聚到这里。"
            case .files: return "还没有文件——资料和文档会聚到这里。"
            case .evolution: return ""
            }
        }
    }

    @ObservedObject private var studio = AppearanceStudio.shared
    @State private var selection: Tab = .images
    @State private var scanResult: PlayHubMediaScanner.Result?
    @State private var scanning = false

    // 预览/播放
    @State private var gallery: GalleryPresentation?
    @State private var playingVideo: URL?
    @State private var playingAudio: URL?
    @State private var previewFile: URL?

    // 头像 / 名字 / 背景（v1 保留）
    @State private var backgroundImage: UIImage?
    @State private var soulIcon: String = ""
    @State private var displayName: String = ""
    @State private var backgroundItem: PhotosPickerItem?
    @State private var avatarItem: PhotosPickerItem?
    @State private var showNameEditor = false
    @State private var nameDraft = ""

    // 上传 / 删除（P1-2 / P1-3）
    @State private var uploadPicks: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var importing = false
    @State private var pendingDelete: PlayHubMediaScanner.Hit?
    @State private var showDeleteConfirm = false
    @State private var currentFileTypes: [UTType] = [.item]

    private static var backgroundURL: URL {
        AppearanceStudio.appearanceAssetsDirectory.appendingPathComponent("play-hub-background.jpg")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            selector
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(studio.color(.canvas, scope: .home).ignoresSafeArea())
        .navigationTitle(AppLocalized("Play", comment: "Play hub page title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            reload()
            await rescan()
        }
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
        .fullScreenCover(item: $gallery) { g in
            MessageImageGallery(items: g.items, startIndex: g.startIndex)
        }
        .fullScreenCover(item: $playingVideo) { url in
            MinisVideoFullscreenPlayer(fileURL: url)
        }
        .sheet(item: $playingAudio) { url in
            MinisAudioPreviewView(fileURL: url)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $previewFile) { url in
            filePreviewView(url)
        }
        .confirmationDialog("删除这个文件？",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let url = pendingDelete?.url {
                    try? FileManager.default.removeItem(at: url)
                    Task { await rescan() }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("将同时删除聊天里引用的该文件，此操作不可恢复。")
        }
        .photosPicker(isPresented: $showPhotoPicker,
                      selection: $uploadPicks,
                      maxSelectionCount: 20,
                      matching: uploadMatching)
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: currentFileTypes) { result in
            if case .success(let url) = result {
                Task { await importFile(from: url) }
            }
        }
        .onChange(of: uploadPicks) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task { await handleUploadPicks() }
        }
    }

    // MARK: - 头图（背景 + 头像 + 名字）

    private var header: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                PhotosPicker(selection: $backgroundItem, matching: .images) {
                    backgroundLayer
                        .frame(height: 150)
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
                        .frame(height: 46)
                        .allowsHitTesting(false)
                }

                PhotosPicker(selection: $avatarItem, matching: .images) {
                    avatar
                }
                .buttonStyle(.plain)
                .offset(y: 38)
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
            .padding(.top, 44)
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
        SoulIconView(icon: soulIcon, size: 76)
            .frame(width: 76, height: 76)
            .background(studio.color(.mutedSurface, scope: .home), in: Circle())
            .clipShape(Circle())
            .overlay(Circle().stroke(studio.color(.raised, scope: .home), lineWidth: 3))
            .shadow(color: studio.color(.primaryText, scope: .home).opacity(0.10), radius: 10, y: 3)
            .contentShape(Circle())
    }

    // MARK: - 五格胶囊开关

    private var selector: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? MinisThemeList.title : MinisThemeList.subtitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(studio.color(.raised, scope: .home))
                                    .shadow(color: studio.color(.primaryText, scope: .home).opacity(0.08),
                                            radius: 3, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if selection != .evolution {
                Button {
                    switch selection {
                    case .audio:
                        currentFileTypes = [.audio]
                        showFileImporter = true
                    case .files:
                        currentFileTypes = [.item]
                        showFileImporter = true
                    default:
                        showPhotoPicker = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MinisThemeList.accent)
                        .frame(width: 30, height: 30)
                        .background(studio.color(.raised, scope: .home), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
        .padding(4)
        .background(Capsule().fill(studio.color(.mutedSurface, scope: .home).opacity(0.6)))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .images: imagesTab
        case .videos: videosTab
        case .audio: audioTab
        case .files: filesTab
        case .evolution: EvolutionCenterView(embedded: true)
        }
    }

    @ViewBuilder
    private var imagesTab: some View {
        if scanning && scanResult == nil {
            loadingView
        } else if let hits = scanResult?.images, !hits.isEmpty {
            GeometryReader { geo in
                let side = max(72, (geo.size.width - 36) / 3)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                              spacing: 6) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                            Button {
                                gallery = GalleryPresentation(items: imageGalleryItems(hits),
                                                              startIndex: index)
                            } label: {
                                AsyncCacheURLImageTile(cacheURL: hit.url, tileSize: side)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    pendingDelete = hit
                                    showDeleteConfirm = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
                .refreshable { await rescan() }
            }
        } else {
            emptyView("photo", Tab.images.emptyText)
        }
    }

    @ViewBuilder
    private var videosTab: some View {
        if scanning && scanResult == nil {
            loadingView
        } else if let hits = scanResult?.videos, !hits.isEmpty {
            GeometryReader { geo in
                let side = max(72, (geo.size.width - 36) / 3)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                              spacing: 6) {
                        ForEach(hits) { hit in
                            PlayHubVideoTile(fileURL: hit.url, tileSize: side) {
                                playingVideo = hit.url
                            }
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    pendingDelete = hit
                                    showDeleteConfirm = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
                .refreshable { await rescan() }
            }
        } else {
            emptyView("video", Tab.videos.emptyText)
        }
    }

    @ViewBuilder
    private var audioTab: some View {
        if scanning && scanResult == nil {
            loadingView
        } else if let hits = scanResult?.audio, !hits.isEmpty {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(hits) { hit in
                        Button {
                            playingAudio = hit.url
                        } label: {
                            mediaRow(icon: "waveform", title: hit.name,
                                     subtitle: "\(PlayHubFormat.size(hit.size)) · \(PlayHubFormat.date(hit.modified))")
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                pendingDelete = hit
                                showDeleteConfirm = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .refreshable { await rescan() }
        } else {
            emptyView("waveform", Tab.audio.emptyText)
        }
    }

    @ViewBuilder
    private var filesTab: some View {
        if scanning && scanResult == nil {
            loadingView
        } else if let hits = scanResult?.files, !hits.isEmpty {
            let grouped = Self.groupFiles(hits)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(grouped, id: \.0) { category, items in
                        fileCategorySection(category: category, items: items)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .refreshable { await rescan() }
        } else {
            emptyView("doc", Tab.files.emptyText)
        }
    }

    // MARK: - 文件桶自动分类 + 折叠（P1-4）

    private enum FileCategory: String, CaseIterable {
        case scripts, code, config, docs, memory, other
        var label: String {
            switch self {
            case .scripts: return "脚本"
            case .code: return "代码"
            case .config: return "配置"
            case .docs: return "文档"
            case .memory: return "记忆"
            case .other: return "其他"
            }
        }
    }

    /// 扩展名优先，目录语义补充（memory/ 下的 .md 归"记忆"）。
    private static func category(of hit: PlayHubMediaScanner.Hit) -> FileCategory {
        let ext = hit.url.pathExtension.lowercased()
        let rel = hit.relative.lowercased()
        if rel.contains("memory/") && ext == "md" { return .memory }
        switch ext {
        case "py", "sh", "js", "ts", "swift", "kt", "go", "rs": return .scripts
        case "c", "h", "m", "mm", "cpp", "java": return .code
        case "json", "yml", "yaml", "plist", "xml", "toml", "ini": return .config
        case "md", "txt", "rst": return .docs
        default: return .other
        }
    }

    private static func groupFiles(_ hits: [PlayHubMediaScanner.Hit])
        -> [(FileCategory, [PlayHubMediaScanner.Hit])] {
        let dict = Dictionary(grouping: hits, by: { category(of: $0) })
        return FileCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    /// 分组头可折叠；行保留长按删除（P1-3）。
    private func fileCategorySection(category: FileCategory,
                                     items: [PlayHubMediaScanner.Hit]) -> some View {
        DisclosureGroup {
            LazyVStack(spacing: 8) {
                ForEach(items) { hit in
                    Button {
                        previewFile = hit.url
                    } label: {
                        mediaRow(icon: "doc.fill", title: hit.name,
                                 subtitle: "\(hit.relative) · \(PlayHubFormat.size(hit.size))")
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            pendingDelete = hit
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Text(category.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MinisThemeList.title)
                Text("\(items.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MinisThemeList.subtitle)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(studio.color(.raised, scope: .home), in: Capsule())
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 行 / 空态 / 载入

    private func mediaRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MinisThemeList.accent)
                .frame(width: 36, height: 36)
                .background(studio.color(.raised, scope: .home),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(studio.color(.border, scope: .home).opacity(0.55), lineWidth: 0.6)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MinisThemeList.title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(MinisThemeList.subtitle)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MinisThemeList.rowFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func emptyView(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(MinisThemeList.accent)
                .frame(width: 84, height: 84)
                .background(studio.color(.raised, scope: .home),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(studio.color(.border, scope: .home).opacity(0.55), lineWidth: 0.6)
                )
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(MinisThemeList.subtitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 预览分发

    @ViewBuilder
    private func filePreviewView(_ url: URL) -> some View {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown":
            MinisMarkdownPreviewView(fileURL: url)
        case "txt", "log", "json", "csv", "swift", "py", "sh", "js", "ts", "css",
             "xml", "yml", "yaml", "ini", "toml", "sql":
            MinisTextPreviewView(fileURL: url)
        case "html", "htm":
            MinisHTMLPreviewView(fileURL: url)
        default:
            MinisDocumentPreviewView(fileURL: url)
        }
    }

    private func imageGalleryItems(_ hits: [PlayHubMediaScanner.Hit]) -> [GalleryItem] {
        hits.map { hit in
            GalleryItem(id: hit.id, title: hit.name) {
                let url = hit.url
                return await Task.detached(priority: .userInitiated) {
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return downsampleImageData(data, maxPixelSize: 2048)
                }.value
            }
        }
    }

    // MARK: - 数据

    private func reload() {
        backgroundImage = UIImage(contentsOfFile: Self.backgroundURL.path)
        soulIcon = SoulStore.cachedMetadata.icon
        displayName = SoulStore.cachedMetadata.name
    }

    private func rescan() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        let roots = PlayHubMediaScanner.roots()
        let result = await Task.detached(priority: .userInitiated) {
            PlayHubMediaScanner.scan(roots: roots)
        }.value
        scanResult = result
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

    // MARK: - 上传（P1-2）

    /// 按当前桶选匹配类型：图片桶只收图、视频桶只收视频（音频走文件导入）。
    private var uploadMatching: PHPickerFilter {
        switch selection {
        case .images: return .images
        case .videos: return .videos
        default: return .images
        }
    }

    private func uploadDir() -> URL {
        let dir = AIChatViewModel.minisPersistentBase
            .appendingPathComponent("play-hub", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 重名自动追加序号（play-1.jpg），不覆盖。
    private func uniqueDest(_ dir: URL, name: String) -> URL {
        var dest = dir.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let ext = (name as NSString).pathExtension
            let base = (name as NSString).deletingPathExtension
            dest = dir.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return dest
    }

    private func saveImported(_ data: Data, ext: String) {
        let dest = uniqueDest(uploadDir(), name: "play-\(Int(Date().timeIntervalSince1970)).\(ext)")
        try? data.write(to: dest)
    }

    private func handleUploadPicks() async {
        guard !uploadPicks.isEmpty else { return }
        importing = true
        defer { importing = false }
        let target = selection
        for item in uploadPicks {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext: String
            switch target {
            case .images: ext = "jpg"
            case .videos: ext = "mov"
            default: ext = "bin"
            }
            saveImported(data, ext: ext)
        }
        uploadPicks = []
        await rescan()
    }

    private func importFile(from url: URL) async {
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            saveImported(data, ext: ext)
            await rescan()
        }
    }
}

// MARK: - 统一视频瓦片（缩略图 + 播放角标）

private struct PlayHubVideoTile: View {
    let fileURL: URL
    let tileSize: CGFloat
    let onTap: () -> Void

    @ObservedObject private var studio = AppearanceStudio.shared
    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: tileSize, height: tileSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(studio.color(.mutedSurface, scope: .home))
                        .frame(width: tileSize, height: tileSize)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(studio.color(.raised, scope: .home))
                    .padding(4)
                    .background(studio.color(.primaryText, scope: .home).opacity(0.55))
                    .clipShape(Circle())
                    .padding(4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(studio.color(.border, scope: .home).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .task(id: fileURL) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let url = fileURL
        let image: UIImage? = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 320)
            guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
        if let image { thumbnail = image }
    }
}

// MARK: - 数据扫描（一趟扫，四桶分类）

struct PlayHubMediaScanner {
    struct Hit: Identifiable {
        let id: String
        let url: URL
        let name: String
        let relative: String
        let size: Int
        let modified: Date
    }

    struct Result {
        var images: [Hit] = []
        var videos: [Hit] = []
        var audio: [Hit] = []
        var files: [Hit] = []
    }

    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "tiff", "tif"]
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
    static let audioExts: Set<String> = ["m4a", "mp3", "wav", "caf", "aac", "flac", "ogg", "opus", "aiff"]
    static let noiseExts: Set<String> = ["db", "sqlite", "sqlite3", "wal", "shm", "lock", "tmp",
                                         "cache", "plist", "log", "jsonl", "db-journal"]

    static let maxScanEntries = 12_000
    static let caps: (images: Int, videos: Int, audio: Int, files: Int) = (600, 200, 400, 400)

    /// 全部数据根（主线程取，避免 detached 里碰凡尘）。
    static func roots() -> [URL] {
        var list: [URL] = []
        list.append(AIChatViewModel.minisPersistentBase)
        list.append(AIChatViewModel.minisPersistentBase
            .deletingLastPathComponent()
            .appendingPathComponent("media", isDirectory: true))
        list.append(AIChatViewModel.minisSharedPersistentDir)
        list.append(RootfsManager.shared.dataPath.appendingPathComponent("var/minis", isDirectory: true))
        return list
    }

    static func scan(roots: [URL]) -> Result {
        var result = Result()
        var seen = Set<String>()
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fm.enumerator(at: root,
                                                 includingPropertiesForKeys: keys,
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            var scanned = 0
            for case let url as URL in enumerator {
                scanned += 1
                if scanned > maxScanEntries { break }
                let ext = url.pathExtension.lowercased()
                if ext.isEmpty || noiseExts.contains(ext) { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                let resolved = url.resolvingSymlinksInPath().path
                guard seen.insert(resolved).inserted else { continue }
                let relative = url.path.hasPrefix(root.path + "/")
                    ? String(url.path.dropFirst(root.path.count + 1))
                    : url.lastPathComponent
                let hit = Hit(id: resolved,
                              url: url,
                              name: url.lastPathComponent,
                              relative: relative,
                              size: values.fileSize ?? 0,
                              modified: values.contentModificationDate ?? .distantPast)
                if imageExts.contains(ext) {
                    result.images.append(hit)
                } else if videoExts.contains(ext) {
                    result.videos.append(hit)
                } else if audioExts.contains(ext) {
                    result.audio.append(hit)
                } else {
                    result.files.append(hit)
                }
            }
        }

        result.images = Array(result.images.sorted { $0.modified > $1.modified }.prefix(caps.images))
        result.videos = Array(result.videos.sorted { $0.modified > $1.modified }.prefix(caps.videos))
        result.audio = Array(result.audio.sorted { $0.modified > $1.modified }.prefix(caps.audio))
        result.files = Array(result.files.sorted { $0.modified > $1.modified }.prefix(caps.files))
        return result
    }
}

// MARK: - 小格式化

enum PlayHubFormat {
    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
