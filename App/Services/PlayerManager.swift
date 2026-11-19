import Foundation
import AVFoundation
import Observation

/// 播放控制核心：播放/暂停/seek/倍速/AB 单句循环/进度持久化
@MainActor
@Observable
final class PlayerManager {
    @ObservationIgnored let player = AVPlayer()

    private(set) var currentItem: MediaItem?
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying: Bool = false
    var loopLine: SubtitleLine?
    /// 单句播放（一次性，播完自动暂停）
    private(set) var playingLine: SubtitleLine?

    var rate: Float = 1.0 {
        didSet { if isPlaying { player.rate = rate } }
    }
    var volume: Float = 1.0 {
        didSet { player.volume = volume }
    }

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var lastPersist: TimeInterval = 0
    @ObservationIgnored private var lastTick: Double?
    @ObservationIgnored private var pendingListening: Double = 0
    @ObservationIgnored private var lastNowPlayingSecond: Int = -1

    init() {
        player.actionAtItemEnd = .pause
        player.volume = volume
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.handleTimeUpdate(time)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self,
                      let pi = note.object as? AVPlayerItem,
                      pi === self.player.currentItem else { return }
                self.isPlaying = false
                self.persistProgress(force: true)
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    // MARK: - Loading

    func load(_ item: MediaItem?) {
        persistProgress(force: true)
        flushListening()
        lastTick = nil
        playingLine = nil
        loopLine = nil
        currentItem = item
        guard let item else {
            player.replaceCurrentItem(with: nil)
            currentTime = 0
            duration = 0
            isPlaying = false
            return
        }
        let asset = AVURLAsset(url: MediaStore.shared.url(for: item.fileName))
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        #if os(iOS)
        NowPlayingService.shared.configurePlaybackSession()
        NowPlayingService.shared.configureCommands(manager: self)
        updateNowPlaying()
        #endif
        // 应用设置中的默认倍速
        let defaultRate = UserDefaults.standard.double(forKey: "defaultRate")
        if defaultRate > 0 { rate = Float(defaultRate) }
        currentTime = item.currentTime
        duration = item.duration
        item.lastPlayedAt = Date()
        if item.currentTime > 0 {
            seek(to: item.currentTime)
        }
        Task {
            if let d = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(d)
                if seconds.isFinite, seconds > 0 {
                    self.duration = seconds
                    item.duration = seconds
                }
            }
        }
    }

    // MARK: - Controls

    func playPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        // 播放到结尾后再按播放：从头开始
        if duration > 0, currentTime >= duration - 0.2 {
            seek(to: 0)
        }
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        persistProgress(force: true)
        flushListening()
        updateNowPlaying()
    }

    func seek(to time: Double, autoplay: Bool = false) {
        playingLine = nil
        let upper = duration > 0 ? duration : time
        let clamped = max(0, min(time, upper))
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        )
        currentTime = clamped
        if autoplay {
            player.playImmediately(atRate: rate)
            isPlaying = true
        }
        updateNowPlaying()
    }

    func skip(_ delta: Double) {
        seek(to: currentTime + delta)
    }

    /// 点击句子：跳转并连续播放；若正在循环别的句子则取消循环
    func seekToLine(_ line: SubtitleLine) {
        if loopLine?.id != line.id { loopLine = nil }
        seek(to: line.startTime, autoplay: true)
    }

    /// 单句播放：跳到该句起点播放，播到句尾自动暂停（进度条同步联动）
    func playLine(_ line: SubtitleLine) {
        loopLine = nil
        seek(to: line.startTime, autoplay: true)
        playingLine = line
    }

    /// 取消单句播放（继续连续播放）
    func cancelLinePlay() {
        playingLine = nil
        if !isPlaying {
            player.playImmediately(atRate: rate)
            isPlaying = true
        }
    }

    /// AB 单句循环开关
    func toggleLoop(_ line: SubtitleLine) {
        playingLine = nil
        if loopLine?.id == line.id {
            loopLine = nil
        } else {
            loopLine = line
            seek(to: line.startTime, autoplay: true)
        }
    }

    // MARK: - Private

    private func handleTimeUpdate(_ time: CMTime) {
        let t = CMTimeGetSeconds(time)
        guard t.isFinite else { return }
        // 单句播放：到句尾自动暂停
        if let line = playingLine {
            if t >= line.endTime - 0.05 {
                playingLine = nil
                currentTime = min(t, line.endTime)
                pause()
                return
            }
        }
        if let line = loopLine, t >= line.endTime || t < line.startTime - 0.3 {
            seek(to: line.startTime)
            return
        }
        currentTime = t
        isPlaying = player.timeControlStatus == .playing
        persistProgress(force: false)
        accumulateListening(t)
        #if os(iOS)
        // 锁屏进度每秒刷新一次
        if Int(t) != lastNowPlayingSecond {
            lastNowPlayingSecond = Int(t)
            updateNowPlaying()
        }
        #endif
    }

    /// 统计真实播放时长（seek 跳变不计），每满 5 秒写入 DayStat
    private func accumulateListening(_ t: Double) {
        if isPlaying, let last = lastTick {
            let delta = t - last
            if delta > 0, delta < 2 { pendingListening += delta }
        }
        lastTick = t
        if pendingListening >= 5 { flushListening() }
    }

    private func flushListening() {
        if pendingListening > 0 {
            StatsTracker.shared.addListening(pendingListening)
            pendingListening = 0
        }
    }

    /// 应用切后台/退出前的检查点：落库进度与统计
    func checkpoint() {
        persistProgress(force: true)
        flushListening()
    }

    private func updateNowPlaying() {
        #if os(iOS)
        NowPlayingService.shared.updateInfo(
            title: currentItem?.title,
            duration: duration,
            elapsed: currentTime,
            rate: isPlaying ? rate : 0
        )
        #endif
    }

    private func persistProgress(force: Bool) {
        guard let item = currentItem else { return }
        let now = Date().timeIntervalSince1970
        if force || now - lastPersist > 3 {
            item.currentTime = currentTime
            lastPersist = now
        }
    }
}
