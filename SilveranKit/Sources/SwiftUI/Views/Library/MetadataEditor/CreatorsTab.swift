import SwiftUI

struct CreatorsTab: View {
    enum CreatorScope {
        case authors
        case narrators
        case otherCreators

        var title: String {
            switch self {
            case .authors: "Authors"
            case .narrators: "Narrators"
            case .otherCreators: "Other Creators"
            }
        }

        var field: String {
            switch self {
            case .authors: "authors"
            case .narrators: "narrators"
            case .otherCreators: "creators"
            }
        }
    }

    private struct CreatorSourceRow: Identifiable {
        let id: Int
        let name: String
        let role: String

        var displayName: String {
            role.isEmpty ? name : "\(name) - \(role)"
        }

        var key: String {
            "\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }
    }

    private struct CurrentCreatorRow: Identifiable {
        let id: Int
        let name: String
        let role: String
        let isImported: Bool
        let sourceIndex: Int

        var key: String {
            "\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }
    }

    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel
    let scope: CreatorScope
    let openHardcoverImport: () -> Void

    @State private var currentSelection: Set<Int> = []
    @State private var serverSelection: Set<Int> = []
    @State private var hardcoverSelection: Set<Int> = []

    var body: some View {
        GeometryReader { geo in
            let contentHeight = max(geo.size.height - 52, 100)
            let sourceWeight: CGFloat = 1
            let currentWeight: CGFloat = 1

            VStack(alignment: .leading, spacing: 2) {
                MetadataColumnHeaders(
                    leftWeight: sourceWeight,
                    centerWeight: currentWeight,
                    rightWeight: sourceWeight,
                    centerTitle: "Current \(scope.title)"
                )
                    .frame(height: 22, alignment: .top)

                TransferColumnRow(
                    leftWeight: sourceWeight,
                    centerWeight: currentWeight,
                    rightWeight: sourceWeight,
                    leftCanCopy: selectedServerRowsContainMissingCreator,
                    leftHelp: "Copy selected server \(scope.title.lowercased()) into current metadata",
                    leftAction: importSelectedServerRows,
                    rightCanCopy: selectedHardcoverRowsContainMissingCreator,
                    rightHelp: "Copy selected Hardcover \(scope.title.lowercased()) into current metadata",
                    rightAction: importSelectedHardcoverRows
                ) {
                    sourceColumn(
                        rows: serverRows,
                        selection: $serverSelection,
                        emptyText: nil,
                        useAllAction: { importRows(serverRows) },
                        selectAction: selectServerRow,
                        doubleClickAction: { row in importRows([row]) }
                    )
                } center: {
                    currentColumn
                } right: {
                    sourceColumn(
                        rows: hardcoverRows,
                        selection: $hardcoverSelection,
                        emptyText: "Import Hardcover Data",
                        useAllAction: { importRows(hardcoverRows, fromHardcover: true) },
                        selectAction: selectHardcoverRow,
                        doubleClickAction: { row in importRows([row], fromHardcover: true) }
                    )
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
        .onChange(of: currentSelection) { _, selection in
            guard !selection.isEmpty else { return }
            serverSelection.removeAll()
            hardcoverSelection.removeAll()
        }
        .onChange(of: serverSelection) { _, selection in
            guard !selection.isEmpty else { return }
            currentSelection.removeAll()
            hardcoverSelection.removeAll()
        }
        .onChange(of: hardcoverSelection) { _, selection in
            guard !selection.isEmpty else { return }
            currentSelection.removeAll()
            serverSelection.removeAll()
        }
    }

    private var currentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                Button("Delete All") {
                    deleteAllCurrentRows()
                }
                .controlSize(.small)
                .foregroundStyle(currentRowsAreEmpty ? Color.secondary : Color.red)
                .disabled(currentRowsAreEmpty)

                Button("Delete Selected (\(currentSelection.count))") {
                    deleteSelectedCurrentRows()
                }
                .controlSize(.small)
                .foregroundStyle(currentSelection.isEmpty ? Color.secondary : Color.red)
                .disabled(currentSelection.isEmpty)
                .help("Delete selected \(scope.title.lowercased())")

                Button(action: addCurrentRow) {
                    Label("Add", systemImage: "plus.circle")
                }
                .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 30, alignment: .center)

            if scope == .otherCreators {
                Table(currentCreatorRows, selection: $currentSelection) {
                    TableColumn("Name") { item in
                        HStack(spacing: 6) {
                            if item.isImported {
                                Circle().fill(.blue).frame(width: 6, height: 6)
                            }
                            TextField(
                                "Name",
                                text: creatorBinding(sourceIndex: item.sourceIndex, keyPath: \.name)
                            )
                            .textFieldStyle(.plain)
                        }
                            .simultaneousGesture(TapGesture().onEnded {
                            currentSelection = [item.id]
                        })
                    }
                    .width(170)

                    TableColumn("Role") { item in
                        MarcRelatorRoleEditor(
                            role: creatorBinding(sourceIndex: item.sourceIndex, keyPath: \.role)
                        )
                        .simultaneousGesture(TapGesture().onEnded {
                            currentSelection = [item.id]
                        })
                    }
                    .width(50)
                }
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Table(currentStringRows, selection: $currentSelection) {
                    TableColumn("Name") { item in
                        HStack(spacing: 6) {
                            if item.isImported {
                                Circle().fill(.blue).frame(width: 6, height: 6)
                            }
                            TextField(
                                scope.title,
                                text: stringBinding(sourceIndex: item.sourceIndex ?? item.id)
                            )
                            .textFieldStyle(.plain)
                        }
                            .simultaneousGesture(TapGesture().onEnded {
                                currentSelection = [item.id]
                            })
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sourceColumn(
        rows: [CreatorSourceRow],
        selection: Binding<Set<Int>>,
        emptyText: String?,
        useAllAction: @escaping () -> Void,
        selectAction: @escaping (Int) -> Void,
        doubleClickAction: @escaping (CreatorSourceRow) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceToolbar {
                Button("Use All", action: useAllAction)
                    .disabled(!rowsContainMissingCreator(rows))
            }

            if rows.isEmpty {
                if let emptyText {
                    Group {
                        if emptyText == "Import Hardcover Data" {
                            ImportHardcoverDataPlaceholder(action: openHardcoverImport)
                        } else {
                            EmptyTablePlaceholder(text: emptyText)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .offset(y: emptyText == "Import Hardcover Data" ? -15 : 0)
                } else {
                    sourceRowsTable(
                        rows: rows,
                        selection: selection,
                        selectAction: selectAction,
                        doubleClickAction: doubleClickAction
                    )
                }
            } else {
                sourceRowsTable(
                    rows: rows,
                    selection: selection,
                    selectAction: selectAction,
                    doubleClickAction: doubleClickAction
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sourceRowsTable(
        rows: [CreatorSourceRow],
        selection: Binding<Set<Int>>,
        selectAction: @escaping (Int) -> Void,
        doubleClickAction: @escaping (CreatorSourceRow) -> Void
    ) -> some View {
        Group {
            if scope == .otherCreators {
                Table(rows, selection: selection) {
                    TableColumn("Name") { item in
                        sourceCell(item.name, item: item, selection: selection, selectAction: selectAction, doubleClickAction: doubleClickAction)
                    }
                    .width(170)

                    TableColumn("Role") { item in
                        sourceCell(roleDisplayName(item.role), item: item, selection: selection, selectAction: selectAction, doubleClickAction: doubleClickAction)
                    }
                    .width(50)
                }
            } else {
                Table(rows, selection: selection) {
                    TableColumn("Name") { item in
                        sourceCell(item.displayName, item: item, selection: selection, selectAction: selectAction, doubleClickAction: doubleClickAction)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sourceCell(
        _ value: String,
        item: CreatorSourceRow,
        selection: Binding<Set<Int>>,
        selectAction: @escaping (Int) -> Void,
        doubleClickAction: @escaping (CreatorSourceRow) -> Void
    ) -> some View {
        TextField(
            "Value",
            text: Binding(
                get: { value },
                set: { _ in }
            )
        )
        .textFieldStyle(.plain)
        .onTapGesture {
            selectAction(item.id)
        }
        .onTapGesture(count: 2) {
            selection.wrappedValue = [item.id]
            doubleClickAction(item)
        }
    }

    private func roleDisplayName(_ role: String) -> String {
        role
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

    private var currentStringRows: [IdentifiedString] {
        currentStrings.enumerated().map { i, value in
            IdentifiedString(
                id: i,
                value: value,
                isImported: viewModel.isImported(field: scope.field, value: value, for: bookId),
                sourceIndex: i
            )
        }
        .sorted {
            $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending
        }
    }

    private var currentCreatorRows: [CurrentCreatorRow] {
        currentCreators.enumerated().map { i, creator in
            CurrentCreatorRow(
                id: i,
                name: creator.name,
                role: creator.role,
                isImported: viewModel.isImported(field: "creators", value: creator.name, for: bookId),
                sourceIndex: i
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var currentStrings: [String] {
        viewModel.books.first { $0.id == bookId }?.stringList(for: scope.field) ?? []
    }

    private var currentCreators: [MetadataEditorViewModel.EditableCreator] {
        viewModel.books.first { $0.id == bookId }?.creators ?? []
    }

    private var currentRowsAreEmpty: Bool {
        switch scope {
        case .authors, .narrators:
            currentStrings.isEmpty
        case .otherCreators:
            currentCreators.isEmpty
        }
    }

    private var serverRows: [CreatorSourceRow] {
        switch scope {
        case .authors, .narrators:
            return sourceRows(from: viewModel.originalStringList(field: scope.field, for: bookId))
        case .otherCreators:
            let creators = viewModel.books.first { $0.id == bookId }?.originalMetadata.creators ?? []
            return sourceRows(from: creators.map {
                (name: $0.name ?? "", role: $0.role ?? "")
            })
        }
    }

    private var hardcoverRows: [CreatorSourceRow] {
        switch scope {
        case .authors, .narrators:
            return sourceRows(from: viewModel.hardcoverStringList(field: scope.field, for: bookId) ?? [])
        case .otherCreators:
            guard let book = viewModel.books.first(where: { $0.id == bookId }),
                  let details = book.lastImportedDetails,
                  book.lastImportedFields.contains("creators") else { return [] }
            return sourceRows(from: details.creators.map { (name: $0.name, role: $0.role) })
        }
    }

    private func sourceRows(from values: [String]) -> [CreatorSourceRow] {
        sourceRows(from: values.map { (name: $0, role: "") })
    }

    private func sourceRows(from values: [(name: String, role: String)]) -> [CreatorSourceRow] {
        values
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { i, value in
                CreatorSourceRow(id: i, name: value.name, role: value.role)
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var selectedServerRowsContainMissingCreator: Bool {
        rowsContainMissingCreator(
            serverSelection.compactMap { id in serverRows.first { $0.id == id } }
        )
    }

    private var selectedHardcoverRowsContainMissingCreator: Bool {
        rowsContainMissingCreator(
            hardcoverSelection.compactMap { id in hardcoverRows.first { $0.id == id } }
        )
    }

    private func rowsContainMissingCreator(_ rows: [CreatorSourceRow]) -> Bool {
        guard !rows.isEmpty else { return false }
        let currentKeys = Set(currentCreatorKeys)
        return rows.contains { !currentKeys.contains($0.key) }
    }

    private var currentCreatorKeys: [String] {
        switch scope {
        case .authors, .narrators:
            return currentStrings.map {
                "\($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|"
            }
        case .otherCreators:
            return currentCreatorRows.map(\.key)
        }
    }

    private func importSelectedServerRows() {
        importRows(serverSelection.compactMap { id in serverRows.first { $0.id == id } })
        serverSelection.removeAll()
    }

    private func importSelectedHardcoverRows() {
        importRows(
            hardcoverSelection.compactMap { id in hardcoverRows.first { $0.id == id } },
            fromHardcover: true
        )
        hardcoverSelection.removeAll()
    }

    private func importRows(_ rows: [CreatorSourceRow], fromHardcover: Bool = false) {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        var changed = false
        var imported = Set<String>()

        switch scope {
        case .authors:
            changed = appendStrings(rows.map(\.name), to: &viewModel.books[index].authors)
            imported = Set(rows.map(\.name))
        case .narrators:
            changed = appendStrings(rows.map(\.name), to: &viewModel.books[index].narrators)
            imported = Set(rows.map(\.name))
        case .otherCreators:
            var seen = Set(currentCreatorKeys)
            for row in rows where !seen.contains(row.key) {
                seen.insert(row.key)
                viewModel.books[index].creators.append(
                    MetadataEditorViewModel.EditableCreator(
                        name: row.name,
                        fileAs: "",
                        role: row.role,
                        uuid: nil
                    )
                )
                imported.insert(row.name)
                changed = true
            }
        }

        guard changed else { return }
        if fromHardcover {
            viewModel.books[index].importedItems[scope.field, default: []].formUnion(imported)
        }
        viewModel.markDirty(field: scope.field, for: bookId)
    }

    private func appendStrings(_ values: [String], to list: inout [String]) -> Bool {
        var seen = Set(list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var changed = false
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            list.append(value)
            changed = true
        }
        return changed
    }

    private func addCurrentRow() {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        switch scope {
        case .authors, .narrators:
            viewModel.books[index].appendToStringList(field: scope.field, value: "")
        case .otherCreators:
            viewModel.books[index].creators.append(
                MetadataEditorViewModel.EditableCreator(
                    name: "",
                    fileAs: "",
                    role: "",
                    uuid: nil
                )
            )
        }
        viewModel.markDirty(field: scope.field, for: bookId)
    }

    private func deleteAllCurrentRows() {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        switch scope {
        case .authors:
            viewModel.books[index].authors.removeAll()
        case .narrators:
            viewModel.books[index].narrators.removeAll()
        case .otherCreators:
            viewModel.books[index].creators.removeAll()
        }
        viewModel.markDirty(field: scope.field, for: bookId)
        currentSelection.removeAll()
    }

    private func deleteSelectedCurrentRows() {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        let sourceIndices: [Int]
        if scope == .otherCreators {
            sourceIndices = currentSelection.compactMap { id in
                currentCreatorRows.first { $0.id == id }?.sourceIndex
            }
        } else {
            sourceIndices = currentSelection.compactMap { id in
                currentStringRows.first { $0.id == id }?.sourceIndex
            }
        }

        for sourceIndex in sourceIndices.sorted(by: >) {
            switch scope {
            case .authors, .narrators:
                viewModel.books[index].removeFromStringList(field: scope.field, index: sourceIndex)
            case .otherCreators:
                guard sourceIndex < viewModel.books[index].creators.count else { continue }
                viewModel.books[index].creators.remove(at: sourceIndex)
            }
        }
        viewModel.markDirty(field: scope.field, for: bookId)
        currentSelection.removeAll()
    }

    private func stringBinding(sourceIndex: Int) -> Binding<String> {
        Binding(
            get: {
                let list = viewModel.books.first { $0.id == bookId }?.stringList(for: scope.field) ?? []
                guard sourceIndex < list.count else { return "" }
                return list[sourceIndex]
            },
            set: { newValue in
                guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
                viewModel.books[index].updateStringList(
                    field: scope.field,
                    index: sourceIndex,
                    value: newValue
                )
                viewModel.markDirty(field: scope.field, for: bookId)
            }
        )
    }

    private func creatorBinding(
        sourceIndex: Int,
        keyPath: WritableKeyPath<MetadataEditorViewModel.EditableCreator, String>
    ) -> Binding<String> {
        Binding(
            get: {
                let creators = viewModel.books.first { $0.id == bookId }?.creators ?? []
                guard sourceIndex < creators.count else { return "" }
                return creators[sourceIndex][keyPath: keyPath]
            },
            set: { newValue in
                guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId }),
                      sourceIndex < viewModel.books[bookIndex].creators.count else { return }
                viewModel.books[bookIndex].creators[sourceIndex][keyPath: keyPath] = newValue
                viewModel.markDirty(field: "creators", for: bookId)
            }
        )
    }

    private func selectServerRow(_ id: Int) {
        currentSelection.removeAll()
        hardcoverSelection.removeAll()
        updateSelection(&serverSelection, id: id)
    }

    private func selectHardcoverRow(_ id: Int) {
        currentSelection.removeAll()
        serverSelection.removeAll()
        updateSelection(&hardcoverSelection, id: id)
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
