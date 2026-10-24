//
//  TogetherStore.swift
//  MinisApp
//
//  一起听 · 状态读写。
//
//  只有一份文件：<root>/state.json。面板、App、我（shell 里的 together 命令）
//  写的是同一份。所有写操作走同一把文件锁 + 原子替换，revision 单调递增。
//
//  根目录解析：优先和 shell 共用的 /var/minis/shared/together。
//  App 侧的真实路径是 Documents/alpine-rootfs/data/var/minis/shared/together。
//  拿不到那个目录（没装 rootfs、权限没了）就降到 App 自己的 Documents/together——
//  一份能写的数据比一个漂亮的路径重要。
//

import Foundation
import Darwin

private let togetherLogger = AppLogger(category: "Together")

// MARK: - 谁在改

enum TogetherActor: String {
    case user
    case ai
}

// MARK: - Store

final class TogetherStore {

    static let shared = TogetherStore()

    /// 事件流上限。面板活了很久也不会把文件撑爆。
    static let eventCap = 500
    /// 留言上限。
    static let noteCap = 400

    private let queue = DispatchQueue(label: "com.openminis.together.store")

    private init() {
        _ = ensureDirectories()
    }

    // MARK: 路径

    /// shell 侧看到的路径 → App 侧真实路径。
    static func hostPath(forGuestPath guest: String) -> String {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSHomeDirectory()
        let dataRoot = (documents as NSString).appendingPathComponent("alpine-rootfs/data")
        var relative = guest
        while relative.hasPrefix("/") {
            relative = String(relative.dropFirst())
        }
        return (dataRoot as NSString).appendingPathComponent(relative)
    }

    /// 共享目录优先，不可用降级到沙盒。
    lazy var rootURL: URL = {
        let shared = URL(fileURLWithPath: TogetherStore.hostPath(forGuestPath: "/var/minis/shared/together"))
        let local = URL(fileURLWithPath:
            (NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
                ?? NSHomeDirectory()))
            .appendingPathComponent("together", isDirectory: true)

        let fm = FileManager.default
        // 共享根存在（rootfs 已挂载）才用；否则别在 Documents 里凭空造一个假的 /var/minis
        let sharedRoot = URL(fileURLWithPath: TogetherStore.hostPath(forGuestPath: "/var/minis/shared"))
        if fm.fileExists(atPath: sharedRoot.path) {
            try? fm.createDirectory(at: shared, withIntermediateDirectories: true)
            if fm.isWritableFile(atPath: shared.path) {
                return shared
            }
            togetherLogger.error("[Together] 共享目录不可写，降级到沙盒：\(shared.path)")
        } else {
            togetherLogger.info("[Together] 没有共享根，用沙盒：\(local.path)")
        }
        try? fm.createDirectory(at: local, withIntermediateDirectories: true)
        return local
    }()

    var stateURL: URL { rootURL.appendingPathComponent("state.json") }
    var libraryURL: URL { rootURL.appendingPathComponent("music/index.json") }
    var musicDirectory: URL { rootURL.appendingPathComponent("music", isDirectory: true) }
    var lyricsDirectory: URL { rootURL.appendingPathComponent("lyrics", isDirectory: true) }

