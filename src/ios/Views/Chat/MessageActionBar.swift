import SwiftUI
import UIKit

// MARK: - Message action bar (kelivo-style + Feedback extension)
//
// [T-message-action-bar 09-11→09-12] 醒醒要的 kelivo 式操作条,挂在 AI 消息气泡下:
//   [▶ 播放语音]  [↻ 重新回复]  [⧉ 复制]  [🗑 删除消息]  [💬 反馈回复]
//
// 播放按钮的状态跟全局播放状态走(不是 per-bubble):
//   空闲   → 用 TTS 服务层的当前声音读这一条气泡的文字
//   播放中 → 暂停
//   暂停中 → 继续

struct MessageActionBar: View {

    /// The bubble's plain text (already markdown-stripped for speech).
    let speakText: String
    /// Speaks ONLY this text via the service layer. Caller (vm) ensures the
    /// read-replies master switch is on before invoking.
    let onSpeak: (String) -> Void
    /// Global pause/resume/stop — the vm's SpeechControlling conformance.
    let controller: SpeechControlling
    /// Regenerate this assistant message (find preceding user msg → retry).
    let onRegenerate: () -> Void
    /// Delete this single assistant message.
    let onDelete: () -> Void
    /// Send feedback or prompt system notice back to the model.
    var onFeedback: ((String) -> Void)? = nil

    @ObservedObject private var outputState = VoiceOutputState.shared
    @State private var showFeedbackSheet: Bool = false

    private var isSpeaking: Bool { outputState.isReadingAloud }
    private var isPaused: Bool { outputState.isPausedOrHeld }

    var body: some View {
        HStack(spacing: 20) {
            playPauseButton
            regenerateButton
            copyButton
            deleteButton
            if onFeedback != nil {
                feedbackButton
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.18), value: isSpeaking)
        .sheet(isPresented: $showFeedbackSheet) {
            ChatFeedbackSheet { text in
                onFeedback?(text)
            }
        }
    }

    // MARK: Play / pause / resume

    private var playPauseButton: some View {
        Button {
            if isSpeaking && !isPaused {
                controller.toggleSpeechPause()
            } else if isPaused {
                controller.toggleSpeechPause()
            } else {
                onSpeak(speakText)
            }
        } label: {
            Group {
                if isSpeaking && !isPaused {
                    actionIcon("pause.fill", label: "Pause")
                } else if isPaused {
                    actionIcon("play.fill", label: "Resume")
                } else {
                    actionIcon("speaker.wave.2.fill", label: "Play")
                }
            }
        }
        .buttonStyle(.borderless)
    }

    // MARK: Regenerate

    private var regenerateButton: some View {
        Button { onRegenerate() } label: {
            actionIcon("arrow.clockwise", label: "Regenerate")
        }
        .buttonStyle(.borderless)
    }

    // MARK: Copy

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = speakText
            MinisToast.show(AppLocalized("Copied", comment: "Message action bar: copied toast"),
                            systemImage: "doc.on.doc")
        } label: {
            actionIcon("doc.on.doc", label: "Copy")
        }
        .buttonStyle(.borderless)
    }

    // MARK: Delete

    private var deleteButton: some View {
        Button(role: .destructive) { onDelete() } label: {
            actionIcon("trash", label: "Delete")
        }
        .buttonStyle(.borderless)
    }

    // MARK: Feedback

    private var feedbackButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showFeedbackSheet = true
        } label: {
            actionIcon("text.bubble", label: "Feedback")
        }
        .buttonStyle(.borderless)
    }

    // MARK: Icon helper

    private func actionIcon(_ systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MinisTheme.secondaryText)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }
}

// MARK: - 回复反馈与整蛊抽屉 (ChatFeedbackSheet)
//
// 100% 对齐 feedback-demo_2.html 原型规范与 CSSThemeVariables 全局色彩驱动。

