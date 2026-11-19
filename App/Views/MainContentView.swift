import SwiftUI

/// 中间主内容区：播放器（居中、大小可调）+ 控制条 + 文本区
struct MainContentView: View {
    @Bindable var manager: PlayerManager
    let item: MediaItem
    var selectedWord: String? = nil
    var onWordTap: (String) -> Void = { _ in }
    var onShadowTap: (SubtitleLine) -> Void = { _ in }
    var onAISubtitle: () -> Void = {}

    @AppStorage("playerWidthFraction") private var playerWidthFraction: Double = 0.85

    var body: some View {
        VStack(spacing: 0) {
            if item.type == .video {
                videoArea
            } else {
                audioHeader
            }

            PlayerControlsView(manager: manager, showSizeControl: item.type == .video)
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

    /// 视频居中显示：宽度按比例可调，严格裁剪防止画面溢出到侧栏
    private var videoArea: some View {
        GeometryReader { geo in
            let w = geo.size.width * playerWidthFraction
            let h = w * 9.0 / 16.0
            PlayerSurface(player: manager.player)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        // 容器高度 = 视频高度（宽 × 比例 × 9/16）
        .aspectRatio(16.0 / 9.0 / playerWidthFraction, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.horizontal, 4)
    }

    private var audioHeader: some View {
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
}
