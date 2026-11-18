import XCTest
@testable import ReviewKit

final class EbbinghausSchedulerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testInitialDueImmediately() {
        let s = EbbinghausScheduler.initial(now: now)
        XCTAssertEqual(s.stage, 0)
        XCTAssertEqual(s.dueDate, now)
        XCTAssertTrue(EbbinghausScheduler.isDue(s, now: now))
    }

    func testRememberedProgressesIntervals() {
        var s = EbbinghausScheduler.initial(now: now)
        let expectedDays: [Double] = [1, 2, 4, 7, 15, 30]
        for (i, days) in expectedDays.enumerated() {
            s = EbbinghausScheduler.next(after: s, grade: .remembered, now: now)
            XCTAssertEqual(s.stage, i + 1)
            XCTAssertEqual(s.dueDate.timeIntervalSince(now), days * 24 * 3600, accuracy: 0.001)
            XCTAssertEqual(s.lastReviewedAt, now)
        }
        XCTAssertTrue(EbbinghausScheduler.isMastered(stage: s.stage))
        XCTAssertFalse(EbbinghausScheduler.isDue(s, now: now.addingTimeInterval(100 * 24 * 3600)))
    }

    func testForgotResets() {
        var s = EbbinghausScheduler.initial(now: now)
        s = EbbinghausScheduler.next(after: s, grade: .remembered, now: now)
        s = EbbinghausScheduler.next(after: s, grade: .remembered, now: now)
        XCTAssertEqual(s.stage, 2)
        s = EbbinghausScheduler.next(after: s, grade: .forgot, now: now)
        XCTAssertEqual(s.stage, 0)
        XCTAssertEqual(s.dueDate.timeIntervalSince(now), 600, accuracy: 0.001)
        XCTAssertFalse(EbbinghausScheduler.isDue(s, now: now))
        XCTAssertTrue(EbbinghausScheduler.isDue(s, now: now.addingTimeInterval(601)))
    }

    func testNotDueBeforeDueDate() {
        let s = EbbinghausScheduler.next(
            after: EbbinghausScheduler.initial(now: now), grade: .remembered, now: now
        )
        XCTAssertFalse(EbbinghausScheduler.isDue(s, now: now.addingTimeInterval(3600)))
        XCTAssertTrue(EbbinghausScheduler.isDue(s, now: now.addingTimeInterval(24 * 3600)))
    }

    func testMasteredNeverDue() {
        XCTAssertFalse(EbbinghausScheduler.isMastered(stage: 5))
        XCTAssertTrue(EbbinghausScheduler.isMastered(stage: 6))
        let mastered = ReviewSchedule(stage: 6, dueDate: .distantPast, lastReviewedAt: now)
        XCTAssertFalse(EbbinghausScheduler.isDue(mastered, now: now))
    }

    func testScheduleCodable() throws {
        let s = EbbinghausScheduler.initial(now: now)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(ReviewSchedule.self, from: data), s)
    }
}
