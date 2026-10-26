import Foundation

enum AO3Error: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case unsupportedHost
    case unsupportedPath
    case accessRequired
    case unavailable
    case challenged
    case throttled(Date?)
    case temporaryFailure(Int)
    case siteLayoutChanged(String)
    case formatUnavailable(DownloadFormat)
    case invalidDownload(String)
    case unsafeRedirect
    case storage(String)
    case seriesTooLarge(Int)
    case noSeriesWorksSelected
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL(let reason): return "That URL is not valid: \(reason)."
        case .unsupportedHost: return "Use an HTTPS URL from archiveofourown.org."
        case .unsupportedPath: return "Paste an AO3 work, chapter, or series URL."
        case .accessRequired: return "This work requires access in your web browser. The app does not collect AO3 passwords or cookies."
        case .unavailable: return "This work is unavailable or has been removed."
        case .challenged: return "AO3 returned an anti-bot or verification page. Open the source in your browser; the app will not bypass it."
        case .throttled(let date):
            return date.map { "AO3 asked clients to retry later. Downloads are paused until \($0.formatted())." }
                ?? "AO3 asked clients to retry later. Downloads are paused."
        case .temporaryFailure: return "AO3 is temporarily unavailable. Please retry later."
        case .siteLayoutChanged(let detail): return "AO3's page layout could not be recognized (\(detail))."
        case .formatUnavailable(let format): return "AO3 does not offer \(format.rawValue) for this work."
        case .invalidDownload(let detail): return "The downloaded file could not be verified: \(detail)."
        case .unsafeRedirect: return "AO3 redirected to an unapproved host, so the request was stopped."
        case .storage(let detail): return "The file could not be saved: \(detail)."
        case .seriesTooLarge(let pages): return "The series exceeded the safe pagination limit of \(pages) pages. It was not silently truncated."
        case .noSeriesWorksSelected: return "Select at least one accessible work in the series."
        case .cancelled: return "The operation was cancelled."
        }
    }
}

