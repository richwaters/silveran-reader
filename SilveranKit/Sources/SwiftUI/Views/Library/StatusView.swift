import SwiftUI

struct StatusView: View {
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
    @AppStorage("viewLayout.status") private var layoutStyleRaw: String = CategoryLayoutStyle.list.rawValue
    @AppStorage("coverPref.global") private var coverPrefRaw: String = CoverPreference.preferEbook.rawValue
    @AppStorage("status.showBookCountBadge") private var showBookCountBadge: Bool = true

    #if os(macOS)
    @State private var selectedStatus: String? = nil
    @State private var statusListWidth: CGFloat = 220
    @State private var sortByCount = false
    #endif

    private var layoutStyle: CategoryLayoutStyle {
        get { CategoryLayoutStyle(rawValue: layoutStyleRaw) ?? .list }
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

    private var statusGroups: [(status: String, books: [BookMetadata])] {
        mediaViewModel.booksByStatus(for: mediaKind)
    }

    private var filteredStatusGroups: [(status: String, books: [BookMetadata])] {
        filterStatuses(statusGroups)
    }

    var body: some View {
        #if os(macOS)
        switch layoutStyle {
        case .list:
            macOSSplitView
        case .fan, .grid:
            NavigationStack(path: $navigationPath) {
                fanGridListView
                    .navigationDestination(for: StatusDetailNavigation.self) { nav in
                        statusDetailView(for: nav.statusName, initialSelectedItem: nav.initialSelectedBook)
                    }
            }
        }
        #else
        iOSStatusView
        #endif
    }

    private func filterStatuses(_ groups: [(status: String, books: [BookMetadata])]) -> [(
        status: String, books: [BookMetadata]
    )] {
        guard !searchText.isEmpty else { return groups }

        let searchLower = searchText.lowercased()
        return groups.compactMap { group in
            let statusMatches = group.status.lowercased().contains(searchLower)

            let filteredBooks = group.books.filter { book in
                book.title.lowercased().contains(searchLower)
                    || book.status?.name.lowercased().contains(searchLower) ?? false
            }

            if statusMatches {
                return (status: group.status, books: group.books)
            }

            guard !filteredBooks.isEmpty else { return nil }
            return (status: group.status, books: filteredBooks)
        }
    }
}

struct StatusDetailNavigation: Hashable {
    let statusName: String
    let initialSelectedBook: BookMetadata?
}

struct StatusRowContent: View {
    let statusName: String
    let bookCount: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: iconName(for: statusName))
                #if os(iOS)
                .font(.body)
                #else
                .font(.system(size: 14))
                #endif
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(statusName)
                #if os(iOS)
                .font(.body)
                #else
                .font(.system(size: 14))
                #endif
                .lineLimit(1)

            Spacer()

