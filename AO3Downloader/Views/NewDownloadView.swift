import AppKit
import SwiftUI

struct NewDownloadView: View {
    @StateObject private var model = NewDownloadViewModel()
    var body: some View {
        Form {
            Section("Source") {
                HStack { TextField("https://archiveofourown.org/works/…", text: $model.input).textFieldStyle(.roundedBorder).accessibilityLabel("AO3 URL"); Button("Paste") { model.paste() }; Button("Analyze URL") { Task { await model.analyze() } }.keyboardShortcut(.return).disabled(model.isBusy || model.input.isEmpty) }
                Text(model.status).foregroundStyle(model.work == nil ? .secondary : .primary).textSelection(.enabled)
            }
            if let work = model.work { WorkPreviewView(work: work) }
            Section("Download") {
                Picker("Format", selection: $model.format) { ForEach(DownloadFormat.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                HStack { Button("Choose Folder…") { model.chooseFolder() }; Text(model.destination?.path(percentEncoded: false) ?? "No folder selected").lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
                Button("Download Complete Work") { Task { await model.download() } }.buttonStyle(.borderedProminent).disabled(model.work == nil || model.destination == nil || model.isBusy)
                if let output = model.outputURL { HStack { Button("Open File") { NSWorkspace.shared.open(output) }; Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) } } }
            }
        }.formStyle(.grouped).navigationTitle("New Download").overlay { if model.isBusy { ProgressView().controlSize(.large) } }
    }
}

