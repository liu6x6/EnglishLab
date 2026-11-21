import Foundation
import AVFoundation
import CWhisper

/// whisper.cpp 转写出的语句片段（秒）
public struct WhisperTranscribedSegment: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum WhisperError: Error, LocalizedError {
    case modelNotFound
    case initFailed
    case audioLoadFailed
    case transcriptionFailed

    public var errorDescription: String? {
        switch self {
        case .modelNotFound: return "Whisper 模型未下载，请在设置中选择并下载模型。"
        case .initFailed: return "Whisper 模型加载失败（文件可能损坏，请删除后重新下载）。"
        case .audioLoadFailed: return "音频读取失败。"
        case .transcriptionFailed: return "Whisper 转写失败。"
        }
    }
}

/// whisper.cpp 设备端转写（Metal/Accelerate 加速，macOS 14+/iOS 17+）
public final class WhisperTranscriptionService: @unchecked Sendable {
    /// 静态 C 字符串（whisper_full_params.language 需要UnsafePointer，字面量不能直接赋给属性）
    private static let enLanguage: UnsafePointer<CChar> = UnsafePointer(strdup("en")!)

    public init() {}

    public func transcribe(
        modelURL: URL,
        audioURL: URL,
        threads: Int = 4,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> [WhisperTranscribedSegment] {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperError.modelNotFound
        }
        onStatus?("加载音频…")
        let samples = try Self.loadSamples(url: audioURL)
        guard !samples.isEmpty else { throw WhisperError.audioLoadFailed }

        // 阻塞式 C 推理放到后台线程
        return try await Task.detached(priority: .userInitiated) {
            onStatus?("加载模型…")
            var cparams = whisper_context_default_params()
            #if targetEnvironment(simulator)
            // 模拟器 Metal 驱动（MTLSimDriver）大缓冲区 XPC shmem 会崩溃，回退 CPU（NEON 仍很快）
            cparams.use_gpu = false
            #else
            cparams.use_gpu = true
            #endif
            guard let ctx = whisper_init_from_file_with_params(modelURL.path, cparams) else {
                throw WhisperError.initFailed
            }
            defer { whisper_free(ctx) }

            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.language = Self.enLanguage
            params.translate = false
            params.print_progress = false
            params.print_realtime = false
            params.print_timestamps = false
            params.no_context = true
            params.n_threads = Int32(threads)

            onStatus?("转写中（whisper.cpp）…")
            let code = samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
            guard code == 0 else { throw WhisperError.transcriptionFailed }

            let n = whisper_full_n_segments(ctx)
            var segments: [WhisperTranscribedSegment] = []
            for i in 0..<n {
                let t0 = whisper_full_get_segment_t0(ctx, i)   // 厘秒
                let t1 = whisper_full_get_segment_t1(ctx, i)
                guard let cText = whisper_full_get_segment_text(ctx, i) else { continue }
                let text = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, t1 > t0 else { continue }
                segments.append(WhisperTranscribedSegment(
                    start: Double(t0) / 100.0, end: Double(t1) / 100.0, text: text
                ))
            }
            return segments
        }.value
    }

    /// 任意音频 → 16kHz 单声道 Float32 PCM（whisper 输入要求）
    static func loadSamples(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw WhisperError.audioLoadFailed
        }
        let inBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: inBuffer)

        let outCapacity = AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 4096
        let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity)!
        var error: NSError?
        var consumed = false
        converter.convert(to: outBuffer, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return inBuffer
        }
        if let error { throw error }
        guard let channel = outBuffer.floatChannelData?[0], outBuffer.frameLength > 0 else {
            throw WhisperError.audioLoadFailed
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outBuffer.frameLength)))
    }
}
