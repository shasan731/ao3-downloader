import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NewDownloadViewModel: ObservableObject {
    @Published var input = ""
    @Published var work: Work?
    @Published var series: Series?
    @Published var format: DownloadFormat = .epub
    @Published var seriesOutputMode: SeriesOutputMode = .separate
    @Published var destination: URL?
    @Published var status = "Paste a public AO3 work or series URL to begin."
    @Published var isBusy = false
    @Published var outputURL: URL?
    @Published var activeOperation: ActiveOperation?
    @Published var seriesItemStates: [String: SeriesItemProgressState] = [:]
    @Published var downloadedParts: [DownloadedPart] = []
    @Published var currentFailures: [SeriesDownloadFailure] = []
    @Published var historyRecords: [LibraryRecord] = []
    @Published var metadataTitle = ""
    @Published var metadataAuthors = ""
    @Published var metadataLanguage = "en"
    @Published var metadataCoverURL: URL?
    private let dependencies: AppDependencies
    private var operationTask: Task<Void, Never>?
    private var currentLibraryRecordID: UUID?
    private var pendingReanalysisRecord: LibraryRecord?
    @Published private(set) var metadataTargetPartID: String?

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
        Task { [weak self] in await self?.loadHistory() }
    }

    var editableMetadata: EditableBookMetadata {
        .init(title: metadataTitle.isEmpty ? (series?.title ?? work?.title ?? "Untitled") : metadataTitle,
              authors: metadataAuthors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
              language: metadataLanguage.isEmpty ? "en" : metadataLanguage,
              coverImageURL: metadataCoverURL)
    }

    var hasLoadedLibraryRecord: Bool { currentLibraryRecordID != nil }

    var hasDownloadableSelection: Bool {
        guard let series else { return work != nil }
        return series.orderedWorks.contains { $0.selected && $0.accessState == .publicAccess }
    }

    var selectedVerifiedCount: Int {
        guard let series else { return 0 }
        let selected = Set(series.orderedWorks.filter { $0.selected }.map(\.workID))
        return downloadedParts.filter { selected.contains($0.work.id) }.count
    }

    var selectedMissingCount: Int {
        guard let series else { return 0 }
        let available = Set(downloadedParts.map { $0.work.id })
        return series.orderedWorks.filter {
            $0.selected && $0.accessState == .publicAccess && !available.contains($0.workID)
        }.count
    }

    var retryableFailureCount: Int {
        guard let series else { return 0 }
        let selected = Set(series.orderedWorks.filter { $0.selected && $0.accessState == .publicAccess }.map(\.workID))
        return currentFailures.filter { selected.contains($0.workID) }.count
    }

    func failureMessage(for workID: String) -> String? {
        currentFailures.first(where: { $0.workID == workID })?.message
    }

    func paste() {
        input = NSPasteboard.general.string(forType: .string) ?? input
    }

    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "Choose"
        if panel.runModal() == .OK { destination = panel.url }
    }

    func startAnalyze() {
        guard operationTask == nil else { return }
        isBusy = true
        operationTask = Task { [weak self] in
            await self?.analyze()
            self?.operationTask = nil
        }
    }

    func cancelOperation() {
        guard let operationTask else { return }
        activeOperation?.detail = "Cancelling…"
        operationTask.cancel()
    }

    private func analyze() async {
        let reanalysis = pendingReanalysisRecord
        pendingReanalysisRecord = nil
        work = nil; series = nil; seriesItemStates = [:]
        if let reanalysis {
            currentLibraryRecordID = reanalysis.id
            downloadedParts = reanalysis.downloadedParts.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
            currentFailures = reanalysis.failures
            for missing in reanalysis.downloadedParts where !FileManager.default.fileExists(atPath: missing.fileURL.path) {
                currentFailures.removeAll { $0.workID == missing.work.id }
                currentFailures.append(.init(workID: missing.work.id, position: missing.entry.position,
                                             title: missing.work.title, sourceURL: missing.work.sourceURL,
                                             category: "missing-local-file", message: "The downloaded source file was moved or deleted."))
            }
            outputURL = reanalysis.destinationURL
        } else {
            outputURL = nil; downloadedParts = []; currentFailures = []; currentLibraryRecordID = nil
        }
        activeOperation = .init(kind: .analysis, stage: .validating, startedAt: .now,
                                completedCount: 0, totalCount: nil, currentTitle: nil,
                                detail: "Validating the AO3 URL")
        defer { isBusy = false }
        do {
            try Task.checkCancellation()
            let link = try AO3URLParser().parse(input)
            status = "Analyzing through the polite request queue…"
            activeOperation?.stage = .fetching
            activeOperation?.currentTitle = link.canonicalURL.absoluteString
            switch link.kind {
            case .work:
                activeOperation?.totalCount = 1
                activeOperation?.detail = "Fetching work metadata and available formats"
                work = try await dependencies.provider.analyze(link)
                metadataTitle = work?.title ?? ""
                metadataAuthors = work?.creators.joined(separator: ", ") ?? ""
                metadataLanguage = work?.language ?? "en"
                metadataCoverURL = nil
                activeOperation?.completedCount = 1
                activeOperation?.stage = .completed
                activeOperation?.detail = "Work analysis complete"
                status = "Ready to download the complete AO3-provided file."
            case .series:
                var analyzed = try await dependencies.provider.analyzeSeries(link) { [weak self] progress in
                    await self?.applyAnalysisProgress(progress)
                }
                let oldSelection = Dictionary(uniqueKeysWithValues: (reanalysis?.series?.orderedWorks ?? []).map { ($0.workID, $0.selected) })
                for index in analyzed.orderedWorks.indices {
                    if let selected = oldSelection[analyzed.orderedWorks[index].workID] { analyzed.orderedWorks[index].selected = selected }
                }
                series = analyzed
                if let series {
                    if reanalysis == nil {
                        metadataTitle = series.title
                        metadataAuthors = series.creators.joined(separator: ", ")
                        metadataLanguage = "en"
                        metadataCoverURL = nil
                    }
                    let currentIDs = Set(series.orderedWorks.map(\.workID))
                    downloadedParts = downloadedParts.filter { currentIDs.contains($0.work.id) }
                    currentFailures = currentFailures.filter { currentIDs.contains($0.workID) }
                    let downloadedIDs = Set(downloadedParts.map { $0.work.id })
                    let failedIDs = Set(currentFailures.map(\.workID))
                    seriesItemStates = Dictionary(uniqueKeysWithValues: series.orderedWorks.map {
                        ($0.workID, $0.accessState != .publicAccess ? .inaccessible
                            : downloadedIDs.contains($0.workID) ? .completed
                            : failedIDs.contains($0.workID) ? .failed
                            : $0.selected ? .pending : .skipped)
                    })
                    activeOperation?.totalCount = series.orderedWorks.count
                    activeOperation?.completedCount = series.orderedWorks.count
                    activeOperation?.stage = .completed
                    let previousIDs = Set(reanalysis?.series?.orderedWorks.map(\.workID) ?? [])
                    let newCount = currentIDs.subtracting(previousIDs).count
                    activeOperation?.detail = reanalysis == nil ? "Found \(series.orderedWorks.count) ordered parts"
                        : "Refreshed \(series.orderedWorks.count) parts • \(newCount) new"
                    if reanalysis != nil { await updateCurrentHistory() }
                }
                status = "Ready. Select accessible works to download as separate files in author order."
            }
        } catch is CancellationError {
            if let reanalysis { restore(record: reanalysis) }
            activeOperation?.stage = .cancelled
            activeOperation?.detail = "Analysis cancelled by user"
            status = "Analysis cancelled."
        } catch {
            if let reanalysis { restore(record: reanalysis) }
            activeOperation?.stage = .failed
            activeOperation?.detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = activeOperation?.detail ?? error.localizedDescription
        }
    }

    private func applyAnalysisProgress(_ progress: SeriesAnalysisProgress) {
        activeOperation?.completedCount = progress.worksDiscovered
        activeOperation?.detail = "Scanned \(progress.pagesCompleted) page\(progress.pagesCompleted == 1 ? "" : "s") • found \(progress.worksDiscovered) parts"
    }

    func setSelection(_ selected: Bool, for workID: String) {
        guard let index = series?.orderedWorks.firstIndex(where: { $0.workID == workID }),
              series?.orderedWorks[index].accessState == .publicAccess else { return }
        series?.orderedWorks[index].selected = selected
        if !selected { seriesItemStates[workID] = .skipped }
        else if downloadedParts.contains(where: { $0.work.id == workID }) { seriesItemStates[workID] = .completed }
        else if currentFailures.contains(where: { $0.workID == workID }) { seriesItemStates[workID] = .failed }
        else { seriesItemStates[workID] = .pending }
        if currentLibraryRecordID != nil { Task { [weak self] in await self?.updateCurrentHistory() } }
    }

    func isWorkSelected(_ workID: String) -> Bool {
        series?.orderedWorks.first(where: { $0.workID == workID })?.selected ?? false
    }

    func selectAllSeriesWorks(_ selected: Bool) {
        guard var current = series else { return }
        for index in current.orderedWorks.indices where current.orderedWorks[index].accessState == .publicAccess {
            current.orderedWorks[index].selected = selected
            let id = current.orderedWorks[index].workID
            if !selected { seriesItemStates[id] = .skipped }
            else if downloadedParts.contains(where: { $0.work.id == id }) { seriesItemStates[id] = .completed }
            else if currentFailures.contains(where: { $0.workID == id }) { seriesItemStates[id] = .failed }
            else { seriesItemStates[id] = .pending }
        }
        series = current
        if currentLibraryRecordID != nil { Task { [weak self] in await self?.updateCurrentHistory() } }
    }

    func setFormat(_ newFormat: DownloadFormat) {
        format = newFormat
        if newFormat == .html { seriesOutputMode = .separate }
    }

    func startDownload() {
        guard operationTask == nil, destination != nil, hasDownloadableSelection else { return }
        isBusy = true
        operationTask = Task { [weak self] in
            await self?.download()
            self?.operationTask = nil
        }
    }

    private func download() async {
        guard let destination else { isBusy = false; return }
        let reusableDirectory = currentLibraryRecordID == nil ? nil : outputURL
        if reusableDirectory == nil { outputURL = nil }
        status = "Downloading and verifying…"
        let selectedCount = series?.orderedWorks.filter { $0.selected && $0.accessState == .publicAccess }.count
        activeOperation = .init(kind: .download, stage: .downloading, startedAt: .now,
                                completedCount: 0, totalCount: selectedCount ?? 1,
                                currentTitle: work?.title ?? series?.title,
                                detail: "Waiting for the courteous AO3 request queue")
        if let series {
            let verified = Set(downloadedParts.map { $0.work.id })
            let failed = Set(currentFailures.map(\.workID))
            seriesItemStates = Dictionary(uniqueKeysWithValues: series.orderedWorks.map {
                ($0.workID, $0.accessState != .publicAccess ? .inaccessible
                    : verified.contains($0.workID) ? .completed
                    : failed.contains($0.workID) ? .failed
                    : $0.selected ? .pending : .skipped)
            })
        }
        defer { isBusy = false }
        do {
            try Task.checkCancellation()
            if let work {
                outputURL = try await dependencies.manager.download(work: work, format: format, to: destination)
                if (format == .pdf || metadataWasCustomized(from: work)), let fileURL = outputURL {
                    let metadata = editableMetadata, selectedFormat = format
                    try await Task.detached {
                        try BookMetadataEditor().apply(metadata, to: fileURL, format: selectedFormat, work: work)
                    }.value
                }
                activeOperation?.completedCount = 1
                activeOperation?.stage = .completed
                let chapters = work.chapterCountPublished.map { " • \($0) chapter\($0 == 1 ? "" : "s")" } ?? ""
                activeOperation?.detail = "Verified complete work\(chapters)"
                status = "Download completed and verified."
                if let fileURL = outputURL { await saveSingleWork(work: work, fileURL: fileURL, destination: destination) }
            } else if let series {
                let result = try await dependencies.manager.download(series: series, format: format,
                                                                      outputMode: seriesOutputMode, metadata: editableMetadata,
                                                                      to: destination, existingDirectory: reusableDirectory,
                                                                      existingParts: downloadedParts, shouldInclude: { [weak self] workID in
                    await self?.isWorkSelected(workID) ?? false
                }, partCompleted: { [weak self] part in
                    await self?.recordCompletedPart(part)
                }, failureRecorded: { [weak self] failure in
                    await self?.recordFailure(failure)
                }, progress: { [weak self] progress in
                    await self?.applyDownloadProgress(progress)
                })
                outputURL = result.directory
                downloadedParts = result.downloadedParts
                currentFailures = result.failures
                await saveSeriesResult(result, series: self.series ?? series)
                if self.series?.orderedWorks.contains(where: { $0.selected && $0.accessState == .publicAccess }) == false {
                    status = "No parts remain selected. Verified downloads were retained in Library."
                } else if let combined = result.combinedFile, !result.failures.isEmpty {
                    status = "Combined the final selection as \(combined.lastPathComponent). \(result.failures.count) deselected or failed part(s) remain available to retry."
                } else if result.isPartial {
                    status = "Series finished partially: \(result.outputFiles.count) individual files saved and \(result.failures.count) failed. Retry them here or in Library, then combine."
                } else if let combined = result.combinedFile, result.outputFiles.isEmpty {
                    status = "Combined series book created and verified: \(combined.lastPathComponent)."
                } else if let combined = result.combinedFile {
                    status = "All \(result.outputFiles.count) individual works and \(combined.lastPathComponent) were created and verified."
                } else {
                    status = "All \(result.outputFiles.count) selected works downloaded and verified in author order."
                }
            } else {
                throw AO3Error.unsupportedPath
            }
        } catch is CancellationError {
            activeOperation?.stage = .cancelled
            activeOperation?.detail = "Stopped by user; already verified files were retained"
            status = "Operation cancelled. Already verified files were retained."
        } catch {
            activeOperation?.stage = .failed
            activeOperation?.detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = activeOperation?.detail ?? error.localizedDescription
        }
    }

    private func applyDownloadProgress(_ progress: SeriesDownloadProgress) async {
        activeOperation?.stage = progress.stage
        activeOperation?.totalCount = progress.totalCount
        activeOperation?.completedCount = progress.completedCount
        activeOperation?.currentTitle = progress.currentTitle
        activeOperation?.detail = progress.stage == .downloading
            ? "\(progress.completedCount) of \(progress.totalCount) processed\(progress.failedCount > 0 ? " • \(progress.failedCount) failed" : "")"
            : progress.stage.rawValue
        outputURL = progress.outputDirectory
        if let id = progress.currentWorkID, let state = progress.currentItemState { seriesItemStates[id] = state }
        if currentLibraryRecordID == nil, let series {
            await saveSeriesCheckpoint(series: series, directory: progress.outputDirectory)
        }
    }

    private func recordCompletedPart(_ part: DownloadedPart) async {
        downloadedParts.removeAll { $0.work.id == part.work.id }
        downloadedParts.append(part)
        downloadedParts.sort { $0.entry.position < $1.entry.position }
        currentFailures.removeAll { $0.workID == part.work.id }
        seriesItemStates[part.work.id] = .completed
        if let series, let directory = outputURL { await saveSeriesCheckpoint(series: series, directory: directory) }
    }

    private func recordFailure(_ failure: SeriesDownloadFailure) async {
        currentFailures.removeAll { $0.workID == failure.workID }
        currentFailures.append(failure)
        currentFailures.sort { $0.position < $1.position }
        seriesItemStates[failure.workID] = .failed
        if let series, let directory = outputURL { await saveSeriesCheckpoint(series: series, directory: directory) }
    }

    func retryPart(_ workID: String) {
        guard operationTask == nil, let series,
              let entry = series.orderedWorks.first(where: { $0.workID == workID }),
              let directory = outputURL else { return }
        isBusy = true
        activeOperation = .init(kind: .download, stage: .downloading, startedAt: .now,
                                completedCount: 0, totalCount: 1, currentTitle: entry.title,
                                detail: "Retrying Part \(entry.position)")
        seriesItemStates[workID] = .downloading
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false; self.operationTask = nil }
            do {
                let part = try await self.dependencies.manager.retry(entry: entry, format: self.format, in: directory)
                self.downloadedParts.removeAll { $0.work.id == workID }
                self.downloadedParts.append(part)
                self.currentFailures.removeAll { $0.workID == workID }
                self.seriesItemStates[workID] = .completed
                self.activeOperation?.completedCount = 1
                self.activeOperation?.stage = .completed
                self.activeOperation?.detail = "Retry succeeded and verified"
                self.status = "Part \(entry.position) downloaded successfully. You can now combine any verified selection."
                await self.updateCurrentHistory()
            } catch is CancellationError {
                self.seriesItemStates[workID] = .failed
                self.activeOperation?.stage = .cancelled
            } catch {
                self.seriesItemStates[workID] = .failed
                self.activeOperation?.stage = .failed
                self.activeOperation?.detail = error.localizedDescription
                self.currentFailures.removeAll { $0.workID == workID }
                self.currentFailures.append(.init(workID: entry.workID, position: entry.position,
                                                  title: entry.title, sourceURL: entry.sourceURL,
                                                  category: "retry-failed", message: error.localizedDescription))
                self.currentFailures.sort { $0.position < $1.position }
                self.status = "Retry failed: \(error.localizedDescription)"
                await self.updateCurrentHistory()
            }
        }
    }

    func retryFailedParts() {
        guard operationTask == nil, let series, let directory = outputURL else { return }
        let failedIDs = Set(currentFailures.map(\.workID))
        let entries = series.orderedWorks
            .filter { $0.selected && $0.accessState == .publicAccess && failedIDs.contains($0.workID) }
            .sorted { $0.position < $1.position }
        guard !entries.isEmpty else { return }
        isBusy = true
        activeOperation = .init(kind: .download, stage: .downloading, startedAt: .now,
                                completedCount: 0, totalCount: entries.count, currentTitle: entries.first?.title,
                                detail: "Retrying \(entries.count) failed selected parts")
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false; self.operationTask = nil }
            var succeeded = 0
            for (index, entry) in entries.enumerated() {
                do {
                    try Task.checkCancellation()
                    self.activeOperation?.currentTitle = entry.title
                    self.activeOperation?.detail = "Retrying Part \(entry.position) • \(index + 1) of \(entries.count)"
                    self.seriesItemStates[entry.workID] = .downloading
                    let part = try await self.dependencies.manager.retry(entry: entry, format: self.format, in: directory)
                    self.downloadedParts.removeAll { $0.work.id == entry.workID }
                    self.downloadedParts.append(part)
                    self.downloadedParts.sort { $0.entry.position < $1.entry.position }
                    self.currentFailures.removeAll { $0.workID == entry.workID }
                    self.seriesItemStates[entry.workID] = .completed
                    succeeded += 1
                } catch is CancellationError {
                    self.seriesItemStates[entry.workID] = .failed
                    self.activeOperation?.stage = .cancelled
                    self.activeOperation?.detail = "Bulk retry cancelled; completed retries were retained"
                    self.status = "Retry cancelled. Successfully retried parts were retained."
                    await self.updateCurrentHistory()
                    return
                } catch {
                    self.seriesItemStates[entry.workID] = .failed
                    self.currentFailures.removeAll { $0.workID == entry.workID }
                    self.currentFailures.append(.init(workID: entry.workID, position: entry.position,
                                                      title: entry.title, sourceURL: entry.sourceURL,
                                                      category: "retry-failed", message: error.localizedDescription))
                    self.currentFailures.sort { $0.position < $1.position }
                }
                self.activeOperation?.completedCount = index + 1
                await self.updateCurrentHistory()
            }
            let remaining = entries.count - succeeded
            self.activeOperation?.stage = remaining == 0 ? .completed : .failed
            self.activeOperation?.detail = remaining == 0
                ? "All \(succeeded) retries succeeded and were verified"
                : "\(succeeded) succeeded • \(remaining) still failed"
            self.status = remaining == 0
                ? "All failed selected parts downloaded successfully. You can combine them now."
                : "Bulk retry finished: \(succeeded) succeeded and \(remaining) still need attention."
        }
    }

    var canCombineSelection: Bool {
        guard metadataTargetPartID == nil, let series, format != .html else { return false }
        let selected = series.orderedWorks.filter { $0.selected && $0.accessState == .publicAccess }.map(\.workID)
        let available = Set(downloadedParts.map { $0.work.id })
        return !selected.isEmpty && selected.allSatisfy { available.contains($0) }
    }

    func combineSelected() {
        guard operationTask == nil, canCombineSelection, let series, let directory = outputURL else { return }
        let selectedIDs = Set(series.orderedWorks.filter { $0.selected }.map(\.workID))
        let parts = downloadedParts.filter { selectedIDs.contains($0.work.id) }
        isBusy = true
        activeOperation = .init(kind: .download, stage: .assembling, startedAt: .now,
                                completedCount: parts.count, totalCount: parts.count,
                                currentTitle: metadataTitle, detail: "Combining selected verified parts")
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false; self.operationTask = nil }
            do {
                let combined = try await self.dependencies.manager.combine(series: series, parts: parts,
                                                                            format: self.format, metadata: self.editableMetadata,
                                                                            in: directory)
                self.activeOperation?.stage = .completed
                self.activeOperation?.detail = "Combined book verified"
                self.status = "Combined selected parts as \(combined.lastPathComponent)."
                if let index = self.historyRecords.firstIndex(where: { $0.id == self.currentLibraryRecordID }) {
                    self.historyRecords[index].combinedFiles.append(combined)
                    self.historyRecords[index].metadata = self.editableMetadata
                    self.historyRecords[index].updatedAt = .now
                    await self.persistHistory()
                }
            } catch is CancellationError {
                self.activeOperation?.stage = .cancelled
            } catch {
                self.activeOperation?.stage = .failed
                self.activeOperation?.detail = error.localizedDescription
            }
        }
    }

    func chooseCoverImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.jpeg, .png]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.prompt = "Use Cover"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        Task { [weak self] in
            guard let self else { return }
            do { self.metadataCoverURL = try await self.dependencies.libraryStore.copyManagedCover(from: source) }
            catch { self.status = "Cover could not be copied: \(error.localizedDescription)" }
        }
    }

    func beginEditingMetadata(for workID: String) {
        guard let part = downloadedParts.first(where: { $0.work.id == workID }) else { return }
        metadataTargetPartID = workID
        metadataTitle = part.metadata?.title ?? part.work.title
        metadataAuthors = (part.metadata?.authors ?? part.work.creators).joined(separator: ", ")
        metadataLanguage = part.metadata?.language ?? part.work.language ?? "en"
        metadataCoverURL = part.metadata?.coverImageURL
        status = "Editing metadata for Part \(part.entry.position)."
    }

    func editCombinedMetadata() {
        metadataTargetPartID = nil
        if let record = historyRecords.first(where: { $0.id == currentLibraryRecordID }) {
            metadataTitle = record.metadata.title
            metadataAuthors = record.metadata.authors.joined(separator: ", ")
            metadataLanguage = record.metadata.language
            metadataCoverURL = record.metadata.coverImageURL
        }
    }

    func cancelPartMetadataEditing() {
        editCombinedMetadata()
        status = "Part metadata editing cancelled."
    }

    func applyMetadata(toCombinedFile file: URL) {
        guard operationTask == nil, let series else { return }
        let metadata = editableMetadata
        let selectedFormat = format
        let syntheticWork = Work(id: "series-\(series.id)", title: series.title, creators: series.creators,
                                 sourceURL: series.sourceURL, summary: series.description, language: metadata.language,
                                 fandoms: [], rating: nil, warnings: [], tags: [], completion: .unknown,
                                 chapterCountPublished: nil, chapterCountExpected: nil, wordCount: nil,
                                 downloadableFormats: [format: file], accessState: .publicAccess)
        isBusy = true
        activeOperation = .init(kind: .download, stage: .verifying, startedAt: .now,
                                completedCount: 0, totalCount: 1, currentTitle: file.lastPathComponent,
                                detail: "Updating combined-book metadata")
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false; self.operationTask = nil }
            do {
                try await Task.detached {
                    try BookMetadataEditor().apply(metadata, to: file, format: selectedFormat, work: syntheticWork)
                }.value
                self.activeOperation?.completedCount = 1
                self.activeOperation?.stage = .completed
                self.activeOperation?.detail = "Metadata updated and book reverified"
                self.status = "Updated metadata in \(file.lastPathComponent)."
                await self.updateCurrentHistory()
            } catch {
                self.activeOperation?.stage = .failed
                self.activeOperation?.detail = error.localizedDescription
                self.status = "Metadata update failed: \(error.localizedDescription)"
            }
        }
    }

    func saveMetadataChanges(applyToSingleFile: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            if let partID = self.metadataTargetPartID,
               let partIndex = self.downloadedParts.firstIndex(where: { $0.work.id == partID }) {
                let part = self.downloadedParts[partIndex], metadata = self.editableMetadata, format = self.format
                do {
                    try await Task.detached {
                        try BookMetadataEditor().apply(metadata, to: part.fileURL, format: format, work: part.work)
                    }.value
                    self.downloadedParts[partIndex].work.title = metadata.title
                    self.downloadedParts[partIndex].work.creators = metadata.authors
                    self.downloadedParts[partIndex].work.language = metadata.language
                    self.downloadedParts[partIndex].metadata = metadata
                    self.status = "Part \(part.entry.position) metadata updated and reverified."
                    self.metadataTargetPartID = nil
                } catch { self.status = "Metadata update failed: \(error.localizedDescription)" }
                if let index = self.historyRecords.firstIndex(where: { $0.id == self.currentLibraryRecordID }) {
                    self.historyRecords[index].downloadedParts = self.downloadedParts
                    self.historyRecords[index].updatedAt = .now
                    await self.persistHistory()
                }
                if self.metadataTargetPartID == nil { self.editCombinedMetadata() }
                return
            } else if applyToSingleFile, let work = self.work,
               let record = self.historyRecords.first(where: { $0.id == self.currentLibraryRecordID }),
               let file = record.singleFileURL {
                do {
                    let metadata = self.editableMetadata, format = record.format
                    try await Task.detached {
                        try BookMetadataEditor().apply(metadata, to: file, format: format, work: work)
                    }.value
                    self.status = "Book metadata updated and the file was reverified."
                } catch {
                    self.status = "Metadata update failed: \(error.localizedDescription)"
                    return
                }
            }
            await self.updateCurrentHistory()
            if !applyToSingleFile { self.status = "Book metadata saved for the next combination." }
        }
    }

    func openHistoryRecord(_ record: LibraryRecord) {
        currentLibraryRecordID = record.id
        input = record.sourceURL.absoluteString; series = record.series; work = record.singleWork
        format = record.format; seriesOutputMode = record.outputMode ?? .separate
        let resolved = SecurityScopedLocation.resolve(record.destinationBookmark, fallback: record.destinationURL)
        _ = resolved.startAccessingSecurityScopedResource()
        destination = record.kind == .series ? resolved.deletingLastPathComponent() : resolved
        outputURL = record.kind == .series ? resolved : (record.singleFileURL ?? resolved)
        downloadedParts = record.downloadedParts.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        currentFailures = record.failures
        for missing in record.downloadedParts where !FileManager.default.fileExists(atPath: missing.fileURL.path) {
            currentFailures.removeAll { $0.workID == missing.work.id }
            currentFailures.append(.init(workID: missing.work.id, position: missing.entry.position,
                                         title: missing.work.title, sourceURL: missing.work.sourceURL,
                                         category: "missing-local-file", message: "The downloaded source file was moved or deleted."))
        }
        metadataTitle = record.metadata.title; metadataAuthors = record.metadata.authors.joined(separator: ", ")
        metadataLanguage = record.metadata.language; metadataCoverURL = record.metadata.coverImageURL
        metadataTargetPartID = nil
        if let series {
            let downloaded = Set(downloadedParts.map { $0.work.id }), failed = Set(currentFailures.map(\.workID))
            seriesItemStates = Dictionary(uniqueKeysWithValues: series.orderedWorks.map { entry in
                (entry.workID, entry.accessState != .publicAccess ? .inaccessible
                    : downloaded.contains(entry.workID) ? .completed
                    : failed.contains(entry.workID) ? .failed
                    : entry.selected ? .pending : .skipped)
            })
        }
        status = "Loaded from Library. Retry failures, change selections or metadata, combine, or reanalyze."
    }

    func reanalyzeCurrentSource() {
        guard !isBusy, let id = currentLibraryRecordID,
              let record = historyRecords.first(where: { $0.id == id }) else { return }
        pendingReanalysisRecord = record
        input = record.sourceURL.absoluteString
        startAnalyze()
    }

    private func loadHistory() async {
        do {
            historyRecords = try await dependencies.libraryStore.load()
        } catch {
            historyRecords = []
            status = "Library recovery failed: \(error.localizedDescription). Existing download files were not changed."
        }
    }

    func removeHistoryRecord(_ id: UUID) {
        guard !isBusy else { return }
        historyRecords.removeAll { $0.id == id }
        if currentLibraryRecordID == id {
            currentLibraryRecordID = nil
            work = nil; series = nil; outputURL = nil; downloadedParts = []; currentFailures = []
            seriesItemStates = [:]; metadataTargetPartID = nil
        }
        status = "Removed from Library. Downloaded files were kept."
        Task { [weak self] in await self?.persistHistory() }
    }

    private func saveSingleWork(work: Work, fileURL: URL, destination: URL) async {
        let record = LibraryRecord(id: UUID(), kind: .work, sourceURL: work.sourceURL, series: nil,
                                   singleWork: work, format: format, outputMode: nil, destinationURL: destination,
                                   destinationBookmark: SecurityScopedLocation.bookmark(for: destination),
                                   metadata: editableMetadata, downloadedParts: [], singleFileURL: fileURL,
                                   combinedFiles: [], failures: [], createdAt: .now, updatedAt: .now)
        historyRecords.insert(record, at: 0); currentLibraryRecordID = record.id
        await persistHistory()
    }

    private func saveSeriesResult(_ result: SeriesDownloadResult, series: Series) async {
        if let id = currentLibraryRecordID, let index = historyRecords.firstIndex(where: { $0.id == id }) {
            historyRecords[index].series = series
            historyRecords[index].format = format
            historyRecords[index].outputMode = seriesOutputMode
            historyRecords[index].metadata = editableMetadata
            historyRecords[index].downloadedParts = result.downloadedParts
            historyRecords[index].failures = result.failures
            if let combined = result.combinedFile { historyRecords[index].combinedFiles.append(combined) }
            historyRecords[index].updatedAt = .now
            await persistHistory()
            return
        }
        let record = LibraryRecord(id: UUID(), kind: .series, sourceURL: series.sourceURL, series: series,
                                   singleWork: nil, format: format, outputMode: seriesOutputMode,
                                   destinationURL: result.directory,
                                   destinationBookmark: SecurityScopedLocation.bookmark(for: result.directory),
                                   metadata: editableMetadata, downloadedParts: result.downloadedParts,
                                   singleFileURL: nil, combinedFiles: result.combinedFile.map { [$0] } ?? [],
                                   failures: result.failures, createdAt: .now, updatedAt: .now)
        historyRecords.insert(record, at: 0); currentLibraryRecordID = record.id
        await persistHistory()
    }

    private func saveSeriesCheckpoint(series: Series, directory: URL) async {
        if let id = currentLibraryRecordID, let index = historyRecords.firstIndex(where: { $0.id == id }) {
            historyRecords[index].series = self.series ?? series
            historyRecords[index].format = format
            historyRecords[index].outputMode = seriesOutputMode
            historyRecords[index].destinationURL = directory
            historyRecords[index].metadata = editableMetadata
            historyRecords[index].downloadedParts = downloadedParts
            historyRecords[index].failures = currentFailures
            historyRecords[index].updatedAt = .now
        } else {
            let record = LibraryRecord(id: UUID(), kind: .series, sourceURL: series.sourceURL,
                                       series: self.series ?? series, singleWork: nil, format: format,
                                       outputMode: seriesOutputMode, destinationURL: directory,
                                       destinationBookmark: SecurityScopedLocation.bookmark(for: directory),
                                       metadata: editableMetadata, downloadedParts: downloadedParts,
                                       singleFileURL: nil, combinedFiles: [], failures: currentFailures,
                                       createdAt: .now, updatedAt: .now)
            historyRecords.insert(record, at: 0)
            currentLibraryRecordID = record.id
        }
        await persistHistory()
    }

    private func metadataWasCustomized(from work: Work) -> Bool {
        let metadata = editableMetadata
        return metadata.title != work.title
            || metadata.authors != work.creators
            || metadata.language != (work.language ?? "en")
            || metadata.coverImageURL != nil
    }

    private func restore(record: LibraryRecord) {
        currentLibraryRecordID = record.id
        work = record.singleWork
        series = record.series
        downloadedParts = record.downloadedParts.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        currentFailures = record.failures
        outputURL = record.kind == .series ? record.destinationURL : record.singleFileURL
        metadataTitle = record.metadata.title
        metadataAuthors = record.metadata.authors.joined(separator: ", ")
        metadataLanguage = record.metadata.language
        metadataCoverURL = record.metadata.coverImageURL
        if let series {
            let downloaded = Set(downloadedParts.map { $0.work.id })
            let failed = Set(currentFailures.map(\.workID))
            seriesItemStates = Dictionary(uniqueKeysWithValues: series.orderedWorks.map { entry in
                (entry.workID, entry.accessState != .publicAccess ? .inaccessible
                    : downloaded.contains(entry.workID) ? .completed
                    : failed.contains(entry.workID) ? .failed
                    : entry.selected ? .pending : .skipped)
            })
        }
    }

    private func updateCurrentHistory() async {
        guard let id = currentLibraryRecordID, let index = historyRecords.firstIndex(where: { $0.id == id }) else { return }
        historyRecords[index].series = series; historyRecords[index].downloadedParts = downloadedParts
        historyRecords[index].failures = currentFailures
        if metadataTargetPartID == nil { historyRecords[index].metadata = editableMetadata }
        historyRecords[index].updatedAt = .now
        await persistHistory()
    }

    @discardableResult
    private func persistHistory() async -> Bool {
        do {
            try await dependencies.libraryStore.save(historyRecords)
            return true
        } catch {
            status = "Library checkpoint could not be saved: \(error.localizedDescription). Downloaded files were kept."
            return false
        }
    }
}

