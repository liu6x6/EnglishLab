import Foundation
import Speech

enum RecognitionError: Error, LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case noResult
    case timeout

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "语音识别权限未授权。请在 系统设置 → 隐私与安全性 → 语音识别 中允许 EnglishLab。"
        case .recognizerUnavailable:
            return "语音识别当前不可用（需要英文识别支持）。"
        case .noResult:
            return "听不清楚，请靠近麦克风或佩戴耳机后重试。"
        case .timeout:
            return "识别超时，请重试。"
        }
    }
}

/// 本地语音识别（SFSpeechRecognizer，支持时强制 on-device，隐私优先）
final class SpeechRecognitionService: @unchecked Sendable {

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// 识别录音文件，返回识别文本；15 秒超时
    func recognize(fileURL: URL) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw RecognitionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw RecognitionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let box = RecognitionBox()
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        box.resumeOnce(continuation, with: .success(result.bestTranscription.formattedString))
                        return
                    }
                    if let error {
                        box.resumeOnce(continuation, with: .failure(error))
                        return
                    }
                    // result 非 final 且无 error：等待
                    if result == nil && error == nil {
                        box.resumeOnce(continuation, with: .failure(RecognitionError.noResult))
                    }
                }
                box.task = task
                // 超时保护
                DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                    if box.markTimedOut() {
                        task.cancel()
                        box.resumeOnce(continuation, with: .failure(RecognitionError.timeout))
                    }
                }
            }
        } onCancel: {
            // 外部取消时的清理由超时/回调路径兜底
        }
    }
}

/// 线程安全的一次性 continuation 包装
private final class RecognitionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var timedOut = false
    var task: SFSpeechRecognitionTask?

    func resumeOnce(_ continuation: CheckedContinuation<String, Error>, with result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        task?.cancel()
        continuation.resume(with: result)
    }

    func markTimedOut() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        timedOut = true
        return true
    }
}
