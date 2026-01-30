import SwiftUI

struct DynamicShelfDetailNavigation: Hashable {
    let shelfId: UUID
    let initialSelectedBook: BookMetadata?

    func hash(into hasher: inout Hasher) {
        hasher.combine(shelfId)
        hasher.combine(initialSelectedBook?.id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.shelfId == rhs.shelfId && lhs.initialSelectedBook?.id == rhs.initialSelectedBook?.id
    }
}

struct DynamicShelvesView: View {
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
    @State private var showCreator = false
    @State private var editingShelf: DynamicShelf?
    @AppStorage("viewLayout.dynamicShelves") private var layoutStyleRaw: String = CategoryLayoutStyle.fan.rawValue
    @AppStorage("coverPref.global") private var coverPrefRaw: String = CoverPreference.preferEbook.rawValue
    @AppStorage("dynamicShelves.showBookCountBadge") private var showBookCountBadge: Bool = true

    #if os(macOS)
    @State private var selectedGroupId: String? = nil
    @State private var listWidth: CGFloat = 220
    @State private var sortByCount = false
    #endif

    private var layoutStyle: CategoryLayoutStyle {
        get { CategoryLayoutStyle(rawValue: layoutStyleRaw) ?? .fan }
        set { layoutStyleRaw = newValue.rawValue }
    }

    private var coverPreference: CoverPreference {
        get { CoverPreference(rawValue: coverPrefRaw) ?? .preferEbook }
        set { coverPrefRaw = newValue.rawValue }
    }

    private let horizontalPadding: CGFloat = 24
    private let sectionSpacing: CGFloat = 32

    private var categoryGroups: [CategoryGroup] {
        let shelves = filteredShelves()
        return shelves.map { shelf in
            let books = mediaViewModel.booksForShelf(shelf)
            return CategoryGroup(
                id: shelf.id.uuidString,
                name: shelf.name,
                books: books,
                pinId: SidebarPinHelper.pinId(forDynamicShelf: shelf.id)
            )
        }
    }

    private func handleNavigation(_ group: CategoryGroup, _ book: BookMetadata?) {
        guard let shelfId = UUID(uuidString: group.id) else { return }
        navigationPath.append(DynamicShelfDetailNavigation(shelfId: shelfId, initialSelectedBook: book))
    }

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
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }
}

#if os(iOS)
extension DynamicShelvesView {
    private var iOSBody: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch layoutStyle {
                case .list: listContent
                case .fan, .grid: fanGridContent
                }
            }
            .navigationTitle("Dynamic Shelves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if hasConnectionError, let showOfflineSheet {
                            Button { showOfflineSheet.wrappedValue = true } label: {
                                Image(systemName: connectionErrorIcon).foregroundStyle(.red)
                            }
                        }
                        Button { showSettings = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .navigationDestination(for: DynamicShelfDetailNavigation.self) { nav in
                shelfDetailView(for: nav.shelfId, initialSelectedItem: nav.initialSelectedBook)
                    .iOSLibraryToolbar(showSettings: $showSettings, showOfflineSheet: showOfflineSheet ?? .constant(false))
            }
            .navigationDestination(for: BookMetadata.self) { item in
                iOSBookDetailView(item: item, mediaKind: .ebook)
                    .iOSLibraryToolbar(showSettings: $showSettings, showOfflineSheet: showOfflineSheet ?? .constant(false))
            }
            .navigationDestination(for: PlayerBookData.self) { bookData in
                playerView(for: bookData)
            }
        }
        .environment(\.mediaNavigationPath, $navigationPath)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(categoryGroups) { group in
                    Button { handleNavigation(group, nil) } label: {
                        CategoryRowContent(iconName: "books.vertical.fill", name: group.name, bookCount: group.books.count, isSelected: false)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 48)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var fanGridContent: some View {
        if layoutStyle == .fan {
            CategoryFanLayout(groups: categoryGroups, mediaKind: .ebook, coverPreference: coverPreference, onNavigate: handleNavigation) { headerView }
        } else {
            CategoryGridLayout(groups: categoryGroups, mediaKind: .ebook, coverPreference: coverPreference, showBookCountBadge: showBookCountBadge, onNavigate: handleNavigation) { headerView }
        }
    }

    @ViewBuilder
    private func playerView(for bookData: PlayerBookData) -> some View {
        switch bookData.category {
        case .audio: AudiobookPlayerView(bookData: bookData).navigationBarTitleDisplayMode(.inline)
        case .ebook, .synced: EbookPlayerView(bookData: bookData).navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif

#if os(macOS)
extension DynamicShelvesView {
    private var macOSBody: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch layoutStyle {
                case .list:
                    CategoryListSidebar(
                        headerTitle: "Dynamic Shelves",
                        sidebarTitle: "Shelves",
                        groups: categoryGroups,
                        selectedGroupId: $selectedGroupId,
                        listWidth: $listWidth,
                        sortByCount: $sortByCount,
                        rowContent: { group, isSelected in
                            CategoryRowContent(iconName: "books.vertical.fill", name: group.name, bookCount: group.books.count, isSelected: isSelected)
                        },
                        detailContent: { group in
                            if let shelfId = UUID(uuidString: group.id), let shelf = mediaViewModel.dynamicShelves.first(where: { $0.id == shelfId }) {
                                let books = mediaViewModel.booksForShelf(shelf)
                                DynamicShelfDetailView(shelf: shelf, books: books, searchText: searchText, initialSelectedItem: nil)
                            } else {
                                Text("Shelf not found").foregroundStyle(.secondary)
                            }
                        },
                        toolbarContent: { CategoryViewOptionsMenu(layoutStyle: Binding(get: { layoutStyle }, set: { layoutStyleRaw = $0.rawValue }), coverPreference: Binding(get: { coverPreference }, set: { coverPrefRaw = $0.rawValue }), showBookCountBadge: $showBookCountBadge) }
                    )
                case .fan, .grid:
                    fanGridContent
                }
            }
            .navigationDestination(for: DynamicShelfDetailNavigation.self) { nav in
                shelfDetailView(for: nav.shelfId, initialSelectedItem: nav.initialSelectedBook)
            }
        }
        .sheet(isPresented: $showCreator) {
            DynamicShelfCreatorView { shelf in
                Task { await mediaViewModel.saveDynamicShelf(shelf) }
            }
        }
        .sheet(item: $editingShelf) { shelf in
            DynamicShelfCreatorView(existingShelf: shelf) { updatedShelf in
                Task { await mediaViewModel.saveDynamicShelf(updatedShelf) }
            }
        }
    }

    @ViewBuilder
    private var fanGridContent: some View {
        if layoutStyle == .fan {
            CategoryFanLayout(groups: categoryGroups, mediaKind: .ebook, coverPreference: coverPreference, onNavigate: handleNavigation) { headerView }
        } else {
            CategoryGridLayout(groups: categoryGroups, mediaKind: .ebook, coverPreference: coverPreference, showBookCountBadge: showBookCountBadge, onNavigate: handleNavigation) { headerView }
        }
    }
}
#endif

