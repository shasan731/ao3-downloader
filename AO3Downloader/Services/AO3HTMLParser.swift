import Foundation
import SwiftSoup

struct AO3HTMLParser: Sendable {
    func parseWork(_ html: String, link: AO3Link) throws -> Work {
        let document = try SwiftSoup.parse(html, link.canonicalURL.absoluteString)
        if try isAdultInterstitial(document) { throw AO3Error.adultConsentRequired }
        if try document.select("form#new_user, .restricted, #tos_agree").first() != nil { throw AO3Error.accessRequired }
        if try document.select(".challenge, #challenge-form").first() != nil { throw AO3Error.challenged }
        guard let title = try document.select(".work.meta h2.title, h2.title.heading").first()?.text(), !title.isEmpty else {
            throw AO3Error.siteLayoutChanged("missing work title")
        }
        let creators = try document.select(".work.meta h3.byline a[rel=author], h3.byline a[rel=author]").array().compactMap { try? $0.text() }
        let summary = try document.select(".summary blockquote, blockquote.userstuff.summary").first()?.text()
        let language = try value(after: "Language", in: document)
        let fandoms = try texts("dd.fandom.tags a.tag", document)
        let warnings = try texts("dd.warning.tags a.tag", document)
        let tags = try texts("dd.freeform.tags a.tag", document)
        let chaptersText = try value(after: "Chapters", in: document)
        let chapterParts = chaptersText?.split(separator: "/") ?? []
        let published = chapterParts.first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let expected = chapterParts.count > 1 ? Int(chapterParts[1].trimmingCharacters(in: .whitespaces)) : nil
        let words = try value(after: "Words", in: document).flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
        var downloads: [DownloadFormat: URL] = [:]
        for element in try document.select("li.download ul li a, ul.download li a, a[href*=\"/downloads/\"]").array() {
            let label = try element.text().uppercased()
            guard let format = DownloadFormat.allCases.first(where: { label.contains($0.rawValue) }),
                  let url = URL(string: try element.attr("href"), relativeTo: link.canonicalURL)?.absoluteURL,
                  url.scheme == "https", ["archiveofourown.org", "download.archiveofourown.org"].contains(url.host?.lowercased() ?? "") else { continue }
            downloads[format] = url
        }
        guard !downloads.isEmpty else { throw AO3Error.siteLayoutChanged("missing download menu") }
        let completion: WorkCompletion = expected == nil ? .workInProgress : (published == expected ? .complete : .workInProgress)
        return Work(id: link.id, title: title, creators: creators, sourceURL: link.canonicalURL,
                    summary: summary, language: language, fandoms: fandoms,
                    rating: try texts("dd.rating.tags a.tag", document).first, warnings: warnings, tags: tags,
                    completion: completion, chapterCountPublished: published, chapterCountExpected: expected,
                    wordCount: words, downloadableFormats: downloads, accessState: .publicAccess)
    }

    func parseSeriesPage(_ html: String, link: AO3Link, pageURL: URL? = nil) throws -> (Series, URL?) {
        let baseURL = pageURL ?? link.canonicalURL
        let document = try SwiftSoup.parse(html, baseURL.absoluteString)
        if try document.select("form#new_user, #tos_agree, .challenge, #challenge-form").first() != nil {
            throw AO3Error.accessRequired
        }
        guard let rawHeading = try document.select(".series.meta h2.heading, h2.heading").first()?.text(), !rawHeading.isEmpty else {
            throw AO3Error.siteLayoutChanged("missing series title")
        }
        let heading = rawHeading.replacingOccurrences(of: "Series: ", with: "")
        var seen = Set<String>(); var entries: [SeriesEntry] = []
        for element in try document.select("li.work.blurb, li[role=article]").array() {
            guard let anchor = try element.select("h4.heading a[href*=\"/works/\"]").first(),
                  let href = try? anchor.attr("href"),
                  let absolute = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  let parsed = try? AO3URLParser().parse(absolute.absoluteString) else {
                let position = entries.count + 1
                entries.append(.init(workID: "unavailable-\(position)", position: position,
                                     title: "Unavailable work at position \(position)", sourceURL: link.canonicalURL,
                                     accessState: .unavailable, selected: false))
                continue
            }
            guard seen.insert(parsed.id).inserted else { continue }
            let restricted = try element.select(".restricted, .private").first() != nil
            entries.append(.init(workID: parsed.id, position: entries.count + 1,
                                 title: (try? anchor.text()) ?? "Work \(parsed.id)", sourceURL: parsed.canonicalURL,
                                 accessState: restricted ? .restricted : .publicAccess, selected: !restricted))
        }
        guard !entries.isEmpty else { throw AO3Error.siteLayoutChanged("no series works found") }
        let nextHref = try document.select("ol.pagination li.next a, .pagination .next a").first()?.attr("href")
        let next = nextHref.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        let series = Series(id: link.id, title: heading, creators: [],
                            description: try document.select(".series.meta blockquote.userstuff").first()?.text(),
                            sourceURL: link.canonicalURL, orderedWorks: entries, isCompletePagination: next == nil)
        return (series, next)
    }

    private func texts(_ selector: String, _ document: Document) throws -> [String] {
        try document.select(selector).array().compactMap { try? $0.text() }.filter { !$0.isEmpty }
    }

    private func isAdultInterstitial(_ document: Document) throws -> Bool {
        guard try document.select("a[href*=\"view_adult=true\"]").first() != nil else { return false }
        return try document.select("p.caution.notice, .work.blurb, #main").first() != nil
    }

    private func value(after label: String, in document: Document) throws -> String? {
        guard let dt = try document.select("dt").array().first(where: { ((try? $0.text()) ?? "").hasPrefix(label) }) else { return nil }
        return try dt.nextElementSibling()?.text()
    }
}

