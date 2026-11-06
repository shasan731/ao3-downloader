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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var downloadModel = NewDownloadViewModel()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                SwiftUI.Section("Workspace") {
                    sidebarItem(.new)
                    sidebarItem(.queue)
                }
                SwiftUI.Section("Collection") {
                    sidebarItem(.history)
                }
                SwiftUI.Section("ArchiveBind") {
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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let operation = downloadModel.activeOperation, downloadModel.isBusy {
                        compactOperationBar(operation)
                    }
                }
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
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
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
            } else if section == .queue {
                let attention = downloadModel.downloadJobs.filter { $0.state == .failed || $0.state == .completedPartial }.count
                if attention > 0 {
                    Text(attention.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                        .accessibilityLabel("\(attention) download activities need attention")
                }
            } else if section == .history && !downloadModel.historyRecords.isEmpty {
                Text(downloadModel.historyRecords.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .tag(section)
    }

    private func compactOperationBar(_ operation: ActiveOperation) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Operation in progress")
            VStack(alignment: .leading, spacing: 1) {
                Text(operation.stage.rawValue).font(.callout.weight(.medium))
                if let total = operation.totalCount, total > 0 {
                    Text("\(min(operation.completedCount, total)) of \(total) • \(operation.detail)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(operation.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button("View Activity") {
                selection = .queue
                columnVisibility = .all
            }
            Button("Cancel", role: .destructive) { downloadModel.cancelOperation() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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

