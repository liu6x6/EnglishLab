import SwiftUI
import SwiftData

/// iOS「学习」Tab：整合复习/生词本/学习统计/跟读记录
struct LearningTabView: View {
    @Environment(\.modelContext) private var context
    @Query private var wordRecords: [WordRecord]
    @Query private var sessions: [ShadowingSession]

    @State private var showReview = false
    @State private var showWordbook = false
    @State private var showStats = false
    @State private var showShadowHistory = false

    private var dueCount: Int {
        let now = Date()
        return wordRecords.filter { $0.stage < 6 && ($0.dueDate ?? .distantPast) <= now }.count
    }

    private var masteredCount: Int {
        wordRecords.filter { $0.statusRaw == "mastered" }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section("学习工具") {
                    toolRow(
                        icon: "brain.head.profile", color: .purple,
                        title: "复习",
                        subtitle: dueCount > 0 ? "\(dueCount) 个单词到期，开始复习" : "艾宾浩斯间隔复习",
                        badge: dueCount
                    ) { showReview = true }

                    toolRow(
                        icon: "book", color: .orange,
                        title: "生词本",
                        subtitle: "\(wordRecords.count) 词 · 已掌握 \(masteredCount)",
                        badge: 0
                    ) { showWordbook = true }

                    toolRow(
                        icon: "chart.bar", color: .blue,
                        title: "学习统计",
                        subtitle: "学习时长 · 词汇增长",
                        badge: 0
                    ) { showStats = true }

                    toolRow(
                        icon: "waveform", color: .red,
                        title: "跟读记录",
                        subtitle: sessions.isEmpty ? "还没有跟读练习" : "\(sessions.count) 次练习",
                        badge: 0
                    ) { showShadowHistory = true }
                }

                Section {
                    Text("在播放页点词查义、跟读评分后，到这里复习巩固。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("学习")
        }
        .sheet(isPresented: $showReview) { ReviewSessionView() }
        .sheet(isPresented: $showWordbook) { WordbookView() }
        .sheet(isPresented: $showStats) { StatsView() }
        .sheet(isPresented: $showShadowHistory) { ShadowingHistoryView() }
    }

    private func toolRow(
        icon: String, color: Color, title: String, subtitle: String,
        badge: Int, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.red))
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
