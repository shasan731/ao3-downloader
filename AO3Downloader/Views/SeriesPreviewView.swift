import SwiftUI

struct SeriesPreviewView: View {
    let series: Series
    let onSelectionChanged: (String, Bool) -> Void

    var body: some View {
        Section("Series Preview") {
            Text(series.title).font(.title2).bold().textSelection(.enabled)
            if let description = series.description { Text(description).textSelection(.enabled) }
            Text("\(series.orderedWorks.filter { $0.accessState == .publicAccess }.count) accessible of \(series.orderedWorks.count) listed works")
                .foregroundStyle(.secondary)
            ForEach(series.orderedWorks.sorted(by: { $0.position < $1.position })) { entry in
                HStack(alignment: .firstTextBaseline) {
                    Toggle(isOn: Binding(get: { entry.selected }, set: { onSelectionChanged(entry.workID, $0) })) { EmptyView() }
                        .labelsHidden()
                        .disabled(entry.accessState != .publicAccess)
                    Text("\(entry.position).")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
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
            Text("Series downloads are separate files. Combined EPUB/PDF is not implemented in this build.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
