import Foundation
import XCTest
@testable import AO3Downloader

private actor WorkAnalysisTransport: HTTPTransport {
    let body: Data
    let responseURL: URL
    private(set) var requests: [URL] = []

    init(body: Data, responseURL: URL) {
        self.body = body
        self.responseURL = responseURL
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(try XCTUnwrap(request.url))
        let response = try XCTUnwrap(HTTPURLResponse(url: responseURL, statusCode: 200,
                                                    httpVersion: nil, headerFields: ["Content-Type": "text/html"]))
        return (body, response)
    }

    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        throw AO3Error.invalidDownload("unexpected download in work analysis test")
    }
}

final class WorkAnalysisTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")
                                ?? bundle.url(forResource: name, withExtension: "html"))
        return try Data(contentsOf: url)
    }

    func testAdultConsentSupportsSameWorkRedirectToFirstChapter() async throws {
        let finalURL = try XCTUnwrap(URL(string: "https://archiveofourown.org/works/123/chapters/456"))
        let transport = WorkAnalysisTransport(body: try fixture("work"), responseURL: finalURL)
        let scheduler = AO3RequestScheduler(minimumInterval: 10)
        let client = AO3Client(transport: transport, scheduler: scheduler, allowsAdultContent: { true })
        let link = try AO3URLParser().parse("https://archiveofourown.org/works/123")

        let work = try await client.analyze(link)

        XCTAssertEqual(work.id, "123")
        XCTAssertEqual(work.chapterCountPublished, 3)
        XCTAssertEqual(work.chapterCountExpected, 3)
        XCTAssertNotNil(work.downloadableFormats[.epub])
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "view_adult", value: "true")])
    }

    func testAdultWarningHasSpecificErrorWhenConsentIsDisabled() async throws {
        let canonicalURL = try XCTUnwrap(URL(string: "https://archiveofourown.org/works/123"))
        let transport = WorkAnalysisTransport(body: try fixture("adult-warning"), responseURL: canonicalURL)
        let scheduler = AO3RequestScheduler(minimumInterval: 10)
        let client = AO3Client(transport: transport, scheduler: scheduler, allowsAdultContent: { false })
        let link = try AO3URLParser().parse(canonicalURL.absoluteString)

        do {
            _ = try await client.analyze(link)
            XCTFail("Adult warning unexpectedly parsed as a work")
        } catch {
            XCTAssertEqual(error as? AO3Error, .adultConsentRequired)
        }
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertNil(URLComponents(url: request, resolvingAgainstBaseURL: false)?.query)
    }

    func testRejectsRedirectToDifferentWorkEvenOnExactAO3Host() async throws {
        let wrongWork = try XCTUnwrap(URL(string: "https://archiveofourown.org/works/999/chapters/456"))
        let transport = WorkAnalysisTransport(body: try fixture("work"), responseURL: wrongWork)
        let scheduler = AO3RequestScheduler(minimumInterval: 10)
        let client = AO3Client(transport: transport, scheduler: scheduler, allowsAdultContent: { true })
        let link = try AO3URLParser().parse("https://archiveofourown.org/works/123")

        do {
            _ = try await client.analyze(link)
            XCTFail("Cross-work redirect unexpectedly passed validation")
        } catch {
            XCTAssertEqual(error as? AO3Error, .unsafeRedirect)
        }
    }
}
