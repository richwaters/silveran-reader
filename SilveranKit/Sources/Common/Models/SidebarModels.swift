import Foundation

public struct SidebarSectionDescription: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var items: [SidebarItemDescription]

    public init(id: String, name: String, items: [SidebarItemDescription]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

public struct SidebarItemDescription: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var systemImage: String
    public var badge: Int32
    public var children: [SidebarItemDescription]? = nil
    public var content: SidebarContentKind

    public init(
        id: String? = nil,
        name: String,
        systemImage: String,
        badge: Int32,
        children: [SidebarItemDescription]? = nil,
        content: SidebarContentKind
    ) {
        self.id = id ?? content.stableIdentifier
        self.name = name
        self.systemImage = systemImage
        self.badge = badge
        self.children = children
        self.content = content
    }
}

public enum SidebarContentKind: Hashable, Sendable {
    case home
    case mediaGrid(MediaGridConfiguration)
    case seriesView(MediaKind)
    case authorView(MediaKind)
    case narratorView(MediaKind)
    case translatorView(MediaKind)
    case tagView(MediaKind)
    case publicationYearView(MediaKind)
    case ratingView(MediaKind)
    case collectionsView(MediaKind)
    case dynamicShelves
    case placeholder(title: String)
    case currentlyDownloading
    case importLocalFile
    case storytellerServer

    public var stableIdentifier: String {
        switch self {
        case .home:
            return "home"
        case .mediaGrid(let config):
            return "mediaGrid.\(config.title)"
        case .seriesView(let kind):
            return "seriesView.\(kind.rawValue)"
        case .authorView(let kind):
            return "authorView.\(kind.rawValue)"
        case .narratorView(let kind):
            return "narratorView.\(kind.rawValue)"
        case .translatorView(let kind):
            return "translatorView.\(kind.rawValue)"
        case .tagView(let kind):
            return "tagView.\(kind.rawValue)"
        case .publicationYearView(let kind):
            return "publicationYearView.\(kind.rawValue)"
        case .ratingView(let kind):
            return "ratingView.\(kind.rawValue)"
        case .collectionsView(let kind):
            return "collectionsView.\(kind.rawValue)"
        case .dynamicShelves:
            return "dynamicShelves"
        case .placeholder(let title):
            return "placeholder.\(title)"
        case .currentlyDownloading:
            return "currentlyDownloading"
        case .importLocalFile:
            return "importLocalFile"
        case .storytellerServer:
            return "storytellerServer"
        }
    }
}

public enum NarrationFilter: Hashable, Sendable {
    case both
    case withAudio
    case withoutAudio
}

public enum LocationFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case downloaded
    case serverOnly
    case localFiles
}

public enum MediaKind: String, CaseIterable, Sendable {
    case ebook
    case audiobook
}

public struct MediaGridConfiguration: Hashable, Sendable {
    public var title: String
    public var mediaKind: MediaKind
    public var preferredTileWidth: Double?
    public var minimumTileWidth: Double?
    public var narrationFilter: NarrationFilter
    public var locationFilter: LocationFilter
    public var tagFilter: String?
    public var seriesFilter: String?
    public var collectionFilter: String?
    public var authorFilter: String?
    public var narratorFilter: String?
    public var translatorFilter: String?
    public var publicationYearFilter: String?
    public var ratingFilter: String?
    public var statusFilter: String?
    public var defaultSort: String?

    public init(
        title: String,
        mediaKind: MediaKind,
        preferredTileWidth: Double? = nil,
        minimumTileWidth: Double? = nil,
        narrationFilter: NarrationFilter = .both,
        locationFilter: LocationFilter = .all,
        tagFilter: String? = nil,
        seriesFilter: String? = nil,
        collectionFilter: String? = nil,
        authorFilter: String? = nil,
        narratorFilter: String? = nil,
        translatorFilter: String? = nil,
        publicationYearFilter: String? = nil,
        ratingFilter: String? = nil,
        statusFilter: String? = nil,
        defaultSort: String? = nil
    ) {
        self.title = title
        self.mediaKind = mediaKind
        self.preferredTileWidth = preferredTileWidth
        self.minimumTileWidth = minimumTileWidth
        self.narrationFilter = narrationFilter
        self.locationFilter = locationFilter
        self.tagFilter = tagFilter
        self.seriesFilter = seriesFilter
        self.collectionFilter = collectionFilter
        self.authorFilter = authorFilter
        self.narratorFilter = narratorFilter
        self.translatorFilter = translatorFilter
        self.publicationYearFilter = publicationYearFilter
        self.ratingFilter = ratingFilter
        self.statusFilter = statusFilter
        self.defaultSort = defaultSort
    }
}

