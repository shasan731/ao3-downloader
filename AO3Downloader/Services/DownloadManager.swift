import Foundation

private struct DownloadedSeriesWork {
    let entry: SeriesEntry
    let work: Work
    let fileURL: URL
}

actor DownloadManager {
    private let provider: AO3Providing
    private let naming = FileNamingService()
    init(provider: AO3Providing) { self.provider = provider }

    func download(work: Work, format: DownloadFormat, to directory: URL) async throws -> URL {
        guard directory.isFileURL else { throw AO3Error.storage("destination is not a local folder") }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AO3Error.storage("destination folder is unavailable")
        }
        let staged = try await provider.download(work, format: format)
        let target = naming.availableURL(in: directory, filename: naming.filename(for: work, format: format))
        do {
            // The URLSession file is already private temporary storage; move only after verification.
            try FileManager.default.moveItem(at: staged, to: target)
            try DownloadValidator().validate(file: target, format: format)
            return target
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw AO3Error.storage(error.localizedDescription)
        }
    }

    func download(series: Series, format: DownloadFormat, outputMode: SeriesOutputMode, to parent: URL,
                  progress: @escaping @Sendable (SeriesDownloadProgress) async -> Void = { _ in }) async throws -> SeriesDownloadResult {
        let selected = series.orderedWorks.filter { $0.selected && $0.accessState == .publicAccess }
        guard !selected.isEmpty else { throw AO3Error.noSeriesWorksSelected }
        if outputMode != .separate && format == .html { throw AO3Error.combinedFormatUnsupported(format) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AO3Error.storage("destination folder is unavailable")
        }
        let directory = naming.availableDirectory(in: parent, name: "\(series.title) [AO3-Series-\(series.id)]")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var outputs: [URL] = []
        var downloaded: [DownloadedSeriesWork] = []
        var processedCount = 0
        var failures: [SeriesDownloadFailure] = series.orderedWorks
            .filter { $0.accessState != .publicAccess }
            .map { failure(for: $0, category: "inaccessible", message: "The series entry is unavailable to a logged-out reader.") }
        await progress(.init(stage: .downloading, totalCount: selected.count, completedCount: 0,
                             failedCount: 0, currentWorkID: nil, currentTitle: nil, currentItemState: nil, outputDirectory: directory))

        let orderedSelected = selected.sorted(by: { $0.position < $1.position })
        for (selectedIndex, entry) in orderedSelected.enumerated() {
            await progress(.init(stage: .downloading, totalCount: selected.count, completedCount: processedCount,
                                 failedCount: failures.filter { $0.accessStateEquivalent }.count,
                                 currentWorkID: entry.workID, currentTitle: entry.title, currentItemState: .downloading, outputDirectory: directory))
            do {
                try Task.checkCancellation()
                let link = try AO3URLParser().parse(entry.sourceURL.absoluteString)
                let work = try await provider.analyze(link)
                let staged = try await provider.download(work, format: format)
                try DownloadValidator().validate(file: staged, format: format)
                let base = naming.filename(for: work, format: format)
                let numbered = String(format: "%02d - %@", entry.position, base)
                let target = naming.availableURL(in: directory, filename: numbered)
                try FileManager.default.moveItem(at: staged, to: target)
                try DownloadValidator().validate(file: target, format: format)
                outputs.append(target)
                downloaded.append(.init(entry: entry, work: work, fileURL: target))
                processedCount += 1
                await progress(.init(stage: .downloading, totalCount: selected.count, completedCount: processedCount,
                                     failedCount: failures.filter { $0.accessStateEquivalent }.count,
                                     currentWorkID: entry.workID, currentTitle: entry.title, currentItemState: .completed, outputDirectory: directory))
            } catch is CancellationError {
                let remaining = orderedSelected[selectedIndex...]
                failures.append(contentsOf: remaining.map {
                    failure(for: $0, category: "cancelled", message: "Not downloaded because the user cancelled the operation.")
                })
                failures.sort { $0.position < $1.position }
                try? writeReport(series: series, format: format, failures: failures, outputs: outputs, to: directory)
                await progress(.init(stage: .cancelled, totalCount: selected.count, completedCount: processedCount,
                                     failedCount: 0, currentWorkID: entry.workID, currentTitle: entry.title,
                                     currentItemState: .pending, outputDirectory: directory))
                throw CancellationError()
            } catch {
                failures.append(failure(for: entry, category: category(for: error), message: error.localizedDescription))
                processedCount += 1
                await progress(.init(stage: .downloading, totalCount: selected.count, completedCount: processedCount,
                                     failedCount: failures.filter { $0.accessStateEquivalent }.count,
                                     currentWorkID: entry.workID, currentTitle: entry.title, currentItemState: .failed, outputDirectory: directory))
            }
        }
        failures.sort { $0.position < $1.position }
        if !failures.isEmpty { try writeReport(series: series, format: format, failures: failures, outputs: outputs, to: directory) }
        var combinedFile: URL?
        if outputMode != .separate && failures.isEmpty {
            if Task.isCancelled {
                await progress(.init(stage: .cancelled, totalCount: selected.count, completedCount: selected.count,
                                     failedCount: 0, currentWorkID: nil, currentTitle: nil,
                                     currentItemState: nil, outputDirectory: directory))
                throw CancellationError()
            }
            await progress(.init(stage: .assembling, totalCount: selected.count, completedCount: selected.count,
                                 failedCount: 0, currentWorkID: nil, currentTitle: series.title,
                                 currentItemState: nil, outputDirectory: directory))
            let author = Array(Set(downloaded.flatMap { $0.work.creators })).sorted().joined(separator: ", ")
            let base = naming.sanitize("\(series.title) - \(author.isEmpty ? "Unknown Creator" : author) [AO3-Series-\(series.id)].\(format.fileExtension)")
            let target = naming.availableURL(in: directory, filename: base)
            do {
                switch format {
                case .epub:
                    try EPUBMerger().merge(series: series, inputs: downloaded.map { .init(entry: $0.entry, work: $0.work, fileURL: $0.fileURL) }, to: target)
                case .pdf:
                    try PDFMerger().merge(downloaded.map { .init(entry: $0.entry, work: $0.work, fileURL: $0.fileURL) }, to: target)
                case .html:
                    throw AO3Error.combinedFormatUnsupported(format)
                }
                combinedFile = target
                await progress(.init(stage: .verifying, totalCount: selected.count, completedCount: selected.count,
                                     failedCount: 0, currentWorkID: nil, currentTitle: target.lastPathComponent,
                                     currentItemState: nil, outputDirectory: directory))
                if outputMode == .combined {
                    for output in outputs { try? FileManager.default.removeItem(at: output) }
                    outputs = []
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: target)
                await progress(.init(stage: .cancelled, totalCount: selected.count, completedCount: selected.count,
                                     failedCount: 0, currentWorkID: nil, currentTitle: nil,
                                     currentItemState: nil, outputDirectory: directory))
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: target)
                if let error = error as? AO3Error { throw error }
                throw AO3Error.mergeFailed(error.localizedDescription)
            }
        }
        await progress(.init(stage: .completed, totalCount: selected.count, completedCount: selected.count,
                             failedCount: failures.filter { $0.accessStateEquivalent }.count,
                             currentWorkID: nil, currentTitle: nil, currentItemState: nil, outputDirectory: directory))
        return SeriesDownloadResult(directory: directory, outputFiles: outputs, combinedFile: combinedFile, failures: failures)
    }

    private func failure(for entry: SeriesEntry, category: String, message: String) -> SeriesDownloadFailure {
        .init(workID: entry.workID, position: entry.position, title: entry.title,
              sourceURL: entry.sourceURL, category: category, message: message)
    }

    private func category(for error: Error) -> String {
        guard let error = error as? AO3Error else { return "unexpected" }
        switch error {
        case .accessRequired: return "access-required"
        case .unavailable: return "unavailable"
        case .formatUnavailable: return "format-unavailable"
        case .throttled: return "throttled"
        case .challenged: return "challenge"
        case .storage: return "storage"
        case .invalidDownload: return "verification"
        default: return "download-failed"
        }
    }

    private func writeReport(series: Series, format: DownloadFormat, failures: [SeriesDownloadFailure], outputs: [URL], to directory: URL) throws {
        struct Report: Codable {
            let version: Int
            let seriesID: String
            let seriesTitle: String
            let sourceURL: URL
            let format: DownloadFormat
            let generatedAt: Date
            let outputFiles: [String]
            let failures: [SeriesDownloadFailure]
        }
        let report = Report(version: 1, seriesID: series.id, seriesTitle: series.title,
                            sourceURL: series.sourceURL, format: format, generatedAt: .now,
                            outputFiles: outputs.map(\.lastPathComponent), failures: failures.sorted { $0.position < $1.position })
        let data = try JSONEncoder().encode(report)
        try data.write(to: directory.appendingPathComponent("download-report.json"), options: .atomic)
    }
}

private extension SeriesDownloadFailure {
    var accessStateEquivalent: Bool { !workID.hasPrefix("unavailable-") }
}

