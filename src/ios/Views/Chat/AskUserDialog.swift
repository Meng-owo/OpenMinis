import SwiftUI

// MARK: - [s2-askuser] 提问小抽屉 (CSS全局变量驱动、胶囊选项与紧凑贴底设计)
//
// 视觉特性：
// 1. 弹窗高度跟着内容走，绝无大片空白区域；超长时自适应平滑滚动。
// 2. 卡片紧贴屏幕物理底部，不悬空，安全区自然延展。
// 3. 精致胶囊选项体系：每个选项为独立药丸胶囊卡片，带选中触感与弹性动效反馈。
// 4. 全局 CSS 变量系统驱动色彩与样式，零硬编码色。

// MARK: - CSS 全局色彩变量定义

@MainActor
/// Colours as CSS-style variables.
///
/// `internal`, not `public`: these take `AppearanceScope` as a default
/// argument, and a public signature cannot carry an internal type's case
/// there. Nothing outside the module used them anyway.
enum CSSThemeVariables {
    private static var studio: AppearanceStudio { .shared }

    /// --color-card / var(--dudu-card)
    /// [4-1 醒醒] 背景卡接入全局 surface 角色，支持壁纸透明度
    static func card(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        if studio.hasWallpaper(scope) {
            return studio.color(.surface, scope: scope, variant: isDark ? .dark : .light).opacity(studio.surfaceOpacity)
        }
        return studio.color(.surface, scope: scope, variant: isDark ? .dark : .light)
    }

    /// --color-bg / var(--dudu-cream)
    /// [4-1 醒醒] 背景底衬接入全局 canvas 角色
    static func bg(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.canvas, scope: scope, variant: isDark ? .dark : .light)
    }

    /// --color-text-main / var(--dudu-brown)
    /// [4-1 醒醒] 主文字接入全局 primaryText 角色
    static func textMain(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.primaryText, scope: scope, variant: isDark ? .dark : .light)
    }

    /// --color-text-dim / var(--dudu-text-dim)
    /// [4-1 醒醒] 次文字接入全局 secondaryText 角色
    static func textDim(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.secondaryText, scope: scope, variant: isDark ? .dark : .light)
    }

    /// --color-divider / var(--dudu-divider)
    /// [4-1 醒醒] 分隔线接入全局 border 角色
    static func divider(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.border, scope: scope, variant: isDark ? .dark : .light)
    }

    /// --color-accent-soft / var(--dudu-pink-soft)
    /// [4-1 醒醒] 柔和强调色由 accent 角色动态派生
    static func accentSoft(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.accent, scope: scope, variant: isDark ? .dark : .light).opacity(0.18)
    }

    /// --color-accent / var(--dudu-pink)
    /// [4-1 醒醒] 强调色接入全局 accent 角色
    static func accent(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.accent, scope: scope, variant: isDark ? .dark : .light)
    }

    /// --color-accent-fg
    /// [4-1 醒醒] 强调色前景字（按钮等）
    static func accentFg(isDark: Bool) -> Color {
        Color.white
    }

    /// --color-option-bg (输入框/未选中胶囊底色)
    /// [10-15 1-3 醒醒] 输入框与选项底色接入全局 input 角色（同族统一，不再硬编码 hex）
    static func optionBg(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.input, scope: scope, variant: isDark ? .dark : .light)
    }

    /// --color-option-border (输入框/未选中胶囊边框)
    /// [10-15 1-3 醒醒] 输入框与选项边线接入全局 border 角色
    static func optionBorder(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.border, scope: scope, variant: isDark ? .dark : .light)
    }

    /// --color-scrim / rgba(42, 42, 46, 0.28)
    static func scrim(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.65) : Color(hex: "#2A2A2E").opacity(0.28)
    }

    /// --color-sheet-shadow / rgba(139, 115, 108, 0.16)
    static func sheetShadow(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.45) : Color(hex: "#8B736C").opacity(0.16)
    }

    /// --color-danger
    /// [4-1 醒醒] 危险操作接入全局 destructive 角色
    static func danger(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.destructive, scope: scope, variant: isDark ? .dark : .light)
    }

    /// --color-danger-soft
    static func dangerSoft(isDark: Bool, scope: AppearanceScope = .chat) -> Color {
        studio.color(.destructive, scope: scope, variant: isDark ? .dark : .light).opacity(0.18)
    }

    /// --color-success
    ///
    /// [AUD-18] Delegates to the theme role instead of another pair of hex
    /// literals: `AppearanceStudio.color(_:)` already resolves per
    /// appearance, so this variable follows the user's theme and its dark
    /// variant for free. `isDark` stays in the signature because every other
    /// variable here takes it and the call sites pass it uniformly.
    static func success(isDark: Bool) -> Color { MinisTheme.success }

    /// --color-warning
    static func warning(isDark: Bool) -> Color { MinisTheme.warning }
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

// MARK: - 胶囊按压反馈样式

