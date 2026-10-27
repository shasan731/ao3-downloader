import SwiftUI

struct MetadataEditorView: View {
    @ObservedObject var model: NewDownloadViewModel
    var showApplyToSingle = false

    var body: some View {
        GroupBox("Book Metadata") {
            VStack(alignment: .leading, spacing: 12) {
                if let workID = model.metadataTargetPartID {
                    Label("Editing downloaded part \(workID)", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                metadataField("Book title", text: $model.metadataTitle)
                metadataField("Authors", hint: "Comma separated", text: $model.metadataAuthors)
                metadataField("Language", hint: "For example, en", text: $model.metadataLanguage)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Cover").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Choose Cover…") { model.chooseCoverImage() }
                        if let cover = model.metadataCoverURL {
                            Text(cover.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Remove") { model.metadataCoverURL = nil }
                        } else {
                            Text("Optional JPEG or PNG")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Divider()
                HStack {
                    Text("Changes are embedded in supported book files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if model.metadataTargetPartID != nil {
                        Button("Cancel") { model.cancelPartMetadataEditing() }
                    }
                    Button(showApplyToSingle || model.metadataTargetPartID != nil ? "Apply to File" : "Save Metadata") {
                        model.saveMetadataChanges(applyToSingleFile: showApplyToSingle)
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }

    private func metadataField(_ label: String, hint: String? = nil, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(label)
                if let hint {
                    Text("• \(hint)").foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
    }
}
