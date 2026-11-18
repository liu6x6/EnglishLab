import Foundation
import SwiftData
import Observation

/// AI 字幕生成状态管理（进度 sheet 数据源）
@MainActor
@Observable
final class TranscriptionManager {
    enum State: Equatable {
        case idle
        case running(String)
        case done(Int)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var targetTitle = ""
    var isPresented = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let service = TranscriptionService()

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func generate(for item: MediaItem, context: ModelContext) {
        guard TranscriptionService.isSupported else {
            targetTitle = item.title
            state = .failed(TranscriptionError.unsupportedOS.localizedDescription)
            isPresented = true
            return
        }
        task?.cancel()
        targetTitle = item.title
        state = .running("准备中…")
        isPresented = true
        let url = MediaStore.shared.url(for: item.fileName)

        task = Task { [weak self] in
            guard let self else { return }
            if #available(macOS 26, iOS 26, *) {
                do {
                    let segments = try await self.service.transcribe(fileURL: url) { status in
                        Task { @MainActor [weak self] in
                            self?.state = .running(status)
                        }
                    }
                    guard !Task.isCancelled, self.isRunning else { return }
                    // 替换旧字幕并入库
                    for line in item.lines { context.delete(line) }
                    item.lines = []
                    for (i, segment) in segments.enumerated() {
                        let line = SubtitleLine(
                            index: i, startTime: segment.start, endTime: segment.end, text: segment.text
                        )
                        line.mediaItem = item
                        context.insert(line)
                    }
                    item.subtitleFileName = "AI 生成字幕"
                    try? context.save()
                    self.state = .done(segments.count)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    /// 取消生成
    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
        isPresented = false
    }

    /// 关闭面板（运行中则转后台继续）
    func dismiss() {
        isPresented = false
        if !isRunning { state = .idle }
    }
}
