import SwiftUI

struct CollectionsTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel

    @State private var serverSelection: Set<Int> = []
    @State private var currentSelection: Set<Int> = []
    @State private var availableSelection: Set<Int> = []
    @State private var newCollectionName = ""
    @State private var showCreateCollectionAlert = false
    @State private var showDeleteCollectionConfirmation = false

    private var book: MetadataEditorViewModel.EditableBook? {
        viewModel.books.first { $0.id == bookId }
    }

    private var currentUuids: [String] {
        book?.collectionUuids ?? []
    }

    private var originalUuids: [String] {
        (book?.originalMetadata.collections?.compactMap(\.uuid) ?? []).filter {
            !viewModel.deletedCollectionUuids.contains($0)
        }
    }

    private var collectionNamesByUuid: [String: String] {
        var names = viewModel.libraryCollectionNamesByUuid
        for collection in book?.originalMetadata.collections ?? [] {
            if let uuid = collection.uuid {
                names[uuid] = collection.name
            }
        }
        return names
    }

    private var serverRows: [CollectionRow] {
        rows(for: originalUuids)
    }

    private var currentRows: [CollectionRow] {
        rows(for: currentUuids)
    }

    private var availableRows: [CollectionRow] {
        viewModel.libraryCollectionChoices.map { collection in
            CollectionRow(id: collection.id, uuid: collection.uuid, name: collection.name)
        }
    }

    private var selectedServerHasMissingCollection: Bool {
        selectedRows(in: serverRows, selection: serverSelection).contains {
            !currentUuids.contains($0.uuid)
        }
    }

    private var selectedAvailableHasMissingCollection: Bool {
        selectedRows(in: availableRows, selection: availableSelection).contains {
            !currentUuids.contains($0.uuid)
        }
    }

    private var selectedAvailableRows: [CollectionRow] {
        selectedRows(in: availableRows, selection: availableSelection)
    }

    private var selectedAvailableCollectionForDelete: CollectionRow? {
        guard selectedAvailableRows.count == 1 else { return nil }
        return selectedAvailableRows.first
    }

    var body: some View {
        GeometryReader { geo in
            let contentHeight = max(geo.size.height - 52, 100)

            VStack(alignment: .leading, spacing: 2) {
                MetadataColumnHeaders(
                    centerTitle: "Current Collections",
                    rightTitle: "Available Collections",
                    rightAccessory: AnyView(refreshCollectionsButton)
                )
                .frame(height: 22, alignment: .top)

                TransferColumnRow(
                    leftCanCopy: selectedServerHasMissingCollection,
                    leftHelp: "Copy selected server collections into current metadata",
                    leftAction: importSelectedServerCollections,
                    rightCanCopy: selectedAvailableHasMissingCollection,
                    rightHelp: "Copy selected available collections into current metadata",
                    rightAction: importSelectedAvailableCollections
                ) {
                    sourceColumn(
                        rows: serverRows,
                        selection: $serverSelection,
                        selectAction: selectServerCollection,
                        doubleClickAction: { importRows([$0]) }
                    ) {
                        Button("Use All") {
                            importRows(serverRows)
                        }
                        .disabled(!serverRows.contains { !currentUuids.contains($0.uuid) })
                    }
                } center: {
                    currentColumn
                } right: {
                    sourceColumn(
                        rows: availableRows,
                        selection: $availableSelection,
                        selectAction: selectAvailableCollection,
                        doubleClickAction: { importRows([$0]) }
                    ) {
                        Button("Create New Collection") {
                            newCollectionName = ""
                            showCreateCollectionAlert = true
                        }

                        Button("Delete Collection") {
                            showDeleteCollectionConfirmation = true
                        }
                        .foregroundStyle(
                            selectedAvailableCollectionForDelete == nil ? Color.secondary : Color.red
                        )
                        .disabled(selectedAvailableCollectionForDelete == nil)
                    }
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
        .alert("Create New Collection", isPresented: $showCreateCollectionAlert) {
            TextField("Collection Name", text: $newCollectionName)
            Button("Create") {
                Task { await createNewCollection() }
            }
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
            }
        } message: {
            Text("Create a new Storyteller collection.")
        }
        .confirmationDialog(
            "Delete Collection?",
            isPresented: $showDeleteCollectionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                Task { await deleteSelectedAvailableCollection() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let row = selectedAvailableCollectionForDelete {
                Text("\"\(row.name)\" will be deleted from the Storyteller server.")
            } else {
                Text("The selected collection will be deleted from the Storyteller server.")
            }
        }
        .task {
            await viewModel.refreshLibraryCollectionsFromServer()
        }
    }

    private var refreshCollectionsButton: some View {
        Button {
            Task { await viewModel.refreshLibraryCollectionsFromServer() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Refresh collections from Storyteller")
    }

    private var currentColumn: some View {
        VStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Button("Delete All") {
                    setCurrentCollections([])
                    currentSelection.removeAll()
                }
                .foregroundStyle(currentRows.isEmpty ? Color.secondary : Color.red)
                .disabled(currentRows.isEmpty)

                Button("Delete Selected (\(currentSelection.count))") {
                    deleteSelectedCurrentCollections()
                }
                .foregroundStyle(currentSelection.isEmpty ? Color.secondary : Color.red)
                .disabled(currentSelection.isEmpty)
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .center)

            Table(currentRows, selection: $currentSelection) {
                TableColumn("Name") { item in
                    TextField(
                        "Name",
                        text: Binding(get: { item.name }, set: { _ in })
                    )
                    .textFieldStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        selectCurrentCollection(item.id)
                    })
                }
            }
            .metadataEditorBoundary()
        }
    }

    private func sourceColumn(
        rows: [CollectionRow],
        selection: Binding<Set<Int>>,
        selectAction: @escaping (Int) -> Void,
        doubleClickAction: @escaping (CollectionRow) -> Void,
        @ViewBuilder toolbar: () -> some View
    ) -> some View {
        VStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                toolbar()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Table(rows, selection: selection) {
                TableColumn("Name") { item in
                    TextField(
                        "Name",
                        text: Binding(get: { item.name }, set: { _ in })
                    )
                    .textFieldStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        selectAction(item.id)
                    })
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        selection.wrappedValue = [item.id]
                        doubleClickAction(item)
                    })
                }
            }
            .metadataEditorBoundary()
        }
    }

    private func rows(for uuids: [String]) -> [CollectionRow] {
        uuids.enumerated().map { index, uuid in
            CollectionRow(id: index, uuid: uuid, name: collectionNamesByUuid[uuid] ?? uuid)
        }
    }

    private func selectedRows(in rows: [CollectionRow], selection: Set<Int>) -> [CollectionRow] {
        rows.filter { selection.contains($0.id) }
    }

    private func importSelectedServerCollections() {
        importRows(selectedRows(in: serverRows, selection: serverSelection))
    }

    private func importSelectedAvailableCollections() {
        importRows(selectedRows(in: availableRows, selection: availableSelection))
    }

    private func importRows(_ rows: [CollectionRow]) {
        var uuids = currentUuids
        for row in rows where !uuids.contains(row.uuid) {
            uuids.append(row.uuid)
        }
        setCurrentCollections(uuids)
    }

    private func deleteSelectedCurrentCollections() {
        let selectedUuids = Set(selectedRows(in: currentRows, selection: currentSelection).map(\.uuid))
        setCurrentCollections(currentUuids.filter { !selectedUuids.contains($0) })
        currentSelection.removeAll()
    }

    private func setCurrentCollections(_ uuids: [String]) {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        viewModel.books[index].collectionUuids = uuids
        viewModel.markDirty(field: "collections", for: bookId)
    }

    private func createNewCollection() async {
        guard let uuid = await viewModel.createCollection(named: newCollectionName) else {
            viewModel.saveError = "Could not create collection."
            return
        }
        newCollectionName = ""
        currentSelection.removeAll()
        serverSelection.removeAll()
        if let row = availableRows.first(where: { $0.uuid == uuid }) {
            availableSelection = [row.id]
        }
    }

    private func deleteSelectedAvailableCollection() async {
        guard let row = selectedAvailableCollectionForDelete else { return }
        guard await viewModel.deleteCollection(uuid: row.uuid) else {
            viewModel.saveError = "Could not delete collection \"\(row.name)\"."
            return
        }
        availableSelection.removeAll()
        serverSelection.removeAll()
        currentSelection.removeAll()
    }

    private func selectCurrentCollection(_ id: Int) {
        serverSelection.removeAll()
        availableSelection.removeAll()
        updateSelection(&currentSelection, id: id)
    }

    private func selectServerCollection(_ id: Int) {
        currentSelection.removeAll()
        availableSelection.removeAll()
        updateSelection(&serverSelection, id: id)
    }

    private func selectAvailableCollection(_ id: Int) {
        currentSelection.removeAll()
        serverSelection.removeAll()
        updateSelection(&availableSelection, id: id)
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

private struct CollectionRow: Identifiable, Hashable {
    let id: Int
    let uuid: String
    let name: String
}
