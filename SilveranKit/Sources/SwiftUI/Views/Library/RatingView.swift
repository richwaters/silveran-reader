import SwiftUI

struct RatingView: View {
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
    @State private var selectedRating: String? = nil
    @State private var ratingListWidth: CGFloat = 220
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

    private var ratingGroups: [(rating: String, books: [BookMetadata])] {
        mediaViewModel.booksByRating(for: mediaKind)
    }

    private var filteredRatingGroups: [(rating: String, books: [BookMetadata])] {
        filterRatings(ratingGroups)
    }

    var body: some View {
        #if os(macOS)
        macOSSplitView
        #else
        iOSRatingList
        #endif
    }

    private func filterRatings(_ groups: [(rating: String, books: [BookMetadata])]) -> [(
        rating: String, books: [BookMetadata]
    )] {
        guard !searchText.isEmpty else { return groups }

        let searchLower = searchText.lowercased()
        return groups.compactMap { group in
            let ratingMatches = Self.displayLabel(for: group.rating).lowercased().contains(searchLower)

            let filteredBooks = group.books.filter { book in
                book.title.lowercased().contains(searchLower)
                    || book.authors?.contains(where: {
                        $0.name?.lowercased().contains(searchLower) ?? false
                    }) ?? false
            }

            if ratingMatches {
                return (rating: group.rating, books: group.books)
            }

            guard !filteredBooks.isEmpty else { return nil }
            return (rating: group.rating, books: filteredBooks)
        }
    }

    static func displayLabel(for rating: String) -> String {
        RatingDisplayHelper.label(for: rating)
    }
}

enum RatingDisplayHelper {
    static func label(for rating: String) -> String {
        if rating == "Unrated" { return "Unrated" }
        guard let stars = Int(rating) else { return rating }
        return String(repeating: "\u{2605}", count: stars) + String(repeating: "\u{2606}", count: 5 - stars)
    }
}

struct RatingRowContent: View {
    let rating: String
    let bookCount: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "star.fill")
                #if os(iOS)
                .font(.body)
                #else
                .font(.system(size: 14))
                #endif
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(RatingView.displayLabel(for: rating))
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
extension RatingView {
    @ViewBuilder
    fileprivate var iOSRatingList: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRatingGroups, id: \.rating) { group in
                        NavigationLink(value: group.rating) {
                            RatingRowContent(
                                rating: group.rating,
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
            .navigationTitle("Ratings")
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
            .navigationDestination(for: String.self) { rating in
                iOSRatingBooksView(rating: rating)
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
    private func iOSRatingBooksView(rating: String) -> some View {
        MediaGridView(
            title: RatingView.displayLabel(for: rating),
            searchText: "",
            mediaKind: mediaKind,
            tagFilter: nil,
            seriesFilter: nil,
            authorFilter: nil,
            narratorFilter: nil,
            ratingFilter: rating,
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
        .navigationTitle(RatingView.displayLabel(for: rating))
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
extension RatingView {
    @ViewBuilder
    fileprivate var macOSSplitView: some View {
        HStack(spacing: 0) {
            macOSRatingListSidebar

            ResizableDivider(width: $ratingListWidth, minWidth: 150, maxWidth: 400)

            macOSBooksContentArea
        }
    }

    @ViewBuilder
    private var macOSRatingListSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ratings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredRatingGroups, id: \.rating) { group in
                        Button {
                            selectedRating = group.rating
                        } label: {
                            RatingRowContent(
                                rating: group.rating,
                                bookCount: group.books.count,
                                isSelected: selectedRating == group.rating
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if group.rating != "Unrated" {
                                let pinId = SidebarPinHelper.pinId(forRating: group.rating)
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
        .frame(width: ratingListWidth)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private var macOSBooksContentArea: some View {
        if let rating = selectedRating {
            MediaGridView(
                title: RatingView.displayLabel(for: rating),
                searchText: searchText,
                mediaKind: mediaKind,
                tagFilter: nil,
                seriesFilter: nil,
                authorFilter: nil,
                narratorFilter: nil,
                ratingFilter: rating,
                statusFilter: nil,
                defaultSort: "title",
                preferredTileWidth: 120,
                minimumTileWidth: 50,
                initialNarrationFilterOption: .both,
                scrollPosition: nil
            )
            .id(rating)
        } else {
            VStack {
                Spacer()
                Text("Select a rating")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}
#endif
