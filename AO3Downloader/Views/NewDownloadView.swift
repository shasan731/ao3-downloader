import AppKit
import SwiftUI

struct NewDownloadView: View {
    @ObservedObject var model: NewDownloadViewModel
    var body: some View {
        Form {
            Section("Source") {
                HStack { TextField("https://archiveofourown.org/works/…", text: $model.input).textFieldStyle(.roundedBorder).accessibilityLabel("AO3 URL").disabled(model.isBusy); Button("Paste") { model.paste() }.disabled(model.isBusy); Button("Analyze URL") { model.startAnalyze() }.keyboardShortcut(.return).disabled(model.isBusy || model.input.isEmpty) }
                Text(model.status).foregroundStyle(model.work == nil ? .secondary : .primary).textSelection(.enabled)
            }
            if let operation = model.activeOperation { OperationProgressView(operation: operation, canCancel: model.isBusy, onCancel: model.cancelOperation) }
            if let work = model.work { WorkPreviewView(work: work) }
            if let series = model.series {
                SeriesPreviewView(series: series,
                                  progressStates: model.seriesItemStates,
                                  onSelectionChanged: { model.setSelection($1, for: $0) },
                                  onSelectAll: { model.selectAllSeriesWorks($0) })
            }
            if model.work != nil || model.series != nil { MetadataEditorView(model: model) }
            Section("Download") {
                Picker("Format", selection: Binding(get: { model.format }, set: { model.setFormat($0) })) {
                    ForEach(DownloadFormat.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).disabled(model.isBusy || model.hasLoadedLibraryRecord)
                if model.series != nil {
                    Picker("Series output", selection: $model.seriesOutputMode) {
                        ForEach(SeriesOutputMode.allCases.filter { model.format != .html || $0 == .separate }) { Text($0.rawValue).tag($0) }
                    }.disabled(model.isBusy || model.hasLoadedLibraryRecord)
                    Text(model.format == .html ? "Combined HTML is not supported." : "The final live selection is combined when every selected part is verified. Failed parts can be retried and combined later.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                HStack { Button("Choose Folder…") { model.chooseFolder() }.disabled(model.isBusy); Text(model.destination?.path(percentEncoded: false) ?? "No folder selected").lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
                Button(model.series == nil ? "Download Complete Work" : "Download Selected Works") { model.startDownload() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasDownloadableSelection || model.destination == nil || model.isBusy)
                if let output = model.outputURL { HStack { Button("Open File") { NSWorkspace.shared.open(output) }; Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) } } }
                if model.series != nil && !model.downloadedParts.isEmpty {
                    Button("Combine Selected Verified Parts") { model.combineSelected() }
                        .disabled(model.isBusy || !model.canCombineSelection)
                }
            }
        }.formStyle(.grouped).navigationTitle("New Download")
    }
}

