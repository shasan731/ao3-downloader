import Foundation

enum AO3Error: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case unsupportedHost
    case unsupportedPath
    case adultConsentRequired
    case accessRequired
    case unavailable
    case challenged
    case challengedSite(String)
    case throttled(Date?)
    case networkUnavailable
    case networkTimedOut
    case temporaryFailure(Int)
    case siteLayoutChanged(String)
    case formatUnavailable(DownloadFormat)
    case invalidDownload(String)
    case unsafeRedirect
    case storage(String)
    case seriesTooLarge(Int)
    case noSeriesWorksSelected
    case combinedFormatUnsupported(DownloadFormat)
    case mergeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL(let reason): return "That URL is not valid: \(reason)."
        case .unsupportedHost: return "Use an HTTPS story URL from archiveofourown.org or www.fanfiction.net."
        case .unsupportedPath: return "Paste an AO3 work, chapter, or series URL, or a FanFiction.net story URL."
        case .adultConsentRequired: return "AO3 requires confirmation before showing this public Mature/Explicit work. Enable ‘Allow public Mature/Explicit works’ and retry."
        case .accessRequired: return "This story requires browser access. ArchiveBind does not collect site passwords, cookies, or browser sessions."
        case .unavailable: return "This story is unavailable, missing, or has been removed."
        case .challenged: return "AO3 returned an anti-bot or verification page. Open the source in your browser; the app will not bypass it."
        case .challengedSite(let site): return "\(site) returned a browser verification page. ArchiveBind will not bypass it; try again later or open the source in your browser."
        case .throttled(let date):
            return date.map { "The source site asked clients to retry later. Downloads are paused until \($0.formatted())." }
                ?? "The source site asked clients to retry later. Downloads are paused."
        case .networkUnavailable: return "The network is unavailable. Check your connection; verified downloads are safe and can be retried."
        case .networkTimedOut: return "The request timed out. The source site may be busy or the connection may be unstable; please retry."
        case .temporaryFailure: return "The source site is temporarily unavailable. Please retry later."
        case .siteLayoutChanged(let detail): return "The source page layout could not be recognized (\(detail))."
        case .formatUnavailable(let format): return "The source does not offer \(format.rawValue) for this work."
        case .invalidDownload(let detail): return "The downloaded file could not be verified: \(detail)."
        case .unsafeRedirect: return "The source redirected to an unapproved host or story, so the request was stopped."
        case .storage(let detail): return "The file could not be saved: \(detail)."
        case .seriesTooLarge(let pages): return "The series exceeded the safe pagination limit of \(pages) pages. It was not silently truncated."
        case .noSeriesWorksSelected: return "Select at least one accessible work in the series."
        case .combinedFormatUnsupported(let format): return "Combined series output is not supported for \(format.rawValue). Choose EPUB, PDF, or separate files."
        case .mergeFailed(let detail): return "The combined book could not be created: \(detail). Verified individual files were retained."
        case .cancelled: return "The operation was cancelled."
        }
    }
}

