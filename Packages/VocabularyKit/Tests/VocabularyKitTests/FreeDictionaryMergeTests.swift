import XCTest
@testable import VocabularyKit

final class FreeDictionaryMergeTests: XCTestCase {

    static let fixture = """
    [{"word":"learn","phonetic":"/lɜːn/","phonetics":[{"text":"/lɜːn/","audio":""},{"text":"/lɝn/","audio":"//ssl.gstatic.com/dictionary/static/sounds/learn--_us_1.mp3"}],"meanings":[{"partOfSpeech":"verb","definitions":[{"definition":"To acquire knowledge.","example":"Children learn quickly.","synonyms":["study"],"antonyms":["forget"]},{"definition":"To memorize.","synonyms":[],"antonyms":[]}],"synonyms":["acquire"],"antonyms":[]}]}]
    """

    func testDecodeAndMerge() throws {
        let tokens = try JSONDecoder().decode([FDToken].self, from: Data(Self.fixture.utf8))
        let entry = try XCTUnwrap(FreeDictionaryService.merge(tokens, word: "learn"))
        XCTAssertEqual(entry.word, "learn")
        XCTAssertEqual(entry.definitions.count, 2)
        XCTAssertEqual(entry.definitions[0].partOfSpeech, "verb")
        XCTAssertEqual(entry.definitions[0].meaning, "To acquire knowledge.")
        XCTAssertEqual(entry.examples, ["Children learn quickly."])
        XCTAssertTrue(entry.synonyms.contains("study"))
        XCTAssertTrue(entry.synonyms.contains("acquire"))
        XCTAssertEqual(entry.antonyms, ["forget"])
        // 空 audio 应被忽略，// 前缀应补 https
        let audio = entry.phonetics.compactMap(\.audioURL).first
        XCTAssertEqual(audio?.scheme, "https")
        XCTAssertTrue(entry.phonetics.contains { $0.text == "/lɜːn/" })
    }

    func testEmptyTokensReturnsNil() {
        XCTAssertNil(FreeDictionaryService.merge([], word: "x"))
    }

    func testNotFoundFixture() throws {
        let json = """
        {"title":"No Definitions Found","message":"Sorry pal...","resolution":"You can try..."}
        """
        // 404 时 API 返回对象而非数组，解码应失败（服务层在 404 时直接返回 nil，不会走到这里）
        XCTAssertThrowsError(try JSONDecoder().decode([FDToken].self, from: Data(json.utf8)))
    }
}
