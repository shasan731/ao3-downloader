import Foundation
import XCTest
@testable import AO3Downloader

private actor WorkAnalysisTransport: HTTPTransport {
    let body: Data
    let responseURL: URL
    let statusCode: Int
    let headerFields: [String: String]
    let transportError: URLError?
    private(set) var requests: [URL] = []

    init(body: Data, responseURL: URL, statusCode: Int = 200,
         headerFields: [String: String] = ["Content-Type": "text/html"], transportError: URLError? = nil) {
        self.body = body
        self.responseURL = responseURL
        self.statusCode = statusCode
        self.headerFields = headerFields
        self.transportError = transportError
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(try XCTUnwrap(request.url))
        if let transportError { throw transportError }
        let response = try XCTUnwrap(HTTPURLResponse(url: responseURL, statusCode: statusCode,
                                                    httpVersion: nil, headerFields: headerFields))
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

    func testRetryAfterAppliesAndExposesPersistentCooldown() async throws {
        let canonicalURL = try XCTUnwrap(URL(string: "https://archiveofourown.org/works/123"))
        let transport = WorkAnalysisTransport(body: Data(), responseURL: canonicalURL, statusCode: 429,
                                              headerFields: ["Retry-After": "600"])
        let scheduler = AO3RequestScheduler(minimumInterval: 10)
        let client = AO3Client(transport: transport, scheduler: scheduler, allowsAdultContent: { false })
        let before = Date()

        do {
            _ = try await client.analyze(try AO3URLParser().parse(canonicalURL.absoluteString))
            XCTFail("Throttled response unexpectedly succeeded")
        } catch let error as AO3Error {
            guard case .throttled(let date) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertGreaterThan(try XCTUnwrap(date), before.addingTimeInterval(590))
        }
        let cooldown = await scheduler.cooldownDate()
        XCTAssertGreaterThan(cooldown, before.addingTimeInterval(590))
    }

    func testOfflineTransportErrorGetsActionableClassification() async throws {
        let canonicalURL = try XCTUnwrap(URL(string: "https://archiveofourown.org/works/123"))
        let transport = WorkAnalysisTransport(body: Data(), responseURL: canonicalURL,
                                              transportError: URLError(.notConnectedToInternet))
        let scheduler = AO3RequestScheduler(minimumInterval: 10)
        let client = AO3Client(transport: transport, scheduler: scheduler, allowsAdultContent: { false })

        do {
            _ = try await client.analyze(try AO3URLParser().parse(canonicalURL.absoluteString))
            XCTFail("Offline request unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? AO3Error, .networkUnavailable)
        }
    }
}
