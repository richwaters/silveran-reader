import SwiftUI

// MARK: - Two Column Layout

struct TwoColumnRow<Left: View, Right: View>: View {
    let left: Left
    let right: Right

    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            left
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
                .padding(.horizontal, 12)
            right
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Reference Values (right column)

struct ReferenceValues: View {
    let label: String
    let field: String
    let bookId: String
    let viewModel: MetadataEditorViewModel
    let revertToOriginal: () -> Void

    var body: some View {
        let original = viewModel.originalScalarValue(field: field, for: bookId)
        let hardcover = viewModel.hardcoverScalarValue(field: field, for: bookId)

        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.callout).foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    RevertButton(color: .white, help: "Revert to server value", action: revertToOriginal)
                    if !original.isEmpty {
                        Text(original)
                            .font(.callout)
                            .foregroundStyle(.white)
                    } else {
                        Text("(empty)")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.5))
                            .italic()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.callout).foregroundStyle(.clear)
                HStack(spacing: 4) {
                    if let hc = hardcover {
                        RevertButton(color: .blue, help: "Revert to Hardcover value") {
                            viewModel.revertToHardcover(field: field, for: bookId)
                        }
                        Text(hc)
                            .font(.callout)
                            .foregroundStyle(.blue)
                    } else {
                        Text("--")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ReferenceListValues: View {
    let field: String
    let bookId: String
    let viewModel: MetadataEditorViewModel
    let revertToOriginal: () -> Void

    var body: some View {
        let original = viewModel.originalStringList(field: field, for: bookId)
        let hardcover = viewModel.hardcoverStringList(field: field, for: bookId)

        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                RevertButton(color: .white, help: "Revert to server value", action: revertToOriginal)
                if original.isEmpty {
                    Text("(empty)")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                        .italic()
                } else {
                    ForEach(original, id: \.self) { item in
                        Text(item)
                            .font(.callout)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.horizontal, 8)
            VStack(alignment: .leading, spacing: 4) {
                if let hc = hardcover {
                    RevertButton(color: .blue, help: "Revert to Hardcover value") {
                        viewModel.revertToHardcover(field: field, for: bookId)
                    }
                    ForEach(hc, id: \.self) { item in
                        Text(item)
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

// MARK: - Revert Button

struct RevertButton: View {
    let color: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(color)
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - Field Match Color

@MainActor
func fieldMatchColor(
    field: String, bookId: String, viewModel: MetadataEditorViewModel
) -> Color {
    if viewModel.fieldHasError(field, for: bookId) { return .red }

    let current: String
    if let book = viewModel.books.first(where: { $0.id == bookId }) {
        switch field {
        case "title": current = book.title
        case "subtitle": current = book.subtitle
        case "description": current = book.description
        case "language": current = book.language
        case "publicationDate": current = book.publicationDate
        case "rating": current = book.rating
        default: current = ""
        }
    } else {
        return .clear
    }

    if let hc = viewModel.hardcoverScalarValue(field: field, for: bookId), current == hc {
        return .blue
    }

    let original = viewModel.originalScalarValue(field: field, for: bookId)
    if current == original {
        return .gray.opacity(0.3)
    }

    return .orange
}

@MainActor
func listFieldMatchColor(
    field: String, bookId: String, viewModel: MetadataEditorViewModel
) -> Color {
    guard let book = viewModel.books.first(where: { $0.id == bookId }) else { return .clear }
    let current = book.stringList(for: field)

    if let hc = viewModel.hardcoverStringList(field: field, for: bookId), current == hc {
        return .blue
    }

    let original = viewModel.originalStringList(field: field, for: bookId)
    if current == original {
        return .gray.opacity(0.3)
    }

    return .orange
}

// MARK: - Labeled Editable Field

struct LabeledEditableField: View {
    let label: String
    let field: String
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel
    let value: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("(empty)", text: value)
                .textFieldStyle(.roundedBorder)
                .border(
                    fieldMatchColor(field: field, bookId: bookId, viewModel: viewModel),
                    width: 2
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - String List Table

struct IdentifiedString: Identifiable {
    let id: Int
    let value: String
    let isImported: Bool
}

struct IdentifiedTagWithCount: Identifiable {
    let id: Int
    let name: String
    let count: Int
}

struct StringListTable: View {
    let label: String
    let field: String
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel
    var expandToFill: Bool = false
    var showHeader: Bool = true
    @State private var selection: Set<Int> = []

    private var items: [IdentifiedString] {
        let list = viewModel.books.first { $0.id == bookId }?.stringList(for: field) ?? []
        return list.enumerated().map { index, value in
            IdentifiedString(
                id: index,
                value: value,
                isImported: viewModel.isImported(field: field, value: value, for: bookId)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showHeader {
                HStack {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(fieldLabelColor)
                    Spacer()
                    Button(action: addItem) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }

                HStack(spacing: 8) {
                    Spacer()
                    if !selection.isEmpty {
                        Button("Delete Selected (\(selection.count))") {
                            deleteSelected()
                        }
                        .controlSize(.small)
                        .foregroundStyle(.red)
                    }
                }
            }

            Table(items, selection: $selection) {
                TableColumn("") { item in
                    if item.isImported {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                    }
                }
                .width(12)

                TableColumn("Value") { item in
                    TextField(
                        label,
                        text: Binding(
                            get: {
                                let list = viewModel.books.first { $0.id == bookId }?
                                    .stringList(for: field) ?? []
                                guard item.id < list.count else { return "" }
                                return list[item.id]
                            },
                            set: { newValue in
                                guard let bookIndex = viewModel.books.firstIndex(where: {
                                    $0.id == bookId
                                }) else { return }
                                viewModel.books[bookIndex].updateStringList(
                                    field: field, index: item.id, value: newValue)
                                viewModel.markDirty(field: field, for: bookId)
                            }
                        )
                    )
                    .textFieldStyle(.plain)
                }
            }
            .frame(height: expandToFill ? nil : min(CGFloat(max(items.count, 1)) * 28 + 28, 200))
            .frame(maxHeight: expandToFill ? .infinity : nil)
            .border(
                listFieldMatchColor(field: field, bookId: bookId, viewModel: viewModel),
                width: 2
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var fieldLabelColor: Color {
        listFieldMatchColor(field: field, bookId: bookId, viewModel: viewModel)
    }

    private func addItem() {
        guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        viewModel.books[bookIndex].appendToStringList(field: field, value: "")
        viewModel.markDirty(field: field, for: bookId)
    }

    private func deleteSelected() {
        guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        let indices = IndexSet(selection)
        viewModel.books[bookIndex].removeFromStringList(field: field, indices: indices)
        viewModel.markDirty(field: field, for: bookId)
        selection.removeAll()
    }
}

// MARK: - Word Diff

struct WordDiffView: View {
    let oldText: String
    let newText: String
    var baseColor: Color = .secondary

    var body: some View {
        let chunks = computeWordDiff(old: oldText, new: newText)
        let attributed = chunks.reduce(into: AttributedString()) { result, chunk in
            var part = AttributedString(chunk.text)
            switch chunk.kind {
            case .same:
                part.foregroundColor = baseColor
            case .added:
                part.foregroundColor = .green
                part.backgroundColor = .green.opacity(0.15)
            case .removed:
                part.foregroundColor = .red
                part.strikethroughStyle = .single
                part.backgroundColor = .red.opacity(0.15)
            }
            result.append(part)
        }
        Text(attributed)
            .font(.callout)
            .textSelection(.enabled)
    }

    enum ChunkKind { case same, added, removed }
    struct Chunk { let text: String; let kind: ChunkKind }

    private func computeWordDiff(old: String, new: String) -> [Chunk] {
        let oldWords = tokenize(old)
        let newWords = tokenize(new)

        let lcs = longestCommonSubsequence(oldWords, newWords)
        var chunks: [Chunk] = []
        var oi = 0, ni = 0, li = 0

        while oi < oldWords.count || ni < newWords.count {
            if li < lcs.count {
                while oi < oldWords.count && oldWords[oi] != lcs[li] {
                    chunks.append(Chunk(text: oldWords[oi], kind: .removed))
                    oi += 1
                }
                while ni < newWords.count && newWords[ni] != lcs[li] {
                    chunks.append(Chunk(text: newWords[ni], kind: .added))
                    ni += 1
                }
                if li < lcs.count {
                    chunks.append(Chunk(text: lcs[li], kind: .same))
                    oi += 1
                    ni += 1
                    li += 1
                }
            } else {
                while oi < oldWords.count {
                    chunks.append(Chunk(text: oldWords[oi], kind: .removed))
                    oi += 1
                }
                while ni < newWords.count {
                    chunks.append(Chunk(text: newWords[ni], kind: .added))
                    ni += 1
                }
            }
        }

        return chunks
    }

    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for char in text {
            if char.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }
}
