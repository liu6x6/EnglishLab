import Foundation

/// 查询缓存（异步，actor 实现）
public protocol DictionaryCache: Sendable {
    func entry(for word: String) async -> WordEntry?
    func store(_ entry: WordEntry, for word: String) async
}

/// JSON 磁盘缓存，默认 30 天过期
public actor DiskDictionaryCache: DictionaryCache {
    private let directory: URL
    private let ttl: TimeInterval

    public init(directory: URL? = nil, ttl: TimeInterval = 30 * 24 * 3600) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("EnglishLab/Dictionary", isDirectory: true)
        }
        self.ttl = ttl
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func entry(for word: String) -> WordEntry? {
        let url = fileURL(for: word)
        guard let data = try? Data(contentsOf: url),
              let wrapper = try? JSONDecoder().decode(CacheWrapper.self, from: data)
        else { return nil }
        if Date().timeIntervalSince(wrapper.cachedAt) > ttl {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return wrapper.entry
    }

    public func store(_ entry: WordEntry, for word: String) {
        let wrapper = CacheWrapper(cachedAt: Date(), entry: entry)
        guard let data = try? JSONEncoder().encode(wrapper) else { return }
        try? data.write(to: fileURL(for: word), options: .atomic)
    }

    private func fileURL(for word: String) -> URL {
        let safe = word.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }

    struct CacheWrapper: Codable {
        let cachedAt: Date
        let entry: WordEntry
    }
}
