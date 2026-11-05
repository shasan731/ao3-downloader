import SwiftUI

struct WorkPreviewView: View {
    let work: Work
    var body: some View {
        Section("Preview") {
            Text(work.title).font(.title2).bold().textSelection(.enabled)
            Text(work.creators.joined(separator: ", ")).foregroundStyle(.secondary).textSelection(.enabled)
            if let summary = work.summary { Text(summary).textSelection(.enabled) }
            LabeledContent("Chapters", value: chapterText)
            LabeledContent("Source", value: work.sourceSite.displayName)
            if let rating = work.rating { LabeledContent("Rating", value: rating) }
            if let language = work.language { LabeledContent("Language", value: language) }
            if let count = work.wordCount { LabeledContent("Words", value: count.formatted()) }
            if !work.fandoms.isEmpty { LabeledContent("Fandom", value: work.fandoms.joined(separator: ", ")) }
            if !work.warnings.isEmpty { LabeledContent("Warnings", value: work.warnings.joined(separator: ", ")) }
            Link("Open source on \(work.sourceSite.shortName)", destination: work.sourceURL)
        }
    }
    private var chapterText: String {
        let count = work.chapterCountPublished.map(String.init) ?? "?"
        let expected = work.chapterCountExpected.map { "/\($0)" } ?? ""
        let state = work.completion == .complete ? "Complete" : work.completion == .workInProgress ? "Work in progress" : "Unknown"
        return "\(count)\(expected) • \(state)"
    }
}