            Text("\(bookCount)")
                #if os(iOS)
                .font(.subheadline)
                #else
                .font(.system(size: 12))
                #endif
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                )
        }
        .padding(.horizontal, 16)
        #if os(iOS)
        .padding(.vertical, 12)
        #else
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        #endif
    }

    private func iconName(for status: String) -> String {
        switch status.lowercased() {
        case "reading": return "arrow.right.circle.fill"
        case "to read": return "bookmark.fill"
        case "read": return "checkmark.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }
}

// MARK: - iOS Implementation

#if os(iOS)
extension StatusView {
    @ViewBuilder
    fileprivate var iOSStatusView: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch layoutStyle {
                case .list:
                    iOSListView
                case .fan, .grid:
                    fanGridListView
                }
            }
            .navigationTitle("By Status")
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
            .navigationDestination(for: StatusDetailNavigation.self) { nav in
                statusDetailView(for: nav.statusName, initialSelectedItem: nav.initialSelectedBook)
                    .iOSLibraryToolbar(
                        showSettings: $showSettings,
                        showOfflineSheet: showOfflineSheet ?? .constant(false)
                    )
            }
            .navigationDestination(for: BookMetadata.self) { item in
                iOSBookDetailView(item: item, mediaKind: mediaKind)
                    .iOSLibraryToolbar(
                        showSettings: $showSettings,
                        showOfflineSheet: showOfflineSheet ?? .constant(false)
                    )
            }
            .navigationDestination(for: PlayerBookData.self) { bookData in
                iOSPlayerView(for: bookData)
            }
        }
        .environment(\.mediaNavigationPath, $navigationPath)
    }

    @ViewBuilder
    private var iOSListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredStatusGroups, id: \.status) { group in
                    NavigationLink(value: StatusDetailNavigation(statusName: group.status, initialSelectedBook: nil)) {
                        StatusRowContent(
                            statusName: group.status,
                            bookCount: group.books.count,
                            isSelected: false
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 48)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func iOSPlayerView(for bookData: PlayerBookData) -> some View {
        switch bookData.category {
            case .audio:
                AudiobookPlayerView(bookData: bookData)
                    .navigationBarTitleDisplayMode(.inline)
            case .ebook, .synced:
                EbookPlayerView(bookData: bookData)
                    .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif

// MARK: - macOS Implementation

#if os(macOS)
extension StatusView {
    @ViewBuilder
    fileprivate var macOSSplitView: some View {
        HStack(spacing: 0) {
            macOSStatusListSidebar

            ResizableDivider(width: $statusListWidth, minWidth: 150, maxWidth: 400)

            macOSBooksContentArea
        }
    }

    private var sortedStatusGroups: [(status: String, books: [BookMetadata])] {
        let groups = filteredStatusGroups
        guard sortByCount else { return groups }
        return groups.sorted { lhs, rhs in
            if lhs.books.count != rhs.books.count {
                return lhs.books.count > rhs.books.count
            }
            return lhs.status.localizedCaseInsensitiveCompare(rhs.status) == .orderedAscending
        }
    }

    @ViewBuilder
    private var macOSStatusListSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Status")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                SidebarSortButton(sortByCount: $sortByCount)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sortedStatusGroups, id: \.status) { group in
                        Button {
                            selectedStatus = group.status
                        } label: {
                            StatusRowContent(
                                statusName: group.status,
                                bookCount: group.books.count,
                                isSelected: selectedStatus == group.status
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            let pinId = SidebarPinHelper.pinId(forStatus: group.status)
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
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .frame(width: statusListWidth)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private var macOSBooksContentArea: some View {
        if let statusName = selectedStatus {
            MediaGridView(
                title: statusName,
                searchText: searchText,
                mediaKind: mediaKind,
                tagFilter: nil,
                seriesFilter: nil,
                authorFilter: nil,
                statusFilter: statusName,
                defaultSort: "recentlyRead",
                preferredTileWidth: 120,
                minimumTileWidth: 50,
                initialNarrationFilterOption: .both,
                scrollPosition: nil
            )
            .id(statusName)
        } else {
            VStack {
                Spacer()
                Text("Select a status")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}
#endif

// MARK: - Fan/Grid Layout (Shared)

extension StatusView {
    @ViewBuilder
    fileprivate var fanGridListView: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        headerView

                        statusContent(contentWidth: contentWidth)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .frame(width: contentWidth)
                .contentMargins(.trailing, 10, for: .scrollIndicators)
                .modifier(SoftScrollEdgeModifier())
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Books by Status")
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
                ForEach(CategoryLayoutStyle.allCases) { style in
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
    private func statusContent(contentWidth: CGFloat) -> some View {
        let groups = filteredStatusGroups

        if groups.isEmpty {
            emptyStateView
        } else {
            switch layoutStyle {
            case .list:
                EmptyView()
            case .fan:
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    statusSection(
                        status: group.status,
                        books: group.books,
                        contentWidth: contentWidth
                    )
                }
            case .grid:
                statusGridLayout(groups: groups, contentWidth: contentWidth)
            }
        }
    }

    @ViewBuilder
    private func statusGridLayout(groups: [(status: String, books: [BookMetadata])], contentWidth: CGFloat) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 125, maximum: 140), spacing: 16)
        ]

        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                GroupedBooksCardView(
                    title: group.status,
                    books: group.books,
                    mediaKind: mediaKind,
                    coverPreference: coverPreference,
                    showBookCountBadge: showBookCountBadge,
                    onTap: {
                        navigateToStatus(group.status)
                    }
                )
                .id(group.status)
                .contextMenu {
                    let pinId = SidebarPinHelper.pinId(forStatus: group.status)
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

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text("No books found")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Books will appear here once you have some in your library.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func statusSection(
        status: String,
        books: [BookMetadata],
        contentWidth: CGFloat
    ) -> some View {
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
                    navigateToStatus(status, initialSelectedBook: book)
                }
            )
            .frame(maxWidth: stackWidth, alignment: .center)

            VStack(alignment: .center, spacing: 6) {
                Button {
                    navigateToStatus(status)
                } label: {
                    Text(status)
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
            let pinId = SidebarPinHelper.pinId(forStatus: status)
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

    private func navigateToStatus(_ statusName: String, initialSelectedBook: BookMetadata? = nil) {
        navigationPath.append(StatusDetailNavigation(statusName: statusName, initialSelectedBook: initialSelectedBook))
    }

    @ViewBuilder
    fileprivate func statusDetailView(for statusName: String, initialSelectedItem: BookMetadata? = nil) -> some View {
        #if os(iOS)
        MediaGridView(
            title: statusName,
            searchText: "",
            mediaKind: mediaKind,
            tagFilter: nil,
            seriesFilter: nil,
            authorFilter: nil,
            statusFilter: statusName,
            defaultSort: "recentlyRead",
            preferredTileWidth: 110,
            minimumTileWidth: 90,
            columnBreakpoints: [
                MediaGridView.ColumnBreakpoint(columns: 3, minWidth: 0)
            ],
            initialNarrationFilterOption: .both,
            scrollPosition: nil,
            initialSelectedItem: initialSelectedItem
        )
        .navigationTitle(statusName)
        #else
        MediaGridView(
            title: statusName,
            searchText: "",
            mediaKind: mediaKind,
            tagFilter: nil,
            seriesFilter: nil,
            authorFilter: nil,
            statusFilter: statusName,
            defaultSort: "recentlyRead",
            preferredTileWidth: 120,
            minimumTileWidth: 50,
            initialNarrationFilterOption: .both,
            scrollPosition: nil,
            initialSelectedItem: initialSelectedItem
        )
        .navigationTitle(statusName)
        #endif
    }
}
