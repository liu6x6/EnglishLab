import Foundation
import Speech
import AVFoundation

/// 转写出的一个语句片段（秒）
struct TranscribedSegment: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

enum TranscriptionError: Error, LocalizedError {
    case unsupportedOS
    case unsupportedLocale
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "AI 字幕需要 macOS 26 / iOS 26 或更高版本。可改用「关联字幕…」导入 .srt/.lrc 文件。"
        case .unsupportedLocale:
            return "当前系统不支持英文语音转写。"
        case .noSpeech:
            return "没有识别到语音内容。"
        }
    }
}

/// 设备端 AI 转写（Apple SpeechTranscriber，macOS 26+/iOS 26+，免费、离线、带时间戳）
final class TranscriptionService: Sendable {

    static var isSupported: Bool {
        if #available(macOS 26, iOS 26, *) { return true }
        return false
    }

    @available(macOS 26, iOS 26, *)
    func transcribe(
        fileURL: URL,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> [TranscribedSegment] {
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "en-US")
        ) else { throw TranscriptionError.unsupportedLocale }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        // 语言模型资产（可能需首次下载）
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onStatus?("正在下载语音模型（首次使用）…")
            try await request.downloadAndInstall()
        }

        onStatus?("正在转写音频…")
        let audioFile = try AVAudioFile(forReading: fileURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = SegmentCollector()

        // 收集结果：volatile 结果按 range.start 覆盖去重
        let collectTask = Task {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = CMTimeGetSeconds(result.range.start)
                let end = CMTimeGetSeconds(result.range.end)
                guard start.isFinite, end.isFinite, end > start else { continue }
                await collector.upsert(TranscribedSegment(start: start, end: end, text: text))
            }
        }

        if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } else {
            try await analyzer.cancelAndFinishNow()
        }
        try await collectTask.value

        let segments = await collector.sortedSegments()
        guard !segments.isEmpty else { throw TranscriptionError.noSpeech }
        return segments
    }
}

/// 按起点去重收集（volatile → final 覆盖）
private actor SegmentCollector {
    private var byStart: [Double: TranscribedSegment] = [:]

    func upsert(_ segment: TranscribedSegment) {
        byStart[segment.start] = segment
    }

    func sortedSegments() -> [TranscribedSegment] {
        byStart.values.sorted { $0.start < $1.start }
    }
}
