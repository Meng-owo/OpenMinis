//
//  TogetherDrawers.swift
//  MinisApp
//
//  一起听 · 底部抽屉组件：
//  1. 历史回声墙（整首歌我们所有的刻字，点击直达回声，底部带输入框）
//  2. 播放队列（查看下一首放什么，点歌切歌）
//

import SwiftUI

// MARK: - 1. 历史回声墙抽屉

struct TogetherEchoDrawerView: View {

    let track: TogetherTrack
    let onSeek: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state = TogetherStore.shared.load()
    @State private var draft = ""

    private var notes: [TogetherNote] {
        state.notes
            .filter { $0.trackId == track.id }
            .sorted { $0.at < $1.at }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if notes.isEmpty {
                    emptyView
                } else {
                    list
                }

                Divider().overlay(CSSThemeVariables.divider(scope: .chat))
                inputBar
            }
            .background(CSSThemeVariables.bg(scope: .chat).ignoresSafeArea())
            .navigationTitle("\(TogetherCopy.historyEchoes) (\(notes.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized("Close", comment: "关闭")) { dismiss() }
                        .font(ChatFont.font(14, weight: .medium))
                        .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(ChatFont.font(40))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.4))
            Text("这首歌还没有刻过字")
                .font(ChatFont.font(14, weight: .medium))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
            Text("在下面留下一句，播到那一秒时就会浮现回声")
                .font(ChatFont.font(11.5))
                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat).opacity(0.8))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(notes) { note in
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            onSeek(note.at)
                            dismiss()
                        } label: {
                            Text(mmss(note.at))
                                .font(ChatFont.font(11, weight: .bold))
                                .foregroundStyle(CSSThemeVariables.accent(scope: .chat))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(CSSThemeVariables.accent(scope: .chat).opacity(0.12)))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(note.from == TogetherActor.ai.rawValue ? ChatAddressing.assistant() : ChatAddressing.user())
                                    .font(ChatFont.font(11, weight: .semibold))
                                    .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                                Text(TogetherEchoClock.label(note.ts))
                                    .font(ChatFont.font(9.5))
                                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                            }

                            Text(note.text)
                                .font(ChatFont.font(13))
                                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(CSSThemeVariables.card(scope: .chat))
                    )
                }
            }
            .padding(18)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("在这一秒留下你的一句话...", text: $draft)
                .textFieldStyle(.plain)
                .font(ChatFont.font(13.5))
                .foregroundStyle(CSSThemeVariables.textMain(scope: .chat))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CSSThemeVariables.optionBg(scope: .chat))
                )

            Button {
                sendNote()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(ChatFont.font(26))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty
                        ? CSSThemeVariables.textDim(scope: .chat).opacity(0.4)
                        : CSSThemeVariables.accent(scope: .chat))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sendNote() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let currentPos = TogetherPlayer.shared.currentTime
        let ok = TogetherStore.shared.addNote(at: currentPos, text: text, by: .user, trackId: track.id)
        if ok {
            state = TogetherStore.shared.load()
            draft = ""
        } else {
            MinisToast.show(TogetherCopy.oneLineOnly, systemImage: "exclamationmark.circle")
        }
    }

    private func mmss(_ s: Double) -> String {
        let total = max(0, Int(s.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - 2. 播放队列抽屉

struct TogetherQueueDrawerView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = TogetherPlayer.shared

    @State private var tracks: [TogetherTrack] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(tracks) { track in
                        let isCurrent = player.track?.id == track.id

                        HStack(spacing: 12) {
                            if isCurrent {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(ChatFont.font(13))
                                    .foregroundStyle(CSSThemeVariables.accent(scope: .chat))
                                    .frame(width: 20)
                            } else {
                                Text("\(tracks.firstIndex(of: track).map { $0 + 1 } ?? 1)")
                                    .font(ChatFont.font(12, weight: .medium))
                                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                                    .frame(width: 20)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(ChatFont.font(13.5, weight: isCurrent ? .semibold : .regular))
                                    .foregroundStyle(isCurrent
                                        ? CSSThemeVariables.accent(scope: .chat)
                                        : CSSThemeVariables.textMain(scope: .chat))
                                    .lineLimit(1)

                                Text(track.artist)
                                    .font(ChatFont.font(10.5))
                                    .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(track.durationString)
                                .font(ChatFont.font(11))
                                .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.load(track)
                            TogetherStore.shared.play(trackId: track.id, at: 0, by: .user)
                            dismiss()
                        }
                    }
                } header: {
                    Text("当前列表共 \(tracks.count) 首歌曲")
                        .font(ChatFont.font(11))
                        .foregroundStyle(CSSThemeVariables.textDim(scope: .chat))
                }
            }
            .listStyle(.plain)
            .background(CSSThemeVariables.bg(scope: .chat).ignoresSafeArea())
            .navigationTitle(TogetherCopy.queueTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized("Done", comment: "完成")) { dismiss() }
                        .font(ChatFont.font(14, weight: .semibold))
                        .foregroundStyle(CSSThemeVariables.accent(scope: .chat))
                }
            }
            .onAppear {
                tracks = TogetherStore.shared.library().tracks
            }
        }
    }
}
