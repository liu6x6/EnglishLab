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
    @State private var isDropTargeted = false
    @State private var dropErrorMessage: String?
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
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
                if isCompact, newValue != nil,
                   !CommandLine.arguments.contains("--selftest-import-picker") {
                    selectedTab = 1
                }
                #endif
            }
            .onAppear {
                StatsTracker.shared.configure(context: context)
                vocabulary.configure(context: context)
                restoreLastSessionIfNeeded()
                manager.load(selectedMedia)
                autoImportForTestingIfNeeded()
            }
            .task {
                let args = CommandLine.arguments
                if let idx = args.firstIndex(of: "--selftest-transcribe"), idx + 1 < args.count {
                    await TranscriptionSelfTest.run(path: args[idx + 1])
                }
                if let idx = args.firstIndex(of: "--selftest-audio"), idx + 1 < args.count {
                    await AudioSelfTest.run(urlString: args[idx + 1])
                }
            }
            .onDisappear {
                manager.pause()
            }
            .onChange(of: scenePhase) { _, phase in
                // 切后台/失焦时落库进度与统计（iOS 后台继续播放，不暂停）
                if phase != .active {
                    manager.checkpoint()
                    #if os(macOS)
                    if phase == .background { manager.pause() }
                    #endif
                }
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
            // 拖拽文件自动导入（Finder 拖入窗口任意位置）
            .dropDestination(for: URL.self) { urls, _ in
                let mediaURLs = urls.filter { $0.isFileURL }
                guard !mediaURLs.isEmpty else { return false }
                let result = MediaImporter.importFiles(mediaURLs, context: context)
                if let first = result.imported.first {
                    selectedMedia = first
                }
                dropErrorMessage = result.error
                return !result.imported.isEmpty
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .background(Color.accentColor.opacity(0.08))
                        .overlay {
                            Label("松开导入素材", systemImage: "square.and.arrow.down")
                                .font(.title2.bold())
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .allowsHitTesting(false)
                        .padding(6)
                }
            }
            .alert("导入提示", isPresented: Binding(
                get: { dropErrorMessage != nil },
                set: { if !$0 { dropErrorMessage = nil } }
            )) {
                Button("好", role: .cancel) { dropErrorMessage = nil }
            } message: {
                Text(dropErrorMessage ?? "")
            }
            // 快捷键：.onKeyPress 走原生焦点系统——输入框/列表聚焦时按键被其消费，不会误触发
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(keys: [.space, .leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                switch press.key {
                case .space: manager.playPause()
                case .leftArrow: manager.skip(-10)
                case .rightArrow: manager.skip(10)
                case .upArrow: manager.volume = min(1, manager.volume + 0.1)
                case .downArrow: manager.volume = max(0, manager.volume - 0.1)
                default: return .ignored
                }
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "[]lLhH")) { press in
                switch press.characters.lowercased() {
                case "[": stepRate(-1)
                case "]": stepRate(1)
                case "l": toggleCurrentLineLoop()
                case "h": cycleHideMode()
                default: return .ignored
                }
                return .handled
            }
            .background {
                // ⌘B 带修饰键，不与输入冲突，保留 keyboardShortcut
                Button("") { showWordbook.toggle() }
                    .keyboardShortcut("b", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
    }

    // MARK: - Shortcut actions

    private let rateSteps: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private func stepRate(_ direction: Int) {
        let idx = rateSteps.firstIndex(of: manager.rate) ?? 2
        let next = max(0, min(rateSteps.count - 1, idx + direction))
        manager.rate = rateSteps[next]
    }

    private func toggleCurrentLineLoop() {
        if manager.loopLine != nil {
            manager.loopLine = nil
            return
        }
        guard let item = manager.currentItem else { return }
        let t = manager.currentTime
        if let line = item.lines.first(where: { t >= $0.startTime && t < $0.endTime }) {
            manager.toggleLoop(line)
        }
    }

    private func cycleHideMode() {
        let all = TextHideMode.allCases
        let current = TextHideMode(rawValue: UserDefaults.standard.string(forKey: "transcriptHideMode") ?? "normal") ?? .normal
        if let idx = all.firstIndex(of: current) {
            UserDefaults.standard.set(all[(idx + 1) % all.count].rawValue, forKey: "transcriptHideMode")
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

    /// 启动恢复：自动选中上次学习的素材
    private func restoreLastSessionIfNeeded() {
        guard selectedMedia == nil else { return }
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.lastPlayedAt != nil },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let last = try? context.fetch(descriptor).first {
            selectedMedia = last
            #if DEBUG
            print("[restore] 恢复上次素材：\(last.title)")
            #endif
        }
    }

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
