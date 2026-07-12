import SwiftUI

@main
struct ScreenScribeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("幕语", systemImage: menuBarSymbol) {
            MenuBarContentView()
                .environment(model)
        }

        WindowGroup("幕语文稿", id: "transcript") {
            MainWindowView()
                .environment(model)
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 920, height: 680)

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 520, height: 380)
        }
    }

    private var menuBarSymbol: String {
        switch model.state {
        case .recording: "record.circle.fill"
        case .paused: "pause.circle.fill"
        case .finalizing: "waveform.badge.magnifyingglass"
        case .failed: "exclamationmark.triangle.fill"
        default: "waveform"
        }
    }
}

