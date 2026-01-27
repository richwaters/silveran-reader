import Foundation

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
