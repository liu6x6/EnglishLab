import Foundation

/// 一次复习后的排期状态
public struct ReviewSchedule: Codable, Equatable, Sendable {
    /// 已连续记住的次数（0 = 新词/刚忘记）
    public let stage: Int
    /// 下次到期时间
    public let dueDate: Date
    public let lastReviewedAt: Date

    public init(stage: Int, dueDate: Date, lastReviewedAt: Date) {
        self.stage = stage
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
    }
}

public enum ReviewGrade: Sendable {
    case forgot
    case remembered
}

/// 艾宾浩斯间隔复习调度器
/// 记住：进入下一阶段，间隔 1/2/4/7/15/30 天递增；6 阶段全部通过 = 已掌握
/// 忘记：重置到阶段 0，10 分钟后重新出现
public enum EbbinghausScheduler {

    /// 各阶段通过后的下次间隔（天）
    public static let intervalsDays: [Double] = [1, 2, 4, 7, 15, 30]

    /// 忘记后的重现延迟（秒）
    public static let relearnDelay: TimeInterval = 10 * 60

    /// 新词加入生词本：当天即可复习
    public static func initial(now: Date = Date()) -> ReviewSchedule {
        ReviewSchedule(stage: 0, dueDate: now, lastReviewedAt: now)
    }

    public static func next(
        after schedule: ReviewSchedule,
        grade: ReviewGrade,
        now: Date = Date()
    ) -> ReviewSchedule {
        switch grade {
        case .forgot:
            return ReviewSchedule(
                stage: 0,
                dueDate: now.addingTimeInterval(relearnDelay),
                lastReviewedAt: now
            )
        case .remembered:
            let newStage = schedule.stage + 1
            let idx = min(schedule.stage, intervalsDays.count - 1)
            let interval = intervalsDays[idx] * 24 * 3600
            return ReviewSchedule(
                stage: newStage,
                dueDate: now.addingTimeInterval(interval),
                lastReviewedAt: now
            )
        }
    }

    /// 全部阶段通过 → 已掌握
    public static func isMastered(stage: Int) -> Bool {
        stage >= intervalsDays.count
    }

    public static func isDue(_ schedule: ReviewSchedule, now: Date = Date()) -> Bool {
        !isMastered(stage: schedule.stage) && schedule.dueDate <= now
    }
}
