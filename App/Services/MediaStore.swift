import Foundation
import AVFoundation

/// 媒体文件仓库：导入时把用户选择的文件拷贝进 App 沙盒，
/// 之后直接用容器内 URL 访问，无需安全作用域书签。
struct MediaStore {
    static let shared = MediaStore()

    /// Application Support/EnglishLab/Media
    var mediaDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("EnglishLab/Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func url(for fileName: String) -> URL {
        mediaDirectory.appendingPathComponent(fileName)
    }

    /// 拷贝导入文件，返回容器内文件名
    func importFile(from sourceURL: URL) throws -> String {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.lowercased()
        let fileName = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let dest = url(for: fileName)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return fileName
    }

    func deleteFile(named fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// 读取媒体时长（秒）
    func duration(of fileName: String) async -> Double {
        let asset = AVURLAsset(url: url(for: fileName))
        guard let d = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(d)
        return seconds.isFinite ? seconds : 0
    }

    func isVideo(ext: String) -> Bool {
        ["mp4", "mov", "m4v", "mkv", "avi", "webm"].contains(ext.lowercased())
    }

    func isAudio(ext: String) -> Bool {
        ["mp3", "m4a", "aac", "wav", "flac", "aiff", "ogg"].contains(ext.lowercased())
    }

    func isSubtitle(ext: String) -> Bool {
        ["srt", "lrc", "vtt", "txt"].contains(ext.lowercased())
    }
}
