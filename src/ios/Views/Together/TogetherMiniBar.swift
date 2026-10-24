//
//  TogetherMiniBar.swift
//  MinisApp
//
//  一起听 · 悬浮小卡。
//
//  叉掉全屏面板之后它不是关掉，是缩成这张卡继续放。
//  外形照语音卡那套来（圆角、描边、播放键尺寸），省得再造一套语言；
//  中间那块换成"一句歌词"，因为唱歌的和说话的不是一回事。
//
//  收起态贴屏幕侧边成一根竖条，点一下弹回来。
//  只贴左右两侧：聊天页的侧滑和抽屉都在边缘，上下贴边会抢手势。
//

import SwiftUI

struct TogetherMiniBar: View {

    @ObservedObject private var player = TogetherPlayer.shared

    @State private var state = TogetherState()
    @State private var lyrics: TogetherLyrics?
    @State private var collapsed = false
    @State private var alignedRight = true
    @State private var dragY: CGFloat = 0
    @State private var dragging = false

    private let cardWidth: CGFloat = 250
    private let cardHeight: CGFloat = 72

    var body: some View {
        GeometryReader { geo in
            let maxY = max(0, geo.size.height - cardHeight - 140)
            HStack {
                if alignedRight { Spacer(minLength: 0) }
                bar
                    .offset(y: clampedY(maxY))
                    .gesture(dragGesture(maxY: maxY))
                if !alignedRight { Spacer(minLength: 0) }
            }
            .padding(alignedRight ? .trailing : .leading, collapsed ? 0 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear(perform: reload)
        .onChange(of: player.track?.id) { _ in reload() }
    }

    private func clampedY(_ maxY: CGFloat) -> CGFloat {
        min(max(0, dragY), maxY)
    }

    // MARK: 卡片

    private var bar: some View {
        Group {
            if collapsed {
                collapsedBar
            } else {
                expandedBar
            }
        }
        .onTapGesture {
            if collapsed {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { collapsed = false }
            }
        }
    }

    private var expandedBar: some View {
        HStack(spacing: 10) {
            cover

            VStack(alignment: .leading, spacing: 2) {
                Text(player.track?.title ?? "一起听")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                    .lineLimit(1)

                Text(movingLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                    .lineLimit(1)
                    .id(movingLine)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .animation(.easeOut(duration: 0.18), value: movingLine)
            }

            Spacer(minLength: 0)

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.accentFg(scope: .chat))
                    .frame(width: 30, height: 30)
                    .background(CSSThemeVariables.accent(scope: .chat))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button { nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                    .frame(width: 24, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CSSThemeVariables.card(scope: .chat))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CSSThemeVariables.optionBorder(scope: .chat), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomLeading) { progressHairline }
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
    }

    /// 收起态：一根竖条，只留进度和暂停。
    private var collapsedBar: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let ratio = progressRatio
                ZStack(alignment: .top) {
                    Capsule().fill(CSSThemeVariables.divider(scope: .chat))
                    Capsule()
                        .fill(CSSThemeVariables.accent(scope: .chat))
                        .frame(height: geo.size.height * ratio)
                }
            }
            .frame(width: 3, height: 54)

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .frame(width: 12, height: 104)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: alignedRight ? 10 : 0,
                bottomLeadingRadius: alignedRight ? 10 : 0,
                bottomTrailingRadius: alignedRight ? 0 : 10,
                topTrailingRadius: alignedRight ? 0 : 10,
                style: .continuous
            )
            .fill(CSSThemeVariables.card(scope: .chat))
        )
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        CSSThemeVariables.textMain(scope: .chat).opacity(0.18),
                        CSSThemeVariables.textMain(scope: .chat).opacity(0.42)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CSSThemeVariables.card(scope: .chat).opacity(0.9))
            )
    }

    private var progressHairline: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(CSSThemeVariables.accent(scope: .chat).opacity(0.55))
                .frame(width: geo.size.width * progressRatio, height: 1.5)
        }
        .frame(height: 1.5)
        .padding(.horizontal, 1)
    }

    private var progressRatio: CGFloat {
        let d = max(player.duration, 1)
        return CGFloat(min(1, max(0, player.currentTime / d)))
    }

    // MARK: 文字

    /// 这一行给谁：有歌词就歌词，没有就我留过的话，再没有就歌名。
    private var movingLine: String {
        if let lyr = lyrics, lyr.timed, let line = lyr.line(at: player.currentTime)?.text,
           !line.trimmingCharacters(in: .whitespaces).isEmpty {
            return line
        }
        if let note = nearestNote { return note.text }
        return player.track?.artist.isEmpty == false ? (player.track?.artist ?? "") : "一起听"
    }

    private var nearestNote: TogetherNote? {
        guard let trackId = player.track?.id else { return nil }
        let pos = player.currentTime
        return state.notes
            .filter { $0.trackId == trackId && abs($0.at - pos) <= 14 }
            .min(by: { abs($0.at - pos) < abs($1.at - pos) })
    }

    // MARK: 手势

    private func dragGesture(maxY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragging = true
                dragY += value.translation.height
                dragY = min(max(0, dragY), maxY)
            }
            .onEnded { value in
                dragging = false
                // 横向拖过 60pt 换边
                if value.predictedEndTranslation.width < -60 {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { alignedRight = false }
                } else if value.predictedEndTranslation.width > 60 {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { alignedRight = true }
                }
                // 往边上甩（纵向），或者甩得够快，就收起
                if value.predictedEndTranslation.height > 160 || abs(value.predictedEndTranslation.width) > 200 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { collapsed = true }
                }
            }
    }

    // MARK: 数据

    private func reload() {
        state = TogetherStore.shared.load()
        lyrics = player.track.flatMap { TogetherStore.shared.lyrics(for: $0) }
    }

    private func nextTrack() {
        let lib = TogetherStore.shared.library()
        guard !lib.tracks.isEmpty else { return }
        let ids = lib.tracks.map { $0.id }
        let idx = ids.firstIndex(of: player.track?.id ?? "") ?? 0
        let next = lib.tracks[(idx + 1) % lib.tracks.count]
        player.load(next)
        TogetherStore.shared.play(trackId: next.id, at: 0, by: .user)
        reload()
    }
}