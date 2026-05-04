import SwiftUI

struct CreatorsTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TwoColumnRow {
                    Text("Edited").font(.headline)
                } right: {
                    HStack(spacing: 0) {
                        Text("Storyteller Server")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Hardcover Import")
                            .font(.headline)
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Authors
                TwoColumnRow {
                    StringListTable(
                        label: "Authors",
                        field: "authors",
                        bookId: bookId,
                        viewModel: viewModel
                    )
                } right: {
                    ReferenceListValues(
                        field: "authors",
                        bookId: bookId,
                        viewModel: viewModel,
                        revertToOriginal: {
                            guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                            else { return }
                            viewModel.books[index].authors =
                                viewModel.books[index].originalMetadata.authors?
                                .compactMap { $0.name } ?? []
                            viewModel.books[index].dirtyFields.remove("authors")
                            viewModel.books[index].importedFields.remove("authors")
                        }
                    )
                }

                Divider()

                // Narrators
                TwoColumnRow {
                    StringListTable(
                        label: "Narrators",
                        field: "narrators",
                        bookId: bookId,
                        viewModel: viewModel
                    )
                } right: {
                    ReferenceListValues(
                        field: "narrators",
                        bookId: bookId,
                        viewModel: viewModel,
                        revertToOriginal: {
                            guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                            else { return }
                            viewModel.books[index].narrators =
                                viewModel.books[index].originalMetadata.narrators?
                                .compactMap { $0.name } ?? []
                            viewModel.books[index].dirtyFields.remove("narrators")
                            viewModel.books[index].importedFields.remove("narrators")
                        }
                    )
                }

                Divider()

                // Other Creators
                TwoColumnRow {
                    creatorListEditor
                } right: {
                    creatorsReference
                }
            }
            .padding()
        }
    }

    // MARK: - Other Creators Editor

    @ViewBuilder
    private var creatorListEditor: some View {
        let isDirty = viewModel.isDirty(field: "creators", for: bookId)
        let creators = viewModel.books.first { $0.id == bookId }?.creators ?? []
        let hasImports = viewModel.books.first { $0.id == bookId }?
            .importedItems["creators"]?.isEmpty == false

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Other Creators")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        hasImports ? Color.blue : isDirty ? Color.orange : .primary)
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

    // MARK: - Creators Reference

    @ViewBuilder
    private var creatorsReference: some View {
        let origCreators = viewModel.books.first { $0.id == bookId }?
            .originalMetadata.creators ?? []
        let hcCreators = viewModel.hardcoverStringList(field: "creators", for: bookId)

        VStack(alignment: .leading, spacing: 6) {
            Text("Other Creators").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    RevertButton(color: .white, help: "Revert to server value") {
                        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        viewModel.books[index].creators =
                            viewModel.books[index].originalMetadata.creators?.map { creator in
                                MetadataEditorViewModel.EditableCreator(
                                    name: creator.name ?? "",
                                    fileAs: creator.fileAs ?? "",
                                    role: creator.role ?? "",
                                    uuid: creator.uuid
                                )
                            } ?? []
                        viewModel.books[index].dirtyFields.remove("creators")
                        viewModel.books[index].importedFields.remove("creators")
                    }
                    if origCreators.isEmpty {
                        Text("(empty)")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.5))
                            .italic()
                    } else {
                        ForEach(origCreators, id: \.self) { creator in
                            let display = [creator.name, creator.role].compactMap { $0 }
                                .filter { !$0.isEmpty }.joined(separator: " - ")
                            Text(display)
                                .font(.callout)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 4) {
                    if let hcCreators {
                        RevertButton(color: .blue, help: "Revert to Hardcover value") {
                            viewModel.revertToHardcover(field: "creators", for: bookId)
                        }
                        ForEach(hcCreators, id: \.self) { creator in
                            Text(creator)
                                .font(.callout)
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Text("--")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
