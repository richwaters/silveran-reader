import SwiftUI

struct MetadataEditorBookForm: View {
    @Bindable var viewModel: MetadataEditorViewModel
    let availableStatuses: [BookStatus]

    private var bookId: String? { viewModel.selectedBookId }

    var body: some View {
        if let bookId, let book = viewModel.books.first(where: { $0.id == bookId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleSection(book: book)
                    descriptionSection(book: book)
                    detailsSection(book: book)
                    creatorsSection(book: book)
                    organizationSection(book: book)
                }
                .padding()
            }
        } else {
            ContentUnavailableView("No Book Selected", systemImage: "book.closed")
        }
    }

    // MARK: - Title Section

    @ViewBuilder
    private func titleSection(book: MetadataEditorViewModel.EditableBook) -> some View {
        GroupBox(label: Text("Title").font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                editableTextField("Title", field: "title", value: Binding(
                    get: { viewModel.books.first { $0.id == bookId }?.title ?? "" },
                    set: { newValue in
                        updateField(bookId: book.id, field: "title") { $0.title = newValue }
                    }
                ), bookId: book.id, revert: {
                    revertField(bookId: book.id, field: "title") {
                        $0.title = $0.originalMetadata.title
                    }
                })

                editableTextField("Subtitle", field: "subtitle", value: Binding(
                    get: { viewModel.books.first { $0.id == bookId }?.subtitle ?? "" },
                    set: { newValue in
                        updateField(bookId: book.id, field: "subtitle") { $0.subtitle = newValue }
                    }
                ), bookId: book.id, revert: {
                    revertField(bookId: book.id, field: "subtitle") {
                        $0.subtitle = $0.originalMetadata.subtitle ?? ""
                    }
                })
            }
        }
    }

    // MARK: - Description Section

    @ViewBuilder
    private func descriptionSection(book: MetadataEditorViewModel.EditableBook) -> some View {
        let isDirty = viewModel.isDirty(field: "description", for: book.id)
        let isImported = viewModel.isImportedField("description", for: book.id)
        GroupBox {
            TextEditor(text: Binding(
                get: { viewModel.books.first { $0.id == bookId }?.description ?? "" },
                set: { newValue in
                    updateField(bookId: book.id, field: "description") {
                        $0.description = newValue
                    }
                }
            ))
            .frame(minHeight: 80, maxHeight: 160)
            .font(.body)
            .border(fieldBorderColor(field: "description", bookId: book.id), width: 2)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if isDirty || isImported {
                let original = book.originalMetadata.description ?? ""
                let current = viewModel.books.first { $0.id == bookId }?.description ?? ""
                if original != current {
                    if !original.isEmpty {
                        Text(original)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .lineLimit(3)
                    } else {
                        Text("(was empty)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
            }
        } label: {
            HStack {
                Text("Description").font(.headline)
                if isDirty {
                    revertButton {
                        revertField(bookId: book.id, field: "description") {
                            $0.description = $0.originalMetadata.description ?? ""
                        }
                    }
                }
            }
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection(book: MetadataEditorViewModel.EditableBook) -> some View {
        GroupBox(label: Text("Details").font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                editableTextField("Language", field: "language", value: Binding(
                    get: { viewModel.books.first { $0.id == bookId }?.language ?? "" },
                    set: { newValue in
                        updateField(bookId: book.id, field: "language") {
                            $0.language = newValue
                        }
                    }
                ), bookId: book.id, revert: {
                    revertField(bookId: book.id, field: "language") {
                        $0.language = $0.originalMetadata.language ?? ""
                    }
                })

                editableTextField("Publication Date", field: "publicationDate", value: Binding(
                    get: { viewModel.books.first { $0.id == bookId }?.publicationDate ?? "" },
                    set: { newValue in
                        updateField(bookId: book.id, field: "publicationDate") {
                            $0.publicationDate = newValue
                        }
                    }
                ), bookId: book.id, revert: {
                    revertField(bookId: book.id, field: "publicationDate") {
                        $0.publicationDate = MetadataEditorViewModel.EditableBook.dateOnly(
                            $0.originalMetadata.publicationDate) ?? ""
                    }
                })

                ratingPicker(book: book)

                statusPicker(book: book)
            }
        }
    }

    // MARK: - Creators Section

    @ViewBuilder
    private func creatorsSection(book: MetadataEditorViewModel.EditableBook) -> some View {
        GroupBox(label: Text("Creators").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                stringListEditor(
                    label: "Authors",
                    field: "authors",
                    bookId: book.id,
                    revert: {
                        revertField(bookId: book.id, field: "authors") {
                            $0.authors = $0.originalMetadata.authors?.compactMap { $0.name } ?? []
                        }
                    }
                )

                Divider()

                stringListEditor(
                    label: "Narrators",
                    field: "narrators",
                    bookId: book.id,
                    revert: {
                        revertField(bookId: book.id, field: "narrators") {
                            $0.narrators =
                                $0.originalMetadata.narrators?.compactMap { $0.name } ?? []
                        }
                    }
                )

                Divider()

                creatorListEditor(book: book)
            }
        }
    }

    // MARK: - Organization Section

    @ViewBuilder
    private func organizationSection(book: MetadataEditorViewModel.EditableBook) -> some View {
        GroupBox(label: Text("Organization").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                seriesEditor(book: book)

                Divider()

                stringListEditor(
                    label: "Tags",
                    placeholder: "Tag",
                    field: "tags",
                    bookId: book.id,
                    revert: {
                        revertField(bookId: book.id, field: "tags") {
                            $0.tags = $0.originalMetadata.tags?.map { $0.name } ?? []
                        }
                    }
                )
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func revertButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(.orange)
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .help("Revert to original value")
    }

    private func fieldBorderColor(field: String, bookId: String) -> Color {
        if viewModel.fieldHasError(field, for: bookId) { return .red }
        if viewModel.isImportedField(field, for: bookId) { return .blue }
        if viewModel.isDirty(field: field, for: bookId) { return .orange }
        return .clear
    }

    @ViewBuilder
    private func editableTextField(
        _ label: String,
        field: String,
        value: Binding<String>,
        bookId: String,
        revert: @escaping () -> Void
    ) -> some View {
        let isDirty = viewModel.isDirty(field: field, for: bookId)
        let isImported = viewModel.isImportedField(field, for: bookId)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                HStack(spacing: 4) {
                    if isDirty {
                        revertButton(action: revert)
                    }
                    Text(label)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 140, alignment: .trailing)

                TextField(label, text: value)
                    .textFieldStyle(.roundedBorder)
                    .border(fieldBorderColor(field: field, bookId: bookId), width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if isDirty || isImported {
                let original = originalScalarValue(field: field, bookId: bookId)
                let current = value.wrappedValue
                if original != current {
                    HStack {
                        Spacer().frame(width: 140)
                        if !original.isEmpty {
                            Text(original)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .strikethrough()
                                .lineLimit(1)
                        } else {
                            Text("(was empty)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .italic()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ratingPicker(book: MetadataEditorViewModel.EditableBook) -> some View {
        let isDirty = viewModel.isDirty(field: "rating", for: book.id)
        HStack {
            HStack(spacing: 4) {
                if isDirty {
                    revertButton {
                        revertField(bookId: book.id, field: "rating") {
                            $0.rating = $0.originalMetadata.rating.map { String($0) } ?? ""
                        }
                    }
                }
                Text("Rating")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140, alignment: .trailing)

            Picker("", selection: Binding(
                get: { viewModel.books.first { $0.id == bookId }?.rating ?? "" },
                set: { newValue in
                    updateField(bookId: book.id, field: "rating") { $0.rating = newValue }
                }
            )) {
                Text("None").tag("")
                ForEach(["1", "2", "3", "4", "5"], id: \.self) { r in
                    Text(r).tag(r)
                }
            }
            .border(fieldBorderColor(field: "rating", bookId: book.id), width: 2)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private func statusPicker(book: MetadataEditorViewModel.EditableBook) -> some View {
        let isDirty = viewModel.isDirty(field: "status", for: book.id)
        HStack {
            HStack(spacing: 4) {
                if isDirty {
                    revertButton {
                        revertField(bookId: book.id, field: "status") {
                            $0.statusUuid = $0.originalMetadata.status?.uuid
                        }
                    }
                }
                Text("Status")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140, alignment: .trailing)

            Picker("", selection: Binding(
                get: { viewModel.books.first { $0.id == bookId }?.statusUuid ?? "" },
                set: { newValue in
                    guard !newValue.isEmpty else { return }
                    updateField(bookId: book.id, field: "status") {
                        $0.statusUuid = newValue
                    }
                }
            )) {
                ForEach(availableStatuses, id: \.uuid) { status in
                    Text(status.name).tag(status.uuid ?? "")
                }
            }
            .border(fieldBorderColor(field: "status", bookId: book.id), width: 2)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private func stringListEditor(
        label: String,
        placeholder: String? = nil,
        field: String,
        bookId: String,
        revert: @escaping () -> Void
    ) -> some View {
        let isDirty = viewModel.isDirty(field: field, for: bookId)
        let items = viewModel.books.first { $0.id == bookId }?.stringList(for: field) ?? []
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                let hasImports = viewModel.books.first { $0.id == bookId }?
                    .importedItems[field]?.isEmpty == false
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        hasImports ? Color.blue : isDirty ? Color.orange : .primary)
                if isDirty {
                    revertButton(action: revert)
                }
                Spacer()
                Button(action: {
                    guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else {
                        return
                    }
                    viewModel.books[index].appendToStringList(field: field, value: "")
                    viewModel.markDirty(field: field, for: bookId)
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let originalList = originalStringList(field: field, bookId: bookId)
                let originalValue = index < originalList.count ? originalList[index] : nil
                let isEdited = originalValue != nil && originalValue != item

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        let isImported = viewModel.isImported(
                            field: field, value: item, for: bookId)
                        if isImported {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                        }
                        TextField(
                            placeholder ?? label,
                            text: Binding(
                                get: {
                                    let current =
                                        viewModel.books.first { $0.id == bookId }?.stringList(
                                            for: field) ?? []
                                    guard index < current.count else { return "" }
                                    return current[index]
                                },
                                set: { newValue in
                                    guard
                                        let bookIndex = viewModel.books.firstIndex(where: {
                                            $0.id == bookId
                                        })
                                    else { return }
                                    viewModel.books[bookIndex].updateStringList(
                                        field: field, index: index, value: newValue)
                                    viewModel.markDirty(field: field, for: bookId)
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(action: {
                            guard
                                let bookIndex = viewModel.books.firstIndex(where: {
                                    $0.id == bookId
                                })
                            else { return }
                            viewModel.books[bookIndex].removeFromStringList(
                                field: field, index: index)
                            viewModel.markDirty(field: field, for: bookId)
                        }) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    if isEdited, let originalValue {
                        Text(originalValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func creatorListEditor(book: MetadataEditorViewModel.EditableBook) -> some View {
        let isDirty = viewModel.isDirty(field: "creators", for: book.id)
        let creators = viewModel.books.first { $0.id == book.id }?.creators ?? []
        let hasImports = viewModel.books.first { $0.id == book.id }?
            .importedItems["creators"]?.isEmpty == false
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Other Creators")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        hasImports ? Color.blue : isDirty ? Color.orange : .primary)
                if isDirty {
                    revertButton {
                        revertField(bookId: book.id, field: "creators") {
                            $0.creators = $0.originalMetadata.creators?.map { creator in
                                MetadataEditorViewModel.EditableCreator(
                                    name: creator.name ?? "",
                                    fileAs: creator.fileAs ?? "",
                                    role: creator.role ?? "",
                                    uuid: creator.uuid
                                )
                            } ?? []
                        }
                    }
                }
                Spacer()
                Button(action: {
                    guard let index = viewModel.books.firstIndex(where: { $0.id == book.id }) else {
                        return
                    }
                    viewModel.books[index].creators.append(
                        MetadataEditorViewModel.EditableCreator(
                            name: "", fileAs: "", role: "", uuid: nil
                        )
                    )
                    viewModel.markDirty(field: "creators", for: book.id)
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            ForEach(creators) { creator in
                HStack(spacing: 4) {
                    if viewModel.isImported(
                        field: "creators", value: creator.name, for: book.id)
                    {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                    }
                    TextField(
                        "Name",
                        text: creatorBinding(bookId: book.id, creatorId: creator.id, keyPath: \.name)
                    )
                    .textFieldStyle(.roundedBorder)

                    creatorRolePicker(bookId: book.id, creatorId: creator.id)

                    Button(action: {
                        guard
                            let bookIndex = viewModel.books.firstIndex(where: {
                                $0.id == book.id
                            })
                        else { return }
                        viewModel.books[bookIndex].creators.removeAll { $0.id == creator.id }
                        viewModel.markDirty(field: "creators", for: book.id)
                    }) {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func creatorBinding(
        bookId: String,
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
    private func creatorRolePicker(bookId: String, creatorId: UUID) -> some View {
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
                    text: creatorRoleBinding(bookId: bookId, creatorId: creatorId)
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

    private func creatorRoleBinding(bookId: String, creatorId: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.books.first { $0.id == bookId }?
                    .creators.first { $0.id == creatorId }?.role ?? ""
            },
            set: { newValue in
                guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId }),
                    let creatorIndex = viewModel.books[bookIndex].creators.firstIndex(where: {
                        $0.id == creatorId
                    })
                else { return }
                viewModel.books[bookIndex].creators[creatorIndex].role = newValue
                viewModel.markDirty(field: "creators", for: bookId)
            }
        )
    }

    @ViewBuilder
    private func seriesEditor(book: MetadataEditorViewModel.EditableBook) -> some View {
        let isDirty = viewModel.isDirty(field: "series", for: book.id)
        let seriesList = viewModel.books.first { $0.id == book.id }?.series ?? []
        let hasImports = viewModel.books.first { $0.id == book.id }?
            .importedItems["series"]?.isEmpty == false
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Series")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        hasImports ? Color.blue : isDirty ? Color.orange : .primary)
                if isDirty {
                    revertButton {
                        revertField(bookId: book.id, field: "series") {
                            $0.series = $0.originalMetadata.series?.map { s in
                                MetadataEditorViewModel.EditableSeries(
                                    name: s.name,
                                    position: s.position.map {
                                        $0.truncatingRemainder(dividingBy: 1) == 0
                                            ? String(Int($0)) : String($0)
                                    } ?? "",
                                    featured: s.featured == 1,
                                    uuid: s.uuid
                                )
                            } ?? []
                        }
                    }
                }
                Spacer()
                Button(action: {
                    guard let index = viewModel.books.firstIndex(where: { $0.id == book.id }) else {
                        return
                    }
                    viewModel.books[index].series.append(
                        MetadataEditorViewModel.EditableSeries(
                            name: "", position: "", featured: false, uuid: nil
                        )
                    )
                    viewModel.markDirty(field: "series", for: book.id)
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            ForEach(seriesList) { series in
                HStack(spacing: 4) {
                    if viewModel.isImported(
                        field: "series", value: series.name, for: book.id)
                    {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                    }
                    TextField(
                        "Series Name",
                        text: seriesBinding(bookId: book.id, seriesId: series.id, keyPath: \.name)
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "#",
                        text: seriesBinding(
                            bookId: book.id, seriesId: series.id, keyPath: \.position)
                    )
                    .textFieldStyle(.roundedBorder)
                    .border(
                        viewModel.seriesPositionHasError(bookId: book.id, seriesId: series.id)
                            ? Color.red : Color.clear, width: 2
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(maxWidth: 60)

                    Toggle(
                        "Featured",
                        isOn: Binding(
                            get: {
                                viewModel.books.first { $0.id == book.id }?
                                    .series.first { $0.id == series.id }?.featured ?? false
                            },
                            set: { newValue in
                                guard
                                    let bookIndex = viewModel.books.firstIndex(where: {
                                        $0.id == book.id
                                    }),
                                    let seriesIndex = viewModel.books[bookIndex].series
                                        .firstIndex(where: { $0.id == series.id })
                                else { return }
                                viewModel.books[bookIndex].series[seriesIndex].featured = newValue
                                viewModel.markDirty(field: "series", for: book.id)
                            }
                        )
                    )
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif

                    Button(action: {
                        guard
                            let bookIndex = viewModel.books.firstIndex(where: {
                                $0.id == book.id
                            })
                        else { return }
                        viewModel.books[bookIndex].series.removeAll { $0.id == series.id }
                        viewModel.markDirty(field: "series", for: book.id)
                    }) {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func seriesBinding(
        bookId: String,
        seriesId: UUID,
        keyPath: WritableKeyPath<MetadataEditorViewModel.EditableSeries, String>
    ) -> Binding<String> {
        Binding(
            get: {
                viewModel.books.first { $0.id == bookId }?
                    .series.first { $0.id == seriesId }?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId }),
                    let seriesIndex = viewModel.books[bookIndex].series.firstIndex(where: {
                        $0.id == seriesId
                    })
                else { return }
                viewModel.books[bookIndex].series[seriesIndex][keyPath: keyPath] = newValue
                viewModel.markDirty(field: "series", for: bookId)
            }
        )
    }

    // MARK: - Helpers

    private func updateField(
        bookId: String, field: String,
        mutation: (inout MetadataEditorViewModel.EditableBook) -> Void
    ) {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        let wasImported = viewModel.books[index].importedFields.contains(field)
        let beforeValue = scalarValue(field: field, book: viewModel.books[index])
        mutation(&viewModel.books[index])
        viewModel.markDirty(field: field, for: bookId)
        if wasImported && scalarValue(field: field, book: viewModel.books[index]) != beforeValue {
            viewModel.books[index].importedFields.remove(field)
        }
    }

    private func scalarValue(
        field: String, book: MetadataEditorViewModel.EditableBook
    ) -> String {
        switch field {
        case "title": return book.title
        case "subtitle": return book.subtitle
        case "description": return book.description
        case "language": return book.language
        case "publicationDate": return book.publicationDate
        case "rating": return book.rating
        default: return ""
        }
    }

    private func originalStringList(field: String, bookId: String) -> [String] {
        guard let book = viewModel.books.first(where: { $0.id == bookId }) else { return [] }
        let orig = book.originalMetadata
        switch field {
        case "authors": return orig.authors?.compactMap { $0.name } ?? []
        case "narrators": return orig.narrators?.compactMap { $0.name } ?? []
        case "tags": return orig.tags?.map { $0.name } ?? []
        default: return []
        }
    }

    private func originalScalarValue(field: String, bookId: String) -> String {
        guard let book = viewModel.books.first(where: { $0.id == bookId }) else { return "" }
        let orig = book.originalMetadata
        switch field {
        case "title": return orig.title
        case "subtitle": return orig.subtitle ?? ""
        case "description": return orig.description ?? ""
        case "language": return orig.language ?? ""
        case "publicationDate":
            return MetadataEditorViewModel.EditableBook.dateOnly(orig.publicationDate) ?? ""
        case "rating": return orig.rating.map { String($0) } ?? ""
        default: return ""
        }
    }

    private func revertField(
        bookId: String, field: String,
        mutation: (inout MetadataEditorViewModel.EditableBook) -> Void
    ) {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        mutation(&viewModel.books[index])
        viewModel.books[index].dirtyFields.remove(field)
        viewModel.books[index].importedFields.remove(field)
    }
}
