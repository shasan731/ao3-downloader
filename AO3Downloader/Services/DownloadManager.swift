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
}

