import Foundation

struct FileNamingService: Sendable {
    func filename(for work: Work, format: DownloadFormat) -> String {
        let author = work.creators.joined(separator: ", ")
        return sanitize("\(work.title) - \(author.isEmpty ? "Unknown Creator" : author) [AO3-\(work.id)].\(format.fileExtension)")
    }

    func sanitize(_ value: String) -> String {
        var result = value.precomposedStringWithCanonicalMapping
        result = result.replacingOccurrences(of: #"[/:\x00-\x1F]"#, with: "-", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\.\."#, with: "-", options: .regularExpression)
        result = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if result.utf8.count > 220 { result = String(result.prefix(180)) + "-truncated" }
        return result.isEmpty ? "AO3 Download" : result
    }

    func availableURL(in directory: URL, filename: String, fileManager: FileManager = .default) -> URL {
        let initial = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }
        let stem = initial.deletingPathExtension().lastPathComponent, ext = initial.pathExtension
        for index in 2...9_999 {
            let candidate = directory.appendingPathComponent("\(stem) (\(index)).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(stem)-\(UUID().uuidString).\(ext)")
    }

    func availableDirectory(in parent: URL, name: String, fileManager: FileManager = .default) -> URL {
        let safeName = sanitize(name)
        let initial = parent.appendingPathComponent(safeName, isDirectory: true)
        guard fileManager.fileExists(atPath: initial.path) else { return initial }
        for index in 2...9_999 {
            let candidate = parent.appendingPathComponent("\(safeName) (\(index))", isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return parent.appendingPathComponent("\(safeName)-\(UUID().uuidString)", isDirectory: true)
    }
}

