import AppKit
import SwiftUI

struct NewDownloadView: View {
    @ObservedObject var model: NewDownloadViewModel
    @AppStorage("allowAdultContent") private var allowAdultContent = false
    @FocusState private var isURLFieldFocused: Bool
    var body: some View {
        Form {
            Section("Source") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("AO3 work/series or FanFiction.net story URL", text: $model.input)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .focused($isURLFieldFocused)
                            .accessibilityLabel("Story source URL")
                            .disabled(model.isBusy)
                            .onSubmit { model.startAnalyze() }
                        if !model.input.isEmpty && !model.isBusy {
                            Button {
                                model.input = ""
                                isURLFieldFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Clear URL")
                            .accessibilityLabel("Clear story source URL")
                        }
                    }
                    HStack {
                        Button("Paste", systemImage: "doc.on.clipboard") { model.paste() }
                            .disabled(model.isBusy)
                        Spacer()
                        Button("Analyze", systemImage: "magnifyingglass") { model.startAnalyze() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.return)
                            .disabled(model.isBusy || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if !isFanFictionInput {
                    Toggle("Allow public Mature/Explicit AO3 works", isOn: $allowAdultContent)
                    Text("This sends AO3’s “Yes, continue” choice with work requests. It does not share browser cookies or sign in.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("FanFiction.net stories are assembled locally from their public chapter pages. Browser verification pages are never bypassed.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label {
                    Text(model.status).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: model.isBusy ? "clock.arrow.circlepath" : "info.circle")
                }
                .foregroundStyle(model.work == nil && model.series == nil ? .secondary : .primary)
            }
            if let operation = model.activeOperation { OperationProgressView(operation: operation, canCancel: model.isBusy, onCancel: model.cancelOperation) }
            if let work = model.work { WorkPreviewView(work: work) }
            if let series = model.series {
                SeriesPreviewView(series: series,
                                  progressStates: model.seriesItemStates,
                                  failureMessages: Dictionary(uniqueKeysWithValues: model.currentFailures.map { ($0.workID, $0.message) }),
                                  isBusy: model.isBusy,
                                  onSelectionChanged: { model.setSelection($1, for: $0) },
                                  onSelectAll: { model.selectAllSeriesWorks($0) },
                                  onRetry: model.retryPart)
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Choose Folder…", systemImage: "folder") { model.chooseFolder() }.disabled(model.isBusy)
                    Text(model.destination?.path(percentEncoded: false) ?? "No folder selected")
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        .foregroundStyle(model.destination == nil ? .secondary : .primary)
                }
                Button(model.series == nil ? "Download Complete Work" : "Download Selected Works", systemImage: "arrow.down.circle.fill") { model.startDownload() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.hasDownloadableSelection || model.destination == nil || model.isBusy)
                if let output = model.outputURL { HStack { Button("Open File") { NSWorkspace.shared.open(output) }; Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) } } }
                if model.series != nil && !model.downloadedParts.isEmpty {
                    Button("Combine Selected Verified Parts") { model.combineSelected() }
                        .disabled(model.isBusy || !model.canCombineSelection)
                }
                if model.retryableFailureCount > 0 {
                    Button("Retry Failed Selected Parts (\(model.retryableFailureCount))") { model.retryFailedParts() }
                        .disabled(model.isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Download")
        .onAppear {
            if model.input.isEmpty { isURLFieldFocused = true }
        }
    }

    private var isFanFictionInput: Bool {
        URLComponents(string: model.input.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() == "www.fanfiction.net"
    }
}

