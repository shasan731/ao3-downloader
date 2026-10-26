import Foundation
import XCTest
@testable import AO3Downloader

private actor SyntheticSeriesProvider: AO3Providing {
    func analyze(_ link: AO3Link) async throws -> Work {
        if link.id == "102" { throw AO3Error.accessRequired }
        return Work(id: link.id, title: "Work \(link.id)", creators: ["Fixture Author"],
                    sourceURL: link.canonicalURL, summary: nil, language: "English", fandoms: [],
                    rating: nil, warnings: [], tags: [], completion: .complete,
                    chapterCountPublished: 1, chapterCountExpected: 1, wordCount: 10,
                    downloadableFormats: [.html: URL(string: "https://archiveofourown.org/downloads/\(link.id)/fixture.html")!],
                    accessState: .publicAccess)
    }

    func analyzeSeries(_ link: AO3Link) async throws -> Series { throw AO3Error.unsupportedPath }

    func download(_ work: Work, format: DownloadFormat) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
        try Data("<!doctype html><title>\(work.title)</title>".utf8).write(to: url)
        return url
    }
}

final class SeriesDownloadTests: XCTestCase {
    func testRetainsSuccessesAndReportsEveryFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = URL(string: "https://archiveofourown.org/series/99")!
        let series = Series(id: "99", title: "Synthetic Saga", creators: ["Fixture Author"], description: nil,
                            sourceURL: source, orderedWorks: [
                                .init(workID: "101", position: 1, title: "First", sourceURL: URL(string: "https://archiveofourown.org/works/101")!, accessState: .publicAccess, selected: true),
                                .init(workID: "102", position: 2, title: "Second", sourceURL: URL(string: "https://archiveofourown.org/works/102")!, accessState: .publicAccess, selected: true),
                                .init(workID: "unavailable-page-1-3", position: 3, title: "Unavailable", sourceURL: source, accessState: .unavailable, selected: false)
                            ], isCompletePagination: true)
        let result = try await DownloadManager(provider: SyntheticSeriesProvider()).download(series: series, format: .html, outputMode: .separate, to: root)
        XCTAssertEqual(result.outputFiles.count, 1)
        XCTAssertTrue(result.outputFiles[0].lastPathComponent.hasPrefix("01 - "))
        XCTAssertEqual(result.failures.map(\.position), [2, 3])
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("download-report.json").path))
    }
}
