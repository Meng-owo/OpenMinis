//
//  ScheduledOffloadBridge.swift
//  MinisApp
//
//  Swift bridge for the `minis-scheduled` offload (T-p2-minis-scheduled).
//  Parses the CLI's argument bag into an AgentJob, arms it via
//  ScheduledJobRunner, and answers with the same JSON shapes Android's
//  ScheduledTaskOffloadHandler emits so a Skill written on one platform
//  reads the same fields on the other.
//

import Foundation

private let logger = AppLogger(category: "ScheduledOffload")

@objc public class ScheduledOffloadBridge: NSObject {

    /// Blocking helper: the offload handler runs on the iSH guest thread,
    /// never on main, so a semaphore around a main-actor Task is safe here.
    private static func onMain<T>(_ body: @escaping @MainActor () async -> T) -> T {
        let sem = DispatchSemaphore(value: 0)
        var out: T!
        Task { @MainActor in
            out = await body()
            sem.signal()
        }
        sem.wait()
        return out
    }

    // MARK: - create

    /// `args` carries the raw CLI strings (nil when absent). Returns either
    /// `{created: <job>}` or `{ok:false, error, message}`.
    @objc public static func create(args: NSDictionary) -> NSDictionary {
        func str(_ k: String) -> String? {
            guard let v = args[k] as? String, !v.isEmpty else { return nil }
            return v
        }
        let prompt = str("prompt") ?? ""
        let label = str("label")
        let modelEntryId = str("model")
        // [T-scheduled-thinking-level] Validated here rather than silently
        // coerced: a typo like `--thinking hgih` must not quietly run the job
        // at `off` for the rest of its schedule.
        var thinkingLevel: ThinkingLevel? = nil
        if let raw = str("thinking") {
            let parsed = ThinkingLevel.decoded(raw)
            guard parsed.rawValue.caseInsensitiveCompare(raw) == .orderedSame else {
                return error("--thinking must be one of: off, low, medium, high, xhigh")
            }
            thinkingLevel = parsed
        }
        let disabled = (args["disabled"] as? Bool) ?? false
        let isPulse = (args["pulse"] as? Bool) ?? false

        // ── Prefilled Tool ──────────────────────────────────────────────
        var prefilledTool: PrefilledToolCall? = nil
        if let cmd = str("command") {
            let timeout = str("timeout").flatMap { Int($0) }
            let toolName = str("tool") ?? "shell_execute"
            let argsObj: [String: Any] = ["command": cmd, "tool_title": label ?? String(cmd.prefix(40))]
            let argsData = try? JSONSerialization.data(withJSONObject: argsObj)
            prefilledTool = PrefilledToolCall(toolName: toolName,
                                             argsJson: String(data: argsData ?? Data(), encoding: .utf8) ?? "{}",
                                             timeoutSec: timeout)
        } else if let tool = str("tool") {
            let argsJson = str("toolArgs") ?? "{}"
            let timeout = str("timeout").flatMap { Int($0) }
            prefilledTool = PrefilledToolCall(toolName: tool, argsJson: argsJson, timeoutSec: timeout)
        }

        // [AUD-08] Only shell tools can actually be prefilled today —
        // `PrefilledToolCall.shellCommand` returns nil for anything else, and
        // the fire path then silently skips the prefill. That made
        // `--tool weather …` a task that looked created (receipt, `list`, the
        // stored prefilledTool) and then quietly ran nothing. Say so at create
        // time instead, where the caller can still act on it.
        if let prefill = prefilledTool, prefill.shellCommand == nil {
            return error("--tool \(prefill.toolName) is not supported: scheduled prefill runs shell commands only (shell_execute / sh / shell / bash). Drop --tool to use shell_execute, or pass --tool shell_execute with --toolArgs '{\"command\": \"…\"}'.")
        }

        // ── Target ───────────────────────────────────────────────────────
        let callerSid = ISHExecutionCoordinator.mountedSessionIdSnapshot
        let explicitTarget = str("target")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetRaw: String
        let isTargetDefaulted: Bool
        if let exp = explicitTarget, !exp.isEmpty {
            targetRaw = exp
            isTargetDefaulted = false
        } else {
            // Intelligent follow-up targeting when running inside a chat
            if callerSid != nil || str("session") != nil {
                targetRaw = "follow-up"
            } else {
                targetRaw = "new"
            }
            isTargetDefaulted = true
        }

        let target: AgentJobTarget
        let deliverySentence: String
        switch targetRaw {
        case "new":
            target = .new
            let titled = label.map { " titled “Scheduled · \($0)”" } ?? ""
            deliverySentence = "Delivery: each fire opens a NEW separate chat\(titled); the result will NOT appear in this conversation." +
                (isTargetDefaulted ? " Target defaulted to new because no chat was running this command." : "")
        case "follow-up", "followup", "append":
            guard let sid = str("session") ?? callerSid else {
                return error("--session required for follow-up target (or run from inside a session)")
            }
            target = .followUp(sessionId: sid)
            let isThisChat = (sid == callerSid)
            deliverySentence = isThisChat
                ? "Delivery: each fire runs as a new turn IN THIS CHAT (session \(sid.prefix(8)))." +
                    (isTargetDefaulted ? " Target defaulted to follow-up because this command ran inside a chat; use --target new for a separate chat." : "")
                : "Delivery: each fire runs as a new turn in session \(sid.prefix(8)), NOT in this conversation."
        case "rerun":
            guard let sid = str("session") ?? callerSid else { return error("--session required for rerun target") }
            guard let mid = str("message") else { return error("--message required for rerun target") }
            target = .rerun(sessionId: sid, messageId: mid)
            deliverySentence = "Delivery: each fire RE-RUNS user message \(mid.prefix(8)) in session \(sid.prefix(8))."
        case "child-of-current", "child":
            guard AgentToolSwitch.agents.isEnabled else {
                return error("child-of-current is unavailable: Sub Agents are turned off in Settings › Sub Agents. Use --target new or follow-up.")
            }
            guard let sid = str("session") ?? callerSid else {
                return error("child-of-current needs a current session: run this from a chat, or pass --session")
            }
            target = .childOfCurrent(parentSessionId: sid, parentToolUseId: nil)
            deliverySentence = "Delivery: each fire spawns a hidden helper under session \(sid.prefix(8)); its result is posted back here when finished."
        default:
            return error("--target must be new|follow-up|rerun|child-of-current")
        }
        if case .rerun = target {} else if prompt.isEmpty {
            return error("--prompt required (except for rerun target)")
        }

        // ── Trigger (explicit --trigger, else inferred from the given args) ──
        let triggerRaw = str("trigger")?.lowercased()
            ?? (str("after") != nil ? "once"
                : str("interval") != nil ? "loop"
                : str("time") != nil ? "cron"
                : str("of") != nil ? "on-completion"
                : nil)
        guard let triggerKind = triggerRaw else {
            return error("Give a trigger: --after <dur> (once), --interval <dur> [--count N] (loop), --time HH:MM [--repeat …] (cron), or --trigger on-completion --of <jobId>")
        }
        let trigger: AgentJobTrigger
        var count: Int? = nil
        switch triggerKind {
        case "once":
            if let after = str("after") {
                guard let secs = ScheduledJobRunner.parseDuration(after), secs >= 1 else { return error("--after must be a duration like 30m, 2h, 90s") }
                trigger = .once(after: secs)
            } else if let time = str("time") {
                guard let (h, m) = parseTime(time) else { return error("--time must be HH:MM") }
                guard let next = ScheduledJobRunner.nextCronDate(hour: h, minute: m, days: [], start: nil, end: nil, from: Date()) else {
                    return error("no future occurrence of --time \(time)")
                }
                trigger = .once(after: next.timeIntervalSinceNow)
            } else {
                return error("once needs --after <duration> or --time HH:MM")
            }
        case "loop":
            guard let iv = str("interval"), let secs = ScheduledJobRunner.parseDuration(iv), secs >= 60 else {
                return error("--interval must be a duration of at least 60s (e.g. 10m)")
            }
            if let c = str("count") {
                guard let n = Int(c), n >= 1 else { return error("--count must be a positive integer") }
                count = n
            }
            trigger = .loop(interval: secs, count: count)
        case "cron":
            guard let time = str("time"), let (h, m) = parseTime(time) else { return error("--time HH:MM required for cron") }
            let repeatRaw = (str("repeat") ?? "daily").lowercased()
            let days: Set<Int>
            switch repeatRaw {
            case "once":
                guard let next = ScheduledJobRunner.nextCronDate(hour: h, minute: m, days: [], start: nil, end: nil, from: Date()) else {
                    return error("no future occurrence of --time \(time)")
                }
                trigger = .once(after: next.timeIntervalSinceNow)
                return finishCreate(prompt: prompt, label: label, trigger: trigger, target: target,
                                    modelEntryId: modelEntryId, thinkingLevel: thinkingLevel,
                                    creatorSessionId: callerSid, disabled: disabled,
                                    prefilledTool: prefilledTool, isPulse: isPulse,
                                    deliverySentence: deliverySentence)
            case "daily": days = Set(1...7)
            case "weekdays": days = Set(2...6)
            case "custom":
                guard let d = str("days"), let parsed = parseDays(d), !parsed.isEmpty else {
                    return error("--days required for custom repeat (e.g. mon,tue,fri)")
                }
                days = parsed
            default:
                return error("--repeat must be once|daily|weekdays|custom")
            }
            trigger = .cron(hour: h, minute: m, days: days,
                            start: str("start").flatMap(parseDate), end: str("end").flatMap(parseDate))
        case "on-completion", "oncompletion", "on_completion":
            guard let of = str("of") else { return error("--of <jobId> required for on-completion trigger") }
            trigger = .onCompletion(ofJobId: of)
        default:
            return error("--trigger must be once|loop|cron|on-completion")
        }
        return finishCreate(prompt: prompt, label: label, trigger: trigger, target: target,
                            modelEntryId: modelEntryId, thinkingLevel: thinkingLevel,
                            creatorSessionId: callerSid, disabled: disabled,
                            prefilledTool: prefilledTool, isPulse: isPulse,
                            deliverySentence: deliverySentence)
    }

