import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 左侧播放列表：素材/自建分组、搜索、导入、进度、继续播放
struct SidebarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MediaItem.addedAt, order: .reverse) private var items: [MediaItem]
    @Query(sort: \Playlist.sortOrder) private var playlists: [Playlist]
    @Binding var selection: MediaItem?
    var onAISubtitle: (MediaItem) -> Void = { _ in }

    @State private var searchText = ""
    @State private var renameTarget: MediaItem?
    @State private var renameText = ""
    @State private var errorMessage: String?
    @State private var newPlaylistPresented = false
    @State private var newPlaylistName = ""
    @State private var pendingAddItem: MediaItem?
    @State private var playlistRenameTarget: Playlist?
    @State private var playlistRenameText = ""
    #if os(iOS)
    /// 导入请求（媒体/字幕共用一个原生选择器，避免多 fileImporter 冲突）
    struct ImportRequest: Identifiable {
        let id = UUID()
        let types: [UTType]
        let multiple: Bool
        let target: MediaItem?
    }
    @State private var importRequest: ImportRequest?
    #endif

    private var videos: [MediaItem] { items.filter { $0.type == .video } }
    private var audios: [MediaItem] { items.filter { $0.type == .audio } }
    private var searchResults: [MediaItem] {
        items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 素材搜索（FR-01.6）
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索素材…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1)))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        importMedia()
                    } label: {
                        Label("导入素材", systemImage: "plus")
                    }
                    Button {
                        newPlaylistName = ""
                        pendingAddItem = nil
                        newPlaylistPresented = true
                    } label: {
                        Label("新建播放列表", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("导入/新建", systemImage: "plus")
                }
                .help("导入素材或新建播放列表")
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
        .alert("新建播放列表", isPresented: $newPlaylistPresented) {
            TextField("名称（如：TED / 美剧 / 考试听力）", text: $newPlaylistName)
            Button("创建") { createPlaylist() }
            Button("取消", role: .cancel) {
                pendingAddItem = nil
                newPlaylistPresented = false
            }
        }
        .alert("重命名播放列表", isPresented: Binding(
            get: { playlistRenameTarget != nil },
            set: { if !$0 { playlistRenameTarget = nil } }
        )) {
            TextField("名称", text: $playlistRenameText)
            Button("确定") {
                playlistRenameTarget?.name = playlistRenameText
                playlistRenameTarget = nil
            }
            Button("取消", role: .cancel) { playlistRenameTarget = nil }
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
        .onAppear {
            // 测试钩子：验证导入选择器能弹出
            if CommandLine.arguments.contains("--selftest-import-picker") {
                importRequest = ImportRequest(
                    types: MediaImporter.mediaTypes + MediaImporter.subtitleTypes,
                    multiple: true,
                    target: nil
                )
            }
        }
        .sheet(item: $importRequest) { request in
            DocumentPicker(types: request.types, multiple: request.multiple) { urls in
                if let target = request.target, let url = urls.first {
                    errorMessage = MediaImporter.attachSubtitle(url, to: target, context: context)
                } else {
                    let r = MediaImporter.importFiles(urls, context: context)
                    errorMessage = r.error
                    if selection == nil { selection = r.imported.first }
                }
                importRequest = nil
            } onCancel: {
                importRequest = nil
            }
            .ignoresSafeArea()
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
            if !searchText.isEmpty {
                Section("搜索结果（\(searchResults.count)）") {
                    ForEach(searchResults) { item in row(item) }
                }
            } else {
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
                ForEach(playlists) { playlist in
                    Section {
                        ForEach(playlist.items.sorted { $0.addedAt > $1.addedAt }) { item in
                            row(item, inPlaylist: playlist)
                        }
                    } header: {
                        Text("\(playlist.name)（\(playlist.items.count)）")
                            .contextMenu {
                                Button("重命名…") {
                                    playlistRenameText = playlist.name
                                    playlistRenameTarget = playlist
                                }
                                Button("删除列表", role: .destructive) {
                                    context.delete(playlist)
                                    try? context.save()
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ item: MediaItem, inPlaylist: Playlist? = nil) -> some View {
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
            Menu("加入播放列表") {
                ForEach(playlists) { playlist in
                    Button(playlist.name) {
                        if !playlist.items.contains(where: { $0.id == item.id }) {
                            playlist.items.append(item)
                            try? context.save()
                        }
                    }
                    .disabled(playlist.items.contains { $0.id == item.id })
                }
                Divider()
                Button("新建播放列表…") {
                    pendingAddItem = item
                    newPlaylistName = ""
                    newPlaylistPresented = true
                }
            }
            if let playlist = inPlaylist {
                Button("从「\(playlist.name)」移出") {
                    playlist.items.removeAll { $0.id == item.id }
                    try? context.save()
                }
            }
            Divider()
            Button("删除", role: .destructive) { delete(item) }
        }
    }

    // MARK: - Playlist actions

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let playlist = Playlist(name: name, sortOrder: playlists.count)
        context.insert(playlist)
        if let item = pendingAddItem {
            playlist.items.append(item)
        }
        try? context.save()
        pendingAddItem = nil
        newPlaylistPresented = false
    }

    // MARK: - Import actions

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
        importRequest = ImportRequest(
            types: MediaImporter.mediaTypes + MediaImporter.subtitleTypes,
            multiple: true,
            target: nil
        )
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
        importRequest = ImportRequest(
            types: MediaImporter.subtitleTypes,
            multiple: false,
            target: item
        )
        #endif
    }

    private func delete(_ item: MediaItem) {
        if selection == item { selection = nil }
        MediaStore.shared.deleteFile(named: item.fileName)
        context.delete(item)
        try? context.save()
    }
}
