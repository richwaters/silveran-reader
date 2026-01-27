import SwiftUI

struct SidebarView: View {
    let sections: [SidebarSectionDescription]
    @Binding var selectedItem: SidebarItemDescription?
    @Binding var searchText: String
    @Binding var isSearchFocused: Bool
    @Environment(MediaViewModel.self) private var mediaViewModel
    @State private var selectedId: String?
    @State private var isRefreshing: Bool = false
    @State private var hoveredItemId: String?

    @AppStorage("sidebar.library.expanded") private var libraryExpanded: Bool = true
    @AppStorage("sidebar.readingStatus.expanded") private var readingStatusExpanded: Bool = false
    @AppStorage("sidebar.collections.expanded") private var collectionsExpanded: Bool = false
    @AppStorage("sidebar.mediaSources.expanded") private var mediaSourcesExpanded: Bool = true
    @AppStorage("sidebar.pinnedItems") private var pinnedItemsJSON: String = "[]"

    private var pinnedItemIds: [String] {
        guard let data = pinnedItemsJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    private var storytellerConfigured: Bool {
        mediaViewModel.connectionStatus != .disconnected
    }

    private var allItems: [SidebarItemDescription] {
        sections.flatMap { section in
            section.items.flatMap { item in
                [item] + (item.children ?? [])
            }
        }
    }

    private var pinnedItems: [SidebarItemDescription] {
        let ids = pinnedItemIds
        return ids.compactMap { id in
            allItems.first(where: { $0.id == id }) ?? resolvePin(id: id)
        }
    }

    private func resolvePin(id: String) -> SidebarItemDescription? {
        if let resolved = Self.resolveDynamicPin(id: id) {
            return resolved
        }
        guard id.hasPrefix("pin.dynamicShelf:") else { return nil }
        let uuidString = String(id.dropFirst("pin.dynamicShelf:".count))
        guard let uuid = UUID(uuidString: uuidString),
              let shelf = mediaViewModel.dynamicShelves.first(where: { $0.id == uuid }) else {
            return nil
        }
        return SidebarItemDescription(
            id: id,
            name: shelf.name,
            systemImage: "sparkles.rectangle.stack",
            badge: -1,
            content: .dynamicShelfDetail(uuid)
        )
    }

    static func resolveDynamicPin(id: String) -> SidebarItemDescription? {
        if id.hasPrefix("pin.series:") {
            let name = String(id.dropFirst("pin.series:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "books.vertical",
                badge: -1,
                content: .mediaGrid(MediaGridConfiguration(
                    title: name,
                    mediaKind: .ebook,
                    preferredTileWidth: 120,
                    minimumTileWidth: 50,
                    seriesFilter: name
                ))
            )
        }
        if id.hasPrefix("pin.collection:") {
            let name = String(id.dropFirst("pin.collection:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "rectangle.stack",
                badge: -1,
                content: .mediaGrid(MediaGridConfiguration(
                    title: name,
                    mediaKind: .ebook,
                    preferredTileWidth: 120,
                    minimumTileWidth: 50,
                    collectionFilter: name
                ))
            )
        }
        if id.hasPrefix("pin.author:") {
            let name = String(id.dropFirst("pin.author:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "person.2",
                badge: -1,
                content: .mediaGrid(MediaGridConfiguration(
                    title: name,
                    mediaKind: .ebook,
                    preferredTileWidth: 120,
                    minimumTileWidth: 50,
                    authorFilter: name
                ))
            )
        }
        if id.hasPrefix("pin.narrator:") {
            let name = String(id.dropFirst("pin.narrator:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "mic",
                badge: -1,
                content: .mediaGrid(MediaGridConfiguration(
                    title: name,
                    mediaKind: .ebook,
                    preferredTileWidth: 120,
                    minimumTileWidth: 50,
                    narratorFilter: name
                ))
            )
        }
        if id.hasPrefix("pin.translator:") {
            let name = String(id.dropFirst("pin.translator:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "character.book.closed.fill",
                badge: -1,
                content: .mediaGrid(MediaGridConfiguration(
                    title: name,
                    mediaKind: .ebook,
                    preferredTileWidth: 120,
                    minimumTileWidth: 50,
                    translatorFilter: name
                ))
            )
        }
        if id.hasPrefix("pin.tag:") {
            let name = String(id.dropFirst("pin.tag:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "tag",
                badge: -1,
                content: .mediaGrid(MediaGridConfiguration(
                    title: name,
                    mediaKind: .ebook,
                    preferredTileWidth: 120,
                    minimumTileWidth: 50,
                    tagFilter: name
                ))
            )
        }
        if id.hasPrefix("pin.year:") {
            let year = String(id.dropFirst("pin.year:".count))
            return SidebarItemDescription(
                id: id,
                name: year,
                systemImage: "calendar",
                badge: -1,
                content: .mediaGrid(MediaGridConfiguration(
                    title: year,
                    mediaKind: .ebook,
                    preferredTileWidth: 120,
                    minimumTileWidth: 50,
                    publicationYearFilter: year
                ))
            )
        }
        if id.hasPrefix("pin.rating:") {
            let rating = String(id.dropFirst("pin.rating:".count))
            let label = RatingDisplayHelper.label(for: rating)
            return SidebarItemDescription(
                id: id,
                name: label,
                systemImage: "star",
                badge: -1,
                content: .mediaGrid(MediaGridConfiguration(
                    title: label,
                    mediaKind: .ebook,
                    preferredTileWidth: 120,
                    minimumTileWidth: 50,
                    ratingFilter: rating
                ))
            )
        }
        return nil
    }

    var body: some View {
        List(selection: $selectedId) {
            homeSection
            librarySection
            readingStatusSection
            collectionsSection
            mediaSourcesSection
        }
        .onChange(of: selectedId) { oldID, newID in
            if let id = newID {
                selectedItem = findItem(by: id)
            } else {
                selectedItem = nil
            }
        }
        .onChange(of: selectedItem) { oldItem, newItem in
            selectedId = newItem?.id
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchFocused,
            placement: .sidebar,
            prompt: "Search"
        )
        .navigationSplitViewColumnWidth(min: 180, ideal: 250)
    }

    // MARK: - Home Section (always open)

    @ViewBuilder
    private var homeSection: some View {
        Section {
            if let homeSection = sections.first(where: { $0.id == "section.home" }) {
                ForEach(homeSection.items) { item in
                    sidebarRow(for: item)
                }
            }
            ForEach(pinnedItems) { item in
                sidebarRow(for: item, isPinned: true)
            }
        } header: {
            Text("Favorites")
                .font(.headline)
                .padding(.bottom, 3)
                .padding(.trailing, 16)
        }
    }

    // MARK: - Library Section

    @ViewBuilder
    private var librarySection: some View {
        if let section = sections.first(where: { $0.id == "section.library" }) {
            Section(isExpanded: $libraryExpanded) {
                ForEach(section.items) { item in
                    sidebarRow(for: item)
                }
            } header: {
                HStack {
                    Text(section.name)
                        .font(.headline)
                    Spacer()
                    #if os(macOS)
                    if storytellerConfigured {
                        Button {
                            Task { await refreshMetadata() }
                        } label: {
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isRefreshing)
                    }
                    #endif
                }
                .contentShape(Rectangle())
                .onTapGesture { libraryExpanded.toggle() }
                .padding(.bottom, 3)
                .padding(.trailing, 16)
            }
        }
    }

    // MARK: - Reading Status Section

    @ViewBuilder
    private var readingStatusSection: some View {
        if let section = sections.first(where: { $0.id == "section.readingStatus" }) {
            Section(isExpanded: $readingStatusExpanded) {
                ForEach(section.items) { item in
                    sidebarRow(for: item)
                }
            } header: {
                Text(section.name)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { readingStatusExpanded.toggle() }
                    .padding(.bottom, 3)
                    .padding(.trailing, 16)
            }
        }
    }

    // MARK: - Collections Section

    @ViewBuilder
    private var collectionsSection: some View {
        if let section = sections.first(where: { $0.id == "section.collections" }) {
            Section(isExpanded: $collectionsExpanded) {
                ForEach(section.items) { item in
                    sidebarRow(for: item)
                }
            } header: {
                Text(section.name)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { collectionsExpanded.toggle() }
                    .padding(.bottom, 3)
                    .padding(.trailing, 16)
            }
        }
    }

    // MARK: - Media Sources Section

    @ViewBuilder
    private var mediaSourcesSection: some View {
        if let section = sections.first(where: { $0.id == "section.mediaSources" }) {
            Section(isExpanded: $mediaSourcesExpanded) {
                ForEach(section.items) { item in
                    sidebarRow(for: item)
                }
            } header: {
                Text(section.name)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { mediaSourcesExpanded.toggle() }
                    .padding(.bottom, 3)
                    .padding(.trailing, 16)
            }
        }
    }

    // MARK: - Sidebar Row

    @ViewBuilder
    private func sidebarRow(for item: SidebarItemDescription, isPinned: Bool = false) -> some View {
        HStack {
            Label(item.name, systemImage: item.systemImage)
                .tag(item.id)
            Spacer()

            if item.content == .storytellerServer {
                connectionIndicator(for: mediaViewModel.connectionStatus)
            } else {
                let count = mediaViewModel.badgeCount(for: item.content)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            #if os(macOS)
            pinButton(for: item, isPinned: isPinned)
            #endif
        }
        #if os(macOS)
        .onHover { hovering in
            hoveredItemId = hovering ? item.id : nil
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private func pinButton(for item: SidebarItemDescription, isPinned: Bool) -> some View {
        if item.content != .home {
            let isCurrentlyPinned = isPinned || SidebarPinHelper.isPinned(item.id)
            let showButton = hoveredItemId == item.id || isCurrentlyPinned
            Button {
                SidebarPinHelper.togglePin(item.id)
            } label: {
                Image(systemName: isCurrentlyPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
            .opacity(showButton ? 1 : 0)
        }
    }
    #endif

    // MARK: - Helpers

    private func findItem(by id: String) -> SidebarItemDescription? {
        for section in sections {
            for item in section.items {
                if item.id == id { return item }
                for child in item.children ?? [] {
                    if child.id == id { return child }
                }
            }
        }
        return resolvePin(id: id)
    }

    @ViewBuilder
    private func connectionIndicator(for status: ConnectionStatus) -> some View {
        switch status {
            case .connected:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            case .connecting:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            case .disconnected:
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
            case .error:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
        }
    }

    #if os(macOS)
    private func refreshMetadata() async {
        isRefreshing = true

        if let library = await StorytellerActor.shared.fetchLibraryInformation() {
            do {
                try await LocalMediaActor.shared.updateStorytellerMetadata(library)
                await mediaViewModel.refreshMetadata(source: "SidebarView.refresh")
                mediaViewModel.showSyncNotification(
                    SyncNotification(message: "Library refreshed", type: .success)
                )
            } catch {
                mediaViewModel.showSyncNotification(
                    SyncNotification(message: "Failed to update metadata", type: .error)
                )
            }
        } else {
            mediaViewModel.showSyncNotification(
                SyncNotification(message: "Failed to fetch metadata from server", type: .error)
            )
        }

        isRefreshing = false
    }
    #endif
}
