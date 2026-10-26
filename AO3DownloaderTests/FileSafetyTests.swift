import XCTest
@testable import AO3Downloader

final class FileSafetyTests: XCTestCase {
    func testSanitizesTraversalAndKeepsUnicode() {
        let value = FileNamingService().sanitize("../../Café/星:\u{0}name.epub")
        XCTAssertFalse(value.contains("..")); XCTAssertFalse(value.contains("/")); XCTAssertTrue(value.contains("Café"))
    }
}

