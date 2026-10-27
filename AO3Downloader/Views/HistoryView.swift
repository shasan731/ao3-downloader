import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: NewDownloadViewModel
    @State private var selection: UUID?
    @State private var searchText = ""
    @State private var recordPendingRemoval: LibraryRecord?

    var body: some View {
        Group {
            if model.historyRecords.isEmpty {
                ContentUnavailableView(
                    "Your library is empty",
                    systemImage: "books.vertical",
                    description: Text("Verified downloads are saved here for retrying, editing, and recombining.")
                )
            } else if model.isBusy && !model.isViewingLibraryWorkspace {
                VStack(alignment: .leading, spacing: 16) {
                    if let operation = model.activeOperation {
                        OperationProgressView(operation: operation, canCancel: true, onCancel: model.cancelOperation)
                    }
                    Text("Library browsing is temporarily read-only so the active workspace stays consistent. The operation continues in the background.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(24)
            } else {
                HSplitView {
                    libraryList
                        .frame(minWidth: 230, idealWidth: 280, maxWidth: 360)
                    detail
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Library")
        .onChange(of: selection) { _, id in
            guard !model.isBusy,
                  let record = model.historyRecords.first(where: { $0.id == id }) else { return }
            model.openHistoryRecord(record)
        }
        .onChange(of: model.historyRecords.map(\.id), initial: true) { _, ids in
            if selection.map({ ids.contains($0) }) != true {
                selection = ids.first
                if let id = ids.first, let record = model.historyRecords.first(where: { $0.id == id }) {
                    model.openHistoryRecord(record)
                }
            }
        }
        .onChange(of: model.isBusy) { wasBusy, isBusy in
            if wasBusy && !isBusy,
               let id = selection,
               let record = model.historyRecords.first(where: { $0.id == id }) {
                model.openHistoryRecord(record)
            }
        }
        .alert("Remove from Library?", isPresented: Binding(
            get: { recordPendingRemoval != nil },
            set: { if !$0 { recordPendingRemoval = nil } }
        )) {
            Button("Cancel", role: .cancel) { recordPendingRemoval = nil }
            Button("Remove", role: .destructive) {
                if let record = recordPendingRemoval {
                    model.removeHistoryRecord(record.id)
                    selection = nil
                }
                recordPendingRemoval = nil
            }
        } message: {
            Text("Only the Library entry is removed. Downloaded books and folders stay on disk.")
        }
    }

    private var libraryList: some View {
        List(filteredRecords, selection: $selection) { record in
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: record.kind == .series ? "books.vertical.fill" : "book.closed.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(record.metadata.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                HStack {
                    Text(record.kind == .series ? "\(record.downloadedParts.count) saved parts" : record.format.rawValue)
                    Spacer()
                    Text(record.updatedAt, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !record.failures.isEmpty {
                    Label("\(record.failures.count) need attention", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 5)
            .tag(record.id)
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search Library")
        .overlay {
            if filteredRecords.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let record = selectedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    recordHeader(record)
                    if let operation = model.activeOperation, model.isBusy {
                        OperationProgressView(operation: operation, canCancel: true, onCancel: model.cancelOperation)
                    }
                    summary(record)
                    MetadataEditorView(model: model, showApplyToSingle: record.kind == .work)
                    actionArea(record)
                    combinedBooks(record)
                    if let series = model.series { partsList(series) }
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            ContentUnavailableView("Select a book", systemImage: "book.closed")
        }
    }

    private func recordHeader(_ record: LibraryRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: record.kind == .series ? "books.vertical.fill" : "book.closed.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(record.metadata.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                Text(record.metadata.authors.isEmpty ? "Unknown author" : record.metadata.authors.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Menu {
                Button("Reanalyze Source", systemImage: "arrow.clockwise") { model.reanalyzeCurrentSource() }
                    .disabled(record.kind != .series || model.isBusy)
                Button("Reveal Folder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([record.destinationURL])
                }
                Link(destination: record.sourceURL) { Label("Open Source", systemImage: "safari") }
                Divider()
                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    recordPendingRemoval = record
                }
                .disabled(model.isBusy)
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func summary(_ record: LibraryRecord) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
            summaryTile("Format", record.format.rawValue, "doc.richtext")
            summaryTile("Saved", record.kind == .series ? "\(record.downloadedParts.count) parts" : "1 book", "checkmark.circle")
            summaryTile("Needs attention", record.failures.count.formatted(), record.failures.isEmpty ? "checkmark.shield" : "exclamationmark.triangle")
            summaryTile("Updated", record.updatedAt.formatted(date: .abbreviated, time: .omitted), "clock")
        }
    }

    private func summaryTile(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
            Text(value).font(.headline).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder
    private func actionArea(_ record: LibraryRecord) -> some View {
        if record.kind == .series {
            GroupBox("Actions") {
                HStack(spacing: 10) {
                    Button("Download Missing (\(model.selectedMissingCount))") { model.startDownload() }
                        .disabled(model.isBusy || model.selectedMissingCount == 0)
                    if model.retryableFailureCount > 0 {
                        Button("Retry Failed (\(model.retryableFailureCount))") { model.retryFailedParts() }
                            .disabled(model.isBusy)
                    }
                    Spacer()
                    Button("Combine Selected") { model.combineSelected() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || !model.canCombineSelection)
                }
            }
        }
    }

    @ViewBuilder
    private func combinedBooks(_ record: LibraryRecord) -> some View {
        let existing = record.combinedFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existing.isEmpty {
            GroupBox("Combined Books") {
                VStack(spacing: 0) {
                    ForEach(Array(existing.enumerated()), id: \.element) { index, file in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Image(systemName: "book.closed.fill").foregroundStyle(Color.accentColor)
                            Text(file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Update Metadata") { model.applyMetadata(toCombinedFile: file) }
                                .disabled(model.isBusy || model.metadataTargetPartID != nil)
                            Button("Open") { NSWorkspace.shared.open(file) }
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([file])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .help("Reveal in Finder")
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func partsList(_ series: Series) -> some View {
        GroupBox("Series Parts") {
            LazyVStack(spacing: 0) {
                ForEach(Array(series.orderedWorks.sorted(by: { $0.position < $1.position }).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    partRow(entry)
                }
            }
        }
    }

    private func partRow(_ entry: SeriesEntry) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.isWorkSelected(entry.workID) },
                set: { model.setSelection($0, for: entry.workID) }
            ))
            .labelsHidden()
            .disabled(entry.accessState != .publicAccess)
            historyStatusIcon(model.seriesItemStates[entry.workID] ?? .pending)
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
            } else if model.seriesItemStates[entry.workID] == .completed && !model.isBusy {
                Button("Edit") { model.beginEditingMetadata(for: entry.workID) }
                    .help("Edit this part’s metadata")
            }
        }
        .padding(.vertical, 9)
    }

    private var filteredRecords: [LibraryRecord] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return model.historyRecords }
        return model.historyRecords.filter { record in
            record.metadata.title.localizedCaseInsensitiveContains(searchText)
                || record.metadata.authors.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private var selectedRecord: LibraryRecord? {
        model.historyRecords.first(where: { $0.id == selection })
    }

    @ViewBuilder
    private func historyStatusIcon(_ state: SeriesItemProgressState) -> some View {
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
