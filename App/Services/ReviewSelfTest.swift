import Foundation
import SwiftData
import VocabularyKit
import ReviewKit

/// 自检钩子：--selftest-review 启动时运行（临时 store，验证模型迁移+调度集成后退出）
enum ReviewSelfTest {
    @MainActor
    static func run() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("englishlab-selftest-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: tmp.path + suffix))
            }
        }
        do {
            let container = try ModelContainer(
                for: WordRecord.self,
                configurations: ModelConfiguration(url: tmp)
            )
            let context = ModelContext(container)
            let entry = WordEntry(word: "perseverance", definitions: [
                Definition(partOfSpeech: "noun", meaning: "毅力")
            ])
            let record = WordRecord(word: entry.word, entryData: try JSONEncoder().encode(entry))
            context.insert(record)
            try context.save()

            // 1. 新词初始化：当天到期
            let fetched = try context.fetch(FetchDescriptor<WordRecord>()).first!
            precondition(fetched.stage == 0, "stage 应为 0")
            precondition(fetched.dueDate != nil, "dueDate 应已初始化")
            precondition(fetched.dueDate! <= Date(), "新词应当天到期")

            // 2. 复习「记得」→ 阶段推进 + 明天到期
            let schedule = ReviewSchedule(
                stage: fetched.stage, dueDate: fetched.dueDate!, lastReviewedAt: Date()
            )
            let next = EbbinghausScheduler.next(after: schedule, grade: .remembered)
            fetched.stage = next.stage
            fetched.dueDate = next.dueDate
            fetched.lastReviewedAt = next.lastReviewedAt
            fetched.reviewCount += 1
            fetched.status = "learning"
            try context.save()

            let refetched = try context.fetch(FetchDescriptor<WordRecord>()).first!
            precondition(refetched.stage == 1, "复习后 stage 应为 1")
            precondition(refetched.dueDate! > Date(), "下次到期应在未来")
            precondition(refetched.reviewCount == 1)

            print("SELFTEST REVIEW OK")
        } catch {
            print("SELFTEST REVIEW FAILED: \(error)")
            exit(1)
        }
    }
}
