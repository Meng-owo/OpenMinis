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

struct TogetherPanelView: View {

    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var player = TogetherPlayer.shared

    @State private var state = TogetherState()
    @State private var lyrics: TogetherLyrics?
    @State private var optimisticPosition: Double = 0
    @State private var isDragging = false
    @State private var shuffle = false
    @State private var repeatOne = false
    @State private var showNoteComposer = false
    @State private var noteDraft = ""

    private var aiName: String { ChatAddressing.assistant() }
    private var userName: String { ChatAddressing.user() }
    private var track: TogetherTrack? { state.track ?? player.track }

    var body: some View {
        GeometryReader { geo in
            let s = min(1.15, max(0.82, geo.size.height / 852))

            ZStack(alignment: .top) {
                CSSThemeVariables.bg(scope: .chat).ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar(s)
                    duoHeader(s)

                    if let t = track {
                        noteStrip(s)
                            .padding(.top, 8 * s)
                        disc(s)
                            .padding(.top, 6 * s)
                        titleBlock(t, s)
                        progressRow(s)
                            .padding(.top, 18 * s)
                            .padding(.horizontal, 28)
                        controls(s)
                            .padding(.top, 22 * s)
                        bottomActions(s)
                            .padding(.top, 20 * s)
                    } else {
                        emptyState
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear(perform: bootstrap)
        .onChange(of: player.track?.id) { _ in
            state = TogetherStore.shared.load()
            lyrics = player.track.flatMap { TogetherStore.shared.lyrics(for: $0) }
        }
        .sheet(isPresented: $showNoteComposer) { noteComposer }
    }

    // MARK: 顶栏

    private func topBar(_ s: CGFloat) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(ChatFont.font(size: 14, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                    .frame(width: 34, height: 34)
                    .background(CSSThemeVariables.optionBg(scope: .chat))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(TogetherCopy.title)
                .font(ChatFont.font(size: 11, weight: .medium))
                .tracking(2)
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))

            Spacer()

            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10 * s)
    }

    // MARK: 双人头像

    private func duoHeader(_ s: CGFloat) -> some View {
        VStack(spacing: 10 * s) {
            HStack(spacing: -14 * s) {
                avatar(Self.aiIcon, size: 104 * s, ring: 3 * s)
                    .zIndex(1)
                avatar(Self.userIcon, size: 104 * s, ring: 3 * s)
            }

            Text("\(aiName) & \(userName)")
                .font(ChatFont.font(size: 11, weight: .medium))
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

    private static var aiIcon: String? {
        let id = SoulStore.displayPersonaId(nil)
        if let p = PersonaStore.shared.personas.first(where: { $0.id == id }), let a = p.avatar, !a.isEmpty {
            return a
        }
        return SoulStore.cachedMetadata.icon
    }

    private static var userIcon: String? {
        PersonaStore.shared.personas
            .first(where: { $0.id == PersonaStore.userProfilePersonaID })?
            .avatar
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
                        .font(ChatFont.font(size: 12.5))
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
                    .font(ChatFont.font(size: 13, weight: .medium))
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
        let size = 250 * s
        return ZStack {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                TogetherSkin.vinyl.opacity(0.92),
                                TogetherSkin.vinyl,
                                TogetherSkin.vinyl
                            ],
                            center: .center, startRadius: 10, endRadius: size / 2
                        )
                    )

                // 纹路：一圈一圈的细线，越往外越密
                ForEach(1..<26, id: \.self) { i in
                    Circle()
                        .strokeBorder(
                            TogetherSkin.vinylRing,
                            lineWidth: 1
                        )
                        .padding(size / 2 * CGFloat(i) / 26 * 0.94)
                }

                Circle()
                    .fill(CSSThemeVariables.card(scope: .chat))
                    .frame(width: size * 0.552, height: size * 0.552)
                    .overlay(
                        Image(systemName: "headphones")
                            .font(ChatFont.font(size: size * 0.16, weight: .light))
                            .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                    )
                    .overlay(
                        Circle().strokeBorder(
                            CSSThemeVariables.bg(scope: .chat).opacity(0.25), lineWidth: 0.8)
                    )

                Circle()
                    .fill(CSSThemeVariables.bg(scope: .chat).opacity(0.9))
                    .frame(width: 6, height: 6)
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(player.currentTime / 22.0 * 360))
            .animation(.linear(duration: 0.5), value: player.currentTime)
            .shadow(color: TogetherSkin.shadowDeep, radius: 26, x: 0, y: 16)
            .onTapGesture { player.toggle() }

            // 唱臂：右上角一根斜杆
            HStack {
                Spacer()
                Capsule()
                    .fill(CSSThemeVariables.textMain(scope: .chat).opacity(0.35))
                    .frame(width: 2.5 * s, height: 96 * s)
                    .rotationEffect(.degrees(21))
                    .offset(x: -6 * s, y: -size * 0.30)
            }
            .frame(width: size + 26 * s)
        }
        .frame(height: size + 10)
    }

    // MARK: 歌名

    private func titleBlock(_ t: TogetherTrack, _ s: CGFloat) -> some View {
        VStack(spacing: 5 * s) {
            Text(t.title)
                .font(ChatFont.font(size: 26 * s, weight: .semibold))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let en = t.titleEn, !en.isEmpty {
                Text(en)
                    .font(ChatFont.font(size: 13.5 * s, design: .serif))
                    .italic()
                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.85))
            }

            Text(t.artist)
                .font(ChatFont.font(size: 11.5 * s, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
        }
        .padding(.top, 14 * s)
        .padding(.horizontal, 24)
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
            .font(ChatFont.font(size: 10.5, weight: .medium))
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
                       active: shuffle) { shuffle.toggle() }

            iconButton("backward.fill", size: 24 * s, active: false) { step(-1) }

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(ChatFont.font(size: 25 * s, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.accentFg(scope: .chat))
                    .frame(width: 68 * s, height: 68 * s)
                    .background(CSSThemeVariables.accent(scope: .chat))
                    .clipShape(Circle())
                    .shadow(color: TogetherSkin.shadowSoft, radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)

            iconButton("forward.fill", size: 24 * s, active: false) { step(1) }

            iconButton("repeat.1", size: 19 * s, active: repeatOne) { repeatOne.toggle() }
        }
    }

    private func iconButton(_ symbol: String, size: CGFloat, active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(ChatFont.font(size: size, weight: .medium))
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
                    .font(ChatFont.font(size: 17, weight: .medium))
                Text(title)
                    .font(ChatFont.font(size: 9.5, weight: .medium))
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
                .font(ChatFont.font(size: 15, weight: .semibold))
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
                    TogetherStore.shared.addNote(at: player.currentTime, text: text, by: .user)
                    state = TogetherStore.shared.load()
                    noteDraft = ""
                    showNoteComposer = false
                }
                .font(ChatFont.font(size: 14, weight: .semibold))
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
                .font(ChatFont.font(size: 40, weight: .light))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.6))
            Text(TogetherCopy.emptyTitle)
                .font(ChatFont.font(size: 15, weight: .medium))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
            Text(TogetherCopy.emptyHint)
                .font(ChatFont.font(size: 12.5))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))

            VStack(spacing: 3) {
                Text(TogetherStore.shared.rootDecision)
                Text("曲库 \(TogetherStore.shared.library().tracks.count) 首")
                Text(TogetherStore.shared.libraryURL.path)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .font(ChatFont.font(size: 9, design: .monospaced))
            .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.65))
            .padding(.horizontal, 24)
            .padding(.top, 14)

            Spacer()
        }
    }

    // MARK: 数据

    private var currentLyricText: String? {
        guard let lyr = lyrics, lyr.timed, let trackId = track?.id else { return nil }
        guard lyr.trackId.isEmpty || lyr.trackId == trackId else { return nil }
        return lyr.line(at: effectivePosition)?.text
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
            player.load(t, from: state.playback.position)
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