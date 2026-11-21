import Foundation
import Observation

/// Whisper 模型目录条目
struct WhisperModel: Identifiable, Equatable {
    let name: String          // 如 small.en
    let displayName: String
    let sizeMB: Int
    let note: String

    var id: String { name }
    var fileName: String { "ggml-\(name).bin" }

    static let catalog: [WhisperModel] = [
        WhisperModel(name: "tiny.en", displayName: "Tiny (英文)", sizeMB: 75, note: "最快，清晰音频够用"),
        WhisperModel(name: "base.en", displayName: "Base (英文)", sizeMB: 142, note: "速度与质量均衡"),
        WhisperModel(name: "small.en", displayName: "Small (英文)", sizeMB: 466, note: "推荐，准确率高"),
        WhisperModel(name: "medium.en", displayName: "Medium (英文)", sizeMB: 1536, note: "更高准确率，较慢"),
        WhisperModel(name: "large-v3-turbo-q5_0", displayName: "Large-v3 Turbo (量化)", sizeMB: 547, note: "接近大模型质量，多语言")
    ]
}

/// 模型下载/管理（hf-mirror 快速通道，失败回退 huggingface.co）
@MainActor
@Observable
final class WhisperModelManager {
    static let shared = WhisperModelManager()

    enum Status: Equatable {
        case notDownloaded
        case downloading(Double)   // 0...1
        case downloaded
        case failed(String)
    }

    private(set) var statuses: [String: Status] = [:]
    var activeModelName: String {
        didSet { UserDefaults.standard.set(activeModelName, forKey: "whisperModelName") }
    }

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("EnglishLab/WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        activeModelName = UserDefaults.standard.string(forKey: "whisperModelName") ?? "small.en"
        refresh()
    }

    func refresh() {
        for model in WhisperModel.catalog {
            if case .downloading = statuses[model.name] { continue }
            let url = directory.appendingPathComponent(model.fileName)
            statuses[model.name] = FileManager.default.fileExists(atPath: url.path) ? .downloaded : .notDownloaded
        }
    }

    func status(for model: WhisperModel) -> Status {
        statuses[model.name] ?? .notDownloaded
    }

    func fileURL(for model: WhisperModel) -> URL {
        directory.appendingPathComponent(model.fileName)
    }

    /// 当前选中且已下载的模型 URL（nil = 不可用）
    var activeModelURL: URL? {
        guard let model = WhisperModel.catalog.first(where: { $0.name == activeModelName }) else { return nil }
        let url = fileURL(for: model)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var hasAnyModel: Bool {
        WhisperModel.catalog.contains { status(for: $0) == .downloaded }
    }

    func download(_ model: WhisperModel) {
        guard downloadTasks[model.name] == nil else { return }
        statuses[model.name] = .downloading(0)
        let dest = fileURL(for: model)
        let partial = dest.appendingPathExtension("partial")
        let urls = [
            URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/\(model.fileName)")!,
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(model.fileName)")!
        ]
        downloadTasks[model.name] = Task { [weak self] in
            var lastError: Error?
            for url in urls {
                do {
                    try await Self.downloadFile(from: url, to: partial) { progress in
                        Task { @MainActor [weak self] in
                            self?.statuses[model.name] = .downloading(progress)
                        }
                    }
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: partial, to: dest)
                    self?.finish(model.name, status: .downloaded)
                    return
                } catch {
                    lastError = error
                    try? FileManager.default.removeItem(at: partial)
                }
            }
            self?.finish(model.name, status: .failed(lastError?.localizedDescription ?? "下载失败"))
        }
    }

    func cancelDownload(_ model: WhisperModel) {
        downloadTasks[model.name]?.cancel()
        downloadTasks[model.name] = nil
        try? FileManager.default.removeItem(at: fileURL(for: model).appendingPathExtension("partial"))
        statuses[model.name] = .notDownloaded
    }

    func delete(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: fileURL(for: model))
        statuses[model.name] = .notDownloaded
    }

    private func finish(_ name: String, status: Status) {
        downloadTasks[name] = nil
        statuses[name] = status
    }

    /// 下载任务（delegate 原生进度回调，避免逐字节异步开销）
    private static func downloadFile(
        from url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = DownloadDelegate()
        delegate.onProgress = onProgress
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            session.downloadTask(with: request).resume()
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 0
        guard (size ?? 0) > 1_000_000 else { throw URLError(.cannotParseResponse) }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        onProgress(1)
    }
}

/// 下载进度/完成回调桥接
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: (@Sendable (Double) -> Void)?
    var continuation: CheckedContinuation<URL, Error>?
    private let lock = NSLock()
    private var resumed = false

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // location 在回调返回后被系统删除，先移走
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            resumeOnce(.success(tmp))
        } catch {
            resumeOnce(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            resumeOnce(.failure(error))
        }
    }

    private func resumeOnce(_ result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed, let continuation else { return }
        resumed = true
        continuation.resume(with: result)
    }
}
