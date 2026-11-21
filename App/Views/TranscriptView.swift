import SwiftUI
import SwiftData

/// 文本区：字幕列表、当前句高亮、自动滚动、点句跳转、单句循环
struct TranscriptView: View {
    let item: MediaItem
    @Bindable var manager: PlayerManager
    var selectedWord: String? = nil
    var onWordTap: (String) -> Void = { _ in }
    var onShadowTap: (SubtitleLine) -> Void = { _ in }
    var onAISubtitle: () -> Void = {}
    @State private var autoScroll = true
    @AppStorage("transcriptHideMode") private var hideModeRaw: String = "normal"
    @Environment(\.modelContext) private var context
    @AppStorage("transcriptFontSize") private var fontSize: Double = 15

    private var hideMode: TextHideMode { TextHideMode(rawValue: hideModeRaw) ?? .normal }

    static var attachSubtitleHint: String {
        #if os(iOS)
        return "在素材列表中长按素材 → 关联字幕…\n支持 .srt / .lrc / .vtt / .txt"
        #else
        return "在左侧素材上右键 → 关联字幕…\n支持 .srt / .lrc / .vtt / .txt"
        #endif
    }
    private var hideModeBinding: Binding<TextHideMode> {
        Binding(get: { hideMode }, set: { hideModeRaw = $0.rawValue })
    }

    /// 单句隐藏（持久化在 MediaItem，按 index）
    private var hiddenIndices: Set<Int> {
        Set(item.hiddenLineIndicesCSV.split(separator: ",").compactMap { Int($0) })
    }

    private var lines: [SubtitleLine] {
        item.lines.sorted { $0.index < $1.index }
    }

    /// 是否有有效时间轴（纯文本导入则无）
    private var hasTiming: Bool {
        lines.contains { $0.endTime > 0 }
    }

    private var currentLineID: UUID? {
        guard hasTiming else { return nil }
        let t = manager.currentTime
        return lines.first { t >= $0.startTime && t < $0.endTime }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("文本")
                    .font(.headline)
                if let name = item.subtitleFileName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Picker("文本显示", selection: hideModeBinding) {
                        ForEach(TextHideMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if !hiddenIndices.isEmpty {
                        Divider()
                        Button("显示所有已隐藏句子（\(hiddenIndices.count)）") {
                            item.hiddenLineIndicesCSV = ""
                            try? context.save()
                        }
                    }
                } label: {
                    Image(systemName: hideMode.systemImage)
                }
                .adaptiveMenuStyle()
                .fixedSize()
                .help("文本隐藏模式：\(hideMode.displayName)")

                Button {
                    fontSize = max(11, fontSize - 1)
                } label: { Image(systemName: "textformat.size.smaller") }
                    .buttonStyle(.borderless)
                    .help("减小字号")
                Button {
                    fontSize = min(28, fontSize + 1)
                } label: { Image(systemName: "textformat.size.larger") }
                    .buttonStyle(.borderless)
                    .help("增大字号")
                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                .help("自动滚动到当前句")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if lines.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "未关联字幕",
                        systemImage: "text.alignleft",
                        description: Text(Self.attachSubtitleHint)
                    )
                    if TranscriptionService.isSupported {
                        Button {
                            onAISubtitle()
                        } label: {
                            Label("AI 生成字幕", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
            } else if hideMode == .hidden {
                VStack(spacing: 12) {
                    Image(systemName: "ear")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("盲听模式")
                        .font(.headline)
                    Text("文本已完全隐藏，专注听音频")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("恢复显示") { hideModeRaw = TextHideMode.normal.rawValue }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(lines) { line in
                                SentenceRowView(
                                    line: line,
                                    fontSize: fontSize,
                                    isCurrent: line.id == currentLineID,
                                    isLooping: manager.loopLine?.id == line.id,
                                    showTiming: hasTiming,
                                    selectedWord: selectedWord,
                                    hideMode: hideMode,
                                    isHidden: hiddenIndices.contains(line.index),
                                    onTap: { manager.seekToLine(line) },
                                    onPlayOnce: { manager.playLine(line) },
                                    onLoop: { manager.toggleLoop(line) },
                                    onWordTap: onWordTap,
                                    onToggleHidden: { toggleHidden(line) },
                                    onShadow: { onShadowTap(line) }
                                )
                                .id(line.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: currentLineID) { _, newValue in
                        if autoScroll, let newValue {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleHidden(_ line: SubtitleLine) {
        var indices = hiddenIndices
        if indices.contains(line.index) {
            indices.remove(line.index)
        } else {
            indices.insert(line.index)
        }
        item.hiddenLineIndicesCSV = indices.sorted().map(String.init).joined(separator: ",")
        try? context.save()
    }
}

/// 单句行（后续会加入点词查词）
struct SentenceRowView: View {
    let line: SubtitleLine
    let fontSize: Double
    let isCurrent: Bool
    let isLooping: Bool
    let showTiming: Bool
    var selectedWord: String? = nil
    var hideMode: TextHideMode = .normal
    var isHidden: Bool = false
    let onTap: () -> Void
    var onPlayOnce: () -> Void = {}
    let onLoop: () -> Void
    var onWordTap: (String) -> Void = { _ in }
    var onToggleHidden: () -> Void = {}
    var onShadow: () -> Void = {}

    @State private var isHovered = false

    /// iOS 无悬停，操作按钮常驻显示
    private var actionsVisible: Bool {
        #if os(iOS)
        return true
        #else
        return isHovered
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showTiming {
                Text(PlayerControlsView.formatTime(line.startTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 34, alignment: .trailing)
                    .padding(.top, 3)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
                    .help("跳转到此时间连续播放")
            }
            if isHidden {
                Text("⋯ 此句已隐藏（点击显示）")
                    .font(.system(size: fontSize))
                    .italic()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleHidden() }
            } else {
                WordFlowText(
                    text: line.text,
                    fontSize: fontSize,
                    isCurrent: isCurrent,
                    selectedWord: selectedWord,
                    hideMode: hideMode,
                    onWordTap: onWordTap
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onPlayOnce() }
                .contextMenu {
                    Button(isHidden ? "显示此句" : "隐藏此句（针对性训练）") { onToggleHidden() }
                    Button("复制句子") {
                        Clipboard.copy(line.text)
                    }
                }
            }

            if showTiming {
                Button(action: onPlayOnce) {
                    Image(systemName: "play.circle")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .opacity(actionsVisible ? 1 : 0)
                .help("只播放这一句（播完自动停）")
                .padding(.top, 2)

                Button(action: onShadow) {
                    Image(systemName: "mic")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .opacity(actionsVisible ? 1 : 0)
                .help("跟读此句")
                .padding(.top, 2)

                Button(action: onLoop) {
                    Image(systemName: isLooping ? "repeat.1.circle.fill" : "repeat.1")
                        .foregroundStyle(isLooping ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .opacity(actionsVisible || isLooping ? 1 : 0)
                .help("单句循环播放")
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.accentColor.opacity(0.16)
                      : (isHovered ? Color.gray.opacity(0.08) : Color.clear))
        )
        .onHover { isHovered = $0 }
    }
}
