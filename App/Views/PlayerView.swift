import SwiftUI
import AVKit
import AVFoundation

/// 无系统控件的视频画面（自定义控制条）
#if os(macOS)
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.player = player
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}
#else
struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.showsPlaybackControls = false
        vc.player = player
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
#endif

/// 自定义播放控制条
struct PlayerControlsView: View {
    @Bindable var manager: PlayerManager
    var showSizeControl: Bool = false
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @AppStorage("playerWidthFraction") private var playerWidthFraction: Double = 0.85

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 6) {
            // 进度条
            HStack(spacing: 8) {
                Text(Self.formatTime(manager.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { scrubbing ? scrubValue : manager.currentTime },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...max(manager.duration, 1),
                    onEditingChanged: { editing in
                        scrubbing = editing
                        if !editing { manager.seek(to: scrubValue) }
                    }
                )
                Text(Self.formatTime(manager.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // 按钮行
            HStack(spacing: 14) {
                if let line = manager.loopLine {
                    Button {
                        manager.loopLine = nil
                    } label: {
                        Label("单句循环中", systemImage: "repeat.1")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .help("点击取消循环：\(line.text)")
                } else if manager.playingLine != nil {
                    Button {
                        manager.cancelLinePlay()
                    } label: {
                        Label("单句播放中", systemImage: "text.line.first.and.arrowtriangle.forward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .help("点击取消单句播放，继续连续播放")
                }

                Spacer()

                Button { manager.skip(-10) } label: {
                    Image(systemName: "gobackward.10")
                }
                .help("快退 10 秒")

                Button { manager.playPause() } label: {
                    Image(systemName: manager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                }
                .buttonStyle(.plain)
                .help(manager.isPlaying ? "暂停" : "播放")

                Button { manager.skip(10) } label: {
                    Image(systemName: "goforward.10")
                }
                .help("快进 10 秒")

                Spacer()

                Picker("倍速", selection: $manager.rate) {
                    ForEach(rates, id: \.self) { r in
                        Text(String(format: "%.2gx", r)).tag(r)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .help("播放速度")

                if showSizeControl {
                    Menu {
                        Picker("画面大小", selection: $playerWidthFraction) {
                            Text("小（50%）").tag(0.5)
                            Text("中（70%）").tag(0.7)
                            Text("大（85%）").tag(0.85)
                            Text("满宽（100%）").tag(1.0)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .adaptiveMenuStyle()
                    .fixedSize()
                    .help("视频画面大小")
                }

                Image(systemName: manager.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .onTapGesture { manager.volume = manager.volume == 0 ? 1 : 0 }
                Slider(value: $manager.volume, in: 0...1)
                    .frame(width: 70)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