public enum LibrarySidebarDefaults {
    public static func getSections() -> [SidebarSectionDescription] {
        [
            SidebarSectionDescription(
                id: "section.home",
                name: "Home",
                items: [
                    SidebarItemDescription(
                        name: "Home",
                        systemImage: "house",
                        badge: 0,
                        content: .home
                    ),
                ]
            ),
            SidebarSectionDescription(
                id: "section.library",
                name: "Library",
                items: [
                    SidebarItemDescription(
                        name: "All Books",
                        systemImage: "book",
                        badge: 112,
                        content: .mediaGrid(
                            MediaGridConfiguration(
                                title: "All Books",
                                mediaKind: .ebook,
                                preferredTileWidth: 120,
                                minimumTileWidth: 50
                            )
                        )
                    ),
                    SidebarItemDescription(
                        name: "By Series",
                        systemImage: "books.vertical",
                        badge: -1,
                        content: .seriesView(.ebook)
                    ),
                    SidebarItemDescription(
                        name: "By Author",
                        systemImage: "person.2",
                        badge: -1,
                        content: .authorView(.ebook)
                    ),
                    SidebarItemDescription(
                        name: "By Narrator",
                        systemImage: "mic",
                        badge: -1,
                        content: .narratorView(.ebook)
                    ),
                    SidebarItemDescription(
                        name: "By Translator",
                        systemImage: "character.book.closed.fill",
                        badge: -1,
                        content: .translatorView(.ebook)
                    ),
                    SidebarItemDescription(
                        name: "By Tag",
                        systemImage: "tag",
                        badge: -1,
                        content: .tagView(.ebook)
                    ),
                    SidebarItemDescription(
                        name: "By Publication Year",
                        systemImage: "calendar",
                        badge: -1,
                        content: .publicationYearView(.ebook)
                    ),
                    SidebarItemDescription(
                        name: "By Rating",
                        systemImage: "star",
                        badge: -1,
                        content: .ratingView(.ebook)
                    ),
                ]
            ),
            SidebarSectionDescription(
                id: "section.readingStatus",
                name: "Reading Status",
                items: [
                    SidebarItemDescription(
                        name: "Currently Reading",
                        systemImage: "arrow.right.circle",
                        badge: 8,
                        content: .mediaGrid(
                            MediaGridConfiguration(
                                title: "Currently Reading",
                                mediaKind: .ebook,
                                preferredTileWidth: 120,
                                minimumTileWidth: 50,
                                statusFilter: "Reading",
                                defaultSort: "recentlyRead"
                            )
                        )
                    ),
                    SidebarItemDescription(
                        name: "Start Reading",
                        systemImage: "bookmark",
                        badge: 8,
                        content: .mediaGrid(
                            MediaGridConfiguration(
                                title: "Start Reading",
                                mediaKind: .ebook,
                                preferredTileWidth: 120,
                                minimumTileWidth: 50,
                                statusFilter: "To read",
                                defaultSort: "recentlyAdded"
                            )
                        )
                    ),
                    SidebarItemDescription(
                        name: "Recently Added",
                        systemImage: "clock",
                        badge: 12,
                        content: .mediaGrid(
                            MediaGridConfiguration(
                                title: "Recently Added",
                                mediaKind: .ebook,
                                preferredTileWidth: 120,
                                minimumTileWidth: 50,
                                defaultSort: "recentlyAdded"
                            )
                        )
                    ),
                    SidebarItemDescription(
                        name: "Completed",
                        systemImage: "checkmark.circle",
                        badge: 12,
                        content: .mediaGrid(
                            MediaGridConfiguration(
                                title: "Completed",
                                mediaKind: .ebook,
                                preferredTileWidth: 120,
                                minimumTileWidth: 50,
                                statusFilter: "Read",
                                defaultSort: "recentlyRead"
                            )
                        )
                    ),
                    SidebarItemDescription(
                        name: "Downloaded",
                        systemImage: "arrow.down.circle",
                        badge: -1,
                        content: .mediaGrid(
                            MediaGridConfiguration(
                                title: "Downloaded",
                                mediaKind: .ebook,
                                preferredTileWidth: 120,
                                minimumTileWidth: 50,
                                locationFilter: .downloaded
                            )
                        )
                    ),
                ]
            ),
            SidebarSectionDescription(
                id: "section.collections",
                name: "Collections",
                items: [
                    SidebarItemDescription(
                        name: "Custom Collections",
                        systemImage: "rectangle.stack",
                        badge: -1,
                        content: .collectionsView(.ebook)
                    ),
                    SidebarItemDescription(
                        name: "Dynamic Shelves",
                        systemImage: "sparkles.rectangle.stack",
                        badge: -1,
                        content: .dynamicShelves
                    ),
                ]
            ),
            SidebarSectionDescription(
                id: "section.mediaSources",
                name: "Media Sources",
                items: [
                    SidebarItemDescription(
                        name: "Storyteller Server",
                        systemImage: "server.rack",
                        badge: -1,
                        content: .storytellerServer
                    ),
                    SidebarItemDescription(
                        name: "Local Files",
                        systemImage: "folder",
                        badge: -1,
                        content: .importLocalFile
                    ),
                    SidebarItemDescription(
                        name: "Currently Downloading",
                        systemImage: "arrow.down.circle.dotted",
                        badge: -1,
                        content: .currentlyDownloading
                    ),
                ]
            ),
        ]
    }
}
