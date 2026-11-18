import XCTest
@testable import SubtitleKit

final class SubtitleParserTests: XCTestCase {

    func testFormatDetect() {
        XCTAssertEqual(SubtitleFormat.detect(fileName: "a.SRT"), .srt)
        XCTAssertEqual(SubtitleFormat.detect(fileName: "a.lrc"), .lrc)
        XCTAssertEqual(SubtitleFormat.detect(fileName: "a.vtt"), .vtt)
        XCTAssertEqual(SubtitleFormat.detect(fileName: "a.txt"), .txt)
        XCTAssertEqual(SubtitleFormat.detect(fileName: "noext"), .txt)
    }

    func testSRTBasic() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,500
        Hello world.

        2
        00:00:05,000 --> 00:00:08,000
        Second line
        continued here.
        """
        let lines = SubtitleParser.parse(srt, format: .srt)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].start, 1.0)
        XCTAssertEqual(lines[0].end, 4.5)
        XCTAssertEqual(lines[0].text, "Hello world.")
        XCTAssertEqual(lines[1].text, "Second line continued here.")
        XCTAssertEqual(lines[1].index, 1)
    }

    func testSRTWithCRLFAndBOMAndTags() {
        let srt = "\u{FEFF}1\r\n00:01:02,250 --> 00:01:05,000\r\n<i>Italic</i> text\r\n\r\n"
        let lines = SubtitleParser.parse(srt, format: .srt)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].start, 62.25)
        XCTAssertEqual(lines[0].text, "Italic text")
    }

    func testVTT() {
        let vtt = """
        WEBVTT

        cue-1
        00:01.000 --> 00:04.000
        Short timestamp.

        00:05.000 --> 00:09.000 position:10%
        With settings.
        """
        let lines = SubtitleParser.parse(vtt, format: .vtt)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].start, 1)
        XCTAssertEqual(lines[0].end, 4)
        XCTAssertEqual(lines[1].start, 5)
        XCTAssertEqual(lines[1].text, "With settings.")
    }

    func testLRC() {
        let lrc = """
        [ti:My Audio]
        [ar:Someone]
        [00:00.50]Today we're going to talk
        [00:03.20]about learning English.
        [00:06.00][00:20.00]Repeated chorus line
        """
        let lines = SubtitleParser.parse(lrc, format: .lrc)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].start, 0.5)
        XCTAssertEqual(lines[0].end, 3.2)
        XCTAssertEqual(lines[0].text, "Today we're going to talk")
        XCTAssertEqual(lines[2].start, 6.0)
        XCTAssertEqual(lines[2].end, 20.0)
        XCTAssertEqual(lines[3].start, 20.0)
        XCTAssertEqual(lines[3].text, "Repeated chorus line")
    }

    func testLRCLastLineEnd() {
        let lines = SubtitleParser.parse("[01:00]Only line", format: .lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].start, 60)
        XCTAssertEqual(lines[0].end, 65)
    }

    func testPlainText() {
        let txt = "Hello there. How are you?\n\nI am fine! Thanks.\nAnd you"
        let lines = SubtitleParser.parse(txt, format: .txt)
        XCTAssertEqual(lines.map(\.text), [
            "Hello there.", "How are you?", "I am fine!", "Thanks.", "And you"
        ])
        XCTAssertTrue(lines.allSatisfy { $0.start == 0 && $0.end == 0 })
    }

    func testInvalidBlocksSkipped() {
        let srt = """
        not a cue at all

        2
        00:00:10,000 --> 00:00:05,000
        end before start, skipped

        3
        00:00:11,000 --> 00:00:12,000
        valid
        """
        let lines = SubtitleParser.parse(srt, format: .srt)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "valid")
    }

    func testTimestampParsing() {
        XCTAssertEqual(SubtitleParser.parseTimestamp("00:00:01,000"), 1)
        XCTAssertEqual(SubtitleParser.parseTimestamp("01:02.250"), 62.25)
        XCTAssertEqual(SubtitleParser.parseTimestamp("02:03"), 123)
        XCTAssertNil(SubtitleParser.parseTimestamp("abc"))
        XCTAssertNil(SubtitleParser.parseTimestamp("12"))
    }
}
