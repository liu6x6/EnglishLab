import SwiftUI
import SwiftData
import VocabularyKit
import UniformTypeIdentifiers

/// 生词本：列表 + 筛选 + 搜索 + 详情 + 状态管理 + CSV/Anki 导出
struct WordbookView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WordRecord.addedAt, order: .reverse) private var records: [WordRecord]

    @State private var statusFilter: LearningStatus?
    @State private var searchText = ""
    @State private var selection: WordRecord?
    @State private var speech = SpeechService()
    #if os(iOS)
    @State private var shareItems: [Any]?
    #endif

    private var filtered: [WordRecord] {
        records.filter { record in
            if let statusFilter, record.statusRaw != statusFilter.rawValue { return false }
            if !searchText.isEmpty,
               !record.word.localizedCaseInsensitiveContains(searchText) { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if records.isEmpty {
                ContentUnavailableView(
                    "生词本是空的",
                    systemImage: "book",
                    description: Text("在文本区点词后，点击「加入生词本」")
                )
                .frame(maxHeight: .infinity)
            } else {
                #if os(macOS)
                HSplitView {
                    list
                        .frame(minWidth: 280, idealWidth: 320)
                    detail
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
                #else
                NavigationStack {
                    List {
                        ForEach(filtered) { record in
                            NavigationLink {
                                ScrollView {
                                    detailContent(record)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .navigationTitle(record.word)
                            } label: {
                                rowContent(record)
                            }
                            .contextMenu {
                                ForEach(LearningStatus.allCases, id: \.self) { status in
                                    Button(status.displayName) { record.status = status.rawValue }
                                }
                                Divider()
                                Button("删除", role: .destructive) { delete(record) }
                            }
                        }
                    }
                }
                #endif
            }
        }
        .sheetMinFrame(width: 760, height: 500)
        #if os(iOS)
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            if let shareItems {
                ShareSheet(items: shareItems)
            }
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("生词本")
                .font(.headline)
            Text("\(filtered.count) / \(records.count) 词")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("状态", selection: $statusFilter) {
                Text("全部").tag(LearningStatus?.none)
                ForEach(LearningStatus.allCases, id: \.self) { s in
                    Text(s.displayName).tag(LearningStatus?.some(s))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)

            TextField("搜索单词…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)

            Spacer()

            Menu {
                Button("导出 CSV") { exportCSV() }
                Button("导出 Anki（TSV 文本）") { exportAnki() }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .adaptiveMenuStyle()
            .fixedSize()
            .disabled(records.isEmpty)

            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: - List

    private var list: some View {
        List(selection: $selection) {
            ForEach(filtered) { record in
                rowContent(record)
                    .tag(record)
                    .contextMenu {
                        ForEach(LearningStatus.allCases, id: \.self) { status in
                            Button(status.displayName) { record.status = status.rawValue }
                        }
                        Divider()
                        Button("删除", role: .destructive) { delete(record) }
                    }
            }
        }
    }

    private func rowContent(_ record: WordRecord) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color(for: record.statusRaw))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.word)
                    .font(.body.weight(.medium))
                Text(firstMeaning(of: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let record = selection {
            ScrollView {
                detailContent(record)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("选择一个单词", systemImage: "book.closed", description: Text("查看释义与学习状态"))
        }
    }

    private func detailContent(_ record: WordRecord) -> some View {
        let entry = decoded(record)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(record.word)
                    .font(.title.bold())
                    .textSelection(.enabled)
                Spacer()
                Button {
                    if let entry { speech.pronounce(entry) }
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
            }
            ForEach(Array((entry?.phonetics ?? []).prefix(2).enumerated()), id: \.offset) { _, ph in
                if let text = ph.text {
                    Text(text).font(.callout).foregroundStyle(.secondary)
                }
            }

            Picker("掌握状态", selection: Binding(
                get: { LearningStatus(rawValue: record.statusRaw) ?? .new },
                set: { record.status = $0.rawValue }
            )) {
                ForEach(LearningStatus.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            ForEach(Array((entry?.definitions ?? []).enumerated()), id: \.offset) { _, def in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 6) {
                        if !def.partOfSpeech.isEmpty {
                            Text(def.partOfSpeech)
                                .font(.caption.italic())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                        }
                        Text(def.meaning)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    ForEach(Array(def.examples.prefix(1).enumerated()), id: \.offset) { _, ex in
                        Text("“\(ex)”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 50)
                    }
                }
            }

            if let syn = entry?.synonyms, !syn.isEmpty {
                Text("近义词：\(syn.prefix(8).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let ant = entry?.antonyms, !ant.isEmpty {
                Text("反义词：\(ant.prefix(8).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if let source = record.sourceTitle {
                    Text("来源素材：\(source)").font(.caption2).foregroundStyle(.tertiary)
                }
                Text("加入时间：\(record.addedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Button("移出生词本", role: .destructive) { delete(record) }
                .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func color(for status: String) -> Color {
        switch LearningStatus(rawValue: status) {
        case .new: return .red
        case .learning: return .orange
        case .mastered: return .green
        case nil: return .gray
        }
    }

    private func decoded(_ record: WordRecord) -> WordEntry? {
        try? JSONDecoder().decode(WordEntry.self, from: record.entryData)
    }

    private func firstMeaning(of record: WordRecord) -> String {
        decoded(record)?.definitions.first?.meaning ?? "—"
    }

    private func delete(_ record: WordRecord) {
        if selection == record { selection = nil }
        context.delete(record)
        try? context.save()
    }

    // MARK: - Export

    private func exportCSV() {
        var csv = "word,status,addedAt,source\n"
        for r in records {
            let source = (r.sourceTitle ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(r.word),\(r.statusRaw),\(r.addedAt.ISO8601Format()),\"\(source)\"\n"
        }
        saveOrShare(content: csv, fileName: "wordbook.csv", type: .commaSeparatedText)
    }

    /// Anki 文本导入格式：#separator:tab + #html:true，Front=单词，Back=音标+释义+例句
    private func exportAnki() {
        var text = "#separator:tab\n#html:true\n#columns:Front\tBack\tTags\n"
        for r in records {
            let entry = decoded(r)
            var backParts: [String] = []
            if let ph = entry?.phonetics.compactMap(\.text).first {
                backParts.append(ph)
            }
            for def in entry?.definitions.prefix(4) ?? [] {
                let pos = def.partOfSpeech.isEmpty ? "" : "<i>\(def.partOfSpeech)</i> "
                backParts.append(pos + Self.escapeHTML(def.meaning))
            }
            if let ex = entry?.definitions.flatMap(\.examples).first {
                backParts.append("<i>“\(Self.escapeHTML(ex))”</i>")
            }
            let front = Self.escapeHTML(r.word)
            let back = backParts.joined(separator: "<br>")
            text += "\(front)\t\(back)\tEnglishLab\n"
        }
        saveOrShare(content: text, fileName: "englishlab_anki.txt", type: .plainText)
    }

    private func saveOrShare(content: String, fileName: String, type: UTType) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        shareItems = [url]
        #endif
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
