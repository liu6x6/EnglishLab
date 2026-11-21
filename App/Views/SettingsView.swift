import SwiftUI

/// 设置窗口（⌘,）
struct SettingsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("transcriptFontSize") private var fontSize: Double = 15
    @AppStorage("defaultRate") private var defaultRate: Double = 1.0
    @AppStorage("playerWidthFraction") private var playerWidthFraction: Double = 0.85
    @AppStorage("transcriptionEngine") private var transcriptionEngine: String = "auto"
    @State private var modelManager = WhisperModelManager.shared

    var body: some View {
        TabView {
            Form {
                Picker("主题", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("字幕字号")
                    Slider(value: $fontSize, in: 11...28, step: 1)
                    Text("\(Int(fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44)
                }

                Picker("默认播放速度", selection: $defaultRate) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                        Text(String(format: "%.2gx", r)).tag(r)
                    }
                }
                Text("新加载素材时应用；播放中可随时用控制条或 [ ] 键调整")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("视频画面宽度")
                    Slider(value: $playerWidthFraction, in: 0.4...1.0, step: 0.05)
                    Text("\(Int(playerWidthFraction * 100))%")
                        .monospacedDigit()
                        .frame(width: 44)
                }
                Text("视频居中显示；也可在播放控制条右侧快速切换")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                shortcutRow("空格", "播放 / 暂停")
                shortcutRow("← / →", "快退 / 快进 10 秒")
                shortcutRow("↑ / ↓", "音量 + / −")
                shortcutRow("[ / ]", "减速 / 加速")
                shortcutRow("L", "当前句单句循环")
                shortcutRow("H", "切换文本隐藏模式")
                shortcutRow("⌘B", "打开生词本")
                Text("提示：焦点在列表或输入框时，部分按键可能被系统控件占用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Label("快捷键", systemImage: "keyboard") }

            transcriptionTab
                .tabItem { Label("转写", systemImage: "waveform.badge.magnifyingglass") }

            Form {
                LabeledContent("词典数据", value: "dictionaryapi.dev（Wiktionary，CC BY-SA 3.0）")
                LabeledContent("近反义词", value: "Datamuse API")
                LabeledContent("发音", value: "Wiktionary 音频 / 系统 TTS")
                Text("查询结果本地缓存 30 天；生词本与录音仅存本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        #if os(macOS)
        .frame(width: 520, height: 460)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    // MARK: - 转写引擎与模型

    private var transcriptionTab: some View {
        Form {
            Picker("AI 字幕引擎", selection: $transcriptionEngine) {
                Text("自动").tag("auto")
                Text("Apple").tag("apple")
                Text("Whisper").tag("whisper")
            }
            .pickerStyle(.segmented)
            Text(engineHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("Whisper 模型（设备端运行，首次需下载）") {
                ForEach(WhisperModel.catalog) { model in
                    modelRow(model)
                }
            }
        }
        .padding(20)
    }

    private var engineHint: String {
        switch transcriptionEngine {
        case "apple":
            return TranscriptionService.isSupported
                ? "Apple SpeechTranscriber：系统级优化，极快。"
                : "当前系统不支持 Apple 引擎（需 macOS 26 / iOS 26），将自动回退 Whisper。"
        case "whisper":
            return "whisper.cpp：Metal/Accelerate 加速，支持 macOS 14 / iOS 17+。"
        default:
            return TranscriptionService.isSupported
                ? "自动：优先 Apple 引擎（macOS 26 / iOS 26+）。"
                : "自动：当前系统低于 26，使用 whisper.cpp（需先下载模型）。"
        }
    }

    @ViewBuilder
    private func modelRow(_ model: WhisperModel) -> some View {
        let status = modelManager.status(for: model)
        let isActive = modelManager.activeModelName == model.name
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.callout.weight(.medium))
                        if isActive, status == .downloaded {
                            Text("使用中")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                                .foregroundStyle(.green)
                        }
                    }
                    Text("\(model.sizeMB) MB · \(model.note)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                switch status {
                case .notDownloaded:
                    Button("下载") { modelManager.download(model) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                case .downloading(let progress):
                    HStack(spacing: 6) {
                        ProgressView(value: progress)
                            .frame(width: 60)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2.monospacedDigit())
                        Button("取消") { modelManager.cancelDownload(model) }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                    }
                case .downloaded:
                    HStack(spacing: 8) {
                        if !isActive {
                            Button("使用") { modelManager.activeModelName = model.name }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        Button(role: .destructive) {
                            modelManager.delete(model)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                case .failed(let message):
                    HStack(spacing: 6) {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                        Button("重试") { modelManager.download(model) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func shortcutRow(_ key: String, _ action: String) -> some View {
        LabeledContent {
            Text(action)
        } label: {
            Text(key)
                .font(.body.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.15)))
        }
    }
}
