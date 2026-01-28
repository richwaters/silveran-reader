#if os(macOS)
import SwiftUI

struct ConditionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let conditionType: ShelfConditionType
    let cachedValues: [ShelfConditionType: [String]]
    let cachedStatuses: [String]
    let onAdd: ([ShelfCondition]) -> Void

    @State private var ratingMode: RatingMode = .single
    @State private var ratingComparison: RatingComparison = .greaterThanOrEqual
    @State private var ratingValue = 3
    @State private var ratingRangeLow = 2
    @State private var ratingRangeHigh = 4

    @State private var yearTab: YearTab = .beforeAfter
    @State private var yearCompareMode: YearCompareMode = .single
    @State private var yearComparison: YearComparison = .newerThan
    @State private var selectedYear = 0
    @State private var yearRangeLow = 0
    @State private var yearRangeHigh = 0

    @State private var inclusionMode: InclusionMode = .include
    @State private var selectedItems: Set<String> = []
    @State private var searchText = ""
    @State private var anyPresent = false

    private enum RatingMode: String, CaseIterable, Hashable {
        case single = "Single"
        case range = "Range"
    }

    private enum YearTab: String, CaseIterable, Hashable {
        case beforeAfter = "Before / After"
        case specificYears = "Specific Years"
    }

    private enum YearCompareMode: String, CaseIterable, Hashable {
        case single = "Single"
        case range = "Range"
    }

    init(
        conditionType: ShelfConditionType,
        cachedValues: [ShelfConditionType: [String]],
        cachedStatuses: [String],
        onAdd: @escaping ([ShelfCondition]) -> Void
    ) {
        self.conditionType = conditionType
        self.cachedValues = cachedValues
        self.cachedStatuses = cachedStatuses
        self.onAdd = onAdd

        if conditionType == .publicationYear {
            let years = (cachedValues[.publicationYear] ?? []).compactMap { Int($0) }.sorted()
            _selectedYear = State(initialValue: years.last ?? 0)
            _yearRangeLow = State(initialValue: years.first ?? 0)
            _yearRangeHigh = State(initialValue: years.last ?? 0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add \(conditionType.label) Condition")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            editorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            Button {
                if let conditions = buildConditions() {
                    onAdd(conditions)
                    dismiss()
                }
            } label: {
                Text("Add Condition")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdd)
            .padding()
        }
        .frame(minWidth: 400, minHeight: 450)
    }

    // MARK: - Editor routing

    @ViewBuilder
    private var editorContent: some View {
        switch conditionType {
        case .format:
            multiSelectEditor(items: FormatCondition.allCases.map(\.label), itemLabel: "Formats", searchable: false)
        case .status:
            multiSelectEditor(items: cachedStatuses, itemLabel: "Statuses", searchable: cachedStatuses.count > 5)
        case .location:
            multiSelectEditor(items: LocationCondition.allCases.map(\.label), itemLabel: "Locations", searchable: false)
        case .progress:
            multiSelectEditor(items: ProgressCondition.allCases.map(\.label), itemLabel: "Progress States", searchable: false)
        case .rating:
            ratingEditor
        case .publicationYear:
            publicationYearEditor
        case .tag:
            multiSelectEditor(items: cachedValues[.tag] ?? [], itemLabel: "Tags")
        case .series:
            multiSelectEditor(items: cachedValues[.series] ?? [], itemLabel: "Series")
        case .author:
            multiSelectEditor(items: cachedValues[.author] ?? [], itemLabel: "Authors", anyPresentLabel: "Any Author Present")
        case .narrator:
            multiSelectEditor(items: cachedValues[.narrator] ?? [], itemLabel: "Narrators", anyPresentLabel: "Any Narrator Present")
        case .translator:
            multiSelectEditor(items: cachedValues[.translator] ?? [], itemLabel: "Translators", anyPresentLabel: "Any Translator Present")
        case .boolean:
            EmptyView()
        }
    }

    // MARK: - Rating editor

    @ViewBuilder
    private var ratingEditor: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $ratingMode) {
                ForEach(RatingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)

            Spacer()

            if ratingMode == .single {
                singleRatingEditor
            } else {
                rangeRatingEditor
            }

            Spacer()
        }
        .padding(.top)
    }

    private var singleRatingEditor: some View {
        VStack(spacing: 16) {
            Picker("Comparison", selection: $ratingComparison) {
                ForEach(RatingComparison.allCases) { comp in
                    Text(comp.label).tag(comp)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)

            Stepper(value: $ratingValue, in: 1...5) {
                starsView(count: ratingValue)
            }
            .frame(maxWidth: 200)

            Text(verbatim: "Rating \(ratingComparison.symbol) \(ratingValue) star\(ratingValue == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var rangeRatingEditor: some View {
        VStack(spacing: 16) {
            HStack {
                Text("From")
                    .frame(width: 40, alignment: .leading)
                Stepper(value: $ratingRangeLow, in: 1...5) {
                    starsView(count: ratingRangeLow)
                }
            }
            .frame(maxWidth: 250)

            HStack {
                Text("To")
                    .frame(width: 40, alignment: .leading)
                Stepper(value: $ratingRangeHigh, in: 1...5) {
                    starsView(count: ratingRangeHigh)
                }
            }
            .frame(maxWidth: 250)

            if ratingRangeLow < ratingRangeHigh {
                Text(verbatim: "Rating between \(ratingRangeLow) and \(ratingRangeHigh) stars")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                Text("'From' must be less than 'To'")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    private func starsView(count: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= count ? "star.fill" : "star")
                    .foregroundStyle(star <= count ? .yellow : .secondary)
            }
        }
    }

    // MARK: - Publication Year editor

    @ViewBuilder
    private var publicationYearEditor: some View {
        let yearStrings = cachedValues[.publicationYear] ?? []
        let years = yearStrings.compactMap { Int($0) }.sorted(by: >)

        VStack(spacing: 0) {
            Picker("Tab", selection: $yearTab) {
                ForEach(YearTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            if yearTab == .beforeAfter {
                yearCompareEditor(years: years)
            } else {
                yearSpecificEditor(yearStrings: yearStrings)
            }
        }
    }

    @ViewBuilder
    private func yearCompareEditor(years: [Int]) -> some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $yearCompareMode) {
                ForEach(YearCompareMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)

            Spacer()

            if years.isEmpty {
                Text("No publication years available")
                    .foregroundStyle(.secondary)
            } else if yearCompareMode == .single {
                yearCompareSingleEditor(years: years)
            } else {
                yearCompareRangeEditor(years: years)
            }

            Spacer()
        }
    }

    private func yearCompareSingleEditor(years: [Int]) -> some View {
        VStack(spacing: 16) {
            Picker("Comparison", selection: $yearComparison) {
                ForEach(YearComparison.allCases) { comp in
                    Text(comp.label).tag(comp)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 350)

            Picker("Year", selection: $selectedYear) {
                ForEach(years, id: \.self) { year in
                    Text(verbatim: "\(year)").tag(year)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)

            Text(verbatim: "Year \(yearComparison.label.lowercased()) \(selectedYear)")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private func yearCompareRangeEditor(years: [Int]) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("From")
                Picker("From", selection: $yearRangeLow) {
                    ForEach(years, id: \.self) { year in
                        Text(verbatim: "\(year)").tag(year)
                    }
                }
                .labelsHidden()
            }
            .frame(maxWidth: 200)

            HStack {
                Text("To")
                Picker("To", selection: $yearRangeHigh) {
                    ForEach(years, id: \.self) { year in
                        Text(verbatim: "\(year)").tag(year)
                    }
                }
                .labelsHidden()
            }
            .frame(maxWidth: 200)

            if yearRangeLow <= yearRangeHigh {
                Text(verbatim: "Years from \(yearRangeLow) to \(yearRangeHigh)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                Text("'From' must not be greater than 'To'")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func yearSpecificEditor(yearStrings: [String]) -> some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $inclusionMode) {
                ForEach(InclusionMode.allCases) { mode in
                    Text(mode.label.capitalized).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            if yearStrings.isEmpty {
                ContentUnavailableView {
                    Label("No Years", systemImage: "calendar")
                } description: {
                    Text("No publication years available in your library.")
                }
            } else {
                searchableList(items: yearStrings, prompt: "Filter years")
            }
        }
    }

    // MARK: - Multi-select editor

    @ViewBuilder
    private func multiSelectEditor(items: [String], itemLabel: String, anyPresentLabel: String? = nil, searchable: Bool = true) -> some View {
        VStack(spacing: 0) {
            if let anyLabel = anyPresentLabel {
                Toggle(anyLabel, isOn: $anyPresent)
                    .toggleStyle(.checkbox)
                    .padding(.horizontal)
                    .padding(.top)

                if anyPresent {
                    Text("Matches books with any \(conditionType.label.lowercased())")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .padding()
                    Spacer()
                }
            }

            if !anyPresent {
                Picker("Mode", selection: $inclusionMode) {
                    ForEach(InclusionMode.allCases) { mode in
                        Text(mode.label.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()

                if items.isEmpty {
                    ContentUnavailableView {
                        Label("No \(itemLabel)", systemImage: conditionType.systemImage)
                    } description: {
                        Text("No \(itemLabel.lowercased()) available in your library.")
                    }
                } else {
                    searchableList(items: items, prompt: "Filter \(itemLabel.lowercased())", searchable: searchable)
                }
            }
        }
    }

    @ViewBuilder
    private func searchableList(items: [String], prompt: String, searchable: Bool = true) -> some View {
        if searchable {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(prompt, text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
        }

        let filtered = searchable && !searchText.isEmpty
            ? items.filter { $0.localizedCaseInsensitiveContains(searchText) }
            : items

        List(filtered, id: \.self) { item in
            HStack {
                Text(item)
                Spacer()
                if selectedItems.contains(item) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selectedItems.contains(item) {
                    selectedItems.remove(item)
                } else {
                    selectedItems.insert(item)
                }
            }
        }
        .listStyle(.plain)

        if !selectedItems.isEmpty {
            HStack {
                Text("\(selectedItems.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    selectedItems.removeAll()
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Validation & building

    private var canAdd: Bool {
        switch conditionType {
        case .format, .status, .location, .progress:
            return !selectedItems.isEmpty
        case .rating:
            return ratingMode == .single || ratingRangeLow < ratingRangeHigh
        case .publicationYear:
            if yearTab == .beforeAfter {
                let hasYears = !(cachedValues[.publicationYear] ?? []).isEmpty
                if !hasYears { return false }
                return yearCompareMode == .single || yearRangeLow <= yearRangeHigh
            }
            return !selectedItems.isEmpty
        case .tag, .series:
            return !selectedItems.isEmpty
        case .author, .narrator, .translator:
            return anyPresent || !selectedItems.isEmpty
        case .boolean:
            return false
        }
    }

    private func buildConditions() -> [ShelfCondition]? {
        guard canAdd else { return nil }
        switch conditionType {
        case .format:
            let conditions = FormatCondition.allCases.filter { selectedItems.contains($0.label) }
            return [.format(mode: inclusionMode, conditions: conditions)]
        case .status:
            return [.status(mode: inclusionMode, values: Array(selectedItems).sorted())]
        case .location:
            let conditions = LocationCondition.allCases.filter { selectedItems.contains($0.label) }
            return [.location(mode: inclusionMode, conditions: conditions)]
        case .progress:
            let conditions = ProgressCondition.allCases.filter { selectedItems.contains($0.label) }
            return [.progress(mode: inclusionMode, conditions: conditions)]
        case .rating:
            if ratingMode == .single {
                return [.rating(comparison: ratingComparison, value: ratingValue)]
            }
            return [
                .rating(comparison: .greaterThanOrEqual, value: ratingRangeLow),
                .rating(comparison: .lessThanOrEqual, value: ratingRangeHigh),
            ]
        case .publicationYear:
            if yearTab == .beforeAfter {
                if yearCompareMode == .single {
                    return [.publicationYearComparison(comparison: yearComparison, value: selectedYear)]
                }
                return [
                    .publicationYearComparison(comparison: .newerThan, value: yearRangeLow - 1),
                    .publicationYearComparison(comparison: .olderThan, value: yearRangeHigh + 1),
                ]
            }
            return [.publicationYear(mode: inclusionMode, values: Array(selectedItems).sorted())]
        case .tag:
            return [.tag(mode: inclusionMode, values: Array(selectedItems).sorted())]
        case .series:
            return [.series(mode: inclusionMode, values: Array(selectedItems).sorted())]
        case .author:
            if anyPresent { return [.hasAuthor] }
            return [.author(mode: inclusionMode, values: Array(selectedItems).sorted())]
        case .narrator:
            if anyPresent { return [.hasNarrator] }
            return [.narrator(mode: inclusionMode, values: Array(selectedItems).sorted())]
        case .translator:
            if anyPresent { return [.hasTranslator] }
            return [.translator(mode: inclusionMode, values: Array(selectedItems).sorted())]
        case .boolean:
            return nil
        }
    }
}
#endif
