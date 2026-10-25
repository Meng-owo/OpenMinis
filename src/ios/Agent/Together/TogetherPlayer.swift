//
//  TogetherPlayer.swift
//  MinisApp
//
//  一起听 · 音频引擎。
//
//  为什么不复用 GlobalAudioPlayer：那是语音气泡的引擎，逻辑绑在
//  "tts-xxx" 文件名和续听上，音乐需要的是换歌从头、长播、精确 seek。
//  两个引擎各管各的，锁屏那一层（VoiceNowPlaying）统一路由。
//
//  后台播放不靠这里：AudioSessionCoordinator 管 session，
//  Info.plist 的 audio background mode 已经在。这里只负责"声音从哪出"。
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class TogetherPlayer: ObservableObject {

    static let shared = TogetherPlayer()
    private init() {
        // 一启动就跟：面板关着的时候我换歌，她那边也该听见。
        startFollowing()
    }

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var track: TogetherTrack?

    /// 真有一个播放器活着（暂停也算）。锁屏那一层靠这个判断该听谁的。
    var isActive: Bool { player != nil }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endToken: NSObjectProtocol?
    private var lastReportedSecond: Double = -1
    private var didSuspendSilentAudio = false
    /// 跟随：上一次处理过的事件 id。
    /// 不能用 revision——播放进度回写也会涨 revision，会把同一条 play 反复触发。
    private var seenEventId = ""
    private var followTimer: Timer?
    /// 语音播报让过路：记下"是我暂停的"，说完才敢自动接着放。
    private var duckedForVoice = false
    private var voiceObservers: [NSObjectProtocol] = []
    private var didStartFollow = false
    private let store = TogetherStore.shared
    private let logger = AppLogger(category: "TogetherPlayer")

    // MARK: 播放

    /// 换一首。position 是起始秒数。
    func load(_ newTrack: TogetherTrack, from position: Double = 0) {
        guard let url = store.audioURL(for: newTrack) else {
            logger.error("[Together] \(newTrack.title) 没有音频文件")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("[Together] 文件不存在：\(url.path)")
            return
        }

        teardown()
        track = newTrack
        duration = newTrack.duration > 0 ? newTrack.duration : 0

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .pause
        player = p

        // 后台被系统续命靠这条静音轨；开始播才拿，停就还回去。
        if !didSuspendSilentAudio {
            BackgroundKeepAliveManager.shared.suspendSilentAudioForMedia()
            didSuspendSilentAudio = true
        }
        AudioSessionCoordinator.shared.begin(.mediaAttachment)

        addPeriodicObserver()
        addEndObserver()

        if position > 0 {
            p.seek(to: CMTime(seconds: position, preferredTimescale: 600),
                   toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = position
        } else {
            currentTime = 0
        }
        p.play()
        isPlaying = true
        VoiceNowPlaying.shared.refresh()

        // 扫目录进来的歌没有时长，读一次回填，列表就不会一直显示 0:00。
        let trackId = newTrack.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let d = try? await item.asset.load(.duration) {
                let secs = d.seconds
                if secs.isFinite, secs > 0 {
                    if self.duration < secs { self.duration = secs }
                    self.store.updateDuration(trackId: trackId, duration: secs)
                }
            }
        }
    }

    func play() {
        guard let p = player else { return }
        if let d = p.currentItem?.duration.seconds, !d.isNaN, d > 0 {
            duration = d
        }
        // 播完了再点播放，从头开始
        if duration > 0, currentTime >= duration - 0.2 {
            p.seek(to: .zero)
            currentTime = 0
        }
        p.play()
        isPlaying = true
        VoiceNowPlaying.shared.refresh()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        reportProgress(force: true)
        VoiceNowPlaying.shared.refresh()
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to seconds: Double) {
        guard let p = player else { return }
        let maxTime = duration > 0 ? min(seconds, duration) : seconds
        let clamped = max(0, maxTime)
        p.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
               toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        reportProgress(force: true)
        VoiceNowPlaying.shared.refresh()
    }

    func stop() {
        teardown()
        track = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        VoiceNowPlaying.shared.refresh()
    }

    /// App 重开时把上次那首装回来。
    /// 只有 state 记着"在放"才真的响——记着暂停就装好不响，别自己冒出来。
    func restoreIfNeeded() {
        guard !isActive else { return }
        let state = store.load()
        guard let t = state.track, t.file != nil else { return }
        load(t, from: state.playback.position)
        if !state.playback.playing {
            pause()
        }
    }

    // MARK: 跟随 AI
    //
    // 我把遥控器递过去之后，她那边得真的换歌——面板关着也要跟。
    // 不轮询进度（进度是本机播出来的事实，反过来写会把播放器拽回去），
    // 只跟三个动作：换歌 / 播停 / 拖动。这三个的 by == "ai" 才动。

    func startFollowing() {
        observeVoice()
        guard !didStartFollow else { return }
        didStartFollow = true
        seenEventId = store.load().events.last?.id ?? ""
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.followTick() }
        }
    }

    func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
        didStartFollow = false
    }

    private func followTick() {
        let state = store.load()
        guard let last = state.events.last else { return }
        guard last.id != seenEventId else { return }
        seenEventId = last.id

        // 遥控器在谁手里，就听谁的。
        // 之前只看事件是谁发的，递给我之后她那边还会被 AI 的事件拽走。
        let controller = state.playback.by

        // 递遥控器本身就是一条事件：谁接手，本机就归谁。
        if last.type == "handoff" { return }

        guard controller == "ai", last.by == "ai" else { return }

        switch last.type {
        case "play", "radio":
            guard let t = state.track else { return }
            let target = state.playback.position
            if track?.id != t.id {
                load(t, from: target)
            } else if abs(currentTime - target) > 2 {
                seek(to: target)
            }
            if !isPlaying { play() }

        case "pause":
            if isPlaying { pause() }

        case "resume":
            if !isPlaying { play() }

        case "seek":
            if let pos = last.detail?.position, abs(currentTime - pos) > 1.5 {
                seek(to: pos)
            }

        default:
            break
        }
    }

    // MARK: 内部

    private func addPeriodicObserver() {
        guard let p = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                guard !seconds.isNaN else { return }
                self.currentTime = seconds
                if let d = p.currentItem?.duration.seconds, !d.isNaN, d > 0 {
                    self.duration = d
                }
                // 每跨过一整秒才往盘上写一次：面板要的是"歌还在放、进度还在"，
                // 不是每秒一条。
                if abs(seconds - self.lastReportedSecond) >= 3 {
                    self.lastReportedSecond = seconds
                    self.reportProgress()
                }
            }
        }
    }

    // MARK: 语音让路
    //
    // 语音播报和音乐抢同一个 AVAudioSession：不处理就是语音一响音乐乱跳，
    // 说完了也回不来。规矩是——语音开始我暂停，语音结束我接着放，
    // 只在我本来是"在放"的时候才恢复，她手动停的不要自己响。

    private func observeVoice() {
        guard voiceObservers.isEmpty else { return }
        let center = NotificationCenter.default
        voiceObservers.append(center.addObserver(
            forName: AudioSessionCoordinator.replyTTSStartedNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.duckedForVoice = true
                self.pause()
            }
        })
        voiceObservers.append(center.addObserver(
            forName: AudioSessionCoordinator.replyTTSEndedNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.duckedForVoice else { return }
                self.duckedForVoice = false
                self.play()
            }
        })
    }

    private func addEndObserver() {
        guard let item = player?.currentItem else { return }
        endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleTrackEnd()
            }
        }
    }

    /// 一首放完：单曲循环就重放；否则顺序（或随机）接着下一首。
    /// 跟音乐 App 一样，别停在最后一句等人点。
    private func handleTrackEnd() {
        let state = store.load()

        if state.playback.repeatOne {
            seek(to: 0)
            play()
            store.reportProgress(position: 0)
            return
        }

        let lib = store.library()
        guard !lib.tracks.isEmpty else {
            isPlaying = false
            currentTime = duration
            reportProgress(force: true)
            VoiceNowPlaying.shared.refresh()
            return
        }

        let currentId = track?.id ?? ""
        let next: TogetherTrack
        if state.playback.shuffle {
            let pool = lib.tracks.filter { $0.id != currentId }
            next = pool.randomElement() ?? lib.tracks[0]
        } else if let i = lib.tracks.firstIndex(where: { $0.id == currentId }) {
            next = lib.tracks[(i + 1) % lib.tracks.count]
        } else {
            next = lib.tracks[0]
        }

        load(next, from: 0)
        store.play(trackId: next.id, at: 0, by: .user)
    }

    private func reportProgress(force: Bool = false) {
        // 面板关着、App 在后台的时候也要把进度落盘，冷启动才能接着放
        guard force || lastReportedSecond >= 0 else { return }
        store.reportProgress(position: currentTime)
    }

    private func teardown() {
        voiceObservers.forEach { NotificationCenter.default.removeObserver($0) }
        voiceObservers.removeAll()
        if let token = endToken {
            NotificationCenter.default.removeObserver(token)
            endToken = nil
        }
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        if didSuspendSilentAudio {
            BackgroundKeepAliveManager.shared.resumeSilentAudioForMedia()
            didSuspendSilentAudio = false
        }
    }
}

// MARK: - 锁屏用的标题

extension TogetherPlayer {
    var nowPlayingTitle: String {
        let t = track?.title ?? ""
        return t.isEmpty ? "一起听" : t
    }

    var nowPlayingArtist: String {
        let a = track?.artist ?? ""
        return a.isEmpty ? "一起听" : a
    }
}