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

    func download(series: Series, format: DownloadFormat, to parent: URL) async throws -> SeriesDownloadResult {
        let selected = series.orderedWorks.filter { $0.selected && $0.accessState == .publicAccess }
        guard !selected.isEmpty else { throw AO3Error.noSeriesWorksSelected }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AO3Error.storage("destination folder is unavailable")
        }
        let directory = naming.availableDirectory(in: parent, name: "\(series.title) [AO3-Series-\(series.id)]")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var outputs: [URL] = []
        var failures: [SeriesDownloadFailure] = series.orderedWorks
            .filter { $0.accessState != .publicAccess }
            .map { failure(for: $0, category: "inaccessible", message: "The series entry is unavailable to a logged-out reader.") }

        for entry in selected.sorted(by: { $0.position < $1.position }) {
            do {
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
            } catch {
                failures.append(failure(for: entry, category: category(for: error), message: error.localizedDescription))
            }
        }
        failures.sort { $0.position < $1.position }
        if !failures.isEmpty { try writeReport(series: series, format: format, failures: failures, outputs: outputs, to: directory) }
        return SeriesDownloadResult(directory: directory, outputFiles: outputs, failures: failures)
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

