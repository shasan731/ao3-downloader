import Foundation
import PDFKit

struct PDFMergeInput: Sendable {
    let entry: SeriesEntry
    let work: Work
    let fileURL: URL
}

struct PDFMerger: Sendable {
    func merge(_ inputs: [PDFMergeInput], to outputURL: URL) throws {
        guard !inputs.isEmpty else { throw AO3Error.mergeFailed("no PDF works were supplied") }
        let output = PDFDocument()
        var expectedPages = 0
        for input in inputs.sorted(by: { $0.entry.position < $1.entry.position }) {
            guard let source = PDFDocument(url: input.fileURL), !source.isLocked, source.pageCount > 0 else {
                throw AO3Error.mergeFailed("part \(input.entry.position), \(input.work.title), is malformed or password-protected")
            }
            for index in 0..<source.pageCount {
                guard let page = source.page(at: index) else {
                    throw AO3Error.mergeFailed("part \(input.entry.position) has an unreadable page")
                }
                output.insert(page, at: output.pageCount)
                expectedPages += 1
            }
        }
        guard output.write(to: outputURL), let verification = PDFDocument(url: outputURL),
              verification.pageCount == expectedPages else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AO3Error.mergeFailed("the merged PDF failed page-count verification")
        }
    }
}
