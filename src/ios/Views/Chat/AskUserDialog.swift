import SwiftUI

// MARK: - [s2-askuser] 提问小抽屉 (CSS全局变量驱动与原型一模一样)
//
// 对齐原型：/var/minis/attachments/uploads/question-tool-card.html
// 结构：半屏圆角小抽屉 + 顶部居中标题 + 右上角 44×44 圆形关闭叉号
//       + 通栏扁平选项行(带细分隔线) + 自填回答输入行 + 右下角 132×48 胶囊大发送按钮
//       + 全屏半透明 scrim 遮罩。
// 色彩：严格由 CSS 全局变量系统（:root 与 prefers-color-scheme: dark）驱动，
//       并与 AppearanceStudio 主题无缝对齐。

// MARK: - CSS 全局色彩变量定义

@MainActor
public enum CSSThemeVariables {
    private static var studio: AppearanceStudio { .shared }

    /// --color-card / var(--dudu-card)
    public static func card(isDark: Bool) -> Color {
        if studio.hasWallpaper(.chat) {
            return studio.color(.surface, scope: .chat).opacity(studio.surfaceOpacity)
        }
        return isDark ? Color(hex: "#2A2523") : Color(hex: "#FFFFFF")
    }

    /// --color-bg / var(--dudu-cream)
    public static func bg(isDark: Bool) -> Color {
        isDark ? Color(hex: "#1C1917") : Color(hex: "#FBF8EA")
    }

    /// --color-text-main / var(--dudu-brown)
    public static func textMain(isDark: Bool) -> Color {
        isDark ? Color(hex: "#E8D9D2") : Color(hex: "#8B736C")
    }

    /// --color-text-dim / var(--dudu-text-dim)
    public static func textDim(isDark: Bool) -> Color {
        isDark ? Color(hex: "#8A7A74") : Color(hex: "#A89890")
    }

    /// --color-divider / var(--dudu-divider)
    public static func divider(isDark: Bool) -> Color {
        isDark ? Color(hex: "#38302C") : Color(hex: "#F1E7E2")
    }

    /// --color-accent-soft / var(--dudu-pink-soft)
    public static func accentSoft(isDark: Bool) -> Color {
        isDark ? Color(hex: "#4A3A36") : Color(hex: "#FFE7E8")
    }

    /// --color-accent / var(--dudu-pink)
    public static func accent(isDark: Bool) -> Color {
        isDark ? Color(hex: "#C2869F") : Color(hex: "#ECC7D6")
    }

    /// --color-scrim / rgba(42, 42, 46, 0.28)
    public static func scrim(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.65) : Color(hex: "#2A2A2E").opacity(0.28)
    }

    /// --color-sheet-shadow / rgba(139, 115, 108, 0.16)
    public static func sheetShadow(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.45) : Color(hex: "#8B736C").opacity(0.16)
    }
}

// MARK: - 顶角圆角 Shape 工具

private struct AskRoundedCorner: Shape {
    var radius: CGFloat = 24.0
    var corners: UIRectCorner = [.topLeft, .topRight]

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - 问询挂载修饰器

struct AskUserDialogModifier: ViewModifier {
    @ObservedObject private var suspension = ToolSuspensionService.shared
    @ObservedObject var vm: AIChatViewModel

    private var currentRequest: SuspendedRequest? {
        suspension.askRequestForSession(vm.sessionId)
    }

    func body(content: Content) -> some View {
        ZStack {
            content

            if let request = currentRequest {
                AskUserDrawerOverlay(request: request, vm: vm)
                    .zIndex(9999)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: currentRequest != nil)
    }
}

// MARK: - 提问小抽屉 Overlay

private struct AskUserDrawerOverlay: View {
    let request: SuspendedRequest
    @ObservedObject var vm: AIChatViewModel

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == darkColorScheme }
    private let darkColorScheme = ColorScheme.dark

    @State private var states: [QuestionAnswerState] = []
    @State private var activeQuestionIndex: Int = 0

    private var payload: AskPayload? {
        if case .askUser(let p) = request.kind { return p }
        return nil
    }

