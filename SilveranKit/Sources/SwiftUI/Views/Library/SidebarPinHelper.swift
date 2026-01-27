import Foundation

struct HomeSectionConfigItem: Codable, Identifiable, Equatable {
    var id: String
    var visible: Bool
}

enum HomeSectionConfigHelper {
    private static let key = "home.sectionConfig"

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

    static func displayName(for id: String) -> String {
        switch id {
        case "currentlyReading": return "Currently Reading"
        case "startReading": return "Start Reading"
        case "recentlyAdded": return "Recently Added"
        case "completed": return "Completed"
        default: return id
        }
    }

    static func systemImage(for id: String) -> String {
        switch id {
        case "currentlyReading": return "book"
        case "startReading": return "bookmark"
        case "recentlyAdded": return "clock"
        case "completed": return "checkmark.circle"
        default: return "questionmark"
        }
    }
}

enum SidebarPinHelper {
    private static let key = "sidebar.pinnedItems"

    static var pinnedItemIds: [String] {
        guard let json = UserDefaults.standard.string(forKey: key),
              let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    static func isPinned(_ id: String) -> Bool {
        pinnedItemIds.contains(id)
    }

    static func togglePin(_ id: String) {
        var ids = pinnedItemIds
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: key)
    }

    static func pinId(forSeries name: String) -> String { "pin.series:\(name)" }
    static func pinId(forCollection name: String) -> String { "pin.collection:\(name)" }
    static func pinId(forAuthor name: String) -> String { "pin.author:\(name)" }
    static func pinId(forNarrator name: String) -> String { "pin.narrator:\(name)" }
    static func pinId(forTranslator name: String) -> String { "pin.translator:\(name)" }
    static func pinId(forTag name: String) -> String { "pin.tag:\(name)" }
    static func pinId(forYear year: String) -> String { "pin.year:\(year)" }
    static func pinId(forRating rating: String) -> String { "pin.rating:\(rating)" }
    static func pinId(forDynamicShelf id: UUID) -> String { "pin.dynamicShelf:\(id.uuidString)" }
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
