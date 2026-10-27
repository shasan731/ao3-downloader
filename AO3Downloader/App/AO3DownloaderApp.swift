import SwiftUI

@main
struct AO3DownloaderApp: App {
    var body: some Scene {
        WindowGroup { MainView() }
            .defaultSize(width: 1080, height: 720)
        Settings { SettingsView() }
    }
}

