import SwiftUI

struct SourceView: View {
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
    @State private var navigationPath = NavigationPath()
    @AppStorage("viewLayout.source") private var layoutStyleRaw: String = CategoryLayoutStyle.list
        .rawValue
    @AppStorage("coverPref.source") private var coverPrefRaw: String = CoverPreference.preferEbook
        .rawValue
    @AppStorage("source.showBookCountBadge") private var showBookCountBadge: Bool = true

    #if os(macOS)
    @State private var selectedGroupId: String? = nil
    @State private var listWidth: CGFloat = 210
    @State private var sortByCount = false
    #endif

    private var layoutStyle: CategoryLayoutStyle {
        CategoryLayoutStyle(rawValue: layoutStyleRaw) ?? .list
    }
    private var coverPreference: CoverPreference {
        CoverPreference(rawValue: coverPrefRaw) ?? .preferEbook
    }

    #if os(iOS)
    private var hasConnectionError: Bool {
        if mediaViewModel.lastNetworkOpSucceeded == false { return true }
        if case .error = mediaViewModel.connectionStatus { return true }
        return false
    }
    private var connectionErrorIcon: String {
        if case .error = mediaViewModel.connectionStatus { return "exclamationmark.triangle" }
        return "wifi.slash"
    }
    #endif

    private var categoryGroups: [CategoryGroup] {
        let groups = mediaViewModel.booksBySource(for: mediaKind)
        let filtered = filterGroups(groups)
        return filtered.map { group in
            CategoryGroup(id: group.source, name: group.source, books: group.books, pinId: nil)
        }
    }

    private func filterGroups(_ groups: [(source: String, books: [BookMetadata])]) -> [(
        source: String, books: [BookMetadata]
    )] {
        guard !searchText.isEmpty else { return groups }
        let searchLower = searchText.lowercased()
        return groups.compactMap { group in
            let sourceMatches = group.source.lowercased().contains(searchLower)
            let filteredBooks = group.books.filter { $0.title.lowercased().contains(searchLower) }
            if sourceMatches { return group }
            guard !filteredBooks.isEmpty else { return nil }
            return (source: group.source, books: filteredBooks)
        }
    }

    private func iconName(for source: String) -> String {
        switch source {
            case "Storyteller": return "server.rack"
            case "Local Files": return "folder.fill"
            default: return "questionmark.circle.fill"
        }
    }

    private func locationFilter(for source: String) -> MediaGridView.LocationFilterOption {
        switch source {
            case "Storyteller": return .serverOnly
            case "Local Files": return .localFiles
            default: return .all
        }
    }

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    private func handleNavigation(_ group: CategoryGroup, _ book: BookMetadata?) {
        navigationPath.append(
            SourceDetailNavigation(sourceName: group.id, initialSelectedBook: book)
        )
    }
}

struct SourceDetailNavigation: Hashable {
    let sourceName: String
    let initialSelectedBook: BookMetadata?
}

