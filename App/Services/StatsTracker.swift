import Foundation
import SwiftData

/// 按天聚合的学习统计
@Model
final class DayStat {
    /// 本地日期 key，如 "2026-11-17"（唯一）
    @Attribute(.unique) var day: String
    var date: Date
    var listeningSeconds: Double = 0
    var lookups: Int = 0
    var shadowings: Int = 0
    var wordsAdded: Int = 0
    var reviews: Int = 0

    init(day: String, date: Date) {
        self.day = day
        self.date = date
    }
}

/// 统计埋点收集器（context 由 ContentView 注入）
@MainActor
final class StatsTracker {
    static let shared = StatsTracker()
    private var context: ModelContext?
    private var cachedDay: String = ""
    private var cachedStat: DayStat?

    private init() {}

    func configure(context: ModelContext) {
        self.context = context
        cachedDay = ""
        cachedStat = nil
    }

    func addListening(_ seconds: Double) {
        guard seconds > 0, let stat = todayStat() else { return }
        stat.listeningSeconds += seconds
        save()
    }

    func recordLookup() { todayStat()?.lookups += 1; save() }
    func recordShadowing() { todayStat()?.shadowings += 1; save() }
    func recordWordAdded() { todayStat()?.wordsAdded += 1; save() }
    func recordReview() { todayStat()?.reviews += 1; save() }

    // MARK: - Private

    private func todayStat() -> DayStat? {
        guard let context else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let key = formatter.string(from: Date())
        if key == cachedDay, let cachedStat { return cachedStat }

        let descriptor = FetchDescriptor<DayStat>(predicate: #Predicate { $0.day == key })
        if let existing = try? context.fetch(descriptor).first {
            cachedDay = key
            cachedStat = existing
            return existing
        }
        let stat = DayStat(day: key, date: Calendar.current.startOfDay(for: Date()))
        context.insert(stat)
        cachedDay = key
        cachedStat = stat
        return stat
    }

    private func save() {
        try? context?.save()
    }
}
