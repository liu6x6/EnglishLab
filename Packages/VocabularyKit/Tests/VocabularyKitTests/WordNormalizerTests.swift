import XCTest
@testable import VocabularyKit

final class WordNormalizerTests: XCTestCase {
    let normalizer = RuleBasedWordNormalizer()

    private func assertContains(_ word: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            normalizer.candidates(for: word).contains(expected),
            "\(word) 的候选中应包含 \(expected)，实际：\(normalizer.candidates(for: word))",
            file: file, line: line
        )
    }

    func testOriginalAlwaysFirst() {
        XCTAssertEqual(normalizer.candidates(for: "running").first, "running")
        XCTAssertEqual(normalizer.candidates(for: "Perseverance").first, "perseverance")
    }

    func testIrregulars() {
        assertContains("went", "go")
        assertContains("children", "child")
        assertContains("were", "be")
        assertContains("taught", "teach")
        assertContains("better", "good")
    }

    func testPlurals() {
        assertContains("cats", "cat")
        assertContains("studies", "study")
        assertContains("boxes", "box")
        assertContains("watches", "watch")
        assertContains("leaves", "leaf")
        assertContains("knives", "knife")
        assertContains("goes", "go")
    }

    func testPastTense() {
        assertContains("walked", "walk")
        assertContains("stopped", "stop")
        assertContains("liked", "like")
        assertContains("tried", "try")
        assertContains("agreed", "agree")
    }

    func testIngForm() {
        assertContains("running", "run")
        assertContains("making", "make")
        assertContains("going", "go")
        assertContains("learning", "learn")
    }

    func testComparatives() {
        assertContains("happier", "happy")
        assertContains("bigger", "big")
        assertContains("nicer", "nice")
    }

    func testNoFalseStemmingOfShortWords() {
        // 短词不应被过度还原
        XCTAssertEqual(normalizer.candidates(for: "is").first, "is")
        XCTAssertFalse(normalizer.candidates(for: "bus").contains("bu"))
        XCTAssertFalse(normalizer.candidates(for: "this").contains("thi"))
    }
}
