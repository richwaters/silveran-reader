import SwiftUI

struct OrganizationTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel

    @State private var editedTagSelection: Set<Int> = []
    @State private var serverTagSelection: Set<Int> = []
    @State private var hcTagSelection: Set<Int> = []
    @State private var hcSortOrder: [KeyPathComparator<IdentifiedTagWithCount>] = [
        KeyPathComparator(\.count, order: .reverse)
    ]

    private var editedTagRows: [IdentifiedString] {
        let list = viewModel.books.first { $0.id == bookId }?.tags ?? []
        return list.enumerated().map { i, value in
            IdentifiedString(
                id: i, value: value,
                isImported: viewModel.isImported(field: "tags", value: value, for: bookId)
            )
        }
    }

    private var serverTagRows: [IdentifiedString] {
        let original = viewModel.originalStringList(field: "tags", for: bookId)
        return original.enumerated().map { i, name in
            IdentifiedString(id: i, value: name, isImported: false)
        }
    }

    private var hcTagRows: [IdentifiedTagWithCount] {
        guard let tags = viewModel.hardcoverTagsWithCounts(for: bookId) else { return [] }
        let rows = tags.enumerated().map { i, tag in
            IdentifiedTagWithCount(id: i, name: tag.name, count: tag.count)
        }
        return rows.sorted(using: hcSortOrder)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Column 1: Edited tags
            VStack(alignment: .leading, spacing: 0) {
                Text("Metadata to save").font(.headline)
                    .padding([.horizontal, .top])

                HStack(spacing: 8) {
                    Button("Delete All") {
                        guard let idx = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        viewModel.books[idx].tags.removeAll()
                        viewModel.markDirty(field: "tags", for: bookId)
                        editedTagSelection.removeAll()
                    }
                    .controlSize(.small)
                    .foregroundStyle(.red)

                    Button(action: {
                        guard let idx = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        viewModel.books[idx].appendToStringList(field: "tags", value: "")
                        viewModel.markDirty(field: "tags", for: bookId)
                    }) {
                        Label("Add", systemImage: "plus.circle")
                    }
                    .controlSize(.small)
                    Spacer()
                    if !editedTagSelection.isEmpty {
                        Button("Delete Selected (\(editedTagSelection.count))") {
                            guard let idx = viewModel.books.firstIndex(where: { $0.id == bookId })
                            else { return }
                            viewModel.books[idx].removeFromStringList(
                                field: "tags", indices: IndexSet(editedTagSelection))
                            viewModel.markDirty(field: "tags", for: bookId)
                            editedTagSelection.removeAll()
                        }
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                }
                .padding([.horizontal, .top], 8)

                Table(editedTagRows, selection: $editedTagSelection) {
                    TableColumn("") { item in
                        if item.isImported {
                            Circle().fill(.blue).frame(width: 6, height: 6)
                        }
                    }
                    .width(12)

                    TableColumn("Tag") { item in
                        TextField(
                            "Tag",
                            text: Binding(
                                get: {
                                    let list = viewModel.books.first { $0.id == bookId }?.tags ?? []
                                    guard item.id < list.count else { return "" }
                                    return list[item.id]
                                },
                                set: { newValue in
                                    guard let idx = viewModel.books.firstIndex(where: { $0.id == bookId })
                                    else { return }
                                    viewModel.books[idx].updateStringList(
                                        field: "tags", index: item.id, value: newValue)
                                    viewModel.markDirty(field: "tags", for: bookId)
                                }
                            )
                        )
                        .textFieldStyle(.plain)
                    }
                }
                .border(
                    listFieldMatchColor(field: "tags", bookId: bookId, viewModel: viewModel),
                    width: 2
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding()
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Column 2: Storyteller Server tags
            VStack(alignment: .leading, spacing: 0) {
                Text("Storyteller Server")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding([.horizontal, .top])

                HStack(spacing: 8) {
                    if !serverTagRows.isEmpty {
                        Button("Import All") {
                            viewModel.importTags(serverTagRows.map(\.value), for: bookId)
                        }
                        .controlSize(.small)
                    }
                    Button(action: {
                        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        viewModel.books[index].tags =
                            viewModel.books[index].originalMetadata.tags?.map { $0.name } ?? []
                        viewModel.books[index].dirtyFields.remove("tags")
                        viewModel.books[index].importedFields.remove("tags")
                    }) {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .controlSize(.small)
                    .help("Replace edited tags with server tags")
                    Spacer()
                    if !serverTagSelection.isEmpty {
                        Button("Import Selected (\(serverTagSelection.count))") {
                            let names = serverTagSelection.compactMap { id in
                                serverTagRows.first { $0.id == id }?.value
                            }
                            viewModel.importTags(names, for: bookId)
                            serverTagSelection.removeAll()
                        }
                        .controlSize(.small)
                    }
                }
                .padding([.horizontal, .top], 8)

                if serverTagRows.isEmpty {
                    Text("(empty)")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                        .italic()
                        .padding()
                } else {
                    Table(serverTagRows, selection: $serverTagSelection) {
                        TableColumn("Tag") { item in
                            Text(item.value)
                                .font(.callout)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Column 3: Hardcover Import tags
            VStack(alignment: .leading, spacing: 0) {
                Text("Hardcover Import")
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .padding([.horizontal, .top])

                HStack(spacing: 8) {
                    if !hcTagRows.isEmpty {
                        Button("Import All") {
                            viewModel.importTags(hcTagRows.map(\.name), for: bookId, fromHardcover: true)
                        }
                        .controlSize(.small)

                        Button(action: {
                            viewModel.revertToHardcover(field: "tags", for: bookId)
                        }) {
                            Image(systemName: "arrow.uturn.backward.circle")
                        }
                        .controlSize(.small)
                        .help("Replace edited tags with Hardcover tags")
                    }
                    Spacer()
                    if !hcTagSelection.isEmpty {
                        Button("Import Selected (\(hcTagSelection.count))") {
                            let names = hcTagSelection.compactMap { id in
                                hcTagRows.first { $0.id == id }?.name
                            }
                            viewModel.importTags(names, for: bookId, fromHardcover: true)
                            hcTagSelection.removeAll()
                        }
                        .controlSize(.small)
                    }
                }
                .padding([.horizontal, .top], 8)

                if hcTagRows.isEmpty {
                    Text("--")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding()
                } else {
                    Table(hcTagRows, selection: $hcTagSelection, sortOrder: $hcSortOrder) {
                        TableColumn("Tag", value: \.name) { item in
                            Text(item.name)
                                .font(.callout)
                                .foregroundStyle(.blue)
                        }
                        TableColumn("Pop.", value: \.count) { item in
                            Text("\(item.count)")
                                .font(.callout)
                                .foregroundStyle(.blue.opacity(0.7))
                        }
                        .width(40)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - HC Series String List

extension MetadataEditorViewModel {
    func hardcoverSeriesList(for bookId: String) -> [String]? {
        guard let book = books.first(where: { $0.id == bookId }),
              let details = book.lastImportedDetails,
              book.lastImportedFields.contains("series"),
              !details.series.isEmpty else { return nil }
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
