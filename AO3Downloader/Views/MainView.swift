import SwiftUI

struct MainView: View {
    enum Section: String, CaseIterable, Identifiable { case new = "New Download", queue = "Queue", history = "Library / History", settings = "Settings", about = "About"; var id: String { rawValue } }
    @State private var selection: Section? = .new
    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in Label(section.rawValue, systemImage: icon(section)).tag(section) }
                .navigationTitle("AO3 Downloader")
        } detail: {
            switch selection ?? .new {
            case .new: NewDownloadView()
            case .queue: DownloadQueueView()
            case .history: HistoryView()
            case .settings: SettingsView()
            case .about: AboutView()
            }
        }
    }
    private func icon(_ section: Section) -> String { switch section { case .new: "plus.circle"; case .queue: "list.bullet"; case .history: "books.vertical"; case .settings: "gear"; case .about: "info.circle" } }
}

