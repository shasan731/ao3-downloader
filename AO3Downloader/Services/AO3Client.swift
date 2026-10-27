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
    func analyzeSeries(_ link: AO3Link, progress: @escaping @Sendable (SeriesAnalysisProgress) async -> Void) async throws -> Series
    func download(_ work: Work, format: DownloadFormat) async throws -> URL
}

extension AO3Providing {
    func analyzeSeries(_ link: AO3Link, progress: @escaping @Sendable (SeriesAnalysisProgress) async -> Void) async throws -> Series {
        let series = try await analyzeSeries(link)
        await progress(.init(pagesCompleted: 1, worksDiscovered: series.orderedWorks.count))
        return series
    }
}

final class AO3Client: AO3Providing, @unchecked Sendable {
    private let transport: HTTPTransport
    private let scheduler: AO3RequestScheduler
    private let parser: AO3HTMLParser
    private let allowsAdultContent: @Sendable () -> Bool
    private let userAgent = "ArchiveBind/0.1 (unofficial personal-use app; https://github.com/shasan731/ao3-downloader)"

    init(transport: HTTPTransport = URLSessionTransport(), scheduler: AO3RequestScheduler,
         parser: AO3HTMLParser = .init(),
         allowsAdultContent: @escaping @Sendable () -> Bool = {
             UserDefaults.standard.bool(forKey: "allowAdultContent")
         }) {
        self.transport = transport
        self.scheduler = scheduler
        self.parser = parser
        self.allowsAdultContent = allowsAdultContent
    }

    func analyze(_ link: AO3Link) async throws -> Work {
        guard link.kind == .work else { throw AO3Error.unsupportedPath }
        let requestURL = workRequestURL(for: link)
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await scheduler.perform { [transport, userAgent] in
                var request = URLRequest(url: requestURL); request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                return try await transport.data(for: request)
            }
        } catch { throw mappedTransportError(error) }
        try await classify(response, body: data)
        guard let responseURL = response.url, isAllowedWorkPage(responseURL, workID: link.id) else {
            throw AO3Error.unsafeRedirect
        }
        guard data.count <= 8_000_000, let html = String(data: data, encoding: .utf8) else {
            throw AO3Error.siteLayoutChanged("invalid or oversized HTML")
        }
        return try parser.parseWork(html, link: link)
    }

    func analyzeSeries(_ link: AO3Link) async throws -> Series {
        try await analyzeSeries(link, progress: { _ in })
    }

    func analyzeSeries(_ link: AO3Link, progress: @escaping @Sendable (SeriesAnalysisProgress) async -> Void) async throws -> Series {
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
            let (data, response): (Data, HTTPURLResponse)
            do {
                (data, response) = try await scheduler.perform { [transport, userAgent] in
                    var request = URLRequest(url: current)
                    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                    return try await transport.data(for: request)
                }
            } catch { throw mappedTransportError(error) }
            try await classify(response, body: data)
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
            await progress(.init(pagesCompleted: visitedPages.count, worksDiscovered: combined?.orderedWorks.count ?? 0))
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
        let (temporaryURL, response): (URL, HTTPURLResponse)
        do {
            (temporaryURL, response) = try await scheduler.perform { [transport, userAgent] in
                var request = URLRequest(url: url); request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                return try await transport.download(for: request)
            }
        } catch { throw mappedTransportError(error) }
        try await classify(response, body: nil)
        try DownloadValidator().validate(file: temporaryURL, format: format)
        return temporaryURL
    }

    private func classify(_ response: HTTPURLResponse, body: Data?) async throws {
        guard let responseURL = response.url, isApproved(responseURL) else { throw AO3Error.unsafeRedirect }
        let now = Date()
        let requestedRetry = retryAfterDate(response.value(forHTTPHeaderField: "Retry-After"), now: now)
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw AO3Error.accessRequired
        case 404, 410: throw AO3Error.unavailable
        case 429:
            let until = requestedRetry ?? now.addingTimeInterval(15 * 60)
            await scheduler.applyCooldown(until: until)
            throw AO3Error.throttled(until)
        case 503 where requestedRetry != nil:
            await scheduler.applyCooldown(until: requestedRetry!)
            throw AO3Error.throttled(requestedRetry)
        case 502, 503, 504: throw AO3Error.temporaryFailure(response.statusCode)
        default: throw AO3Error.temporaryFailure(response.statusCode)
        }
        if let body, let text = String(data: body.prefix(200_000), encoding: .utf8)?.lowercased(),
           text.contains("retry later") {
            let until = now.addingTimeInterval(15 * 60)
            await scheduler.applyCooldown(until: until)
            throw AO3Error.throttled(until)
        }
    }

    private func retryAfterDate(_ value: String?, now: Date) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let maximum = now.addingTimeInterval(24 * 60 * 60)
        if let seconds = TimeInterval(value), seconds >= 0 {
            return min(maximum, now.addingTimeInterval(seconds))
        }
        let formats = ["EEE',' dd MMM yyyy HH':'mm':'ss z", "EEEE',' dd-MMM-yy HH':'mm':'ss z", "EEE MMM d HH':'mm':'ss yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return min(maximum, max(now, date)) }
        }
        return nil
    }

    private func mappedTransportError(_ error: Error) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        guard let error = error as? URLError else { return error }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
            return AO3Error.networkUnavailable
        case .timedOut: return AO3Error.networkTimedOut
        case .cancelled: return CancellationError()
        default: return AO3Error.temporaryFailure(error.errorCode)
        }
    }

    private func isApproved(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https"
            && ["archiveofourown.org", "download.archiveofourown.org"].contains(components.host?.lowercased() ?? "")
            && components.user == nil && components.password == nil && components.port == nil
            && components.fragment == nil
    }

    private func workRequestURL(for link: AO3Link) -> URL {
        guard allowsAdultContent(), var components = URLComponents(url: link.canonicalURL, resolvingAgainstBaseURL: false) else {
            return link.canonicalURL
        }
        components.queryItems = [URLQueryItem(name: "view_adult", value: "true")]
        return components.url ?? link.canonicalURL
    }

    private func isAllowedWorkPage(_ url: URL, workID: String) -> Bool {
        guard isApproved(url), url.host?.lowercased() == "archiveofourown.org",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let isCanonicalWork = parts == ["works", workID]
        let isChapterOfWork = parts.count == 4 && parts[0] == "works" && parts[1] == workID
            && parts[2] == "chapters" && !parts[3].isEmpty && parts[3].allSatisfy(\.isNumber)
        guard isCanonicalWork || isChapterOfWork else { return false }
        return (components.queryItems ?? []).allSatisfy { item in
            item.name == "view_adult" && item.value == "true"
                || item.name == "view_full_work" && item.value == "true"
        }
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

