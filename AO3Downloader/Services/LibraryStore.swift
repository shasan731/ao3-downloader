import AppKit
import Foundation

actor LibraryStore {
    private struct Envelope: Codable { let version: Int; var records: [LibraryRecord] }
    private let fileURL: URL
    private var backupURL: URL { fileURL.deletingPathExtension().appendingPathExtension("backup.json") }

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AO3Downloader", isDirectory: true)
        self.fileURL = fileURL ?? support.appendingPathComponent("library-v1.json")
    }

    func load() throws -> [LibraryRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try decode(fileURL)
        } catch {
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                throw AO3Error.storage("the Library database is unreadable and no recovery copy is available")
            }
            do { return try decode(backupURL) }
            catch { throw AO3Error.storage("both the Library database and its recovery copy are unreadable") }
        }
    }

    func save(_ records: [LibraryRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Envelope(version: 1, records: records))
        let temporary = directory.appendingPathComponent(".library-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if (try? decode(fileURL)) != nil {
                let current = try Data(contentsOf: fileURL)
                try current.write(to: backupURL, options: .atomic)
            }
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: fileURL)
        }
    }

    private func decode(_ url: URL) throws -> [LibraryRecord] {
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.version == 1 else { throw AO3Error.storage("unsupported Library database version") }
        return envelope.records.sorted { $0.updatedAt > $1.updatedAt }
    }

    func copyManagedCover(from source: URL) throws -> URL {
        guard ["jpg", "jpeg", "png"].contains(source.pathExtension.lowercased()),
              let image = NSImage(contentsOf: source), image.size.width > 0, image.size.height > 0 else {
            throw AO3Error.storage("cover image must be a readable JPEG or PNG")
        }
        let support = fileURL.deletingLastPathComponent().appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let ext = source.pathExtension.lowercased()
        let target = support.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
}

enum SecurityScopedLocation {
    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ bookmark: Data?, fallback: URL) -> URL {
        guard let bookmark else { return fallback }
        var stale = false
        return (try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                         relativeTo: nil, bookmarkDataIsStale: &stale)) ?? fallback
    }
}
