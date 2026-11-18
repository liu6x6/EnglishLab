import XCTest
@testable import VocabularyKit

final class ModelsTests: XCTestCase {
    func testWordEntryCodableRoundTrip() throws {
        let entry = WordEntry(
            word: "perseverance",
            phonetics: [Phonetic(text: "/pɜːrsəˈvɪrəns/")],
            definitions: [Definition(partOfSpeech: "noun", meaning: "毅力", examples: ["Success requires perseverance."])],
            synonyms: ["persistence"],
            source: "test"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(WordEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
        XCTAssertEqual(decoded.id, "en:perseverance")
    }
}
