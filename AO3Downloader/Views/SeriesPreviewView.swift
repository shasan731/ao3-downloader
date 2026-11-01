import AppKit
import SwiftUI

struct SeriesPreviewView: View {
    private enum PartFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case selected = "Selected"
        case remaining = "Remaining"
        case failed = "Failed"
        case completed = "Completed"

        var id: String { rawValue }
    }

    let series: Series
    let progressStates: [String: SeriesItemProgressState]
    let failureMessages: [String: String]
    let isBusy: Bool
    let onSelectionChanged: (String, Bool) -> Void
    let onSelectAll: (Bool) -> Void
    let onRetry: (String) -> Void

    @State private var searchText = ""
    @State private var partFilter: PartFilter = .all
    @State private var showsDescription = false

    var body: some View {
        Section("Series Preview") {
            VStack(alignment: .leading, spacing: 12) {
                titleArea
                selectionSummary
                filterBar
                partsScroller
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: series.id) { _, _ in
                searchText = ""
                partFilter = .all
                showsDescription = false
            }
        }
    }

    private var titleArea: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(series.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            if let description = series.description, !description.isEmpty {
                DisclosureGroup("Series description", isExpanded: $showsDescription) {
                    Text(description)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var selectionSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                summaryText
                Spacer()
                selectionButtons
            }
            VStack(alignment: .leading, spacing: 9) {
                summaryText
                selectionButtons
            }
        }
    }

    private var summaryText: some View {
        HStack(spacing: 10) {
            Label("\(selectedCount) selected", systemImage: "checkmark.circle")
            Label("\(completedCount) saved", systemImage: "arrow.down.circle")
            if failedCount > 0 {
                Label("\(failedCount) failed", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var selectionButtons: some View {
        ControlGroup {
            Button("Select All") { onSelectAll(true) }
                .accessibilityLabel("Select all accessible series parts")
            Button("Select None") { onSelectAll(false) }
                .accessibilityLabel("Deselect all series parts")
        }
        .fixedSize()
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            TextField("Search title or part number", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Picker("Filter", selection: $partFilter) {
                ForEach(PartFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 125)
            if !searchText.isEmpty || partFilter != .all {
                Button {
                    searchText = ""
                    partFilter = .all
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear filters")
                .accessibilityLabel("Clear series filters")
            }
        }
    }

    private var partsScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if displayedEntries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.title2)
                            Text("No matching parts").font(.headline)
                            Text("Change the search or status filter.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 54)
                    } else {
                        ForEach(Array(displayedEntries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider() }
                            partRow(entry)
                                .id(entry.workID)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 330)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
            .onChange(of: activeWorkID) { _, workID in
                guard let workID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(workID, anchor: .center)
                }
            }
        }
    }

    private func partRow(_ entry: SeriesEntry) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { entry.selected },
                set: { onSelectionChanged(entry.workID, $0) }
            ))
            .labelsHidden()
            .disabled(entry.accessState != .publicAccess)

            Text("\(entry.position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if entry.accessState != .publicAccess {
                    Text(entry.accessState == .restricted ? "Restricted" : "Unavailable")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let message = failureMessages[entry.workID] {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)
            progressIcon(for: entry)
            if progressStates[entry.workID] == .failed {
                Button("Retry") { onRetry(entry.workID) }
                    .disabled(isBusy)
                    .accessibilityLabel("Retry Part \(entry.position), \(entry.title)")
            }
            if entry.accessState == .publicAccess {
                Link(destination: entry.sourceURL) {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open Part \(entry.position) on AO3")
                .accessibilityLabel("Open source for Part \(entry.position), \(entry.title)")
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 2)
        .background {
            if progressStates[entry.workID] == .downloading {
                RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.08))
            }
        }
    }

    private var orderedEntries: [SeriesEntry] {
        series.orderedWorks.sorted { $0.position < $1.position }
    }

    private var displayedEntries: [SeriesEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return orderedEntries.filter { entry in
            let matchesSearch = query.isEmpty
                || entry.title.localizedCaseInsensitiveContains(query)
                || String(entry.position).contains(query)
            guard matchesSearch else { return false }
            switch partFilter {
            case .all: return true
            case .selected: return entry.selected
            case .remaining:
                return entry.selected
                    && entry.accessState == .publicAccess
                    && progressStates[entry.workID] != .completed
            case .failed: return progressStates[entry.workID] == .failed
            case .completed: return progressStates[entry.workID] == .completed
            }
        }
    }

    private var selectedCount: Int { orderedEntries.filter(\.selected).count }
    private var completedCount: Int { progressStates.values.filter { $0 == .completed }.count }
    private var failedCount: Int { progressStates.values.filter { $0 == .failed }.count }
    private var activeWorkID: String? {
        orderedEntries.first { progressStates[$0.workID] == .downloading }?.workID
    }

    @ViewBuilder
    private func progressIcon(for entry: SeriesEntry) -> some View {
        if entry.accessState != .publicAccess {
            Image(systemName: "lock.fill").foregroundStyle(.red).accessibilityLabel("Inaccessible")
        } else if progressStates[entry.workID] == .completed {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Completed")
        } else if progressStates[entry.workID] == .downloading {
            ProgressView().controlSize(.small).accessibilityLabel("Downloading")
        } else if progressStates[entry.workID] == .failed {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Failed")
        } else if progressStates[entry.workID] == .skipped {
            Image(systemName: "minus.circle").foregroundStyle(.secondary).accessibilityLabel("Not selected")
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary).accessibilityLabel("Pending")
        }
    }
}
