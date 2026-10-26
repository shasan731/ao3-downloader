import AppKit
import Foundation
import PDFKit
import SwiftSoup
import ZIPFoundation

private final class MetadataContainerDelegate: NSObject, XMLParserDelegate {
    var rootfile: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName.split(separator: ":").last == "rootfile" { rootfile = attributeDict["full-path"] }
    }
}

struct BookMetadataEditor: Sendable {
    func apply(_ metadata: EditableBookMetadata, to fileURL: URL, format: DownloadFormat, work: Work) throws {
        let temporary = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".metadata-\(UUID().uuidString).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        switch format {
        case .epub:
            try editEPUB(metadata, source: fileURL, output: temporary)
        case .pdf:
            let entry = SeriesEntry(workID: work.id, position: 1, title: work.title,
                                    sourceURL: work.sourceURL, accessState: .publicAccess, selected: true)
            try PDFMerger().merge([.init(entry: entry, work: work, fileURL: fileURL)], metadata: metadata, to: temporary)
        case .html:
            let document = try SwiftSoup.parse(String(contentsOf: fileURL, encoding: .utf8))
            if let title = try document.select("title").first() { try title.text(metadata.title) }
            else { try document.head()?.appendElement("title").text(metadata.title) }
            try document.head()?.appendElement("meta").attr("name", "author").attr("content", metadata.authors.joined(separator: ", "))
            try Data(document.outerHtml().utf8).write(to: temporary, options: .atomic)
        }
        try DownloadValidator().validate(file: temporary, format: format)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
    }

    private func editEPUB(_ metadata: EditableBookMetadata, source: URL, output: URL) throws {
        try DownloadValidator().validate(file: source, format: .epub)
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent("AO3Metadata-\(UUID().uuidString)", isDirectory: true)
        let root = staging.appendingPathComponent("Package", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.unzipItem(at: source, to: root)

        let delegate = MetadataContainerDelegate()
        let directContainer = root.appendingPathComponent("META-INF/container.xml")
        var containerURL: URL? = fileManager.fileExists(atPath: directContainer.path) ? directContainer : nil
        if containerURL == nil {
            let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                    options: [.skipsHiddenFiles])
            while let candidate = enumerator?.nextObject() as? URL {
                if candidate.lastPathComponent == "container.xml",
                   candidate.deletingLastPathComponent().lastPathComponent == "META-INF" {
                    containerURL = candidate
                    break
                }
            }
        }
        guard let containerURL else { throw AO3Error.mergeFailed("the EPUB has no readable container") }
        let epubRoot = containerURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
        guard epubRoot.path.hasPrefix(root.standardizedFileURL.path) else {
            throw AO3Error.mergeFailed("the EPUB container escapes its extraction directory")
        }
        guard let parser = XMLParser(contentsOf: containerURL) else {
            throw AO3Error.mergeFailed("the EPUB has no readable container")
        }
        parser.delegate = delegate
        guard parser.parse(), let packagePath = delegate.rootfile, safeRelativePath(packagePath) else {
            throw AO3Error.mergeFailed("the EPUB package path is invalid")
        }
        let packageURL = epubRoot.appendingPathComponent(packagePath).standardizedFileURL
        guard packageURL.path.hasPrefix(epubRoot.path + "/"),
              var package = try? String(contentsOf: packageURL, encoding: .utf8) else {
            throw AO3Error.mergeFailed("the EPUB package is unreadable")
        }

        package = replacingFirst(in: package, pattern: #"<dc:title\b[^>]*>.*?</dc:title>"#,
                                 with: "<dc:title>\(xml(metadata.title))</dc:title>",
                                 insertion: "<dc:title>\(xml(metadata.title))</dc:title>")
        package = removingAll(in: package, pattern: #"<dc:creator\b[^>]*>.*?</dc:creator>"#)
        let creators = (metadata.authors.isEmpty ? ["Unknown Creator"] : metadata.authors)
            .map { "<dc:creator>\(xml($0))</dc:creator>" }.joined()
        package = insert(creators, beforeClosingTag: "metadata", in: package)
        package = replacingFirst(in: package, pattern: #"<dc:language\b[^>]*>.*?</dc:language>"#,
                                 with: "<dc:language>\(xml(metadata.language))</dc:language>",
                                 insertion: "<dc:language>\(xml(metadata.language))</dc:language>")

        let packageDirectory = packageURL.deletingLastPathComponent()
        for oldName in ["ao3downloader-cover.jpg", "ao3downloader-cover.jpeg", "ao3downloader-cover.png", "ao3downloader-cover.xhtml"] {
            try? fileManager.removeItem(at: packageDirectory.appendingPathComponent(oldName))
        }
        package = removingAll(in: package, pattern: #"<item\b[^>]*id=[\"']ao3downloader-cover-(?:image|page)[\"'][^>]*/?>"#)
        package = removingAll(in: package, pattern: #"<itemref\b[^>]*idref=[\"']ao3downloader-cover-page[\"'][^>]*/?>"#)
        package = removingAll(in: package, pattern: #"<meta\b[^>]*name=[\"']cover[\"'][^>]*content=[\"']ao3downloader-cover-image[\"'][^>]*/?>"#)
        if let cover = metadata.coverImageURL {
            let ext = cover.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png"].contains(ext), NSImage(contentsOf: cover) != nil else {
                throw AO3Error.mergeFailed("cover image must be a readable JPEG or PNG")
            }
            let imageName = "ao3downloader-cover.\(ext)"
            try fileManager.copyItem(at: cover, to: packageDirectory.appendingPathComponent(imageName))
            let page = """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(xml(metadata.title))</title><style>html,body{margin:0;text-align:center}img{max-width:100%;max-height:100vh}</style></head><body><img src="\(imageName)" alt="Cover"/></body></html>
            """
            try Data(page.utf8).write(to: packageDirectory.appendingPathComponent("ao3downloader-cover.xhtml"), options: .atomic)
            let media = ext == "png" ? "image/png" : "image/jpeg"
            let manifest = "<item id=\"ao3downloader-cover-image\" href=\"\(imageName)\" media-type=\"\(media)\" properties=\"cover-image\"/><item id=\"ao3downloader-cover-page\" href=\"ao3downloader-cover.xhtml\" media-type=\"application/xhtml+xml\"/>"
            package = insert(manifest, beforeClosingTag: "manifest", in: package)
            package = insert("<meta name=\"cover\" content=\"ao3downloader-cover-image\"/>", beforeClosingTag: "metadata", in: package)
            package = insertAfterOpeningTag("spine", content: "<itemref idref=\"ao3downloader-cover-page\"/>", in: package)
        }
        try Data(package.utf8).write(to: packageURL, options: .atomic)
        try createEPUB(from: epubRoot, at: output)
    }

    private func createEPUB(from root: URL, at output: URL) throws {
        guard let archive = Archive(url: output, accessMode: .create) else {
            throw AO3Error.mergeFailed("could not create the edited EPUB")
        }
        let mime = Data("application/epub+zip".utf8)
        try archive.addEntry(with: "mimetype", type: .file, uncompressedSize: Int64(mime.count), compressionMethod: .none) { position, size in
            mime.subdata(in: Int(position)..<Int(position) + size)
        }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var paths: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent != "mimetype",
                  (try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false) else { continue }
            paths.append(String(url.path.dropFirst(root.path.count + 1)))
        }
        for path in paths.sorted() { try archive.addEntry(with: path, relativeTo: root, compressionMethod: .deflate) }
    }

    private func replacingFirst(in source: String, pattern: String, with replacement: String, insertion: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        if let match = regex.firstMatch(in: source, range: range), let matchRange = Range(match.range, in: source) {
            return source.replacingCharacters(in: matchRange, with: replacement)
        }
        return insert(insertion, beforeClosingTag: "metadata", in: source)
    }

    private func removingAll(in source: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return source }
        return regex.stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: "")
    }

    private func insert(_ content: String, beforeClosingTag tag: String, in source: String) -> String {
        guard !content.isEmpty,
              let regex = try? NSRegularExpression(pattern: "</(?:[A-Za-z0-9_-]+:)?\(tag)\\s*>", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range, in: source) else { return source }
        var copy = source
        copy.insert(contentsOf: content, at: range.lowerBound)
        return copy
    }

    private func insertAfterOpeningTag(_ tag: String, content: String, in source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<(?:[A-Za-z0-9_-]+:)?\(tag)\\b[^>]*>", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range, in: source) else { return source }
        var copy = source
        copy.insert(contentsOf: content, at: range.upperBound)
        return copy
    }

    private func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && !path.split(separator: "/").contains("..")
    }

    private func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
