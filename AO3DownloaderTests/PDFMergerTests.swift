import AppKit
import Foundation
import PDFKit
import XCTest
@testable import AO3Downloader

final class PDFMergerTests: XCTestCase {
    func testPreservesPDFPageOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makePDF(at: root.appendingPathComponent("first.pdf"), labels: ["A1", "A2"])
        let second = try makePDF(at: root.appendingPathComponent("second.pdf"), labels: ["B1"])
        let output = root.appendingPathComponent("merged.pdf")
        try PDFMerger().merge([input(position: 1, file: first), input(position: 2, file: second)], to: output)
        let merged = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(merged.pageCount, 3)
        let labels = (0..<merged.pageCount).compactMap { merged.page(at: $0)?.annotations.first?.contents }
        XCTAssertEqual(labels, ["A1", "A2", "B1"])
    }

    private func makePDF(at url: URL, labels: [String]) throws -> URL {
        let document = PDFDocument()
        for label in labels {
            let image = NSImage(size: NSSize(width: 300, height: 400), flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                return true
            }
            guard let page = PDFPage(image: image) else { throw AO3Error.mergeFailed("could not create PDF fixture") }
            let annotation = PDFAnnotation(bounds: NSRect(x: 20, y: 20, width: 100, height: 30), forType: .freeText, withProperties: nil)
            annotation.contents = label
            page.addAnnotation(annotation)
            document.insert(page, at: document.pageCount)
        }
        guard document.write(to: url) else { throw AO3Error.mergeFailed("could not write PDF fixture") }
        return url
    }

    private func input(position: Int, file: URL) -> PDFMergeInput {
        let id = String(100 + position), source = URL(string: "https://archiveofourown.org/works/\(100 + position)")!
        let work = Work(id: id, title: "Work \(position)", creators: ["Fixture Author"], sourceURL: source,
                        summary: nil, language: "en", fandoms: [], rating: nil, warnings: [], tags: [],
                        completion: .complete, chapterCountPublished: 1, chapterCountExpected: 1,
                        wordCount: 10, downloadableFormats: [.pdf: source], accessState: .publicAccess)
        return .init(entry: .init(workID: id, position: position, title: work.title, sourceURL: source,
                                  accessState: .publicAccess, selected: true), work: work, fileURL: file)
    }
}
