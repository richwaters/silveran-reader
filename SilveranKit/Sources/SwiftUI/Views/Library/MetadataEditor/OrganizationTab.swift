import SwiftUI

struct OrganizationTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel
    let openHardcoverImport: () -> Void

    @State private var editedTagSelection: Set<Int> = []
    @State private var serverTagSelection: Set<Int> = []
    @State private var hcTagSelection: Set<Int> = []
    @State private var hcSortOrder: [KeyPathComparator<IdentifiedTagWithCount>] = [
        KeyPathComparator(\.count, order: .reverse)
    ]
    @State private var showServerTagHelp = false

    private var editedTagRows: [IdentifiedString] {
        let list = currentTags
        return list.enumerated().map { i, value in
            IdentifiedString(
                id: i, value: value,
                isImported: viewModel.isImported(field: "tags", value: value, for: bookId),
                sourceIndex: i
            )
        }.sorted {
            $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending
        }
    }

    private var currentTags: [String] {
        viewModel.books.first { $0.id == bookId }?.tags ?? []
    }

    private var serverTags: [String] {
        viewModel.originalStringList(field: "tags", for: bookId)
    }

    private var serverTagRows: [IdentifiedServerTag] {
        let currentKeys = Set(serverTags.map { $0.lowercased() })
        let currentRows = serverTags.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let otherRows = viewModel.libraryTagNames.filter { !currentKeys.contains($0.lowercased()) }

        return (currentRows.map { (value: $0, isOnCurrentBook: true) }
            + otherRows.map { (value: $0, isOnCurrentBook: false) })
            .enumerated()
            .map { i, row in
                IdentifiedServerTag(
                    id: i,
                    value: row.value,
                    isOnCurrentBook: row.isOnCurrentBook
                )
            }
    }

    private var hcTagRows: [IdentifiedTagWithCount] {
        guard let tags = viewModel.hardcoverTagsWithCounts(for: bookId)
        else { return [] }
        let rows = tags.enumerated().map { i, tag in
            IdentifiedTagWithCount(id: i, name: tag.name, count: tag.count)
        }
        return rows.sorted(using: hcSortOrder)
    }

    private var hcTagNames: [String]? {
        guard viewModel.hardcoverTagsWithCounts(for: bookId) != nil else {
            return nil
        }
        return hcTagRows.map(\.name)
    }

    var body: some View {
        GeometryReader { geo in
            let headerHeight: CGFloat = 24
            let contentHeight = max(geo.size.height - headerHeight - 30, 100)

            VStack(alignment: .leading, spacing: 2) {
                MetadataColumnHeaders(centerTitle: "Current Tags")
                .frame(height: headerHeight, alignment: .top)

                TransferColumnRow(
                    leftCanCopy: selectedServerTagsContainMissingTag,
                    leftHelp: "Copy selected server tags into current metadata",
                    leftAction: importSelectedServerTags,
                    rightCanCopy: selectedHardcoverTagsContainMissingTag,
                    rightHelp: "Copy selected Hardcover tags into current metadata",
                    rightAction: importSelectedHardcoverTags
                ) {
                    serverTagsColumn
                } center: {
                    currentTagsColumn
                } right: {
                    hardcoverTagsColumn
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
        .onChange(of: editedTagSelection) { _, selection in
            guard !selection.isEmpty else { return }
            serverTagSelection.removeAll()
            hcTagSelection.removeAll()
        }
        .onChange(of: serverTagSelection) { _, selection in
            guard !selection.isEmpty else { return }
            editedTagSelection.removeAll()
            hcTagSelection.removeAll()
        }
        .onChange(of: hcTagSelection) { _, selection in
            guard !selection.isEmpty else { return }
            editedTagSelection.removeAll()
            serverTagSelection.removeAll()
        }
    }

    private var currentTagsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    Button("Delete All") {
                        guard let idx = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        viewModel.books[idx].tags.removeAll()
                        viewModel.markDirty(field: "tags", for: bookId)
                        editedTagSelection.removeAll()
                    }
                    .controlSize(.small)
                    .foregroundStyle(currentTags.isEmpty ? Color.secondary : Color.red)
                    .disabled(currentTags.isEmpty)

                    Button("Delete Selected (\(editedTagSelection.count))") {
                        deleteSelectedTags()
                    }
                    .controlSize(.small)
                    .foregroundStyle(editedTagSelection.isEmpty ? Color.secondary : Color.red)
                    .disabled(editedTagSelection.isEmpty)
                    .help("Delete selected tags")

                    Button(action: {
                        guard let idx = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        viewModel.books[idx].appendToStringList(field: "tags", value: "")
                        viewModel.markDirty(field: "tags", for: bookId)
                    }) {
                        Label("Add", systemImage: "plus.circle")
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30, alignment: .center)

            Table(editedTagRows, selection: $editedTagSelection) {
                TableColumn("Tag") { item in
                    HStack(spacing: 6) {
                        if item.isImported {
                            Circle().fill(.blue).frame(width: 6, height: 6)
                        }
                        TextField(
                            "Tag",
                            text: Binding(
                                get: {
                                    let list = viewModel.books.first { $0.id == bookId }?.tags ?? []
                                    guard let sourceIndex = item.sourceIndex, sourceIndex < list.count else { return "" }
                                    return list[sourceIndex]
                                },
                                set: { newValue in
                                    guard let idx = viewModel.books.firstIndex(where: { $0.id == bookId })
                                    else { return }
                                    guard let sourceIndex = item.sourceIndex else { return }
                                    viewModel.books[idx].updateStringList(
                                        field: "tags", index: sourceIndex, value: newValue)
                                    viewModel.markDirty(field: "tags", for: bookId)
                                }
                            )
                        )
                        .textFieldStyle(.plain)
                    }
                        .simultaneousGesture(TapGesture().onEnded {
                            editedTagSelection = [item.id]
                        })
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var serverTagsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceToolbar {
                Button("Use All") {
                    importServerTags(serverTags)
                }
                .disabled(!selectedTagsContainMissingTag(serverTags))

                Button {
                    showServerTagHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("About Storyteller tag colors")
                .popover(isPresented: $showServerTagHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Storyteller Tags")
                            .font(.headline)
                        Text("Bright tags are already on this book. Dimmer tags exist on other books in your library and can be added here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\"Use All\" will copy only the tags on this book over.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(width: 280, alignment: .leading)
                }
            }

            if serverTagRows.isEmpty {
                serverTagsTable
            } else {
                serverTagsTable
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var serverTagsTable: some View {
        Table(serverTagRows, selection: $serverTagSelection) {
            TableColumn("Tag") { item in
                TextField(
                    "Tag",
                    text: Binding(
                        get: { item.value },
                        set: { _ in }
                    )
                )
                .textFieldStyle(.plain)
                .foregroundStyle(item.isOnCurrentBook ? .primary : .secondary)
                .opacity(item.isOnCurrentBook ? 1 : 0.7)
                    .simultaneousGesture(TapGesture().onEnded {
                        selectServerTag(item.id)
                    })
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        serverTagSelection = [item.id]
                        importServerTags([item.value])
                    })
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var hardcoverTagsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceToolbar {
                Button("Use All") {
                    importHardcoverTags(hcTagNames ?? [])
                }
                .disabled(!selectedTagsContainMissingTag(hcTagNames ?? []))
            }

            if hcTagRows.isEmpty {
                ImportHardcoverDataPlaceholder(action: openHardcoverImport)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .offset(y: -15)
            } else {
                Table(hcTagRows, selection: $hcTagSelection, sortOrder: $hcSortOrder) {
                    TableColumn("Tag", value: \.name) { item in
                        TextField(
                            "Tag",
                            text: Binding(
                                get: { item.name },
                                set: { _ in }
                            )
                        )
                        .textFieldStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                selectHardcoverTag(item.id)
                            })
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                hcTagSelection = [item.id]
                                importHardcoverTags([item.name])
                            })
                    }
                    TableColumn("Popularity", value: \.count) { item in
                        Text("\(item.count)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .width(86)
                }
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sourceToolbar<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Spacer()
            content()
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 30, alignment: .center)
    }

    private var selectedServerTagsContainMissingTag: Bool {
        selectedTagsContainMissingTag(
            serverTagSelection.compactMap { id in
                serverTagRows.first { $0.id == id }?.value
            }
        )
    }

    private var selectedHardcoverTagsContainMissingTag: Bool {
        selectedTagsContainMissingTag(
            hcTagSelection.compactMap { id in
                hcTagRows.first { $0.id == id }?.name
            }
        )
    }

    private func selectedTagsContainMissingTag(_ tags: [String]) -> Bool {
        guard !tags.isEmpty else { return false }
        let currentKeys = Set(currentTags.map { $0.lowercased() })
        return tags.contains { !currentKeys.contains($0.lowercased()) }
    }

    private func importSelectedServerTags() {
        let names = serverTagSelection.compactMap { id in
            serverTagRows.first { $0.id == id }?.value
        }
        importServerTags(names)
        serverTagSelection.removeAll()
    }

    private func importSelectedHardcoverTags() {
        let names = hcTagSelection.compactMap { id in
            hcTagRows.first { $0.id == id }?.name
        }
        importHardcoverTags(names)
        hcTagSelection.removeAll()
    }

    private func importServerTags(_ names: [String]) {
        viewModel.importTags(names, for: bookId)
    }

    private func importHardcoverTags(_ names: [String]) {
        viewModel.importTags(names, for: bookId, fromHardcover: true)
    }

    private func deleteSelectedTags() {
        guard let idx = viewModel.books.firstIndex(where: { $0.id == bookId })
        else { return }
        let sourceIndices = editedTagSelection.compactMap { id in
            editedTagRows.first { $0.id == id }?.sourceIndex
        }
        viewModel.books[idx].removeFromStringList(
            field: "tags", indices: IndexSet(sourceIndices))
        viewModel.markDirty(field: "tags", for: bookId)
        editedTagSelection.removeAll()
    }

    private func selectServerTag(_ id: Int) {
        editedTagSelection.removeAll()
        hcTagSelection.removeAll()
        updateSelection(&serverTagSelection, id: id)
    }

    private func selectHardcoverTag(_ id: Int) {
        editedTagSelection.removeAll()
        serverTagSelection.removeAll()
        updateSelection(&hcTagSelection, id: id)
    }

    private func updateSelection(_ selection: inout Set<Int>, id: Int) {
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
            return
        }
        #endif
        selection = [id]
    }
}

// MARK: - HC Series String List

extension MetadataEditorViewModel {
    func hardcoverSeriesList(for bookId: String) -> [String]? {
        guard let book = books.first(where: { $0.id == bookId }),
              let details = book.hardcoverImports[.text],
              book.hardcoverImportFields[.text]?.contains("series") == true,
              !details.series.isEmpty
        else { return nil }
        return details.series.map { s in
            if let pos = s.position {
                let posStr = pos.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(pos)) : String(pos)
                return "\(s.name) #\(posStr)"
            }
            return s.name
        }
    }
}
