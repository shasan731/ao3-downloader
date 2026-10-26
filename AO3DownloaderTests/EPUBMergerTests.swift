import Foundation
import XCTest
import ZIPFoundation
@testable import AO3Downloader

final class EPUBMergerTests: XCTestCase {
    func testCreatesEPUB3WithSeriesWorkChapterOrderAndNamespacedResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeEPUB(at: root, name: "first", chapter: "Chapter One", assetText: "first")
        let second = try makeEPUB(at: root, name: "second", chapter: "Chapter Two", assetText: "second")
        let seriesURL = URL(string: "https://archiveofourown.org/series/99")!
        let series = Series(id: "99", title: "Synthetic Saga", creators: ["Fixture Author"], description: nil,
                            sourceURL: seriesURL, orderedWorks: [], isCompletePagination: true)
        let inputs = [
            input(position: 1, id: "101", title: "First Work", file: first),
            input(position: 2, id: "102", title: "Second Work", file: second)
        ]
        let output = root.appendingPathComponent("merged.epub")
        try EPUBMerger().merge(series: series, inputs: inputs, to: output)
        try DownloadValidator().validate(file: output, format: .epub)
        guard let archive = Archive(url: output, accessMode: .read) else { return XCTFail("Could not reopen merged EPUB") }
        var iterator = archive.makeIterator()
        XCTAssertEqual(iterator.next()?.path, "mimetype")

        let extracted = root.appendingPathComponent("merged", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)
        try FileManager.default.unzipItem(at: output, to: extracted)
        let opf = try String(contentsOf: extracted.appendingPathComponent("OEBPS/content.opf"), encoding: .utf8)
        let nav = try String(contentsOf: extracted.appendingPathComponent("OEBPS/nav.xhtml"), encoding: .utf8)
        XCTAssertTrue(opf.contains("works/001/Text/chapter.xhtml"))
        XCTAssertTrue(opf.contains("works/002/Text/chapter.xhtml"))
        XCTAssertLessThan(try XCTUnwrap(nav.range(of: "Part 1: First Work")?.lowerBound),
                          try XCTUnwrap(nav.range(of: "Part 2: Second Work")?.lowerBound))
        XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent("OEBPS/works/001/Images/shared.txt"), encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent("OEBPS/works/002/Images/shared.txt"), encoding: .utf8), "second")
    }

    func testEditsEPUBMetadataAndCoverInPlaceWithoutNestingBook() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try makeEPUB(at: root, name: "editable", chapter: "Chapter", assetText: "asset")
        let cover = root.appendingPathComponent("cover.png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!.write(to: cover)
        let source = URL(string: "https://archiveofourown.org/works/101")!
        let work = Work(id: "101", title: "Original", creators: ["Original Author"], sourceURL: source,
                        summary: nil, language: "en", fandoms: [], rating: nil, warnings: [], tags: [],
                        completion: .complete, chapterCountPublished: 1, chapterCountExpected: 1,
                        wordCount: 10, downloadableFormats: [.epub: source], accessState: .publicAccess)
        try BookMetadataEditor().apply(.init(title: "Edited & Safe", authors: ["New Author"], language: "fr", coverImageURL: cover),
                                       to: file, format: .epub, work: work)
        let extracted = root.appendingPathComponent("edited", isDirectory: true)
        try FileManager.default.unzipItem(at: file, to: extracted)
        let opf = try String(contentsOf: extracted.appendingPathComponent("OEBPS/content.opf"), encoding: .utf8)
        XCTAssertTrue(opf.contains("<dc:title>Edited &amp; Safe</dc:title>"))
        XCTAssertTrue(opf.contains("<dc:creator>New Author</dc:creator>"))
        XCTAssertTrue(opf.contains("<dc:language>fr</dc:language>"))
        XCTAssertTrue(opf.contains("ao3downloader-cover-image"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("OEBPS/ao3downloader-cover.png").path))
        XCTAssertFalse(opf.contains("works/001"))
    }

    private func input(position: Int, id: String, title: String, file: URL) -> EPUBMergeInput {
        let source = URL(string: "https://archiveofourown.org/works/\(id)")!
        let work = Work(id: id, title: title, creators: ["Fixture Author"], sourceURL: source,
                        summary: nil, language: "en", fandoms: [], rating: nil, warnings: [], tags: [],
                        completion: .complete, chapterCountPublished: 1, chapterCountExpected: 1,
                        wordCount: 10, downloadableFormats: [.epub: source], accessState: .publicAccess)
        let entry = SeriesEntry(workID: id, position: position, title: title, sourceURL: source,
                                accessState: .publicAccess, selected: true)
        return .init(entry: entry, work: work, fileURL: file)
    }

    private func makeEPUB(at root: URL, name: String, chapter: String, assetText: String) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("OEBPS/Text"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("OEBPS/Images"), withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: directory.appendingPathComponent("mimetype"))
        try Data("""
        <?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """.utf8).write(to: directory.appendingPathComponent("META-INF/container.xml"))
        try Data("""
        <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(name)</dc:title></metadata><manifest><item id="chapter" href="Text/chapter.xhtml" media-type="application/xhtml+xml"/><item id="asset" href="Images/shared.txt" media-type="text/plain"/></manifest><spine><itemref idref="chapter"/></spine></package>
        """.utf8).write(to: directory.appendingPathComponent("OEBPS/content.opf"))
        try Data("<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>\(chapter)</title></head><body><h2>\(chapter)</h2><a href=\"../Images/shared.txt\">asset</a></body></html>".utf8)
            .write(to: directory.appendingPathComponent("OEBPS/Text/chapter.xhtml"))
        try Data(assetText.utf8).write(to: directory.appendingPathComponent("OEBPS/Images/shared.txt"))
        let output = root.appendingPathComponent(name + ".epub")
        try FileManager.default.zipItem(at: directory, to: output, shouldKeepParent: false, compressionMethod: .none)
        return output
    }
}
