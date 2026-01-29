import SwiftUI

struct MediaGridSortAndFilterBar: View {
    @Binding var selectedSortOption: MediaGridView.SortOption
    @Binding var selectedFormatFilter: MediaGridView.FormatFilterOption
    @Binding var selectedTag: String?
    @Binding var selectedSeries: String?
    @Binding var selectedAuthor: String?
    @Binding var selectedNarrator: String?
    @Binding var selectedTranslator: String?
    @Binding var selectedPublicationYear: String?
    @Binding var selectedRating: String?
    @Binding var selectedStatus: String?
    @Binding var selectedLocation: MediaGridView.LocationFilterOption
    @Binding var layoutStyle: LibraryLayoutStyle
    @Binding var coverPreference: CoverPreference
    @Binding var coverSize: Double
    @Binding var showAudioIndicator: Bool
    @Binding var showSourceBadge: Bool
    @Binding var showSeriesPositionBadge: Bool
    let availableTags: [String]
    let availableSeries: [String]
    let availableAuthors: [String]
    let availableNarrators: [String]
    let availableTranslators: [String]
    let availablePublicationYears: [String]
    let availableRatings: [String]
    let availableStatuses: [String]
    let filtersSummaryText: String
    let showLayoutOption: Bool
    var showSortOption: Bool = true
    #if os(macOS)
    var columnCustomization: Binding<TableColumnCustomization<BookMetadata>>? = nil
    var onResetColumns: (() -> Void)? = nil
    #endif

    @State private var showViewOptions = false

    var body: some View {
        HStack(spacing: 12) {
            if showSortOption {
                sortMenu
            }
            formatMenu
            Spacer()
            #if os(macOS)
            if isTableLayout, columnCustomization != nil {
                columnsMenu
            }
            #endif
            viewOptionsButton
        }
        .font(.callout)
    }