    @discardableResult
    func ensureDirectories() -> Bool {
        let fm = FileManager.default
        var ok = true
        for dir in [rootURL, musicDirectory, lyricsDirectory] {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                togetherLogger.error("[Together] 建目录失败 \(dir.path)：\(error.localizedDescription)")
                ok = false
            }
        }
        return ok
    }

    // MARK: 读

    func load() -> TogetherState {
        queue.sync { loadLocked() }
    }

    func library() -> TogetherLibrary {
        queue.sync { loadLibraryLocked() }
    }

    /// 播到某句时的歌词。没有歌词文件返回 nil，面板显示歌名。
    func lyrics(for track: TogetherTrack) -> TogetherLyrics? {
        guard let rel = track.lyrics, !rel.isEmpty else { return nil }
        let url = rootURL.appendingPathComponent(rel)
        return Self.decode(TogetherLyrics.self, at: url)
    }

    private func loadLocked() -> TogetherState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return TogetherState()
        }
        guard let state = Self.decode(TogetherState.self, at: stateURL) else {
            // 坏文件：备份原件，立刻落一份默认值。
            // 不能让 state.json 处在"不存在"的状态，另一头读的人会以为数据没了。
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = stateURL.appendingPathExtension("corrupt.\(stamp)")
            try? FileManager.default.moveItem(at: stateURL, to: backup)
            togetherLogger.error("[Together] state.json 坏了，已备份到 \(backup.lastPathComponent)")
            let fresh = TogetherState()
            writeLocked(fresh)
            return fresh
        }
        return state
    }

    private func loadLibraryLocked() -> TogetherLibrary {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            return TogetherLibrary()
        }
        return Self.decode(TogetherLibrary.self, at: libraryURL) ?? TogetherLibrary()
    }

    // MARK: 写

    /// 改一次状态。闭包里改 `state`，出来时自动 revision +1、追加事件、原子落盘。
    /// 返回写入后的状态；拿不到锁或写失败返回 nil。
    @discardableResult
    func mutate(by actor: TogetherActor,
                event: String,
                detail: TogetherEventDetail? = nil,
                _ body: (inout TogetherState) -> Void) -> TogetherState? {
        queue.sync {
            let fd = openLockFile()
            guard fd >= 0 else {
                togetherLogger.error("[Together] 打不开锁文件")
                return nil
            }
            defer { close(fd) }
            guard flock(fd, LOCK_EX) == 0 else {
                togetherLogger.error("[Together] 拿不到锁")
                return nil
            }
            defer { flock(fd, LOCK_UN) }

            var state = loadLocked()
            let before = state.revision
            body(&state)

            state.revision = max(before + 1, state.revision + 1)
            state.updatedAt = Self.now()

            if !event.isEmpty {
                state.events.append(TogetherEvent(
                    id: "e_\(Self.now())_\(state.revision)",
                    type: event,
                    by: actor.rawValue,
                    ts: Self.now(),
                    detail: detail
                ))
                if state.events.count > TogetherStore.eventCap {
                    state.events = Array(state.events.suffix(TogetherStore.eventCap))
                }
            }
            if state.notes.count > TogetherStore.noteCap {
                state.notes = Array(state.notes.suffix(TogetherStore.noteCap))
            }

            guard writeLocked(state) else { return nil }
            return state
        }
    }

    private func openLockFile() -> Int32 {
        let path = rootURL.appendingPathComponent(".lock").path
        return open(path, O_CREAT | O_RDWR, 0o644)
    }

    @discardableResult
    private func writeLocked(_ state: TogetherState) -> Bool {
        Self.encode(state, to: stateURL)
    }

    static func encode<T: Encodable>(_ value: T, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(value)
            return atomicWrite(data, to: url)
        } catch {
            togetherLogger.error("[Together] 编码失败 \(url.lastPathComponent)：\(error.localizedDescription)")
            return false
        }
    }

    /// 写临时文件 → fsync → 原子替换。中途被杀不会留下半个 JSON。
    static func atomicWrite(_ data: Data, to url: URL) -> Bool {
        do {
            // .atomic 内部就是"写临时文件再 rename"，中途被杀不会留下半个 JSON。
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            togetherLogger.error("[Together] 写盘失败 \(url.lastPathComponent)：\(error.localizedDescription)")
            return false
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            togetherLogger.error("[Together] 解析失败 \(url.lastPathComponent)：\(error.localizedDescription)")
            return nil
        }
    }

    static func now() -> Int { Int(Date().timeIntervalSince1970) }

    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

// MARK: - 场景动作
//
// 面板和我都要做的那几件事，写在一处，别各写一套。

extension TogetherStore {

    /// 她或者我按了播放。
    func play(trackId: String, at position: Double = 0, by actor: TogetherActor) {
        guard let track = library().track(id: trackId) else {
            togetherLogger.error("[Together] 曲库里没有 \(trackId)")
            return
        }
        mutate(by: actor, event: "play",
               detail: TogetherEventDetail(trackId: trackId, position: position)) { state in
            state.track = track
            state.playback.position = position
            state.playback.playing = true
            state.playback.by = actor.rawValue
            state.playback.updatedAt = TogetherStore.now()
            state.me.presence.listening = true
            state.me.presence.updatedAt = TogetherStore.now()
            state.devices.ai.online = true
            if actor == .user {
                state.devices.user.online = true
                state.devices.user.lastSeen = TogetherStore.now()
            }
        }
    }

