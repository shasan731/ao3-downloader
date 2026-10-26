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
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) { self.dependencies = dependencies }

    func paste() {
        input = NSPasteboard.general.string(forType: .string) ?? input
    }

    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "Choose"
        if panel.runModal() == .OK { destination = panel.url }
    }

    func analyze() async {
        guard !isBusy else { return }
        isBusy = true; work = nil; series = nil; outputURL = nil; defer { isBusy = false }
        do {
            let link = try AO3URLParser().parse(input)
            status = "Analyzing through the polite request queue…"
            switch link.kind {
            case .work:
                work = try await dependencies.provider.analyze(link)
                status = "Ready to download the complete AO3-provided file."
            case .series:
                series = try await dependencies.provider.analyzeSeries(link)
                status = "Ready. Select accessible works to download as separate files in author order."
            }
        } catch { status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func setSelection(_ selected: Bool, for workID: String) {
        guard let index = series?.orderedWorks.firstIndex(where: { $0.workID == workID }),
              series?.orderedWorks[index].accessState == .publicAccess else { return }
        series?.orderedWorks[index].selected = selected
    }

    func selectAllSeriesWorks(_ selected: Bool) {
        guard var current = series else { return }
        for index in current.orderedWorks.indices where current.orderedWorks[index].accessState == .publicAccess {
            current.orderedWorks[index].selected = selected
        }
        series = current
    }

    func setFormat(_ newFormat: DownloadFormat) {
        format = newFormat
        if newFormat == .html { seriesOutputMode = .separate }
    }

    func download() async {
        guard let destination, !isBusy else { return }
        isBusy = true; outputURL = nil; status = "Downloading and verifying…"; defer { isBusy = false }
        do {
            if let work {
                outputURL = try await dependencies.manager.download(work: work, format: format, to: destination)
                status = "Download completed and verified."
            } else if let series {
                let result = try await dependencies.manager.download(series: series, format: format, outputMode: seriesOutputMode, to: destination)
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
        } catch { status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

