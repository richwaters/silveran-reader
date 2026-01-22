import SwiftUI
#if os(macOS)
import AppKit

private struct ScrollWheelMonitor: ViewModifier {
    let onScroll: () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    onScroll()
                    return event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
    }
}

extension View {
    func onScrollWheel(perform action: @escaping () -> Void) -> some View {
        modifier(ScrollWheelMonitor(onScroll: action))
    }
}
#endif

extension MediaKind {
    var coverAspectRatio: CGFloat {
        switch self {
            case .ebook:
                2.0 / 3.0
            case .audiobook:
                1.0
        }
    }

    var iconName: String {
        switch self {
            case .ebook:
                "books.vertical"
            case .audiobook:
                "headphones"
        }
    }
}

struct SeriesNavIdentifier: Hashable {
    let name: String
}

struct MediaGridView: View {
    public struct ColumnBreakpoint: Hashable {
        public let columns: Int
        public let minWidth: CGFloat

        public init(columns: Int, minWidth: CGFloat) {
            self.columns = columns
            self.minWidth = minWidth
        }
    }

    let title: String
    let searchText: String
    @Environment(MediaViewModel.self) private var mediaViewModel: MediaViewModel
    @State private var settingsViewModel = SettingsViewModel()
    let mediaKind: MediaKind
    let tagFilter: String?
    let seriesFilter: String?
    let collectionFilter: String?
    let authorFilter: String?
    let narratorFilter: String?
    let statusFilter: String?
    let defaultSort: String?
    let preferredTileWidth: CGFloat
    let minimumTileWidth: CGFloat
    let columnBreakpoints: [ColumnBreakpoint]
    let onReadNow: (BookMetadata) -> Void
    let onRename: (BookMetadata) -> Void
    let onDelete: (BookMetadata) -> Void
    let onSeriesSelected: ((String) -> Void)?
    let initialNarrationFilterOption: NarrationFilter
    private let scrollPosition: Binding<BookMetadata.ID?>?
    private let headerScrollID = "media-grid-header"

    #if os(macOS)
    // Workaround for macOS Sequoia bug where parent view's onTapGesture fires after card tap
    @State private var cardTapInProgress: Bool = false
    #endif

    @State private var activeInfoItem: BookMetadata? = nil
    @State private var isSidebarVisible: Bool = false
    @State private var lastKnownColumnCount: Int = 1
    @State private var selectedSortOption: SortOption
    @State private var selectedFormatFilter: FormatFilterOption
    @State private var selectedTag: String? = nil
    @State private var selectedSeries: String? = nil
    @State private var selectedCollection: String? = nil
    @State private var selectedAuthor: String? = nil
    @State private var selectedNarrator: String? = nil
    @State private var selectedStatus: String? = nil
    @State private var selectedLocation: LocationFilterOption = .all
    @State private var shouldEnsureActiveItemVisible: Bool = false
    @State private var showSourceBadge: Bool = false
    @State private var showSeriesPositionBadge: Bool
    @AppStorage("viewLayout.books") private var layoutStyleRaw: String = LibraryLayoutStyle.grid.rawValue
    @AppStorage("coverPref.global") private var coverPrefRaw: String = CoverPreference.preferEbook.rawValue
    @AppStorage("coverSize.global") private var coverSizeRaw: String = CoverSize.medium.rawValue
    #if os(macOS)
    @AppStorage("library.table.columnVisibility") private var columnVisibility: TableColumnVisibility = .defaultVisibility(compact: false)
    #endif

    private var layoutStyle: LibraryLayoutStyle {
        get { LibraryLayoutStyle(rawValue: layoutStyleRaw) ?? .grid }
        set { layoutStyleRaw = newValue.rawValue }
    }

    private var coverPreference: CoverPreference {
        get { CoverPreference(rawValue: coverPrefRaw) ?? .preferEbook }
        set { coverPrefRaw = newValue.rawValue }
    }

    private var coverSize: CoverSize {
        get { CoverSize(rawValue: coverSizeRaw) ?? .medium }
        set { coverSizeRaw = newValue.rawValue }
    }

    @State private var cachedDisplayItems: [BookMetadata] = []
    @State private var cachedAvailableTags: [String] = []
    @State private var cachedAvailableSeries: [String] = []
    @State private var cachedAvailableAuthors: [String] = []
    @State private var cachedAvailableNarrators: [String] = []
    @State private var cachedAvailableStatuses: [String] = []
    @State private var cachedFiltersSummary: String = ""
    @State private var lastCachedLibraryVersion: Int = -1

    private static let defaultHorizontalSpacing: CGFloat = 16
    private let horizontalSpacing: CGFloat = MediaGridView.defaultHorizontalSpacing
    private let verticalSpacing: CGFloat = 24
    private let gridHorizontalPadding: CGFloat = 16
    private let sidebarWidth: CGFloat = 340
    private let sidebarSpacing: CGFloat = 1
    private let headerFontSize: CGFloat = 32

    #if os(macOS)
    private let platformMinimumWidth: CGFloat = 550
    #else
    // TODO: what floor makes sense here for iOS?
    private let platformMinimumWidth: CGFloat = 0
    #endif

    init(
        title: String,
        searchText: String = "",
        mediaKind: MediaKind = .ebook,
        tagFilter: String? = nil,
        seriesFilter: String? = nil,
        collectionFilter: String? = nil,
        authorFilter: String? = nil,
        narratorFilter: String? = nil,
        statusFilter: String? = nil,
        defaultSort: String? = nil,
        preferredTileWidth: CGFloat = 250,
        minimumTileWidth: CGFloat = 10,
        columnBreakpoints: [ColumnBreakpoint]? = nil,
        onReadNow: ((BookMetadata) -> Void)? = { _ in },
        onRename: ((BookMetadata) -> Void)? = { _ in },
        onDelete: ((BookMetadata) -> Void)? = { _ in },
        onSeriesSelected: ((String) -> Void)? = nil,
        initialNarrationFilterOption: NarrationFilter = .both,
        initialLocationFilter: LocationFilterOption = .all,
        scrollPosition: Binding<BookMetadata.ID?>? = nil
    ) {
        self.title = title
        self.searchText = searchText
        self.mediaKind = mediaKind
        self.tagFilter = tagFilter
        self.seriesFilter = seriesFilter
        self.collectionFilter = collectionFilter
        self.authorFilter = authorFilter
        self.narratorFilter = narratorFilter
        self.statusFilter = statusFilter
        self.defaultSort = defaultSort
        self.preferredTileWidth = preferredTileWidth
        self.minimumTileWidth = minimumTileWidth
        let resolvedBreakpoints: [ColumnBreakpoint] =
            if let columnBreakpoints {
                columnBreakpoints.sorted { $0.minWidth < $1.minWidth }
            } else {
                MediaGridView.defaultColumnBreakpoints(
                    preferredTileWidth: preferredTileWidth,
                )
            }
        self.columnBreakpoints = resolvedBreakpoints
        self.onReadNow = onReadNow ?? { _ in }
        self.onRename = onRename ?? { _ in }
        self.onDelete = onDelete ?? { _ in }
        self.onSeriesSelected = onSeriesSelected
        self.initialNarrationFilterOption = initialNarrationFilterOption
        self.scrollPosition = scrollPosition
        _selectedFormatFilter = State(
            initialValue: MediaGridView.mapNarrationToFormatFilter(initialNarrationFilterOption)
        )
        _selectedTag = State(initialValue: tagFilter)
        _selectedSeries = State(initialValue: seriesFilter)
        _selectedCollection = State(initialValue: collectionFilter)
        _selectedAuthor = State(initialValue: authorFilter)
        _selectedNarrator = State(initialValue: narratorFilter)
        _selectedStatus = State(initialValue: statusFilter)
        _selectedLocation = State(initialValue: initialLocationFilter)

        let sortOption: SortOption
        if let defaultSort, let option = SortOption(rawValue: defaultSort) {
            sortOption = option
        } else {
            sortOption = .titleAZ
        }
        _selectedSortOption = State(initialValue: sortOption)
        _showSeriesPositionBadge = State(initialValue: seriesFilter != nil)
    }

