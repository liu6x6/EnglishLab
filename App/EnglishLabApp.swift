import SwiftUI
import SwiftData

@main
struct EnglishLabApp: App {
    init() {
        if CommandLine.arguments.contains("--selftest-review") {
            MainActor.assumeIsolated { ReviewSelfTest.run() }
            exit(0)
        }
        UserDefaults.standard.register(defaults: [
            "defaultRate": 1.0,
            "transcriptFontSize": 15.0,
            "appearance": "system"
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [MediaItem.self, Playlist.self, SubtitleLine.self, WordRecord.self, ShadowingSession.self, DayStat.self])
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
