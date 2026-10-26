import AppKit
import SwiftUI

struct DownloadQueueView: View {
    @ObservedObject var model: NewDownloadViewModel
    var body: some View {
        Group {
            if let operation = model.activeOperation {
                VStack(alignment: .leading, spacing: 16) {
                    OperationProgressView(operation: operation, canCancel: model.isBusy, onCancel: model.cancelOperation)
                    if let series = model.series {
                        List(series.orderedWorks.sorted(by: { $0.position < $1.position })) { entry in
                            HStack {
                                statusIcon(model.seriesItemStates[entry.workID] ?? (entry.accessState == .publicAccess ? .pending : .inaccessible))
                                Text("Part \(entry.position)").foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
                                Text(entry.title).lineLimit(2)
                                Spacer()
                            }
                        }
                    } else if let work = model.work {
                        HStack {
                            statusIcon(operation.stage == .completed ? .completed : .downloading)
                            VStack(alignment: .leading) {
                                Text(work.title)
                                if let chapters = work.chapterCountPublished { Text("\(chapters) chapter\(chapters == 1 ? "" : "s")").foregroundStyle(.secondary) }
                            }
                        }.padding()
                    }
                    if let output = model.outputURL {
                        HStack { Button("Open Result") { NSWorkspace.shared.open(output) }; Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) } }
                    }
                    Spacer()
                }.padding()
            } else {
                ContentUnavailableView("No active operation", systemImage: "list.bullet", description: Text("Analysis and downloads will continue here when you switch sections."))
            }
        }.navigationTitle("Queue")
    }

    @ViewBuilder private func statusIcon(_ state: SeriesItemProgressState) -> some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary).accessibilityLabel("Pending")
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary).accessibilityLabel("Not selected")
        case .downloading: ProgressView().controlSize(.small).accessibilityLabel("Downloading")
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Completed")
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Failed")
        case .inaccessible: Image(systemName: "lock.circle.fill").foregroundStyle(.red).accessibilityLabel("Inaccessible")
        }
    }
}
struct HistoryView: View { var body: some View { ContentUnavailableView("No download history", systemImage: "books.vertical", description: Text("Verified downloads will appear here.")) } }
struct SettingsView: View { @AppStorage("minimumRequestInterval") private var interval = 15.0; var body: some View { Form { Section("Network Courtesy") { Stepper("Minimum request interval: \(Int(interval)) seconds", value: $interval, in: 10...120, step: 5); Text("This conservative setting is not an AO3-provided quota. Changes apply after relaunch; slower is gentler.").foregroundStyle(.secondary) } }.padding().frame(minWidth: 480) } }
struct AboutView: View { var body: some View { VStack(spacing: 16) { Image(systemName: "arrow.down.doc").font(.system(size: 56)); Text("AO3 Downloader").font(.largeTitle); Text("Unofficial application; not affiliated with AO3 or the Organization for Transformative Works.").multilineTextAlignment(.center); Link("Source repository", destination: URL(string: "https://github.com/shasan731/ao3-downloader")!); Link("AO3 Terms of Service FAQ", destination: URL(string: "https://archiveofourown.org/tos_faq")!) }.padding(40).frame(maxWidth: 600) } }

