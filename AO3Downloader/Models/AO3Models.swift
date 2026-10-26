import Foundation

enum AO3LinkKind: String, Codable, Sendable { case work, series }

struct AO3Link: Codable, Hashable, Sendable {
    let kind: AO3LinkKind
    let id: String
    let canonicalURL: URL
}

enum AccessState: String, Codable, Sendable { case publicAccess, restricted, unavailable }
enum WorkCompletion: String, Codable, Sendable { case complete, workInProgress, unknown }
enum DownloadFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case epub = "EPUB", pdf = "PDF", html = "HTML"
    var id: String { rawValue }
    var fileExtension: String { rawValue.lowercased() }
}

struct Work: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var creators: [String]
    let sourceURL: URL
    var summary: String?
    var language: String?
    var fandoms: [String]
    var rating: String?
    var warnings: [String]
    var tags: [String]
    var completion: WorkCompletion
    var chapterCountPublished: Int?
    var chapterCountExpected: Int?
    var wordCount: Int?
    var downloadableFormats: [DownloadFormat: URL]
    var accessState: AccessState
}

struct SeriesEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String { workID }
    let workID: String
    let position: Int
    var title: String
    let sourceURL: URL
    var accessState: AccessState
    var selected: Bool
}

struct Series: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var creators: [String]
    var description: String?
    let sourceURL: URL
    var orderedWorks: [SeriesEntry]
    var isCompletePagination: Bool
}

enum DownloadJobState: String, Codable, Sendable {
    case queued, analyzing, ready, downloading, backingOff, paused, assembling
    case verifying, completed, completedPartial, failed, cancelled
}

struct DownloadJob: Identifiable, Codable, Sendable {
    let id: UUID
    var source: AO3Link
    var format: DownloadFormat
    var destination: URL
    var state: DownloadJobState
    var outputFiles: [URL]
    var errorMessage: String?
    let createdAt: Date
    var lastUpdatedAt: Date
}

