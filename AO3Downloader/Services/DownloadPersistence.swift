import Foundation

actor DownloadPersistence {
    struct Envelope: Codable { let version: Int; var jobs: [DownloadJob] }
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AO3Downloader", isDirectory: true)
        self.fileURL = fileURL ?? support.appendingPathComponent("jobs-v1.json")
    }

    func load() throws -> [DownloadJob] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL)).jobs
    }

    func save(_ jobs: [DownloadJob]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Envelope(version: 1, jobs: jobs))
        let temporary = directory.appendingPathComponent(".jobs-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: fileURL)
        }
    }
}