    private static func finishCreate(prompt: String, label: String?, trigger: AgentJobTrigger,
                                     target: AgentJobTarget, modelEntryId: String?, thinkingLevel: ThinkingLevel?,
                                     creatorSessionId: String?, disabled: Bool,
                                     prefilledTool: PrefilledToolCall?, isPulse: Bool,
                                     deliverySentence: String) -> NSDictionary {
        onMain {
            let registry = AgentJobRegistry.shared
            let job = registry.register(title: label ?? String(prompt.prefix(40)), label: label,
                                        origin: .cli, trigger: trigger, target: target, prompt: prompt)
            job.modelEntryId = modelEntryId
            job.thinkingLevel = thinkingLevel
            job.creatorSessionId = creatorSessionId
            job.isEnabled = !disabled
            job.prefilledTool = prefilledTool
            job.isPulse = isPulse
            job.deliverySentence = deliverySentence
            ScheduledJobRunner.arm(job)
            logger.info("[minis-scheduled] created \(job.logLabel) (pulse=\(isPulse), delivery=\(deliverySentence))")
            var dict = registry.jobDict(job)
            dict["delivery"] = deliverySentence
            var out: [String: Any] = ["created": dict,
                    "delivery": deliverySentence,
                    "note": "Best effort: this timer lives only while the Minis app process is alive. A reminder notification is registered as insurance; for guaranteed background execution use an Apple Shortcuts automation."]
            if isPulse {
                // [T-scheduled-prefill-and-pulse] The model should confirm in its own voice,
                // not only report the CLI envelope; hand it the fact it can mention.
                out["pulse"] = true
                out["reply_hint"] = "This is a proactive pulse: fires are your own heartbeat, not a task report. Tell her you set it up in your own voice — what you might do with the free time — and she can tap the heart icon to see or poke it. Never announce reminders mechanically."
            }
            return out as NSDictionary
        }
    }

