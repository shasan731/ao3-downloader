import AppKit
import SwiftUI

struct DownloadQueueView: View {
    @ObservedObject var model: NewDownloadViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let operation = model.activeOperation {
                    OperationProgressView(operation: operation, canCancel: model.isBusy, onCancel: model.cancelOperation)

                    if let series = model.series {
                        LazyVStack(spacing: 0) {
                            ForEach(series.orderedWorks.sorted(by: { $0.position < $1.position })) { entry in
                                queueRow(entry)
                                Divider()
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
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
                if !model.downloadJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Activity").font(.headline)
                        ForEach(model.downloadJobs) { job in
                            downloadJobRow(job)
                        }
                    }
                }
                if model.activeOperation == nil && model.downloadJobs.isEmpty {
                ContentUnavailableView(
                    "No active activity",
                    systemImage: "arrow.down.circle",
                        description: Text("Downloads appear here, continue while you browse, and retain their last checkpoint after relaunch.")
                )
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Activity")
    }

    private func downloadJobRow(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 11) {
                jobStatusIcon(job.state)
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title ?? "Saved download").font(.headline).lineLimit(2)
                    Text("\(job.state.displayName) • \(job.format.rawValue) • \(job.source.canonicalURL.host == "www.fanfiction.net" ? "FanFiction.net" : "AO3")")
                        .font(.caption).foregroundStyle(.secondary)
                    if let detail = job.statusDetail {
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                    }
                    if let error = job.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                Spacer(minLength: 12)
                if job.state == .failed || job.state == .cancelled || job.state == .completedPartial {
                    Button("Retry") { model.retryDownloadJob(job.id) }
                        .disabled(model.isBusy)
                } else if let output = job.outputFiles.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    Button("Open") { NSWorkspace.shared.open(output) }
                }
                if job.state.isTerminal {
                    Button {
                        model.removeDownloadJob(job.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy)
                    .help("Remove this Activity entry (downloaded files stay on disk)")
                }
            }
            if let total = job.totalUnitCount, total > 0 {
                let completed = min(job.completedUnitCount ?? 0, total)
                ProgressView(value: Double(completed), total: Double(total))
                HStack {
                    Text("\(completed) of \(total)")
                    Spacer()
                    if let current = job.currentUnitTitle, !job.state.isTerminal {
                        Text(current).lineLimit(1).truncationMode(.middle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
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

    @ViewBuilder
    private func jobStatusIcon(_ state: DownloadJobState) -> some View {
        switch state {
        case .queued, .analyzing, .ready, .downloading, .backingOff, .paused, .assembling, .verifying:
            ProgressView().controlSize(.small).accessibilityLabel(state.displayName)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Completed")
        case .completedPartial:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).accessibilityLabel("Completed with issues")
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Needs attention")
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(.secondary).accessibilityLabel("Cancelled")
        }
    }
}
