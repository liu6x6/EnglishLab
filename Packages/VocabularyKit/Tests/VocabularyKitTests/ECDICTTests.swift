import XCTest
import SQLite3
@testable import VocabularyKit

final class ECDICTTests: XCTestCase {

    /// 建测试用 sqlite fixture（与 make_ecdict.sh 相同 schema）
    private func makeFixture(rows: [(String, String, String)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ecdict-test-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_exec(db, """
            CREATE TABLE dict(word TEXT PRIMARY KEY, phonetic TEXT, translation TEXT,
            definition TEXT, pos TEXT, tag TEXT, exchange TEXT)
            """, nil, nil, nil)
        for (word, phonetic, translation) in rows {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO dict(word, phonetic, translation) VALUES(?,?,?)", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, word, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, phonetic, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 3, translation, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
            sqlite3_finalize(stmt)
        }
        sqlite3_close(db)
        return url
    }

    func testLookupChinese() throws {
        let url = try makeFixture(rows: [
            ("perseverance", "pə:si'viərəns", "n. 毅力；韧性；不屈不挠的精神"),
            ("run", "rʌn", "v. 跑；奔跑；经营\\nn. 跑步；奔跑")
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let dict = try XCTUnwrap(ECDICTDictionary(url: url))

        let entry = try XCTUnwrap(dict.entry(for: "Perseverance"))
        XCTAssertEqual(entry.word, "perseverance")
        XCTAssertTrue(entry.definitions[0].meaning.contains("毅力"))
        XCTAssertEqual(entry.phonetics.first?.text, "/pə:si'viərəns/")
        XCTAssertTrue(entry.source.contains("ECDICT"))

        // 字面 \n 分行 → 多个义项
        let run = try XCTUnwrap(dict.entry(for: "run"))
        XCTAssertEqual(run.definitions.count, 2)
        XCTAssertTrue(run.definitions[1].meaning.hasPrefix("n."))

        XCTAssertNil(dict.entry(for: "zzzznotexist"))
    }

    func testBundledResourceOpens() throws {
        // 内嵌资源（当前为 mini 或全量）应可打开且可查任意存在词
        let dict = try XCTUnwrap(ECDICTDictionary())
        // mini/全量都含 'hood（若全量替换后依然收录）；用 SQL 无关的方式验证：查一个必查词
        // 这里只验证初始化成功 + 查询不崩溃
        _ = dict.entry(for: "hello")
        _ = dict.entry(for: "'hood")
    }

    // MARK: - Repository 集成

    struct FailingDictionary: DictionaryLookupService {
        func lookup(word: String) async throws -> WordEntry? {
            throw URLError(.notConnectedToInternet)
        }
    }

    struct NotFoundDictionary: DictionaryLookupService {
        func lookup(word: String) async throws -> WordEntry? { nil }
    }

    struct StubOffline: OfflineDictionary {
        let entries: [String: WordEntry]
        func entry(for word: String) -> WordEntry? { entries[word.lowercased()] }
    }

    private let chineseRun = WordEntry(
        word: "run",
        phonetics: [Phonetic(text: "/rʌn/")],
        definitions: [Definition(partOfSpeech: "", meaning: "v. 跑；经营")],
        source: "ECDICT 离线英汉词典 (MIT)"
    )

    func testOfflineFallbackWhenNetworkFails() async throws {
        let repo = DefaultVocabularyRepository(
            dictionary: FailingDictionary(),
            cache: MemoryCache(),
            offline: StubOffline(entries: ["run": chineseRun])
        )
        let entry = try await repo.lookup(word: "running")  // 词形还原 → run
        XCTAssertEqual(entry.word, "run")
        XCTAssertTrue(entry.definitions[0].meaning.contains("跑"))
    }

    func testOfflineFallbackWhenOnlineNotFound() async throws {
        let repo = DefaultVocabularyRepository(
            dictionary: NotFoundDictionary(),
            cache: MemoryCache(),
            offline: StubOffline(entries: ["run": chineseRun])
        )
        let entry = try await repo.lookup(word: "run")
        XCTAssertTrue(entry.source.contains("ECDICT"))
    }

    func testChineseMergedIntoOnlineEntry() async throws {
        let online = WordEntry(
            word: "run",
            definitions: [Definition(partOfSpeech: "verb", meaning: "to move fast")],
            source: "mock-online"
        )
        let repo = DefaultVocabularyRepository(
            dictionary: MockDictionary(known: ["run": online], counter: CallCounter()),
            cache: MemoryCache(),
            offline: StubOffline(entries: ["run": chineseRun])
        )
        let entry = try await repo.lookup(word: "run")
        // 中文释义在最前，英文释义保留
        XCTAssertTrue(entry.definitions[0].meaning.contains("跑"))
        XCTAssertTrue(entry.definitions.contains { $0.meaning == "to move fast" })
        XCTAssertTrue(entry.source.contains("ECDICT"))
        XCTAssertEqual(entry.phonetics.first?.text, "/rʌn/")
    }

    func testNoOfflineStillWorks() async throws {
        let online = WordEntry(word: "run", definitions: [Definition(partOfSpeech: "verb", meaning: "move")])
        let repo = DefaultVocabularyRepository(
            dictionary: MockDictionary(known: ["run": online], counter: CallCounter()),
            cache: MemoryCache()
        )
        let entry = try await repo.lookup(word: "run")
        XCTAssertEqual(entry.definitions.count, 1)
    }
}