struct ChatFeedbackSheet: View {
    let onSendFeedback: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var feedbackText: String = ""
    @State private var sendAsSystem: Bool = false
    @State private var templates: [String] = {
        let saved = UserDefaults.standard.stringArray(forKey: "openminis_feedback_templates") ?? []
        return saved.isEmpty ? ["说人话", "短一点", "不许道歉"] : saved
    }()
    @State private var isThumbUp: Bool = false
    @State private var isThumbDown: Bool = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部抓手条
            Capsule()
                .fill(CSSThemeVariables.divider(isDark: isDark))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            // 头部标题与关闭按钮
            ZStack {
                Text("反馈这条回复")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))

                HStack {
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                            .frame(width: 32, height: 32)
                            .background(CSSThemeVariables.accentSoft(isDark: isDark))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. 快捷赞踩
                    VStack(alignment: .leading, spacing: 8) {
                        Text("快捷")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))

                        HStack(spacing: 12) {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                isThumbUp = true
                                isThumbDown = false
                                MinisToast.show("已点赞", systemImage: "hand.thumbsup.fill")
                                onSendFeedback("[系统：上条回复被点赞]")
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isThumbUp ? "hand.thumbsup.fill" : "hand.thumbsup")
                                        .font(.system(size: 16))
                                    Text("赞")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(isThumbUp ? CSSThemeVariables.accent(isDark: isDark) : CSSThemeVariables.card(isDark: isDark))
                                .foregroundStyle(isThumbUp ? CSSThemeVariables.accentFg(isDark: isDark) : CSSThemeVariables.textMain(isDark: isDark))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(isThumbUp ? Color.clear : CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1.0)
                                )
                                .shadow(color: CSSThemeVariables.sheetShadow(isDark: isDark).opacity(0.06), radius: 6, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                isThumbDown = true
                                isThumbUp = false
                                MinisToast.show("已踩", systemImage: "hand.thumbsdown.fill")
                                onSendFeedback("[系统：上条回复被踩]")
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isThumbDown ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                        .font(.system(size: 16))
                                    Text("踩")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(isThumbDown ? CSSThemeVariables.accentSoft(isDark: isDark) : CSSThemeVariables.card(isDark: isDark))
                                .foregroundStyle(isThumbDown ? CSSThemeVariables.accent(isDark: isDark) : CSSThemeVariables.textMain(isDark: isDark))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(isThumbDown ? CSSThemeVariables.accent(isDark: isDark) : CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1.0)
                                )
                                .shadow(color: CSSThemeVariables.sheetShadow(isDark: isDark).opacity(0.06), radius: 6, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 2. 快捷标签与趣味互动
                    VStack(alignment: .leading, spacing: 8) {
                        Text("快捷标签")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))

                        FeedbackFlowLayout(hSpacing: 8, vSpacing: 8) {
                            tagButton("太长", systemMsg: "[系统：上条回复被标记为过长]")
                            tagButton("太客服腔", systemMsg: "[系统：上条回复被标记为客服腔]")
                            tagButton("没感觉", systemMsg: "[系统：上条回复被标记为没感觉]")
                            funTagButton("戳一下", systemMsg: "[系统：醒醒戳了你一下]")
                            funTagButton("闭嘴", systemMsg: "[系统：醒醒让你闭嘴]")
                        }
                    }

                    // 3. 自定义输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自定义")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))

                        TextField("写你想对他说的话…", text: $feedbackText, axis: .vertical)
                            .lineLimit(3...5)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(CSSThemeVariables.optionBg(isDark: isDark))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1.0)
                            )

                        // 身份分段切换
                        HStack(spacing: 0) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    sendAsSystem = false
                                }
                            } label: {
                                Text("以醒醒发")
                                    .font(.system(size: 13, weight: !sendAsSystem ? .semibold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(!sendAsSystem ? CSSThemeVariables.card(isDark: isDark) : Color.clear)
                                    .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                                    .clipShape(Capsule())
                                    .shadow(color: !sendAsSystem ? CSSThemeVariables.sheetShadow(isDark: isDark).opacity(0.12) : Color.clear, radius: 4, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    sendAsSystem = true
                                }
                            } label: {
                                Text("以系统通知发")
                                    .font(.system(size: 13, weight: sendAsSystem ? .semibold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(sendAsSystem ? CSSThemeVariables.card(isDark: isDark) : Color.clear)
                                    .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                                    .clipShape(Capsule())
                                    .shadow(color: sendAsSystem ? CSSThemeVariables.sheetShadow(isDark: isDark).opacity(0.12) : Color.clear, radius: 4, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(4)
                        .background(CSSThemeVariables.accentSoft(isDark: isDark))
                        .clipShape(Capsule())

                        Text(sendAsSystem ? "以系统通知发 = 发出 [系统：…]，模型会照做 · 只在当前对话生效" : "以醒醒发 = 当普通消息发出 · 只在当前对话生效")
                            .font(.system(size: 11))
                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                    }

                    // 4. 常用模板
                    VStack(alignment: .leading, spacing: 8) {
                        Text("常用模板")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))

                        FeedbackFlowLayout(hSpacing: 8, vSpacing: 8) {
                            ForEach(templates, id: \.self) { tpl in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    feedbackText = tpl
                                } label: {
                                    Text(tpl)
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(CSSThemeVariables.card(isDark: isDark))
                                        .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule().strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1.0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            // ＋ 存为模板
                            Button {
                                let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else {
                                    MinisToast.show("先写点内容再存", systemImage: "pencil")
                                    return
                                }
                                if !templates.contains(trimmed) {
                                    templates.append(trimmed)
                                    UserDefaults.standard.set(templates, forKey: "openminis_feedback_templates")
                                    MinisToast.show("已存为常用模板！", systemImage: "checkmark")
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("存为模板")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.clear)
                                .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark))
                                .overlay(
                                    Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        .foregroundStyle(CSSThemeVariables.textDim(isDark: isDark).opacity(0.5))
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }

            // 底部发送按钮
            HStack {
                Spacer()
                Button {
                    let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let msg = sendAsSystem ? "[系统：\(trimmed)]" : trimmed
                    onSendFeedback(msg)
                    dismiss()
                } label: {
                    Text("发送")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minWidth: 100)
                        .padding(.vertical, 12)
                        .background(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CSSThemeVariables.optionBg(isDark: isDark) : CSSThemeVariables.accent(isDark: isDark))
                        .foregroundStyle(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CSSThemeVariables.textDim(isDark: isDark) : CSSThemeVariables.accentFg(isDark: isDark))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.hidden)
        .background(CSSThemeVariables.card(isDark: isDark).ignoresSafeArea())
    }

    private func tagButton(_ title: String, systemMsg: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSendFeedback(systemMsg)
            MinisToast.show("已反馈「\(title)」")
            dismiss()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(CSSThemeVariables.optionBg(isDark: isDark))
                .foregroundStyle(CSSThemeVariables.textMain(isDark: isDark))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1.0)
                )
        }
        .buttonStyle(.plain)
    }

    private func funTagButton(_ title: String, systemMsg: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSendFeedback(systemMsg)
            MinisToast.show("已发送「\(title)」")
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(CSSThemeVariables.accentSoft(isDark: isDark))
            .foregroundStyle(CSSThemeVariables.accent(isDark: isDark))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(CSSThemeVariables.accent(isDark: isDark).opacity(0.35), lineWidth: 1.0)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FeedbackFlowLayout

private struct FeedbackFlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + vSpacing
                lineHeight = 0
            }
            currentX += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + vSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
