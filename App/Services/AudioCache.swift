import Foundation
import CryptoKit

/// 在线发音音频本地缓存（架构文档缓存策略：避免重复下载）
actor AudioCache {
    static let shared = AudioCache()

    private let directory: URL
    private var inFlight: [String: Task<URL?, Never>] = [:]

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("EnglishLab/Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 返回本地缓存文件 URL；未缓存则下载后返回；下载失败返回 nil（调用方回退流播/TTS）
    func localURL(for remote: URL) async -> URL? {
        let key = SHA256.hash(data: Data(remote.absoluteString.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        let ext = remote.pathExtension.isEmpty ? "mp3" : remote.pathExtension
        let file = directory.appendingPathComponent("\(key).\(ext)")

        if FileManager.default.fileExists(atPath: file.path) { return file }

        // 同一 URL 并发请求共享一个下载任务
        if let task = inFlight[key] { return await task.value }
        let task = Task<URL?, Never> {
            do {
                let (tmp, _) = try await URLSession.shared.download(from: remote)
                try? FileManager.default.removeItem(at: file)
                try FileManager.default.moveItem(at: tmp, to: file)
                return file
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
}
