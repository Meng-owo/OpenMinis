//
//  TogetherPanelView.swift
//  MinisApp
//
//  一起听 · 全屏播放页。照 reference.html 的 01 播放页做。
//
//  坐标基准 393 × 852，整页按屏幕高度等比缩放，比例不变。
//  所有颜色走 CSSThemeVariables，不写裸色值。
//
//  叉掉不等于关掉：dismiss 只收面板，TogetherPlayer 继续放，聊天页浮出小卡。
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TogetherPanelView: View {


    @ObservedObject private var player = TogetherPlayer.shared

    @State private var state = TogetherState()
    @State private var lyrics: TogetherLyrics?
    @State private var optimisticPosition: Double = 0
    @State private var isDragging = false
    @State private var showNoteComposer = false
    /// 点胶片翻到歌词页，再点回来。
    @State private var showLyrics = false
    /// 回声气泡：同一时间只放一个，放完再接下一个。
    @State private var echoOn = true
    @State private var echoBubbles: [EchoBubble] = []
    @State private var echoQueue: [TogetherNote] = []
    @State private var echoLastPosition: Double = 0
    @State private var echoCorner: Int = 0
    @State private var showWallpaperPicker = false
    @State private var pendingWallpaper: [URL] = []
    @State private var noteDraft = ""
    /// 每 2 秒看一眼 state.json：我在 shell 里改了东西，她这边不重启也能看见。
    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var aiName: String { ChatAddressing.assistant() }
    private var userName: String { ChatAddressing.user() }
    private var track: TogetherTrack? { state.track ?? player.track }

    var body: some View {
        GeometryReader { geo in
            let s = min(1.15, max(0.82, geo.size.height / 852))

            ZStack(alignment: .top) {
                pageBackground

                VStack(spacing: 0) {
                    topBar(s)
                    duoHeader(s)

                    if let t = track {
                        noteStrip(s)
                            .padding(.top, 8 * s)
                        disc(s)
                            .padding(.top, 6 * s)
                        titleBlock(t, s)
                            .sheet(isPresented: $showWallpaperPicker) {
                                DocumentCopyPicker(contentTypes: [.image],
                                                   allowsMultipleSelection: false) { urls in
                                    pendingWallpaper = urls
                                } onDone: {
                                    showWallpaperPicker = false
                                    if let url = pendingWallpaper.first {
                                        _ = TogetherStore.shared.setImage(slot: TogetherImages.wallpaperNow, from: url)
                                    }
                                    pendingWallpaper = []
                                    state = TogetherStore.shared.load()
                                }
                            }
                        progressRow(s)
                            .padding(.top, 34 * s)
                            .padding(.horizontal, 28)
                        controls(s)
                            .padding(.top, 30 * s)
                        bottomActions(s)
                            .padding(.top, 26 * s)
                    } else {
                        emptyState
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear(perform: bootstrap)
        .onReceive(ticker) { _ in
            let fresh = TogetherStore.shared.load()
            if fresh.revision != state.revision {
                state = fresh
            }
        }
        .onChange(of: player.track?.id) { _ in
            state = TogetherStore.shared.load()
            lyrics = player.track.flatMap { TogetherStore.shared.lyrics(for: $0) }
            echoBubbles.removeAll()
            echoQueue.removeAll()
            echoLastPosition = player.currentTime
        }
        .onChange(of: player.currentTime) { pos in
            checkEcho(at: pos)
        }
        .sheet(isPresented: $showNoteComposer) { noteComposer }
        .overlay {
            if showLyrics, let t = track {
                TogetherLyricsPage(track: t,
                                   lyrics: lyrics,
                                   loopLine: state.loopLines[t.id],
                                   position: player.currentTime,
                                   onSeek: { target in
                                       player.seek(to: target)
                                       TogetherStore.shared.seek(to: target, by: .user)
                                   },
                                   onClose: {
                                       withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                                           showLyrics = false
                                       }
                                   })
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.04)),
                        removal: .opacity
                    ))
                    .zIndex(10)
            }
        }
    }

    // MARK: 顶栏

    private func topBar(_ s: CGFloat) -> some View {
        // 关闭按钮由根容器统一给，这里只占位，保证标题在正中间。
        HStack {
            Color.clear.frame(width: 34, height: 34)
            Spacer()
            Text(TogetherCopy.title)
                .font(ChatFont.font(11, weight: .medium))
                .tracking(2)
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
            Spacer()
            Button {
                echoOn.toggle()
                if !echoOn {
                    echoBubbles.removeAll()
                    echoQueue.removeAll()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: echoOn ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    Text(echoOn ? TogetherCopy.echoOn : TogetherCopy.echoOff)
                }
                .font(ChatFont.font(9, weight: .medium))
                .foregroundStyle(echoOn
                    ? CSSThemeVariables.accent(scope: .chat)
                    : CSSThemeVariables.textDim(scope: .chat).opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(CSSThemeVariables.optionBg(scope: .chat)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10 * s)
    }

    // MARK: 双人头像

    private func duoHeader(_ s: CGFloat) -> some View {
        VStack(spacing: 10 * s) {
            HStack(spacing: -14 * s) {
                avatar(TogetherIdentity.aiIcon, size: 104 * s, ring: 3 * s)
                    .zIndex(1)
                avatar(TogetherIdentity.userIcon, size: 104 * s, ring: 3 * s)
            }

            Text("\(aiName) & \(userName)")
                .font(ChatFont.font( 11, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
        }
        .padding(.top, 12 * s)
    }

    private func avatar(_ iconRef: String?, size: CGFloat, ring: CGFloat) -> some View {
        PersonaAvatarView(iconRef: iconRef, size: size)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(CSSThemeVariables.bg(scope: .chat), lineWidth: ring)
            )
    }

    // MARK: 我留的话

    private func noteStrip(_ s: CGFloat) -> some View {
        Group {
            if let note = noteNearPlayhead {
                HStack(spacing: 8) {
                    Circle()
                        .fill(CSSThemeVariables.accent(scope: .chat))
                        .frame(width: 5, height: 5)

                    (Text(aiName).fontWeight(.semibold)
                        + Text("  ") + Text(note.text))
                        .font(ChatFont.font( 12.5))
                        .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(CSSThemeVariables.optionBg(scope: .chat).opacity(0.7))
                )
                .transition(.opacity)
            } else if let line = currentLyricText {
                Text(line)
                    .font(ChatFont.font( 13, weight: .medium))
                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.85))
                    .lineLimit(1)
                    .frame(height: 20)
                    .id(line)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .animation(.easeOut(duration: 0.18), value: line)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .frame(height: 30)
    }

    // MARK: 唱片

    private func disc(_ s: CGFloat) -> some View {
        ZStack {
            TogetherDiscView(size: 250 * s,
                             spinDegrees: player.currentTime / 22.0 * 360,
                             isPlaying: player.isPlaying) {
                // 点胶片翻到歌词页——不是暂停。
                withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                    showLyrics = true
                }
            }

            // 回声：黑胶周围，一次只显一个
            ForEach(echoBubbles) { bubble in
                EchoBubbleView(bubble: bubble)
                    .offset(x: bubble.dx * s, y: bubble.dy * s)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 250 * s + 10)
    }

    // MARK: 歌名

    private func titleBlock(_ t: TogetherTrack, _ s: CGFloat) -> some View {
        VStack(spacing: 5 * s) {
            Text(t.title)
                .font(ChatFont.font( 26 * s, weight: .semibold))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let en = t.titleEn, !en.isEmpty {
                Text(en)
                    .font(ChatFont.font( 13.5 * s, design: .serif))
                    .italic()
                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.85))
            }

            Text(t.artist)
                .font(ChatFont.font( 11.5 * s, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
        }
        .padding(.top, 14 * s)
        .padding(.horizontal, 24)
        .contextMenu {
            Button(TogetherCopy.changeWallpaper) { showWallpaperPicker = true }
            Button(TogetherCopy.resetCover, role: .destructive) {
                TogetherStore.shared.clearImage(slot: TogetherImages.wallpaperNow)
            }
        }
    }

    private var pageBackground: some View {
        ZStack {
            CSSThemeVariables.bg(scope: .chat)
            if let url = TogetherImages.url(for: TogetherImages.wallpaperNow),
               let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .overlay(CSSThemeVariables.bg(scope: .chat).opacity(0.82))
                    .clipped()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: 进度

    private var effectivePosition: Double {
        isDragging ? optimisticPosition : player.currentTime
    }

    private func progressRow(_ s: CGFloat) -> some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let width = geo.size.width
                let duration = max(player.duration, 1)
                let ratio = min(1, max(0, effectivePosition / duration))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CSSThemeVariables.divider(scope: .chat))
                        .frame(height: 4)
                    Capsule()
                        .fill(CSSThemeVariables.accent(scope: .chat))
                        .frame(width: width * ratio, height: 4)

                    Circle()
                        .fill(CSSThemeVariables.accent(scope: .chat))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(CSSThemeVariables.bg(scope: .chat), lineWidth: 1.5))
                        .offset(x: max(0, width * ratio - 4.5))

                    ForEach(noteDotOffsets(duration: duration, width: width), id: \.self) { x in
                        Circle()
                            .fill(CSSThemeVariables.accent(scope: .chat).opacity(0.85))
                            .frame(width: 4, height: 4)
                            .offset(x: x - 2, y: -5)
                    }
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let r = min(1, max(0, value.location.x / max(width, 1)))
                            optimisticPosition = Double(r) * duration
                        }
                        .onEnded { value in
                            let r = min(1, max(0, value.location.x / max(width, 1)))
                            let target = Double(r) * duration
                            player.seek(to: target)
                            TogetherStore.shared.seek(to: target, by: .user)
                            isDragging = false
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(mmss(effectivePosition))
                Spacer()
                Text(mmss(player.duration))
            }
            .font(ChatFont.font( 10.5, weight: .medium))
            .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.75))
        }
    }

    private func noteDotOffsets(duration: Double, width: CGFloat) -> [CGFloat] {
        guard let trackId = track?.id, duration > 0 else { return [] }
        return Array(Set(state.notes
            .filter { $0.trackId == trackId }
            .map { (CGFloat(min(1, max(0, $0.at / duration))) * width).rounded() }))
            .sorted()
    }

    // MARK: 控制

    private func controls(_ s: CGFloat) -> some View {
        HStack(spacing: 26 * s) {
            iconButton("shuffle", size: 19 * s,
                       active: state.playback.shuffle) {
                TogetherStore.shared.setShuffle(!state.playback.shuffle)
                state = TogetherStore.shared.load()
            }

            iconButton("backward.fill", size: 24 * s, active: false) { step(-1) }

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(ChatFont.font( 25 * s, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.accentFg(scope: .chat))
                    .frame(width: 68 * s, height: 68 * s)
                    .background(CSSThemeVariables.accent(scope: .chat))
                    .clipShape(Circle())
                    .shadow(color: TogetherSkin.shadowSoft, radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)

            iconButton("forward.fill", size: 24 * s, active: false) { step(1) }

            iconButton("repeat.1", size: 19 * s, active: state.playback.repeatOne) {
                TogetherStore.shared.setRepeatOne(!state.playback.repeatOne)
                state = TogetherStore.shared.load()
            }
        }
    }

    private func iconButton(_ symbol: String, size: CGFloat, active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ChatFont.font( size, weight: .medium))
                .foregroundStyle(
                    active
                        ? CSSThemeVariables.accent(scope: .chat)
                        : CSSThemeVariables.textDim(scope: .chat)
                )
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: 底部

    private func bottomActions(_ s: CGFloat) -> some View {
        let liked = track.map { state.liked.contains($0.id) } ?? false

        return HStack(spacing: 0) {
            bottomItem("heart.fill", TogetherCopy.like, active: liked) {
                if let id = track?.id {
                    TogetherStore.shared.toggleLike(trackId: id, by: .user)
                    state = TogetherStore.shared.load()
                }
            }
            bottomItem("text.bubble", TogetherCopy.comment, active: false) {
                showNoteComposer = true
            }
            bottomItem("plus", TogetherCopy.addToPlaylist, active: false, enabled: false) {}
            bottomItem("speaker.wave.2", TogetherCopy.volume, active: false, enabled: false) {}
        }
        .padding(.horizontal, 18)
    }

    private func bottomItem(_ symbol: String, _ title: String, active: Bool,
                            enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(ChatFont.font( 17, weight: .medium))
                Text(title)
                    .font(ChatFont.font( 9.5, weight: .medium))
                    .tracking(0.6)
            }
            .foregroundStyle(
                active
                    ? CSSThemeVariables.accent(scope: .chat)
                    : CSSThemeVariables.textDim(scope: .chat)
            )
            .opacity(enabled ? 1 : 0.32)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 留言输入

    private var noteComposer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(TogetherCopy.leaveNoteTitle) \(mmss(player.currentTime))")
                .font(ChatFont.font( 15, weight: .semibold))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))

            TextField(TogetherCopy.leaveNotePlaceholder, text: $noteDraft, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CSSThemeVariables.optionBg(scope: .chat))
                )

            HStack {
                Spacer()
                Button(TogetherCopy.leaveNoteAction) {
                    let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    // 一轮一首歌，每个人只能刻一句。
                    let ok = TogetherStore.shared.addNote(at: player.currentTime, text: text, by: .user)
                    guard ok else {
                        MinisToast.show(TogetherCopy.oneLineOnly, systemImage: "exclamationmark.circle")
                        return
                    }
                    state = TogetherStore.shared.load()
                    noteDraft = ""
                    showNoteComposer = false
                }
                .font(ChatFont.font( 14, weight: .semibold))
                .foregroundStyle(CSSThemeVariables.accentFg(scope: .chat))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Capsule().fill(CSSThemeVariables.accent(scope: .chat)))
            }
        }
        .padding(22)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .presentationBackground(CSSThemeVariables.bg(scope: .chat))
    }

    // MARK: 空

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "headphones")
                .font(ChatFont.font( 40, weight: .light))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.6))
            Text(TogetherCopy.emptyTitle)
                .font(ChatFont.font( 15, weight: .medium))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
            Text(TogetherCopy.emptyHint)
                .font(ChatFont.font( 12.5))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))

            VStack(spacing: 3) {
                Text(TogetherStore.shared.rootDecision)
                Text("曲库 \(TogetherStore.shared.library().tracks.count) 首")
                Text(TogetherStore.shared.libraryURL.path)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .font(ChatFont.font( 9, design: .monospaced))
            .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.65))
            .padding(.horizontal, 24)
            .padding(.top, 14)

            Spacer()
        }
    }

    // MARK: 数据

    /// 一句歌词。抓不到时间轴就用我写的那句循环——她说过，没词我得自己写。
    private var currentLyricText: String? {
        if let lyr = lyrics, lyr.timed, let trackId = track?.id,
           lyr.trackId.isEmpty || lyr.trackId == trackId,
           let line = lyr.line(at: effectivePosition)?.text,
           !line.trimmingCharacters(in: .whitespaces).isEmpty {
            return line
        }
        if let id = track?.id, let loop = state.loopLines[id],
           !loop.trimmingCharacters(in: .whitespaces).isEmpty {
            return loop
        }
        return nil
    }

    private var noteNearPlayhead: TogetherNote? {
        guard let trackId = track?.id else { return nil }
        let pos = effectivePosition
        return state.notes
            .filter { $0.trackId == trackId && abs($0.at - pos) <= 12 }
            .min(by: { abs($0.at - pos) < abs($1.at - pos) })
    }

    private func bootstrap() {
        state = TogetherStore.shared.load()
        lyrics = state.track.flatMap { TogetherStore.shared.lyrics(for: $0) }

        if !player.isActive, let t = state.track, t.file != nil {
            // 冷启动接着放：位置接上，但放不放按 state 里记的来。
            // 上次是暂停的就别自己响起来。
            player.load(t, from: state.playback.position)
            if !state.playback.playing {
                player.pause()
            }
        }
    }

    // MARK: 回声

    /// 唱到某一句的那一秒才浮出来。
    /// 只在"往前走"时触发；拖回去、跳太远都不补发，免得一拖一堆。
    private func checkEcho(at pos: Double) {
        defer { echoLastPosition = pos }
        guard echoOn, let trackId = track?.id else { return }
        if pos < echoLastPosition - 1.5 || pos - echoLastPosition > 5 { return }

        let due = state.notes.filter { note in
            note.trackId == trackId && note.at > echoLastPosition && note.at <= pos
        }
        guard !due.isEmpty else { return }
        echoQueue.append(contentsOf: due)
        pumpEchoQueue(trackId: trackId)
    }

    private func pumpEchoQueue(trackId: String) {
        guard echoBubbles.isEmpty, !echoQueue.isEmpty else { return }
        let note = echoQueue.removeFirst()
        let corners: [(CGFloat, CGFloat)] = [(-72, -118), (78, -86), (-84, 74), (74, 104)]
        let corner = corners[echoCorner % corners.count]
        echoCorner += 1

        let bubble = EchoBubble(
            id: note.id,
            text: note.text,
            name: note.from == TogetherActor.ai.rawValue
                ? ChatAddressing.assistant()
                : ChatAddressing.user(),
            time: TogetherEchoClock.label(note.ts),
            isAI: note.from == TogetherActor.ai.rawValue,
            dx: corner.0,
            dy: corner.1
        )
        echoBubbles = [bubble]

        // 气泡活 4.6 秒，化完再接下一个——同一时间只一个。
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.65) {
            echoBubbles.removeAll()
            pumpEchoQueue(trackId: trackId)
        }
    }

    private func step(_ delta: Int) {
        let lib = TogetherStore.shared.library()
        guard !lib.tracks.isEmpty else { return }

        var next: TogetherTrack
        if shuffle {
            let pool = lib.tracks.filter { $0.id != track?.id }
            next = pool.randomElement() ?? lib.tracks[0]
        } else {
            let ids = lib.tracks.map { $0.id }
            let idx = ids.firstIndex(of: track?.id ?? "") ?? 0
            next = lib.tracks[(idx + delta + ids.count) % ids.count]
        }

        player.load(next)
        TogetherStore.shared.play(trackId: next.id, at: 0, by: .user)
        state = TogetherStore.shared.load()
        lyrics = TogetherStore.shared.lyrics(for: next)
    }

    private func mmss(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 唱片
//
// 单独拆出来：一个函数里塞五层叠加 + 26 圈纹路，编译器会拒绝做类型检查。
// 拆开之后每层都短，也能单独预览。

struct TogetherDiscView: View {
    let size: CGFloat
    let spinDegrees: Double
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            disc
                .rotationEffect(.degrees(spinDegrees))
                .animation(.linear(duration: 0.5), value: spinDegrees)
                .shadow(color: TogetherSkin.shadowDeep, radius: 26, x: 0, y: 16)
                .onTapGesture(perform: onTap)

            arm
        }
    }

    private var disc: some View {
        ZStack {
            Circle().fill(vinylFill)
            rings
            label
            hole
        }
        .frame(width: size, height: size)
    }

    private var vinylFill: RadialGradient {
        RadialGradient(colors: [TogetherSkin.vinyl.opacity(0.92),
                                TogetherSkin.vinyl,
                                TogetherSkin.vinyl],
                       center: .center, startRadius: 10, endRadius: size / 2)
    }

    private var rings: some View {
        ForEach(1..<26, id: \.self) { i in
            Circle()
                .strokeBorder(TogetherSkin.vinylRing, lineWidth: 1)
                .padding(size / 2 * CGFloat(i) / 26 * 0.94)
        }
    }

    private var label: some View {
        Circle()
            .fill(CSSThemeVariables.card(scope: .chat))
            .frame(width: size * 0.552, height: size * 0.552)
            .overlay(
                Image(systemName: "headphones")
                    .font(ChatFont.font(size * 0.16, weight: .light))
                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
            )
            .overlay(
                Circle().strokeBorder(CSSThemeVariables.bg(scope: .chat).opacity(0.25), lineWidth: 0.8)
            )
    }

    private var hole: some View {
        Circle()
            .fill(CSSThemeVariables.bg(scope: .chat).opacity(0.9))
            .frame(width: 6, height: 6)
    }

    private var arm: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(CSSThemeVariables.textMain(scope: .chat).opacity(0.35))
                .frame(width: 2.5, height: size * 0.384)
                .rotationEffect(.degrees(21))
                .offset(x: -6, y: -size * 0.30)
        }
        .frame(width: size + 26)
    }
}


