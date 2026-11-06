import Foundation

private actor FanFictionAnalysisCache {
    private var values: [String: FanFictionAnalysis] = [:]
    func value(for id: String) -> FanFictionAnalysis? { values[id] }
    func store(_ value: FanFictionAnalysis, for id: String) { values[id] = value }
}

final class FanFictionClient: AO3Providing, @unchecked Sendable {
    private let transport: HTTPTransport
    private let scheduler: AO3RequestScheduler
    private let parser: FanFictionHTMLParser
    private let cache = FanFictionAnalysisCache()
    private let userAgent = "ArchiveBind/0.2 (unofficial personal-use app; https://github.com/shasan731/ao3-downloader)"

    init(transport: HTTPTransport = URLSessionTransport(), scheduler: AO3RequestScheduler,
         parser: FanFictionHTMLParser = .init()) {
        self.transport = transport
        self.scheduler = scheduler
        self.parser = parser
    }

    func analyze(_ link: AO3Link) async throws -> Work {
        guard link.kind == .work, link.canonicalURL.host?.lowercased() == "www.fanfiction.net" else {
            throw AO3Error.unsupportedPath
        }
        let html = try await fetch(link.canonicalURL, storyID: link.id, chapter: 1)
        let analysis = try parser.parseAnalysis(html, link: link)
        await cache.store(analysis, for: link.id)
        return analysis.work
    }

    func analyzeSeries(_ link: AO3Link) async throws -> Series { throw AO3Error.unsupportedPath }

    func download(_ work: Work, format: DownloadFormat) async throws -> URL {
        try await download(work, format: format, progress: { _ in })
    }

    func download(_ work: Work, format: DownloadFormat,
                  progress: @escaping @Sendable (WorkDownloadProgress) async -> Void) async throws -> URL {
        guard work.sourceSite == .fanFictionNet else { throw AO3Error.unsupportedHost }
        let link = try FanFictionURLParser().parse(work.sourceURL.absoluteString)
        var analysis = await cache.value(for: link.id)
        if analysis == nil {
            let html = try await fetch(link.canonicalURL, storyID: link.id, chapter: 1)
            let parsed = try parser.parseAnalysis(html, link: link)
            await cache.store(parsed, for: link.id)
            analysis = parsed
        }
        guard let analysis else { throw AO3Error.siteLayoutChanged("FanFiction.net analysis was not retained") }
        let total = max(1, work.chapterCountPublished ?? analysis.chapterTitles.count)
        let titles = (1...total).map { index in
            analysis.chapterTitles.indices.contains(index - 1) ? analysis.chapterTitles[index - 1] : "Chapter \(index)"
        }
        var chapters: [FanFictionChapter] = []
        var transferredBytes = 0
        for number in 1...total {
            try Task.checkCancellation()
            let title = titles[number - 1]
            await progress(.init(completedChapters: number - 1, totalChapters: total, currentChapterTitle: title))
            let chapter: FanFictionChapter
            if number == 1 {
                chapter = analysis.firstChapter
            } else {
                let url = URL(string: "https://www.fanfiction.net/s/\(link.id)/\(number)")!
                let html = try await fetch(url, storyID: link.id, chapter: number)
                transferredBytes += html.utf8.count
                guard transferredBytes <= 200_000_000 else {
                    throw AO3Error.invalidDownload("the story exceeded the 200 MB safety limit")
                }
                chapter = try parser.parseChapter(html, storyID: link.id, number: number, title: title)
            }
            chapters.append(chapter)
            await progress(.init(completedChapters: number, totalChapters: total, currentChapterTitle: title))
        }
        await progress(.init(completedChapters: total, totalChapters: total,
                             currentChapterTitle: work.title, stage: .assembling))
        return try await FanFictionBookBuilder().build(work: work, chapters: chapters, format: format)
    }

    private func fetch(_ url: URL, storyID: String, chapter: Int) async throws -> String {
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await scheduler.perform { [transport, userAgent] in
                var request = URLRequest(url: url)
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
                return try await transport.data(for: request)
            }
        } catch { throw mappedTransportError(error) }
        try await classify(response, body: data)
        guard let finalURL = response.url, isAllowedStoryPage(finalURL, storyID: storyID, chapter: chapter) else {
            throw AO3Error.unsafeRedirect
        }
        guard data.count <= 12_000_000, let html = String(data: data, encoding: .utf8) else {
            throw AO3Error.siteLayoutChanged("invalid or oversized FanFiction.net HTML")
        }
        return html
    }

    private func classify(_ response: HTTPURLResponse, body: Data) async throws {
        guard let responseURL = response.url, isApproved(responseURL) else { throw AO3Error.unsafeRedirect }
        let sample = String(data: body.prefix(200_000), encoding: .utf8)?.lowercased() ?? ""
        let isChallenge = response.value(forHTTPHeaderField: "cf-mitigated") != nil
            || sample.contains("just a moment") || sample.contains("cf-challenge")
        if isChallenge { throw AO3Error.challengedSite("FanFiction.net") }
        let now = Date()
        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw AO3Error.accessRequired
        case 404, 410: throw AO3Error.unavailable
        case 429:
            let until = retryAfterDate(response.value(forHTTPHeaderField: "Retry-After"), now: now)
                ?? now.addingTimeInterval(15 * 60)
            await scheduler.applyCooldown(until: until)
            throw AO3Error.throttled(until)
        case 502, 503, 504: throw AO3Error.temporaryFailure(response.statusCode)
        default: throw AO3Error.temporaryFailure(response.statusCode)
        }
    }

    private func retryAfterDate(_ value: String?, now: Date) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let maximum = now.addingTimeInterval(24 * 60 * 60)
        if let seconds = TimeInterval(value), seconds >= 0 { return min(maximum, now.addingTimeInterval(seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value).map { min(maximum, max(now, $0)) }
    }

    private func mappedTransportError(_ error: Error) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        guard let error = error as? URLError else { return error }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed: return AO3Error.networkUnavailable
        case .timedOut: return AO3Error.networkTimedOut
        case .cancelled: return CancellationError()
        default: return AO3Error.temporaryFailure(error.errorCode)
        }
    }

    private func isApproved(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host?.lowercased() == "www.fanfiction.net"
            && components.user == nil && components.password == nil && components.port == nil
            && components.fragment == nil
    }

    private func isAllowedStoryPage(_ url: URL, storyID: String, chapter: Int) -> Bool {
        guard isApproved(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.isEmpty ?? true else { return false }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return (parts.count == 3 || parts.count == 4) && parts[0] == "s" && parts[1] == storyID
            && parts[2] == String(chapter)
    }
}
