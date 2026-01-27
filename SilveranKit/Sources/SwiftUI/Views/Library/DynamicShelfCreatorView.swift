import SwiftUI

private struct IdentifiedCondition: Identifiable, Equatable {
    let id: UUID
    var condition: ShelfCondition

    init(_ condition: ShelfCondition) {
        self.id = UUID()
        self.condition = condition
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.condition == rhs.condition
    }
}

struct DynamicShelfCreatorView: View {
    @Environment(MediaViewModel.self) private var mediaViewModel
    @Environment(\.dismiss) private var dismiss

    let existingShelf: DynamicShelf?
    let onSave: (DynamicShelf) -> Void

    @State private var shelfName: String
    @State private var identifiedConditions: [IdentifiedCondition]
    @State private var showingConditionPicker = false
    @State private var editingConditionIndex: Int?
    @State private var cachedValues: [ShelfConditionType: [String]] = [:]
    @State private var cachedStatuses: [String] = []
    @State private var showValidation = false
    @AppStorage("coverPref.global") private var coverPrefRaw: String = CoverPreference.preferEbook.rawValue

    private var coverPreference: CoverPreference {
        CoverPreference(rawValue: coverPrefRaw) ?? .preferEbook
    }

    private var conditions: [ShelfCondition] {
        identifiedConditions.map(\.condition)
    }

    init(existingShelf: DynamicShelf? = nil, onSave: @escaping (DynamicShelf) -> Void) {
        self.existingShelf = existingShelf
        self.onSave = onSave
        _shelfName = State(initialValue: existingShelf?.name ?? "")
        _identifiedConditions = State(
            initialValue: (existingShelf?.conditions ?? []).map { IdentifiedCondition($0) }
        )
    }

    private var matchingBooks: [BookMetadata] {
        let raw = conditions
        guard !raw.isEmpty else { return [] }
        let shelf = DynamicShelf(
            id: existingShelf?.id ?? UUID(),
            name: shelfName,
            conditions: raw
        )
        return mediaViewModel.booksForShelf(shelf)
    }