    private var isRestored: Bool { request.tag == "ask-user-restored" }
    private var isSessionReady: Bool { !vm.isLoadingSession }

    private var questions: [AskQuestion] {
        payload?.questions ?? []
    }

    private var currentQuestion: AskQuestion? {
        guard !questions.isEmpty, activeQuestionIndex < questions.count else { return nil }
        return questions[activeQuestionIndex]
    }

    private var displayTitle: String {
        if let current = currentQuestion {
            return current.question
        }
        return payload?.title ?? "AI 想问你几个问题"
    }

    private var canSubmit: Bool {
        guard !states.isEmpty else { return false }
        for st in states {
            if !st.selected.isEmpty || !st.otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }
        return false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景半透明遮罩 (Scrim)
            CSSThemeVariables.scrim(isDark: isDark)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // 抽屉卡片主体
            VStack(spacing: 0) {
                // 顶部抓手条 (Grabber)
                Capsule()
                    .fill(CSSThemeVariables.divider(isDark: isDark))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                // 抽屉头部 (Head)
                ZStack(alignment: .trailing) {
                    VStack(spacing: 4) {
                        Text(displayTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(1)
                            .foregroundColor(CSSThemeVariables.textMain(isDark: isDark))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)

                        if questions.count > 1 {
                            Text("问题 \(activeQuestionIndex + 1) / \(questions.count)")
                                .font(.system(size: 11))
                                .foregroundColor(CSSThemeVariables.textDim(isDark: isDark))
                        } else if isRestored {
                            Text("之前未答完的问题，答完后继续")
                                .font(.system(size: 11))
                                .foregroundColor(CSSThemeVariables.textDim(isDark: isDark))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 64)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                    // 右上角圆形关闭按钮 (Close Button)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(CSSThemeVariables.textMain(isDark: isDark))
                            .frame(width: 44, height: 44)
                            .background(CSSThemeVariables.accentSoft(isDark: isDark))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 14)
                }

                // 抽屉主体：选项列表与自填输入行 (Body)
                ScrollView {
                    VStack(spacing: 0) {
                        if let q = currentQuestion, activeQuestionIndex < states.count {
                            let isMulti = q.type == "multi"
                            let currentState = states[activeQuestionIndex]

                            // 选项列表
                            ForEach(Array(q.options.enumerated()), id: \.offset) { optIdx, option in
                                let isSelected = currentState.selected.contains(optIdx)
                                Button {
                                    toggleOption(questionIndex: activeQuestionIndex, optionIndex: optIdx, isMulti: isMulti)
                                } label: {
                                    HStack(spacing: 0) {
                                        Text(option)
                                            .font(.system(size: 14))
                                            .foregroundColor(CSSThemeVariables.textMain(isDark: isDark))
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: isMulti ? "checkmark.square.fill" : "checkmark")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(CSSThemeVariables.accent(isDark: isDark))
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .frame(minHeight: 56)
                                    .background(isSelected ? CSSThemeVariables.accentSoft(isDark: isDark) : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .background(CSSThemeVariables.divider(isDark: isDark))
                            }

                            // 自填回答输入行 (Free Input Row)
                            HStack(spacing: 8) {
                                TextField("输入回答…", text: Binding(
                                    get: {
                                        activeQuestionIndex < states.count ? states[activeQuestionIndex].otherText : ""
                                    },
                                    set: { val in
                                        if activeQuestionIndex < states.count {
                                            states[activeQuestionIndex].otherText = val
                                            if !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                // 自填有输入时清空普通选项勾选，以自填为准
                                                if !isMulti {
                                                    states[activeQuestionIndex].selected.removeAll()
                                                }
                                                states[activeQuestionIndex].otherSelected = true
                                            }
                                        }
                                    }
                                ))
                                .font(.system(size: 14))
                                .foregroundColor(CSSThemeVariables.textMain(isDark: isDark))
                                .submitLabel(.send)
                                .onSubmit {
                                    if canSubmit && isSessionReady {
                                        submit()
                                    }
                                }

                                if !states[activeQuestionIndex].otherText.isEmpty {
                                    Button {
                                        states[activeQuestionIndex].otherText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(CSSThemeVariables.textDim(isDark: isDark))
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .frame(minHeight: 52)

                            Divider()
                                .background(CSSThemeVariables.divider(isDark: isDark))
                        }
                    }
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.46)

                // 抽屉底部操作栏 (Foot)
                HStack(spacing: 12) {
                    if questions.count > 1 {
                        // 多题目时的上一题 / 下一题切换
                        if activeQuestionIndex > 0 {
                            Button("上一题") {
                                activeQuestionIndex -= 1
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(CSSThemeVariables.textDim(isDark: isDark))
                            .padding(.leading, 20)
                        }

                        if activeQuestionIndex < questions.count - 1 {
                            Button("下一题") {
                                activeQuestionIndex += 1
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(CSSThemeVariables.accent(isDark: isDark))
                            .padding(.leading, activeQuestionIndex == 0 ? 20 : 0)
                        }
                    }

                    Spacer()

                    // 右下角大胶囊发送按钮 (Send Button)
                    Button(action: submit) {
                        Text("发送")
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(2)
                            .foregroundColor(.white)
                            .frame(minWidth: 132, minHeight: 48)
                            .background(CSSThemeVariables.accent(isDark: isDark))
                            .clipShape(Capsule())
                    }
                    .disabled(!canSubmit || !isSessionReady)
                    .opacity((canSubmit && isSessionReady) ? 1.0 : 0.45)
                    .padding(.trailing, 20)
                }
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .background(CSSThemeVariables.card(isDark: isDark))
            .clipShape(AskRoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
            .shadow(color: CSSThemeVariables.sheetShadow(isDark: isDark), radius: 24, x: 0, y: -8)
            .transition(.move(edge: .bottom))
        }
        .onAppear {
            if let payload, states.count != payload.questions.count {
                states = Array(repeating: QuestionAnswerState(), count: payload.questions.count)
            }
        }
    }

    private func toggleOption(questionIndex: Int, optionIndex: Int, isMulti: Bool) {
        guard questionIndex < states.count else { return }
        if isMulti {
            if states[questionIndex].selected.contains(optionIndex) {
                states[questionIndex].selected.remove(optionIndex)
            } else {
                states[questionIndex].selected.insert(optionIndex)
            }
        } else {
            states[questionIndex].selected = [optionIndex]
            states[questionIndex].otherSelected = false
            states[questionIndex].otherText = ""
        }
    }

    private func dismiss() {
        ToolSuspensionService.shared.respond(id: request.id, decision: .skipped)
    }

    private func submit() {
        guard let payload else { return }
        var answers: [String: Any] = [:]
        for (idx, q) in payload.questions.enumerated() {
            let st = idx < states.count ? states[idx] : QuestionAnswerState()
            let isMulti = q.type == "multi"
            if st.skipped {
                answers[q.id] = NSNull()
                continue
            }
            let otherText = st.otherText.trimmingCharacters(in: .whitespacesAndNewlines)
            if isMulti {
                var picked = st.selected.sorted().compactMap { i in
                    i < q.options.count ? q.options[i] : nil
                }
                if !otherText.isEmpty { picked.append(otherText) }
                answers[q.id] = picked.isEmpty ? NSNull() : picked
            } else {
                if !otherText.isEmpty {
                    answers[q.id] = otherText
                } else if let first = st.selected.sorted().first, first < q.options.count {
                    answers[q.id] = q.options[first]
                } else {
                    answers[q.id] = NSNull()
                }
            }
        }
        let json = (try? JSONSerialization.data(withJSONObject: answers, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        ToolSuspensionService.shared.respond(id: request.id, decision: .answered(json))
    }
}

/// 单题的作答状态
private struct QuestionAnswerState {
    var selected: Set<Int> = []
    var otherSelected = false
    var otherText = ""
    var skipped = false
}

extension View {
    func askUserDialog(vm: AIChatViewModel) -> some View {
        modifier(AskUserDialogModifier(vm: vm))
    }
}