#if os(iOS)
extension SourceView {
    private var iOSBody: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch layoutStyle {
                    case .list: listContent
                    case .fan, .grid: fanGridContent
                }
            }
            .navigationTitle("Sources").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if hasConnectionError, let showOfflineSheet {
                            Button {
                                showOfflineSheet.wrappedValue = true
                            } label: {
                                Image(systemName: connectionErrorIcon).foregroundStyle(.red)
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
            .navigationDestination(for: SourceDetailNavigation.self) { nav in
                sourceDetailView(for: nav.sourceName, initialSelectedItem: nav.initialSelectedBook)
                    .iOSLibraryToolbar(
                        showSettings: $showSettings,
                        showOfflineSheet: showOfflineSheet ?? .constant(false)
                    )
            }
            .navigationDestination(for: BookMetadata.self) { item in
                iOSBookDetailView(item: item, mediaKind: mediaKind).iOSLibraryToolbar(
                    showSettings: $showSettings,
                    showOfflineSheet: showOfflineSheet ?? .constant(false)
                )
            }
            .navigationDestination(for: PlayerBookData.self) { bookData in playerView(for: bookData)
            }
        }.environment(\.mediaNavigationPath, $navigationPath)
    }

    private var listContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerView.padding(.horizontal).padding(.bottom, 16)
                LazyVStack(spacing: 0) {
                    ForEach(categoryGroups) { group in
                        Button {
                            handleNavigation(group, nil)
                        } label: {
                            CategoryRowContent(
                                iconName: iconName(for: group.name),
                                name: group.name,
                                bookCount: group.books.count,
                                isSelected: false
                            ).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider().padding(.leading, 48)
                    }
                }
            }.padding(.top, 8)
        }
    }

    @ViewBuilder
    private var fanGridContent: some View {
        if layoutStyle == .fan {
            CategoryFanLayout(
                groups: categoryGroups,
                mediaKind: mediaKind,
                coverPreference: coverPreference,
                onNavigate: handleNavigation
            ) { headerView }
        } else {
            CategoryGridLayout(
                groups: categoryGroups,
                mediaKind: mediaKind,
                coverPreference: coverPreference,
                showBookCountBadge: showBookCountBadge,
                onNavigate: handleNavigation
            ) { headerView }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources").font(.system(size: 32, weight: .regular, design: .serif))
            HStack {
                CategoryViewOptionsMenu(
                    layoutStyle: Binding(
                        get: { layoutStyle },
                        set: { layoutStyleRaw = $0.rawValue }
                    ),
                    coverPreference: Binding(
                        get: { coverPreference },
                        set: { coverPrefRaw = $0.rawValue }
                    ),
                    showBookCountBadge: $showBookCountBadge
                )
                Spacer()
            }.font(.callout)
        }
    }

    @ViewBuilder private func playerView(for bookData: PlayerBookData) -> some View {
        switch bookData.category { case .audio:
            AudiobookPlayerView(bookData: bookData).navigationBarTitleDisplayMode(.inline)
            case .ebook, .synced:
                EbookPlayerView(bookData: bookData).navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif

#if os(macOS)
extension SourceView {
    private var macOSBody: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch layoutStyle {
                    case .list:
                        CategoryListSidebar(
                            sidebarTitle: "Sources",
                            groups: categoryGroups,
                            selectedGroupId: $selectedGroupId,
                            listWidth: $listWidth,
                            sortByCount: $sortByCount,
                            rowContent: { group, isSelected, isHovered in
                                CategoryRowContent(
                                    iconName: iconName(for: group.name),
                                    name: group.name,
                                    bookCount: group.books.count,
                                    isSelected: isSelected,
                                    showBookCount: showBookCountBadge,
                                    pinId: group.pinId,
                                    isHovered: isHovered
                                )
                            },
                            detailContent: { group in
                                MediaGridView(
                                    title: group.name,
                                    searchText: searchText,
                                    mediaKind: mediaKind,
                                    viewOptionsKey: "sourceView.\(mediaKind.rawValue)",
                                    defaultSort: "title",
                                    tableContext: "category",
                                    preferredTileWidth: 120,
                                    minimumTileWidth: 50,
                                    initialNarrationFilterOption: .both,
                                    initialLocationFilter: locationFilter(for: group.name),
                                    scrollPosition: nil
                                )
                            },
                            toolbarContent: {
                                CategoryViewOptionsMenu(
                                    layoutStyle: Binding(
                                        get: { layoutStyle },
                                        set: { layoutStyleRaw = $0.rawValue }
                                    ),
                                    coverPreference: Binding(
                                        get: { coverPreference },
                                        set: { coverPrefRaw = $0.rawValue }
                                    ),
                                    showBookCountBadge: $showBookCountBadge
                                )
                            }
                        )
                    case .fan, .grid: fanGridContent
                }
            }.navigationDestination(for: SourceDetailNavigation.self) { nav in
                sourceDetailView(for: nav.sourceName, initialSelectedItem: nav.initialSelectedBook)
            }
        }
    }

    @ViewBuilder
    private var fanGridContent: some View {
        if layoutStyle == .fan {
            CategoryFanLayout(
                groups: categoryGroups,
                mediaKind: mediaKind,
                coverPreference: coverPreference,
                onNavigate: handleNavigation
            ) {
                headerView
            } stickyHeader: {
                stickyHeaderView
            }
        } else {
            CategoryGridLayout(
                groups: categoryGroups,
                mediaKind: mediaKind,
                coverPreference: coverPreference,
                showBookCountBadge: showBookCountBadge,
                onNavigate: handleNavigation
            ) {
                headerView
            } stickyHeader: {
                stickyHeaderView
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources").font(.system(size: 32, weight: .regular, design: .serif))
            stickyHeaderView
        }
    }

    private var stickyHeaderView: some View {
        HStack {
            CategoryViewOptionsMenu(
                layoutStyle: Binding(get: { layoutStyle }, set: { layoutStyleRaw = $0.rawValue }),
                coverPreference: Binding(
                    get: { coverPreference },
                    set: { coverPrefRaw = $0.rawValue }
                ),
                showBookCountBadge: $showBookCountBadge
            )
            Spacer()
        }.font(.callout)
    }
}
#endif

extension SourceView {
    @ViewBuilder fileprivate func sourceDetailView(
        for sourceName: String,
        initialSelectedItem: BookMetadata? = nil
    ) -> some View {
        #if os(iOS)
        MediaGridView(
            title: sourceName,
            searchText: "",
            mediaKind: mediaKind,
            viewOptionsKey: "sourceView.\(mediaKind.rawValue)",
            defaultSort: "title",
            preferredTileWidth: 110,
            minimumTileWidth: 90,
            columnBreakpoints: [MediaGridView.ColumnBreakpoint(columns: 3, minWidth: 0)],
            initialNarrationFilterOption: .both,
            initialLocationFilter: locationFilter(for: sourceName),
            scrollPosition: nil,
            initialSelectedItem: initialSelectedItem
        ).navigationTitle(sourceName)
        #else
        MediaGridView(
            title: sourceName,
            searchText: "",
            mediaKind: mediaKind,
            viewOptionsKey: "sourceView.\(mediaKind.rawValue)",
            defaultSort: "title",
            preferredTileWidth: 120,
            minimumTileWidth: 50,
            initialNarrationFilterOption: .both,
            initialLocationFilter: locationFilter(for: sourceName),
            scrollPosition: nil,
            initialSelectedItem: initialSelectedItem
        ).navigationTitle(sourceName)
        #endif
    }
}
