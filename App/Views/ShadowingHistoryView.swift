import SwiftUI
import SwiftData
import AVFoundation
import ShadowingKit

/// 跟读记录：历史会话列表 + 着色结果回放 + 删除
struct ShadowingHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShadowingSession.recordedAt, order: .reverse) private var sessions: [ShadowingSession]

    @State private var selection: ShadowingSession?
    @State private var searchText = ""
    @State private var player: AVPlayer?

    private var filtered: [ShadowingSession] {
        guard !searchText.isEmpty else { return sessions }
        return sessions.filter {
            $0.targetText.localizedCaseInsensitiveContains(searchText)
            || $0.mediaTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if sessions.isEmpty {
                ContentUnavailableView(
                    "还没有跟读记录",
                    systemImage: "mic",
                    description: Text("在文本区句子旁点击 🎙 开始跟读练习")
                )
                .frame(maxHeight: .infinity)
            } else {
                #if os(macOS)
                HSplitView {
                    list.frame(minWidth: 300, idealWidth: 340)
                    detail.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }
                #else
                NavigationStack {
                    List {
                        ForEach(filtered) { session in
                            NavigationLink {
                                ScrollView {
                                    detailContent(session)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .navigationTitle("跟读详情")
                            } label: {
                                rowContent(session)
                            }
                            .contextMenu {
                                Button("删除记录", role: .destructive) { delete(session) }
                            }
                        }
                    }
                }
                #endif
            }
        }
        .sheetMinFrame(width: 800, height: 520)
        .onDisappear { player?.pause() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("跟读记录")
                .font(.headline)
            Text("\(sessions.count) 次练习")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !sessions.isEmpty {
                Text(String(format: "平均 %.0f 分", averageScore))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("搜索句子或素材…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var averageScore: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.map(\.overallScore).reduce(0, +) / Double(sessions.count)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(filtered) { session in
                rowContent(session)
                    .tag(session)
                    .contextMenu {
                        Button("删除记录", role: .destructive) { delete(session) }
                    }
            }
        }
    }

    private func rowContent(_ session: ShadowingSession) -> some View {
        HStack(spacing: 10) {
            scoreBadge(session.overallScore)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.targetText)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(session.mediaTitle) · \(session.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session = selection {
            ScrollView {
                detailContent(session)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("选择一条记录", systemImage: "waveform", description: Text("查看着色结果并回放录音"))
        }
    }

    private func detailContent(_ session: ShadowingSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                scoreBadge(session.overallScore, large: true)
                Spacer()
                Button {
                    play(session)
                } label: {
                    Label("回放我的录音", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
            }

            if let result = decodedResult(session) {
                ScoredSentenceView(result: result, fontSize: 18)
                let improve = result.wordsToImprove
                if !improve.isEmpty {
                    Text("待改进：\(improve.map(\.targetWord).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text(session.targetText)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("识别结果").font(.headline)
                Text(session.recognizedText.isEmpty ? "（无）" : session.recognizedText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()
            Text("素材：\(session.mediaTitle)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("时间：\(session.recordedAt.formatted())")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button("删除记录", role: .destructive) { delete(session) }
        }
    }

    // MARK: - Helpers

    private func scoreBadge(_ score: Double, large: Bool = false) -> some View {
        Text(String(format: "%.0f", score))
            .font(large ? .title2.bold().monospacedDigit() : .caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: large ? 52 : 34, height: large ? 52 : 24)
            .background(
                RoundedRectangle(cornerRadius: large ? 12 : 6)
                    .fill(score >= 80 ? Color.green : (score >= 50 ? Color.orange : Color.red))
            )
    }

    private func decodedResult(_ session: ShadowingSession) -> ShadowingResult? {
        guard let data = session.resultData else { return nil }
        return try? JSONDecoder().decode(ShadowingResult.self, from: data)
    }

    private func play(_ session: ShadowingSession) {
        player?.pause()
        let url = RecordingStore.shared.url(for: session.audioFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let p = AVPlayer(url: url)
        player = p
        p.play()
    }

    private func delete(_ session: ShadowingSession) {
        if selection == session { selection = nil }
        RecordingStore.shared.delete(fileName: session.audioFileName)
        context.delete(session)
        try? context.save()
    }
}
