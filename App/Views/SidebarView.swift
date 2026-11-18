import SwiftUI
import SwiftData

/// 左侧播放列表：素材列表、导入（NSOpenPanel）、进度、继续播放
struct SidebarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MediaItem.addedAt, order: .reverse) private var items: [MediaItem]
    @Binding var selection: MediaItem?
    var onAISubtitle: (MediaItem) -> Void = { _ in }

    @State private var renameTarget: MediaItem?
    @State private var renameText = ""
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var showMediaPicker = false
    @State private var showSubtitlePicker = false
    @State private var subtitleTarget: MediaItem?
    #endif

    private var videos: [MediaItem] { items.filter { $0.type == .video } }
    private var audios: [MediaItem] { items.filter { $0.type == .audio } }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    importMedia()
                } label: {
                    Label("导入素材", systemImage: "plus")
                }
                .help("导入视频/音频（可同时选择同名字幕文件）")
            }
        }
        .alert("重命名", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("标题", text: $renameText)
            Button("确定") {
                renameTarget?.title = renameText
                renameTarget = nil
            }
            Button("取消", role: .cancel) { renameTarget = nil }
        }
        .alert("导入提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(iOS)
        .fileImporter(
            isPresented: $showMediaPicker,
            allowedContentTypes: MediaImporter.mediaTypes + MediaImporter.subtitleTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let r = MediaImporter.importFiles(urls, context: context)
                errorMessage = r.error
                if selection == nil { selection = r.imported.first }
            }
        }
        .fileImporter(
            isPresented: $showSubtitlePicker,
            allowedContentTypes: MediaImporter.subtitleTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first, let target = subtitleTarget {
                errorMessage = MediaImporter.attachSubtitle(url, to: target, context: context)
            }
            subtitleTarget = nil
        }
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("还没有素材")
                .font(.headline)
            Text("导入你的第一个音频/视频\n开始沉浸式学习")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("导入素材") { importMedia() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var list: some View {
        List(selection: $selection) {
            if !videos.isEmpty {
                Section("视频") {
                    ForEach(videos) { item in row(item) }
                }
            }
            if !audios.isEmpty {
                Section("音频") {
                    ForEach(audios) { item in row(item) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ item: MediaItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.type == .video ? "film" : "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ProgressView(value: item.progress)
                        .frame(width: 60)
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !item.lines.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("已关联字幕 \(item.lines.count) 句")
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .tag(item)
        .contextMenu {
            Button("AI 生成字幕") { onAISubtitle(item) }
            Button("关联字幕…") { attachSubtitle(to: item) }
            Button("重命名…") {
                renameText = item.title
                renameTarget = item
            }
            Divider()
            Button("删除", role: .destructive) { delete(item) }
        }
    }

    // MARK: - Actions（NSOpenPanel，macOS 原生可靠）

    private func importMedia() {
        #if os(macOS)
        guard let urls = MediaImporter.openPanel(
            types: MediaImporter.mediaTypes + MediaImporter.subtitleTypes,
            multiple: true,
            message: "选择视频/音频文件（可同时选择同名字幕自动配对）"
        ) else { return }
        let result = MediaImporter.importFiles(urls, context: context)
        errorMessage = result.error
        if selection == nil { selection = result.imported.first }
        #else
        showMediaPicker = true
        #endif
    }

    private func attachSubtitle(to item: MediaItem) {
        #if os(macOS)
        guard let urls = MediaImporter.openPanel(
            types: MediaImporter.subtitleTypes,
            multiple: false,
            message: "为「\(item.title)」选择字幕文件（.srt / .lrc / .vtt / .txt）"
        ), let url = urls.first else { return }
        errorMessage = MediaImporter.attachSubtitle(url, to: item, context: context)
        #else
        subtitleTarget = item
        showSubtitlePicker = true
        #endif
    }

    private func delete(_ item: MediaItem) {
        if selection == item { selection = nil }
        MediaStore.shared.deleteFile(named: item.fileName)
        context.delete(item)
        try? context.save()
    }
}
