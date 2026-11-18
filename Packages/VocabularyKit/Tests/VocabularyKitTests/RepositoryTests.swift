import XCTest
@testable import VocabularyKit

// MARK: - Mocks

struct MockDictionary: DictionaryLookupService {
    let known: [String: WordEntry]
    let counter: CallCounter

    func lookup(word: String) async throws -> WordEntry? {
        await counter.increment()
        return known[word]
    }
}

struct MockThesaurus: ThesaurusService {
    let syn: [String]
    let ant: [String]
    func relations(for word: String) async -> (synonyms: [String], antonyms: [String]) {
        (syn, ant)
    }
}

actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

actor MemoryCache: DictionaryCache {
    var storage: [String: WordEntry] = [:]
    func entry(for word: String) -> WordEntry? { storage[word] }
    func store(_ entry: WordEntry, for word: String) { storage[word] = entry }
}

// MARK: - Tests

final class RepositoryTests: XCTestCase {
    private let runEntry = WordEntry(
        word: "run",
        definitions: [Definition(partOfSpeech: "verb", meaning: "to move fast")],
        source: "mock"
    )

    private func makeRepo(
        known: [String: WordEntry]? = nil,
        thesaurus: ThesaurusService? = nil,
        cache: DictionaryCache = MemoryCache(),
        counter: CallCounter = CallCounter()
    ) -> DefaultVocabularyRepository {
        DefaultVocabularyRepository(
            dictionary: MockDictionary(known: known ?? ["run": runEntry], counter: counter),
            thesaurus: thesaurus,
            cache: cache
        )
    }

    func testDirectLookup() async throws {
        let entry = try await makeRepo().lookup(word: "run")
        XCTAssertEqual(entry.word, "run")
    }

    func testLemmatizedLookup() async throws {
        // running 词典里没有 → 还原到 run 命中
        let entry = try await makeRepo().lookup(word: "running")
        XCTAssertEqual(entry.word, "run")
    }

    func testIrregularLookup() async throws {
        let goEntry = WordEntry(word: "go", definitions: [Definition(partOfSpeech: "verb", meaning: "move")])
        let entry = try await makeRepo(known: ["go": goEntry]).lookup(word: "went")
        XCTAssertEqual(entry.word, "go")
    }

    func testCacheHitSkipsNetwork() async throws {
        let cache = MemoryCache()
        let counter = CallCounter()
        let repo = makeRepo(cache: cache, counter: counter)
        _ = try await repo.lookup(word: "run")
        let callsAfterFirst = await counter.value
        _ = try await repo.lookup(word: "run")
        let callsAfterSecond = await counter.value
        XCTAssertEqual(callsAfterFirst, callsAfterSecond, "第二次应命中缓存")
    }

    func testAliasCached() async throws {
        let cache = MemoryCache()
        let counter = CallCounter()
        let repo = makeRepo(cache: cache, counter: counter)
        _ = try await repo.lookup(word: "running")
        let before = await counter.value
        _ = try await repo.lookup(word: "running")
        let after = await counter.value
        XCTAssertEqual(before, after, "变形词别名也应命中缓存")
    }

    func testThesaurusMerged() async throws {
        let repo = makeRepo(thesaurus: MockThesaurus(syn: ["jog", "sprint"], ant: ["walk"]))
        let entry = try await repo.lookup(word: "run")
        XCTAssertTrue(entry.synonyms.contains("jog"))
        XCTAssertTrue(entry.antonyms.contains("walk"))
    }

    func testNotFound() async {
        do {
            _ = try await makeRepo().lookup(word: "zzzzqqq")
            XCTFail("应抛出 notFound")
        } catch let error as LookupError {
            XCTAssertEqual(error, .notFound("zzzzqqq"))
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
    }

    func testInvalidWord() async {
        do {
            _ = try await makeRepo().lookup(word: "123")
            XCTFail("应抛出 invalidWord")
        } catch let error as LookupError {
            XCTAssertEqual(error, .invalidWord)
        } catch {
            XCTFail("错误类型不符：\(error)")
        }
    }

    func testDiskCacheRoundTripAndExpiry() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocab-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = DiskDictionaryCache(directory: dir, ttl: 3600)
        await cache.store(runEntry, for: "run")
        let hit = await cache.entry(for: "run")
        XCTAssertEqual(hit?.word, "run")

        let expired = DiskDictionaryCache(directory: dir, ttl: -1)
        let miss = await expired.entry(for: "run")
        XCTAssertNil(miss, "过期缓存应返回 nil")
    }
}
