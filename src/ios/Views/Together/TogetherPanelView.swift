//
//  TogetherPanelView.swift
//  MinisApp
//
//  一起听 · 全屏面板（播放页）。
//
//  叉掉不等于关掉：dismiss 只收面板，TogetherPlayer 继续放，聊天页上浮出小卡。
//
//  颜色一律走 CSSThemeVariables，不写裸色值——换主题这一页跟着变。
//  歌词只显示一句，按时间轴换；没有时间轴就显示歌名，不拿假词凑。
//

import SwiftUI

struct TogetherPanelView: View {

    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var player = TogetherPlayer.shared

    @State private var state = TogetherState()
    @State private var lyrics: TogetherLyrics?
    @State private var optimisticPosition: Double = 0
    @State private var isDragging = false

    private var aiName: String { ChatAddressing.assistant() }
    private var userName: String { ChatAddressing.user() }
    private var track: TogetherTrack? { state.track ?? player.track }

    var body: some View {
        ZStack {
            CSSThemeVariables.bg(scope: .chat).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let t = track {
                    nowPlaying(t)
                } else {
                    emptyState
                }

                Spacer(minLength: 0)
            }
        }
        .onAppear(perform: bootstrap)
    }

    // MARK: 头部

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                    .frame(width: 34, height: 34)
                    .background(CSSThemeVariables.optionBg(scope: .chat))
                    .clipShape(Circle())
            }
            Spacer()
            Text(togetherNames)
                .font(.system(size: 11, weight: .medium))
                .tracking(2.4)
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private var togetherNames: String {
        "\(aiName) & \(userName)"
    }

    // MARK: 播放页

    private func nowPlaying(_ t: TogetherTrack) -> some View {
        VStack(spacing: 0) {
            vinyl(t)
                .padding(.top, 26)

            Text(t.title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 30)

            Text(t.artist)
                .font(.system(size: 12, weight: .medium))
                .tracking(1.7)
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                .padding(.top, 6)

            lyricLine
                .padding(.top, 22)

            progressRow
                .padding(.top, 20)
                .padding(.horizontal, 34)

            controls
                .padding(.top, 26)
        }
    }

    // MARK: 唱片

    private func vinyl(_ t: TogetherTrack) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            CSSThemeVariables.textMain(scope: .chat).opacity(0.82),
                            CSSThemeVariables.textMain(scope: .chat).opacity(0.62),
                            CSSThemeVariables.textMain(scope: .chat).opacity(0.92)
                        ],
                        center: .center, startRadius: 8, endRadius: 125
                    )
                )
                .overlay(
                    // 黑胶纹路：细圈，不用图片
                    Circle()
                        .strokeBorder(CSSThemeVariables.bg(scope: .chat).opacity(0.12), lineWidth: 1)
                        .padding(18)
                )
                .overlay(
                    Circle()
                        .strokeBorder(CSSThemeVariables.bg(scope: .chat).opacity(0.10), lineWidth: 1)
                        .padding(40)
                )

            Circle()
                .fill(CSSThemeVariables.card(scope: .chat))
                .frame(width: 138, height: 138)
                .overlay(
                    Image(systemName: "headphones")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                )
                .overlay(Circle().strokeBorder(CSSThemeVariables.divider(scope: .chat), lineWidth: 1))
        }
        .frame(width: 250, height: 250)
        // 旋转角度直接跟播放时间走：22 秒一圈。
        // 暂停自然停在原地不重置，也不用额外养一个 20Hz 的定时器耗电。
        .rotationEffect(.degrees(player.currentTime / 22.0 * 360))
        .animation(.linear(duration: 0.5), value: player.currentTime)
        .onTapGesture { player.toggle() }
    }

    // MARK: 歌词（一次一句）

    private var lyricLine: some View {
        Group {
            if let line = currentLyricText {
                Text(line)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat).opacity(0.86))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 42)
                    .padding(.horizontal, 40)
                    .id(line)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .animation(.easeOut(duration: 0.18), value: line)
            } else {
                // 没有时间轴歌词：这行留白，显示我留过的话；也没有就空着。
                Text(noteNearPlayhead ?? "")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 42)
                    .padding(.horizontal, 40)
            }
        }
    }

    private var currentLyricText: String? {
        guard let lyr = lyrics, lyr.timed, let trackId = track?.id else { return nil }
        guard lyr.trackId.isEmpty || lyr.trackId == trackId else { return nil }
        return lyr.line(at: effectivePosition)?.text
    }

    /// 这一秒附近有没有我留的话（±12 秒内，最近的一条）。
    private var noteNearPlayhead: String? {
        guard let trackId = track?.id else { return nil }
        let pos = effectivePosition
        let candidates = state.notes.filter { $0.trackId == trackId && abs($0.at - pos) <= 12 }
        return candidates.min(by: { abs($0.at - pos) < abs($1.at - pos) })?.text
    }

    // MARK: 进度

    private var effectivePosition: Double {
        isDragging ? optimisticPosition : player.currentTime
    }

    private var progressRow: some View {
        VStack(spacing: 8) {
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

                    // 我留话的位置：一个小小的点
                    ForEach(noteDots(duration: duration, width: width), id: \.self) { x in
                        Circle()
                            .fill(CSSThemeVariables.accent(scope: .chat))
                            .frame(width: 5, height: 5)
                            .overlay(Circle().strokeBorder(CSSThemeVariables.bg(scope: .chat), lineWidth: 1))
                            .offset(x: x - 2.5)
                    }
                }
                .frame(height: 18)
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
            .frame(height: 18)

            HStack {
                Text(mmss(effectivePosition))
                Spacer()
                Text(mmss(player.duration))
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.8))
        }
    }

    private func noteDots(duration: Double, width: CGFloat) -> [CGFloat] {
        guard let trackId = track?.id, duration > 0 else { return [] }
        return state.notes
            .filter { $0.trackId == trackId }
            .map { CGFloat(min(1, max(0, $0.at / duration))) * width }
    }

    // MARK: 控制

    private var controls: some View {
        HStack(spacing: 34) {
            Button { step(-1) } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
            }

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.accentFg(scope: .chat))
                    .frame(width: 68, height: 68)
                    .background(CSSThemeVariables.accent(scope: .chat))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button { step(1) } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "headphones")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.6))
            Text("还没有歌")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
            Text("我找来放进去，或者你从文件里传。")
                .font(.system(size: 12.5))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
            Spacer()
        }
    }

    // MARK: 行为

    private func bootstrap() {
        state = TogetherStore.shared.load()
        lyrics = state.track.flatMap { TogetherStore.shared.lyrics(for: $0) }

        // 冷启动接着放：文件里有歌、有进度，播放器却是空的
        if !player.isActive, let t = state.track, t.file != nil {
            player.load(t, from: state.playback.position)
        }
    }

    private func step(_ delta: Int) {
        let lib = TogetherStore.shared.library()
        let ids = lib.tracks.map { $0.id }
        guard !ids.isEmpty else { return }
        let currentId = track?.id
        let idx = ids.firstIndex(of: currentId ?? "") ?? 0
        let next = (idx + delta + ids.count) % ids.count
        let t = lib.tracks[next]
        player.load(t)
        TogetherStore.shared.play(trackId: t.id, at: 0, by: .user)
        state = TogetherStore.shared.load()
        lyrics = TogetherStore.shared.lyrics(for: t)
    }

    private func mmss(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}