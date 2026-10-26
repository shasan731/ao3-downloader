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
        XCTAssertEqual(merged.pageCount, 5)
        let labels = (0..<merged.pageCount).flatMap { merged.page(at: $0)?.annotations.compactMap(\.contents) ?? [] }
            .filter { ["A1", "A2", "B1"].contains($0) }
        XCTAssertEqual(labels, ["A1", "A2", "B1"])
        let rootOutline = try XCTUnwrap(merged.outlineRoot)
        XCTAssertEqual(rootOutline.numberOfChildren, 4)
        XCTAssertEqual(rootOutline.child(at: 2)?.label, "Book 1: Work 1")
        XCTAssertEqual(rootOutline.child(at: 2)?.numberOfChildren, 2)
        XCTAssertEqual(rootOutline.child(at: 2)?.child(at: 0)?.label, "A1")
        let contentsPage = try XCTUnwrap(merged.page(at: 1))
        XCTAssertEqual(contentsPage.annotations.filter { $0.destination != nil }.count, 5)
    }

    func testAppliesMetadataAndManagedCover() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makePDF(at: root.appendingPathComponent("source.pdf"), labels: ["Body"])
        let cover = root.appendingPathComponent("cover.png")
        let image = NSImage(size: NSSize(width: 200, height: 300), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        try XCTUnwrap(image.tiffRepresentation).write(to: cover)
        let output = root.appendingPathComponent("metadata.pdf")
        let metadata = EditableBookMetadata(title: "Custom Title", authors: ["Custom Author"], language: "en", coverImageURL: cover)
        try PDFMerger().merge([input(position: 1, file: source)], metadata: metadata, to: output)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 4)
        XCTAssertEqual(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Custom Title")
        XCTAssertEqual(document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String, "Custom Author")

        let edited = root.appendingPathComponent("metadata-edited.pdf")
        try PDFMerger().merge([input(position: 1, file: output)],
                              metadata: .init(title: "Edited Again", authors: ["Custom Author"], language: "en", coverImageURL: cover),
                              to: edited)
        let editedDocument = try XCTUnwrap(PDFDocument(url: edited))
        XCTAssertEqual(editedDocument.pageCount, 4)
        XCTAssertEqual(editedDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Edited Again")
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
        let root = PDFOutline()
        for (index, label) in labels.enumerated() {
            let item = PDFOutline()
            item.label = label
            item.destination = PDFDestination(page: try XCTUnwrap(document.page(at: index)), at: .zero)
            root.insertChild(item, at: root.numberOfChildren)
        }
        document.outlineRoot = root
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
