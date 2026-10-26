import XCTest
@testable import AO3Downloader

final class PersistenceTests: XCTestCase {
    func testRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadPersistence(fileURL: root.appendingPathComponent("jobs.json"))
        let link = try AO3URLParser().parse("https://archiveofourown.org/works/1")
        let job = DownloadJob(id: UUID(), source: link, format: .epub, destination: root, state: .queued, outputFiles: [], createdAt: .now, lastUpdatedAt: .now)
        try await store.save([job]); let loaded = try await store.load()
        XCTAssertEqual(loaded.first?.id, job.id)
    }
}

