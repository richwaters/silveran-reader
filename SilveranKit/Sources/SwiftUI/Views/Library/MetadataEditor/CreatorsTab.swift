import SwiftUI

struct CreatorsTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MetadataColumnHeaders()

                // Authors
                listRow(label: "Authors", field: "authors")

                Divider()

                // Narrators
                listRow(label: "Narrators", field: "narrators")

                Divider()

                // Other Creators
                TransferColumnRow(
                    leftCanCopy: originalCreatorsDisplay != currentCreatorsDisplay,
                    leftHelp: "Copy server creators into current metadata",
                    leftAction: { viewModel.revertFieldToOriginal(field: "creators", for: bookId) },
                    rightCanCopy: viewModel.hardcoverStringList(field: "creators", for: bookId).map { $0 != currentCreatorsDisplay } ?? false,
                    rightHelp: "Copy Hardcover creators into current metadata",
                    rightAction: { viewModel.revertToHardcover(field: "creators", for: bookId) }
                ) {
                    SourceListValues(
                        values: originalCreatorsDisplay,
                        currentValues: currentCreatorsDisplay
                    )
                } center: {
                    creatorListEditor
                } right: {
                    SourceListValues(
                        values: viewModel.hardcoverStringList(field: "creators", for: bookId),
                        currentValues: currentCreatorsDisplay
                    )
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func listRow(label: String, field: String) -> some View {
        let current = viewModel.books.first { $0.id == bookId }?.stringList(for: field) ?? []

        TransferColumnRow(
            leftCanCopy: viewModel.originalStringList(field: field, for: bookId) != current,
            leftHelp: "Copy server \(label.lowercased()) into current metadata",
            leftAction: { viewModel.revertFieldToOriginal(field: field, for: bookId) },
            rightCanCopy: viewModel.hardcoverStringList(field: field, for: bookId).map { $0 != current } ?? false,
            rightHelp: "Copy Hardcover \(label.lowercased()) into current metadata",
            rightAction: { viewModel.revertToHardcover(field: field, for: bookId) }
        ) {
            SourceListValues(
                values: viewModel.originalStringList(field: field, for: bookId),
                currentValues: current
            )
        } center: {
            StringListTable(
                label: label,
                field: field,
                bookId: bookId,
                viewModel: viewModel
            )
        } right: {
            SourceListValues(
                values: viewModel.hardcoverStringList(field: field, for: bookId),
                currentValues: current
            )
        }
    }

    private var originalCreatorsDisplay: [String] {
        let creators = viewModel.books.first { $0.id == bookId }?
            .originalMetadata.creators ?? []
        return creators.map { creator in
            [creator.name, creator.role].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: " - ")
        }
    }

    private var currentCreatorsDisplay: [String] {
        let creators = viewModel.books.first { $0.id == bookId }?.creators ?? []
        return creators.map { creator in
            [creator.name, creator.role]
                .filter { !$0.isEmpty }.joined(separator: " - ")
        }
    }

    // MARK: - Other Creators Editor

    @ViewBuilder
    private var creatorListEditor: some View {
        let creators = viewModel.books.first { $0.id == bookId }?.creators ?? []

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Other Creators")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                    else { return }
                    viewModel.books[index].creators.append(
                        MetadataEditorViewModel.EditableCreator(
                            name: "", fileAs: "", role: "", uuid: nil
                        )
                    )
                    viewModel.markDirty(field: "creators", for: bookId)
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            ForEach(creators) { creator in
                HStack(spacing: 4) {
                    if viewModel.isImported(
                        field: "creators", value: creator.name, for: bookId)
                    {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                    }
                    TextField(
                        "Name",
                        text: creatorBinding(creatorId: creator.id, keyPath: \.name)
                    )
                    .textFieldStyle(.roundedBorder)

                    creatorRolePicker(creatorId: creator.id)

                    Button(action: {
                        guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        viewModel.books[bookIndex].creators.removeAll { $0.id == creator.id }
                        viewModel.markDirty(field: "creators", for: bookId)
                    }) {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Creator Bindings

    private func creatorBinding(
        creatorId: UUID,
        keyPath: WritableKeyPath<MetadataEditorViewModel.EditableCreator, String>
    ) -> Binding<String> {
        Binding(
            get: {
                viewModel.books.first { $0.id == bookId }?
                    .creators.first { $0.id == creatorId }?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId }),
                    let creatorIndex = viewModel.books[bookIndex].creators.firstIndex(where: {
                        $0.id == creatorId
                    })
                else { return }
                viewModel.books[bookIndex].creators[creatorIndex][keyPath: keyPath] = newValue
                viewModel.markDirty(field: "creators", for: bookId)
            }
        )
    }

    private static let knownRoles: [(code: String, label: String)] = [
        ("trl", "Translator"),
        ("edt", "Editor"),
        ("ill", "Illustrator"),
        ("aui", "Foreword"),
        ("clr", "Colorist"),
    ]

    private static let knownRoleCodes: Set<String> = Set(knownRoles.map(\.code))

    @ViewBuilder
    private func creatorRolePicker(creatorId: UUID) -> some View {
        let role =
            viewModel.books.first { $0.id == bookId }?
            .creators.first { $0.id == creatorId }?.role ?? ""
        let isCustom = !Self.knownRoleCodes.contains(role)

        HStack(spacing: 2) {
            Picker("", selection: Binding(
                get: {
                    let r =
                        viewModel.books.first { $0.id == bookId }?
                        .creators.first { $0.id == creatorId }?.role ?? ""
                    if Self.knownRoleCodes.contains(r) { return r }
                    return "__custom__"
                },
                set: { newValue in
                    guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId }),
                        let creatorIndex = viewModel.books[bookIndex].creators.firstIndex(where: {
                            $0.id == creatorId
                        })
                    else { return }
                    if newValue == "__custom__" {
                        viewModel.books[bookIndex].creators[creatorIndex].role = ""
                    } else {
                        viewModel.books[bookIndex].creators[creatorIndex].role = newValue
                    }
                    viewModel.markDirty(field: "creators", for: bookId)
                }
            )) {
                ForEach(Self.knownRoles, id: \.code) { role in
                    Text(role.label).tag(role.code)
                }
                Divider()
                Text("Custom...").tag("__custom__")
            }
            .frame(maxWidth: 130)

            if isCustom {
                TextField(
                    "MARC",
                    text: creatorBinding(creatorId: creatorId, keyPath: \.role)
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 60)

                marcHelpButton
            }
        }
    }

    @ViewBuilder
    private var marcHelpButton: some View {
        Button(action: {
            let url = URL(string: "https://www.loc.gov/marc/relators/relaterm.html")!
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        }) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(
            "Enter a MARC relator code (e.g. trl, edt, ill).\nClick to view the full list at the Library of Congress."
        )
    }
}
