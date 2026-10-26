import SwiftUI

struct SeriesPreviewView: View {
    let series: Series
    let progressStates: [String: SeriesItemProgressState]
    let isBusy: Bool
    let onSelectionChanged: (String, Bool) -> Void
    let onSelectAll: (Bool) -> Void
    let onRetry: (String) -> Void

    var body: some View {
        Section("Series Preview") {
            Text(series.title).font(.title2).bold().textSelection(.enabled)
            if let description = series.description { Text(description).textSelection(.enabled) }
            HStack {
                Text("\(series.orderedWorks.filter(\.selected).count) selected • \(series.orderedWorks.filter { $0.accessState == .publicAccess }.count) accessible of \(series.orderedWorks.count) listed parts")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("All") { onSelectAll(true) }.accessibilityLabel("Select all accessible series parts")
                Button("None") { onSelectAll(false) }.accessibilityLabel("Deselect all series parts")
            }
            ForEach(series.orderedWorks.sorted(by: { $0.position < $1.position })) { entry in
                HStack(alignment: .firstTextBaseline) {
                    Toggle(isOn: Binding(get: { entry.selected }, set: { onSelectionChanged(entry.workID, $0) })) { EmptyView() }
                        .labelsHidden()
                        .disabled(entry.accessState != .publicAccess)
                    Text("Part \(entry.position)")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 52, alignment: .trailing)
                    VStack(alignment: .leading) {
                        Text(entry.title).textSelection(.enabled)
                        if entry.accessState != .publicAccess {
                            Text(entry.accessState == .restricted ? "Restricted" : "Unavailable")
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    progressIcon(for: entry)
                    if progressStates[entry.workID] == .failed {
                        Button("Retry") { onRetry(entry.workID) }
                            .disabled(isBusy)
                            .accessibilityLabel("Retry Part \(entry.position), \(entry.title)")
                    }
                    if entry.accessState == .publicAccess { Link("Source", destination: entry.sourceURL) }
                }
            }
        }
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
        } else if !entry.selected {
            Image(systemName: "circle").foregroundStyle(.secondary).accessibilityLabel("Not selected")
        }
    }
}
