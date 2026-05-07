import SwiftUI

// MARK: - Shared Boundaries

extension View {
    func metadataEditorBoundary(cornerRadius: CGFloat = 6) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 0.75)
        }
    }

    func metadataEditorFieldBoundary(cornerRadius: CGFloat = 6) -> some View {
        padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .metadataEditorBoundary(cornerRadius: cornerRadius)
    }
}

// MARK: - Column Layouts

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

struct ThreeColumnRow<Left: View, Center: View, Right: View>: View {
    let left: Left
    let center: Center
    let right: Right

    init(
        @ViewBuilder left: () -> Left,
        @ViewBuilder center: () -> Center,
        @ViewBuilder right: () -> Right
    ) {
        self.left = left()
        self.center = center()
        self.right = right()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            left
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
                .padding(.horizontal, 12)
            center
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
                .padding(.horizontal, 12)
            right
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TransferColumnRow<Left: View, Center: View, Right: View>: View {
    let left: Left
    let leftWeight: CGFloat
    let leftCanCopy: Bool
    let leftHelp: String
    let leftAction: () -> Void
    let center: Center
    let centerWeight: CGFloat
    let rightCanCopy: Bool
    let rightHelp: String
    let rightAction: () -> Void
    let right: Right
    let rightWeight: CGFloat
    let leftArrowFooter: AnyView?
    let rightArrowFooter: AnyView?
    let arrowYOffset: CGFloat

    init(
        leftWeight: CGFloat = 1,
        centerWeight: CGFloat = 1,
        rightWeight: CGFloat = 1,
        leftCanCopy: Bool,
        leftHelp: String,
        leftAction: @escaping () -> Void,
        rightCanCopy: Bool,
        rightHelp: String,
        rightAction: @escaping () -> Void,
        leftArrowFooter: AnyView? = nil,
        rightArrowFooter: AnyView? = nil,
        arrowYOffset: CGFloat = 0,
        @ViewBuilder left: () -> Left,
        @ViewBuilder center: () -> Center,
        @ViewBuilder right: () -> Right
    ) {
        self.left = left()
        self.leftWeight = leftWeight
        self.leftCanCopy = leftCanCopy
        self.leftHelp = leftHelp
        self.leftAction = leftAction
        self.center = center()
        self.centerWeight = centerWeight
        self.rightCanCopy = rightCanCopy
        self.rightHelp = rightHelp
        self.rightAction = rightAction
        self.right = right()
        self.rightWeight = rightWeight
        self.leftArrowFooter = leftArrowFooter
        self.rightArrowFooter = rightArrowFooter
        self.arrowYOffset = arrowYOffset
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let arrowWidth: CGFloat = 34
            let columnWidth = max(geo.size.width - arrowWidth * 2 - spacing * 4, 0)
            let totalWeight = max(leftWeight + centerWeight + rightWeight, 0.1)
            let leftWidth = columnWidth * leftWeight / totalWeight
            let centerWidth = columnWidth * centerWeight / totalWeight
            let rightWidth = columnWidth * rightWeight / totalWeight

            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: spacing) {
                    left
                        .frame(width: leftWidth, alignment: .leading)

                    SourceCopyButton(
                        direction: .fromLeft,
                        isEnabled: leftCanCopy,
                        help: leftCanCopy ? leftHelp : "Already matches",
                        action: leftAction
                    )
                    .frame(width: arrowWidth, alignment: .center)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .offset(y: arrowYOffset)

                    center
                        .frame(width: centerWidth, alignment: .leading)

                    SourceCopyButton(
                        direction: .fromRight,
                        isEnabled: rightCanCopy,
                        help: rightCanCopy ? rightHelp : "Already matches",
                        action: rightAction
                    )
                    .frame(width: arrowWidth, alignment: .center)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .offset(y: arrowYOffset)

                    right
                        .frame(width: rightWidth, alignment: .leading)
                }

                if let leftArrowFooter {
                    leftArrowFooter
                        .position(
                            x: leftWidth + spacing + arrowWidth / 2,
                            y: geo.size.height - 18
                        )
                }

                if let rightArrowFooter {
                    rightArrowFooter
                        .position(
                            x: leftWidth + arrowWidth + centerWidth + spacing * 3 + arrowWidth / 2,
                            y: geo.size.height - 18
                        )
                }
            }
        }
    }
}

struct MetadataColumnHeaders: View {
    let leftWeight: CGFloat
    let centerWeight: CGFloat
    let rightWeight: CGFloat
    let leftTitle: String
    let centerTitle: String
    let rightTitle: String
    let leftAccessory: AnyView?
    let centerAccessory: AnyView?
    let rightAccessory: AnyView?

