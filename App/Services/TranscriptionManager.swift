import Foundation
import SwiftData
import Observation
import WhisperCppKit

/// AI 字幕生成状态管理（进度 sheet 数据源）
/// 引擎路由：auto → 26+ 用 Apple，否则 whisper.cpp；可手动指定
@MainActor
@Observable
final class TranscriptionManager {
    enum State: Equatable {
        case idle
        case running(String)
        case done(Int)
        case failed(String)
    }

    private enum Engine { case apple, whisper }

    private(set) var state: State = .idle
    private(set) var targetTitle = ""
    var isPresented = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let appleService = TranscriptionService()
    @ObservationIgnored private let whisperService = WhisperTranscriptionService()

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private func resolveEngine() -> Engine {
        let pref = UserDefaults.standard.string(forKey: "transcriptionEngine") ?? "auto"
        switch pref {
        case "whisper": return .whisper
        case "apple": return TranscriptionService.isSupported ? .apple : .whisper
        default: return TranscriptionService.isSupported ? .apple : .whisper
        }
    }

    func generate(for item: MediaItem, context: ModelContext) {
        task?.cancel()
        targetTitle = item.title
        isPresented = true
        let url = MediaStore.shared.url(for: item.fileName)
        let engine = resolveEngine()

        if engine == .whisper {
            guard let modelURL = WhisperModelManager.shared.activeModelURL else {
                state = .failed("Whisper 模型未下载。请打开 设置 → 转写，选择并下载模型（推荐 Small 英文），完成后重试。")
                return
            }
            state = .running("准备中…")
            task = Task { [weak self] in
                guard let self else { return }
                do {
                    let segments = try await self.whisperService.transcribe(
                        modelURL: modelURL, audioURL: url
                    ) { status in
                        Task { @MainActor [weak self] in self?.state = .running(status) }
                    }
                    guard !Task.isCancelled, self.isRunning else { return }
                    self.save(segments.map {
                        TranscribedSegment(start: $0.start, end: $0.end, text: $0.text)
                    }, to: item, context: context, sourceName: "Whisper 生成字幕")
                } catch {
                    guard !Task.isCancelled else { return }
                    self.state = .failed(error.localizedDescription)
                }
            }
            return
        }

        // Apple 引擎（macOS 26 / iOS 26+）
        state = .running("准备中…")
        task = Task { [weak self] in
            guard let self else { return }
            if #available(macOS 26, iOS 26, *) {
                do {
                    let segments = try await self.appleService.transcribe(fileURL: url) { status in
                        Task { @MainActor [weak self] in self?.state = .running(status) }
                    }
                    guard !Task.isCancelled, self.isRunning else { return }
                    self.save(segments, to: item, context: context, sourceName: "AI 生成字幕")
                } catch {
                    guard !Task.isCancelled else { return }
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func save(_ segments: [TranscribedSegment], to item: MediaItem, context: ModelContext, sourceName: String) {
        for line in item.lines { context.delete(line) }
        item.lines = []
        for (i, segment) in segments.enumerated() {
            let line = SubtitleLine(
                index: i, startTime: segment.start, endTime: segment.end, text: segment.text
            )
            line.mediaItem = item
            context.insert(line)
        }
        item.subtitleFileName = sourceName
        try? context.save()
        state = .done(segments.count)
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
