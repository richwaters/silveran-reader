import SwiftUI

struct TranslatorView: View {
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
    @State private var selectedTranslator: String? = nil
    @State private var translatorListWidth: CGFloat = 220
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

    private var translatorGroups: [(translator: BookCreator?, books: [BookMetadata])] {
        mediaViewModel.booksByTranslator(for: mediaKind)
    }

    private var filteredTranslatorGroups: [(translator: BookCreator?, books: [BookMetadata])] {
        filterTranslators(translatorGroups)
    }

    var body: some View {
        #if os(macOS)
        macOSSplitView
        #else
        iOSTranslatorList
        #endif
    }

    private func filterTranslators(_ groups: [(translator: BookCreator?, books: [BookMetadata])]) -> [(
        translator: BookCreator?, books: [BookMetadata]
    )] {
        guard !searchText.isEmpty else { return groups }

        let searchLower = searchText.lowercased()
        return groups.compactMap { group in
            let translatorNameMatches = group.translator?.name?.lowercased().contains(searchLower) ?? false

            let filteredBooks = group.books.filter { book in
                book.title.lowercased().contains(searchLower)
                    || (book.creators ?? []).contains(where: {
                        $0.role == "trl" && ($0.name?.lowercased().contains(searchLower) ?? false)
                    })
            }

            if translatorNameMatches {
                return (translator: group.translator, books: group.books)
            }

            guard !filteredBooks.isEmpty else { return nil }
            return (translator: group.translator, books: filteredBooks)
        }
    }
}

struct TranslatorRowContent: View {
    let translatorName: String
    let bookCount: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "character.book.closed.fill")
                #if os(iOS)
                .font(.body)
                #else
                .font(.system(size: 14))
                #endif
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(translatorName)
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
extension TranslatorView {
    @ViewBuilder
    fileprivate var iOSTranslatorList: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredTranslatorGroups, id: \.translator?.name) { group in
                        let translatorName = group.translator?.name ?? "Unknown Translator"
                        NavigationLink(value: translatorName) {
                            TranslatorRowContent(
                                translatorName: translatorName,
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
            .navigationTitle("Translators")
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
            .navigationDestination(for: String.self) { translatorName in
                iOSTranslatorBooksView(translatorName: translatorName)
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
    private func iOSTranslatorBooksView(translatorName: String) -> some View {
        MediaGridView(
            title: translatorName,
            searchText: "",
            mediaKind: mediaKind,
            tagFilter: nil,
            seriesFilter: nil,
            authorFilter: nil,
            narratorFilter: nil,
            translatorFilter: translatorName,
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
        .navigationTitle(translatorName)
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
extension TranslatorView {
    @ViewBuilder
    fileprivate var macOSSplitView: some View {
        HStack(spacing: 0) {
            macOSTranslatorListSidebar

            ResizableDivider(width: $translatorListWidth, minWidth: 150, maxWidth: 400)

            macOSBooksContentArea
        }
    }

    private var sortedTranslatorGroups: [(translator: BookCreator?, books: [BookMetadata])] {
        let groups = filteredTranslatorGroups
        guard sortByCount else { return groups }
        return groups.sorted { lhs, rhs in
            if lhs.books.count != rhs.books.count {
                return lhs.books.count > rhs.books.count
            }
            let lName = lhs.translator?.name ?? ""
            let rName = rhs.translator?.name ?? ""
            return lName.localizedCaseInsensitiveCompare(rName) == .orderedAscending
        }
    }

    @ViewBuilder
    private var macOSTranslatorListSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Translators")
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
                    ForEach(sortedTranslatorGroups, id: \.translator?.name) { group in
                        let translatorName = group.translator?.name ?? "Unknown Translator"
                        Button {
                            selectedTranslator = translatorName
                        } label: {
                            TranslatorRowContent(
                                translatorName: translatorName,
                                bookCount: group.books.count,
                                isSelected: selectedTranslator == translatorName
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if group.translator?.name != nil {
                                let pinId = SidebarPinHelper.pinId(forTranslator: translatorName)
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
        .frame(width: translatorListWidth)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private var macOSBooksContentArea: some View {
        if let translatorName = selectedTranslator {
            MediaGridView(
                title: translatorName,
                searchText: searchText,
                mediaKind: mediaKind,
                tagFilter: nil,
                seriesFilter: nil,
                authorFilter: nil,
                narratorFilter: nil,
                translatorFilter: translatorName,
                statusFilter: nil,
                defaultSort: "title",
                preferredTileWidth: 120,
                minimumTileWidth: 50,
                initialNarrationFilterOption: .both,
                scrollPosition: nil
            )
            .id(translatorName)
        } else {
            VStack {
                Spacer()
                Text("Select a translator")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}
#endif
