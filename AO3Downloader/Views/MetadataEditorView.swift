import SwiftUI

struct MetadataEditorView: View {
    @ObservedObject var model: NewDownloadViewModel
    var showApplyToSingle = false

    var body: some View {
        GroupBox("Book Metadata") {
            Form {
                if let workID = model.metadataTargetPartID { Text("Editing downloaded part \(workID)").font(.caption).foregroundStyle(.secondary) }
                TextField("Book title", text: $model.metadataTitle)
                TextField("Authors (comma separated)", text: $model.metadataAuthors)
                TextField("Language", text: $model.metadataLanguage)
                HStack {
                    Button("Choose Cover…") { model.chooseCoverImage() }
                    if let cover = model.metadataCoverURL { Text(cover.lastPathComponent).lineLimit(1); Button("Remove") { model.metadataCoverURL = nil } }
                    Spacer()
                    if model.metadataTargetPartID != nil {
                        Button("Cancel") { model.cancelPartMetadataEditing() }
                    }
                    Button(showApplyToSingle || model.metadataTargetPartID != nil ? "Apply to File" : "Save Metadata") {
                        model.saveMetadataChanges(applyToSingleFile: showApplyToSingle)
                    }
                }
            }.formStyle(.grouped)
        }
    }
}
