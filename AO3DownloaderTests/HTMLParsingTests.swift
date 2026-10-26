import XCTest
@testable import AO3Downloader

final class HTMLParsingTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")
                                ?? bundle.url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesMetadataAndRealDownloadMenu() throws {
        let link = try AO3URLParser().parse("https://archiveofourown.org/works/123")
        let work = try AO3HTMLParser().parseWork(try fixture("work"), link: link)
        XCTAssertEqual(work.title, "Café 星の物語")
        XCTAssertEqual(work.chapterCountPublished, 3)
        XCTAssertEqual(work.wordCount, 12_345)
        XCTAssertEqual(work.downloadableFormats[.epub]?.host, "archiveofourown.org")
    }
    func testMissingTitleIsLayoutChange() throws {
        let link = try AO3URLParser().parse("https://archiveofourown.org/works/123")
        XCTAssertThrowsError(try AO3HTMLParser().parseWork("<html></html>", link: link))
    }

    func testRecognizesAdultContentInterstitialBeforeLayoutFailure() throws {
        let link = try AO3URLParser().parse("https://archiveofourown.org/works/123")
        XCTAssertThrowsError(try AO3HTMLParser().parseWork(try fixture("adult-warning"), link: link)) { error in
            XCTAssertEqual(error as? AO3Error, .adultConsentRequired)
        }
    }
}