// MARK: - 回声气泡
//
// 照 reference 的 whisperFlow：0% 缩到 0.35、下移 12、模糊 4、透明；
// 50% 回到 1、清晰；100% 缩到 0.4、上移 14、模糊 3、透明。
// 4.6 秒一笔贯通，纯椭圆，没有对话框小角。

struct EchoBubble: Identifiable, Equatable {
    let id: String
    let text: String
    let name: String
    let time: String
    let isAI: Bool
    let dx: CGFloat
    let dy: CGFloat
}

struct EchoBubbleView: View {
    let bubble: EchoBubble

    @State private var t: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(bubble.name).fontWeight(.semibold)
                Text(bubble.time)
            }
            .font(ChatFont.font(9))
            .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))

            Text(bubble.text)
                .font(ChatFont.font(12.5))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: 230, alignment: .leading)
        .background(
            Capsule().fill(
                bubble.isAI
                    ? CSSThemeVariables.card(scope: .chat).opacity(0.94)
                    : CSSThemeVariables.optionBg(scope: .chat)
            )
        )
        .overlay(
            Capsule().strokeBorder(CSSThemeVariables.bg(scope: .chat).opacity(0.95), lineWidth: 0.5)
        )
        .shadow(color: TogetherSkin.shadowSoft, radius: 16, x: 0, y: 12)
        .scaleEffect(scaleValue)
        .opacity(opacityValue)
        .blur(radius: blurValue)
        .offset(y: riseValue)
        .onAppear {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 4.6)) { t = 1 }
        }
    }

    private var seg: CGFloat { t < 0.5 ? t / 0.5 : (t - 0.5) / 0.5 }
    private var scaleValue: CGFloat { t < 0.5 ? 0.35 + 0.65 * seg : 1 - 0.6 * seg }
    private var opacityValue: Double { t < 0.5 ? Double(seg) : Double(1 - seg) }
    private var blurValue: CGFloat { t < 0.5 ? 4 - 4 * seg : 3 * seg }
    private var riseValue: CGFloat { t < 0.5 ? 12 - 12 * seg : -14 * seg }
}

