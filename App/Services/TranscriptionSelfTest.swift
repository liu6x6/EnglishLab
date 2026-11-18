import Foundation

/// 自检钩子：--selftest-transcribe <音频路径>（在 ContentView.task 中运行，验证后退出）
enum TranscriptionSelfTest {
    static func run(path: String) async {
        guard TranscriptionService.isSupported else {
            print("SELFTEST TRANSCRIBE SKIPPED: 需要 macOS 26+")
            exit(2)
        }
        if #available(macOS 26, iOS 26, *) {
            do {
                let service = TranscriptionService()
                let segments = try await service.transcribe(
                    fileURL: URL(fileURLWithPath: path),
                    onStatus: { status in print("[status] \(status)") }
                )
                precondition(!segments.isEmpty, "应有转写结果")
                precondition(segments.allSatisfy { $0.end > $0.start }, "时间轴应有效")
                print("SELFTEST TRANSCRIBE OK: \(segments.count) segments")
                for s in segments.prefix(3) {
                    print(String(format: "  [%.2f-%.2f] %@", s.start, s.end, s.text))
                }
                exit(0)
            } catch {
                print("SELFTEST TRANSCRIBE FAILED: \(error.localizedDescription)")
                exit(1)
            }
        }
    }
}
