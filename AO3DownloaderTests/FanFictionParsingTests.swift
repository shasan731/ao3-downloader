import Foundation
import XCTest
@testable import AO3Downloader

final class FanFictionParsingTests: XCTestCase {
    private func fixture() throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "fanfiction-story", withExtension: "html", subdirectory: "Fixtures")
                                ?? bundle.url(forResource: "fanfiction-story", withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testNormalizesStoryAndChapterURLs() throws {
        let parser = FanFictionURLParser()
        XCTAssertEqual(try parser.parse("https://www.fanfiction.net/s/123/8/Example-Story?ignored=1#top").canonicalURL.absoluteString,
                       "https://www.fanfiction.net/s/123/1")
        XCTAssertEqual(try SourceURLParser().parse("https://www.fanfiction.net/s/123/1").id, "123")
    }

    func testRejectsLookalikeAndNonHTTPSHosts() {
        for value in ["http://www.fanfiction.net/s/123/1",
                      "https://fanfiction.net/s/123/1",
                      "https://www.fanfiction.net.evil.test/s/123/1",
                      "https://www.fanfiction.net/u/42/Author"] {
            XCTAssertThrowsError(try FanFictionURLParser().parse(value), value)
        }
    }

    func testParsesMetadataChaptersAndSanitizesBody() throws {
        let link = try FanFictionURLParser().parse("https://www.fanfiction.net/s/123/1/Example-Story")
        let result = try FanFictionHTMLParser().parseAnalysis(try fixture(), link: link)
        XCTAssertEqual(result.work.title, "Example Story")
        XCTAssertEqual(result.work.creators, ["Example Author"])
        XCTAssertEqual(result.work.chapterCountPublished, 2)
        XCTAssertEqual(result.work.wordCount, 1_234)
        XCTAssertEqual(result.work.completion, .complete)
        XCTAssertEqual(result.chapterTitles, ["The Beginning", "The Ending"])
        XCTAssertFalse(result.firstChapter.bodyHTML.contains("script"))
        XCTAssertFalse(result.firstChapter.bodyHTML.contains("href"))
    }

    func testRecognizesBrowserChallenge() throws {
        let link = try FanFictionURLParser().parse("https://www.fanfiction.net/s/123/1")
        XCTAssertThrowsError(try FanFictionHTMLParser().parseAnalysis("<html><head><title>Just a moment...</title></head></html>", link: link)) { error in
            XCTAssertEqual(error as? AO3Error, .challengedSite("FanFiction.net"))
        }
    }

    func testBuildsVerifiedOfflineBooksInEveryFormat() async throws {
        let link = try FanFictionURLParser().parse("https://www.fanfiction.net/s/123/1")
        let analysis = try FanFictionHTMLParser().parseAnalysis(try fixture(), link: link)
        let chapters = [analysis.firstChapter,
                        FanFictionChapter(number: 2, title: "The Ending", bodyHTML: "<p>Synthetic ending.</p>")]
        for format in DownloadFormat.allCases {
            let output = try await FanFictionBookBuilder().build(work: analysis.work, chapters: chapters, format: format)
            defer { try? FileManager.default.removeItem(at: output) }
            XCTAssertNoThrow(try DownloadValidator().validate(file: output, format: format))
        }
    }
}
