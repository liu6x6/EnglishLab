import XCTest
@testable import VocabularyKit

final class PhraseLookupTests: XCTestCase {
    private let phraseEntry = WordEntry(
        word: "give up",
        definitions: [Definition(partOfSpeech: "verb", meaning: "to stop trying")],
        source: "mock"
    )

    func testPhraseOnlineLookup() async throws {
        let repo = DefaultVocabularyRepository(
            dictionary: MockDictionary(known: ["give up": phraseEntry], counter: CallCounter()),
            cache: MemoryCache()
        )
        let entry = try await repo.lookup(word: "Give  Up")  // 大小写+多空格标准化
        XCTAssertEqual(entry.word, "give up")
    }

    func testPhraseOfflineFallback() async throws {
        let zh = WordEntry(
            word: "give up",
            definitions: [Definition(partOfSpeech: "", meaning: "放弃；投降")],
            source: "ECDICT 离线英汉词典 (MIT)"
        )
        let repo = DefaultVocabularyRepository(
            dictionary: MockDictionary(known: [:], counter: CallCounter()),
            cache: MemoryCache(),
            offline: StubOfflinePhrase(entries: ["give up": zh])
        )
        let entry = try await repo.lookup(word: "give up")
        XCTAssertTrue(entry.definitions[0].meaning.contains("放弃"))
    }

    func testPhraseChineseMerged() async throws {
        let zh = WordEntry(
            word: "give up",
            definitions: [Definition(partOfSpeech: "", meaning: "放弃")],
            source: "ECDICT"
        )
        let repo = DefaultVocabularyRepository(
            dictionary: MockDictionary(known: ["give up": phraseEntry], counter: CallCounter()),
            cache: MemoryCache(),
            offline: StubOfflinePhrase(entries: ["give up": zh])
        )
        let entry = try await repo.lookup(word: "give up")
        XCTAssertTrue(entry.definitions[0].meaning.contains("放弃"))
        XCTAssertTrue(entry.definitions.contains { $0.meaning == "to stop trying" })
    }

    func testPhraseNotFound() async {
        let repo = DefaultVocabularyRepository(
            dictionary: MockDictionary(known: [:], counter: CallCounter()),
            cache: MemoryCache()
        )
        do {
            _ = try await repo.lookup(word: "zzz qqq")
            XCTFail("应抛出 notFound")
        } catch let error as LookupError {
            XCTAssertEqual(error, .notFound("zzz qqq"))
        } catch {
            XCTFail("错误类型不符")
        }
    }

    func testPhraseCached() async throws {
        let cache = MemoryCache()
        let counter = CallCounter()
        let repo = DefaultVocabularyRepository(
            dictionary: MockDictionary(known: ["give up": phraseEntry], counter: counter),
            cache: cache
        )
        _ = try await repo.lookup(word: "give up")
        let before = await counter.value
        _ = try await repo.lookup(word: "give up")
        let after = await counter.value
        XCTAssertEqual(before, after)
    }
}

private struct StubOfflinePhrase: OfflineDictionary {
    let entries: [String: WordEntry]
    func entry(for word: String) -> WordEntry? { entries[word.lowercased()] }
}
