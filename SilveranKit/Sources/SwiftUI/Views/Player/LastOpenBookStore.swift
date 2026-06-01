#if os(iOS)
import Foundation

public enum LastOpenBookStore {
    public struct Route: Codable, Equatable {
        public let bookId: String
        public let category: LocalMediaCategory
        public let openedAt: Date
        public let metadata: BookMetadata?
        public let localMediaPath: URL?
        public let localMediaRelativePath: String?

        public init(
            bookId: String,
            category: LocalMediaCategory,
            openedAt: Date,
            metadata: BookMetadata?,
            localMediaPath: URL?,
            localMediaRelativePath: String?,
        ) {
            self.bookId = bookId
            self.category = category
            self.openedAt = openedAt
            self.metadata = metadata
            self.localMediaPath = localMediaPath
            self.localMediaRelativePath = localMediaRelativePath
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bookId = try container.decode(String.self, forKey: .bookId)
            category = try container.decode(LocalMediaCategory.self, forKey: .category)
            openedAt = try container.decode(Date.self, forKey: .openedAt)
            metadata = try container.decodeIfPresent(BookMetadata.self, forKey: .metadata)
            localMediaPath = try container.decodeIfPresent(URL.self, forKey: .localMediaPath)
            localMediaRelativePath = try container.decodeIfPresent(
                String.self,
                forKey: .localMediaRelativePath,
            )
        }
    }

    private static let key = "iOSLastOpenBookRoute"

    public static var hasSavedRoute: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    static func save(bookData: PlayerBookData) async {
        let relativePath: String?
        if let localMediaPath = bookData.localMediaPath {
            relativePath = await FilesystemActor.shared.applicationSupportRelativePath(
                for: localMediaPath
            )
        } else {
            relativePath = nil
        }

        let route = Route(
            bookId: bookData.metadata.uuid,
            category: bookData.category,
            openedAt: Date(),
            metadata: bookData.metadata,
            localMediaPath: bookData.localMediaPath,
            localMediaRelativePath: relativePath,
        )
        guard let data = try? JSONEncoder().encode(route) else { return }
        UserDefaults.standard.set(data, forKey: key)
        debugLog(
            "[LastOpenBookStore] saved bookId=\(bookData.metadata.uuid) category=\(bookData.category.rawValue) relativePath=\(relativePath ?? "nil") path=\(bookData.localMediaPath?.path ?? "nil")"
        )
    }

    public static func load() -> Route? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            debugLog("[LastOpenBookStore] load: no saved route")
            return nil
        }
        guard let route = try? JSONDecoder().decode(Route.self, from: data) else {
            debugLog("[LastOpenBookStore] load: failed to decode saved route")
            return nil
        }
        debugLog(
            "[LastOpenBookStore] load: bookId=\(route.bookId) category=\(route.category.rawValue) openedAt=\(route.openedAt) hasMetadata=\(route.metadata != nil) relativePath=\(route.localMediaRelativePath ?? "nil") path=\(route.localMediaPath?.path ?? "nil")"
        )
        return route
    }

    public static func loadPlayerBookData() async -> PlayerBookData? {
        guard let route = load(),
            let metadata = route.metadata
        else { return nil }

        guard
            let localMediaPath = await FilesystemActor.shared.resolvePersistedApplicationSupportURL(
                relativePath: route.localMediaRelativePath,
                legacyAbsoluteURL: route.localMediaPath,
            )
        else { return nil }

        return PlayerBookData(
            metadata: metadata,
            localMediaPath: localMediaPath,
            category: route.category,
        )
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
