import Foundation
import SQLite3

/// 离线英汉词典（ECDICT 精简 SQLite，MIT License）
public protocol OfflineDictionary: Sendable {
    func entry(for word: String) -> WordEntry?
}

public final class ECDICTDictionary: OfflineDictionary, @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()

    /// - Parameter url: 自定义数据库路径（测试用）；默认取 Bundle.module 内嵌资源
    public init?(url: URL? = nil) {
        let fileURL = url ?? Bundle.module.url(forResource: "ecdict", withExtension: "sqlite")
        guard let fileURL else { return nil }
        guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        // 校验表结构
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT word FROM dict LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_finalize(stmt)
    }

    deinit {
        sqlite3_close(db)
    }

    public func entry(for word: String) -> WordEntry? {
        let key = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }

        var stmt: OpaquePointer?
        let sql = "SELECT phonetic, translation, definition FROM dict WHERE word = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let phonetic = columnText(stmt, 0)
        let translation = columnText(stmt, 1)
        let definition = columnText(stmt, 2)

        var definitions: [Definition] = []
        // ECDICT translation 中的换行是字面 \n
        for line in translation.replacingOccurrences(of: "\\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            definitions.append(Definition(partOfSpeech: "", meaning: text))
        }
        if definitions.isEmpty, !definition.isEmpty {
            for line in definition.replacingOccurrences(of: "\\n", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: true).prefix(3) {
                definitions.append(Definition(partOfSpeech: "", meaning: String(line)))
            }
        }
        guard !definitions.isEmpty else { return nil }

        let phonetics = phonetic.isEmpty ? [] : [Phonetic(text: "/\(phonetic)/")]
        return WordEntry(
            word: key,
            phonetics: phonetics,
            definitions: definitions,
            source: "ECDICT 离线英汉词典 (MIT)"
        )
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }
}
