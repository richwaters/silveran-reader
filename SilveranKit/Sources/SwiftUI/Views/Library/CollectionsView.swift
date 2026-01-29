import SwiftUI

struct CollectionsView: View {
    let mediaKind: MediaKind
    #if os(iOS)
    @Binding var searchText: String
    #else
    let searchText: String
    #endif
    @Binding var sidebarSections: [SidebarSectionDescription]
    @Binding var selectedSidebarItem: SidebarItemDescription?
    @Binding var showSettings: Bool
    #if os(iOS)
    var showOfflineSheet: Binding<Bool>?
    #endif
    @Environment(MediaViewModel.self) private var mediaViewModel
    @State private var settingsViewModel = SettingsViewModel()
    @State private var navigationPath = NavigationPath()
    @AppStorage("viewLayout.collections") private var layoutStyleRaw: String = LibraryLayoutStyle.fan.rawValue
    @AppStorage("coverPref.global") private var coverPrefRaw: String = CoverPreference.preferEbook.rawValue
    @AppStorage("collections.showBookCountBadge") private var showBookCountBadge: Bool = true

    private var layoutStyle: LibraryLayoutStyle {
        get { LibraryLayoutStyle(rawValue: layoutStyleRaw) ?? .fan }
        set { layoutStyleRaw = newValue.rawValue }
    }

    private var coverPreference: CoverPreference {
        get { CoverPreference(rawValue: coverPrefRaw) ?? .preferEbook }
        set { coverPrefRaw = newValue.rawValue }
    }

    private let horizontalPadding: CGFloat = 24
    private let sectionSpacing: CGFloat = 32

    #if os(iOS)
    private var hasConnectionError: Bool {
        if mediaViewModel.lastNetworkOpSucceeded == false { return true }
        if case .error = mediaViewModel.connectionStatus { return true }
        return false
    }

    private var connectionErrorIcon: String {
        if case .error = mediaViewModel.connectionStatus {
            return "exclamationmark.triangle"
        }
        return "wifi.slash"
    }
    #endif

    var body: some View {
        NavigationStack(path: $navigationPath) {
            collectionsListView
                #if os(iOS)
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if hasConnectionError,
                            let showOfflineSheet
                        {
                            Button {
                                showOfflineSheet.wrappedValue = true
                            } label: {
                                Image(systemName: connectionErrorIcon)
                                .foregroundStyle(.red)
                            }
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search"
            )
                #endif
                .navigationDestination(for: CollectionDetailNavigation.self) { nav in
                    collectionDetailView(for: nav.collectionIdentifier, initialSelectedItem: nav.initialSelectedBook)
                        #if os(iOS)
                    .iOSLibraryToolbar(
                        showSettings: $showSettings,
                        showOfflineSheet: showOfflineSheet ?? .constant(false)
                    )
                        #endif
                }
                .navigationDestination(for: SeriesDetailNavigation.self) { nav in
                    seriesDetailView(for: nav.seriesName, initialSelectedItem: nav.initialSelectedBook)
                        #if os(iOS)
                    .iOSLibraryToolbar(
                        showSettings: $showSettings,
                        showOfflineSheet: showOfflineSheet ?? .constant(false)
                    )
                        #endif
                }
                #if os(iOS)
            .navigationDestination(for: BookMetadata.self) { item in
                iOSBookDetailView(item: item, mediaKind: mediaKind)
                .iOSLibraryToolbar(
                    showSettings: $showSettings,
                    showOfflineSheet: showOfflineSheet ?? .constant(false)
                )
            }
            .navigationDestination(for: PlayerBookData.self) { bookData in
                playerView(for: bookData)
            }
            #endif
        }
        #if os(iOS)
        .environment(\.mediaNavigationPath, $navigationPath)
        #endif
    }

    private var collectionsListView: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        headerView

                        collectionsContent(contentWidth: contentWidth)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .modifier(SoftScrollEdgeModifier())
                .frame(width: contentWidth)
                #if os(iOS)
                .overlay(alignment: .trailing) {
                    let groups = mediaViewModel.booksByCollection(for: mediaKind)
                    AlphabetScrubber(
                        items: groups,
                        textForItem: { $0.collection?.name ?? "Unknown Collection" },
                        idForItem: { $0.collection?.uuid ?? $0.collection?.name ?? "unknown" },
                        proxy: proxy
                    )
                    .padding(.top, 120)
                    .padding(.bottom, 40)
                }
                #endif
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Books by Collection")
                .font(.system(size: 32, weight: .regular, design: .serif))

