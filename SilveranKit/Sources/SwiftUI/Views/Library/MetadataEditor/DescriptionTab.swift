import SwiftUI

struct DescriptionTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel
    let openHardcoverImport: () -> Void

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
            let contentHeight = max(geo.size.height - 52, 100)

            VStack(alignment: .leading, spacing: 2) {
                MetadataColumnHeaders(centerTitle: "Current Description")
                    .frame(height: 22, alignment: .top)

                TransferColumnRow(
                    leftCanCopy: originalDescription != currentDescription,
                    leftHelp: originalDescription != currentDescription
                        ? "Copy server description into current metadata" : "Already matches",
                    leftAction: { viewModel.revertFieldToOriginal(field: "description", for: bookId) },
                    rightCanCopy: hardcoverDescription.map { $0 != currentDescription } ?? false,
                    rightHelp: hardcoverDescription.map { $0 != currentDescription } == true
                        ? "Copy Hardcover description into current metadata" : "Already matches",
                    rightAction: { viewModel.revertToHardcover(field: "description", for: bookId) }
                ) {
                    sourceColumn(value: originalDescription)
                } center: {
                    currentColumn
                } right: {
                    sourceColumn(value: hardcoverDescription)
                }
                .frame(height: contentHeight, alignment: .top)
            }
            .padding()
            .frame(
                width: geo.size.width,
                height: max(geo.size.height - 28, 100),
                alignment: .top
            )
        }
    }

    private var currentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        }
    }

    @ViewBuilder
    private func sourceColumn(
        value: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let value {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if value.isEmpty {
                            Text("(empty)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .italic()
                        } else if currentDescription == value {
                            Text(value)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        } else {
                            WordDiffView(
                                oldText: value,
                                newText: currentDescription,
                                baseColor: .primary
                            )
                        }
                    }
                    .padding()
                }
            } else {
                ImportHardcoverDataPlaceholder(action: openHardcoverImport)
            }
        }
    }
}
