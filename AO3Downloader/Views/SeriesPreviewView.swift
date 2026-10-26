import SwiftUI

struct SeriesPreviewView: View {
    let series: Series
    let onSelectionChanged: (String, Bool) -> Void
    let onSelectAll: (Bool) -> Void

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
                    if entry.accessState == .publicAccess { Link("Source", destination: entry.sourceURL) }
                }
            }
        }
    }
}
