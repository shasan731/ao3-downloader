import XCTest
@testable import AO3Downloader

final class PersistenceTests: XCTestCase {
    func testRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadPersistence(fileURL: root.appendingPathComponent("jobs.json"))
        let link = try AO3URLParser().parse("https://archiveofourown.org/works/1")
        let job = DownloadJob(id: UUID(), source: link, format: .epub, destination: root,
                              state: .downloading, outputFiles: [], createdAt: .now, lastUpdatedAt: .now,
                              title: "Saved story", completedUnitCount: 3, totalUnitCount: 8,
                              currentUnitTitle: "Chapter 4", statusDetail: "Fetched 3 of 8 chapters")
        try await store.save([job]); let loaded = try await store.load()
        XCTAssertEqual(loaded.first?.id, job.id)
        XCTAssertEqual(loaded.first?.completedUnitCount, 3)
        XCTAssertEqual(loaded.first?.totalUnitCount, 8)
        XCTAssertEqual(loaded.first?.currentUnitTitle, "Chapter 4")
    }
}

