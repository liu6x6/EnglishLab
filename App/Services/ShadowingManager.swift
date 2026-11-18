import Foundation
import AVFoundation
import SwiftData
import Observation
import ShadowingKit

/// 跟读状态机（ShadowingModule_Design.md §8.2）：
/// idle → preparing → playingOriginal → readyToRecord → recording → processing → result
/// result → recording（再练一次）；任意状态 → failed（错误）/ idle（关闭）
@MainActor
@Observable
final class ShadowingManager {
    enum Phase: Equatable {
        case idle, preparing, playingOriginal, readyToRecord, recording, processing, result, failed
    }

    private(set) var phase: Phase = .idle
    private(set) var line: SubtitleLine?
    private(set) var media: MediaItem?
    private(set) var result: ShadowingResult?
    private(set) var lastRecordingURL: URL?
    var errorMessage: String?

    let recorder = AudioRecorderService()

    @ObservationIgnored private let speech = SpeechRecognitionService()
    @ObservationIgnored private var playerManager: PlayerManager?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var recognitionTask: Task<Void, Never>?
    @ObservationIgnored private var myPlayer: AVPlayer?

    // MARK: - Lifecycle

    func start(line: SubtitleLine, media: MediaItem, player: PlayerManager, context: ModelContext) {
        reset()
        self.line = line
        self.media = media
        self.playerManager = player
        self.context = context
        player.loopLine = nil
        player.pause()
        phase = .preparing
        Task { [weak self] in
            guard let self else { return }
            guard await self.recorder.requestPermission() else {
                self.fail(RecorderError.permissionDenied); return
            }
            guard await self.speech.requestPermission() else {
                self.fail(RecognitionError.notAuthorized); return
            }
            guard self.phase == .preparing else { return }
            self.playOriginal(autoAdvance: true)
        }
    }

    func close() {
        reset()
        playerManager?.pause()
        playerManager = nil
        context = nil
    }

    private func reset() {
        playTask?.cancel()
        recognitionTask?.cancel()
        if recorder.isRecording { recorder.cancelRecording() }
        myPlayer?.pause()
        myPlayer = nil
        phase = .idle
        line = nil
        media = nil
        result = nil
        errorMessage = nil
        lastRecordingURL = nil
    }

    // MARK: - Original playback

    /// 播放原句；autoAdvance 时播完自动进入待录音状态
    func playOriginal(autoAdvance: Bool = false) {
        guard let line, let player = playerManager else { return }
        playTask?.cancel()
        player.loopLine = nil
        player.seek(to: line.startTime, autoplay: true)
        if autoAdvance { phase = .playingOriginal }
        let endTime = line.endTime
        playTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, !Task.isCancelled else { return }
                if player.currentTime >= endTime - 0.05 {
                    player.pause()
                    if autoAdvance, self.phase == .playingOriginal {
                        self.phase = .readyToRecord
                    }
                    return
                }
            }
        }
    }

    func skipOriginal() {
        playTask?.cancel()
        playerManager?.pause()
        phase = .readyToRecord
    }

    // MARK: - Recording

    func startRecording() {
        guard phase == .readyToRecord || phase == .result || phase == .failed else { return }
        playTask?.cancel()
        playerManager?.pause()
        myPlayer?.pause()
        do {
            try recorder.startRecording()
            errorMessage = nil
            phase = .recording
        } catch {
            fail(error)
        }
    }

    func finishRecording() {
        guard phase == .recording else { return }
        let elapsed = recorder.elapsed
        guard let url = recorder.stopRecording() else {
            fail(RecorderError.recorderUnavailable)
            return
        }
        // 空录音检测
        guard elapsed >= 0.4 else {
            try? FileManager.default.removeItem(at: url)
            errorMessage = "没有检测到声音，请再试一次。"
            phase = .readyToRecord
            return
        }
        lastRecordingURL = url
        phase = .processing
        recognitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.speech.recognize(fileURL: url)
                guard let line = self.line, self.phase == .processing else { return }
                let result = TextAligner.assess(targetText: line.text, recognizedText: text)
                self.result = result
                self.persist(result: result, recordingURL: url)
                self.phase = .result
            } catch {
                guard self.phase == .processing else { return }
                self.fail(error)
            }
        }
    }

    /// 再练一次（保留历史会话记录）
    func retry() {
        result = nil
        errorMessage = nil
        phase = .readyToRecord
    }

    // MARK: - Playback of my recording

    func playMyRecording() {
        guard let url = lastRecordingURL else { return }
        playerManager?.pause()
        myPlayer?.pause()
        let player = AVPlayer(url: url)
        myPlayer = player
        player.play()
    }

    // MARK: - Private

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        phase = .failed
    }

    private func persist(result: ShadowingResult, recordingURL: URL) {
        guard let context, let line, let media else { return }
        let session = ShadowingSession(
            mediaItemID: media.id,
            subtitleLineID: line.id,
            mediaTitle: media.title,
            targetText: line.text,
            recognizedText: result.recognizedText,
            audioFileName: recordingURL.lastPathComponent,
            overallScore: result.overallScore,
            resultData: try? JSONEncoder().encode(result)
        )
        context.insert(session)
        try? context.save()
        StatsTracker.shared.recordShadowing()
    }
}
