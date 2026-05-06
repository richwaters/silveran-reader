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
            let gutterWidth: CGFloat = 42
            let columnWidth = (geo.size.width - gutterWidth * 2) / 3

            HStack(alignment: .top, spacing: 8) {
                sourceColumn(
                    title: "Storyteller Server",
                    value: originalDescription
                )
                .frame(width: columnWidth)

                SourceCopyButton(
                    direction: .fromLeft,
                    isEnabled: originalDescription != currentDescription,
                    help: originalDescription != currentDescription
                        ? "Copy server description into current metadata" : "Already matches",
                    action: { viewModel.revertFieldToOriginal(field: "description", for: bookId) }
                )
                .frame(width: gutterWidth)
                .padding(.top, 52)

                currentColumn
                    .frame(width: columnWidth)

                SourceCopyButton(
                    direction: .fromRight,
                    isEnabled: hardcoverDescription.map { $0 != currentDescription } ?? false,
                    help: hardcoverDescription.map { $0 != currentDescription } == true
                        ? "Copy Hardcover description into current metadata" : "Already matches",
                    action: { viewModel.revertToHardcover(field: "description", for: bookId) }
                )
                .frame(width: gutterWidth)
                .padding(.top, 52)

                sourceColumn(
                    title: "Hardcover Import",
                    value: hardcoverDescription
                )
                .frame(width: columnWidth)
            }
        }
    }

    private var currentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Current Metadata").font(.headline).padding([.horizontal, .top])

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
            .padding()
        }
    }

    @ViewBuilder
    private func sourceColumn(
        title: String,
        value: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding([.horizontal, .top])

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let value {
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
                    } else {
                        Text("--")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
        }
    }
}
