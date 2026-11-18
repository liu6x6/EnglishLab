import SwiftUI
import ShadowingKit

/// 跟读面板（sheet）：原句 → 录音 → 识别评分 → 着色结果 → 对比回放
struct ShadowingPanel: View {
    @Bindable var shadowing: ShadowingManager
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    sentenceArea
                    phaseArea
                    if let error = shadowing.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                    Text("录音仅保存在本机；识别优先在设备本地完成")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .sheetFrame(width: 560, height: 520)
    }

    private var header: some View {
        HStack {
            Label("跟读练习", systemImage: "mic.fill")
                .font(.headline)
            Spacer()
            if let media = shadowing.media {
                Text(media.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    // MARK: - Sentence

    @ViewBuilder
    private var sentenceArea: some View {
        if let result = shadowing.result, shadowing.phase == .result {
            ScoredSentenceView(result: result, fontSize: 20)
        } else if let line = shadowing.line {
            Text(line.text)
                .font(.system(size: 20, weight: .medium))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
    }

    // MARK: - Phase content

    @ViewBuilder
    private var phaseArea: some View {
        switch shadowing.phase {
        case .idle, .preparing:
            VStack(spacing: 10) {
                ProgressView()
                Text("准备中（首次使用会请求麦克风与语音识别权限）…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .playingOriginal:
            VStack(spacing: 14) {
                Label("正在播放原句，注意语音语调…", systemImage: "speaker.wave.2")
                    .foregroundStyle(.secondary)
                Button("跳过，直接录音") { shadowing.skipOriginal() }
                    .buttonStyle(.bordered)
            }

        case .readyToRecord:
            VStack(spacing: 16) {
                Text("模仿原句，大声读出来")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                recordButton
                Button {
                    shadowing.playOriginal()
                } label: {
                    Label("再听一遍原音", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
            }

        case .recording:
            VStack(spacing: 16) {
                LevelMeterView(level: shadowing.recorder.level)
                    .frame(height: 36)
                    .padding(.horizontal, 40)
                Text(String(format: "%.1fs", shadowing.recorder.elapsed))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    shadowing.finishRecording()
                } label: {
                    Label("完成", systemImage: "stop.circle.fill")
                        .font(.title2)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }

        case .processing:
            VStack(spacing: 10) {
                ProgressView()
                Text("识别中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .result:
            if let result = shadowing.result {
                resultArea(result)
            }

        case .failed:
            VStack(spacing: 14) {
                Button {
                    shadowing.startRecording()
                } label: {
                    Label("再试一次", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                if shadowing.lastRecordingURL != nil {
                    Button {
                        shadowing.playMyRecording()
                    } label: {
                        Label("听我的录音", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var recordButton: some View {
        Button {
            shadowing.startRecording()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text("开始录音")
                    .font(.callout)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    private func resultArea(_ result: ShadowingResult) -> some View {
        VStack(spacing: 16) {
            // 分数
            HStack(spacing: 8) {
                Text(String(format: "%.0f", result.overallScore))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(result.overallScore))
                VStack(alignment: .leading, spacing: 2) {
                    Text("正确率")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(result.correctCount) / \(result.targetCount) 词")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // 待改进
            let improve = result.wordsToImprove
            if !improve.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("待改进").font(.headline)
                    ForEach(improve) { word in
                        HStack(spacing: 6) {
                            Text(word.targetWord)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.red)
                            Text(word.status == .deletion
                                 ? "— 漏读"
                                 : "— 识别为「\(word.recognizedWord ?? "")」")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.06)))
            } else {
                Label("全部读对了，太棒了！", systemImage: "star.fill")
                    .foregroundStyle(.green)
            }

            // 回放对比
            HStack(spacing: 12) {
                Button {
                    shadowing.playOriginal()
                } label: {
                    Label("原音", systemImage: "speaker.wave.2")
                }
                Button {
                    shadowing.playMyRecording()
                } label: {
                    Label("我的录音", systemImage: "person.wave.2")
                }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 12) {
                Button {
                    shadowing.retry()
                } label: {
                    Label("再练一次", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderedProminent)
                Button("完成") { onClose() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 50 { return .orange }
        return .red
    }
}

/// 词级着色句子（绿=正确，红=读错，红+下划线=漏读，灰=多读）
struct ScoredSentenceView: View {
    let result: ShadowingResult
    let fontSize: CGFloat

    var body: some View {
        WordFlowLayout(hSpacing: 6, vSpacing: 6) {
            ForEach(result.words) { word in
                wordView(word)
            }
        }
    }

    @ViewBuilder
    private func wordView(_ word: ScoredWord) -> some View {
        switch word.status {
        case .correct:
            Text(word.targetWord)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.green)
        case .substitution:
            Text(word.targetWord)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.red)
                .help("识别为：\(word.recognizedWord ?? "")")
        case .deletion:
            Text(word.targetWord)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.red)
                .underline()
                .help("漏读")
        case .insertion:
            Text(word.recognizedWord ?? "")
                .font(.system(size: fontSize - 3))
                .italic()
                .foregroundStyle(.gray)
                .help("多读的词")
        }
    }
}

/// 录音电平可视化（跳动的音量条）
struct LevelMeterView: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.15))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geo.size.width * CGFloat(level)))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
    }
}
