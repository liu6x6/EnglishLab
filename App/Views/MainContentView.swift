import SwiftUI

/// 中间主内容区：播放器 + 控制条 + 文本区
struct MainContentView: View {
    @Bindable var manager: PlayerManager
    let item: MediaItem
    var selectedWord: String? = nil
    var onWordTap: (String) -> Void = { _ in }
    var onShadowTap: (SubtitleLine) -> Void = { _ in }
    var onAISubtitle: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            if item.type == .video {
                PlayerSurface(player: manager.player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("音频素材")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.06))
            }

            PlayerControlsView(manager: manager)
            Divider()
            TranscriptView(
                item: item,
                manager: manager,
                selectedWord: selectedWord,
                onWordTap: onWordTap,
                onShadowTap: onShadowTap,
                onAISubtitle: onAISubtitle
            )
            .frame(maxHeight: .infinity)
        }
    }
}
