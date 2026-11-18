import Foundation
import AVFoundation
import Observation

enum RecorderError: Error, LocalizedError {
    case permissionDenied
    case recorderUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "麦克风权限未授权。请在 系统设置 → 隐私与安全性 → 麦克风 中允许 EnglishLab。"
        case .recorderUnavailable:
            return "无法启动录音，请检查麦克风设备。"
        }
    }
}

/// 录音服务：m4a 录制 + 实时电平（录音可视化）
@MainActor
@Observable
final class AudioRecorderService: NSObject {
    private(set) var isRecording = false
    /// 归一化电平 0...1（用于 UI 波形/音量条）
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var currentURL: URL?

    /// 请求麦克风权限（macOS）
    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// 开始录音，返回目标文件 URL
    @discardableResult
    func startRecording() throws -> URL {
        stopMeter()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        #endif
        let url = RecordingStore.shared.newRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.recorderUnavailable }
        self.recorder = recorder
        self.currentURL = url
        isRecording = true
        elapsed = 0
        startMeter()
        return url
    }

    /// 停止录音，返回录音文件 URL
    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        stopMeter()
        #if os(iOS)
        // 录音结束恢复播放类会话（保证退后台继续播放）
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        isRecording = false
        level = 0
        let url = currentURL
        recorder = nil
        currentURL = nil
        return url
    }

    /// 取消录音并删除文件
    func cancelRecording() {
        let url = currentURL
        _ = stopRecording()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Metering

    private func startMeter() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                let db = recorder.averagePower(forChannel: 0)   // -160...0
                // -50dB 以下视为静音
                let normalized = max(0, min(1, (db + 50) / 50))
                self.level = normalized
                self.elapsed = recorder.currentTime
            }
        }
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
    }
}