    private var isTableLayout: Bool {
        layoutStyle == .table
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            ForEach(MediaGridView.SortOption.menuFields, id: \.self) { field in
                Button {
                    handleSortFieldTap(field)
                } label: {
                    sortMenuRow(for: field)
                }
            }
        } label: {
            #if os(iOS)
            Label("Sort", systemImage: "arrow.up.arrow.down")
            #else
            Label(
                "Sort: \(selectedSortOption.sortField.label)",
                systemImage: selectedSortOption.isAscending ? "arrow.up" : "arrow.down"
            )
            #endif
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    private func handleSortFieldTap(_ field: MediaGridView.SortOption.SortField) {
        if selectedSortOption.sortField == field && field.isToggleable {
            selectedSortOption = selectedSortOption.toggled
        } else {
            selectedSortOption = MediaGridView.SortOption.defaultOption(for: field)
        }
    }

    @ViewBuilder
    private func sortMenuRow(for field: MediaGridView.SortOption.SortField) -> some View {
        let isSelected = selectedSortOption.sortField == field
        HStack {
            Text(field.label)
            Spacer()
            if isSelected && field.isToggleable {
                Image(systemName: selectedSortOption.isAscending ? "arrow.up" : "arrow.down")
                    .imageScale(.small)
            } else if isSelected {
                Image(systemName: "checkmark")
                    .imageScale(.small)
            }
        }
    }

    @ViewBuilder
    private var formatMenu: some View {
        Menu {
            clearMenuItem
            formatSection
            statusSection
            locationSection
            otherSection
        } label: {
            #if os(iOS)
            Label("Filters", systemImage: "line.3.horizontal.decrease")
            #else
            Label(
                "Filters: \(filtersSummaryText)",
                systemImage: "line.3.horizontal.decrease"
            )
            #endif
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    @ViewBuilder
    private var formatSection: some View {
        Section("Format") {
            ForEach(MediaGridView.FormatFilterOption.allCases) { option in
                Button {
                    selectedFormatFilter = option
                } label: {
                    menuRowLabel(text: option.label, isSelected: option == selectedFormatFilter)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        let statuses = availableStatuses
        if statuses.isEmpty {
            EmptyView()
        } else {
            Divider()
            Section("Status") {
                Button {
                    selectedStatus = nil
                } label: {
                    menuRowLabel(
                        text: "All Statuses",
                        isSelected: selectedStatus == nil
                    )
                }

                ForEach(statuses, id: \.self) { status in
                    Button {
                        selectedStatus = status
                    } label: {
                        menuRowLabel(text: status, isSelected: selectedStatus == status)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var otherSection: some View {
        let tags = availableTags
        let series = availableSeries
        let authors = availableAuthors
        let narrators = availableNarrators
        let translators = availableTranslators
        let publicationYears = availablePublicationYears

        if !tags.isEmpty || !series.isEmpty || !authors.isEmpty || !narrators.isEmpty || !translators.isEmpty || !publicationYears.isEmpty {
            Divider()
            Section("Other") {
                if !tags.isEmpty {
                    Menu {
                        Button {
                            selectedTag = nil
                        } label: {
                            menuRowLabel(text: "All Tags", isSelected: selectedTag == nil)
                        }

                        ForEach(tags, id: \.self) { tag in
                            Button {
                                selectedTag = tag
                            } label: {
                                menuRowLabel(text: tag, isSelected: selectedTag == tag)
                            }
                        }
                    } label: {
                        Label("Select Tag", systemImage: "tag")
                    }
                }

                if !series.isEmpty {
                    Menu {
                        Button {
                            selectedSeries = nil
                        } label: {
                            menuRowLabel(text: "All Series", isSelected: selectedSeries == nil)
                        }

                        ForEach(series, id: \.self) { seriesName in
                            Button {
                                selectedSeries = seriesName
                            } label: {
                                menuRowLabel(
                                    text: seriesName,
                                    isSelected: selectedSeries == seriesName
                                )
                            }
                        }
                    } label: {
                        Label("Select Series", systemImage: "books.vertical")
                    }
                }

                if !authors.isEmpty {
                    Menu {
                        Button {
                            selectedAuthor = nil
                        } label: {
                            menuRowLabel(text: "All Authors", isSelected: selectedAuthor == nil)
                        }

                        ForEach(authors, id: \.self) { authorName in
                            Button {
                                selectedAuthor = authorName
                            } label: {
                                menuRowLabel(
                                    text: authorName,
                                    isSelected: selectedAuthor == authorName
                                )
                            }
                        }
                    } label: {
                        Label("Select Author", systemImage: "person.2")
                    }
                }

                if !narrators.isEmpty {
                    Menu {
                        Button {
                            selectedNarrator = nil
                        } label: {
                            menuRowLabel(text: "All Narrators", isSelected: selectedNarrator == nil)
                        }

                        ForEach(narrators, id: \.self) { narratorName in
                            Button {
                                selectedNarrator = narratorName
                            } label: {
                                menuRowLabel(
                                    text: narratorName,
                                    isSelected: selectedNarrator == narratorName
                                )
                            }
                        }
                    } label: {
                        Label("Select Narrator", systemImage: "mic")
                    }
                }

                if !translators.isEmpty {
                    Menu {
                        Button {
                            selectedTranslator = nil
                        } label: {
                            menuRowLabel(text: "All Translators", isSelected: selectedTranslator == nil)
                        }

                        ForEach(translators, id: \.self) { translatorName in
                            Button {
                                selectedTranslator = translatorName
                            } label: {
                                menuRowLabel(
                                    text: translatorName,
                                    isSelected: selectedTranslator == translatorName
                                )
                            }
                        }
                    } label: {
                        Label("Select Translator", systemImage: "character.book.closed.fill")
                    }
                }

                if !publicationYears.isEmpty {
                    Menu {
                        Button {
                            selectedPublicationYear = nil
                        } label: {
                            menuRowLabel(text: "All Years", isSelected: selectedPublicationYear == nil)
                        }

                        ForEach(publicationYears, id: \.self) { year in
                            Button {
                                selectedPublicationYear = year
                            } label: {
                                menuRowLabel(
                                    text: year,
                                    isSelected: selectedPublicationYear == year
                                )
                            }
                        }
                    } label: {
                        Label("Select Year", systemImage: "calendar")
                    }
                }

                let ratings = availableRatings
                if !ratings.isEmpty {
                    Menu {
                        Button {
                            selectedRating = nil
                        } label: {
                            menuRowLabel(text: "All Ratings", isSelected: selectedRating == nil)
                        }

                        ForEach(ratings, id: \.self) { rating in
                            Button {
                                selectedRating = rating
                            } label: {
                                menuRowLabel(
                                    text: rating == "Unrated" ? "Unrated" : "\(rating) Stars",
                                    isSelected: selectedRating == rating
                                )
                            }
                        }
                    } label: {
                        Label("Select Rating", systemImage: "star")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Divider()
        Section("Location") {
            ForEach(MediaGridView.LocationFilterOption.allCases) { option in
                Button {
                    selectedLocation = option
                } label: {
                    menuRowLabel(text: option.label, isSelected: selectedLocation == option)
                }
            }
        }
    }

    @ViewBuilder
    private func menuRowLabel(text: String, isSelected: Bool) -> some View {
        HStack {
            Text(text)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .imageScale(.small)
            }
        }
    }

    @ViewBuilder
    private var clearMenuItem: some View {
        if canClearFilters {
            Button {
                clearFilters()
            } label: {
                menuRowLabel(text: "Clear Filters", isSelected: false)
            }
        }
    }

    private var canClearFilters: Bool {
        selectedFormatFilter != .all
            || selectedTag != nil
            || selectedSeries != nil
            || selectedAuthor != nil
            || selectedNarrator != nil
            || selectedTranslator != nil
            || selectedPublicationYear != nil
            || selectedRating != nil
            || selectedStatus != nil
            || selectedLocation != .all
    }

    private func clearFilters() {
        selectedFormatFilter = .all
        selectedTag = nil
        selectedSeries = nil
        selectedAuthor = nil
        selectedNarrator = nil
        selectedTranslator = nil
        selectedPublicationYear = nil
        selectedRating = nil
        selectedStatus = nil
        selectedLocation = .all
    }

    @ViewBuilder
    private var viewOptionsButton: some View {
        Button {
            showViewOptions.toggle()
        } label: {
            Label("View Options", systemImage: "ellipsis.circle")
        }
        #if os(macOS)
        .buttonStyle(.borderless)
        .popover(isPresented: $showViewOptions) {
            viewOptionsPopoverContent
        }
        #else
        .sheet(isPresented: $showViewOptions) {
            viewOptionsPopoverContent
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        #endif
    }

    @ViewBuilder
    private var viewOptionsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showLayoutOption {
                layoutPopoverSection
            }

            coverStylePopoverSection

            if !isTableLayout {
                coverSizePopoverSection
            }

            displayPopoverSection

            Divider()

            Button("Reset to Defaults") {
                resetViewOptions()
            }
            .font(.subheadline)
        }
        .padding()
        #if os(macOS)
        .frame(width: 200)
        #else
        .frame(minWidth: 220)
        #endif
    }

    private func resetViewOptions() {
        layoutStyle = .grid
        coverPreference = .preferEbook
        coverSize = CoverSizeRange.defaultValue
        showAudioIndicator = true
        showSourceBadge = false
        showSeriesPositionBadge = false
    }

    @ViewBuilder
    private var layoutPopoverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([LibraryLayoutStyle.grid, LibraryLayoutStyle.compactGrid, LibraryLayoutStyle.table], id: \.self) { style in
                    Button {
                        layoutStyle = style
                    } label: {
                        Image(systemName: style.iconName)
                            .frame(width: 32, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(layoutStyle == style ? .accentColor : .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var coverStylePopoverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cover Style")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    coverPreference = .preferEbook
                } label: {
                    Image(systemName: "book.fill")
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.bordered)
                .tint(coverPreference == .preferEbook ? .accentColor : .secondary)

                Button {
                    coverPreference = .preferAudiobook
                } label: {
                    Image(systemName: "headphones")
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.bordered)
                .tint(coverPreference == .preferAudiobook ? .accentColor : .secondary)
            }
        }
    }

    @ViewBuilder
    private var coverSizePopoverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cover Size")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(
                    value: $coverSize,
                    in: Double(CoverSizeRange.min)...Double(CoverSizeRange.max),
                    step: 5
                )
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var displayPopoverSection: some View {
        #if os(iOS)
        let showGridOnlyOptions = !isTableLayout
        #else
        let showGridOnlyOptions = true
        #endif

        VStack(alignment: .leading, spacing: 8) {
            Text("Display")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if showGridOnlyOptions {
                Toggle("Audio Indicator", isOn: $showAudioIndicator)
                Toggle("Source Badge", isOn: $showSourceBadge)
            }
            Toggle("Series Position", isOn: $showSeriesPositionBadge)
        }
    }

    #if os(macOS)
    private var isListLayout: Bool {
        layoutStyle == .table
    }

    @ViewBuilder
    private var columnsMenu: some View {
        Menu {
            columnToggle(id: "cover", label: "Cover")
            columnToggle(id: "title", label: "Title")
            columnToggle(id: "author", label: "Author")
            columnToggle(id: "series", label: "Series")
            columnToggle(id: "progress", label: "Progress")
            columnToggle(id: "narrator", label: "Narrator")
            columnToggle(id: "status", label: "Status")
            columnToggle(id: "added", label: "Added")
            columnToggle(id: "lastRead", label: "Last Read")
            columnToggle(id: "tags", label: "Tags")
            columnToggle(id: "translator", label: "Translator")
            columnToggle(id: "publicationYear", label: "Published")
            columnToggle(id: "media", label: "Media")
            Divider()
            Button("Reset to Defaults") {
                onResetColumns?()
            }
        } label: {
            Label("Columns", systemImage: "rectangle.split.3x1")
        }
        .menuStyle(.borderlessButton)
    }

    private static let defaultVisibleColumns: Set<String> = ["cover", "title", "series", "media"]

    private func isColumnVisible(_ id: String) -> Bool {
        guard let binding = columnCustomization else { return false }
        let visibility = binding.wrappedValue[visibility: id]
        switch visibility {
        case .visible:
            return true
        case .hidden:
            return false
        default:
            return Self.defaultVisibleColumns.contains(id)
        }
    }

    @ViewBuilder
    private func columnToggle(id: String, label: String) -> some View {
        if let binding = columnCustomization {
            let isVisible = isColumnVisible(id)
            Button {
                binding.wrappedValue[visibility: id] = isVisible ? .hidden : .visible
            } label: {
                HStack {
                    Text(label)
                    Spacer()
                    if isVisible {
                        Image(systemName: "checkmark")
                            .imageScale(.small)
                    }
                }
            }
        }
    }
    #endif

}
