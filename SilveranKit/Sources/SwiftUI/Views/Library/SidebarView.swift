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
    @State private var hoveredSectionId: String?
    @State private var visibilityPopoverSectionId: String?
    @State private var homePopoverVisible: Bool = false
    @State private var homeSectionConfig: [HomeSectionConfigItem] = HomeSectionConfigHelper.config
    #if os(macOS)
    @State private var editingShelf: SmartShelf?
    #endif

    @AppStorage("sidebar.library.expanded") private var libraryExpanded: Bool = true
    @AppStorage("sidebar.readingStatus.expanded") private var readingStatusExpanded: Bool = false
    @AppStorage("sidebar.collections.expanded") private var collectionsExpanded: Bool = false
    @AppStorage("sidebar.mediaSources.expanded") private var mediaSourcesExpanded: Bool = true
    @AppStorage("sidebar.pinnedItems") private var pinnedItemsJSON: String = "[]"
    @AppStorage("sidebar.hiddenItems") private var hiddenItemsJSON: String = "[]"
    @AppStorage("home.sectionConfig") private var homeSectionConfigJSON: String = "[]"

    private var hiddenItemIds: [String] {
        guard let data = hiddenItemsJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

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

    private var pinnedItems: [SidebarItemDescription] {
        pinnedItemIds
            .filter { $0.hasPrefix("pin.") }
            .compactMap { resolvePin(id: $0) }
    }

    private func resolvePin(id: String) -> SidebarItemDescription? {
        if let resolved = Self.resolveDynamicPin(id: id) {
            return resolved
        }
        guard id.hasPrefix("pin.smartShelf:") else { return nil }
        let uuidString = String(id.dropFirst("pin.smartShelf:".count))
        guard let uuid = UUID(uuidString: uuidString),
              let shelf = mediaViewModel.smartShelves.first(where: { $0.id == uuid }) else {
            return nil
        }
        return SidebarItemDescription(
            id: id,
            name: shelf.name,
            systemImage: "sparkles.rectangle.stack",
            badge: -1,
            content: .smartShelfDetail(uuid)
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
                    seriesFilter: name,
                    defaultSort: "seriesPosition"
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
        if id.hasPrefix("pin.status:") {
            let status = String(id.dropFirst("pin.status:".count))
            let icon: String
            switch status.lowercased() {
            case "reading": icon = "arrow.right.circle.fill"
            case "to read": icon = "bookmark.fill"
            case "read": icon = "checkmark.circle.fill"
            default: icon = "questionmark.circle.fill"
            }
            return SidebarItemDescription(
                id: id,
                name: status,
                systemImage: icon,
                badge: -1,
                content: .mediaGrid(MediaGridConfiguration(
                    title: status,
                    mediaKind: .ebook,
                    preferredTileWidth: 120,
                    minimumTileWidth: 50,
                    statusFilter: status,
                    defaultSort: "recentlyRead"
                ))
            )
        }
        return nil
    }

    var body: some View {
        let _ = mediaViewModel.smartShelves
        List(selection: $selectedId) {
            homeSection
            librarySection
            readingStatusSection
            collectionsSection
            mediaSourcesSection
        }
        .onChange(of: selectedId) { oldID, newID in
            if let id = newID, let found = findItem(by: id) {
                selectedItem = found
            } else if newID == nil, selectedItem != nil, findItem(by: selectedItem!.id) != nil {
                selectedItem = nil
            }
        }
        .onChange(of: selectedItem) { oldItem, newItem in
            if let newItem {
                if findItem(by: newItem.id) != nil {
                    selectedId = newItem.id
                } else {
                    selectedId = nil
                }
            } else {
                selectedId = nil
            }
        }
        .onAppear {
            HomeSectionConfigHelper.syncWithPinnedItems(pinnedItemIds)
            homeSectionConfig = HomeSectionConfigHelper.config
            homeSectionConfigJSON = UserDefaults.standard.string(forKey: "home.sectionConfig") ?? "[]"
        }
        .onChange(of: pinnedItemsJSON) {
            HomeSectionConfigHelper.syncWithPinnedItems(pinnedItemIds)
            homeSectionConfig = HomeSectionConfigHelper.config
            homeSectionConfigJSON = UserDefaults.standard.string(forKey: "home.sectionConfig") ?? "[]"
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchFocused,
            placement: .sidebar,
            prompt: "Search"
        )
        .navigationSplitViewColumnWidth(min: 180, ideal: 250)
        #if os(macOS)
        .sheet(item: $editingShelf) { shelf in
            SmartShelfCreatorView(existingShelf: shelf) { updatedShelf in
                Task { await mediaViewModel.saveSmartShelf(updatedShelf) }
            }
        }
        #endif
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
            let hidden = hiddenItemIds
            Section(isExpanded: nonAnimating($libraryExpanded)) {
                ForEach(section.items.filter { !hidden.contains($0.id) }) { item in
                    sidebarRow(for: item)
                }
            } header: {
                HStack {
                    Text(section.name)
                        .font(.headline)
                    #if os(macOS)
                    visibilityMenuButton(for: section)
                    #endif
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { libraryExpanded.toggle() }
                .padding(.bottom, 3)
                .padding(.trailing, 16)
                #if os(macOS)
                .onHover { hovering in
                    hoveredSectionId = hovering ? section.id : nil
                }
                #endif
            }
        }
    }

    // MARK: - Reading Status Section

    @ViewBuilder
    private var readingStatusSection: some View {
        if let section = sections.first(where: { $0.id == "section.readingStatus" }) {
            let hidden = hiddenItemIds
            Section(isExpanded: nonAnimating($readingStatusExpanded)) {
                ForEach(section.items.filter { !hidden.contains($0.id) }) { item in
                    sidebarRow(for: item)
                }
            } header: {
                HStack {
                    Text(section.name)
                        .font(.headline)
                    #if os(macOS)
                    visibilityMenuButton(for: section)
                    #endif
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { readingStatusExpanded.toggle() }
                .padding(.bottom, 3)
                .padding(.trailing, 16)
                #if os(macOS)
                .onHover { hovering in
                    hoveredSectionId = hovering ? section.id : nil
                }
                #endif
            }
        }
    }

    // MARK: - Collections Section

    @ViewBuilder
    private var collectionsSection: some View {
        if let section = sections.first(where: { $0.id == "section.collections" }) {
            let hidden = hiddenItemIds
            Section(isExpanded: nonAnimating($collectionsExpanded)) {
                ForEach(section.items.filter { !hidden.contains($0.id) }) { item in
                    sidebarRow(for: item)
                }
            } header: {
                HStack {
                    Text(section.name)
                        .font(.headline)
                    #if os(macOS)
                    visibilityMenuButton(for: section)
                    #endif
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { collectionsExpanded.toggle() }
                .padding(.bottom, 3)
                .padding(.trailing, 16)
                #if os(macOS)
                .onHover { hovering in
                    hoveredSectionId = hovering ? section.id : nil
                }
                #endif
            }
        }
    }

    // MARK: - Media Sources Section

    @ViewBuilder
    private var mediaSourcesSection: some View {
        if let section = sections.first(where: { $0.id == "section.mediaSources" }) {
            let hidden = hiddenItemIds
            Section(isExpanded: nonAnimating($mediaSourcesExpanded)) {
                ForEach(section.items.filter { !hidden.contains($0.id) }) { item in
                    sidebarRow(for: item)
                }
            } header: {
                HStack {
                    Text(section.name)
                        .font(.headline)
                    #if os(macOS)
                    visibilityMenuButton(for: section)
                    #endif
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { mediaSourcesExpanded.toggle() }
                .padding(.bottom, 3)
                .padding(.trailing, 16)
                #if os(macOS)
                .onHover { hovering in
                    hoveredSectionId = hovering ? section.id : nil
                }
                #endif
            }
        }
    }

    // MARK: - Sidebar Row

    @ViewBuilder
    private func sidebarRow(for item: SidebarItemDescription, isPinned: Bool = false) -> some View {
        HStack {
            Label(item.name, systemImage: item.systemImage)
                .tag(item.id)
            #if os(macOS)
            if item.content == .home {
                homeVisibilityButton(for: item)
            }
            #endif
            Spacer()

            #if os(macOS)
            pinButton(for: item, isPinned: isPinned)
            #endif

            if item.content == .storytellerServer {
                #if os(macOS)
                if storytellerConfigured {
                    Button {
                        Task { await refreshMetadata() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isRefreshing)
                }
                #endif
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
        }
        #if os(macOS)
        .onHover { hovering in
            hoveredItemId = hovering ? item.id : nil
        }
        .contextMenu { smartShelfContextMenu(for: item) }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private func smartShelfContextMenu(for item: SidebarItemDescription) -> some View {
        if item.id.hasPrefix("pin.smartShelf:") {
            let uuidString = String(item.id.dropFirst("pin.smartShelf:".count))
            if let uuid = UUID(uuidString: uuidString),
               let shelf = mediaViewModel.smartShelves.first(where: { $0.id == uuid }) {
                Button {
                    editingShelf = shelf
                } label: {
                    Label("Edit Shelf", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    Task { await mediaViewModel.deleteSmartShelf(id: shelf.id) }
                } label: {
                    Label("Delete Shelf", systemImage: "trash")
                }
            }
        }
    }
    #endif

    #if os(macOS)
    @ViewBuilder
    private func pinButton(for item: SidebarItemDescription, isPinned: Bool) -> some View {
        if item.id.hasPrefix("pin.") {
            let isCurrentlyPinned = isPinned || SidebarPinHelper.isPinned(item.id)
            Button {
                SidebarPinHelper.togglePin(item.id)
            } label: {
                Image(systemName: isCurrentlyPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
            .opacity(hoveredItemId == item.id ? 1 : 0)
        }
    }
    @ViewBuilder
    private func homeVisibilityButton(for item: SidebarItemDescription) -> some View {
        let showButton = hoveredItemId == item.id || homePopoverVisible
        Button {
            homePopoverVisible.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.5))
                .frame(width: 12, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(showButton ? 1 : 0)
        .popover(isPresented: $homePopoverVisible, arrowEdge: .trailing) {
            homeSectionsPopoverContent
        }
    }

    @ViewBuilder
    private var homeSectionsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Home Sections")
                .font(.headline)
                .padding(.bottom, 4)

            List {
                ForEach(homeSectionConfig) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Toggle(isOn: Binding(
                            get: { item.visible },
                            set: { newValue in
                                if let idx = homeSectionConfig.firstIndex(where: { $0.id == item.id }) {
                                    homeSectionConfig[idx].visible = newValue
                                    HomeSectionConfigHelper.save(homeSectionConfig)
                                    homeSectionConfigJSON = UserDefaults.standard.string(forKey: "home.sectionConfig") ?? "[]"
                                }
                            }
                        )) {
                            Label(
                                homeSectionDisplayName(for: item.id),
                                systemImage: HomeSectionConfigHelper.systemImage(for: item.id)
                            )
                        }
                    }
                }
                .onMove { from, to in
                    homeSectionConfig.move(fromOffsets: from, toOffset: to)
                    HomeSectionConfigHelper.save(homeSectionConfig)
                    homeSectionConfigJSON = UserDefaults.standard.string(forKey: "home.sectionConfig") ?? "[]"
                }
            }
            .listStyle(.plain)
            .frame(height: CGFloat(homeSectionConfig.count) * 34)
        }
        .padding(12)
        .frame(minWidth: 260)
    }
    #endif

    // MARK: - Section Visibility

    #if os(macOS)
    @ViewBuilder
    private func visibilityMenuButton(for section: SidebarSectionDescription) -> some View {
        let showButton = hoveredSectionId == section.id || visibilityPopoverSectionId == section.id
        Button {
            visibilityPopoverSectionId = visibilityPopoverSectionId == section.id ? nil : section.id
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.5))
                .frame(width: 12, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(showButton ? 1 : 0)
        .popover(
            isPresented: Binding(
                get: { visibilityPopoverSectionId == section.id },
                set: { if !$0 { visibilityPopoverSectionId = nil } }
            ),
            arrowEdge: .trailing
        ) {
            visibilityPopoverContent(for: section)
        }
    }

    @ViewBuilder
    private func visibilityPopoverContent(for section: SidebarSectionDescription) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Show Items")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(section.items) { item in
                let hidden = hiddenItemIds.contains(item.id)
                Toggle(isOn: Binding(
                    get: { !hidden },
                    set: { _ in
                        SidebarHideHelper.toggleHidden(item.id)
                        hiddenItemsJSON = UserDefaults.standard.string(forKey: "sidebar.hiddenItems") ?? "[]"
                    }
                )) {
                    Label(item.name, systemImage: item.systemImage)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 200)
    }
    #endif

    // MARK: - Helpers

    private func nonAnimating(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                var t = Transaction()
                t.animation = nil
                withTransaction(t) {
                    binding.wrappedValue = newValue
                }
            }
        )
    }

    private func homeSectionDisplayName(for id: String) -> String {
        if id.hasPrefix("pin.smartShelf:") {
            let uuidString = String(id.dropFirst("pin.smartShelf:".count))
            if let uuid = UUID(uuidString: uuidString),
               let shelf = mediaViewModel.smartShelves.first(where: { $0.id == uuid }) {
                return shelf.name
            }
            return id
        }
        return HomeSectionConfigHelper.displayName(for: id)
    }

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
