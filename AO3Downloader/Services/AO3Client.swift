import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AO3Error.temporaryFailure(0) }
        return (data, http)
    }
    func download(for request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let (url, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw AO3Error.temporaryFailure(0) }
        return (url, http)
    }
}

protocol AO3Providing: Sendable {
    func analyze(_ link: AO3Link) async throws -> Work
    func download(_ work: Work, format: DownloadFormat) async throws -> URL
}

final class AO3Client: AO3Providing, @unchecked Sendable {
    private let transport: HTTPTransport
    private let scheduler: AO3RequestScheduler
    private let parser: AO3HTMLParser
    private let userAgent = "AO3Downloader/0.1 (unofficial personal-use app; https://github.com/shasan731/ao3-downloader)"

    init(transport: HTTPTransport = URLSessionTransport(), scheduler: AO3RequestScheduler, parser: AO3HTMLParser = .init()) {
        self.transport = transport; self.scheduler = scheduler; self.parser = parser
    }

    func analyze(_ link: AO3Link) async throws -> Work {
        guard link.kind == .work else { throw AO3Error.unsupportedPath }
        let (data, response) = try await scheduler.perform { [transport, userAgent] in
            var request = URLRequest(url: link.canonicalURL); request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            return try await transport.data(for: request)
        }
        try classify(response, body: data)
        guard data.count <= 8_000_000, let html = String(data: data, encoding: .utf8) else {
            throw AO3Error.siteLayoutChanged("invalid or oversized HTML")
        }
        return try parser.parseWork(html, link: link)
    }

    func download(_ work: Work, format: DownloadFormat) async throws -> URL {
        guard let url = work.downloadableFormats[format] else { throw AO3Error.formatUnavailable(format) }
        guard isApproved(url) else { throw AO3Error.unsafeRedirect }
        let (temporaryURL, response) = try await scheduler.perform { [transport, userAgent] in
            var request = URLRequest(url: url); request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            return try await transport.download(for: request)
        }
        try classify(response, body: nil)
        try DownloadValidator().validate(file: temporaryURL, format: format)
        return temporaryURL
    }

    private func classify(_ response: HTTPURLResponse, body: Data?) throws {
        guard let responseURL = response.url, isApproved(responseURL) else { throw AO3Error.unsafeRedirect }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw AO3Error.accessRequired
        case 404, 410: throw AO3Error.unavailable
        case 429: throw AO3Error.throttled(nil)
        case 502, 503, 504: throw AO3Error.temporaryFailure(response.statusCode)
        default: throw AO3Error.temporaryFailure(response.statusCode)
        }
        if let body, let text = String(data: body.prefix(200_000), encoding: .utf8)?.lowercased(),
           text.contains("retry later") { throw AO3Error.throttled(nil) }
    }

    private func isApproved(_ url: URL) -> Bool {
        url.scheme == "https" && ["archiveofourown.org", "download.archiveofourown.org"].contains(url.host?.lowercased() ?? "")
    }
}

