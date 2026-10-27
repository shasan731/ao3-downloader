import Foundation
import XCTest
@testable import AO3Downloader

final class LibraryStoreTests: XCTestCase {
    func testPersistsRecombinableSeriesState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = root.appendingPathComponent("library.json")
        let store = LibraryStore(fileURL: libraryURL)
        let seriesURL = URL(string: "https://archiveofourown.org/series/99")!
        let workURL = URL(string: "https://archiveofourown.org/works/101")!
        let entry = SeriesEntry(workID: "101", position: 1, title: "First", sourceURL: workURL,
                                accessState: .publicAccess, selected: true)
        let work = Work(id: "101", title: "First", creators: ["Author"], sourceURL: workURL,
                        summary: nil, language: "en", fandoms: [], rating: nil, warnings: [], tags: [],
                        completion: .complete, chapterCountPublished: 1, chapterCountExpected: 1,
                        wordCount: 10, downloadableFormats: [.epub: workURL], accessState: .publicAccess)
        let series = Series(id: "99", title: "Series", creators: ["Author"], description: nil,
                            sourceURL: seriesURL, orderedWorks: [entry], isCompletePagination: true)
        let record = LibraryRecord(id: UUID(), kind: .series, sourceURL: seriesURL, series: series,
                                   singleWork: nil, format: .epub, outputMode: .combined,
                                   destinationURL: root, destinationBookmark: nil,
                                   metadata: .init(title: "Custom", authors: ["Editor"], language: "en", coverImageURL: nil),
                                   downloadedParts: [.init(entry: entry, work: work, fileURL: root.appendingPathComponent("part.epub"))],
                                   singleFileURL: nil, combinedFiles: [], failures: [], createdAt: .now, updatedAt: .now)
        try await store.save([record])
        let loaded = try await store.load()
        XCTAssertEqual(loaded.first?.id, record.id)
        XCTAssertEqual(loaded.first?.downloadedParts.first?.entry.position, 1)
        XCTAssertEqual(loaded.first?.metadata.title, "Custom")

        var updated = record
        updated.metadata.title = "Updated"
        try await store.save([updated])
        let updatedLoad = try await store.load()
        XCTAssertEqual(updatedLoad.first?.metadata.title, "Updated")

        try Data("{not valid json".utf8).write(to: libraryURL, options: .atomic)
        let recovered = try await store.load()
        XCTAssertEqual(recovered.first?.metadata.title, "Custom")
    }
}
