import Foundation

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

    func download(series: Series, format: DownloadFormat, outputMode: SeriesOutputMode,
                  metadata: EditableBookMetadata? = nil, to parent: URL,
                  existingDirectory: URL? = nil, existingParts: [DownloadedPart] = [],
                  shouldInclude: @escaping @Sendable (String) async -> Bool = { _ in true },
                  partCompleted: @escaping @Sendable (DownloadedPart) async -> Void = { _ in },
                  failureRecorded: @escaping @Sendable (SeriesDownloadFailure) async -> Void = { _ in },
                  progress: @escaping @Sendable (SeriesDownloadProgress) async -> Void = { _ in }) async throws -> SeriesDownloadResult {
        let candidates = series.orderedWorks.filter { $0.accessState == .publicAccess }
        guard candidates.contains(where: { $0.selected }) else { throw AO3Error.noSeriesWorksSelected }
        if outputMode != .separate && format == .html { throw AO3Error.combinedFormatUnsupported(format) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AO3Error.storage("destination folder is unavailable")
        }
        let directory = existingDirectory ?? naming.availableDirectory(in: parent, name: "\(series.title) [AO3-Series-\(series.id)]")
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        let candidateIDs = Set(candidates.map(\.workID))
        var downloaded = existingParts.filter {
            candidateIDs.contains($0.work.id)
                && $0.fileURL.pathExtension.lowercased() == format.fileExtension
                && FileManager.default.fileExists(atPath: $0.fileURL.path)
        }
        for index in downloaded.indices {
            if let currentEntry = candidates.first(where: { $0.workID == downloaded[index].work.id }) {
                downloaded[index] = .init(entry: currentEntry, work: downloaded[index].work,
                                          fileURL: downloaded[index].fileURL, metadata: downloaded[index].metadata)
            }
        }
        var outputs: [URL] = downloaded.map(\.fileURL).filter { !$0.path.contains("/.AO3DownloaderParts/") }
        var processedCount = 0
        var failures: [SeriesDownloadFailure] = []
        await progress(.init(stage: .downloading, totalCount: candidates.count, completedCount: 0,
                             failedCount: 0, currentWorkID: nil, currentTitle: nil, currentItemState: nil, outputDirectory: directory))

        let orderedSelected = candidates.sorted(by: { $0.position < $1.position })
        for (selectedIndex, entry) in orderedSelected.enumerated() {
            let included = await shouldInclude(entry.workID)
            if !included {
                processedCount += 1
                await progress(.init(stage: .downloading, totalCount: candidates.count, completedCount: processedCount,
                                     failedCount: failures.count,
                                     currentWorkID: entry.workID, currentTitle: entry.title,
                                     currentItemState: .skipped, outputDirectory: directory))
                continue
            }
            if let existingIndex = downloaded.firstIndex(where: { $0.work.id == entry.workID }) {
                if (try? DownloadValidator().validate(file: downloaded[existingIndex].fileURL, format: format)) == nil {
                    downloaded.remove(at: existingIndex)
                } else {
                    if outputMode != .combined && downloaded[existingIndex].fileURL.path.contains("/.AO3DownloaderParts/") {
                        let visible = naming.availableURL(in: directory, filename: downloaded[existingIndex].fileURL.lastPathComponent)
                        do {
                            try FileManager.default.copyItem(at: downloaded[existingIndex].fileURL, to: visible)
                            downloaded[existingIndex].fileURL = visible
                            outputs.append(visible)
                            await partCompleted(downloaded[existingIndex])
                        } catch {
                            let item = failure(for: entry, category: "storage", message: error.localizedDescription)
                            failures.append(item)
                            await failureRecorded(item)
                            processedCount += 1
                            await progress(.init(stage: .downloading, totalCount: candidates.count, completedCount: processedCount,
                                                 failedCount: failures.count, currentWorkID: entry.workID,
                                                 currentTitle: entry.title, currentItemState: .failed, outputDirectory: directory))
                            continue
                        }
                    }
                    processedCount += 1
                    await progress(.init(stage: .downloading, totalCount: candidates.count, completedCount: processedCount,
                                         failedCount: failures.count,
                                         currentWorkID: entry.workID, currentTitle: entry.title,
                                         currentItemState: .completed, outputDirectory: directory))
                    continue
                }
            }
            await progress(.init(stage: .downloading, totalCount: candidates.count, completedCount: processedCount,
                                 failedCount: failures.count,
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
                do {
                    try FileManager.default.moveItem(at: staged, to: target)
                    try DownloadValidator().validate(file: target, format: format)
                } catch {
                    try? FileManager.default.removeItem(at: target)
                    throw error
                }
                let part = DownloadedPart(entry: entry, work: work, fileURL: target)
                outputs.append(target)
                downloaded.append(part)
                await partCompleted(part)
                processedCount += 1
                await progress(.init(stage: .downloading, totalCount: candidates.count, completedCount: processedCount,
                                     failedCount: failures.count,
                                     currentWorkID: entry.workID, currentTitle: entry.title, currentItemState: .completed, outputDirectory: directory))
            } catch is CancellationError {
                var cancelled: [SeriesDownloadFailure] = []
                for remainingEntry in orderedSelected[selectedIndex...] {
                    if await shouldInclude(remainingEntry.workID) {
                        cancelled.append(failure(for: remainingEntry, category: "cancelled",
                                                 message: "Not downloaded because the user cancelled the operation."))
                    }
                }
                failures.append(contentsOf: cancelled)
                for item in cancelled { await failureRecorded(item) }
                failures.sort { $0.position < $1.position }
                try? writeReport(series: series, format: format, failures: failures, outputs: outputs, to: directory)
                await progress(.init(stage: .cancelled, totalCount: candidates.count, completedCount: processedCount,
                                     failedCount: 0, currentWorkID: entry.workID, currentTitle: entry.title,
                                     currentItemState: .pending, outputDirectory: directory))
                throw CancellationError()
            } catch {
                let item = failure(for: entry, category: category(for: error), message: error.localizedDescription)
                failures.append(item)
                await failureRecorded(item)
                processedCount += 1
                await progress(.init(stage: .downloading, totalCount: candidates.count, completedCount: processedCount,
                                     failedCount: failures.count,
                                     currentWorkID: entry.workID, currentTitle: entry.title, currentItemState: .failed, outputDirectory: directory))
            }
        }
        var finalSelectedIDs = Set<String>()
        for candidate in candidates {
            if await shouldInclude(candidate.workID) { finalSelectedIDs.insert(candidate.workID) }
        }
        let mergeParts = downloaded.filter { finalSelectedIDs.contains($0.work.id) }
        let downloadedIDs = Set(mergeParts.map { $0.work.id })
        let failedIDs = Set(failures.map(\.workID))
        for missingID in finalSelectedIDs.subtracting(downloadedIDs).subtracting(failedIDs) {
            if let entry = candidates.first(where: { $0.workID == missingID }) {
                let item = failure(for: entry, category: "not-downloaded",
                                   message: "Selected after its queue position had passed. Use Download Missing Selected or Retry.")
                failures.append(item)
                await failureRecorded(item)
            }
        }
        failures.sort { $0.position < $1.position }
        if !failures.isEmpty { try writeReport(series: series, format: format, failures: failures, outputs: outputs, to: directory) }
        let failedSelectedIDs = Set(failures.map(\.workID)).intersection(finalSelectedIDs)
        let canAutomaticallyCombine = !finalSelectedIDs.isEmpty
            && failedSelectedIDs.isEmpty
            && finalSelectedIDs.isSubset(of: downloadedIDs)
        var combinedFile: URL?
        if outputMode != .separate && canAutomaticallyCombine {
            if Task.isCancelled {
                await progress(.init(stage: .cancelled, totalCount: candidates.count, completedCount: processedCount,
                                     failedCount: 0, currentWorkID: nil, currentTitle: nil,
                                     currentItemState: nil, outputDirectory: directory))
                throw CancellationError()
            }
            await progress(.init(stage: .assembling, totalCount: candidates.count, completedCount: processedCount,
                                 failedCount: 0, currentWorkID: nil, currentTitle: series.title,
                                 currentItemState: nil, outputDirectory: directory))
            let author = Array(Set(mergeParts.flatMap { $0.work.creators })).sorted().joined(separator: ", ")
            let base = naming.sanitize("\(series.title) - \(author.isEmpty ? "Unknown Creator" : author) [AO3-Series-\(series.id)].\(format.fileExtension)")
            let target = naming.availableURL(in: directory, filename: base)
            do {
                switch format {
                case .epub:
                    try EPUBMerger().merge(series: series, inputs: mergeParts.map { .init(entry: $0.entry, work: $0.work, fileURL: $0.fileURL) }, metadata: metadata, to: target)
                case .pdf:
                    try PDFMerger().merge(mergeParts.map { .init(entry: $0.entry, work: $0.work, fileURL: $0.fileURL) },
                                          metadata: metadata, asAnthology: true, to: target)
                case .html:
                    throw AO3Error.combinedFormatUnsupported(format)
                }
                combinedFile = target
                await progress(.init(stage: .verifying, totalCount: candidates.count, completedCount: processedCount,
                                     failedCount: 0, currentWorkID: nil, currentTitle: target.lastPathComponent,
                                     currentItemState: nil, outputDirectory: directory))
                if outputMode == .combined {
                    let sourceDirectory = directory.appendingPathComponent(".AO3DownloaderParts", isDirectory: true)
                    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
                    for index in downloaded.indices where !downloaded[index].fileURL.path.contains("/.AO3DownloaderParts/") {
                        let old = downloaded[index].fileURL
                        let new = naming.availableURL(in: sourceDirectory, filename: old.lastPathComponent)
                        do {
                            try FileManager.default.moveItem(at: old, to: new)
                            downloaded[index].fileURL = new
                            await partCompleted(downloaded[index])
                        } catch {
                            // The verified source remains usable in place; failure to hide it must not discard the combined book.
                        }
                    }
                    outputs = downloaded.map(\.fileURL).filter { !$0.path.contains("/.AO3DownloaderParts/") }
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: target)
                await progress(.init(stage: .cancelled, totalCount: candidates.count, completedCount: processedCount,
                                     failedCount: 0, currentWorkID: nil, currentTitle: nil,
                                     currentItemState: nil, outputDirectory: directory))
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: target)
                if let error = error as? AO3Error { throw error }
                throw AO3Error.mergeFailed(error.localizedDescription)
            }
        }
        await progress(.init(stage: .completed, totalCount: candidates.count, completedCount: processedCount,
                             failedCount: failures.count,
                             currentWorkID: nil, currentTitle: nil, currentItemState: nil, outputDirectory: directory))
        return SeriesDownloadResult(directory: directory, outputFiles: outputs, combinedFile: combinedFile,
                                    downloadedParts: downloaded, failures: failures)
    }

    func retry(entry: SeriesEntry, format: DownloadFormat, in directory: URL) async throws -> DownloadedPart {
        try Task.checkCancellation()
        let link = try AO3URLParser().parse(entry.sourceURL.absoluteString)
        let work = try await provider.analyze(link)
        let staged = try await provider.download(work, format: format)
        try DownloadValidator().validate(file: staged, format: format)
        let filename = String(format: "%02d - %@", entry.position, naming.filename(for: work, format: format))
        let target = naming.availableURL(in: directory, filename: filename)
        do {
            try FileManager.default.moveItem(at: staged, to: target)
            try DownloadValidator().validate(file: target, format: format)
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return .init(entry: entry, work: work, fileURL: target)
    }

    func combine(series: Series, parts: [DownloadedPart], format: DownloadFormat,
                 metadata: EditableBookMetadata, in directory: URL) throws -> URL {
        guard !parts.isEmpty else { throw AO3Error.noSeriesWorksSelected }
        guard format != .html else { throw AO3Error.combinedFormatUnsupported(format) }
        let author = metadata.authors.isEmpty ? "Unknown Creator" : metadata.authors.joined(separator: ", ")
        let filename = naming.sanitize("\(metadata.title) - \(author) [AO3-Series-\(series.id)].\(format.fileExtension)")
        let target = naming.availableURL(in: directory, filename: filename)
        do {
            switch format {
            case .epub:
                try EPUBMerger().merge(series: series, inputs: parts.map { .init(entry: $0.entry, work: $0.work, fileURL: $0.fileURL) },
                                       metadata: metadata, to: target)
            case .pdf:
                try PDFMerger().merge(parts.map { .init(entry: $0.entry, work: $0.work, fileURL: $0.fileURL) },
                                      metadata: metadata, asAnthology: true, to: target)
            case .html: throw AO3Error.combinedFormatUnsupported(format)
            }
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return target
    }

    private func failure(for entry: SeriesEntry, category: String, message: String) -> SeriesDownloadFailure {
        .init(workID: entry.workID, position: entry.position, title: entry.title,
              sourceURL: entry.sourceURL, category: category, message: message)
    }

    private func category(for error: Error) -> String {
        guard let error = error as? AO3Error else { return "unexpected" }
        switch error {
        case .adultConsentRequired: return "adult-consent-required"
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

