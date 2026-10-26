import AppKit
import Foundation
import SwiftUI

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
    private let dependencies: AppDependencies
    private var operationTask: Task<Void, Never>?

    init(dependencies: AppDependencies = .live) { self.dependencies = dependencies }

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
        work = nil; series = nil; outputURL = nil; seriesItemStates = [:]
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
                activeOperation?.completedCount = 1
                activeOperation?.stage = .completed
                activeOperation?.detail = "Work analysis complete"
                status = "Ready to download the complete AO3-provided file."
            case .series:
                series = try await dependencies.provider.analyzeSeries(link) { [weak self] progress in
                    await self?.applyAnalysisProgress(progress)
                }
                if let series {
                    seriesItemStates = Dictionary(uniqueKeysWithValues: series.orderedWorks.map {
                        ($0.workID, $0.accessState == .publicAccess ? .pending : .inaccessible)
                    })
                    activeOperation?.totalCount = series.orderedWorks.count
                    activeOperation?.completedCount = series.orderedWorks.count
                    activeOperation?.stage = .completed
                    activeOperation?.detail = "Found \(series.orderedWorks.count) ordered parts"
                }
                status = "Ready. Select accessible works to download as separate files in author order."
            }
        } catch is CancellationError {
            activeOperation?.stage = .cancelled
            activeOperation?.detail = "Analysis cancelled by user"
            status = "Analysis cancelled."
        } catch {
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
        seriesItemStates[workID] = selected ? .pending : .skipped
    }

    func selectAllSeriesWorks(_ selected: Bool) {
        guard var current = series else { return }
        for index in current.orderedWorks.indices where current.orderedWorks[index].accessState == .publicAccess {
            current.orderedWorks[index].selected = selected
            seriesItemStates[current.orderedWorks[index].workID] = selected ? .pending : .skipped
        }
        series = current
    }

    func setFormat(_ newFormat: DownloadFormat) {
        format = newFormat
        if newFormat == .html { seriesOutputMode = .separate }
    }

    func startDownload() {
        guard operationTask == nil, destination != nil else { return }
        isBusy = true
        operationTask = Task { [weak self] in
            await self?.download()
            self?.operationTask = nil
        }
    }

    private func download() async {
        guard let destination else { isBusy = false; return }
        outputURL = nil; status = "Downloading and verifying…"
        let selectedCount = series?.orderedWorks.filter { $0.selected && $0.accessState == .publicAccess }.count
        activeOperation = .init(kind: .download, stage: .downloading, startedAt: .now,
                                completedCount: 0, totalCount: selectedCount ?? 1,
                                currentTitle: work?.title ?? series?.title,
                                detail: "Waiting for the courteous AO3 request queue")
        if let series {
            seriesItemStates = Dictionary(uniqueKeysWithValues: series.orderedWorks.map {
                ($0.workID, $0.accessState == .publicAccess ? ($0.selected ? .pending : .skipped) : .inaccessible)
            })
        }
        defer { isBusy = false }
        do {
            try Task.checkCancellation()
            if let work {
                outputURL = try await dependencies.manager.download(work: work, format: format, to: destination)
                activeOperation?.completedCount = 1
                activeOperation?.stage = .completed
                let chapters = work.chapterCountPublished.map { " • \($0) chapter\($0 == 1 ? "" : "s")" } ?? ""
                activeOperation?.detail = "Verified complete work\(chapters)"
                status = "Download completed and verified."
            } else if let series {
                let result = try await dependencies.manager.download(series: series, format: format,
                                                                      outputMode: seriesOutputMode, to: destination) { [weak self] progress in
                    await self?.applyDownloadProgress(progress)
                }
                outputURL = result.directory
                if result.isPartial {
                    status = "Series finished partially: \(result.outputFiles.count) individual files saved, \(result.failures.count) unavailable or failed. No combined book was created. See download-report.json."
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

    private func applyDownloadProgress(_ progress: SeriesDownloadProgress) {
        activeOperation?.stage = progress.stage
        activeOperation?.totalCount = progress.totalCount
        activeOperation?.completedCount = progress.completedCount
        activeOperation?.currentTitle = progress.currentTitle
        activeOperation?.detail = progress.stage == .downloading
            ? "\(progress.completedCount) of \(progress.totalCount) processed\(progress.failedCount > 0 ? " • \(progress.failedCount) failed" : "")"
            : progress.stage.rawValue
        outputURL = progress.outputDirectory
        if let id = progress.currentWorkID, let state = progress.currentItemState { seriesItemStates[id] = state }
    }
}

