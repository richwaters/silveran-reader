import SwiftUI

struct DescriptionTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel

    private var currentDescription: String {
        viewModel.books.first { $0.id == bookId }?.description ?? ""
    }

    private var originalDescription: String {
        viewModel.originalScalarValue(field: "description", for: bookId)
    }

    private var hardcoverDescription: String? {
        viewModel.hardcoverScalarValue(field: "description", for: bookId)
    }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let editWidth = total * 0.43
            let refWidth = total * 0.285

            HStack(alignment: .top, spacing: 0) {
                // Column 1: editor
                VStack(alignment: .leading, spacing: 0) {
                    Text("Metadata to save").font(.headline).padding([.horizontal, .top])

                    TextEditor(text: Binding(
                        get: { currentDescription },
                        set: { newValue in
                            guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                            else { return }
                            viewModel.books[index].description = newValue
                            viewModel.markDirty(field: "description", for: bookId)
                        }
                    ))
                    .font(.body)
                    .padding(8)
                    .border(
                        fieldMatchColor(field: "description", bookId: bookId, viewModel: viewModel),
                        width: 2
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding()
                }
                .frame(width: editWidth)

                Divider()

                // Column 2: Storyteller Server diff
                VStack(alignment: .leading, spacing: 0) {
                    Text("Storyteller Server")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding([.horizontal, .top])

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            RevertButton(color: .white, help: "Revert to server value") {
                                guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                                else { return }
                                viewModel.books[index].description =
                                    viewModel.books[index].originalMetadata.description ?? ""
                                viewModel.books[index].dirtyFields.remove("description")
                                viewModel.books[index].importedFields.remove("description")
                            }
                            if originalDescription.isEmpty {
                                Text("(empty)")
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .italic()
                            } else if currentDescription == originalDescription {
                                Text(originalDescription)
                                    .font(.callout)
                                    .foregroundStyle(.white)
                                    .textSelection(.enabled)
                            } else {
                                WordDiffView(
                                    oldText: originalDescription,
                                    newText: currentDescription,
                                    baseColor: .white
                                )
                            }
                        }
                        .padding()
                    }
                }
                .frame(width: refWidth)

                Divider()

                // Column 3: Hardcover Import diff
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hardcover Import")
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .padding([.horizontal, .top])

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if let hcDesc = hardcoverDescription {
                                RevertButton(color: .blue, help: "Revert to Hardcover value") {
                                    viewModel.revertToHardcover(field: "description", for: bookId)
                                }
                                if currentDescription == hcDesc {
                                    Text(hcDesc)
                                        .font(.callout)
                                        .foregroundStyle(.blue)
                                        .textSelection(.enabled)
                                } else {
                                    WordDiffView(
                                        oldText: hcDesc,
                                        newText: currentDescription,
                                        baseColor: .blue
                                    )
                                }
                            } else {
                                Text("--")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding()
                    }
                }
                .frame(width: refWidth)
            }
        }
    }
}
