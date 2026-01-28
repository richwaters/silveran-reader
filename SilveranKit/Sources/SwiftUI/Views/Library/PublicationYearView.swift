import SwiftUI

struct PublicationYearView: View {
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

    #if os(macOS)
    @State private var selectedYear: String? = nil
    @State private var yearListWidth: CGFloat = 220
    @State private var sortByCount = false
    #endif

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

    private var yearGroups: [(year: String, books: [BookMetadata])] {
        mediaViewModel.booksByPublicationYear(for: mediaKind)
    }

    private var filteredYearGroups: [(year: String, books: [BookMetadata])] {
        filterYears(yearGroups)
    }

    var body: some View {
        #if os(macOS)
        macOSSplitView
        #else
        iOSYearList
        #endif
    }

    private func filterYears(_ groups: [(year: String, books: [BookMetadata])]) -> [(
        year: String, books: [BookMetadata]
    )] {
        guard !searchText.isEmpty else { return groups }

        let searchLower = searchText.lowercased()
        return groups.compactMap { group in
            let yearMatches = group.year.lowercased().contains(searchLower)

            let filteredBooks = group.books.filter { book in
                book.title.lowercased().contains(searchLower)
                    || book.authors?.contains(where: {
                        $0.name?.lowercased().contains(searchLower) ?? false
                    }) ?? false
            }

            if yearMatches {
                return (year: group.year, books: group.books)
            }

            guard !filteredBooks.isEmpty else { return nil }
            return (year: group.year, books: filteredBooks)
        }
    }
}

struct YearRowContent: View {
    let year: String
    let bookCount: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "calendar")
                #if os(iOS)
                .font(.body)
                #else
                .font(.system(size: 14))
                #endif
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(year)
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
}

#if os(iOS)
extension PublicationYearView {
    @ViewBuilder
    fileprivate var iOSYearList: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredYearGroups, id: \.year) { group in
                        NavigationLink(value: group.year) {
                            YearRowContent(
                                year: group.year,
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
            .navigationTitle("Publication Year")
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
            .navigationDestination(for: String.self) { year in
                iOSYearBooksView(year: year)
            }
            .navigationDestination(for: BookMetadata.self) { item in
                iOSBookDetailView(item: item, mediaKind: mediaKind)
            }
            .navigationDestination(for: PlayerBookData.self) { bookData in
                iOSPlayerView(for: bookData)
            }
        }
    }

    @ViewBuilder
    private func iOSYearBooksView(year: String) -> some View {
        MediaGridView(
            title: year,
            searchText: "",
            mediaKind: mediaKind,
            tagFilter: nil,
            seriesFilter: nil,
            authorFilter: nil,
            narratorFilter: nil,
            publicationYearFilter: year,
            statusFilter: nil,
            defaultSort: "title",
            preferredTileWidth: 110,
            minimumTileWidth: 90,
            columnBreakpoints: [
                MediaGridView.ColumnBreakpoint(columns: 3, minWidth: 0)
            ],
            initialNarrationFilterOption: .both,
            scrollPosition: nil
        )
        .navigationTitle(year)
        .navigationBarTitleDisplayMode(.inline)
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

#if os(macOS)
extension PublicationYearView {
    private var sortedYearGroups: [(year: String, books: [BookMetadata])] {
        let groups = filteredYearGroups
        guard sortByCount else { return groups }
        return groups.sorted { lhs, rhs in
            if lhs.books.count != rhs.books.count {
                return lhs.books.count > rhs.books.count
            }
            return lhs.year.localizedCaseInsensitiveCompare(rhs.year) == .orderedAscending
        }
    }

    @ViewBuilder
    fileprivate var macOSSplitView: some View {
        HStack(spacing: 0) {
            macOSYearListSidebar

            ResizableDivider(width: $yearListWidth, minWidth: 150, maxWidth: 400)

            macOSBooksContentArea
        }
    }

    @ViewBuilder
    private var macOSYearListSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Publication Year")
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
                    ForEach(sortedYearGroups, id: \.year) { group in
                        Button {
                            selectedYear = group.year
                        } label: {
                            YearRowContent(
                                year: group.year,
                                bookCount: group.books.count,
                                isSelected: selectedYear == group.year
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if group.year != "Unknown" {
                                let pinId = SidebarPinHelper.pinId(forYear: group.year)
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
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .frame(width: yearListWidth)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private var macOSBooksContentArea: some View {
        if let year = selectedYear {
            MediaGridView(
                title: year,
                searchText: searchText,
                mediaKind: mediaKind,
                tagFilter: nil,
                seriesFilter: nil,
                authorFilter: nil,
                narratorFilter: nil,
                publicationYearFilter: year,
                statusFilter: nil,
                defaultSort: "title",
                preferredTileWidth: 120,
                minimumTileWidth: 50,
                initialNarrationFilterOption: .both,
                scrollPosition: nil
            )
            .id(year)
        } else {
            VStack {
                Spacer()
                Text("Select a year")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}
#endif