private struct PillOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                // 背景半透明遮罩 (Scrim)
                CSSThemeVariables.scrim(isDark: isDark)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }

                // 抽屉卡片主体 (贴底不悬空，高度随内容紧凑自适应)
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
                        .padding(.horizontal, 56)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                        // 右上角圆形关闭按钮 (Close Button)
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(CSSThemeVariables.textMain(isDark: isDark))
                                .frame(width: 40, height: 40)
                                .background(CSSThemeVariables.accentSoft(isDark: isDark))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                    }

                    // 抽屉主体：胶囊选项体系 (紧跟内容高度，底部绝无留白)
                    if let q = currentQuestion, activeQuestionIndex < states.count {
                        let isMulti = q.type == "multi"
                        let currentState = states[activeQuestionIndex]

                        if q.options.count <= 4 {
                            // 选项少时紧贴内容高度渲染，高度由内容自然撑开
                            optionsList(q: q, currentState: currentState, isMulti: isMulti)
                                .padding(.horizontal, 18)
                                .padding(.top, 6)
                                .padding(.bottom, 8)
                        } else {
                            // 选项很多时才限制最大高度并支持滚动
                            ScrollView(.vertical, showsIndicators: true) {
                                optionsList(q: q, currentState: currentState, isMulti: isMulti)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 6)
                                    .padding(.bottom, 8)
                            }
                            .frame(maxHeight: UIScreen.main.bounds.height * 0.46)
                        }
                    }

                    // 抽屉底部操作栏 (Foot)
                    HStack(spacing: 12) {
                        if questions.count > 1 {
                            // 多题目时的上一题 / 下一题切换
                            if activeQuestionIndex > 0 {
                                Button("上一题") {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                        activeQuestionIndex -= 1
                                    }
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(CSSThemeVariables.textDim(isDark: isDark))
                                .padding(.leading, 18)
                            }

                            if activeQuestionIndex < questions.count - 1 {
                                Button("下一题") {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                        activeQuestionIndex += 1
                                    }
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(CSSThemeVariables.accent(isDark: isDark))
                                .padding(.leading, activeQuestionIndex == 0 ? 18 : 0)
                            }
                        }

                        Spacer()

                        // 右下角大胶囊发送按钮 (Send Button)
                        Button(action: submit) {
                            Text("发送")
                                .font(.system(size: 15, weight: .semibold))
                                .tracking(2)
                                .foregroundColor(CSSThemeVariables.accentFg(isDark: isDark))
                                .frame(minWidth: 120, minHeight: 46)
                                .background(CSSThemeVariables.accent(isDark: isDark))
                                .clipShape(Capsule())
                        }
                        .disabled(!canSubmit || !isSessionReady)
                        .opacity((canSubmit && isSessionReady) ? 1.0 : 0.45)
                        .padding(.trailing, 18)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .padding(.bottom, max(bottomInset, 16))
                .background(
                    CSSThemeVariables.card(isDark: isDark)
                        .clipShape(AskRoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
                )
                .shadow(color: CSSThemeVariables.sheetShadow(isDark: isDark), radius: 24, x: 0, y: -8)
                .transition(.move(edge: .bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
        }
        .onAppear {
            if let payload, states.count != payload.questions.count {
                states = Array(repeating: QuestionAnswerState(), count: payload.questions.count)
            }
        }
    }

    // MARK: - 胶囊选项与自填行

    @ViewBuilder
    private func optionsList(q: AskQuestion, currentState: QuestionAnswerState, isMulti: Bool) -> some View {
        VStack(spacing: 8) {
            // 胶囊选项列表
            ForEach(Array(q.options.enumerated()), id: \.offset) { optIdx, option in
                let isSelected = currentState.selected.contains(optIdx)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        toggleOption(questionIndex: activeQuestionIndex, optionIndex: optIdx, isMulti: isMulti)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(option)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? CSSThemeVariables.textMain(isDark: isDark) : CSSThemeVariables.textMain(isDark: isDark))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)

                        Spacer(minLength: 8)

                        ZStack {
                            if isSelected {
                                Image(systemName: isMulti ? "checkmark.square.fill" : "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(CSSThemeVariables.accent(isDark: isDark))
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Circle()
                                    .strokeBorder(CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: 1.5)
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isSelected ? CSSThemeVariables.accentSoft(isDark: isDark) : CSSThemeVariables.optionBg(isDark: isDark))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? CSSThemeVariables.accent(isDark: isDark) : CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: isSelected ? 1.5 : 1.0)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PillOptionButtonStyle())
            }

            // 自填回答输入行 (同样为胶囊卡片设计)
            let hasCustomText = !currentState.otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(hasCustomText ? CSSThemeVariables.accent(isDark: isDark) : CSSThemeVariables.textDim(isDark: isDark))

                TextField("自填回答…", text: Binding(
                    get: {
                        activeQuestionIndex < states.count ? states[activeQuestionIndex].otherText : ""
                    },
                    set: { val in
                        if activeQuestionIndex < states.count {
                            states[activeQuestionIndex].otherText = val
                            if !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

                if !currentState.otherText.isEmpty {
                    Button {
                        states[activeQuestionIndex].otherText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(CSSThemeVariables.textDim(isDark: isDark))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CSSThemeVariables.optionBg(isDark: isDark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(hasCustomText ? CSSThemeVariables.accent(isDark: isDark) : CSSThemeVariables.optionBorder(isDark: isDark), lineWidth: hasCustomText ? 1.5 : 1.0)
            )
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
