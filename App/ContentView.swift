import SwiftUI
import SwiftData

/// 主界面：macOS/iPad 三栏；iPhone 底部 Tab（素材/播放/单词）
struct ContentView: View {
    @State private var selectedMedia: MediaItem?
    @State private var manager = PlayerManager()
    @State private var vocabulary = VocabularyManager()
    @State private var showWordbook = false
    @State private var shadowing = ShadowingManager()
    @State private var showShadowing = false
    @State private var showShadowHistory = false
    @State private var showReview = false
    @State private var showStats = false
    @State private var transcription = TranscriptionManager()
    @State private var aiOverwriteTarget: MediaItem?
    @Environment(\.modelContext) private var context
    @Query private var wordRecords: [WordRecord]
    @AppStorage("appearance") private var appearance: String = "system"

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab = 0
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #endif

    private var dueCount: Int {
        let now = Date()
        return wordRecords.filter { $0.stage < 6 && ($0.dueDate ?? .distantPast) <= now }.count
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        layout
            .onChange(of: selectedMedia) { _, newValue in
                manager.load(newValue)
                #if os(iOS)
                if isCompact, newValue != nil { selectedTab = 1 }
                #endif
            }
            .onAppear {
                StatsTracker.shared.configure(context: context)
                manager.load(selectedMedia)
                autoImportForTestingIfNeeded()
            }
            .task {
                let args = CommandLine.arguments
                if let idx = args.firstIndex(of: "--selftest-transcribe"), idx + 1 < args.count {
                    await TranscriptionSelfTest.run(path: args[idx + 1])
                }
            }
            .onDisappear {
                manager.pause()
            }
            .sheet(isPresented: $showWordbook) {
                WordbookView()
            }
            .sheet(isPresented: $showShadowing, onDismiss: { shadowing.close() }) {
                ShadowingPanel(shadowing: shadowing) {
                    showShadowing = false
                }
            }
            .sheet(isPresented: $showShadowHistory) {
                ShadowingHistoryView()
            }
            .sheet(isPresented: $showReview) {
                ReviewSessionView()
            }
            .sheet(isPresented: $showStats) {
                StatsView()
            }
            .sheet(isPresented: $transcription.isPresented) {
                TranscriptionSheet(manager: transcription)
            }
            .alert("替换现有字幕？", isPresented: Binding(
                get: { aiOverwriteTarget != nil },
                set: { if !$0 { aiOverwriteTarget = nil } }
            )) {
                Button("替换", role: .destructive) {
                    if let target = aiOverwriteTarget {
                        transcription.generate(for: target, context: context)
                    }
                    aiOverwriteTarget = nil
                }
                Button("取消", role: .cancel) { aiOverwriteTarget = nil }
            } message: {
                Text("「\(aiOverwriteTarget?.title ?? "")」已有 \(aiOverwriteTarget?.lines.count ?? 0) 句字幕，AI 生成将替换它们。")
            }
            .preferredColorScheme(colorScheme)
            .background {
                PlayerShortcuts(manager: manager, showWordbook: $showWordbook)
            }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if isCompact {
            tabLayout
        } else {
            splitLayout
        }
        #else
        splitLayout
        #endif
    }

    private var splitLayout: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedMedia, onAISubtitle: requestAISubtitle)
                .columnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            mainContent
                .columnWidth(min: 480, ideal: 700)
        } detail: {
            wordDetail
                .columnWidth(min: 260, ideal: 300, max: 400)
        }
        .toolbar { mainToolbar }
    }

    #if os(iOS)
    private var tabLayout: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SidebarView(selection: $selectedMedia, onAISubtitle: requestAISubtitle)
                    .navigationTitle("素材")
                    .toolbar { mainToolbar }
            }
            .tabItem { Label("素材", systemImage: "rectangle.stack") }
            .tag(0)

            NavigationStack {
                mainContent
                    .navigationTitle(selectedMedia?.title ?? "播放")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("播放", systemImage: "play.circle") }
            .tag(1)

            NavigationStack {
                wordDetail
                    .navigationTitle("单词详情")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("单词", systemImage: "character.book.closed") }
            .tag(2)
        }
    }
    #endif

    @ViewBuilder
    private var mainContent: some View {
        if let item = selectedMedia {
            MainContentView(
                manager: manager,
                item: item,
                selectedWord: vocabulary.selectedWord,
                onWordTap: { word in
                    vocabulary.lookup(word)
                    #if os(iOS)
                    if isCompact { selectedTab = 2 }
                    #endif
                },
                onShadowTap: { line in
                    shadowing.start(line: line, media: item, player: manager, context: context)
                    showShadowing = true
                },
                onAISubtitle: { requestAISubtitle(item) }
            )
        } else {
            ContentUnavailableView(
                "选择或导入素材",
                systemImage: "play.rectangle",
                description: Text("从素材列表选择，或点击 + 导入")
            )
        }
    }

    private var wordDetail: some View {
        WordDetailPanel(
            vocabulary: vocabulary,
            playerManager: manager,
            media: selectedMedia
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                showReview = true
            } label: {
                Label("复习", systemImage: "brain.head.profile")
                    .overlay(alignment: .topTrailing) {
                        if dueCount > 0 {
                            Text("\(dueCount)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(.red))
                                .offset(x: 10, y: -10)
                        }
                    }
            }
            .help(dueCount > 0 ? "\(dueCount) 个单词到期，开始复习" : "艾宾浩斯复习")
        }
        ToolbarItem {
            Button {
                showShadowHistory = true
            } label: {
                Label("跟读记录", systemImage: "waveform")
            }
            .help("查看历史跟读记录与评分")
        }
        ToolbarItem {
            Button {
                showWordbook = true
            } label: {
                Label("生词本", systemImage: "book")
            }
            .help("打开生词本")
        }
        ToolbarItem {
            Button {
                showStats = true
            } label: {
                Label("学习统计", systemImage: "chart.bar")
            }
            .help("查看学习时长、词汇增长等统计")
        }
    }

    // MARK: - Actions

    /// AI 字幕：无字幕直接生成；已有字幕先确认替换
    private func requestAISubtitle(_ item: MediaItem) {
        if item.lines.isEmpty {
            transcription.generate(for: item, context: context)
        } else {
            aiOverwriteTarget = item
        }
    }

    /// 测试钩子：--import-samples-dir <路径> 启动时自动导入目录内素材（验证导入链路）
    private func autoImportForTestingIfNeeded() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--import-samples-dir"), idx + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[idx + 1])
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ), !files.isEmpty else { return }
        let result = MediaImporter.importFiles(files, context: context)
        if selectedMedia == nil { selectedMedia = result.imported.first }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [MediaItem.self, Playlist.self, SubtitleLine.self, WordRecord.self], inMemory: true)
}
