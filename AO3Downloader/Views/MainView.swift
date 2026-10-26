import SwiftUI

struct MainView: View {
    enum Section: String, CaseIterable, Identifiable { case new = "New Download", queue = "Queue", history = "Library / History", settings = "Settings", about = "About"; var id: String { rawValue } }
    @State private var selection: Section? = .new
    @StateObject private var downloadModel = NewDownloadViewModel()
    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                HStack {
                    Label(section.rawValue, systemImage: icon(section))
                    if section == .queue && downloadModel.isBusy { Spacer(); ProgressView().controlSize(.small) }
                }.tag(section)
            }
                .navigationTitle("AO3 Downloader")
        } detail: {
            switch selection ?? .new {
            case .new: NewDownloadView(model: downloadModel)
            case .queue: DownloadQueueView(model: downloadModel)
            case .history: HistoryView(model: downloadModel)
            case .settings: SettingsView()
            case .about: AboutView()
            }
        }
    }
    private func icon(_ section: Section) -> String { switch section { case .new: "plus.circle"; case .queue: "list.bullet"; case .history: "books.vertical"; case .settings: "gear"; case .about: "info.circle" } }
}