    private static func defaultColumnBreakpoints(preferredTileWidth: CGFloat) -> [ColumnBreakpoint]
    {
        let spacing = defaultHorizontalSpacing
        var breakpoints: [ColumnBreakpoint] = []
        let maxColumns = 10
        guard preferredTileWidth > 0 else {
            return breakpoints
        }

        for columns in 4...maxColumns {
            let width = (preferredTileWidth * CGFloat(columns)) + (spacing * CGFloat(columns - 1))
            breakpoints.append(ColumnBreakpoint(columns: columns, minWidth: width))
        }

        return breakpoints
    }

    private struct LayoutConfiguration {
        let columns: [GridItem]
        let tileWidth: CGFloat
    }

    private func resolvedLayout(for containerWidth: CGFloat) -> LayoutConfiguration {
        let availableWidth = max(0, containerWidth - (gridHorizontalPadding * 2))
        guard availableWidth > 0 else {
            let fallbackColumns = max(columnBreakpoints.first?.columns ?? 1, 1)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: horizontalSpacing, alignment: .top),
                count: fallbackColumns
            )
            return LayoutConfiguration(
                columns: columns,
                tileWidth: minimumTileWidth,
            )
        }

        var targetColumns =
            columnBreakpoints.last { breakpoint in
                availableWidth >= breakpoint.minWidth
            }?.columns ?? columnBreakpoints.first?.columns ?? 1

        var currentTileWidth = tileWidth(forColumns: targetColumns, availableWidth: availableWidth)

        while currentTileWidth < minimumTileWidth, targetColumns > 1 {
            targetColumns -= 1
            currentTileWidth = tileWidth(forColumns: targetColumns, availableWidth: availableWidth)
        }

        currentTileWidth = max(minimumTileWidth, currentTileWidth)

        let columns = Array(
            repeating: GridItem(
                .fixed(currentTileWidth),
                spacing: horizontalSpacing,
                alignment: .top
            ),
            count: targetColumns
        )
        return LayoutConfiguration(columns: columns, tileWidth: currentTileWidth)
    }

    private func tileWidth(forColumns columnCount: Int, availableWidth: CGFloat) -> CGFloat {
        guard columnCount > 0 else { return availableWidth }
        let spacingTotal = horizontalSpacing * CGFloat(max(columnCount - 1, 0))
        let usableWidth = max(availableWidth - spacingTotal, 0)
        return usableWidth / CGFloat(columnCount)
    }

    var body: some View {
        GeometryReader { geometry in
            #if os(macOS)
            let shouldShowSidebar = isSidebarVisible && activeInfoItem != nil
            let usesTableLayout = layoutStyle == .list || layoutStyle == .compactList
            #else
            let shouldShowSidebar = false
            #endif
            let availableWidth = geometry.size.width
            let detailWidth = sidebarWidth + sidebarSpacing
            let contentWidth =
                shouldShowSidebar
                ? max(availableWidth - detailWidth, 0)
                : max(availableWidth, platformMinimumWidth)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    #if os(macOS)
                    if usesTableLayout {
                        tableContent(for: max(contentWidth, minimumTileWidth))
                            .frame(width: max(contentWidth, minimumTileWidth))
                    } else {
                        scrollableContent(for: max(contentWidth, minimumTileWidth))
                    }
                    #else
                    scrollableContent(for: max(contentWidth, minimumTileWidth))
                    #endif

                    #if os(macOS)
                    if shouldShowSidebar, let activeInfoItem {
                        MediaGridInfoSidebar(
                            item: activeInfoItem,
                            mediaKind: mediaKind,
                            onClose: { dismissSidebar() },
                            onReadNow: {
                                onReadNow(activeInfoItem)
                                dismissSidebar()
                            },
                            onRename: {
                                onRename(activeInfoItem)
                            },
                            onDelete: {
                                onDelete(activeInfoItem)
                                dismissSidebar()
                            },
                            onSeriesSelected: onSeriesSelected.map { handler in
                                { seriesName in
                                    dismissSidebar()
                                    handler(seriesName)
                                }
                            }
                        )
                    }
                    #endif
                }
            }
        }
        .frame(minWidth: platformMinimumWidth)
        #if os(macOS)
        .focusable(true)
        .focusEffectDisabled(true)
        .onMoveCommand(perform: handleMoveCommand)
        .onKeyPress(.escape) {
            if isSidebarVisible {
                dismissSidebar()
                return .handled
            }
            return .ignored
        }
        #endif
    }

    @ViewBuilder
    private func scrollableContent(for contentWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                content(for: contentWidth)
            }
            .frame(width: contentWidth)
            .contentMargins(.trailing, 10, for: .scrollIndicators)
            .scrollClipDisabled(true)
            .modifier(SoftScrollEdgeModifier())
            .contentShape(Rectangle())
            .onTapGesture {
                #if os(macOS)
                if cardTapInProgress {
                    cardTapInProgress = false
                    return
                }
                #endif
                activeInfoItem = nil
                dismissSidebar()
            }
            #if os(macOS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in }
            )
            #endif
            #if os(iOS)
            .overlay(alignment: .trailing) {
                if shouldShowAlphabetScrubber {
                    AlphabetScrubber(
                        items: cachedDisplayItems,
                        textForItem: { item in
                            selectedSortOption == .authorAZ
                                ? (item.authors?.first?.name ?? item.title)
                                : item.title
                        },
                        idForItem: { $0.id },
                        proxy: proxy
                    )
                    .padding(.top, 120)
                    .padding(.bottom, 40)
                }
            }
            #endif
        }
    }

    #if os(macOS)
    @ViewBuilder
    private func tableContent(for contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tableHeader
                .padding(.horizontal, gridHorizontalPadding)
                .padding(.leading, 8)
                .padding(.top)

            if cachedDisplayItems.isEmpty {
                emptyStateView
                    .padding(.horizontal, gridHorizontalPadding)
            } else {
                MediaTableView(
                    items: cachedDisplayItems,
                    mediaKind: mediaKind,
                    coverPreference: coverPreference,
                    showAudioIndicator: settingsViewModel.showAudioIndicator,
                    compact: layoutStyle == .compactList,
                    selection: Binding(
                        get: { activeInfoItem?.id },
                        set: { newID in
                            activeInfoItem = cachedDisplayItems.first { $0.id == newID }
                        }
                    ),
                    columnVisibility: $columnVisibility,
                    onSelect: { selectItem($0) },
                    onInfo: { openSidebar(for: $0) }
                )
            }
        }
        .onAppear {
            recomputeAllCaches()
        }
        .onChange(of: mediaViewModel.libraryVersion) { _, _ in
            recomputeAllCaches()
        }
        .onChange(of: selectedFormatFilter) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedTag) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedSeries) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedStatus) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedLocation) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedNarrator) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedAuthor) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedSortOption) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: mediaKind) { _, _ in
            recomputeAllCaches()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: searchText) { _, _ in
            recomputeDisplayItems()
        }
        .onChange(of: initialNarrationFilterOption) { _, _ in
            selectedFormatFilter =
                MediaGridView.mapNarrationToFormatFilter(initialNarrationFilterOption)
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
    }

    private var tableHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: headerFontSize, weight: .regular, design: .serif))

            MediaGridSortAndFilterBar(
                selectedSortOption: $selectedSortOption,
                selectedFormatFilter: $selectedFormatFilter,
                selectedTag: $selectedTag,
                selectedSeries: $selectedSeries,
                selectedAuthor: $selectedAuthor,
                selectedNarrator: $selectedNarrator,
                selectedStatus: $selectedStatus,
                selectedLocation: $selectedLocation,
                layoutStyle: Binding(
                    get: { layoutStyle },
                    set: { layoutStyleRaw = $0.rawValue }
                ),
                coverPreference: Binding(
                    get: { coverPreference },
                    set: { coverPrefRaw = $0.rawValue }
                ),
                coverSize: Binding(
                    get: { coverSize },
                    set: { coverSizeRaw = $0.rawValue }
                ),
                showAudioIndicator: Binding(
                    get: { settingsViewModel.showAudioIndicator },
                    set: { newValue in
                        settingsViewModel.showAudioIndicator = newValue
                        Task { try? await settingsViewModel.save() }
                    }
                ),
                showSourceBadge: $showSourceBadge,
                showSeriesPositionBadge: $showSeriesPositionBadge,
                availableTags: cachedAvailableTags,
                availableSeries: cachedAvailableSeries,
                availableAuthors: cachedAvailableAuthors,
                availableNarrators: cachedAvailableNarrators,
                availableStatuses: cachedAvailableStatuses,
                filtersSummaryText: cachedFiltersSummary,
                showLayoutOption: true,
                columnVisibility: $columnVisibility,
                onResetColumns: {
                    columnVisibility = .defaultVisibility(compact: layoutStyle == .compactList)
                }
            )
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text("No media is available here yet!")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(
                "To add some media, use the Media Sources on the left to load either local files or a remote Storyteller server."
            )
            .font(.body)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 60)
    }
    #endif


    private var contentFilterBar: some View {
        MediaGridSortAndFilterBar(
            selectedSortOption: $selectedSortOption,
            selectedFormatFilter: $selectedFormatFilter,
            selectedTag: $selectedTag,
            selectedSeries: $selectedSeries,
            selectedAuthor: $selectedAuthor,
            selectedNarrator: $selectedNarrator,
            selectedStatus: $selectedStatus,
            selectedLocation: $selectedLocation,
            layoutStyle: Binding(
                get: { layoutStyle },
                set: { layoutStyleRaw = $0.rawValue }
            ),
            coverPreference: Binding(
                get: { coverPreference },
                set: { coverPrefRaw = $0.rawValue }
            ),
            coverSize: Binding(
                get: { coverSize },
                set: { coverSizeRaw = $0.rawValue }
            ),
            showAudioIndicator: Binding(
                get: { settingsViewModel.showAudioIndicator },
                set: { newValue in
                    settingsViewModel.showAudioIndicator = newValue
                    Task { await settingsViewModel.save() }
                }
            ),
            showSourceBadge: $showSourceBadge,
            showSeriesPositionBadge: $showSeriesPositionBadge,
            availableTags: cachedAvailableTags,
            availableSeries: cachedAvailableSeries,
            availableAuthors: cachedAvailableAuthors,
            availableNarrators: cachedAvailableNarrators,
            availableStatuses: cachedAvailableStatuses,
            filtersSummaryText: cachedFiltersSummary,
            showLayoutOption: true
        )
    }

    @ViewBuilder
    private func content(for containerWidth: CGFloat) -> some View {
        let layout = resolvedLayout(for: containerWidth)
        let tileMetrics = MediaItemCardMetrics.make(for: layout.tileWidth, mediaKind: mediaKind, coverPreference: coverPreference)
        let columnCount = max(layout.columns.count, 1)

        VStack(alignment: .leading, spacing: verticalSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: headerFontSize, weight: .regular, design: .serif))

                contentFilterBar
            }
            .padding(.horizontal, gridHorizontalPadding)
            .padding(.leading, 8)

            if cachedDisplayItems.isEmpty {
                VStack(spacing: 12) {
                    Text("No media is available here yet!")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    #if os(iOS)
                    Text("To add some media, go to Settings to connect a Storyteller server.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    #else
                    Text(
                        "To add some media, use the Media Sources on the left to load either local files or a remote Storyteller server."
                    )
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    #endif
                }
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 60)
                .padding(.horizontal, gridHorizontalPadding)
            } else {
                switch layoutStyle {
                case .grid, .fan:
                    let gridTileSize = coverSize.gridTileWidth
                    let gridColumns = [GridItem(.adaptive(minimum: gridTileSize, maximum: gridTileSize + 40), spacing: horizontalSpacing)]
                    let gridMetrics = MediaItemCardMetrics.make(for: gridTileSize, mediaKind: mediaKind, coverPreference: coverPreference)
                    #if os(iOS)
                    let gridAlignment: HorizontalAlignment = .center
                    #else
                    let gridAlignment: HorizontalAlignment = .leading
                    #endif
                    LazyVGrid(columns: gridColumns, alignment: gridAlignment, spacing: verticalSpacing) {
                        ForEach(cachedDisplayItems) { item in
                            card(for: item, metrics: gridMetrics)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, gridHorizontalPadding)
                case .compactGrid:
                    let compactTileSize = coverSize.gridTileWidth
                    let compactColumns = [GridItem(.adaptive(minimum: compactTileSize, maximum: compactTileSize + 20), spacing: 4)]
                    #if os(iOS)
                    let compactGridAlignment: HorizontalAlignment = .center
                    #else
                    let compactGridAlignment: HorizontalAlignment = .leading
                    #endif
                    LazyVGrid(columns: compactColumns, alignment: compactGridAlignment, spacing: 4) {
                        ForEach(cachedDisplayItems) { item in
                            MediaCompactCardView(
                                item: item,
                                coverPreference: coverPreference,
                                tileSize: compactTileSize,
                                showAudioIndicator: settingsViewModel.showAudioIndicator,
                                sourceLabel: showSourceBadge ? mediaViewModel.sourceLabel(for: item.id) : nil,
                                seriesPositionBadge: seriesPositionBadge(for: item),
                                isSelected: activeInfoItem?.id == item.id,
                                onSelect: { selected in
                                    selectItem(selected)
                                },
                                onInfo: { selected in
                                    openSidebar(for: selected)
                                }
                            )
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, gridHorizontalPadding)
                case .list:
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(cachedDisplayItems) { item in
                            MediaListRowView(
                                item: item,
                                mediaKind: mediaKind,
                                coverPreference: coverPreference,
                                showAudioIndicator: settingsViewModel.showAudioIndicator,
                                sourceLabel: showSourceBadge ? mediaViewModel.sourceLabel(for: item.id) : nil,
                                seriesPositionBadge: seriesPositionBadge(for: item),
                                isSelected: activeInfoItem?.id == item.id,
                                onSelect: { selected in
                                    selectItem(selected)
                                },
                                onInfo: { selected in
                                    openSidebar(for: selected)
                                }
                            )
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, gridHorizontalPadding)
                case .compactList:
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(cachedDisplayItems) { item in
                            MediaCompactListRowView(
                                item: item,
                                isSelected: activeInfoItem?.id == item.id,
                                onSelect: { selected in
                                    selectItem(selected)
                                },
                                onInfo: { selected in
                                    openSidebar(for: selected)
                                }
                            )
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, gridHorizontalPadding)
                }
            }
        }
        .padding(.vertical)
        .onAppear {
            lastKnownColumnCount = columnCount
            recomputeAllCaches()
        }
        .onChange(of: columnCount) { oldValue, newValue in
            lastKnownColumnCount = newValue
        }
        .onChange(of: mediaViewModel.libraryVersion) { _, _ in
            recomputeAllCaches()
        }
        .onChange(of: selectedFormatFilter) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedTag) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedSeries) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedStatus) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedLocation) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedNarrator) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedAuthor) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: selectedSortOption) { _, _ in
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: mediaKind) { _, _ in
            recomputeAllCaches()
            reconcileSelectionAfterFiltering()
        }
        .onChange(of: searchText) { _, _ in
            recomputeDisplayItems()
        }
        .onChange(of: initialNarrationFilterOption) { _, _ in
            selectedFormatFilter =
                MediaGridView.mapNarrationToFormatFilter(initialNarrationFilterOption)
            recomputeDisplayItems()
            reconcileSelectionAfterFiltering()
        }
    }

    static func mapNarrationToFormatFilter(_ narration: NarrationFilter) -> FormatFilterOption {
        switch narration {
            case .both: .all
            case .withAudio: .audiobook
            case .withoutAudio: .ebookOnly
        }
    }

    @ViewBuilder
    private func card(for item: BookMetadata, metrics: MediaItemCardMetrics) -> some View {
        let sourceLabel = showSourceBadge ? mediaViewModel.sourceLabel(for: item.id) : nil
        let seriesPositionBadge = seriesPositionBadge(for: item)
        #if os(macOS)
        MediaItemCardView(
            item: item,
            mediaKind: mediaKind,
            metrics: metrics,
            isSelected: activeInfoItem?.id == item.id,
            showAudioIndicator: settingsViewModel.showAudioIndicator,
            sourceLabel: sourceLabel,
            seriesPositionBadge: seriesPositionBadge,
            coverPreference: coverPreference,
            onSelect: { selected in
                selectItem(selected)
            },
            onInfo: { selected in
                openSidebar(for: selected)
            }
        )
        #else
        MediaItemCardView(
            item: item,
            mediaKind: mediaKind,
            metrics: metrics,
            isSelected: activeInfoItem?.id == item.id,
            showAudioIndicator: settingsViewModel.showAudioIndicator,
            sourceLabel: sourceLabel,
            seriesPositionBadge: seriesPositionBadge,
            coverPreference: coverPreference,
            onSelect: { selected in
                selectItem(selected)
            },
            onInfo: { selected in
                openSidebar(for: selected)
            }
        )
        #endif
    }

    private func seriesPositionBadge(for item: BookMetadata) -> String? {
        guard showSeriesPositionBadge else { return nil }
        guard let seriesList = item.series else { return nil }

        let matchingSeries: BookSeries?
        if let filter = selectedSeries {
            let normalizedFilter = filter.lowercased()
            matchingSeries = seriesList.first(where: { $0.name.lowercased() == normalizedFilter })
        } else {
            matchingSeries = seriesList.first
        }

        guard let series = matchingSeries, let position = series.position else { return nil }
        return "#\(position)"
    }

    private func selectItem(_ item: BookMetadata, ensureVisible: Bool = false) {
        #if os(macOS)
        cardTapInProgress = true
        #endif
        guard cachedDisplayItems.contains(where: { $0.id == item.id }) else { return }
        shouldEnsureActiveItemVisible = ensureVisible
        activeInfoItem = item
    }

    private func openSidebar(for item: BookMetadata) {
        activeInfoItem = item
        if !isSidebarVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSidebarVisible = true
            }
        }
    }

    private func dismissSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarVisible = false
        }
    }

    #if os(iOS)
    private var shouldShowAlphabetScrubber: Bool {
        let isAlphabeticalSort = selectedSortOption == .titleAZ || selectedSortOption == .authorAZ
        return isAlphabeticalSort
    }
    #endif

    private func reconcileSelectionAfterFiltering() {
        guard let activeInfoItem else { return }
        if !cachedDisplayItems.contains(where: { $0.id == activeInfoItem.id }) {
            clearSelection()
        }
    }

    private func clearSelection() {
        activeInfoItem = nil
        isSidebarVisible = false
    }

    private struct ItemLocationInfo: Sendable {
        let isDownloaded: Bool
        let isLocalStandalone: Bool
    }

    private func captureLocationInfo(for items: [BookMetadata]) -> [BookMetadata.ID: ItemLocationInfo] {
        var info: [BookMetadata.ID: ItemLocationInfo] = [:]
        for item in items {
            let isDownloaded = mediaViewModel.isCategoryDownloaded(.ebook, for: item)
                || mediaViewModel.isCategoryDownloaded(.audio, for: item)
                || mediaViewModel.isCategoryDownloaded(.synced, for: item)
            let isLocal = mediaViewModel.isLocalStandaloneBook(item.id)
            info[item.id] = ItemLocationInfo(isDownloaded: isDownloaded, isLocalStandalone: isLocal)
        }
        return info
    }

    private func recomputeDisplayItems() {
        let baseItems = itemsForCurrentFormatSelection()
        let locationInfo = captureLocationInfo(for: baseItems)
        let formatFilter = selectedFormatFilter
        let tagSel = selectedTag
        let seriesSel = selectedSeries
        let collectionSel = selectedCollection
        let authorSel = selectedAuthor
        let narratorSel = selectedNarrator
        let statusSel = selectedStatus
        let locationSel = selectedLocation
        let search = searchText
        let sortOpt = selectedSortOption
        let filtersSummary = computeFiltersSummary()

        Task.detached(priority: .userInitiated) {
            let result = Self.computeDisplayItemsOffThread(
                base: baseItems,
                locationInfo: locationInfo,
                formatFilter: formatFilter,
                tagFilter: tagSel,
                seriesFilter: seriesSel,
                collectionFilter: collectionSel,
                authorFilter: authorSel,
                narratorFilter: narratorSel,
                statusFilter: statusSel,
                locationFilter: locationSel,
                searchText: search,
                sortOption: sortOpt
            )
            await MainActor.run {
                self.cachedDisplayItems = result
                self.cachedFiltersSummary = filtersSummary
            }
        }
    }

    private func recomputeFilterOptions() {
        let catalog = catalogItemsForFilters

        Task.detached(priority: .userInitiated) {
            let newTags = Self.computeAvailableTagsOffThread(from: catalog)
            let newSeries = Self.computeAvailableSeriesOffThread(from: catalog)
            let newAuthors = Self.computeAvailableAuthorsOffThread(from: catalog)
            let newNarrators = Self.computeAvailableNarratorsOffThread(from: catalog)
            let newStatuses = Self.computeAvailableStatusesOffThread(from: catalog)
            await MainActor.run {
                self.cachedAvailableTags = newTags
                self.cachedAvailableSeries = newSeries
                self.cachedAvailableAuthors = newAuthors
                self.cachedAvailableNarrators = newNarrators
                self.cachedAvailableStatuses = newStatuses
                self.lastCachedLibraryVersion = self.mediaViewModel.libraryVersion
            }
        }
    }

    private func recomputeAllCaches() {
        let catalog = catalogItemsForFilters
        let baseItems = itemsForCurrentFormatSelection()
        let locationInfo = captureLocationInfo(for: baseItems)
        let formatFilter = selectedFormatFilter
        let tagSel = selectedTag
        let seriesSel = selectedSeries
        let collectionSel = selectedCollection
        let authorSel = selectedAuthor
        let narratorSel = selectedNarrator
        let statusSel = selectedStatus
        let locationSel = selectedLocation
        let search = searchText
        let sortOpt = selectedSortOption
        let filtersSummary = computeFiltersSummary()

        Task.detached(priority: .userInitiated) {
            let newTags = Self.computeAvailableTagsOffThread(from: catalog)
            let newSeries = Self.computeAvailableSeriesOffThread(from: catalog)
            let newAuthors = Self.computeAvailableAuthorsOffThread(from: catalog)
            let newNarrators = Self.computeAvailableNarratorsOffThread(from: catalog)
            let newStatuses = Self.computeAvailableStatusesOffThread(from: catalog)
            let newDisplayItems = Self.computeDisplayItemsOffThread(
                base: baseItems,
                locationInfo: locationInfo,
                formatFilter: formatFilter,
                tagFilter: tagSel,
                seriesFilter: seriesSel,
                collectionFilter: collectionSel,
                authorFilter: authorSel,
                narratorFilter: narratorSel,
                statusFilter: statusSel,
                locationFilter: locationSel,
                searchText: search,
                sortOption: sortOpt
            )
            await MainActor.run {
                self.cachedAvailableTags = newTags
                self.cachedAvailableSeries = newSeries
                self.cachedAvailableAuthors = newAuthors
                self.cachedAvailableNarrators = newNarrators
                self.cachedAvailableStatuses = newStatuses
                self.lastCachedLibraryVersion = self.mediaViewModel.libraryVersion
                self.cachedDisplayItems = newDisplayItems
                self.cachedFiltersSummary = filtersSummary
            }
        }
    }

    private func scrollToActiveItem(using proxy: ScrollViewProxy) {
        guard let id = activeInfoItem?.id else { return }
        if let binding = scrollPosition {
            binding.wrappedValue = id
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private func restoreScrollPosition(
        using proxy: ScrollViewProxy,
        binding: Binding<BookMetadata.ID?>
    ) {
        let target = binding.wrappedValue ?? headerScrollID
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func computeDisplayItems() -> [BookMetadata] {
        let base = itemsForCurrentFormatSelection()
        let formatFiltered = base.filter { selectedFormatFilter.matches($0) }
        let tagFiltered = formatFiltered.filter { matchesSelectedTag($0) }
        let seriesFiltered = tagFiltered.filter { matchesSelectedSeries($0) }
        let collectionFiltered = seriesFiltered.filter { matchesSelectedCollection($0) }
        let authorFiltered = collectionFiltered.filter { matchesSelectedAuthor($0) }
        let narratorFiltered = authorFiltered.filter { matchesSelectedNarrator($0) }
        let statusFiltered = narratorFiltered.filter { matchesSelectedStatus($0) }
        let locationFiltered = statusFiltered.filter { matchesSelectedLocation($0) }
        let searchFiltered = locationFiltered.filter { matchesSearchText($0) }
        let sorted =
            searchFiltered.sorted { lhs, rhs in
                if lhs.id == rhs.id { return false }
                let result: ComparisonResult
                if selectedSortOption == .seriesPosition, let filter = selectedSeries {
                    let normalizedFilter = filter.lowercased()
                    let lhsPosition = lhs.series?.first(where: { $0.name.lowercased() == normalizedFilter })?.position ?? Int.max
                    let rhsPosition = rhs.series?.first(where: { $0.name.lowercased() == normalizedFilter })?.position ?? Int.max
                    if lhsPosition == rhsPosition {
                        result = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    } else {
                        result = lhsPosition < rhsPosition ? .orderedAscending : .orderedDescending
                    }
                } else {
                    result = selectedSortOption.comparison(lhs, rhs)
                }
                if result == .orderedSame {
                    return lhs.id < rhs.id
                }
                return result == .orderedAscending
            }
        return sorted
    }

    private func itemsForCurrentFormatSelection() -> [BookMetadata] {
        var primary = mediaViewModel.items(
            for: mediaKind,
            narrationFilter: .both,
            tagFilter: tagFilter
        )
        if selectedFormatFilter.includesAudiobookOnlyItems {
            let audioOnlyItems = mediaViewModel.items(
                for: .audiobook,
                narrationFilter: .both,
                tagFilter: tagFilter
            )
            primary = merge(primary, with: audioOnlyItems)
        }
        return primary
    }

    private var catalogItemsForFilters: [BookMetadata] {
        if mediaKind == .audiobook {
            return mediaViewModel.items(
                for: .audiobook,
                narrationFilter: .both,
                tagFilter: tagFilter
            )
        }
        let primary = mediaViewModel.items(
            for: mediaKind,
            narrationFilter: .both,
            tagFilter: tagFilter
        )
        let audioOnly = mediaViewModel.items(
            for: .audiobook,
            narrationFilter: .both,
            tagFilter: tagFilter
        )
        return merge(primary, with: audioOnly)
    }

    private func merge(_ primary: [BookMetadata], with supplemental: [BookMetadata])
        -> [BookMetadata]
    {
        guard !supplemental.isEmpty else { return primary }
        var result = primary
        var seen = Set(result.map(\.id))
        for item in supplemental where !seen.contains(item.id) {
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }

    private func matchesSelectedTag(_ item: BookMetadata) -> Bool {
        guard let tag = selectedTag else { return true }
        let normalized = tag.lowercased()
        return item.tagNames.contains { $0.lowercased() == normalized }
    }

    private func matchesSelectedSeries(_ item: BookMetadata) -> Bool {
        guard let series = selectedSeries else { return true }
        if series == SeriesView.noSeriesFilterKey {
            return item.series == nil || item.series?.isEmpty == true
        }
        let normalized = series.lowercased()
        return item.series?.contains(where: { $0.name.lowercased() == normalized }) ?? false
    }

    private func matchesSelectedCollection(_ item: BookMetadata) -> Bool {
        guard let collection = selectedCollection else { return true }
        let normalized = collection.lowercased()
        return item.collections?.contains(where: {
            $0.uuid?.lowercased() == normalized || $0.name.lowercased() == normalized
        }) ?? false
    }

    private func matchesSelectedAuthor(_ item: BookMetadata) -> Bool {
        guard let author = selectedAuthor else { return true }
        let normalized = author.lowercased()
        return item.authors?.contains(where: { $0.name?.lowercased() == normalized }) ?? false
    }

    private func matchesSelectedNarrator(_ item: BookMetadata) -> Bool {
        guard let narrator = selectedNarrator else { return true }
        if narrator == "Unknown Narrator" {
            guard let narrators = item.narrators, !narrators.isEmpty else { return true }
            return narrators.allSatisfy { narrator in
                guard let name = narrator.name?.trimmingCharacters(in: .whitespacesAndNewlines) else { return true }
                return name.isEmpty
            }
        }
        let normalized = narrator.lowercased()
        return item.narrators?.contains(where: { $0.name?.lowercased() == normalized }) ?? false
    }

    private func matchesSelectedStatus(_ item: BookMetadata) -> Bool {
        guard let status = selectedStatus else { return true }
        guard let itemStatus = item.status?.name else { return false }
        return itemStatus.caseInsensitiveCompare(status) == .orderedSame
    }

    private func matchesSelectedLocation(_ item: BookMetadata) -> Bool {
        switch selectedLocation {
            case .all:
                return true
            case .downloaded:
                return hasAnyDownloadedCategory(for: item)
            case .serverOnly:
                return !hasAnyDownloadedCategory(for: item)
                    && !mediaViewModel.isLocalStandaloneBook(item.id)
            case .localFiles:
                return mediaViewModel.isLocalStandaloneBook(item.id)
        }
    }

    private func hasAnyDownloadedCategory(for item: BookMetadata) -> Bool {
        return mediaViewModel.isCategoryDownloaded(.ebook, for: item)
            || mediaViewModel.isCategoryDownloaded(.audio, for: item)
            || mediaViewModel.isCategoryDownloaded(.synced, for: item)
    }

    private func matchesSearchText(_ item: BookMetadata) -> Bool {
        guard searchText.count >= 2 else { return true }

        let terms = searchText.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return true }

        let title = item.title.lowercased()
        let authorNames = (item.authors ?? []).compactMap { $0.name?.lowercased() }
        let seriesNames = (item.series ?? []).compactMap { $0.name.lowercased() }

        for term in terms {
            let matchesTitle = title.contains(term)
            let matchesAuthor = authorNames.contains { $0.contains(term) }
            let matchesSeries = seriesNames.contains { $0.contains(term) }

            if !matchesTitle && !matchesAuthor && !matchesSeries {
                return false
            }
        }

        return true
    }

    private func computeAvailableTags(from catalog: [BookMetadata]) -> [String] {
        var unique: [String: String] = [:]
        for rawTag
            in catalog
            .flatMap(\.tagNames)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
        {
            let key = rawTag.lowercased()
            if unique[key] == nil {
                unique[key] = rawTag
            }
        }
        return unique.values
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func computeAvailableStatuses(from catalog: [BookMetadata]) -> [String] {
        let statuses =
            catalog
            .compactMap { metadata in
                metadata.status?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        var unique: [String: String] = [:]
        for status in statuses {
            let key = status.lowercased()
            if unique[key] == nil {
                unique[key] = status
            }
        }
        return unique.values
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func computeAvailableSeries(from catalog: [BookMetadata]) -> [String] {
        var unique: [String: String] = [:]
        for rawSeries
            in catalog
            .compactMap(\.series)
            .flatMap({ $0 })
            .map({ $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
        {
            let key = rawSeries.lowercased()
            if unique[key] == nil {
                unique[key] = rawSeries
            }
        }
        return unique.values
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func computeAvailableAuthors(from catalog: [BookMetadata]) -> [String] {
        var unique: [String: String] = [:]
        for rawAuthor
            in catalog
            .compactMap(\.authors)
            .flatMap({ $0 })
            .compactMap({ $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
        {
            let key = rawAuthor.lowercased()
            if unique[key] == nil {
                unique[key] = rawAuthor
            }
        }
        return unique.values
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func computeAvailableNarrators(from catalog: [BookMetadata]) -> [String] {
        var unique: [String: String] = [:]
        var hasUnknown = false
        for item in catalog {
            if let narrators = item.narrators, !narrators.isEmpty {
                for narrator in narrators {
                    if let name = narrator.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                        let key = name.lowercased()
                        if unique[key] == nil {
                            unique[key] = name
                        }
                    } else {
                        hasUnknown = true
                    }
                }
            } else {
                hasUnknown = true
            }
        }
        var result = unique.values
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if hasUnknown {
            result.append("Unknown Narrator")
        }
        return result
    }

    private func computeFiltersSummary() -> String {
        var parts: [String] = [selectedFormatFilter.shortLabel]
        if let status = selectedStatus {
            parts.append(status)
        }
        if let tag = selectedTag {
            parts.append(tag)
        }
        if let series = selectedSeries {
            parts.append(series)
        }
        if let author = selectedAuthor {
            parts.append(author)
        }
        if let narrator = selectedNarrator {
            parts.append(narrator)
        }
        if selectedLocation != .all {
            parts.append(selectedLocation.shortLabel)
        }
        return parts.joined(separator: " • ")
    }

    private static nonisolated func computeDisplayItemsOffThread(
        base: [BookMetadata],
        locationInfo: [BookMetadata.ID: ItemLocationInfo],
        formatFilter: FormatFilterOption,
        tagFilter: String?,
        seriesFilter: String?,
        collectionFilter: String?,
        authorFilter: String?,
        narratorFilter: String?,
        statusFilter: String?,
        locationFilter: LocationFilterOption,
        searchText: String,
        sortOption: SortOption
    ) -> [BookMetadata] {
        var filtered = base.filter { formatFilter.matches($0) }

        if let tag = tagFilter {
            let lowercasedTag = tag.lowercased()
            filtered = filtered.filter { item in
                item.tagNames.contains { $0.lowercased() == lowercasedTag }
            }
        }

        if let series = seriesFilter {
            if series == "No Series" {
                filtered = filtered.filter { $0.series?.isEmpty ?? true }
            } else {
                let lowercasedSeries = series.lowercased()
                filtered = filtered.filter { item in
                    guard let seriesList = item.series else { return false }
                    for s in seriesList {
                        if s.name.lowercased() == lowercasedSeries { return true }
                    }
                    return false
                }
            }
        }

        if let collection = collectionFilter {
            filtered = filtered.filter { item in
                guard let collections = item.collections else { return false }
                for col in collections {
                    if col.uuid == collection || col.name == collection {
                        return true
                    }
                }
                return false
            }
        }

        if let author = authorFilter {
            let lowercasedAuthor = author.lowercased()
            filtered = filtered.filter { item in
                guard let authors = item.authors else { return false }
                for a in authors {
                    if a.name?.lowercased() == lowercasedAuthor { return true }
                }
                return false
            }
        }

        if let narrator = narratorFilter {
            if narrator == "Unknown Narrator" {
                filtered = filtered.filter { item in
                    guard let narrators = item.narrators else { return true }
                    if narrators.isEmpty { return true }
                    for n in narrators {
                        if let name = n.name, !name.isEmpty { return false }
                    }
                    return true
                }
            } else {
                let lowercasedNarrator = narrator.lowercased()
                filtered = filtered.filter { item in
                    guard let narrators = item.narrators else { return false }
                    for n in narrators {
                        if n.name?.lowercased() == lowercasedNarrator { return true }
                    }
                    return false
                }
            }
        }

        if let status = statusFilter {
            let lowercasedStatus = status.lowercased()
            filtered = filtered.filter { $0.status?.name.lowercased() == lowercasedStatus }
        }

        switch locationFilter {
        case .all:
            break
        case .downloaded:
            filtered = filtered.filter { locationInfo[$0.id]?.isDownloaded ?? false }
        case .serverOnly:
            filtered = filtered.filter {
                let info = locationInfo[$0.id]
                return !(info?.isDownloaded ?? false) && !(info?.isLocalStandalone ?? false)
            }
        case .localFiles:
            filtered = filtered.filter { locationInfo[$0.id]?.isLocalStandalone ?? false }
        }

        if !searchText.isEmpty && searchText.count >= 2 {
            let terms = searchText.lowercased().split(separator: " ").map(String.init)
            filtered = filtered.filter { item in
                let title = item.title.lowercased()
                let authorNames = (item.authors ?? []).compactMap { $0.name?.lowercased() }
                let seriesNames = (item.series ?? []).compactMap { $0.name.lowercased() }

                for term in terms {
                    let matchesTitle = title.contains(term)
                    let matchesAuthor = authorNames.contains { $0.contains(term) }
                    let matchesSeries = seriesNames.contains { $0.contains(term) }
                    if !matchesTitle && !matchesAuthor && !matchesSeries {
                        return false
                    }
                }
                return true
            }
        }

        return filtered.sorted { lhs, rhs in
            if lhs.id == rhs.id { return false }
            let result: ComparisonResult
            if sortOption == .seriesPosition, let filter = seriesFilter {
                let normalizedFilter = filter.lowercased()
                let lhsPosition = lhs.series?.first(where: { $0.name.lowercased() == normalizedFilter })?.position ?? Int.max
                let rhsPosition = rhs.series?.first(where: { $0.name.lowercased() == normalizedFilter })?.position ?? Int.max
                if lhsPosition == rhsPosition {
                    result = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                } else {
                    result = lhsPosition < rhsPosition ? .orderedAscending : .orderedDescending
                }
            } else {
                result = sortOption.comparison(lhs, rhs)
            }
            if result == .orderedSame {
                return lhs.id < rhs.id
            }
            return result == .orderedAscending
        }
    }

    private static nonisolated func computeAvailableTagsOffThread(from catalog: [BookMetadata]) -> [String] {
        var unique: [String: String] = [:]
        for item in catalog {
            for rawTag in item.tagNames {
                let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if unique[key] == nil {
                    unique[key] = trimmed
                }
            }
        }
        return unique.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static nonisolated func computeAvailableSeriesOffThread(from catalog: [BookMetadata]) -> [String] {
        var unique: [String: String] = [:]
        for item in catalog {
            guard let seriesList = item.series else { continue }
            for series in seriesList {
                let trimmed = series.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if unique[key] == nil {
                    unique[key] = trimmed
                }
            }
        }
        return unique.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static nonisolated func computeAvailableAuthorsOffThread(from catalog: [BookMetadata]) -> [String] {
        var unique: [String: String] = [:]
        for item in catalog {
            guard let authors = item.authors else { continue }
            for author in authors {
                guard let name = author.name else { continue }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if unique[key] == nil {
                    unique[key] = trimmed
                }
            }
        }
        return unique.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static nonisolated func computeAvailableNarratorsOffThread(from catalog: [BookMetadata]) -> [String] {
        var unique: [String: String] = [:]
        var hasUnknown = false
        for item in catalog {
            if let narrators = item.narrators, !narrators.isEmpty {
                for narrator in narrators {
                    if let name = narrator.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                        let key = name.lowercased()
                        if unique[key] == nil {
                            unique[key] = name
                        }
                    } else {
                        hasUnknown = true
                    }
                }
            } else {
                hasUnknown = true
            }
        }
        var result = unique.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if hasUnknown {
            result.append("Unknown Narrator")
        }
        return result
    }

    private static nonisolated func computeAvailableStatusesOffThread(from catalog: [BookMetadata]) -> [String] {
        var unique: [String: String] = [:]
        for item in catalog {
            guard let statusName = item.status?.name else { continue }
            let trimmed = statusName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if unique[key] == nil {
                unique[key] = trimmed
            }
        }
        return unique.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    #if os(macOS)
    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        let visibleItems = cachedDisplayItems
        guard !visibleItems.isEmpty else {
            clearSelection()
            return
        }

        guard
            let nextItem = MediaGridViewUtilities.nextSelectableItem(
                from: direction,
                in: visibleItems,
                currentItemID: activeInfoItem?.id,
                columnCount: max(lastKnownColumnCount, 1)
            )
        else {
            return
        }
        selectItem(nextItem, ensureVisible: true)
    }
    #endif

    enum SortOption: String, CaseIterable, Identifiable {
        case titleAZ
        case titleZA
        case authorAZ
        case authorZA
        case progressHighToLow
        case progressLowToHigh
        case recentlyRead
        case recentlyAdded
        case seriesPosition

        var id: String { rawValue }

        var label: String {
            switch self {
                case .titleAZ:
                    "Title A-Z"
                case .titleZA:
                    "Title Z-A"
                case .authorAZ:
                    "Author A-Z"
                case .authorZA:
                    "Author Z-A"
                case .progressHighToLow:
                    "Progress High-Low"
                case .progressLowToHigh:
                    "Progress Low-High"
                case .recentlyRead:
                    "Recently Read"
                case .recentlyAdded:
                    "Recently Added"
                case .seriesPosition:
                    "Series Position"
            }
        }

        var shortLabel: String {
            switch self {
                case .titleAZ:
                    "Title A-Z"
                case .titleZA:
                    "Title Z-A"
                case .authorAZ:
                    "Author A-Z"
                case .authorZA:
                    "Author Z-A"
                case .progressHighToLow:
                    "Progress High-Low"
                case .progressLowToHigh:
                    "Progress Low-High"
                case .recentlyRead:
                    "Recently Read"
                case .recentlyAdded:
                    "Recently Added"
                case .seriesPosition:
                    "Series Position"
            }
        }

        func comparison(_ lhs: BookMetadata, _ rhs: BookMetadata) -> ComparisonResult {
            switch self {
                case .titleAZ:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                case .titleZA:
                    return rhs.title.localizedCaseInsensitiveCompare(lhs.title)
                case .authorAZ:
                    let lhsAuthor = lhs.authors?.first?.name ?? ""
                    let rhsAuthor = rhs.authors?.first?.name ?? ""
                    let result = lhsAuthor.localizedCaseInsensitiveCompare(rhsAuthor)
                    if result == .orderedSame {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    }
                    return result
                case .authorZA:
                    let lhsAuthor = lhs.authors?.first?.name ?? ""
                    let rhsAuthor = rhs.authors?.first?.name ?? ""
                    let result = rhsAuthor.localizedCaseInsensitiveCompare(lhsAuthor)
                    if result == .orderedSame {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    }
                    return result
                case .progressHighToLow:
                    if lhs.progress == rhs.progress {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    }
                    return lhs.progress > rhs.progress ? .orderedAscending : .orderedDescending
                case .progressLowToHigh:
                    if lhs.progress == rhs.progress {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    }
                    return lhs.progress < rhs.progress ? .orderedAscending : .orderedDescending
                case .recentlyRead:
                    let lhsDate = lhs.position?.updatedAt ?? ""
                    let rhsDate = rhs.position?.updatedAt ?? ""
                    if lhsDate == rhsDate {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    }
                    return lhsDate > rhsDate ? .orderedAscending : .orderedDescending
                case .recentlyAdded:
                    let lhsDate = lhs.createdAt ?? ""
                    let rhsDate = rhs.createdAt ?? ""
                    if lhsDate == rhsDate {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    }
                    return lhsDate > rhsDate ? .orderedAscending : .orderedDescending
                case .seriesPosition:
                    let lhsSeriesName = lhs.series?.first?.name ?? ""
                    let rhsSeriesName = rhs.series?.first?.name ?? ""

                    if lhsSeriesName.isEmpty && rhsSeriesName.isEmpty {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    }
                    if lhsSeriesName.isEmpty {
                        return .orderedDescending
                    }
                    if rhsSeriesName.isEmpty {
                        return .orderedAscending
                    }

                    let seriesResult = lhsSeriesName.localizedCaseInsensitiveCompare(rhsSeriesName)
                    if seriesResult != .orderedSame {
                        return seriesResult
                    }

                    let lhsPosition = lhs.series?.first?.position ?? Int.max
                    let rhsPosition = rhs.series?.first?.position ?? Int.max
                    if lhsPosition == rhsPosition {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    }
                    return lhsPosition < rhsPosition ? .orderedAscending : .orderedDescending
            }
        }
    }

    enum FormatFilterOption: String, CaseIterable, Identifiable {
        case all
        case readaloud
        case ebook
        case audiobook
        case ebookOnly
        case audiobookOnly
        case missingReadaloud

        var id: String { rawValue }

        var label: String {
            switch self {
                case .all:
                    "All Titles"
                case .readaloud:
                    "Readaloud"
                case .ebook:
                    "Ebook Without Audio"
                case .audiobook:
                    "Audiobook"
                case .ebookOnly:
                    "Ebook Only"
                case .audiobookOnly:
                    "Audiobook Only"
                case .missingReadaloud:
                    "Missing Readaloud"
            }
        }

        var shortLabel: String {
            switch self {
                case .all:
                    "All"
                case .readaloud:
                    "Readaloud"
                case .ebook:
                    "Ebook"
                case .audiobook:
                    "Audiobook"
                case .ebookOnly:
                    "Ebook Only"
                case .audiobookOnly:
                    "Audiobook Only"
                case .missingReadaloud:
                    "Missing Readaloud"
            }
        }

        var includesAudiobookOnlyItems: Bool {
            switch self {
                case .all, .audiobook, .audiobookOnly:
                    true
                default:
                    false
            }
        }

        func matches(_ item: BookMetadata) -> Bool {
            switch self {
                case .all:
                    true
                case .readaloud:
                    item.hasAvailableReadaloud
                case .ebook:
                    item.hasAvailableEbook
                case .audiobook:
                    item.hasAvailableAudiobook || item.hasAvailableReadaloud
                case .ebookOnly:
                    item.isEbookOnly
                case .audiobookOnly:
                    item.isAudiobookOnly
                case .missingReadaloud:
                    item.isMissingReadaloud
            }
        }
    }

    enum LocationFilterOption: String, CaseIterable, Identifiable {
        case all
        case downloaded
        case serverOnly
        case localFiles

        var id: String { rawValue }

        var label: String {
            switch self {
                case .all:
                    "All Locations"
                case .downloaded:
                    "Downloaded"
                case .serverOnly:
                    "Server Only"
                case .localFiles:
                    "Local Files"
            }
        }

        var shortLabel: String {
            switch self {
                case .all:
                    "All"
                case .downloaded:
                    "Downloaded"
                case .serverOnly:
                    "Server Only"
                case .localFiles:
                    "Local Files"
            }
        }

        var iconName: String {
            switch self {
                case .all:
                    "square.grid.2x2"
                case .downloaded:
                    "play.circle"
                case .serverOnly:
                    "arrow.down.circle"
                case .localFiles:
                    "folder"
            }
        }
    }
}

#Preview("Ebooks") {
    MediaGridView(title: "Preview Library", mediaKind: .ebook)
}

#Preview("Audiobooks") {
    MediaGridView(
        title: "Preview Audiobooks",
        mediaKind: .audiobook,
        preferredTileWidth: 200,
        minimumTileWidth: 160,
    )
}
