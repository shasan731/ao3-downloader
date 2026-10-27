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
                                Toggle("", isOn: Binding(get: { model.series?.orderedWorks.first(where: { $0.workID == entry.workID })?.selected ?? false },
                                                         set: { model.setSelection($0, for: entry.workID) }))
                                    .labelsHidden().disabled(entry.accessState != .publicAccess)
                                statusIcon(model.seriesItemStates[entry.workID] ?? (entry.accessState == .publicAccess ? .pending : .inaccessible))
                                Text("Part \(entry.position)").foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
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
                    if model.series != nil && !model.downloadedParts.isEmpty {
                        HStack {
                            Button("Combine Selected Verified Parts") { model.combineSelected() }
                                .buttonStyle(.borderedProminent).disabled(model.isBusy || !model.canCombineSelection)
                            if !model.canCombineSelection { Text("Retry or deselect unavailable selected parts first.").foregroundStyle(.secondary) }
                        }
                    }
                    if model.retryableFailureCount > 0 {
                        Button("Retry Failed Selected Parts (\(model.retryableFailureCount))") { model.retryFailedParts() }
                            .disabled(model.isBusy)
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
struct HistoryView: View {
    @ObservedObject var model: NewDownloadViewModel
    @State private var selection: UUID?
    @State private var recordPendingRemoval: LibraryRecord?
    var body: some View {
        Group {
            if model.historyRecords.isEmpty {
                ContentUnavailableView("No download history", systemImage: "books.vertical", description: Text("Verified downloads will appear here."))
            } else {
                HSplitView {
                    List(model.historyRecords, selection: $selection) { record in
                        VStack(alignment: .leading) {
                            Text(record.metadata.title).font(.headline)
                            Text(record.kind == .series ? "Series • \(record.downloadedParts.count) verified parts" : "Single work")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(record.updatedAt.formatted()).font(.caption2).foregroundStyle(.secondary)
                        }.tag(record.id)
                    }.frame(minWidth: 260)
                    VStack(alignment: .leading, spacing: 12) {
                        if let record = selectedRecord {
                            Text(record.metadata.title).font(.title2).bold()
                            if let operation = model.activeOperation, model.isBusy {
                                OperationProgressView(operation: operation, canCancel: true, onCancel: model.cancelOperation)
                            }
                            MetadataEditorView(model: model, showApplyToSingle: record.kind == .work)
                            VStack(alignment: .leading, spacing: 8) {
                                if record.kind == .series {
                                    HStack {
                                        Button("Reanalyze Source") { model.reanalyzeCurrentSource() }.disabled(model.isBusy)
                                        Button("Download Missing (\(model.selectedMissingCount))") { model.startDownload() }
                                            .disabled(model.isBusy || model.selectedMissingCount == 0)
                                        Button("Retry Failed (\(model.retryableFailureCount))") { model.retryFailedParts() }
                                            .disabled(model.isBusy || model.retryableFailureCount == 0)
                                        Button("Combine Selected") { model.combineSelected() }
                                            .disabled(model.isBusy || !model.canCombineSelection)
                                    }
                                }
                                HStack {
                                    Button("Reveal Folder") { NSWorkspace.shared.activateFileViewerSelecting([record.destinationURL]) }
                                    Button("Remove from Library", role: .destructive) { recordPendingRemoval = record }
                                        .disabled(model.isBusy)
                                }
                            }
                            if !record.combinedFiles.isEmpty {
                                GroupBox("Combined Books") {
                                    ForEach(record.combinedFiles.filter { FileManager.default.fileExists(atPath: $0.path) }, id: \.self) { file in
                                        HStack {
                                            Image(systemName: "book.closed.fill").foregroundStyle(Color.accentColor)
                                            Text(file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                            Spacer()
                                            Button("Apply Metadata") { model.applyMetadata(toCombinedFile: file) }
                                                .disabled(model.isBusy || model.metadataTargetPartID != nil)
                                            Button("Open") { NSWorkspace.shared.open(file) }
                                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                                        }
                                    }
                                }
                            }
                            if let series = model.series {
                                List(series.orderedWorks.sorted(by: { $0.position < $1.position })) { entry in
                                    HStack {
                                        Toggle("", isOn: Binding(get: { model.series?.orderedWorks.first(where: { $0.workID == entry.workID })?.selected ?? false },
                                                                 set: { model.setSelection($0, for: entry.workID) }))
                                            .labelsHidden().disabled(entry.accessState != .publicAccess)
                                        historyStatusIcon(model.seriesItemStates[entry.workID] ?? .pending)
                                        Text("Part \(entry.position)").foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.title)
                                            if let message = model.failureMessage(for: entry.workID) {
                                                Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                        if model.seriesItemStates[entry.workID] == .failed && !model.isBusy {
                                            Button("Retry") { model.retryPart(entry.workID) }
                                        } else if model.seriesItemStates[entry.workID] == .completed && !model.isBusy {
                                            Button("Edit Metadata") { model.beginEditingMetadata(for: entry.workID) }
                                        }
                                    }
                                }
                            }
                            Spacer()
                        } else { ContentUnavailableView("Select a download", systemImage: "books.vertical") }
                    }.padding().frame(minWidth: 480)
                }
            }
        }.navigationTitle("Library / History")
        .onChange(of: selection) { _, id in
            if let record = model.historyRecords.first(where: { $0.id == id }) { model.openHistoryRecord(record) }
        }
        .onChange(of: model.historyRecords.map(\.id), initial: true) { _, ids in
            if selection.map({ ids.contains($0) }) != true {
                selection = ids.first
                if let id = ids.first, let record = model.historyRecords.first(where: { $0.id == id }) {
                    model.openHistoryRecord(record)
                }
            }
        }
        .alert("Remove from Library?", isPresented: Binding(get: { recordPendingRemoval != nil },
                                                              set: { if !$0 { recordPendingRemoval = nil } })) {
            Button("Cancel", role: .cancel) { recordPendingRemoval = nil }
            Button("Remove", role: .destructive) {
                if let record = recordPendingRemoval {
                    model.removeHistoryRecord(record.id)
                    selection = nil
                }
                recordPendingRemoval = nil
            }
        } message: {
            Text("This removes only the Library entry. Downloaded books and folders remain on disk.")
        }
    }
    private var selectedRecord: LibraryRecord? { model.historyRecords.first(where: { $0.id == selection }) }

    @ViewBuilder private func historyStatusIcon(_ state: SeriesItemProgressState) -> some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .downloading: ProgressView().controlSize(.small)
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .inaccessible: Image(systemName: "lock.circle.fill").foregroundStyle(.red)
        }
    }
}
struct SettingsView: View {
    @AppStorage("minimumRequestInterval") private var interval = 15.0
    @AppStorage("allowAdultContent") private var allowAdultContent = false

    var body: some View {
        Form {
            Section("Content Access") {
                Toggle("Allow public Mature/Explicit works", isOn: $allowAdultContent)
                Text("Equivalent to choosing “Yes, continue” on AO3’s warning page. This app does not use your browser session, AO3 account, or login-only works.")
                    .foregroundStyle(.secondary)
            }
            Section("Network Courtesy") {
                Stepper("Minimum request interval: \(Int(interval)) seconds", value: $interval, in: 10...120, step: 5)
                Text("This conservative setting is not an AO3-provided quota. Changes apply after relaunch; slower is gentler.")
                    .foregroundStyle(.secondary)
            }
        }.padding().frame(minWidth: 480)
    }
}
struct AboutView: View { var body: some View { VStack(spacing: 16) { Image(systemName: "arrow.down.doc").font(.system(size: 56)); Text("AO3 Downloader").font(.largeTitle); Text("Unofficial application; not affiliated with AO3 or the Organization for Transformative Works.").multilineTextAlignment(.center); Link("Source repository", destination: URL(string: "https://github.com/shasan731/ao3-downloader")!); Link("AO3 Terms of Service FAQ", destination: URL(string: "https://archiveofourown.org/tos_faq")!) }.padding(40).frame(maxWidth: 600) } }

