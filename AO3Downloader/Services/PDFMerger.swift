import Foundation
import AppKit
import PDFKit

struct PDFMergeInput: Sendable {
    let entry: SeriesEntry
    let work: Work
    let fileURL: URL
}

struct PDFMerger: Sendable {
    private let coverMarker = "AO3Downloader:ManagedCover"

    func merge(_ inputs: [PDFMergeInput], metadata: EditableBookMetadata? = nil, to outputURL: URL) throws {
        guard !inputs.isEmpty else { throw AO3Error.mergeFailed("no PDF works were supplied") }
        let output = PDFDocument()
        var expectedPages = 0
        if let coverURL = metadata?.coverImageURL {
            guard let image = NSImage(contentsOf: coverURL), let page = PDFPage(image: image) else {
                throw AO3Error.mergeFailed("cover image must be a readable JPEG or PNG")
            }
            let marker = PDFAnnotation(bounds: .zero, forType: .text, withProperties: nil)
            marker.contents = coverMarker
            page.addAnnotation(marker)
            output.insert(page, at: 0)
            expectedPages += 1
        }
        for input in inputs.sorted(by: { $0.entry.position < $1.entry.position }) {
            try Task.checkCancellation()
            guard let source = PDFDocument(url: input.fileURL), !source.isLocked, source.pageCount > 0 else {
                throw AO3Error.mergeFailed("part \(input.entry.position), \(input.work.title), is malformed or password-protected")
            }
            let replacesManagedCover = metadata != nil && inputs.count == 1
                && source.page(at: 0)?.annotations.contains(where: { $0.contents == coverMarker }) == true
            let firstPage = replacesManagedCover ? 1 : 0
            for index in firstPage..<source.pageCount {
                try Task.checkCancellation()
                guard let page = source.page(at: index) else {
                    throw AO3Error.mergeFailed("part \(input.entry.position) has an unreadable page")
                }
                output.insert(page, at: output.pageCount)
                expectedPages += 1
            }
        }
        if let metadata {
            let fallbackAuthors = Array(Set(inputs.flatMap { $0.work.creators })).sorted()
            output.documentAttributes = [PDFDocumentAttribute.titleAttribute: metadata.title,
                                         PDFDocumentAttribute.authorAttribute: (metadata.authors.isEmpty ? fallbackAuthors : metadata.authors).joined(separator: ", ")]
        }
        guard output.write(to: outputURL), let verification = PDFDocument(url: outputURL),
              verification.pageCount == expectedPages else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AO3Error.mergeFailed("the merged PDF failed page-count verification")
        }
    }
}
