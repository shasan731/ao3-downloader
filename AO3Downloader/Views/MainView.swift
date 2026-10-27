import AppKit
import SwiftUI

struct MainView: View {
    enum Section: String, CaseIterable, Identifiable {
        case new = "New Download"
        case queue = "Activity"
        case history = "Library"
        case settings = "Settings"
        case about = "About"

        var id: String { rawValue }
    }

    @State private var selection: Section? = .new
    @StateObject private var downloadModel = NewDownloadViewModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspace") {
                    sidebarItem(.new)
                    sidebarItem(.queue)
                }
                Section("Collection") {
                    sidebarItem(.history)
                }
                Section("ArchiveBind") {
                    sidebarItem(.settings)
                    sidebarItem(.about)
                }
            }
            .safeAreaInset(edge: .top) { brandHeader }
            .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 280)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .onChange(of: selection) { _, section in
            if section == .new {
                downloadModel.prepareNewDownloadWorkspace()
            }
        }
        .onChange(of: downloadModel.isBusy) { wasBusy, isBusy in
            if wasBusy && !isBusy && selection == .new {
                downloadModel.prepareNewDownloadWorkspace()
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .new {
        case .new: NewDownloadView(model: downloadModel)
        case .queue: DownloadQueueView(model: downloadModel)
        case .history: HistoryView(model: downloadModel)
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("ArchiveBind").font(.headline)
                Text("Your stories, beautifully bound")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func sidebarItem(_ section: Section) -> some View {
        HStack(spacing: 9) {
            Label(section.rawValue, systemImage: icon(section))
            Spacer(minLength: 4)
            if section == .queue && downloadModel.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Operation in progress")
            } else if section == .history && !downloadModel.historyRecords.isEmpty {
                Text(downloadModel.historyRecords.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .tag(section)
    }

    private func icon(_ section: Section) -> String {
        switch section {
        case .new: "plus.square"
        case .queue: "arrow.down.circle"
        case .history: "books.vertical"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }
}