    private var hasName: Bool {
        !shelfName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasConditions: Bool {
        conditions.contains(where: { if case .orSeparator = $0 { return false }; return true })
    }

    private var canSave: Bool {
        hasName && hasConditions
    }

    private var validationMessage: String? {
        if !hasName && !hasConditions { return "Add a name and at least one condition" }
        if !hasName { return "Add a shelf name" }
        if !hasConditions { return "Add at least one condition" }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            HSplitView {
                conditionPanel
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

                previewPanel
                    .frame(minWidth: 300, idealWidth: 500)
            }

            Divider()

            footerBar
        }
        .frame(minWidth: 700, idealWidth: 850, minHeight: 500, idealHeight: 600)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            precomputeAvailableValues()
        }
    }

    private func precomputeAvailableValues() {
        let books = mediaViewModel.library.bookMetaData
        var tagSet = Set<String>()
        var seriesSet = Set<String>()
        var authorSet = Set<String>()
        var narratorSet = Set<String>()
        var translatorSet = Set<String>()
        var yearSet = Set<String>()
        var statusSet = Set<String>()

        for book in books {
            for tag in book.tagNames { tagSet.insert(tag) }
            for s in book.series ?? [] { seriesSet.insert(s.name) }
            for a in book.authors ?? [] { if let n = a.name { authorSet.insert(n) } }
            for n in book.narrators ?? [] { if let name = n.name { narratorSet.insert(name) } }
            for c in book.creators ?? [] where c.role == "trl" { if let n = c.name { translatorSet.insert(n) } }
            let year = book.sortablePublicationYear
            if !year.isEmpty { yearSet.insert(year) }
            if let name = book.status?.name { statusSet.insert(name) }
        }

        cachedValues = [
            .tag: tagSet.sorted(),
            .series: seriesSet.sorted(),
            .author: authorSet.sorted(),
            .narrator: narratorSet.sorted(),
            .translator: translatorSet.sorted(),
            .publicationYear: yearSet.sorted(),
        ]
        cachedStatuses = statusSet.sorted()
    }

    private var headerBar: some View {
        HStack {
            TextField("Shelf Name", text: $shelfName)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private var conditionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Conditions")
                    .font(.headline)
                Spacer()
                addConditionMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if identifiedConditions.isEmpty {
                VStack(spacing: 8) {
                    Text("No conditions added")
                        .foregroundStyle(.secondary)
                    Text("Add conditions to filter your library")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(identifiedConditions.enumerated()), id: \.element.id) { index, ic in
                        conditionRow(ic.condition, at: index)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    }
                    .onMove(perform: moveConditions)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func moveConditions(from source: IndexSet, to destination: Int) {
        identifiedConditions.move(fromOffsets: source, toOffset: destination)
    }

    @ViewBuilder
    private func conditionRow(_ condition: ShelfCondition, at index: Int) -> some View {
        if case .orSeparator = condition {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
                Text("OR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
                Button {
                    identifiedConditions.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if index > 0 && !isPrecededByOrSeparator(at: index) {
                    Text("AND")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                HStack {
                    Text(condition.displayLabel)
                        .font(.callout)
                        .lineLimit(2)

                    Spacer()

                    Button {
                        identifiedConditions.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
        }
    }

    private func isPrecededByOrSeparator(at index: Int) -> Bool {
        guard index > 0 else { return false }
        if case .orSeparator = identifiedConditions[index - 1].condition { return true }
        return false
    }

    // MARK: - Condition menus

    private var addConditionMenu: some View {
        Menu {
            ForEach(ShelfConditionType.allCases) { type in
                Menu(type.label) {
                    conditionSubMenu(for: type)
                }
            }
        } label: {
            Label("Add Condition", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func conditionSubMenu(for type: ShelfConditionType) -> some View {
        switch type {
        case .format:
            ForEach(FormatCondition.allCases) { fc in
                Button(fc.label) {
                    identifiedConditions.append(IdentifiedCondition(.format(fc)))
                }
            }

        case .status:
            ForEach(cachedStatuses, id: \.self) { status in
                Button(status) {
                    identifiedConditions.append(IdentifiedCondition(.status(status)))
                }
            }

        case .location:
            ForEach(LocationCondition.allCases) { lc in
                Button(lc.label) {
                    identifiedConditions.append(IdentifiedCondition(.location(lc)))
                }
            }

        case .rating:
            ForEach(RatingComparison.allCases) { comparison in
                Menu(comparison.label) {
                    ForEach(1...5, id: \.self) { value in
                        Button("\(value) star\(value == 1 ? "" : "s")") {
                            identifiedConditions.append(
                                IdentifiedCondition(.rating(comparison: comparison, value: value))
                            )
                        }
                    }
                }
            }

        case .progress:
            ForEach(ProgressCondition.allCases) { pc in
                Button(pc.label) {
                    identifiedConditions.append(IdentifiedCondition(.progress(pc)))
                }
            }

        case .tag:
            inclusionSubMenu(type: .tag)

        case .series:
            inclusionSubMenu(type: .series)

        case .author:
            inclusionSubMenu(type: .author)

        case .narrator:
            inclusionSubMenu(type: .narrator)

        case .translator:
            inclusionSubMenu(type: .translator)

        case .publicationYear:
            publicationYearFullSubMenu

        case .boolean:
            Button("OR") {
                identifiedConditions.append(IdentifiedCondition(.orSeparator))
            }
        }
    }

    @ViewBuilder
    private var publicationYearFullSubMenu: some View {
        let yearStrings = cachedValues[.publicationYear] ?? []
        let years = yearStrings.compactMap { Int($0) }.sorted(by: >)

        ForEach(YearComparison.allCases) { comparison in
            Menu(comparison.label) {
                ForEach(years, id: \.self) { year in
                    Button {
                        identifiedConditions.append(
                            IdentifiedCondition(.publicationYearComparison(comparison: comparison, value: year))
                        )
                    } label: {
                        Text(verbatim: "\(year)")
                    }
                }
                if years.isEmpty {
                    Text("No values available")
                }
            }
        }

        Divider()

        ForEach(InclusionMode.allCases) { mode in
            Menu(mode.label.capitalized) {
                ForEach(yearStrings, id: \.self) { value in
                    Button(value) {
                        appendInclusionCondition(type: .publicationYear, mode: mode, value: value)
                    }
                }
                if yearStrings.isEmpty {
                    Text("No values available")
                }
            }
        }
    }

    @ViewBuilder
    private func inclusionSubMenu(type: ShelfConditionType) -> some View {
        let values = cachedValues[type] ?? []
        ForEach(InclusionMode.allCases) { mode in
            Menu(mode.label.capitalized) {
                ForEach(values, id: \.self) { value in
                    Button(value) {
                        appendInclusionCondition(type: type, mode: mode, value: value)
                    }
                }
                if values.isEmpty {
                    Text("No values available")
                }
            }
        }
    }

    // MARK: - Inclusion merge logic (scoped to current OR group)

    private func appendInclusionCondition(type: ShelfConditionType, mode: InclusionMode, value: String) {
        // Only merge within the last OR group (everything after the last orSeparator).
        let lastOrIndex = identifiedConditions.lastIndex(where: {
            if case .orSeparator = $0.condition { return true }
            return false
        })
        let groupStart = (lastOrIndex ?? -1) + 1

        if let existingIndex = identifiedConditions[groupStart...].firstIndex(where: {
            existingConditionMatches($0.condition, type: type, mode: mode)
        }) {
            identifiedConditions[existingIndex].condition =
                addValueToCondition(identifiedConditions[existingIndex].condition, value: value)
        } else {
            let newCondition: ShelfCondition
            switch type {
            case .tag: newCondition = .tag(mode: mode, values: [value])
            case .series: newCondition = .series(mode: mode, values: [value])
            case .author: newCondition = .author(mode: mode, values: [value])
            case .narrator: newCondition = .narrator(mode: mode, values: [value])
            case .translator: newCondition = .translator(mode: mode, values: [value])
            case .publicationYear: newCondition = .publicationYear(mode: mode, values: [value])
            default: return
            }
            identifiedConditions.append(IdentifiedCondition(newCondition))
        }
    }

    private func existingConditionMatches(_ condition: ShelfCondition, type: ShelfConditionType, mode: InclusionMode) -> Bool {
        switch (condition, type) {
        case (.tag(let m, _), .tag): return m == mode
        case (.series(let m, _), .series): return m == mode
        case (.author(let m, _), .author): return m == mode
        case (.narrator(let m, _), .narrator): return m == mode
        case (.translator(let m, _), .translator): return m == mode
        case (.publicationYear(let m, _), .publicationYear): return m == mode
        default: return false
        }
    }

    private func addValueToCondition(_ condition: ShelfCondition, value: String) -> ShelfCondition {
        switch condition {
        case .tag(let m, var v):
            if !v.contains(value) { v.append(value) }
            return .tag(mode: m, values: v)
        case .series(let m, var v):
            if !v.contains(value) { v.append(value) }
            return .series(mode: m, values: v)
        case .author(let m, var v):
            if !v.contains(value) { v.append(value) }
            return .author(mode: m, values: v)
        case .narrator(let m, var v):
            if !v.contains(value) { v.append(value) }
            return .narrator(mode: m, values: v)
        case .translator(let m, var v):
            if !v.contains(value) { v.append(value) }
            return .translator(mode: m, values: v)
        case .publicationYear(let m, var v):
            if !v.contains(value) { v.append(value) }
            return .publicationYear(mode: m, values: v)
        default:
            return condition
        }
    }

    // MARK: - Available values

    private var availableStatuses: [String] {
        var statuses = Set<String>()
        for book in mediaViewModel.library.bookMetaData {
            if let name = book.status?.name {
                statuses.insert(name)
            }
        }
        return statuses.sorted()
    }

    private func availableValues(for type: ShelfConditionType) -> [String] {
        let books = mediaViewModel.library.bookMetaData
        var values = Set<String>()

        for book in books {
            switch type {
            case .tag:
                for tag in book.tagNames { values.insert(tag) }
            case .series:
                for s in book.series ?? [] { values.insert(s.name) }
            case .author:
                for a in book.authors ?? [] {
                    if let name = a.name { values.insert(name) }
                }
            case .narrator:
                for n in book.narrators ?? [] {
                    if let name = n.name { values.insert(name) }
                }
            case .translator:
                for c in book.creators ?? [] where c.role == "trl" {
                    if let name = c.name { values.insert(name) }
                }
            case .publicationYear:
                let year = book.sortablePublicationYear
                if !year.isEmpty { values.insert(year) }
            default:
                break
            }
        }

        return values.sorted()
    }

    // MARK: - Preview panel

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Text("\(matchingBooks.count) book\(matchingBooks.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if conditions.isEmpty {
                VStack(spacing: 8) {
                    Text("Add conditions to see matching books")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matchingBooks.isEmpty {
                VStack(spacing: 8) {
                    Text("No books match")
                        .foregroundStyle(.secondary)
                    Text("Try adjusting your conditions")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    let columns = [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(matchingBooks) { book in
                            previewBookTile(book)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    @ViewBuilder
    private func previewBookTile(_ book: BookMetadata) -> some View {
        let variant = resolveCoverVariant(for: book)
        let coverState = mediaViewModel.coverState(for: book, variant: variant)
        let aspectRatio = coverPreference.preferredContainerAspectRatio

        VStack(spacing: 4) {
            ZStack {
                Color(white: 0.2)
                if let image = coverState.image {
                    image
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .task {
                mediaViewModel.ensureCoverLoaded(for: book, variant: variant)
            }

            Text(book.title)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func resolveCoverVariant(for item: BookMetadata) -> MediaViewModel.CoverVariant {
        switch coverPreference {
        case .preferEbook:
            if item.hasAvailableEbook { return .standard }
            return item.hasAvailableAudiobook ? .audioSquare : .standard
        case .preferAudiobook:
            if item.hasAvailableAudiobook || item.isAudiobookOnly { return .audioSquare }
            return .standard
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if showValidation, let message = validationMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(existingShelf != nil ? "Save Changes" : "Create Dynamic Shelf") {
                if canSave {
                    let shelf = DynamicShelf(
                        id: existingShelf?.id ?? UUID(),
                        name: shelfName.trimmingCharacters(in: .whitespacesAndNewlines),
                        conditions: conditions,
                        createdAt: existingShelf?.createdAt ?? Date()
                    )
                    onSave(shelf)
                    dismiss()
                } else {
                    showValidation = true
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
