import Foundation
#if os(macOS)
import AppKit
#endif
import SwiftData
import SubtitleKit
import UniformTypeIdentifiers

/// 素材导入逻辑（NSOpenPanel 与测试钩子共用）
@MainActor
enum MediaImporter {

    static var mediaTypes: [UTType] {
        var types: [UTType] = [.movie, .audio, .mpeg4Movie, .quickTimeMovie, .mp3, .wav, .aiff]
        for ext in ["mkv", "flac", "m4a", "webm", "ogg"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    static var subtitleTypes: [UTType] {
        var types: [UTType] = [.plainText]
        for ext in ["srt", "lrc", "vtt"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    /// 弹出原生打开面板（macOS；iOS 用 SwiftUI fileImporter）
    #if os(macOS)
    static func openPanel(types: [UTType], multiple: Bool, message: String) -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = multiple
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = message
        panel.prompt = "导入"
        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }
    #endif

    /// 导入媒体（可混选字幕，同名自动配对）。返回新导入的素材与错误信息。
    @discardableResult
    static func importFiles(_ urls: [URL], context: ModelContext) -> (imported: [MediaItem], error: String?) {
        let store = MediaStore.shared
        var subtitlesByName: [String: URL] = [:]
        var imported: [MediaItem] = []
        var errorMessage: String?

        for url in urls {
            let ext = url.pathExtension.lowercased()
            let baseName = url.deletingPathExtension().lastPathComponent
            if store.isSubtitle(ext: ext) {
                subtitlesByName[baseName] = url
            } else if store.isVideo(ext: ext) || store.isAudio(ext: ext) {
                do {
                    let fileName = try store.importFile(from: url)
                    let item = MediaItem(
                        type: store.isVideo(ext: ext) ? .video : .audio,
                        title: baseName,
                        fileName: fileName
                    )
                    context.insert(item)
                    imported.append(item)
                    Task { item.duration = await store.duration(of: fileName) }
                } catch {
                    errorMessage = "无法导入 \(url.lastPathComponent)：\(error.localizedDescription)"
                }
            } else {
                errorMessage = "不支持的文件类型：\(url.lastPathComponent)"
            }
        }
        for item in imported {
            if let subURL = subtitlesByName[item.title] {
                if let err = attachSubtitle(subURL, to: item, context: context) {
                    errorMessage = err
                }
            }
        }
        try? context.save()
        return (imported, errorMessage)
    }

    /// 关联字幕文件到素材，返回错误信息（nil 表示成功）
    @discardableResult
    static func attachSubtitle(_ url: URL, to item: MediaItem, context: ModelContext) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let content = try readText(at: url)
            let format = SubtitleFormat.detect(fileName: url.lastPathComponent)
            let parsed = SubtitleParser.parse(content, format: format)
            guard !parsed.isEmpty else {
                return "字幕文件解析结果为空：\(url.lastPathComponent)"
            }
            for line in item.lines { context.delete(line) }
            item.lines = []
            for p in parsed {
                let line = SubtitleLine(index: p.index, startTime: p.start, endTime: p.end, text: p.text)
                line.mediaItem = item
                context.insert(line)
            }
            item.subtitleFileName = url.lastPathComponent
            try? context.save()
            return nil
        } catch {
            return "无法读取字幕：\(error.localizedDescription)"
        }
    }

    /// 尝试 UTF-8 / UTF-16 / Latin-1 读取字幕文本
    static func readText(at url: URL) throws -> String {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let s = try? String(contentsOf: url, encoding: .utf16) { return s }
        return try String(contentsOf: url, encoding: .isoLatin1)
    }
}
