import SwiftUI
import SwiftData
import VocabularyKit

/// 右侧单词详情面板：释义/音标/发音/例句/近反义词/加入生词本
struct WordDetailPanel: View {
    @Bindable var vocabulary: VocabularyManager
    var playerManager: PlayerManager
    var media: MediaItem?

    @Environment(\.modelContext) private var context
    @Query private var records: [WordRecord]
    @Query(sort: \LookupHistory.lastLookedUpAt, order: .reverse) private var history: [LookupHistory]
    @State private var speech = SpeechService()
    @State private var searchText = ""

    private var currentRecord: WordRecord? {
        guard let word = vocabulary.entry?.word else { return nil }
        return records.first { $0.word == word }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 单词/词组搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("查询单词或词组…", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let q = searchText.trimmingCharacters(in: .whitespaces)
                        if !q.isEmpty { vocabulary.lookup(q) }
                    }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
            .padding(10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if vocabulary.isLoading {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("查询「\(vocabulary.selectedWord ?? "")」…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let entry = vocabulary.entry {
                        entryView(entry)
                    } else if let error = vocabulary.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("查询失败", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let word = vocabulary.selectedWord {
                                Button("重试") { vocabulary.lookup(word) }
                            }
                        }
                    } else {
                        historyView
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 空状态：查词历史（可点击重查/清空）
    @ViewBuilder
    private var historyView: some View {
        if history.isEmpty {
            ContentUnavailableView(
                "点词查义",
                systemImage: "character.cursor.ibeam",
                description: Text("点击文本区中的任意英文单词\n或在上方搜索框输入单词/词组")
            )
            .padding(.top, 30)
        } else {
            HStack {
                Text("查词历史").font(.headline)
                Spacer()
                Button("清空", role: .destructive) {
                    for h in history { context.delete(h) }
                    try? context.save()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            ForEach(history.prefix(20)) { item in
                Button {
                    vocabulary.lookup(item.word)
                } label: {
                    HStack {
                        Text(item.word)
                            .font(.callout)
                        Spacer()
                        if item.count > 1 {
                            Text("×\(item.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.lastLookedUpAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func entryView(_ entry: WordEntry) -> some View {
        // 单词 + 发音 + 生词本
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.word)
                    .font(.title.bold())
                    .textSelection(.enabled)
                if entry.source.contains("ECDICT") {
                    Text("中文/离线")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                        .foregroundStyle(.green)
                }
            }
            ForEach(Array(entry.phonetics.prefix(2).enumerated()), id: \.offset) { _, ph in
                if let text = ph.text {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    speech.pronounce(entry)
                } label: {
                    Label("发音", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)

                if let record = currentRecord {
                    Menu {
                        ForEach(LearningStatus.allCases, id: \.self) { status in
                            Button(status.displayName) {
                                record.status = status.rawValue
                            }
                        }
                        Divider()
                        Button("移出生词本", role: .destructive) {
                            context.delete(record)
                        }
                    } label: {
                        Label(LearningStatus(rawValue: record.statusRaw)?.displayName ?? "已加入",
                              systemImage: "checkmark.circle.fill")
                    }
                    .adaptiveMenuStyle()
                    .fixedSize()
                    .tint(.green)
                } else {
                    Button {
                        addToWordbook(entry)
                    } label: {
                        Label("加入生词本", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }

        Divider()

        // 释义
        if !entry.definitions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("释义").font(.headline)
                ForEach(Array(entry.definitions.prefix(6).enumerated()), id: \.offset) { _, def in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 6) {
                            if !def.partOfSpeech.isEmpty {
                                Text(def.partOfSpeech)
                                    .font(.caption.italic())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .leading)
                            }
                            Text(def.meaning)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        ForEach(Array(def.examples.prefix(1).enumerated()), id: \.offset) { _, ex in
                            Text("“\(ex)”")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 46)
                        }
                    }
                }
            }
        }

        // 近义词 / 反义词
        if !entry.synonyms.isEmpty || !entry.antonyms.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !entry.synonyms.isEmpty {
                    chipSection(title: "近义词", words: entry.synonyms, color: .blue)
                }
                if !entry.antonyms.isEmpty {
                    chipSection(title: "反义词", words: entry.antonyms, color: .orange)
                }
            }
        }

        // 当前素材中的例句
        let contextLines = materialExamples(for: entry.word)
        if !contextLines.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("素材中的例句").font(.headline)
                ForEach(contextLines, id: \.id) { line in
                    Button {
                        playerManager.seekToLine(line)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                            Text(PlayerControlsView.formatTime(line.startTime))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
                }
            }
        }

        // 数据来源（CC BY-SA attribution）
        if !entry.source.isEmpty {
            Text("来源：\(entry.source)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func chipSection(title: String, words: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            WordFlowLayout(hSpacing: 6, vSpacing: 5) {
                ForEach(words.prefix(10), id: \.self) { w in
                    Button(w) { vocabulary.lookup(w) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(color)
                }
            }
        }
    }

    /// 从当前素材字幕中找包含该词的句子（最多 3 句）
    private func materialExamples(for word: String) -> [SubtitleLine] {
        guard let media else { return [] }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return media.lines
            .sorted { $0.index < $1.index }
            .filter { line in
                let ns = line.text as NSString
                return regex.firstMatch(in: line.text, range: NSRange(location: 0, length: ns.length)) != nil
            }
            .prefix(3)
            .map { $0 }
    }

    private func addToWordbook(_ entry: WordEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        let record = WordRecord(
            word: entry.word,
            entryData: data,
            sourceTitle: media?.title
        )
        context.insert(record)
        try? context.save()
        StatsTracker.shared.recordWordAdded()
    }
}
