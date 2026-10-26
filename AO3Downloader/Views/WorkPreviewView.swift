import SwiftUI

struct WorkPreviewView: View {
    let work: Work
    var body: some View {
        Section("Preview") {
            Text(work.title).font(.title2).bold().textSelection(.enabled)
            Text(work.creators.joined(separator: ", ")).foregroundStyle(.secondary).textSelection(.enabled)
            if let summary = work.summary { Text(summary).textSelection(.enabled) }
            LabeledContent("Chapters", value: chapterText)
            if let language = work.language { LabeledContent("Language", value: language) }
            if let count = work.wordCount { LabeledContent("Words", value: count.formatted()) }
            if !work.warnings.isEmpty { LabeledContent("Warnings", value: work.warnings.joined(separator: ", ")) }
            Link("Open source on AO3", destination: work.sourceURL)
        }
    }
    private var chapterText: String { "\(work.chapterCountPublished.map(String.init) ?? "?")/\(work.chapterCountExpected.map(String.init) ?? "?") • \(work.completion == .complete ? "Complete" : "Work in progress")" }
}

