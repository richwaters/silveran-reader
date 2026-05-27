#if os(iOS)
import Foundation

public enum LastOpenBookStore {
    struct Route: Codable, Equatable {
        let bookId: String
        let category: LocalMediaCategory
        let openedAt: Date
        let metadata: BookMetadata?
        let localMediaPath: URL?
    }

    private static let key = "iOSLastOpenBookRoute"

    public static var hasSavedRoute: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    static func save(bookData: PlayerBookData) {
        let route = Route(
            bookId: bookData.metadata.uuid,
            category: bookData.category,
            openedAt: Date(),
            metadata: bookData.metadata,
            localMediaPath: bookData.localMediaPath,
        )
        guard let data = try? JSONEncoder().encode(route) else { return }
        UserDefaults.standard.set(data, forKey: key)
        debugLog(
            "[LastOpenBookStore] saved bookId=\(bookData.metadata.uuid) category=\(bookData.category.rawValue) path=\(bookData.localMediaPath?.path ?? "nil")"
        )
    }

    static func load() -> Route? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            debugLog("[LastOpenBookStore] load: no saved route")
            return nil
        }
        guard let route = try? JSONDecoder().decode(Route.self, from: data) else {
            debugLog("[LastOpenBookStore] load: failed to decode saved route")
            return nil
        }
        debugLog(
            "[LastOpenBookStore] load: bookId=\(route.bookId) category=\(route.category.rawValue) openedAt=\(route.openedAt) hasMetadata=\(route.metadata != nil) path=\(route.localMediaPath?.path ?? "nil")"
        )
        return route
    }

    static func clearIfMatching(bookId: String, category: LocalMediaCategory) {
        guard let route = load(),
            route.bookId == bookId,
            route.category == category
        else { return }
        debugLog(
            "[LastOpenBookStore] clearIfMatching: matched bookId=\(bookId) category=\(category.rawValue)"
        )
        clear()
    }

    static func clear() {
        debugLog("[LastOpenBookStore] clear")
        UserDefaults.standard.removeObject(forKey: key)
    }
}
#endif
