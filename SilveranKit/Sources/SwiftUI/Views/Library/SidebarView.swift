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
    #if os(macOS)
    @State private var editingShelf: SmartShelf?
    @State private var showCustomizeSidebar: Bool = false
    #endif

    @AppStorage("sidebar.config") private var sidebarConfigJSON: String = ""
    @AppStorage("home.sectionConfig") private var homeSectionConfigJSON: String = "[]"

    private var sidebarConfig: [SidebarConfigGroup] {
        let _ = sidebarConfigJSON
        return SidebarConfigHelper.config
    }

    private let defaultLookup = SidebarConfigHelper.defaultItemLookup

    private var storytellerConfigured: Bool {
        mediaViewModel.connectionStatus != .disconnected
    }

    private func resolveConfigItem(_ item: SidebarConfigItem) -> SidebarItemDescription? {
        guard item.visible else { return nil }
        if item.id == SidebarConfigHelper.newPinLocationMarker { return nil }

        if item.id.hasPrefix("pin.") {
            guard var description = resolvePin(id: item.id) else { return nil }
            if let alias = item.alias, !alias.isEmpty {
                description.name = alias
            }
            return description
        }

        guard var description = defaultLookup[item.id] else { return nil }
        if let alias = item.alias, !alias.isEmpty {
            description.name = alias
        }
        return description
    }

    private func resolvePin(id: String) -> SidebarItemDescription? {
        if let resolved = Self.resolveDynamicPin(id: id) {
            return resolved
        }
        guard id.hasPrefix("pin.smartShelf:") else { return nil }
        let uuidString = String(id.dropFirst("pin.smartShelf:".count))
        guard let uuid = UUID(uuidString: uuidString),
            let shelf = mediaViewModel.smartShelves.first(where: { $0.id == uuid })
        else {
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
                content: .mediaGrid(
                    MediaGridConfiguration(
                        title: name,
                        mediaKind: .ebook,
                        preferredTileWidth: 120,
                        minimumTileWidth: 50,
                        seriesFilter: name,
                        defaultSort: "seriesPosition"
                    )
                )
            )
        }
        if id.hasPrefix("pin.collection:") {
            let name = String(id.dropFirst("pin.collection:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "rectangle.stack",
                badge: -1,
                content: .mediaGrid(
                    MediaGridConfiguration(
                        title: name,
                        mediaKind: .ebook,
                        preferredTileWidth: 120,
                        minimumTileWidth: 50,
                        collectionFilter: name
                    )
                )
            )
        }
        if id.hasPrefix("pin.author:") {
            let name = String(id.dropFirst("pin.author:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "person.2",
                badge: -1,
                content: .mediaGrid(
                    MediaGridConfiguration(
                        title: name,
                        mediaKind: .ebook,
                        preferredTileWidth: 120,
                        minimumTileWidth: 50,
                        authorFilter: name
                    )
                )
            )
        }
        if id.hasPrefix("pin.narrator:") {
            let name = String(id.dropFirst("pin.narrator:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "mic",
                badge: -1,
                content: .mediaGrid(
                    MediaGridConfiguration(
                        title: name,
                        mediaKind: .ebook,
                        preferredTileWidth: 120,
                        minimumTileWidth: 50,
                        narratorFilter: name
                    )
                )
            )
        }
        if id.hasPrefix("pin.translator:") {
            let name = String(id.dropFirst("pin.translator:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "character.book.closed.fill",
                badge: -1,
                content: .mediaGrid(
                    MediaGridConfiguration(
                        title: name,
                        mediaKind: .ebook,
                        preferredTileWidth: 120,
                        minimumTileWidth: 50,
                        translatorFilter: name
                    )
                )
            )
        }
        if id.hasPrefix("pin.tag:") {
            let name = String(id.dropFirst("pin.tag:".count))
            return SidebarItemDescription(
                id: id,
                name: name,
                systemImage: "tag",
                badge: -1,
                content: .mediaGrid(
                    MediaGridConfiguration(
                        title: name,
                        mediaKind: .ebook,
                        preferredTileWidth: 120,
                        minimumTileWidth: 50,
                        tagFilter: name
                    )
                )
            )
        }
        if id.hasPrefix("pin.year:") {
            let year = String(id.dropFirst("pin.year:".count))
            return SidebarItemDescription(
                id: id,
                name: year,
                systemImage: "calendar",
                badge: -1,
                content: .mediaGrid(
                    MediaGridConfiguration(
                        title: year,
                        mediaKind: .ebook,
                        preferredTileWidth: 120,
                        minimumTileWidth: 50,
                        publicationYearFilter: year
                    )
                )
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
                content: .mediaGrid(
                    MediaGridConfiguration(
                        title: label,
                        mediaKind: .ebook,
                        preferredTileWidth: 120,
                        minimumTileWidth: 50,
                        ratingFilter: rating
                    )
                )
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
                content: .mediaGrid(
                    MediaGridConfiguration(
                        title: status,
                        mediaKind: .ebook,
                        preferredTileWidth: 120,
                        minimumTileWidth: 50,
                        statusFilter: status,
                        defaultSort: "recentlyRead"
                    )
                )
            )
        }
        return nil
    }

    var body: some View {
        let _ = mediaViewModel.smartShelves
        let config = sidebarConfig
        List(selection: $selectedId) {
            ForEach(config) { group in
                sidebarSection(for: group, config: config)
            }
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
            HomeSectionConfigHelper.syncWithPinnedItems(SidebarPinHelper.pinnedItemIds)
            homeSectionConfigJSON =
                UserDefaults.standard.string(forKey: "home.sectionConfig") ?? "[]"
        }
        .onChange(of: sidebarConfigJSON) {
            HomeSectionConfigHelper.syncWithPinnedItems(SidebarPinHelper.pinnedItemIds)
            homeSectionConfigJSON =
                UserDefaults.standard.string(forKey: "home.sectionConfig") ?? "[]"
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchFocused,
            placement: .sidebar,
            prompt: "Search"
        )
        .navigationSplitViewColumnWidth(min: 180, ideal: 250)
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Customize Sidebar...") {
                        showCustomizeSidebar = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editingShelf) { shelf in
            SmartShelfCreatorView(existingShelf: shelf) { updatedShelf in
                Task { await mediaViewModel.saveSmartShelf(updatedShelf) }
            }
        }
        .sheet(isPresented: $showCustomizeSidebar) {
            CustomizeSidebarView()
        }
        #endif
    }

    // MARK: - Data-driven section rendering

    @ViewBuilder
    private func sidebarSection(for group: SidebarConfigGroup, config: [SidebarConfigGroup])
        -> some View
    {
        let resolvedItems = group.items.compactMap { resolveConfigItem($0) }
        let isPinGroup = group.items.contains { $0.id == SidebarConfigHelper.newPinLocationMarker }

        if isPinGroup && resolvedItems.isEmpty {
            Section(isExpanded: expandedBinding(for: group.id, config: config)) {
                Text("Right-click any series or category to pin it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 8)
            } header: {
                sectionHeader(for: group, config: config)
            }
        } else if !resolvedItems.isEmpty {
            Section(isExpanded: expandedBinding(for: group.id, config: config)) {
                ForEach(resolvedItems) { item in
                    sidebarRow(for: item, isPinned: item.id.hasPrefix("pin."))
                }
            } header: {
                sectionHeader(for: group, config: config)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(for group: SidebarConfigGroup, config: [SidebarConfigGroup])
        -> some View
    {
        HStack {
            Text(group.name)
                .font(.headline)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleExpanded(group.id) }
        .padding(.bottom, 3)
        .padding(.trailing, 16)
    }

    private func expandedBinding(for groupId: UUID, config: [SidebarConfigGroup]) -> Binding<Bool> {
        Binding(
            get: {
                sidebarConfig.first(where: { $0.id == groupId })?.expanded ?? true
            },
            set: { _ in toggleExpanded(groupId) }
        )
    }

    private func toggleExpanded(_ groupId: UUID) {
        var config = SidebarConfigHelper.config
        if let index = config.firstIndex(where: { $0.id == groupId }) {
            config[index].expanded.toggle()
            SidebarConfigHelper.config = config
        }
    }

    // MARK: - Sidebar Row

    @ViewBuilder
    private func sidebarRow(for item: SidebarItemDescription, isPinned: Bool = false) -> some View {
        HStack {
            Label(item.name, systemImage: item.systemImage)
                .tag(item.id)

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
        .contextMenu { sidebarRowContextMenu(for: item, isPinned: isPinned) }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private func sidebarRowContextMenu(for item: SidebarItemDescription, isPinned: Bool)
        -> some View
    {
        if isPinned {
            Button {
                SidebarPinHelper.togglePin(item.id)
            } label: {
                Label("Remove Pin", systemImage: "pin.slash")
            }
        }

        if item.id.hasPrefix("pin.smartShelf:") {
            let uuidString = String(item.id.dropFirst("pin.smartShelf:".count))
            if let uuid = UUID(uuidString: uuidString),
                let shelf = mediaViewModel.smartShelves.first(where: { $0.id == uuid })
            {
                Divider()
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
        if item.id.hasPrefix("pin.") && !isPinned {
            Button {
                SidebarPinHelper.togglePin(item.id)
            } label: {
                Image(systemName: "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
            .opacity(hoveredItemId == item.id ? 1 : 0)
        }
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

    private func findItem(by id: String) -> SidebarItemDescription? {
        for section in sections {
            for item in section.items {
                if item.id == id { return item }
                for child in item.children ?? [] {
                    if child.id == id { return child }
                }
            }
        }
        for group in sidebarConfig {
            for configItem in group.items {
                if configItem.id == id, let resolved = resolveConfigItem(configItem) {
                    return resolved
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
