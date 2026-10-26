import XCTest
@testable import AO3Downloader

final class URLParsingTests: XCTestCase {
    let parser = AO3URLParser()
    func testNormalizesWorkAndChapter() throws {
        XCTAssertEqual(try parser.parse("https://archiveofourown.org/works/123?view_full_work=true#x").canonicalURL.absoluteString, "https://archiveofourown.org/works/123")
        XCTAssertEqual(try parser.parse("https://archiveofourown.org/works/123/chapters/456").id, "123")
    }
    func testParsesSeries() throws { XCTAssertEqual(try parser.parse("https://archiveofourown.org/series/987/").kind, .series) }
    func testRejectsUnsafeInputs() {
        for value in ["http://archiveofourown.org/works/1", "https://archiveofourown.org.evil.test/works/1", "https://archiveofourown.org/works/nope", "file:///etc/passwd"] {
            XCTAssertThrowsError(try parser.parse(value), value)
        }
    }
}

