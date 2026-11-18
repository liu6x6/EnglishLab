import SwiftUI

/// 隐藏按钮承载全局快捷键（挂在主窗口上）
struct PlayerShortcuts: View {
    @Bindable var manager: PlayerManager
    @Binding var showWordbook: Bool

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        Group {
            Button("") { manager.playPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { manager.skip(-10) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { manager.skip(10) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { manager.volume = min(1, manager.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("") { manager.volume = max(0, manager.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("") { stepRate(-1) }
                .keyboardShortcut("[", modifiers: [])
            Button("") { stepRate(1) }
                .keyboardShortcut("]", modifiers: [])
            Button("") { toggleCurrentLineLoop() }
                .keyboardShortcut("l", modifiers: [])
            Button("") { showWordbook.toggle() }
                .keyboardShortcut("b", modifiers: .command)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func stepRate(_ direction: Int) {
        let idx = rates.firstIndex(of: manager.rate) ?? 2
        let next = max(0, min(rates.count - 1, idx + direction))
        manager.rate = rates[next]
    }

    private func toggleCurrentLineLoop() {
        if let looping = manager.loopLine {
            manager.loopLine = nil
            _ = looping
            return
        }
        guard let item = manager.currentItem else { return }
        let t = manager.currentTime
        if let line = item.lines.first(where: { t >= $0.startTime && t < $0.endTime }) {
            manager.toggleLoop(line)
        }
    }
}