// MARK: - 时间

enum TogetherEchoClock {
    static func label(_ ts: Int) -> String {
        guard ts > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}

// MARK: - 歌词页

/// 点胶片翻过来的整页歌词：当前句高亮居中，点一句跳到那句。
/// 没歌词就显示我写的那句循环——不许编假词。
struct TogetherLyricsPage: View {
    let track: TogetherTrack
    let lyrics: TogetherLyrics?
    let loopLine: String?
    let position: Double
    let onSeek: (Double) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                cover
                    .padding(.top, 18)
                if let lines = timedLines, !lines.isEmpty {
                    lyricsScroll(lines)
                        .padding(.top, 22)
                } else {
                    fallback
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: 背景

    private var background: some View {
        ZStack {
            CSSThemeVariables.bg(scope: .chat)
            if let url = TogetherImages.url(for: TogetherImages.wallpaperNow),
               let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .overlay(CSSThemeVariables.bg(scope: .chat).opacity(0.78))
                    .clipped()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: 顶栏

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(ChatFont.font(14, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                    .frame(width: 34, height: 34)
                    .background(CSSThemeVariables.optionBg(scope: .chat))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(track.title)
                    .font(ChatFont.font(12, weight: .medium))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(ChatFont.font(10))
                        .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                        .lineLimit(1)
                }
            }

            Spacer()

            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 22)
        .padding(.top, 54)
    }

    // MARK: 封面

    private var cover: some View {
        Group {
            if let url = TogetherImages.url(for: TogetherImages.lyricsCover),
               let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: TogetherSkin.shadowSoft, radius: 12, x: 0, y: 6)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TogetherCover.fill(track.cover))
                    .frame(width: 92, height: 92)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(ChatFont.font(26, weight: .light))
                            .foregroundStyle(CSSThemeVariables.card(scope: .chat).opacity(0.85))
                    )
            }
        }
    }

    // MARK: 歌词

    private var timedLines: [TogetherLyricLine]? {
        guard let lyr = lyrics, lyr.timed, !lyr.lines.isEmpty else { return nil }
        return lyr.lines
    }

    private var currentIndex: Int {
        guard let lyr = lyrics, lyr.timed, !lyr.lines.isEmpty else { return -1 }
        let t = position - lyr.offset
        var hit = -1
        for (i, line) in lyr.lines.enumerated() {
            if line.at <= t { hit = i } else { break }
        }
        return hit
    }

    private func lyricsScroll(_ lines: [TogetherLyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 18) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.text)
                            .font(ChatFont.font(idx == currentIndex ? 17 : 14,
                                                weight: idx == currentIndex ? .semibold : .regular))
                            .foregroundStyle(
                                idx == currentIndex
                                    ? CSSThemeVariables.textMain(scope: .chat)
                                    : CSSThemeVariables.textDim(scope: .chat).opacity(0.65)
                            )
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .scaleEffect(idx == currentIndex ? 1 : 0.96)
                            .animation(.easeOut(duration: 0.28), value: currentIndex)
                            .contentShape(Rectangle())
                            .onTapGesture { onSeek(line.at) }
                            .id(idx)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 180)
            }
            .onAppear {
                if currentIndex >= 0 { proxy.scrollTo(currentIndex, anchor: .center) }
            }
            .onChange(of: currentIndex) { idx in
                guard idx >= 0 else { return }
                withAnimation(.easeOut(duration: 0.4)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }

    private var fallback: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(loopLine ?? TogetherCopy.noLyrics)
                .font(ChatFont.font(17, weight: .medium))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Text(TogetherCopy.noLyricsHint)
                .font(ChatFont.font(11.5))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
            Spacer()
            Spacer()
        }
    }
}
