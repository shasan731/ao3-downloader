import Foundation
import XCTest
@testable import AO3Downloader

final class SeriesParsingTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")
                                ?? bundle.url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesOrderPaginationAndUnavailableEntry() throws {
        let link = try AO3URLParser().parse("https://archiveofourown.org/series/99")
        let parser = AO3HTMLParser()
        let (first, next) = try parser.parseSeriesPage(try fixture("series-page-1"), link: link)
        XCTAssertEqual(first.title, "Synthetic Saga")
        XCTAssertEqual(first.orderedWorks.map(\.workID), ["101", "102"])
        XCTAssertEqual(next?.absoluteString, "https://archiveofourown.org/series/99?page=2")

        let (second, noNext) = try parser.parseSeriesPage(try fixture("series-page-2"), link: link, pageURL: try XCTUnwrap(next))
        XCTAssertEqual(second.orderedWorks.first?.workID, "103")
        XCTAssertEqual(second.orderedWorks.last?.accessState, .unavailable)
        XCTAssertFalse(second.orderedWorks.last?.selected ?? true)
        XCTAssertNil(noNext)
    }
}

private actor SeriesTransport: HTTPTransport {
    let first: Data
    let second: Data
    private(set) var requests: [URL] = []

    init(first: Data, second: Data) { self.first = first; self.second = second }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try XCTUnwrap(request.url)
        requests.append(url)
        let data = url.query?.contains("page=2") == true ? second : first
        return (data, try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])))
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        throw AO3Error.invalidDownload("unexpected download in series analysis test")
    }
}

extension SeriesParsingTests {
    func testClientTraversesAllSeriesPagesInOrder() async throws {
        let transport = SeriesTransport(first: Data(try fixture("series-page-1").utf8),
                                        second: Data(try fixture("series-page-2").utf8))
        let scheduler = AO3RequestScheduler(minimumInterval: 10, sleeper: ImmediateSeriesSleeper(), jitter: { 0 })
        let client = AO3Client(transport: transport, scheduler: scheduler)
        let link = try AO3URLParser().parse("https://archiveofourown.org/series/99")
        let series = try await client.analyzeSeries(link)
        XCTAssertEqual(series.orderedWorks.map(\.workID), ["101", "102", "103", "unavailable-page-2-2"])
        XCTAssertEqual(series.orderedWorks.map(\.position), [1, 2, 3, 4])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }
}

private struct ImmediateSeriesSleeper: Sleeping {
    func sleep(for duration: Duration) async throws {}
}
