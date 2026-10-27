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
                            queueRow(entry)
                        }
                        .listStyle(.inset)
                    } else if let work = model.work {
                        HStack(spacing: 12) {
                            statusIcon(operation.stage == .completed ? .completed : .downloading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(work.title).font(.headline)
                                if let chapters = work.chapterCountPublished {
                                    Text("\(chapters) chapter\(chapters == 1 ? "" : "s")")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    }

                    actionBar
                }
                .padding(20)
            } else {
                ContentUnavailableView(
                    "No active activity",
                    systemImage: "arrow.down.circle",
                    description: Text("Analysis and downloads appear here and continue while you browse the app.")
                )
            }
        }
        .navigationTitle("Activity")
    }

    private func queueRow(_ entry: SeriesEntry) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.isWorkSelected(entry.workID) },
                set: { model.setSelection($0, for: entry.workID) }
            ))
            .labelsHidden()
            .disabled(entry.accessState != .publicAccess)

            statusIcon(model.seriesItemStates[entry.workID] ?? (entry.accessState == .publicAccess ? .pending : .inaccessible))
            Text("\(entry.position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(2)
                if let message = model.failureMessage(for: entry.workID) {
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer()
            if model.seriesItemStates[entry.workID] == .failed && !model.isBusy {
                Button("Retry") { model.retryPart(entry.workID) }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 10) {
            if let output = model.outputURL {
                Button("Open Result") { NSWorkspace.shared.open(output) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
            }
            Spacer()
            if model.retryableFailureCount > 0 {
                Button("Retry Failed (\(model.retryableFailureCount))") { model.retryFailedParts() }
                    .disabled(model.isBusy)
            }
            if model.series != nil && !model.downloadedParts.isEmpty {
                Button("Combine Selected") { model.combineSelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || !model.canCombineSelection)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ state: SeriesItemProgressState) -> some View {
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
