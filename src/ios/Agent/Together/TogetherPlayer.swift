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
    /// 跟随：上一次处理过的 state revision
    private var seenRevision = 0
    private var followTimer: Timer?
    private var didStartFollow = false
    private let store = TogetherStore.shared
    private let logger = AppLogger(category: "TogetherPlayer")

    // MARK: 播放

    /// 换一首。position 是起始秒数。
    func load(_ newTrack: TogetherTrack, from position: Double = 0) {
        guard let relative = newTrack.file, !relative.isEmpty else {
            logger.error("[Together] \(newTrack.title) 没有音频文件")
            return
        }
        let url = store.rootURL.appendingPathComponent(relative)
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

    // MARK: 跟随 AI
    //
    // 我把遥控器递过去之后，她那边得真的换歌——面板关着也要跟。
    // 不轮询进度（进度是本机播出来的事实，反过来写会把播放器拽回去），
    // 只跟三个动作：换歌 / 播停 / 拖动。这三个的 by == "ai" 才动。

    func startFollowing() {
        guard !didStartFollow else { return }
        didStartFollow = true
        seenRevision = store.load().revision
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
        guard state.revision != seenRevision else { return }
        seenRevision = state.revision

        // 只跟 AI 做的动作
        guard let last = state.events.last, last.by == "ai" else { return }

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

    private func addEndObserver() {
        guard let item = player?.currentItem else { return }
        endToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
                self.reportProgress(force: true)
                VoiceNowPlaying.shared.refresh()
            }
        }
    }

    private func reportProgress(force: Bool = false) {
        // 面板关着、App 在后台的时候也要把进度落盘，冷启动才能接着放
        guard force || lastReportedSecond >= 0 else { return }
        store.reportProgress(position: currentTime)
    }

    private func teardown() {
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