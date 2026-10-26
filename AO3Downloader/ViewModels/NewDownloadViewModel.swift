import AppKit
import Foundation
import SwiftUI

@MainActor
final class NewDownloadViewModel: ObservableObject {
    @Published var input = ""
    @Published var work: Work?
    @Published var format: DownloadFormat = .epub
    @Published var destination: URL?
    @Published var status = "Paste a public AO3 work URL to begin."
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
        isBusy = true; work = nil; outputURL = nil; defer { isBusy = false }
        do {
            let link = try AO3URLParser().parse(input)
            guard link.kind == .work else {
                status = "Series downloads are listed as an upcoming capability in this build."
                return
            }
            status = "Analyzing through the polite request queue…"
            work = try await dependencies.provider.analyze(link)
            status = "Ready to download the complete AO3-provided file."
        } catch { status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func download() async {
        guard let work, let destination, !isBusy else { return }
        isBusy = true; outputURL = nil; status = "Downloading and verifying…"; defer { isBusy = false }
        do {
            outputURL = try await dependencies.manager.download(work: work, format: format, to: destination)
            status = "Download completed and verified."
        } catch { status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

