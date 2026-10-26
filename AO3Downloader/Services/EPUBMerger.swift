import AppKit
import Foundation
import SwiftSoup
import ZIPFoundation

struct EPUBMergeInput: Sendable {
    let entry: SeriesEntry
    let work: Work
    let fileURL: URL
}

private struct EPUBManifestItem {
    let id: String
    let href: String
    let mediaType: String
    let properties: String?
}

private struct EPUBPackage {
    let opfPath: String
    let manifest: [String: EPUBManifestItem]
    let spine: [String]
}

private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    var rootfile: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName.split(separator: ":").last == "rootfile" { rootfile = attributeDict["full-path"] }
    }
}

private final class OPFXMLDelegate: NSObject, XMLParserDelegate {
    var manifest: [String: EPUBManifestItem] = [:]
    var spine: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributes: [String: String] = [:]) {
        switch elementName.split(separator: ":").last {
        case "item":
            if let id = attributes["id"], let href = attributes["href"], let media = attributes["media-type"] {
                manifest[id] = .init(id: id, href: href, mediaType: media, properties: attributes["properties"])
            }
        case "itemref":
            if let idref = attributes["idref"] { spine.append(idref) }
        default: break
        }
    }
}

struct EPUBMerger: Sendable {
    func merge(series: Series, inputs: [EPUBMergeInput], metadata: EditableBookMetadata? = nil, to outputURL: URL) throws {
        guard !inputs.isEmpty else { throw AO3Error.mergeFailed("no EPUB works were supplied") }
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AO3Downloader/Staging", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let root = support.appendingPathComponent("Merge-\(UUID().uuidString)", isDirectory: true)
        let packageRoot = root.appendingPathComponent("Package", isDirectory: true)
        let oebps = packageRoot.appendingPathComponent("OEBPS", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: oebps, withIntermediateDirectories: true)
        try write("application/epub+zip", to: packageRoot.appendingPathComponent("mimetype"))
        try fileManager.createDirectory(at: packageRoot.appendingPathComponent("META-INF", isDirectory: true), withIntermediateDirectories: true)
        try write(containerXML, to: packageRoot.appendingPathComponent("META-INF/container.xml"))

        var manifestLines: [String] = []
        var spineLines: [String] = []
        var navigationWorks: [String] = []
        var authors: [String] = []
        var firstReadingHref: String?

        if let cover = metadata?.coverImageURL {
            let ext = cover.pathExtension.lowercased()
            let media = ["jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png"][ext]
            guard let media, NSImage(contentsOf: cover) != nil else {
                throw AO3Error.mergeFailed("cover image must be a readable JPEG or PNG")
            }
            let imageName = "cover.\(ext)"
            try fileManager.copyItem(at: cover, to: oebps.appendingPathComponent(imageName))
            try write(coverPage(imageName: imageName, title: metadata?.title ?? series.title),
                      to: oebps.appendingPathComponent("cover.xhtml"))
            manifestLines.append("<item id=\"cover-image\" href=\"\(imageName)\" media-type=\"\(media)\" properties=\"cover-image\"/>")
            manifestLines.append("<item id=\"cover-page\" href=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>")
            spineLines.append("<itemref idref=\"cover-page\"/>")
        }

        manifestLines.append("<item id=\"book-style\" href=\"styles/book.css\" media-type=\"text/css\"/>")
        manifestLines.append("<item id=\"title-page\" href=\"title.xhtml\" media-type=\"application/xhtml+xml\"/>")
        manifestLines.append("<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>")
        spineLines.append("<itemref idref=\"title-page\"/>")
        spineLines.append("<itemref idref=\"nav\"/>")

        for input in inputs.sorted(by: { $0.entry.position < $1.entry.position }) {
            try Task.checkCancellation()
            try DownloadValidator().validate(file: input.fileURL, format: .epub)
            let extracted = root.appendingPathComponent("Source-\(input.entry.position)", isDirectory: true)
            try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: input.fileURL, to: extracted)
            let package = try readPackage(at: extracted)
            let opfDirectory = extracted.appendingPathComponent(package.opfPath).deletingLastPathComponent()
            let namespace = "works/\(String(format: "%03d", input.entry.position))"
            let destinationBase = oebps.appendingPathComponent(namespace, isDirectory: true)
            try fileManager.createDirectory(at: destinationBase, withIntermediateDirectories: true)
            let dividerHref = "\(namespace)/index.xhtml"
            if firstReadingHref == nil { firstReadingHref = dividerHref }
            let dividerID = "w\(input.entry.position)_title"
            try write(workTitlePage(input), to: oebps.appendingPathComponent(dividerHref))
            manifestLines.append("<item id=\"\(dividerID)\" href=\"\(xml(dividerHref))\" media-type=\"application/xhtml+xml\"/>")
            spineLines.append("<itemref idref=\"\(dividerID)\"/>")

            var chapterLinks: [String] = []
            var mergedIDs: [String: String] = [:]
            for (itemIndex, item) in package.manifest.values.sorted(by: { $0.id < $1.id }).enumerated() {
                try Task.checkCancellation()
                guard isSafeRelativePath(item.href) else {
                    throw AO3Error.mergeFailed("part \(input.entry.position) contains an unsafe manifest path")
                }
                let source = opfDirectory.appendingPathComponent(item.href.removingPercentEncoding ?? item.href).standardizedFileURL
                guard source.path.hasPrefix(opfDirectory.standardizedFileURL.path + "/"), fileManager.fileExists(atPath: source.path) else {
                    throw AO3Error.mergeFailed("part \(input.entry.position) references a missing or escaping resource")
                }
                if item.mediaType.contains("javascript") { throw AO3Error.mergeFailed("scripted EPUB content is not merged") }
                if item.mediaType == "application/xhtml+xml" || item.mediaType == "text/html" {
                    try inspectMarkup(at: source, part: input.entry.position)
                }
                let relative = item.href.removingPercentEncoding ?? item.href
                let destination = destinationBase.appendingPathComponent(relative)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
                try fileManager.copyItem(at: source, to: destination)
                let newID = "w\(input.entry.position)_i\(itemIndex)_\(safeID(item.id))"
                mergedIDs[item.id] = newID
                let newHref = "\(namespace)/\(relative)"
                let propertyTokens = (item.properties ?? "").split(separator: " ").map(String.init).filter { $0 != "nav" }
                let properties = propertyTokens.isEmpty ? "" : " properties=\"\(xml(propertyTokens.joined(separator: " ")))\""
                manifestLines.append("<item id=\"\(newID)\" href=\"\(xml(newHref))\" media-type=\"\(xml(item.mediaType))\"\(properties)/>")
            }
            for idref in package.spine {
                guard let item = package.manifest[idref], let newID = mergedIDs[idref] else {
                    throw AO3Error.mergeFailed("part \(input.entry.position) has a broken spine")
                }
                spineLines.append("<itemref idref=\"\(newID)\"/>")
                let href = "\(namespace)/\(item.href.removingPercentEncoding ?? item.href)"
                let label = try chapterTitle(at: opfDirectory.appendingPathComponent(item.href.removingPercentEncoding ?? item.href))
                if isReadableSection(item: item, label: label, workTitle: input.work.title) {
                    chapterLinks.append("<li><a href=\"\(xml(href))\">\(xml(label))</a></li>")
                }
            }
            let workLabel = "Book \(input.entry.position): \(input.work.title)"
            let chapters = chapterLinks.isEmpty ? "" : "<ol>\(chapterLinks.joined())</ol>"
            navigationWorks.append("<li class=\"book-entry\"><a href=\"\(xml(dividerHref))\">\(xml(workLabel))</a>\(chapters)</li>")
            authors.append(contentsOf: input.work.creators)
        }

