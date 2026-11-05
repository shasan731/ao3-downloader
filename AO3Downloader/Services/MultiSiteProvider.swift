import Foundation

struct MultiSiteProvider: AO3Providing {
    let ao3: AO3Providing
    let fanFiction: AO3Providing

    func analyze(_ link: AO3Link) async throws -> Work {
        switch site(for: link.canonicalURL) {
        case .ao3: return try await ao3.analyze(link)
        case .fanFictionNet: return try await fanFiction.analyze(link)
        }
    }

    func analyzeSeries(_ link: AO3Link) async throws -> Series {
        guard site(for: link.canonicalURL) == .ao3 else { throw AO3Error.unsupportedPath }
        return try await ao3.analyzeSeries(link)
    }

    func analyzeSeries(_ link: AO3Link,
                       progress: @escaping @Sendable (SeriesAnalysisProgress) async -> Void) async throws -> Series {
        guard site(for: link.canonicalURL) == .ao3 else { throw AO3Error.unsupportedPath }
        return try await ao3.analyzeSeries(link, progress: progress)
    }

    func download(_ work: Work, format: DownloadFormat) async throws -> URL {
        try await provider(for: work).download(work, format: format)
    }

    func download(_ work: Work, format: DownloadFormat,
                  progress: @escaping @Sendable (WorkDownloadProgress) async -> Void) async throws -> URL {
        try await provider(for: work).download(work, format: format, progress: progress)
    }

    private func provider(for work: Work) -> AO3Providing {
        work.sourceSite == .fanFictionNet ? fanFiction : ao3
    }

    private func site(for url: URL) -> SupportedSite {
        url.host?.lowercased() == "www.fanfiction.net" ? .fanFictionNet : .ao3
    }
}
