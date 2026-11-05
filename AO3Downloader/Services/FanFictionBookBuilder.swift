import AppKit
import CoreText
import Foundation
import PDFKit
import ZIPFoundation

struct FanFictionBookBuilder: Sendable {
    func build(work: Work, chapters: [FanFictionChapter], format: DownloadFormat) async throws -> URL {
        guard !chapters.isEmpty else { throw AO3Error.invalidDownload("the story has no chapters") }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveBind-\(UUID().uuidString).\(format.fileExtension)")
        do {
            switch format {
            case .epub: try buildEPUB(work: work, chapters: chapters, to: output)
            case .pdf: try await buildPDF(work: work, chapters: chapters, to: output)
            case .html: try Data(htmlBook(work: work, chapters: chapters).utf8).write(to: output, options: .atomic)
            }
            try DownloadValidator().validate(file: output, format: format)
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private func buildEPUB(work: Work, chapters: [FanFictionChapter], to output: URL) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("ArchiveBind-EPUB-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        try fileManager.createDirectory(at: oebps.appendingPathComponent("chapters", isDirectory: true), withIntermediateDirectories: true)
        try write("application/epub+zip", to: root.appendingPathComponent("mimetype"))
        try write(containerXML, to: root.appendingPathComponent("META-INF/container.xml"))
        try write(bookCSS, to: oebps.appendingPathComponent("book.css"))
        try write(titlePage(work), to: oebps.appendingPathComponent("title.xhtml"))
        try write(navigation(work: work, chapters: chapters), to: oebps.appendingPathComponent("nav.xhtml"))
        for chapter in chapters {
            try Task.checkCancellation()
            try write(chapterPage(work: work, chapter: chapter),
                      to: oebps.appendingPathComponent("chapters/chapter-\(chapter.number).xhtml"))
        }
        try write(package(work: work, chapters: chapters), to: oebps.appendingPathComponent("content.opf"))
        guard let archive = Archive(url: output, accessMode: .create) else {
            throw AO3Error.invalidDownload("could not create the EPUB archive")
        }
        let mime = Data("application/epub+zip".utf8)
        try archive.addEntry(with: "mimetype", type: .file, uncompressedSize: Int64(mime.count), compressionMethod: .none) { position, size in
            mime.subdata(in: Int(position)..<Int(position) + size)
        }
        for path in try fileManager.subpathsOfDirectory(atPath: root.path).sorted() where path != "mimetype" {
            let url = root.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                try archive.addEntry(with: path, relativeTo: root, compressionMethod: .deflate)
            }
        }
    }

    private func buildPDF(work: Work, chapters: [FanFictionChapter], to output: URL) async throws {
        let body = PDFDocument()
        let outlineRoot = PDFOutline()
        for chapter in chapters {
            try Task.checkCancellation()
            let attributed = try await MainActor.run { try attributedChapter(chapter) }
            let chapterData = try renderedPDF(attributed)
            guard let document = PDFDocument(data: chapterData), document.pageCount > 0 else {
                throw AO3Error.invalidDownload("chapter \(chapter.number) could not be rendered as PDF")
            }
            let start = body.pageCount
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                body.insert(page, at: body.pageCount)
            }
            if let firstPage = body.page(at: start) {
                let item = PDFOutline()
                item.label = chapter.title
                item.destination = PDFDestination(page: firstPage, at: NSPoint(x: 0, y: firstPage.bounds(for: .mediaBox).height))
                outlineRoot.insertChild(item, at: outlineRoot.numberOfChildren)
            }
        }
        body.outlineRoot = outlineRoot
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveBind-PDF-Body-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: raw) }
        guard body.write(to: raw) else { throw AO3Error.invalidDownload("could not save the PDF body") }
        let entry = SeriesEntry(workID: work.id, position: 1, title: work.title,
                                sourceURL: work.sourceURL, accessState: .publicAccess, selected: true)
        try PDFMerger().merge([.init(entry: entry, work: work, fileURL: raw)], to: output)
    }

    @MainActor
    private func attributedChapter(_ chapter: FanFictionChapter) throws -> NSAttributedString {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font-family: Georgia, 'Times New Roman', serif; font-size: 12pt; line-height: 1.55; color: #1f1f1f; }
        h1 { font-family: -apple-system, sans-serif; font-size: 22pt; font-weight: 500; margin-bottom: 28pt; }
        p { margin: 0 0 9pt; } hr { margin: 18pt 25%; }
        </style></head><body><h1>\(xml(chapter.title))</h1>\(chapter.bodyHTML)</body></html>
        """
        guard let attributed = try? NSAttributedString(data: Data(html.utf8),
                                                       options: [.documentType: NSAttributedString.DocumentType.html,
                                                                 .characterEncoding: String.Encoding.utf8.rawValue],
                                                       documentAttributes: nil), attributed.length > 0 else {
            throw AO3Error.invalidDownload("chapter \(chapter.number) contains unsupported formatting")
        }
        return attributed
    }

    private func renderedPDF(_ attributed: NSAttributedString) throws -> Data {
        guard let data = CFDataCreateMutable(nil, 0),
              let consumer = CGDataConsumer(data: data) else {
            throw AO3Error.invalidDownload("could not initialize PDF rendering")
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw AO3Error.invalidDownload("could not initialize PDF rendering")
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var location = 0
        while location < attributed.length {
            try Task.checkCancellation()
            context.beginPDFPage(nil)
            let path = CGPath(rect: CGRect(x: 68, y: 62, width: 476, height: 668), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { throw AO3Error.invalidDownload("PDF pagination stopped unexpectedly") }
            location += visible.length
        }
        context.closePDF()
        return data as Data
    }

    private func htmlBook(work: Work, chapters: [FanFictionChapter]) -> String {
        let toc = chapters.map { "<li><a href=\"#chapter-\($0.number)\">\(xml($0.title))</a></li>" }.joined()
        let body = chapters.map { chapter in
            "<section class=\"chapter\" id=\"chapter-\(chapter.number)\"><h2>\(xml(chapter.title))</h2>\(chapter.bodyHTML)<p class=\"return\"><a href=\"#contents\">Return to Contents</a></p></section>"
        }.joined()
        return """
        <!doctype html><html lang="\(xml(work.language ?? "en"))"><head><meta charset="utf-8">
        <meta name="author" content="\(xml(work.creators.joined(separator: ", ")))"><title>\(xml(work.title))</title>
        <style>\(bookCSS)</style></head><body><header><p class="eyebrow">A complete work</p><h1>\(xml(work.title))</h1><p>\(xml(byline(work)))</p><p><a href="\(xml(work.sourceURL.absoluteString))">Original story on FanFiction.net</a></p></header>
        <nav id="contents"><h2>Contents</h2><ol>\(toc)</ol></nav>\(body)</body></html>
        """
    }

    private func titlePage(_ work: Work) -> String { """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" lang="\(xml(work.language ?? "en"))"><head><title>\(xml(work.title))</title><link rel="stylesheet" href="book.css" type="text/css"/></head><body class="title-page"><main><p class="eyebrow">A complete work</p><h1>\(xml(work.title))</h1><div class="ornament">◆</div><p>\(xml(byline(work)))</p><p class="source"><a href="\(xml(work.sourceURL.absoluteString))">Original story on FanFiction.net</a></p></main></body></html>
    """ }

    private func navigation(work: Work, chapters: [FanFictionChapter]) -> String {
        let items = chapters.map { "<li><a href=\"chapters/chapter-\($0.number).xhtml\">\(xml($0.title))</a></li>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title><link rel="stylesheet" href="book.css" type="text/css"/></head><body><nav epub:type="toc" id="toc"><p class="eyebrow">\(xml(work.title))</p><h1>Contents</h1><ol>\(items)</ol></nav><nav epub:type="landmarks" hidden="hidden"><ol><li><a epub:type="titlepage" href="title.xhtml">Title Page</a></li><li><a epub:type="toc" href="nav.xhtml">Contents</a></li><li><a epub:type="bodymatter" href="chapters/chapter-1.xhtml">Begin Reading</a></li></ol></nav></body></html>
        """
    }

    private func chapterPage(work: Work, chapter: FanFictionChapter) -> String { """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml" lang="\(xml(work.language ?? "en"))"><head><title>\(xml(chapter.title))</title><link rel="stylesheet" href="../book.css" type="text/css"/></head><body class="chapter"><h1>\(xml(chapter.title))</h1>\(chapter.bodyHTML)<p class="return"><a href="../nav.xhtml">Return to Contents</a></p></body></html>
    """ }

    private func package(work: Work, chapters: [FanFictionChapter]) -> String {
        let manifest = chapters.map { "<item id=\"chapter-\($0.number)\" href=\"chapters/chapter-\($0.number).xhtml\" media-type=\"application/xhtml+xml\"/>" }.joined()
        let spine = chapters.map { "<itemref idref=\"chapter-\($0.number)\"/>" }.joined()
        let creators = (work.creators.isEmpty ? ["Unknown Author"] : work.creators).map { "<dc:creator>\(xml($0))</dc:creator>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">urn:fanfiction-net:\(xml(work.id))</dc:identifier><dc:title>\(xml(work.title))</dc:title>\(creators)<dc:language>\(xml(work.language ?? "en"))</dc:language><meta property="dcterms:modified">\(isoTimestamp())</meta></metadata><manifest><item id="style" href="book.css" media-type="text/css"/><item id="title" href="title.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\(manifest)</manifest><spine><itemref idref="title"/><itemref idref="nav"/>\(spine)</spine></package>
        """
    }

    private var containerXML: String { """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
    """ }

    private var bookCSS: String { """
    html { color: #222; background: transparent; } body { font-family: Georgia, "Times New Roman", serif; line-height: 1.58; margin: 5%; max-width: 42em; } a { color: #315c86; text-decoration: none; } h1, h2 { font-weight: normal; line-height: 1.2; } .title-page { text-align: center; } .title-page main { margin: 18vh auto 0; } .eyebrow { font-family: sans-serif; font-size: .75em; font-weight: bold; letter-spacing: .14em; text-transform: uppercase; color: #666; } .ornament { color: #777; margin: 1.8em 0; } .source, .return { font-size: .85em; margin-top: 2.4em; } nav ol { line-height: 1.8; } .chapter h1 { margin-bottom: 2em; } hr { border: 0; text-align: center; margin: 2em 25%; border-top: 1px solid #aaa; }
    """ }

    private func byline(_ work: Work) -> String {
        work.creators.isEmpty ? "Unknown Author" : "by " + work.creators.joined(separator: ", ")
    }

    private func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url, options: .atomic)
    }

    private func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
