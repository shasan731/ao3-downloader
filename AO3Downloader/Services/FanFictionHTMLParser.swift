import Foundation
import SwiftSoup

struct FanFictionChapter: Sendable {
    let number: Int
    let title: String
    let bodyHTML: String
}

struct FanFictionAnalysis: Sendable {
    let work: Work
    let firstChapter: FanFictionChapter
    let chapterTitles: [String]
}

struct FanFictionHTMLParser: Sendable {
    func parseAnalysis(_ html: String, link: AO3Link) throws -> FanFictionAnalysis {
        let document = try SwiftSoup.parse(html, link.canonicalURL.absoluteString)
        try rejectErrorPage(document)
        guard let profile = try document.select("#profile_top").first(),
              let title = try profile.select("b.xcontrast_txt, b").first()?.text()
                .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw AO3Error.siteLayoutChanged("FanFiction.net story title is missing")
        }
        let creators = try profile.select("a[href^=/u/]").array()
            .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let summary = try profile.select("div.xcontrast_txt").first()?.text()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = try profile.select("span.xgray.xcontrast_txt, span.xgray").first()?.text() ?? ""
        let titles = try chapterTitles(in: document)
        let declaredChapters = integer(matching: #"Chapters:\s*([0-9,]+)"#, in: metadata)
        let chapterCount = max(1, declaredChapters ?? titles.count)
        let completion: WorkCompletion = metadata.range(of: #"Status:\s*Complete"#, options: .regularExpression) == nil
            ? .workInProgress : .complete
        let formats = Dictionary(uniqueKeysWithValues: DownloadFormat.allCases.map { ($0, link.canonicalURL) })
        let fandoms = try document.select("#pre_story_links a").array()
            .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare("FanFiction") != .orderedSame }
        let work = Work(id: link.id, title: title, creators: Array(creators.prefix(1)),
                        sourceURL: link.canonicalURL, summary: summary, language: language(in: metadata),
                        fandoms: fandoms, rating: capture(#"Rated:\s*Fiction\s+([^\s-]+)"#, in: metadata),
                        warnings: [], tags: [], completion: completion,
                        chapterCountPublished: chapterCount,
                        chapterCountExpected: completion == .complete ? chapterCount : nil,
                        wordCount: integer(matching: #"Words:\s*([0-9,]+)"#, in: metadata),
                        downloadableFormats: formats, accessState: .publicAccess)
        let firstTitle = titles.first ?? (chapterCount == 1 ? title : "Chapter 1")
        return .init(work: work,
                     firstChapter: try parseChapter(document, number: 1, title: firstTitle),
                     chapterTitles: normalizedTitles(titles, count: chapterCount))
    }

    func parseChapter(_ html: String, storyID: String, number: Int, title: String) throws -> FanFictionChapter {
        let base = URL(string: "https://www.fanfiction.net/s/\(storyID)/\(number)")!
        let document = try SwiftSoup.parse(html, base.absoluteString)
        try rejectErrorPage(document)
        return try parseChapter(document, number: number, title: title)
    }

    private func parseChapter(_ document: Document, number: Int, title: String) throws -> FanFictionChapter {
        guard let story = try document.select("#storytext").first() else {
            throw AO3Error.siteLayoutChanged("FanFiction.net chapter text is missing")
        }
        let whitelist = try Whitelist.basic()
        _ = try whitelist.removeTags("a")
        _ = try whitelist.removeAttributes("blockquote", "cite")
        guard let cleaned = try SwiftSoup.clean(try story.html(), whitelist),
              !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AO3Error.siteLayoutChanged("FanFiction.net chapter is empty")
        }
        let fragment = try SwiftSoup.parseBodyFragment(cleaned)
        fragment.outputSettings().syntax(syntax: .xml)
        let xhtml = try fragment.body()?.html() ?? cleaned
        return .init(number: number, title: title.isEmpty ? "Chapter \(number)" : title, bodyHTML: xhtml)
    }

    private func chapterTitles(in document: Document) throws -> [String] {
        try document.select("#chap_select option, select[name=chapter] option").array().compactMap { option in
            let value = try option.text().trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    private func normalizedTitles(_ titles: [String], count: Int) -> [String] {
        (1...count).map { index in
            guard titles.indices.contains(index - 1) else { return "Chapter \(index)" }
            let raw = titles[index - 1]
            let stripped = raw.replacingOccurrences(of: #"^\s*[0-9]+[\.:\-]?\s*"#, with: "", options: .regularExpression)
            return stripped.isEmpty ? "Chapter \(index)" : stripped
        }
    }

    private func language(in metadata: String) -> String? {
        let pattern = #"Rated:\s*Fiction\s+[^-]+-\s*([^-]+?)\s*-"#
        return capture(pattern, in: metadata)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func integer(matching pattern: String, in text: String) -> Int? {
        capture(pattern, in: text).flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
    }

    private func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func rejectErrorPage(_ document: Document) throws {
        let title = (try? document.title().lowercased()) ?? ""
        if title.contains("just a moment") || (try? document.select("#challenge-running, .cf-challenge").first()) != nil {
            throw AO3Error.challengedSite("FanFiction.net")
        }
        let pageText = (try? document.body()?.text().lowercased()) ?? ""
        if pageText.contains("story not found") || pageText.contains("story is unavailable for reading")
            || pageText.contains("chapter not found") {
            throw AO3Error.unavailable
        }
    }
}