        let customAuthors = metadata?.authors ?? []
        let finalAuthors = customAuthors.isEmpty ? Array(Set(authors)).sorted() : customAuthors
        try write(bookStyle, to: oebps.appendingPathComponent("styles/book.css"))
        try write(titlePage(series: series, title: metadata?.title ?? series.title, authors: finalAuthors),
                  to: oebps.appendingPathComponent("title.xhtml"))
        try write(navigation(title: metadata?.title ?? series.title, works: navigationWorks,
                             firstReadingHref: firstReadingHref ?? "title.xhtml"),
                  to: oebps.appendingPathComponent("nav.xhtml"))
        let opf = contentOPF(series: series, metadata: metadata, authors: Array(Set(authors)).sorted(), manifest: manifestLines, spine: spineLines)
        try write(opf, to: oebps.appendingPathComponent("content.opf"))
        try createArchive(from: packageRoot, at: outputURL)
        try DownloadValidator().validate(file: outputURL, format: .epub)
    }

    private func readPackage(at root: URL) throws -> EPUBPackage {
        let containerURL = root.appendingPathComponent("META-INF/container.xml")
        let containerDelegate = ContainerXMLDelegate()
        guard let parser = XMLParser(contentsOf: containerURL) else { throw AO3Error.mergeFailed("missing container.xml") }
        parser.delegate = containerDelegate
        guard parser.parse(), let opfPath = containerDelegate.rootfile, isSafeRelativePath(opfPath) else {
            throw AO3Error.mergeFailed("invalid container.xml")
        }
        let opfURL = root.appendingPathComponent(opfPath).standardizedFileURL
        guard opfURL.path.hasPrefix(root.standardizedFileURL.path + "/"), let opfParser = XMLParser(contentsOf: opfURL) else {
            throw AO3Error.mergeFailed("unsafe or missing OPF package")
        }
        let delegate = OPFXMLDelegate(); opfParser.delegate = delegate
        guard opfParser.parse(), !delegate.manifest.isEmpty, !delegate.spine.isEmpty else {
            throw AO3Error.mergeFailed("invalid OPF manifest or spine")
        }
        return .init(opfPath: opfPath, manifest: delegate.manifest, spine: delegate.spine)
    }

    private func inspectMarkup(at url: URL, part: Int) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 16_000_000, let markup = String(data: data, encoding: .utf8) else {
            throw AO3Error.mergeFailed("part \(part) contains oversized or unsupported markup")
        }
        let document = try SwiftSoup.parse(markup)
        if try document.select("script").first() != nil { throw AO3Error.mergeFailed("scripted EPUB content is not merged") }
        for selector in ["[href]", "[src]"] {
            for element in try document.select(selector).array() {
                let attribute = selector == "[href]" ? "href" : "src"
                let value = try element.attr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("/") && !value.hasPrefix("//") {
                    throw AO3Error.mergeFailed("part \(part) contains an unsupported root-relative resource link")
                }
            }
        }
    }

    private func chapterTitle(at url: URL) throws -> String {
        guard let text = String(data: try Data(contentsOf: url, options: .mappedIfSafe), encoding: .utf8) else { return "Chapter" }
        let document = try SwiftSoup.parse(text)
        for selector in ["h1", "h2", "title"] {
            if let value = try document.select(selector).first()?.text(), !value.isEmpty { return value }
        }
        return "Chapter"
    }

    private func isReadableSection(item: EPUBManifestItem, label: String, workTitle: String) -> Bool {
        let path = item.href.lowercased()
        if path.contains("chapter") { return true }
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let work = workTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized != work && !["cover", "title page", "contents", "table of contents"].contains(normalized)
    }

    private func createArchive(from root: URL, at output: URL) throws {
        try? FileManager.default.removeItem(at: output)
        guard let archive = Archive(url: output, accessMode: .create) else { throw AO3Error.mergeFailed("could not create ZIP archive") }
        let mime = Data("application/epub+zip".utf8)
        try archive.addEntry(with: "mimetype", type: .file, uncompressedSize: Int64(mime.count), compressionMethod: .none) { position, size in
            mime.subdata(in: Int(position)..<Int(position) + size)
        }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var paths: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url != root.appendingPathComponent("mimetype"), (try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false) else { continue }
            paths.append(String(url.path.dropFirst(root.path.count + 1)))
        }
        for path in paths.sorted() {
            try Task.checkCancellation()
            try archive.addEntry(with: path, relativeTo: root, compressionMethod: .deflate)
        }
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              !path.contains("#"), !path.contains("?") else { return false }
        var depth = 0
        for part in path.split(separator: "/") {
            if part == ".." { depth -= 1 } else if part != "." { depth += 1 }
            if depth < 0 { return false }
        }
        return true
    }

    private func safeID(_ value: String) -> String {
        let cleaned = value.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" }
        return cleaned.isEmpty ? UUID().uuidString : String(cleaned)
    }

    private func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url, options: .atomic)
    }

    private var containerXML: String { """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
    """ }

    private func workTitlePage(_ input: EPUBMergeInput) -> String { """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(xml(input.work.language ?? "en"))"><head><title>\(xml(input.work.title))</title><link rel="stylesheet" type="text/css" href="../../styles/book.css"/></head><body class="part-title"><section epub:type="part"><p class="eyebrow">Book \(input.entry.position)</p><h1>\(xml(input.work.title))</h1><p class="byline">\(xml(byline(input.work.creators)))</p><div class="ornament">◆</div>\(summary(input.work.summary))<p class="source"><a href="\(xml(input.work.sourceURL.absoluteString))">Original work on AO3</a></p><p class="contents-link"><a href="../../nav.xhtml">Return to Contents</a></p></section></body></html>
    """ }

    private func navigation(title: String, works: [String], firstReadingHref: String) -> String { """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title><link rel="stylesheet" type="text/css" href="styles/book.css"/></head><body class="contents"><nav epub:type="toc" id="toc"><p class="eyebrow">\(xml(title))</p><h1>Contents</h1><ol>\(works.joined())</ol></nav><nav epub:type="landmarks" hidden="hidden"><ol><li><a epub:type="titlepage" href="title.xhtml">Title Page</a></li><li><a epub:type="toc" href="nav.xhtml">Contents</a></li><li><a epub:type="bodymatter" href="\(xml(firstReadingHref))">Begin Reading</a></li></ol></nav></body></html>
    """ }

    private func titlePage(series: Series, title: String, authors: [String]) -> String { """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>\(xml(title))</title><link rel="stylesheet" type="text/css" href="styles/book.css"/></head><body class="book-title"><section epub:type="titlepage"><p class="eyebrow">A series anthology</p><h1>\(xml(title))</h1><div class="ornament">◆</div><p class="byline">\(xml(byline(authors)))</p><p class="source"><a href="\(xml(series.sourceURL.absoluteString))">Original series on AO3</a></p></section></body></html>
    """ }

    private func byline(_ authors: [String]) -> String {
        authors.isEmpty ? "Unknown Creator" : "by \(authors.joined(separator: ", "))"
    }

    private func summary(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return "<blockquote>\(xml(value))</blockquote>"
    }

    private var bookStyle: String { """
    @charset "UTF-8";
    html { color: #222; background: transparent; }
    body { font-family: Georgia, "Times New Roman", serif; line-height: 1.55; margin: 5%; }
    a { color: #315c86; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .book-title, .part-title { text-align: center; }
    .book-title section, .part-title section { margin: 18vh auto 0; max-width: 36em; }
    h1 { font-weight: normal; line-height: 1.15; margin: 0.45em 0; }
    .book-title h1 { font-size: 2.4em; }
    .part-title h1 { font-size: 2em; }
    .eyebrow { font-family: -apple-system, sans-serif; font-size: 0.75em; font-weight: 600; letter-spacing: 0.14em; text-transform: uppercase; color: #666; }
    .byline { font-style: italic; }
    .ornament { color: #777; margin: 1.8em 0; }
    .source, .contents-link { font-size: 0.85em; margin-top: 2.4em; }
    blockquote { border-left: 0.18em solid #bbb; margin: 2em auto; max-width: 32em; padding-left: 1em; text-align: left; }
    .contents { max-width: 42em; margin: 5% auto; }
    .contents h1 { border-bottom: 1px solid #aaa; padding-bottom: 0.35em; }
    .contents ol { padding-left: 1.4em; }
    .contents li { margin: 0.55em 0; }
    .contents .book-entry { margin-top: 1.2em; }
    .contents .book-entry > a { font-weight: 700; }
    .contents .book-entry ol { font-size: 0.92em; }
    """ }

    private func coverPage(imageName: String, title: String) -> String { """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(xml(title))</title><style>html,body{margin:0;padding:0;text-align:center}img{max-width:100%;max-height:100vh}</style></head><body><section epub:type="cover" xmlns:epub="http://www.idpf.org/2007/ops"><img src="\(xml(imageName))" alt="Cover"/></section></body></html>
    """ }

    private func contentOPF(series: Series, metadata: EditableBookMetadata?, authors: [String], manifest: [String], spine: [String]) -> String {
        let customAuthors = metadata?.authors ?? []
        let finalAuthors = customAuthors.isEmpty ? authors : customAuthors
        let creators = finalAuthors.isEmpty ? "<dc:creator>Unknown Creator</dc:creator>" : finalAuthors.map { "<dc:creator>\(xml($0))</dc:creator>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">urn:uuid:\(UUID().uuidString)</dc:identifier><dc:title>\(xml(metadata?.title ?? series.title))</dc:title>\(creators)<dc:language>\(xml(metadata?.language ?? "en"))</dc:language><dc:source>\(xml(series.sourceURL.absoluteString))</dc:source><meta property="belongs-to-collection">\(xml(series.title))</meta><meta property="collection-type">series</meta><meta property="dcterms:modified">\(ISO8601DateFormatter().string(from: .now))</meta></metadata><manifest>\(manifest.joined())</manifest><spine>\(spine.joined())</spine></package>
        """
    }
}