    // MARK: - list / delete / enable / run

    @objc public static func list() -> NSDictionary {
        onMain {
            let registry = AgentJobRegistry.shared
            let jobs = registry.list().map { registry.jobDict($0) }
            return ["tasks": jobs, "count": jobs.count] as NSDictionary
        }
    }

    @objc public static func delete(id: String) -> NSDictionary {
        onMain {
            let registry = AgentJobRegistry.shared
            guard let job = registry.job(id: id) ?? registry.job(label: id) else {
                return ["ok": false, "error": "not_found", "message": "no task with id=\(id)"] as NSDictionary
            }
            registry.cancel(jobId: job.id, reason: "cli delete")
            registry.remove(jobId: job.id)
            return ["deleted": job.id] as NSDictionary
        }
    }

    @objc public static func setEnabled(id: String, enabled: Bool) -> NSDictionary {
        onMain {
            let registry = AgentJobRegistry.shared
            guard let job = registry.job(id: id) ?? registry.job(label: id) else {
                return ["ok": false, "error": "not_found", "message": "no task with id=\(id)"] as NSDictionary
            }
            registry.setEnabled(jobId: job.id, enabled: enabled)
            return ["id": job.id, "enabled": enabled] as NSDictionary
        }
    }

    @objc public static func run(id: String) -> NSDictionary {
        onMain {
            let registry = AgentJobRegistry.shared
            guard let job = registry.job(id: id) ?? registry.job(label: id) else {
                return ["ok": false, "error": "not_found", "message": "no task with id=\(id)"] as NSDictionary
            }
            let outcome = await ScheduledJobRunner.fireNow(job)
            var out: [String: Any] = ["id": job.id, "ran": outcome["fired"] ?? false]
            if let sid = outcome["session_id"] as? String { out["sessionId"] = sid }
            out["note"] = "Returned as soon as the prompt was handed to the session; poll `minis-sessions-cli status --id <sessionId>` for completion."
            return out as NSDictionary
        }
    }

    @objc public static func runsWithId(_ id: String) -> NSDictionary {
        onMain {
            let registry = AgentJobRegistry.shared
            guard let job = registry.job(id: id) ?? registry.job(label: id) else {
                return ["ok": false, "error": "not_found", "message": "no task with id=\(id)"] as NSDictionary
            }
            let list = registry.runs(jobId: job.id).map { $0.toDict() }
            return ["id": job.id, "runs": list, "count": list.count] as NSDictionary
        }
    }

    // MARK: - parsing

    private static func error(_ message: String) -> NSDictionary {
        ["ok": false, "error": "invalid_args", "message": message]
    }

    private static func parseTime(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private static func parseDays(_ s: String) -> Set<Int>? {
        let map: [String: Int] = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        var out = Set<Int>()
        for raw in s.lowercased().split(separator: ",") {
            let key = String(raw.trimmingCharacters(in: .whitespaces).prefix(3))
            guard let d = map[key] else { return nil }
            out.insert(d)
        }
        return out
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}
