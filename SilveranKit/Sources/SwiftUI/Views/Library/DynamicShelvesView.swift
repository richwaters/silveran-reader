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
    @AppStorage("viewLayout.dynamicShelves") private var layoutStyleRaw: String = LibraryLayoutStyle.fan.rawValue
    @AppStorage("coverPref.global") private var coverPrefRaw: String = CoverPreference.preferEbook.rawValue
    @AppStorage("dynamicShelves.showBookCountBadge") private var showBookCountBadge: Bool = true

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
            shelvesListView
                #if os(iOS)
            .navigationTitle("Dynamic Shelves")
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
                .navigationDestination(for: DynamicShelfDetailNavigation.self) { nav in
                    shelfDetailView(for: nav.shelfId, initialSelectedItem: nav.initialSelectedBook)
                        #if os(iOS)
                    .iOSLibraryToolbar(
                        showSettings: $showSettings,
                        showOfflineSheet: showOfflineSheet ?? .constant(false)
                    )
                        #endif
                }
                #if os(iOS)
            .navigationDestination(for: BookMetadata.self) { item in
                iOSBookDetailView(item: item, mediaKind: .ebook)
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
        #if os(macOS)
        .sheet(isPresented: $showCreator) {
            DynamicShelfCreatorView { shelf in
                Task {
                    await mediaViewModel.saveDynamicShelf(shelf)
                }
            }
        }
        .sheet(item: $editingShelf) { shelf in
            DynamicShelfCreatorView(existingShelf: shelf) { updatedShelf in
                Task {
                    await mediaViewModel.saveDynamicShelf(updatedShelf)
                }
            }
        }
        #endif
    }

    private var shelvesListView: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width

            ScrollView {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    headerView

                    shelvesContent(contentWidth: contentWidth)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .modifier(SoftScrollEdgeModifier())
            .frame(width: contentWidth)
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dynamic Shelves")
                .font(.system(size: 32, weight: .regular, design: .serif))

            HStack(spacing: 12) {
                viewOptionsMenu

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
    private func shelvesContent(contentWidth: CGFloat) -> some View {
        let shelves = filteredShelves()

        if mediaViewModel.dynamicShelves.isEmpty {
            emptyStateView
        } else if shelves.isEmpty {
            VStack(spacing: 12) {
                Text("No matching shelves")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 60)
        } else {
            switch layoutStyle {
            case .fan:
                ForEach(shelves) { shelf in
                    shelfFanSection(shelf: shelf, contentWidth: contentWidth)
                }
            case .grid, .compactGrid, .table:
                shelvesGridLayout(shelves: shelves, contentWidth: contentWidth)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("No dynamic shelves")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Create dynamic shelves to filter your library by custom criteria like tags, ratings, reading progress, and more.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                showCreator = true
            } label: {
                Text("Create New Shelf")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func shelfFanSection(shelf: DynamicShelf, contentWidth: CGFloat) -> some View {
        let books = mediaViewModel.booksForShelf(shelf)
        let stackWidth = max(contentWidth - (horizontalPadding * 2), 100)

        VStack(alignment: .center, spacing: 12) {
            if !books.isEmpty {
                SeriesStackView(
                    books: books,
                    mediaKind: .ebook,
                    availableWidth: stackWidth,
                    showAudioIndicator: settingsViewModel.showAudioIndicator,
                    coverPreference: coverPreference,
                    onSelect: { book in
                        navigationPath.append(DynamicShelfDetailNavigation(shelfId: shelf.id, initialSelectedBook: book))
                    }
                )
                .frame(maxWidth: stackWidth, alignment: .center)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 120)
                    .overlay {
                        Text("No matching books")
                            .foregroundStyle(.tertiary)
                    }
            }

            VStack(alignment: .center, spacing: 6) {
                Button {
                    navigationPath.append(DynamicShelfDetailNavigation(shelfId: shelf.id, initialSelectedBook: nil))
                } label: {
                    Text(shelf.name)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
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
            shelfContextMenu(shelf)
        }
    }

    @ViewBuilder
    private func shelvesGridLayout(shelves: [DynamicShelf], contentWidth: CGFloat) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 125, maximum: 140), spacing: 16)
        ]

        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(shelves) { shelf in
                let books = mediaViewModel.booksForShelf(shelf)
                GroupedBooksCardView(
                    title: shelf.name,
                    books: books,
                    mediaKind: .ebook,
                    coverPreference: coverPreference,
                    showBookCountBadge: showBookCountBadge,
                    onTap: {
                        navigationPath.append(DynamicShelfDetailNavigation(shelfId: shelf.id, initialSelectedBook: nil))
                    }
                )
                .contextMenu {
                    shelfContextMenu(shelf)
                }
            }
        }
    }

    @ViewBuilder
    private func shelfContextMenu(_ shelf: DynamicShelf) -> some View {
        let pinId = SidebarPinHelper.pinId(forDynamicShelf: shelf.id)
        Button {
            SidebarPinHelper.togglePin(pinId)
        } label: {
            Label(
                SidebarPinHelper.isPinned(pinId) ? "Unpin from Sidebar" : "Pin to Sidebar",
                systemImage: SidebarPinHelper.isPinned(pinId) ? "pin.slash" : "pin"
            )
        }

        Button {
            editingShelf = shelf
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button(role: .destructive) {
            Task {
                await mediaViewModel.deleteDynamicShelf(id: shelf.id)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func filteredShelves() -> [DynamicShelf] {
        guard !searchText.isEmpty else { return mediaViewModel.dynamicShelves }

        let searchLower = searchText.lowercased()
        return mediaViewModel.dynamicShelves.filter { shelf in
            shelf.name.lowercased().contains(searchLower)
        }
    }

    @ViewBuilder
    private func shelfDetailView(for shelfId: UUID, initialSelectedItem: BookMetadata? = nil) -> some View {
        if let shelf = mediaViewModel.dynamicShelves.first(where: { $0.id == shelfId }) {
            let books = mediaViewModel.booksForShelf(shelf)
            DynamicShelfDetailView(
                shelf: shelf,
                books: books,
                searchText: "",
                initialSelectedItem: initialSelectedItem
            )
            .navigationTitle(shelf.name)
        } else {
            Text("Shelf not found")
                .foregroundStyle(.secondary)
        }
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
