import Foundation

struct HomeSectionConfigItem: Codable, Identifiable, Equatable {
    var id: String
    var visible: Bool
}

enum HomeSectionConfigHelper {
    private static let key = "home.sectionConfig"

    static let builtInIds: Set<String> = [
        "currentlyReading", "startReading", "recentlyAdded", "completed",
    ]

    static let defaultConfig: [HomeSectionConfigItem] = [
        .init(id: "currentlyReading", visible: true),
        .init(id: "startReading", visible: true),
        .init(id: "recentlyAdded", visible: true),
        .init(id: "completed", visible: true),
    ]

    static var config: [HomeSectionConfigItem] {
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([HomeSectionConfigItem].self, from: data),
              !items.isEmpty else {
            return defaultConfig
        }
        return items
    }

    static func save(_ items: [HomeSectionConfigItem]) {
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: key)
    }

    static func syncWithPinnedItems(_ pinnedIds: [String]) {
        let homePinIds = pinnedIds.filter { $0.hasPrefix("pin.") }

        var current = config
        let existingIds = Set(current.map(\.id))

        let staleIds = current
            .filter { !builtInIds.contains($0.id) && !homePinIds.contains($0.id) }
            .map(\.id)

        let newIds = homePinIds.filter { !existingIds.contains($0) }

        guard !staleIds.isEmpty || !newIds.isEmpty else { return }

        current.removeAll { staleIds.contains($0.id) }
        for pinId in newIds {
            current.append(HomeSectionConfigItem(id: pinId, visible: false))
        }
        save(current)
    }

    static func displayName(for id: String) -> String {
        switch id {
        case "currentlyReading": return "Currently Reading"
        case "startReading": return "Start Reading"
        case "recentlyAdded": return "Recently Added"
        case "completed": return "Completed"
        default:
            return pinDisplayName(for: id) ?? id
        }
    }

    static func systemImage(for id: String) -> String {
        switch id {
        case "currentlyReading": return "book"
        case "startReading": return "bookmark"
        case "recentlyAdded": return "clock"
        case "completed": return "checkmark.circle"
        default:
            return pinSystemImage(for: id) ?? "questionmark"
        }
    }

    private static func pinDisplayName(for id: String) -> String? {
        if id.hasPrefix("pin.series:") { return String(id.dropFirst("pin.series:".count)) }
        if id.hasPrefix("pin.author:") { return String(id.dropFirst("pin.author:".count)) }
        if id.hasPrefix("pin.collection:") { return String(id.dropFirst("pin.collection:".count)) }
        if id.hasPrefix("pin.tag:") { return String(id.dropFirst("pin.tag:".count)) }
        if id.hasPrefix("pin.narrator:") { return String(id.dropFirst("pin.narrator:".count)) }
        if id.hasPrefix("pin.translator:") { return String(id.dropFirst("pin.translator:".count)) }
        if id.hasPrefix("pin.year:") { return String(id.dropFirst("pin.year:".count)) }
        if id.hasPrefix("pin.rating:") {
            let rating = String(id.dropFirst("pin.rating:".count))
            return RatingDisplayHelper.label(for: rating)
        }
        if id.hasPrefix("pin.status:") { return String(id.dropFirst("pin.status:".count)) }
        if id.hasPrefix("pin.smartShelf:") { return nil }
        return nil
    }

    private static func pinSystemImage(for id: String) -> String? {
        if id.hasPrefix("pin.series:") { return "books.vertical" }
        if id.hasPrefix("pin.author:") { return "person.2" }
        if id.hasPrefix("pin.collection:") { return "rectangle.stack" }
        if id.hasPrefix("pin.tag:") { return "tag" }
        if id.hasPrefix("pin.narrator:") { return "mic" }
        if id.hasPrefix("pin.translator:") { return "character.book.closed.fill" }
        if id.hasPrefix("pin.year:") { return "calendar" }
        if id.hasPrefix("pin.rating:") { return "star" }
        if id.hasPrefix("pin.status:") {
            let status = String(id.dropFirst("pin.status:".count))
            switch status.lowercased() {
            case "reading": return "arrow.right.circle.fill"
            case "to read": return "bookmark.fill"
            case "read": return "checkmark.circle.fill"
            default: return "questionmark.circle.fill"
            }
        }
        if id.hasPrefix("pin.smartShelf:") { return "sparkles.rectangle.stack" }
        return nil
    }
}

