import SwiftUI

/// 设置窗口（⌘,）
struct SettingsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("transcriptFontSize") private var fontSize: Double = 15
    @AppStorage("defaultRate") private var defaultRate: Double = 1.0

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
        .frame(width: 480, height: 320)
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
