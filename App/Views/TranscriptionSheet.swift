import SwiftUI

/// AI 字幕生成进度面板
struct TranscriptionSheet: View {
    @Bindable var manager: TranscriptionManager

    var body: some View {
        VStack(spacing: 18) {
            switch manager.state {
            case .idle:
                EmptyView()

            case .running(let status):
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(.purple)
                Text("AI 生成字幕")
                    .font(.headline)
                Text(manager.targetTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView()
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("设备本地转写，不上传音频")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 12) {
                    Button("后台运行") { manager.dismiss() }
                        .buttonStyle(.bordered)
                    Button("取消", role: .cancel) { manager.cancel() }
                        .buttonStyle(.bordered)
                }

            case .done(let count):
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
                Text("字幕生成完成")
                    .font(.headline)
                Text("共 \(count) 句，已带时间轴，可直接点词/跟读")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("完成") { manager.dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("生成失败")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("关闭") { manager.dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .sheetFrame(width: 380, height: 300)
    }
}
