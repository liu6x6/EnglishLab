import SwiftUI
import SwiftData
import VocabularyKit

/// 批量加词：粘贴文本 → 提取生词候选 → 勾选 → 逐词查询入库
struct BatchAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [WordRecord]

    @State private var inputText = ""
    @State private var candidates: [String] = []
    @State private var selected: Set<String> = []
    @State private var isAdding = false
    @State private var progress = 0
    @State private var resultMessage: String?
    @State private var vocabulary = VocabularyManager()

    /// 常见停用词（不加生词本）
    private static let stopwords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being", "am",
        "do", "does", "did", "have", "has", "had", "will", "would", "can", "could",
        "shall", "should", "may", "might", "must", "of", "in", "on", "at", "to",
        "for", "with", "by", "from", "as", "and", "or", "but", "not", "no", "so",
        "if", "then", "than", "that", "this", "these", "those", "it", "its",
        "he", "she", "they", "them", "we", "us", "you", "your", "i", "my", "me",
        "his", "her", "their", "our", "what", "which", "who", "whom", "when",
        "where", "why", "how", "all", "any", "both", "each", "few", "more",
        "most", "other", "some", "such", "only", "own", "same", "too", "very",
        "just", "also", "now", "here", "there", "don", "doesn", "didn", "won",
        "isn", "aren", "wasn", "weren", "hasn", "haven", "hadn", "couldn",
        "shouldn", "wouldn", "ll", "ve", "re", "ve", "nt"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("批量加词").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()

            if isAdding {
                addingView
            } else if candidates.isEmpty {
                inputView
            } else {
                candidateList
            }
        }
        .sheetFrame(width: 520, height: 560)
        .onAppear { vocabulary.configure(context: context) }
    }

    private var inputView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("粘贴一段英文文本，自动提取生词候选（过滤常见词与已收藏词）")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $inputText)
                .font(.body)
                .frame(maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                extract()
            } label: {
                Label("提取单词", systemImage: "text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
    }

    private var candidateList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("候选 \(candidates.count) 词，已选 \(selected.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(selected.count == candidates.count ? "全不选" : "全选") {
                    selected = selected.count == candidates.count ? [] : Set(candidates)
                }
                .font(.caption)
                Button("重新提取") {
                    candidates = []
                    selected = []
                }
                .font(.caption)
            }
            .padding(12)
            List(candidates, id: \.self) { word in
                HStack {
                    Image(systemName: selected.contains(word) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(word) ? Color.accentColor : Color.secondary)
                    Text(word)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(word) { selected.remove(word) } else { selected.insert(word) }
                }
            }
            Divider()
            HStack {
                if let resultMessage {
                    Text(resultMessage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await addSelected() }
                } label: {
                    Label("加入生词本（\(selected.count)）", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
                .padding(12)
            }
        }
    }

    private var addingView: some View {
        VStack(spacing: 14) {
            ProgressView(value: Double(progress), total: Double(max(selected.count, 1)))
                .frame(width: 240)
            Text("正在查询并加入 \(progress) / \(selected.count)…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("逐词查询释义（在线+离线），请稍候")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    private func extract() {
        let pattern = "[A-Za-z]+(?:['’\\-][A-Za-z]+)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = inputText as NSString
        let matches = regex.matches(in: inputText, range: NSRange(location: 0, length: ns.length))
        let existing = Set(records.map { $0.word.lowercased() })
        var seen = Set<String>()
        var result: [String] = []
        for m in matches {
            let word = ns.substring(with: m.range).lowercased()
            guard word.count >= 3,
                  !Self.stopwords.contains(word),
                  !existing.contains(word),
                  !seen.contains(word) else { continue }
            seen.insert(word)
            result.append(word)
        }
        candidates = result
        selected = Set(result)
        resultMessage = result.isEmpty ? "没有提取到新词（可能都太常见或已收藏）" : nil
    }

    private func addSelected() async {
        isAdding = true
        progress = 0
        var added = 0
        var failed = 0
        for word in candidates where selected.contains(word) {
            defer { progress += 1 }
            do {
                let entry = try await vocabulary.fetchEntry(for: word)
                guard let data = try? JSONEncoder().encode(entry) else { failed += 1; continue }
                // 查重（查询期间可能已加入）
                let descriptor = FetchDescriptor<WordRecord>(predicate: #Predicate { $0.word == word })
                if (try? context.fetch(descriptor))?.isEmpty == false { continue }
                context.insert(WordRecord(word: entry.word, entryData: data, sourceTitle: "批量导入"))
                StatsTracker.shared.recordWordAdded()
                added += 1
            } catch {
                failed += 1
            }
        }
        try? context.save()
        isAdding = false
        resultMessage = "已加入 \(added) 词" + (failed > 0 ? "，\(failed) 词未找到释义" : "")
        candidates = []
        selected = []
        inputText = ""
    }
}