struct PinItem: Codable, Identifiable, Equatable {
    var id: String
    var alias: String?
    var visible: Bool

    init(id: String, alias: String? = nil, visible: Bool = true) {
        self.id = id
        self.alias = alias
        self.visible = visible
    }
}

struct PinGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var items: [PinItem]
    var expanded: Bool

    init(id: UUID = UUID(), name: String = "Pins", items: [PinItem] = [], expanded: Bool = true) {
        self.id = id
        self.name = name
        self.items = items
        self.expanded = expanded
    }
}

enum SidebarPinHelper {
    private static let legacyKey = "sidebar.pinnedItems"
    private static let groupsKey = "sidebar.pinGroups"

    static var pinGroups: [PinGroup] {
        get {
            if let json = UserDefaults.standard.string(forKey: groupsKey),
               let data = json.data(using: .utf8),
               let groups = try? JSONDecoder().decode([PinGroup].self, from: data) {
                return groups
            }
            return migrateLegacyPins()
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else { return }
            UserDefaults.standard.set(json, forKey: groupsKey)
        }
    }

    private static func migrateLegacyPins() -> [PinGroup] {
        guard let json = UserDefaults.standard.string(forKey: legacyKey),
              let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data),
              !ids.isEmpty else {
            return []
        }
        let items = ids.map { PinItem(id: $0) }
        let group = PinGroup(name: "Pins", items: items)
        pinGroups = [group]
        return [group]
    }

    static var pinnedItemIds: [String] {
        pinGroups.flatMap { $0.items.map(\.id) }
    }

    static func isPinned(_ id: String) -> Bool {
        pinnedItemIds.contains(id)
    }

    static func togglePin(_ id: String) {
        var groups = pinGroups

        for i in groups.indices {
            if let itemIndex = groups[i].items.firstIndex(where: { $0.id == id }) {
                groups[i].items.remove(at: itemIndex)
                if groups.allSatisfy({ $0.items.isEmpty }) {
                    groups = []
                }
                pinGroups = groups
                return
            }
        }

        if groups.isEmpty {
            groups = [PinGroup(name: "Pins", items: [PinItem(id: id)])]
        } else {
            groups[0].items.append(PinItem(id: id))
        }
        pinGroups = groups
    }

    static func displayName(for item: PinItem) -> String? {
        if let alias = item.alias, !alias.isEmpty {
            return alias
        }
        return nil
    }

    static func pinId(forSeries name: String) -> String { "pin.series:\(name)" }
    static func pinId(forCollection name: String) -> String { "pin.collection:\(name)" }
    static func pinId(forAuthor name: String) -> String { "pin.author:\(name)" }
    static func pinId(forNarrator name: String) -> String { "pin.narrator:\(name)" }
    static func pinId(forTranslator name: String) -> String { "pin.translator:\(name)" }
    static func pinId(forTag name: String) -> String { "pin.tag:\(name)" }
    static func pinId(forYear year: String) -> String { "pin.year:\(year)" }
    static func pinId(forRating rating: String) -> String { "pin.rating:\(rating)" }
    static func pinId(forStatus status: String) -> String { "pin.status:\(status)" }
    static func pinId(forSmartShelf id: UUID) -> String { "pin.smartShelf:\(id.uuidString)" }
}

enum SidebarHideHelper {
    private static let key = "sidebar.hiddenItems"

    static var hiddenItemIds: [String] {
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    static func isHidden(_ id: String) -> Bool {
        hiddenItemIds.contains(id)
    }

    static func toggleHidden(_ id: String) {
        var ids = hiddenItemIds
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: key)
    }
}
