import SwiftUI

@main
struct AO3DownloaderApp: App {
    var body: some Scene {
        WindowGroup { MainView() }
            .defaultSize(width: 980, height: 680)
        Settings { SettingsView() }
    }
}