    init(
        leftWeight: CGFloat = 1,
        centerWeight: CGFloat = 1,
        rightWeight: CGFloat = 1,
        leftTitle: String = "Storyteller Server",
        centerTitle: String = "Current Metadata",
        rightTitle: String = "Hardcover Import",
        leftAccessory: AnyView? = nil,
        centerAccessory: AnyView? = nil,
        rightAccessory: AnyView? = nil
    ) {
        self.leftWeight = leftWeight
        self.centerWeight = centerWeight
        self.rightWeight = rightWeight
        self.leftTitle = leftTitle
        self.centerTitle = centerTitle
        self.rightTitle = rightTitle
        self.leftAccessory = leftAccessory
        self.centerAccessory = centerAccessory
        self.rightAccessory = rightAccessory
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let arrowWidth: CGFloat = 34
            let columnWidth = max(geo.size.width - arrowWidth * 2 - spacing * 4, 0)
            let totalWeight = max(leftWeight + centerWeight + rightWeight, 0.1)
            let leftWidth = columnWidth * leftWeight / totalWeight
            let centerWidth = columnWidth * centerWeight / totalWeight
            let rightWidth = columnWidth * rightWeight / totalWeight

            HStack(alignment: .top, spacing: spacing) {
                header(title: leftTitle, accessory: leftAccessory)
                    .frame(width: leftWidth, alignment: .center)
                Color.clear.frame(width: arrowWidth)
                header(title: centerTitle, accessory: centerAccessory)
                    .frame(width: centerWidth, alignment: .center)
                Color.clear.frame(width: arrowWidth)
                header(title: rightTitle, accessory: rightAccessory)
                    .frame(width: rightWidth, alignment: .center)
            }
        }
    }

    private func header(title: String, accessory: AnyView?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
            accessory
        }
    }
}

struct MetadataColumnAccessoryRow: View {
    let leftWeight: CGFloat
    let centerWeight: CGFloat
    let rightWeight: CGFloat
    let leftAccessory: AnyView?
    let centerAccessory: AnyView?
    let rightAccessory: AnyView?

    init(
        leftWeight: CGFloat = 1,
        centerWeight: CGFloat = 1,
        rightWeight: CGFloat = 1,
        leftAccessory: AnyView? = nil,
        centerAccessory: AnyView? = nil,
        rightAccessory: AnyView? = nil
    ) {
        self.leftWeight = leftWeight
        self.centerWeight = centerWeight
        self.rightWeight = rightWeight
        self.leftAccessory = leftAccessory
        self.centerAccessory = centerAccessory
        self.rightAccessory = rightAccessory
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let arrowWidth: CGFloat = 34
            let columnWidth = max(geo.size.width - arrowWidth * 2 - spacing * 4, 0)
            let totalWeight = max(leftWeight + centerWeight + rightWeight, 0.1)
            let leftWidth = columnWidth * leftWeight / totalWeight
            let centerWidth = columnWidth * centerWeight / totalWeight
            let rightWidth = columnWidth * rightWeight / totalWeight

            HStack(alignment: .center, spacing: spacing) {
                accessorySlot(leftAccessory)
                    .frame(width: leftWidth)
                Color.clear.frame(width: arrowWidth)
                accessorySlot(centerAccessory)
                    .frame(width: centerWidth)
                Color.clear.frame(width: arrowWidth)
                accessorySlot(rightAccessory)
                    .frame(width: rightWidth)
            }
        }
    }

    private func accessorySlot(_ accessory: AnyView?) -> some View {
        HStack {
            if let accessory {
                accessory
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct EmptyTablePlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct ImportHardcoverDataLink: View {
    let action: () -> Void

    var body: some View {
        Button("Import Hardcover Data", action: action)
            .buttonStyle(.link)
            .font(.callout.weight(.semibold))
    }
}

struct ImportHardcoverDataPlaceholder: View {
    let action: () -> Void

    var body: some View {
        ImportHardcoverDataLink(action: action)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Source Values

struct SourceCopyButton: View {
    enum Direction {
        case fromLeft
        case fromRight

        var systemName: String {
            switch self {
            case .fromLeft: return "arrow.right.circle.fill"
            case .fromRight: return "arrow.left.circle.fill"
            }
        }
    }

    let direction: Direction
    let isEnabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: direction.systemName)
                .font(.title.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.blue : Color.secondary.opacity(0.45))
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(help)
    }
}

struct SourceScalarValue: View {
    let label: String
    let value: String?
    let currentValue: String
    var onImportHardcover: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            if let value {
                if value.isEmpty {
                    Text("(empty)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text(value)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            } else {
                if let onImportHardcover {
                    ImportHardcoverDataLink(action: onImportHardcover)
                } else {
                    Text("--")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .metadataEditorFieldBoundary()
    }
}

struct SourceListValues: View {
    let values: [String]?
    let currentValues: [String]
    var compareAsSet = false
    var onImportHardcover: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let values {
                if values.isEmpty {
                    Text("(empty)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(values, id: \.self) { item in
                        Text(item)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                }
            } else {
                if let onImportHardcover {
                    ImportHardcoverDataLink(action: onImportHardcover)
                } else {
                    Text("--")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
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
        }
        .metadataEditorFieldBoundary()
    }
}

// MARK: - String List Table

struct IdentifiedString: Identifiable {
    let id: Int
    let value: String
    let isImported: Bool
    var sourceIndex: Int? = nil
}

struct IdentifiedServerTag: Identifiable {
    let id: Int
    let value: String
    let isOnCurrentBook: Bool
}

struct IdentifiedTagWithCount: Identifiable {
    let id: Int
    let name: String
    let count: Int
    let category: String?
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
                        .foregroundStyle(.secondary)
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
                TableColumn("Value") { item in
                    HStack(spacing: 6) {
                        if item.isImported {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                        }
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
            }
            .metadataEditorBoundary()
            .frame(height: expandToFill ? nil : min(CGFloat(max(items.count, 1)) * 28 + 28, 200))
            .frame(maxHeight: expandToFill ? .infinity : nil)
        }
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
        guard m > 0 && n > 0 else { return [] }
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