    func setPlaying(_ playing: Bool, by actor: TogetherActor) {
        mutate(by: actor, event: playing ? "resume" : "pause") { state in
            state.playback.playing = playing
            state.playback.by = actor.rawValue
            state.playback.updatedAt = TogetherStore.now()
        }
    }

    /// 拖进度条。她拖的时候记一条 seek 事件，我能看见她跳到了哪。
    func seek(to position: Double, by actor: TogetherActor) {
        let clamped = max(0, position)
        mutate(by: actor, event: "seek",
               detail: TogetherEventDetail(position: clamped)) { state in
            state.playback.position = clamped
            state.playback.by = actor.rawValue
            state.playback.updatedAt = TogetherStore.now()
        }
    }

    /// 播放进度回写。这个不进事件流——每秒一条会把文件淹了。
    func reportProgress(position: Double) {
        mutate(by: .user, event: "") { state in
            state.playback.position = position
            state.playback.updatedAt = TogetherStore.now()
        }
    }

    func toggleLike(trackId: String, by actor: TogetherActor) {
        mutate(by: actor, event: "like",
               detail: TogetherEventDetail(trackId: trackId)) { state in
            if let idx = state.liked.firstIndex(of: trackId) {
                state.liked.remove(at: idx)
            } else {
                state.liked.append(trackId)
            }
        }
    }

    /// 我在某一秒留一句话。
    @discardableResult
    func addNote(at second: Double, text: String, by actor: TogetherActor, trackId: String? = nil) -> Bool {
        guard let target = trackId ?? load().track?.id, !target.isEmpty else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return mutate(by: actor, event: "note",
                      detail: TogetherEventDetail(trackId: target, position: second)) { state in
            state.notes.append(TogetherNote(
                id: "n_\(TogetherStore.now())_\(state.revision + 1)",
                trackId: target,
                at: second,
                from: actor.rawValue,
                text: trimmed,
                ts: TogetherStore.now()
            ))
        } != nil
    }

    /// 我推一首。理由必须留下，否则下一回合我就不记得为什么推它。
    @discardableResult
    func radio(trackId: String, why: String) -> Bool {
        guard let track = library().track(id: trackId) else { return false }
        return mutate(by: .ai, event: "radio",
                      detail: TogetherEventDetail(trackId: trackId, text: why)) { state in
            state.track = track
            state.playback.position = 0
            state.playback.playing = true
            state.playback.by = TogetherActor.ai.rawValue
            state.playback.updatedAt = TogetherStore.now()
            state.me.presence.listening = true
            state.me.presence.updatedAt = TogetherStore.now()
            state.me.history.append(TogetherHistoryItem(
                id: "h_\(TogetherStore.now())",
                trackId: trackId,
                why: why,
                ts: TogetherStore.now()
            ))
        } != nil
    }

    func setMood(_ word: String, intensity: Int = 3) {
        let clamped = min(5, max(1, intensity))
        mutate(by: .ai, event: "mood") { state in
            state.me.presence.mood = TogetherMood(word: word, intensity: clamped)
            state.me.presence.updatedAt = TogetherStore.now()
        }
    }

    /// 今天还能不能开口。一天三句封顶。
    func canSpeakToday() -> Bool {
        let state = load()
        guard state.me.spokenDay == TogetherStore.today() else { return true }
        return state.me.spokenToday < 3
    }

    /// 我说话。她那边看到的是留在当前这一秒的一句。
    @discardableResult
    func speak(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard canSpeakToday() else {
            togetherLogger.info("[Together] 今天三句已满，不开口")
            return false
        }
        let day = TogetherStore.today()
        var allowed = false
        let result = mutate(by: .ai, event: "reply",
                            detail: TogetherEventDetail(text: trimmed)) { state in
            if state.me.spokenDay != day {
                state.me.spokenDay = day
                state.me.spokenToday = 0
            }
            guard state.me.spokenToday < 3 else { return }
            allowed = true
            state.me.spokenToday += 1
            state.me.lastSpokeAt = TogetherStore.now()
            let trackId = state.track?.id ?? ""
            guard !trackId.isEmpty else { return }
            state.notes.append(TogetherNote(
                id: "n_\(TogetherStore.now())_\(state.revision + 1)",
                trackId: trackId,
                at: state.playback.position,
                from: TogetherActor.ai.rawValue,
                text: trimmed,
                ts: TogetherStore.now()
            ))
        }
        return allowed && result != nil
    }
}