import SwiftUI
import SwiftData
import VocabularyKit
import ReviewKit

/// 艾宾浩斯复习会话：到期词卡片流（词 → 揭示答案 → 忘记/记得 → 自动排期）
struct ReviewSessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [WordRecord] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var rememberedCount = 0
    @State private var forgotCount = 0
    @State private var loaded = false
    @State private var speech = SpeechService()

    private var current: WordRecord? {
        index < queue.count ? queue[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if !loaded {
                    ProgressView()
                } else if queue.isEmpty {
                    ContentUnavailableView(
                        "今天没有到期的单词",
                        systemImage: "checkmark.seal",
                        description: Text("加入生词本后按 1/2/4/7/15/30 天间隔安排复习")
                    )
                } else if let record = current {
                    card(record)
                } else {
                    summary
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheetFrame(width: 520, height: 480)
        .onAppear { loadQueue() }
    }

    private var header: some View {
        HStack {
            Label("复习", systemImage: "brain.head.profile")
                .font(.headline)
            if !queue.isEmpty, current != nil {
                Text("\(index + 1) / \(queue.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(index), total: Double(queue.count))
                    .frame(width: 100)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    // MARK: - Card

    private func card(_ record: WordRecord) -> some View {
        let entry = try? JSONDecoder().decode(WordEntry.self, from: record.entryData)
        return VStack(spacing: 18) {
            Spacer()
            Text(record.word)
                .font(.system(size: 36, weight: .bold))
                .textSelection(.enabled)
            if let ph = entry?.phonetics.compactMap(\.text).first {
                Text(ph)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("第 \(record.stage + 1) 阶段 · 已复习 \(record.reviewCount) 次")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if revealed {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((entry?.definitions ?? []).prefix(3).enumerated()), id: \.offset) { _, def in
                        HStack(alignment: .top, spacing: 6) {
                            if !def.partOfSpeech.isEmpty {
                                Text(def.partOfSpeech)
                                    .font(.caption.italic())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .leading)
                            }
                            Text(def.meaning)
                                .font(.callout)
                        }
                    }
                    if let ex = entry?.definitions.flatMap(\.examples).first {
                        Text("“\(ex)”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: 380, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))

                Button {
                    if let entry { speech.pronounce(entry) }
                } label: {
                    Label("发音", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)

                HStack(spacing: 16) {
                    Button {
                        grade(.forgot)
                    } label: {
                        Label("忘记了", systemImage: "xmark")
                            .frame(width: 100)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .keyboardShortcut("1", modifiers: [])

                    Button {
                        grade(.remembered)
                    } label: {
                        Label("记得了", systemImage: "checkmark")
                            .frame(width: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut("2", modifiers: [])
                }
                Text("快捷键：1 忘记 / 2 记得")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("先回忆释义，再揭示答案")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    revealed = true
                } label: {
                    Text("显示答案")
                        .frame(width: 140)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
                Text("快捷键：空格")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(20)
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: 14) {
            Image(systemName: "party.popper")
                .font(.system(size: 44))
            Text("复习完成！")
                .font(.title2.bold())
            Text("共 \(queue.count) 词 · 记得 \(rememberedCount) · 忘记 \(forgotCount)")
                .foregroundStyle(.secondary)
            if forgotCount > 0 {
                Text("忘记的词将在 10 分钟后重新到期")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Logic

    private func loadQueue() {
        let now = Date()
        let all = (try? context.fetch(FetchDescriptor<WordRecord>())) ?? []
        queue = all
            .filter { record in
                record.stage < EbbinghausScheduler.intervalsDays.count
                && (record.dueDate ?? .distantPast) <= now
            }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        loaded = true
    }

    private func grade(_ grade: ReviewGrade) {
        guard let record = current else { return }
        let schedule = ReviewSchedule(
            stage: record.stage,
            dueDate: record.dueDate ?? Date(),
            lastReviewedAt: record.lastReviewedAt ?? Date()
        )
        let next = EbbinghausScheduler.next(after: schedule, grade: grade)
        record.stage = next.stage
        record.dueDate = next.dueDate
        record.lastReviewedAt = next.lastReviewedAt
        record.reviewCount += 1
        record.status = EbbinghausScheduler.isMastered(stage: next.stage)
            ? LearningStatus.mastered.rawValue
            : LearningStatus.learning.rawValue
        try? context.save()
        StatsTracker.shared.recordReview()

        switch grade {
        case .remembered: rememberedCount += 1
        case .forgot: forgotCount += 1
        }
        revealed = false
        index += 1
    }
}
