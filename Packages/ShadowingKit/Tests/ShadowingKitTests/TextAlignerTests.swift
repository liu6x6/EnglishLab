import XCTest
@testable import ShadowingKit

final class TextAlignerTests: XCTestCase {

    // MARK: - normalize

    func testNormalizeBasic() {
        XCTAssertEqual(
            TextAligner.normalize("Today we're going to learn English."),
            ["today", "were", "going", "to", "learn", "english"]
        )
    }

    func testNormalizePunctuationAndCase() {
        XCTAssertEqual(
            TextAligner.normalize("HELLO, World! How are you?"),
            ["hello", "world", "how", "are", "you"]
        )
        XCTAssertEqual(TextAligner.normalize("  "), [])
        XCTAssertEqual(TextAligner.normalize("don't"), ["dont"])
        XCTAssertEqual(TextAligner.normalize("It's 2024."), ["its", "2024"])
    }

    // MARK: - align

    func testPerfectMatch() {
        let result = TextAligner.assess(
            targetText: "Today we're going to learn English.",
            recognizedText: "today were going to learn english"
        )
        XCTAssertEqual(result.overallScore, 100)
        XCTAssertEqual(result.correctCount, 6)
        XCTAssertEqual(result.targetCount, 6)
        XCTAssertTrue(result.words.allSatisfy { $0.status == .correct })
        XCTAssertTrue(result.wordsToImprove.isEmpty)
    }

    func testDeletion() {
        // 漏读 learn（设计文档 §6.2 示例）
        let result = TextAligner.assess(
            targetText: "Today we're going to learn English.",
            recognizedText: "today were going to english"
        )
        XCTAssertEqual(result.words.count, 6)
        let learn = result.words.first { $0.targetWord == "learn" }
        XCTAssertEqual(learn?.status, .deletion)
        XCTAssertNil(learn?.recognizedWord)
        XCTAssertEqual(result.correctCount, 5)
        XCTAssertEqual(result.overallScore, 83.3)
    }

    func testSubstitution() {
        let result = TextAligner.assess(
            targetText: "I like apples",
            recognizedText: "I like oranges"
        )
        let last = result.words.last
        XCTAssertEqual(last?.status, .substitution)
        XCTAssertEqual(last?.targetWord, "apples")
        XCTAssertEqual(last?.recognizedWord, "oranges")
        XCTAssertEqual(result.overallScore, 66.7)
        XCTAssertEqual(result.wordsToImprove.map(\.targetWord), ["apples"])
    }

    func testInsertion() {
        let result = TextAligner.assess(
            targetText: "I like apples",
            recognizedText: "I really like apples"
        )
        XCTAssertEqual(result.overallScore, 100, "多读词不扣正确率")
        let insertions = result.words.filter { $0.status == .insertion }
        XCTAssertEqual(insertions.count, 1)
        XCTAssertEqual(insertions.first?.recognizedWord, "really")
        XCTAssertEqual(insertions.first?.targetWord, "")
        // 插入位置在 I 之后
        XCTAssertEqual(insertions.first?.index, 1)
    }

    func testEmptyRecognition() {
        let result = TextAligner.assess(targetText: "Hello world", recognizedText: "")
        XCTAssertEqual(result.overallScore, 0)
        XCTAssertEqual(result.words.count, 2)
        XCTAssertTrue(result.words.allSatisfy { $0.status == .deletion })
    }

    func testEmptyTarget() {
        let result = TextAligner.assess(targetText: "", recognizedText: "hello")
        XCTAssertEqual(result.overallScore, 0)
        XCTAssertEqual(result.targetCount, 0)
        XCTAssertTrue(result.words.allSatisfy { $0.status == .insertion })
    }

    func testMixedErrors() {
        let result = TextAligner.assess(
            targetText: "the quick brown fox jumps",
            recognizedText: "the fast brown fox"
        )
        // quick→fast 替换，jumps 漏读
        XCTAssertEqual(result.words.first { $0.targetWord == "quick" }?.status, .substitution)
        XCTAssertEqual(result.words.first { $0.targetWord == "jumps" }?.status, .deletion)
        XCTAssertEqual(result.correctCount, 3)
        XCTAssertEqual(result.overallScore, 60)
    }

    func testWordOrderPreserved() {
        let result = TextAligner.assess(
            targetText: "a b c d e",
            recognizedText: "a x c e"
        )
        let targets = result.words.filter { !$0.targetWord.isEmpty }.map(\.targetWord)
        XCTAssertEqual(targets, ["a", "b", "c", "d", "e"])
        XCTAssertEqual(result.words.filter { !$0.targetWord.isEmpty }.map(\.index), [0, 1, 2, 3, 4])
    }

    func testResultCodable() throws {
        let result = TextAligner.assess(targetText: "Hello world", recognizedText: "hello")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ShadowingResult.self, from: data)
        XCTAssertEqual(result, decoded)
    }
}
