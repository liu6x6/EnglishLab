import Foundation
import WhisperCppKit

/// 自检钩子：--selftest-whisper <音频路径> [模型名]（默认用当前选中模型）
enum WhisperSelfTest {
    @MainActor
    static func run(audioPath: String, modelName: String? = nil) async {
        let manager = WhisperModelManager.shared
        let modelURL: URL?
        if let modelName, let model = WhisperModel.catalog.first(where: { $0.name == modelName }) {
            let url = manager.fileURL(for: model)
            modelURL = FileManager.default.fileExists(atPath: url.path) ? url : nil
        } else {
            modelURL = manager.activeModelURL
        }
        guard let modelURL else {
            print("SELFTEST WHISPER FAILED: 无已下载模型（active=\(manager.activeModelName)）")
            exit(1)
        }
        print("[whisper] model: \(modelURL.lastPathComponent)")
        print("[whisper] runtime: \(WhisperCppKit.systemInfo.prefix(120))")
        let t0 = Date()
        do {
            let segments = try await WhisperTranscriptionService().transcribe(
                modelURL: modelURL,
                audioURL: URL(fileURLWithPath: audioPath)
            ) { status in print("[status] \(status)") }
            let elapsed = Date().timeIntervalSince(t0)
            precondition(!segments.isEmpty, "应有转写结果")
            precondition(segments.allSatisfy { $0.end > $0.start }, "时间轴应有效")
            print(String(format: "SELFTEST WHISPER OK: %d segments in %.1fs", segments.count, elapsed))
            for s in segments.prefix(3) {
                print(String(format: "  [%.2f-%.2f] %@", s.start, s.end, s.text))
            }
            exit(0)
        } catch {
            print("SELFTEST WHISPER FAILED: \(error.localizedDescription)")
            exit(1)
        }
    }
}
