import SwiftUI

struct MediaGridSortAndFilterBar: View {
    @Binding var selectedSortOption: MediaGridView.SortOption
    @Binding var selectedFormatFilter: MediaGridView.FormatFilterOption
    @Binding var selectedTag: String?
    @Binding var selectedSeries: String?
    @Binding var selectedAuthor: String?
    @Binding var selectedNarrator: String?
    @Binding var selectedStatus: String?
    @Binding var selectedLocation: MediaGridView.LocationFilterOption
    @Binding var layoutStyle: LibraryLayoutStyle
    @Binding var coverPreference: CoverPreference
    @Binding var coverSize: CoverSize
    @Binding var showAudioIndicator: Bool
    @Binding var showSourceBadge: Bool
    @Binding var showSeriesPositionBadge: Bool
    let availableTags: [String]
    let availableSeries: [String]
    let availableAuthors: [String]
    let availableNarrators: [String]
    let availableStatuses: [String]
    let filtersSummaryText: String
    let showLayoutOption: Bool
    var showSortOption: Bool = true
    #if os(macOS)
    var columnCustomization: Binding<TableColumnCustomization<BookMetadata>>? = nil
    var onResetColumns: (() -> Void)? = nil
    #endif

    var body: some View {
        HStack(spacing: 12) {
            if showSortOption {
                sortMenu
            }
            formatMenu
            Spacer()
            #if os(macOS)
            if isListLayout, columnCustomization != nil {
                columnsMenu
            }
            #endif
            viewOptionsMenu
        }
        .font(.callout)
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            ForEach(MediaGridView.SortOption.allCases) { option in
                Button {
                    selectedSortOption = option
                } label: {
                    menuRowLabel(text: option.label, isSelected: option == selectedSortOption)
                }
            }
        } label: {
            #if os(iOS)
            Label("Sort", systemImage: "arrow.up.arrow.down")
            #else
            Label(
                "Sort: \(selectedSortOption.shortLabel)",
                systemImage: "arrow.up.arrow.down"
            )
            #endif
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
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

        if !tags.isEmpty || !series.isEmpty || !authors.isEmpty || !narrators.isEmpty {
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
            || selectedStatus != nil
            || selectedLocation != .all
    }

    private func clearFilters() {
        selectedFormatFilter = .all
        selectedTag = nil
        selectedSeries = nil
        selectedAuthor = nil
        selectedNarrator = nil
        selectedStatus = nil
        selectedLocation = .all
    }

    @ViewBuilder
    private var viewOptionsMenu: some View {
        Menu {
            if showLayoutOption {
                layoutSection
                Divider()
            }

            coverStyleSection
            Divider()
            coverSizeSection
            Divider()
            displaySection
        } label: {
            Label("View Options", systemImage: "ellipsis.circle")
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    #if os(macOS)
    private var isListLayout: Bool {
        layoutStyle == .list || layoutStyle == .compactList
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
            columnToggle(id: "tags", label: "Tags")
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

    private static let defaultVisibleColumns: Set<String> = ["cover", "title", "author", "series", "media"]

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

    @ViewBuilder
    private var layoutSection: some View {
        Section("Layout") {
            ForEach([LibraryLayoutStyle.grid, LibraryLayoutStyle.compactGrid, LibraryLayoutStyle.list, LibraryLayoutStyle.compactList], id: \.self) { style in
                Button {
                    layoutStyle = style
                } label: {
                    menuRowLabel(text: style.label, isSelected: layoutStyle == style)
                }
            }
        }
    }

    @ViewBuilder
    private var coverStyleSection: some View {
        Section("Cover Style") {
            ForEach(CoverPreference.allCases) { preference in
                Button {
                    coverPreference = preference
                } label: {
                    menuRowLabel(text: preference.label, isSelected: coverPreference == preference)
                }
            }
        }
    }

    @ViewBuilder
    private var coverSizeSection: some View {
        Section("Cover Size") {
            ForEach(CoverSize.allCases) { size in
                Button {
                    coverSize = size
                } label: {
                    menuRowLabel(text: size.label, isSelected: coverSize == size)
                }
            }
        }
    }

    @ViewBuilder
    private var displaySection: some View {
        Section("Display") {
            Button {
                showAudioIndicator.toggle()
            } label: {
                HStack {
                    Text("Show Audio Indicator")
                    Spacer()
                    if showAudioIndicator {
                        Image(systemName: "checkmark")
                            .imageScale(.small)
                    }
                }
            }

            Button {
                showSourceBadge.toggle()
            } label: {
                HStack {
                    Text("Show Source Badge")
                    Spacer()
                    if showSourceBadge {
                        Image(systemName: "checkmark")
                            .imageScale(.small)
                    }
                }
            }

            Button {
                showSeriesPositionBadge.toggle()
            } label: {
                HStack {
                    Text("Show Series Position")
                    Spacer()
                    if showSeriesPositionBadge {
                        Image(systemName: "checkmark")
                            .imageScale(.small)
                    }
                }
            }
        }
    }
}