extension DynamicShelvesView {
    fileprivate var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dynamic Shelves")
                .font(.system(size: 32, weight: .regular, design: .serif))

            HStack(spacing: 12) {
                CategoryViewOptionsMenu(
                    layoutStyle: Binding(get: { layoutStyle }, set: { layoutStyleRaw = $0.rawValue }),
                    coverPreference: Binding(get: { coverPreference }, set: { coverPrefRaw = $0.rawValue }),
                    showBookCountBadge: $showBookCountBadge
                )

                Spacer()

                Button {
                    showCreator = true
                } label: {
                    Label("Create New Shelf", systemImage: "plus.circle")
                }
                #if os(macOS)
                .buttonStyle(.borderless)
                #endif
            }
            .font(.callout)
        }
    }

    fileprivate func filteredShelves() -> [DynamicShelf] {
        guard !searchText.isEmpty else { return mediaViewModel.dynamicShelves }
        let searchLower = searchText.lowercased()
        return mediaViewModel.dynamicShelves.filter { shelf in
            shelf.name.lowercased().contains(searchLower)
        }
    }

    @ViewBuilder
    fileprivate func shelfDetailView(for shelfId: UUID, initialSelectedItem: BookMetadata? = nil) -> some View {
        if let shelf = mediaViewModel.dynamicShelves.first(where: { $0.id == shelfId }) {
            let books = mediaViewModel.booksForShelf(shelf)
            DynamicShelfDetailView(shelf: shelf, books: books, searchText: "", initialSelectedItem: initialSelectedItem)
                .navigationTitle(shelf.name)
        } else {
            Text("Shelf not found").foregroundStyle(.secondary)
        }
    }
}

struct DynamicShelfDetailView: View {
    let shelf: DynamicShelf
    let books: [BookMetadata]
    let searchText: String
    let initialSelectedItem: BookMetadata?
    @Environment(MediaViewModel.self) private var mediaViewModel

    init(shelf: DynamicShelf, books: [BookMetadata], searchText: String, initialSelectedItem: BookMetadata? = nil) {
        self.shelf = shelf
        self.books = books
        self.searchText = searchText
        self.initialSelectedItem = initialSelectedItem
    }

    var body: some View {
        MediaGridView(
            title: shelf.name,
            searchText: searchText,
            mediaKind: .ebook,
            preferredTileWidth: 120,
            minimumTileWidth: 50,
            initialNarrationFilterOption: .both,
            scrollPosition: nil,
            initialSelectedItem: initialSelectedItem,
            filteredItems: books
        )
    }
}