            HStack {
                viewOptionsMenu
                Spacer()
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var viewOptionsMenu: some View {
        Menu {
            Section("Layout") {
                ForEach([LibraryLayoutStyle.fan, LibraryLayoutStyle.grid], id: \.self) { style in
                    Button {
                        layoutStyleRaw = style.rawValue
                    } label: {
                        HStack {
                            Text(style.label)
                            Spacer()
                            if layoutStyle == style {
                                Image(systemName: "checkmark")
                                    .imageScale(.small)
                            }
                        }
                    }
                }
            }

            Divider()

            Section("Cover Style") {
                ForEach(CoverPreference.allCases) { preference in
                    Button {
                        coverPrefRaw = preference.rawValue
                    } label: {
                        HStack {
                            Text(preference.label)
                            Spacer()
                            if coverPreference == preference {
                                Image(systemName: "checkmark")
                                    .imageScale(.small)
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                showBookCountBadge.toggle()
            } label: {
                HStack {
                    Text("Show Book Count")
                    Spacer()
                    if showBookCountBadge {
                        Image(systemName: "checkmark")
                            .imageScale(.small)
                    }
                }
            }
        } label: {
            Label("View Options", systemImage: "ellipsis.circle")
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    @ViewBuilder
    private func collectionsContent(contentWidth: CGFloat) -> some View {
        let collectionGroups = mediaViewModel.booksByCollection(for: mediaKind)
        let filteredGroups = filterCollections(collectionGroups)

        if filteredGroups.isEmpty {
            emptyStateView
        } else {
            switch layoutStyle {
            case .fan:
                ForEach(Array(filteredGroups.enumerated()), id: \.offset) { _, group in
                    collectionSection(
                        collection: group.collection,
                        books: group.books,
                        contentWidth: contentWidth
                    )
                }
            case .grid, .compactGrid, .table:
                collectionsGridLayout(groups: filteredGroups, contentWidth: contentWidth)
            }
        }
    }

    @ViewBuilder
    private func collectionsGridLayout(groups: [(collection: BookCollectionSummary?, books: [BookMetadata])], contentWidth: CGFloat) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 125, maximum: 140), spacing: 16)
        ]

        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                let collectionId = group.collection?.uuid ?? group.collection?.name ?? "unknown"
                GroupedBooksCardView(
                    title: group.collection?.name ?? "Unknown Collection",
                    books: group.books,
                    mediaKind: mediaKind,
                    coverPreference: coverPreference,
                    showBookCountBadge: showBookCountBadge,
                    onTap: {
                        navigateToCollection(collectionId)
                    }
                )
                .id(collectionId)
                .contextMenu {
                    if let name = group.collection?.name {
                        let pinId = SidebarPinHelper.pinId(forCollection: name)
                        Button {
                            SidebarPinHelper.togglePin(pinId)
                        } label: {
                            Label(
                                SidebarPinHelper.isPinned(pinId) ? "Unpin from Sidebar" : "Pin to Sidebar",
                                systemImage: SidebarPinHelper.isPinned(pinId) ? "pin.slash" : "pin"
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text("No collections found")
                .font(.title)
                .foregroundStyle(.secondary)
            #if os(iOS)
            Text(
                "Books in collections will appear here. Create collections on Storyteller to organize your library."
            )
            .font(.body)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            #else
            Text(
                "Books in collections will appear here. Create collections on Storyteller to organize your library."
            )
            .font(.body)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            #endif
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 60)
    }

    private func filterCollections(
        _ groups: [(collection: BookCollectionSummary?, books: [BookMetadata])]
    ) -> [(
        collection: BookCollectionSummary?, books: [BookMetadata]
    )] {
        guard !searchText.isEmpty else { return groups }

        let searchLower = searchText.lowercased()
        return groups.compactMap { group in
            let collectionNameMatches =
                group.collection?.name.lowercased().contains(searchLower) ?? false

            let filteredBooks = group.books.filter { book in
                book.title.lowercased().contains(searchLower)
                    || book.authors?.contains(where: {
                        $0.name?.lowercased().contains(searchLower) ?? false
                    }) ?? false
            }

            if collectionNameMatches {
                return (collection: group.collection, books: group.books)
            }

            guard !filteredBooks.isEmpty else { return nil }
            return (collection: group.collection, books: filteredBooks)
        }
    }

    @ViewBuilder
    private func collectionSection(
        collection: BookCollectionSummary?,
        books: [BookMetadata],
        contentWidth: CGFloat
    )
        -> some View
    {
        let displayBooks = books
        let stackWidth = max(contentWidth - (horizontalPadding * 2), 100)

        VStack(alignment: .center, spacing: 12) {
            SeriesStackView(
                books: displayBooks,
                mediaKind: mediaKind,
                availableWidth: stackWidth,
                showAudioIndicator: settingsViewModel.showAudioIndicator,
                coverPreference: coverPreference,
                onSelect: { book in
                    if let collectionId = collection?.uuid ?? collection?.name {
                        navigateToCollection(collectionId, initialSelectedBook: book)
                    }
                }
            )
            .frame(maxWidth: stackWidth, alignment: .center)

            VStack(alignment: .center, spacing: 6) {
                Button {
                    if let collectionId = collection?.uuid ?? collection?.name {
                        navigateToCollection(collectionId)
                    }
                } label: {
                    Text(collection?.name ?? "Unknown Collection")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(collection == nil)
                .frame(maxWidth: .infinity, alignment: .center)

                Text("\(books.count) book\(books.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            if let name = collection?.name {
                let pinId = SidebarPinHelper.pinId(forCollection: name)
                Button {
                    SidebarPinHelper.togglePin(pinId)
                } label: {
                    Label(
                        SidebarPinHelper.isPinned(pinId) ? "Unpin from Sidebar" : "Pin to Sidebar",
                        systemImage: SidebarPinHelper.isPinned(pinId) ? "pin.slash" : "pin"
                    )
                }
            }
        }
    }

    private func navigateToCollection(_ collectionIdentifier: String, initialSelectedBook: BookMetadata? = nil) {
        navigationPath.append(CollectionDetailNavigation(collectionIdentifier: collectionIdentifier, initialSelectedBook: initialSelectedBook))
    }

    @ViewBuilder
    private func collectionDetailView(for collectionIdentifier: String, initialSelectedItem: BookMetadata? = nil) -> some View {
        let collectionName = findCollectionName(for: collectionIdentifier)
        #if os(iOS)
        MediaGridView(
            title: collectionName,
            searchText: "",
            mediaKind: mediaKind,
            tagFilter: nil,
            seriesFilter: nil,
            collectionFilter: collectionIdentifier,
            statusFilter: nil,
            defaultSort: "titleAZ",
            preferredTileWidth: 110,
            minimumTileWidth: 90,
            columnBreakpoints: [
                MediaGridView.ColumnBreakpoint(columns: 3, minWidth: 0)
            ],
            initialNarrationFilterOption: .both,
            scrollPosition: nil,
            initialSelectedItem: initialSelectedItem
        )
        .navigationTitle(collectionName)
        #else
        MediaGridView(
            title: collectionName,
            searchText: "",
            mediaKind: mediaKind,
            tagFilter: nil,
            seriesFilter: nil,
            collectionFilter: collectionIdentifier,
            statusFilter: nil,
            defaultSort: "titleAZ",
            preferredTileWidth: 120,
            minimumTileWidth: 50,
            initialNarrationFilterOption: .both,
            scrollPosition: nil,
            initialSelectedItem: initialSelectedItem
        )
        .navigationTitle(collectionName)
        #endif
    }

    @ViewBuilder
    private func seriesDetailView(for seriesName: String, initialSelectedItem: BookMetadata? = nil) -> some View {
        let sortKey = "seriesPosition"
        #if os(iOS)
        MediaGridView(
            title: seriesName,
            searchText: "",
            mediaKind: mediaKind,
            tagFilter: nil,
            seriesFilter: seriesName,
            statusFilter: nil,
            defaultSort: sortKey,
            preferredTileWidth: 110,
            minimumTileWidth: 90,
            columnBreakpoints: [
                MediaGridView.ColumnBreakpoint(columns: 3, minWidth: 0)
            ],
            initialNarrationFilterOption: .both,
            scrollPosition: nil,
            initialSelectedItem: initialSelectedItem
        )
        .navigationTitle(seriesName)
        #else
        MediaGridView(
            title: seriesName,
            searchText: "",
            mediaKind: mediaKind,
            tagFilter: nil,
            seriesFilter: seriesName,
            statusFilter: nil,
            defaultSort: sortKey,
            preferredTileWidth: 120,
            minimumTileWidth: 50,
            onSeriesSelected: { newSeriesName in
                navigationPath.append(SeriesDetailNavigation(seriesName: newSeriesName, initialSelectedBook: nil))
            },
            initialNarrationFilterOption: .both,
            scrollPosition: nil,
            initialSelectedItem: initialSelectedItem
        )
        .navigationTitle(seriesName)
        #endif
    }

    private func findCollectionName(for identifier: String) -> String {
        let groups = mediaViewModel.booksByCollection(for: mediaKind)
        for group in groups {
            if let collection = group.collection {
                if collection.uuid == identifier || collection.name == identifier {
                    return collection.name
                }
            }
        }
        return identifier
    }

    @ViewBuilder
    private func playerView(for bookData: PlayerBookData) -> some View {
        switch bookData.category {
            case .audio:
                AudiobookPlayerView(bookData: bookData)
                    #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                    #endif
            case .ebook, .synced:
                EbookPlayerView(bookData: bookData)
                    #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                    #endif
        }
    }

}
