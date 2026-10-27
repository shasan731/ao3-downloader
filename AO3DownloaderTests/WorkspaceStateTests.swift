import XCTest
@testable import AO3Downloader

private struct WorkspaceTestProvider: AO3Providing {
    func analyze(_ link: AO3Link) async throws -> Work { throw AO3Error.unsupportedPath }
    func analyzeSeries(_ link: AO3Link) async throws -> Series { throw AO3Error.unsupportedPath }
    func download(_ work: Work, format: DownloadFormat) async throws -> URL { throw AO3Error.unsupportedPath }
}

@MainActor
final class WorkspaceStateTests: XCTestCase {
    func testNewDownloadClearsIdleLibraryContextWithoutDeletingHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(fileURL: root.appendingPathComponent("library.json"))
        let record = makeRecord(destination: root)
        try await store.save([record])

        let provider = WorkspaceTestProvider()
        let model = NewDownloadViewModel(dependencies: .init(
            provider: provider,
            manager: DownloadManager(provider: provider),
            persistence: DownloadPersistence(),
            libraryStore: store
        ))
        for _ in 0..<50 where model.historyRecords.isEmpty { await Task.yield() }
        model.historyRecords = [record]

        model.openHistoryRecord(record)
        XCTAssertEqual(model.input, record.sourceURL.absoluteString)
        XCTAssertNotNil(model.series)

        model.prepareNewDownloadWorkspace()

        XCTAssertEqual(model.input, "")
        XCTAssertNil(model.series)
        XCTAssertNil(model.work)
        XCTAssertNil(model.activeOperation)
        XCTAssertEqual(model.status, "Paste a public AO3 work or series URL to begin.")
        XCTAssertEqual(model.historyRecords.map(\.id), [record.id])
        XCTAssertFalse(model.hasLoadedLibraryRecord)
    }

    func testNewDownloadDoesNotClearBusyLibraryOperation() {
        let record = makeRecord(destination: FileManager.default.temporaryDirectory)
        let provider = WorkspaceTestProvider()
        let model = NewDownloadViewModel(dependencies: .init(
            provider: provider,
            manager: DownloadManager(provider: provider),
            persistence: DownloadPersistence(),
            libraryStore: LibraryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        ))
        model.openHistoryRecord(record)
        model.isBusy = true

        model.prepareNewDownloadWorkspace()

        XCTAssertEqual(model.input, record.sourceURL.absoluteString)
        XCTAssertNotNil(model.series)
    }

    private func makeRecord(destination: URL) -> LibraryRecord {
        let source = URL(string: "https://archiveofourown.org/series/123")!
        let series = Series(id: "123", title: "Saved Series", creators: ["Writer"], description: nil,
                            sourceURL: source, orderedWorks: [
                                .init(workID: "456", position: 1, title: "First Part",
                                      sourceURL: URL(string: "https://archiveofourown.org/works/456")!,
                                      accessState: .publicAccess, selected: true)
                            ], isCompletePagination: true)
        return LibraryRecord(id: UUID(), kind: .series, sourceURL: source, series: series, singleWork: nil,
                             format: .epub, outputMode: .combined, destinationURL: destination,
                             destinationBookmark: nil,
                             metadata: .init(title: series.title, authors: series.creators, language: "en", coverImageURL: nil),
                             downloadedParts: [], singleFileURL: nil, combinedFiles: [], failures: [],
                             createdAt: .now, updatedAt: .now)
    }
}
