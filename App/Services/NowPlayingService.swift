#if os(iOS)
import Foundation
import AVFoundation
import MediaPlayer

/// iOS 后台播放 + 锁屏/控制中心/耳机控制
@MainActor
final class NowPlayingService {
    static let shared = NowPlayingService()

    private var commandsConfigured = false
    private weak var manager: PlayerManager?

    private init() {}

    /// 播放类音频会话（允许退后台继续播放）
    func configurePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    /// 注册远程命令（播放/暂停/±10s/拖动进度）
    func configureCommands(manager: PlayerManager) {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        self.manager = manager

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak manager] _ in
            MainActor.assumeIsolated { manager?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak manager] _ in
            MainActor.assumeIsolated { manager?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak manager] _ in
            MainActor.assumeIsolated { manager?.playPause() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak manager] event in
            let interval = (event as? MPSkipIntervalCommand)?.preferredIntervals.first?.doubleValue ?? 10
            MainActor.assumeIsolated { manager?.skip(interval) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak manager] event in
            let interval = (event as? MPSkipIntervalCommand)?.preferredIntervals.first?.doubleValue ?? 10
            MainActor.assumeIsolated { manager?.skip(-interval) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak manager] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { manager?.seek(to: e.positionTime) }
            return .success
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    /// 更新锁屏/控制中心信息
    func updateInfo(title: String?, duration: Double, elapsed: Double, rate: Float) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title ?? "EnglishLab",
            MPMediaItemPropertyArtist: "EnglishLab",
            MPMediaItemPropertyPlaybackDuration: max(0, duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if duration > 0 {
            info[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
#endif
