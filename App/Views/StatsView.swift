import SwiftUI
import SwiftData
import Charts

/// 学习统计：汇总卡片 + 近 7 天学习时长 + 词汇增长
struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var dayStats: [DayStat]
    @Query private var words: [WordRecord]
    @Query private var media: [MediaItem]
    @Query private var sessions: [ShadowingSession]

    // MARK: - Derived data

    private var totalListening: Double { dayStats.reduce(0) { $0 + $1.listeningSeconds } }
    private var todayListening: Double { stat(for: Date())?.listeningSeconds ?? 0 }
    private var totalLookups: Int { dayStats.reduce(0) { $0 + $1.lookups } }
    private var totalReviews: Int { dayStats.reduce(0) { $0 + $1.reviews } }
    private var masteredCount: Int { words.filter { $0.statusRaw == "mastered" }.count }
    private var avgShadowScore: Double {
        sessions.isEmpty ? 0 : sessions.map(\.overallScore).reduce(0, +) / Double(sessions.count)
    }

    /// 近 7 天（含今天），每天学习分钟数
    private var last7Listening: [(label: String, date: Date, minutes: Double)] {
        last7Days.map { day in
            (label: Self.dayLabel(day), date: day, minutes: (stat(for: day)?.listeningSeconds ?? 0) / 60)
        }
    }

    /// 近 7 天累计词汇量（窗口前存量 + 每日新增累加）
    private var last7Vocab: [(label: String, date: Date, total: Int)] {
        let windowStart = last7Days.first ?? Date()
        let baseline = words.filter { $0.addedAt < Calendar.current.startOfDay(for: windowStart) }.count
        var running = baseline
        return last7Days.map { day in
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: day))!
            let start = Calendar.current.startOfDay(for: day)
            running += words.filter { $0.addedAt >= start && $0.addedAt < end }.count
            return (label: Self.dayLabel(day), date: day, total: running)
        }
    }

    private var last7Days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    private func stat(for date: Date) -> DayStat? {
        let key = Self.dayKey(date)
        return dayStats.first { $0.day == key }
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f.string(from: date)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("学习统计").font(.headline)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryGrid
                    chartSection(title: "近 7 天学习时长（分钟）") {
                        Chart(last7Listening, id: \.date) { item in
                            BarMark(
                                x: .value("日期", item.label),
                                y: .value("分钟", item.minutes)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                            .cornerRadius(4)
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 180)
                    }
                    chartSection(title: "词汇量增长（累计）") {
                        Chart(last7Vocab, id: \.date) { item in
                            AreaMark(
                                x: .value("日期", item.label),
                                y: .value("词汇量", item.total)
                            )
                            .foregroundStyle(Color.green.opacity(0.2).gradient)
                            LineMark(
                                x: .value("日期", item.label),
                                y: .value("词汇量", item.total)
                            )
                            .foregroundStyle(.green)
                            PointMark(
                                x: .value("日期", item.label),
                                y: .value("词汇量", item.total)
                            )
                            .foregroundStyle(.green)
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 180)
                    }
                }
                .padding(16)
            }
        }
        .sheetFrame(width: 640, height: 600)
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard("今日学习", value: Self.formatDuration(todayListening), icon: "clock", color: .blue)
            statCard("累计学习", value: Self.formatDuration(totalListening), icon: "clock.arrow.circlepath", color: .indigo)
            statCard("生词本", value: "\(words.count) 词", subtitle: "已掌握 \(masteredCount)", icon: "book", color: .orange)
            statCard("点词查询", value: "\(totalLookups) 次", icon: "character.cursor.ibeam", color: .teal)
            statCard("跟读练习", value: "\(sessions.count) 次", subtitle: sessions.isEmpty ? nil : String(format: "平均 %.0f 分", avgShadowScore), icon: "mic", color: .red)
            statCard("复习", value: "\(totalReviews) 次", subtitle: "素材 \(media.count) 个", icon: "brain.head.profile", color: .purple)
        }
    }

    private func statCard(_ title: String, value: String, subtitle: String? = nil, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.07)))
    }

    private func chartSection(title: String, @ViewBuilder chart: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            chart()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.05)))
    }

    static func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            return String(format: "%d 小时 %d 分", minutes / 60, minutes % 60)
        }
        if minutes > 0 { return "\(minutes) 分钟" }
        return seconds > 0 ? "\(Int(seconds)) 秒" : "0 分钟"
    }
}
