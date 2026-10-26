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
    func analyzeSeries(_ link: AO3Link) async throws -> Series
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

    func analyzeSeries(_ link: AO3Link) async throws -> Series {
        guard link.kind == .series else { throw AO3Error.unsupportedPath }
        let pageLimit = 50
        var pageURL: URL? = link.canonicalURL
        var visitedPages = Set<URL>()
        var seenWorks = Set<String>()
        var combined: Series?
        var position = 0

        for _ in 0..<pageLimit {
            guard let current = pageURL else { break }
            guard isAllowedSeriesPage(current, seriesID: link.id), visitedPages.insert(current).inserted else {
                throw AO3Error.siteLayoutChanged("repeated or unsafe series page")
            }
            let (data, response) = try await scheduler.perform { [transport, userAgent] in
                var request = URLRequest(url: current)
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                return try await transport.data(for: request)
            }
            try classify(response, body: data)
            guard data.count <= 8_000_000, let html = String(data: data, encoding: .utf8) else {
                throw AO3Error.siteLayoutChanged("invalid or oversized series HTML")
            }
            let (page, next) = try parser.parseSeriesPage(html, link: link, pageURL: current)
            if combined == nil { combined = page; combined?.orderedWorks = [] }
            for var entry in page.orderedWorks {
                let identity = entry.workID.hasPrefix("unavailable-") ? "unavailable-page-\(visitedPages.count)-\(entry.position)" : entry.workID
                guard seenWorks.insert(identity).inserted else { continue }
                position += 1
                entry = .init(workID: identity, position: position, title: entry.title,
                              sourceURL: entry.sourceURL, accessState: entry.accessState, selected: entry.selected)
                combined?.orderedWorks.append(entry)
            }
            pageURL = next
        }
        if pageURL != nil { throw AO3Error.seriesTooLarge(pageLimit) }
        guard var result = combined, !result.orderedWorks.isEmpty else {
            throw AO3Error.siteLayoutChanged("no series works found")
        }
        result.isCompletePagination = true
        return result
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

    private func isAllowedSeriesPage(_ url: URL, seriesID: String) -> Bool {
        guard url.scheme == "https", url.host?.lowercased() == "archiveofourown.org",
              url.path == "/series/\(seriesID)", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.fragment == nil else { return false }
        return (components.queryItems ?? []).allSatisfy { item in
            if item.name == "page" { return item.value?.allSatisfy(\.isNumber) == true }
            return item.name == "language_id"
        }
    }
}

