import Foundation

/// 跟读录音文件仓库：Application Support/EnglishLab/Recordings
struct RecordingStore {
    static let shared = RecordingStore()

    var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("EnglishLab/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func newRecordingURL() -> URL {
        directory.appendingPathComponent(UUID().uuidString + ".m4a")
    }

    func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
