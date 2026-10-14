import Foundation

/// [S3-2][evolution] Injector — shadow-first retrieval layer.
///
/// Modes (`EvolutionSettings.mode`):
///   • `.off`    → returns "" always — the prompt is byte-identical to a
///                 build that never had this file.
///   • `.shadow` → returns "" (NEVER injects) but records what WOULD have
///                 been injected into `injections` (mode="shadow") — the
///                 promotion dataset required before `active` is allowed.
///   • `.active` → returns the rendered `<evolution-tips>` fragment, built
///                 from an async-refreshed cache (the prompt builder is
///                 synchronous, so the cache warms one step ahead).
///
/// The cache refreshes at most once per `refreshInterval`, entirely off the
/// prompt path, and can be invalidated explicitly by lesson edits (S6-2).
final class EvolutionInjector: @unchecked Sendable {

    static let shared = EvolutionInjector()

    enum Constants {
        static let topK = 3
        static let refreshInterval: TimeInterval = 120
        /// Cost model from design §12: ≈3.5 chars per token.
        static let charsPerToken = 3.5
        /// Shadow-hit logging throttle — a rapid multi-turn conversation
        /// must not spam the injections table.
        static let shadowLogInterval: TimeInterval = 60
    }

    // MARK: - Pure surface (unit-tested)

    /// Which mode actually injects into the prompt. Shadow never does —
    /// that is the whole point of shadow.
    static func injects(mode: EvolutionMode) -> Bool {
        mode == .active
    }

    /// Render the would-be fragment: verified first, then injectPriority
    /// desc, capped at Top-K lines and the token budget.
    static func render(lessons: [EvolutionLesson], budgetTokens: Int) -> String {
        let eligible = lessons.filter { $0.status == .verified || $0.status == .candidate }
        guard !eligible.isEmpty, budgetTokens > 0 else { return "" }
        let ranked = rank(eligible)
        let maxChars = max(80, Int(Double(budgetTokens) * Constants.charsPerToken))
        let header = "<evolution-tips>"
        let footer = "</evolution-tips>"
        var used = header.count + footer.count + 2
        var lines: [String] = []
        for lesson in ranked.prefix(Constants.topK) {
            let tag = lesson.status == .verified ? "已验证" : "候选"
            let line = "- [\(tag)] \(lineText(for: lesson))"
            if used + line.count + 1 > maxChars { break }
            lines.append(line)
            used += line.count + 1
        }
        guard !lines.isEmpty else { return "" }
        return header + "\n" + lines.joined(separator: "\n") + "\n" + footer
    }

    /// Shared ranking: verified outranks candidate, then priority, then id.
    static func rank(_ lessons: [EvolutionLesson]) -> [EvolutionLesson] {
        lessons.sorted { a, b in
            if a.status != b.status { return a.status == .verified }
            if a.injectPriority != b.injectPriority { return a.injectPriority > b.injectPriority }
            return a.id < b.id
        }
    }

    private static func lineText(for lesson: EvolutionLesson) -> String {
        let who = lesson.taskSignature ?? "工具"
        let body = lesson.recommendation.isEmpty ? lesson.conditions : lesson.recommendation
        return "\(who)：\(body)"
    }

    // MARK: - Cache

    private let lock = NSLock()
    private var cachedLessons: [EvolutionLesson] = []
    private var cachedFragment = ""
    private var lastRefreshAt = Date.distantPast
    private var lastShadowLogAt = Date.distantPast

    /// Called from `buildTurnSystemPrompt` (MainActor, synchronous).
    func turnFragment(sessionId: String?) -> String {
        let mode = EvolutionSettings.currentMode
        guard mode != .off else { return "" }
        refreshIfStale()
        let (lessons, fragment) = lockedSnapshot()
        guard !fragment.isEmpty else { return "" }
        if mode == .shadow {
            logShadowHit(lessons: lessons, fragment: fragment)
            return ""          // ★ shadow NEVER injects
        }
        return fragment
    }

    /// Explicit invalidation after lesson edits (S6-2) or data wipes.
    func invalidate() {
        lock.lock()
        lastRefreshAt = .distantPast
        lock.unlock()
    }

    // MARK: - Internals

    private func lockedSnapshot() -> ([EvolutionLesson], String) {
        lock.lock()
        defer { lock.unlock() }
        return (cachedLessons, cachedFragment)
    }

    private func refreshIfStale() {
        guard EvolutionSettings.recordingEnabled else { return }
        let budget = EvolutionSettings.budgetTokens
        lock.lock()
        let due = Date().timeIntervalSince(lastRefreshAt) > Constants.refreshInterval
        if due { lastRefreshAt = Date() }     // claim the slot before spawning
        lock.unlock()
        guard due else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self, let store = EvolutionStore.shared else { return }
            let candidates = await store.lessons(status: .candidate)
            let verified = await store.lessons(status: .verified)
            let fragment = Self.render(lessons: candidates + verified, budgetTokens: budget)
            self.lock.lock()
            self.cachedLessons = candidates + verified
            self.cachedFragment = fragment
            self.lock.unlock()
        }
    }

    private func logShadowHit(lessons: [EvolutionLesson], fragment: String) {
        lock.lock()
        let due = Date().timeIntervalSince(lastShadowLogAt) > Constants.shadowLogInterval
        if due { lastShadowLogAt = Date() }
        lock.unlock()
        guard due else { return }

        let ranked = Self.rank(lessons.filter { $0.status == .verified || $0.status == .candidate })
            .prefix(Constants.topK)
        let perLineTokens = max(1, Int(Double(fragment.count) / Constants.charsPerToken / Double(max(1, ranked.count))))
        let entries: [(String, Int)] = ranked.map { ($0.id, perLineTokens) }
        guard !entries.isEmpty else { return }
        Task.detached(priority: .utility) {
            guard let store = EvolutionStore.shared else { return }
            for entry in entries {
                await store.insert(EvolutionInjection(
                    id: UUID().uuidString,
                    runId: nil,
                    lessonId: entry.0,
                    injectedAt: Date(),
                    tokenCost: entry.1,
                    mode: EvolutionMode.shadow.rawValue,
                    outcomeLinked: nil
                ))
            }
        }
    }
}
