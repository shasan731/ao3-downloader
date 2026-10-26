import XCTest
@testable import AO3Downloader

final class HTMLParsingTests: XCTestCase {
    func testParsesMetadataAndRealDownloadMenu() throws {
        let url = Bundle(for: Self.self).url(forResource: "work", withExtension: "html", subdirectory: "Fixtures")!
        let html = try String(contentsOf: url, encoding: .utf8)
        let link = try AO3URLParser().parse("https://archiveofourown.org/works/123")
        let work = try AO3HTMLParser().parseWork(html, link: link)
        XCTAssertEqual(work.title, "Café 星の物語")
        XCTAssertEqual(work.chapterCountPublished, 3)
        XCTAssertEqual(work.wordCount, 12_345)
        XCTAssertEqual(work.downloadableFormats[.epub]?.host, "archiveofourown.org")
    }
    func testMissingTitleIsLayoutChange() throws {
        let link = try AO3URLParser().parse("https://archiveofourown.org/works/123")
        XCTAssertThrowsError(try AO3HTMLParser().parseWork("<html></html>", link: link))
    }
}

