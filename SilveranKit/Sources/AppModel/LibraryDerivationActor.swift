import Foundation
import SilveranKitCommon

public struct LibraryViewSnapshot: Sendable {
    public var generation: Int
    public var badgeCounts: [String: Int]
    public var groups: LibraryGroupSnapshot

    public init(
        generation: Int = 0,
        badgeCounts: [String: Int] = [:],
        groups: LibraryGroupSnapshot = LibraryGroupSnapshot(),
    ) {
        self.generation = generation
        self.badgeCounts = badgeCounts
        self.groups = groups
    }
}

public struct LibraryGroupSnapshot: Sendable {
    public var generation: Int
    public var series: [MediaKind: [LibrarySeriesGroup]]
    public var authors: [MediaKind: [LibraryCreatorGroup]]
    public var collections: [MediaKind: [LibraryCollectionGroup]]
    public var narrators: [MediaKind: [LibraryCreatorGroup]]
    public var translators: [MediaKind: [LibraryCreatorGroup]]
    public var publicationYears: [MediaKind: [LibraryNamedBooksGroup]]
    public var tags: [MediaKind: [LibraryNamedBooksGroup]]
    public var ratings: [MediaKind: [LibraryNamedBooksGroup]]
    public var statuses: [MediaKind: [LibraryNamedBooksGroup]]
    public var sources: [MediaKind: [LibraryNamedBooksGroup]]

    public init(
        generation: Int = 0,
        series: [MediaKind: [LibrarySeriesGroup]] = [:],
        authors: [MediaKind: [LibraryCreatorGroup]] = [:],
        collections: [MediaKind: [LibraryCollectionGroup]] = [:],
        narrators: [MediaKind: [LibraryCreatorGroup]] = [:],
        translators: [MediaKind: [LibraryCreatorGroup]] = [:],
        publicationYears: [MediaKind: [LibraryNamedBooksGroup]] = [:],
        tags: [MediaKind: [LibraryNamedBooksGroup]] = [:],
        ratings: [MediaKind: [LibraryNamedBooksGroup]] = [:],
        statuses: [MediaKind: [LibraryNamedBooksGroup]] = [:],
        sources: [MediaKind: [LibraryNamedBooksGroup]] = [:],
    ) {
        self.generation = generation
        self.series = series
        self.authors = authors
        self.collections = collections
        self.narrators = narrators
        self.translators = translators
        self.publicationYears = publicationYears
        self.tags = tags
        self.ratings = ratings
        self.statuses = statuses
        self.sources = sources
    }
}

public struct LibrarySeriesGroup: Sendable {
    public var series: BookSeries?
    public var books: [BookMetadata]
}

public struct LibraryCreatorGroup: Sendable {
    public var creator: BookCreator?
    public var books: [BookMetadata]
}

public struct LibraryCollectionGroup: Sendable {
    public var collection: BookCollectionSummary?
    public var books: [BookMetadata]
}

public struct LibraryNamedBooksGroup: Sendable {
    public var name: String
    public var books: [BookMetadata]
}

public struct LibraryDerivationInput: Sendable {
    public var generation: Int
    public var deriveGroups: Bool
    public var metadata: [BookMetadata]
    public var paths: [String: MediaPaths]
    public var localStandaloneBookIds: Set<String>
    public var storytellerBookIds: Set<String>
    public var progress: [String: BookProgress]
    public var smartShelves: [SmartShelf]
    public var sidebarContents: [SidebarContentKind]

    public init(
        generation: Int,
        deriveGroups: Bool = false,
        metadata: [BookMetadata],
        paths: [String: MediaPaths],
        localStandaloneBookIds: Set<String>,
        storytellerBookIds: Set<String>,
        progress: [String: BookProgress],
        smartShelves: [SmartShelf],
        sidebarContents: [SidebarContentKind],
    ) {
        self.generation = generation
        self.deriveGroups = deriveGroups
        self.metadata = metadata
        self.paths = paths
        self.localStandaloneBookIds = localStandaloneBookIds
        self.storytellerBookIds = storytellerBookIds
        self.progress = progress
        self.smartShelves = smartShelves
        self.sidebarContents = sidebarContents
    }
}

public actor LibraryDerivationActor {
    public init() {}

    public func deriveSnapshot(from input: LibraryDerivationInput) -> LibraryViewSnapshot {
        let started = CFAbsoluteTimeGetCurrent()
        var badgeCounts: [String: Int] = [:]
        var context = Context(input: input)

        for content in input.sidebarContents {
            badgeCounts[content.stableIdentifier] = context.badgeCount(for: content)
        }

        var groups = LibraryGroupSnapshot()
        if input.deriveGroups {
            groups = LibraryGroupSnapshot(generation: input.generation)
            for kind in MediaKind.allCases {
                groups.series[kind] = context.seriesGroups(kind)
                groups.authors[kind] = context.authorGroups(kind)
                groups.collections[kind] = context.collectionGroups(kind)
                groups.narrators[kind] = context.narratorGroups(kind)
                groups.translators[kind] = context.translatorGroups(kind)
                groups.publicationYears[kind] = context.publicationYearGroups(kind)
                groups.tags[kind] = context.tagGroups(kind)
                groups.ratings[kind] = context.ratingGroups(kind)
                groups.statuses[kind] = context.statusGroups(kind)
                groups.sources[kind] = context.sourceGroups(kind)
            }
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1_000
        debugLog(
            "[PerfTrace][LibraryDerivationActor] deriveSnapshot generation=\(input.generation) contents=\(input.sidebarContents.count) badges=\(badgeCounts.count) elapsedMs=\(String(format: "%.1f", elapsed))"
        )
        return LibraryViewSnapshot(
            generation: input.generation,
            badgeCounts: badgeCounts,
            groups: groups,
        )
    }

    private struct Context {
        let input: LibraryDerivationInput
        var seriesCountCache: [MediaKind: Int] = [:]
        var authorCountCache: [MediaKind: Int] = [:]
        var collectionCountCache: [MediaKind: Int] = [:]
        var narratorCountCache: [MediaKind: Int] = [:]
        var translatorCountCache: [MediaKind: Int] = [:]
        var publicationYearCountCache: [MediaKind: Int] = [:]
        var tagCountCache: [MediaKind: Int] = [:]
        var ratingCountCache: [MediaKind: Int] = [:]
        var statusCountCache: [MediaKind: Int] = [:]
        var sourceCountCache: [MediaKind: Int] = [:]

        mutating func badgeCount(for content: SidebarContentKind) -> Int {
            switch content {
                case .home, .placeholder, .currentlyDownloading, .importLocalFile,
                    .storytellerServer:
                    return 0
                case .mediaGrid(let config):
                    return mediaGridCount(config)
                case .seriesView(let mediaKind):
                    if let count = seriesCountCache[mediaKind] { return count }
                    let count = seriesGroupCount(mediaKind)
                    seriesCountCache[mediaKind] = count
                    return count
                case .authorView(let mediaKind):
                    if let count = authorCountCache[mediaKind] { return count }
                    let count = authorGroupCount(mediaKind)
                    authorCountCache[mediaKind] = count
                    return count
                case .narratorView(let mediaKind):
                    if let count = narratorCountCache[mediaKind] { return count }
                    let count = narratorGroupCount(mediaKind)
                    narratorCountCache[mediaKind] = count
                    return count
                case .translatorView(let mediaKind):
                    if let count = translatorCountCache[mediaKind] { return count }
                    let count = translatorGroupCount(mediaKind)
                    translatorCountCache[mediaKind] = count
                    return count
                case .tagView(let mediaKind):
                    if let count = tagCountCache[mediaKind] { return count }
                    let count = tagGroupCount(mediaKind)
                    tagCountCache[mediaKind] = count
                    return count
                case .publicationYearView(let mediaKind):
                    if let count = publicationYearCountCache[mediaKind] { return count }
                    let count = publicationYearGroupCount(mediaKind)
                    publicationYearCountCache[mediaKind] = count
                    return count
                case .ratingView(let mediaKind):
                    if let count = ratingCountCache[mediaKind] { return count }
                    let count = ratingGroupCount(mediaKind)
                    ratingCountCache[mediaKind] = count
                    return count
                case .collectionsView(let mediaKind):
                    if let count = collectionCountCache[mediaKind] { return count }
                    let count = collectionGroupCount(mediaKind)
                    collectionCountCache[mediaKind] = count
                    return count
                case .statusView(let mediaKind):
                    if let count = statusCountCache[mediaKind] { return count }
                    let count = statusGroupCount(mediaKind)
                    statusCountCache[mediaKind] = count
                    return count
                case .sourceView(let mediaKind):
                    if let count = sourceCountCache[mediaKind] { return count }
                    let count = sourceGroupCount(mediaKind)
                    sourceCountCache[mediaKind] = count
                    return count
                case .smartShelves:
                    return input.smartShelves.count
                case .smartShelfDetail(let shelfId):
                    guard let shelf = input.smartShelves.first(where: { $0.id == shelfId }) else {
                        return 0
                    }
                    return input.metadata.filter { book in
                        let progress = input.progress[book.id]?.progressFraction ?? book.progress
                        let isLocal = input.localStandaloneBookIds.contains(book.id)
                        let isDownloaded = hasDownloadedContent(book) && !isLocal
                        return shelf.matchesAll(
                            book,
                            progress: progress,
                            locationInfo: ShelfLocationInfo(
                                isDownloaded: isDownloaded,
                                isLocalStandalone: isLocal,
                            ),
                        )
                    }.count
                case .downloaded:
                    return input.metadata.filter {
                        metadataMatchesKind($0, kind: .ebook)
                            && matchesLocationFilter($0, .downloaded)
                    }.count
            }
        }

        private func mediaGridCount(_ config: MediaGridConfiguration) -> Int {
            var base = items(
                for: config.mediaKind,
                narrationFilter: .both,
                tagFilter: config.tagFilter,
            )

            if shouldIncludeAudiobookOnlyItems(for: config.narrationFilter) {
                let audioOnlyItems = items(
                    for: .audiobook,
                    narrationFilter: .both,
                    tagFilter: config.tagFilter,
                )
                base = mergeItems(base, with: audioOnlyItems)
            }

            base = base.filter { matchesNarrationFilter($0, config.narrationFilter) }

            if let series = config.seriesFilter {
                base = base.filter { $0.matchesSeries(series) }
            }
            if let collection = config.collectionFilter {
                base = base.filter { $0.matchesCollection(collection) }
            }
            if let author = config.authorFilter {
                base = base.filter { $0.matchesAuthor(author) }
            }
            if let narrator = config.narratorFilter {
                base = base.filter { $0.matchesNarrator(narrator) }
            }
            if let translator = config.translatorFilter {
                base = base.filter { $0.matchesTranslator(translator) }
            }
            if let year = config.publicationYearFilter {
                base = base.filter { $0.matchesPublicationYear(year) }
            }
            if let ratingKey = config.ratingFilter {
                base = base.filter { $0.matchesRating(ratingKey) }
            }
            if let statusFilter = config.statusFilter {
                base = base.filter { $0.matchesStatus(statusFilter) }
            }

            base = base.filter { matchesLocationFilter($0, config.locationFilter) }
            return base.count
        }

        private func items(
            for kind: MediaKind,
            narrationFilter: NarrationFilter,
            tagFilter: String?,
        ) -> [BookMetadata] {
            var base = input.metadata.filter { metadataMatchesKind($0, kind: kind) }
            switch narrationFilter {
                case .both:
                    break
                case .withAudio:
                    base = base.filter(\.hasAnyAudiobookAsset)
                case .withoutAudio:
                    base = base.filter { !$0.hasAnyAudiobookAsset }
            }
            if let tagFilter, !tagFilter.isEmpty {
                let target = tagFilter.lowercased()
                base = base.filter { item in
                    item.tagNames.contains(where: { $0.lowercased() == target })
                }
            }
            return base
        }

        private func metadataMatchesKind(_ metadata: BookMetadata, kind: MediaKind) -> Bool {
            switch kind {
                case .ebook:
                    return metadata.hasAvailableEbook || metadata.hasAvailableReadaloud
                case .audiobook:
                    return !metadata.hasAvailableEbook && !metadata.hasAvailableReadaloud
                        && metadata.hasAvailableAudiobook
            }
        }

        private func shouldIncludeAudiobookOnlyItems(for filter: NarrationFilter) -> Bool {
            switch filter {
                case .both, .withAudio:
                    return true
                case .withoutAudio:
                    return false
            }
        }

        private func matchesNarrationFilter(_ item: BookMetadata, _ filter: NarrationFilter)
            -> Bool
        {
            switch filter {
                case .both:
                    return true
                case .withAudio:
                    return item.hasAvailableAudiobook || item.hasAvailableReadaloud
                case .withoutAudio:
                    return item.isEbookOnly
            }
        }

        private func matchesLocationFilter(_ item: BookMetadata, _ filter: LocationFilter) -> Bool {
            switch filter {
                case .all:
                    return true
                case .downloaded:
                    return hasDownloadedContent(item)
                        && !input.localStandaloneBookIds.contains(item.id)
                case .serverOnly:
                    return !hasDownloadedContent(item)
                        && !input.localStandaloneBookIds.contains(item.id)
                case .localFiles:
                    return input.localStandaloneBookIds.contains(item.id)
            }
        }

        private func hasDownloadedContent(_ item: BookMetadata) -> Bool {
            guard let paths = input.paths[item.id] else { return false }
            return paths.ebookPath != nil || paths.audioPath != nil || paths.syncedPath != nil
        }

        private func mergeItems(_ primary: [BookMetadata], with supplemental: [BookMetadata])
            -> [BookMetadata]
        {
            guard !supplemental.isEmpty else { return primary }
            var result = primary
            var seen = Set(result.map(\.id))
            for item in supplemental where !seen.contains(item.id) {
                seen.insert(item.id)
                result.append(item)
            }
            return result
        }

        private func seriesGroupCount(_ kind: MediaKind) -> Int {
            var keys = Set<String>()
            for book in input.metadata where metadataMatchesKind(book, kind: kind) {
                if let seriesList = book.series, !seriesList.isEmpty {
                    for series in seriesList {
                        keys.insert(normalizedCategoryKey(series.name))
                    }
                } else {
                    keys.insert("__no_series__")
                }
            }
            return keys.count
        }

        private func authorGroupCount(_ kind: MediaKind) -> Int {
            var keys = Set<String>()
            for book in input.metadata where metadataMatchesKind(book, kind: kind) {
                if let authors = book.authors, !authors.isEmpty {
                    for author in authors {
                        keys.insert(creatorGroupingKey(author, unknownKey: "__unknown__"))
                    }
                } else {
                    keys.insert("__no_author__")
                }
            }
            return keys.count
        }

        private func collectionGroupCount(_ kind: MediaKind) -> Int {
            var keys = Set<String>()
            for book in input.metadata where metadataMatchesKind(book, kind: kind) {
                if let collections = book.collections {
                    for collection in collections {
                        keys.insert(normalizedCategoryKey(collection.name))
                    }
                }
            }
            return keys.count
        }

        private func narratorGroupCount(_ kind: MediaKind) -> Int {
            var keys = Set<String>()
            for book in input.metadata where metadataMatchesKind(book, kind: kind) {
                if let narrators = book.narrators, !narrators.isEmpty {
                    for narrator in narrators {
                        keys.insert(creatorGroupingKey(narrator, unknownKey: "__unknown__"))
                    }
                } else {
                    keys.insert("__no_narrator__")
                }
            }
            return keys.count
        }

        private func translatorGroupCount(_ kind: MediaKind) -> Int {
            var keys = Set<String>()
            for book in input.metadata where metadataMatchesKind(book, kind: kind) {
                let translators = (book.creators ?? []).filter { $0.role == "trl" }
                if translators.isEmpty {
                    keys.insert("__no_translator__")
                } else {
                    for translator in translators {
                        keys.insert(creatorGroupingKey(translator, unknownKey: "__unknown__"))
                    }
                }
            }
            return keys.count
        }

        private func publicationYearGroupCount(_ kind: MediaKind) -> Int {
            Set(
                input.metadata
                    .filter { metadataMatchesKind($0, kind: kind) }
                    .map { BookMetadata.publicationYear(from: $0.publicationDate) ?? "Unknown" }
            ).count
        }

        private func tagGroupCount(_ kind: MediaKind) -> Int {
            var keys = Set<String>()
            for book in input.metadata where metadataMatchesKind(book, kind: kind) {
                for tagName in book.tagNames {
                    keys.insert(tagName.lowercased())
                }
            }
            return keys.count
        }

        private func ratingGroupCount(_ kind: MediaKind) -> Int {
            Set(
                input.metadata
                    .filter { metadataMatchesKind($0, kind: kind) }
                    .map { book -> String in
                        if let rating = book.rating, rating > 0 {
                            return "\(Int(rating.rounded()))"
                        }
                        return "Unrated"
                    }
            ).count
        }

        private func statusGroupCount(_ kind: MediaKind) -> Int {
            Set(
                input.metadata
                    .filter { metadataMatchesKind($0, kind: kind) }
                    .map { $0.status?.name ?? "Unknown" }
            ).count
        }

        private func sourceGroupCount(_ kind: MediaKind) -> Int {
            Set(
                input.metadata
                    .filter { metadataMatchesKind($0, kind: kind) }
                    .map { book -> String in
                        if input.localStandaloneBookIds.contains(book.id) {
                            return "Local Files"
                        }
                        if input.storytellerBookIds.contains(book.id) {
                            return "Storyteller"
                        }
                        return "Unknown"
                    }
            ).count
        }

        private func books(matching kind: MediaKind) -> [BookMetadata] {
            input.metadata
        }

        private func creatorGroupingKey(_ creator: BookCreator, unknownKey: String) -> String {
            let name = (creator.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return normalizedCategoryKey(name)
            }
            return creator.uuid ?? unknownKey
        }

        private func normalizedCategoryKey(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }

        mutating func seriesGroups(_ kind: MediaKind) -> [LibrarySeriesGroup] {
            var seriesMap: [String: LibrarySeriesGroup] = [:]
            for book in books(matching: kind) {
                if let seriesList = book.series, !seriesList.isEmpty {
                    for series in seriesList {
                        let key = normalizedCategoryKey(series.name)
                        var group =
                            seriesMap[key]
                            ?? LibrarySeriesGroup(series: series, books: [])
                        if group.series?.uuid == nil, series.uuid != nil {
                            group.series = series
                        }
                        if !group.books.contains(where: { $0.id == book.id }) {
                            group.books.append(book)
                        }
                        seriesMap[key] = group
                    }
                } else {
                    seriesMap[
                        "__no_series__",
                        default: LibrarySeriesGroup(series: nil, books: []),
                    ]
                    .books
                    .append(book)
                }
            }

            for key in seriesMap.keys {
                let seriesName = seriesMap[key]?.series?.name.lowercased()
                seriesMap[key]?.books.sort { a, b in
                    let posA =
                        a.series?.first { $0.name.lowercased() == seriesName }?.position
                        ?? .greatestFiniteMagnitude
                    let posB =
                        b.series?.first { $0.name.lowercased() == seriesName }?.position
                        ?? .greatestFiniteMagnitude
                    if posA == posB {
                        return a.title.articleStrippedCompare(b.title) == .orderedAscending
                    }
                    return posA < posB
                }
            }

            return seriesMap.values.sorted { a, b in
                guard let seriesA = a.series, let seriesB = b.series else {
                    return a.series != nil
                }
                return seriesA.name.articleStrippedCompare(seriesB.name) == .orderedAscending
            }
        }

        mutating func authorGroups(_ kind: MediaKind) -> [LibraryCreatorGroup] {
            creatorGroups(
                kind,
                emptyKey: "__no_author__",
                creators: { $0.authors ?? [] },
                sort: { a, b in
                    guard let creatorA = a.creator, let creatorB = b.creator else {
                        return a.creator != nil
                    }
                    let nameA = creatorA.name ?? ""
                    let nameB = creatorB.name ?? ""
                    return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
                },
            )
        }

        mutating func narratorGroups(_ kind: MediaKind) -> [LibraryCreatorGroup] {
            creatorGroups(
                kind,
                emptyKey: "__no_narrator__",
                creators: { $0.narrators ?? [] },
                sort: { a, b in
                    guard let creatorA = a.creator, let creatorB = b.creator else {
                        return a.creator != nil
                    }
                    let nameA = creatorA.name ?? ""
                    let nameB = creatorB.name ?? ""
                    return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
                },
            )
        }

        mutating func translatorGroups(_ kind: MediaKind) -> [LibraryCreatorGroup] {
            creatorGroups(
                kind,
                emptyKey: "__no_translator__",
                creators: { ($0.creators ?? []).filter { $0.role == "trl" } },
                sort: { a, b in
                    guard let creatorA = a.creator, let creatorB = b.creator else {
                        return a.creator != nil
                    }
                    let nameA = creatorA.name ?? ""
                    let nameB = creatorB.name ?? ""
                    return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
                },
            )
        }

        private func creatorGroups(
            _ kind: MediaKind,
            emptyKey: String,
            creators: (BookMetadata) -> [BookCreator],
            sort: (LibraryCreatorGroup, LibraryCreatorGroup) -> Bool,
        ) -> [LibraryCreatorGroup] {
            var creatorMap: [String: LibraryCreatorGroup] = [:]
            for book in books(matching: kind) {
                let creatorList = creators(book)
                if creatorList.isEmpty {
                    creatorMap[
                        emptyKey,
                        default: LibraryCreatorGroup(creator: nil, books: []),
                    ]
                    .books
                    .append(book)
                } else {
                    for creator in creatorList {
                        let key = creatorGroupingKey(creator, unknownKey: "__unknown__")
                        var group =
                            creatorMap[key]
                            ?? LibraryCreatorGroup(creator: creator, books: [])
                        if group.creator?.uuid == nil, creator.uuid != nil {
                            group.creator = creator
                        }
                        if !group.books.contains(where: { $0.id == book.id }) {
                            group.books.append(book)
                        }
                        creatorMap[key] = group
                    }
                }
            }

            for key in creatorMap.keys {
                creatorMap[key]?.books.sort {
                    $0.title.articleStrippedCompare($1.title) == .orderedAscending
                }
            }

            return creatorMap.values.sorted(by: sort)
        }

        mutating func collectionGroups(_ kind: MediaKind) -> [LibraryCollectionGroup] {
            var collectionMap: [String: LibraryCollectionGroup] = [:]
            for book in books(matching: kind) {
                guard let collections = book.collections else { continue }
                for collection in collections {
                    let key = normalizedCategoryKey(collection.name)
                    var group =
                        collectionMap[key]
                        ?? LibraryCollectionGroup(collection: collection, books: [])
                    if group.collection?.uuid == nil, collection.uuid != nil {
                        group.collection = collection
                    }
                    if !group.books.contains(where: { $0.id == book.id }) {
                        group.books.append(book)
                    }
                    collectionMap[key] = group
                }
            }

            for key in collectionMap.keys {
                collectionMap[key]?.books.sort {
                    $0.title.articleStrippedCompare($1.title) == .orderedAscending
                }
            }

            return collectionMap.values.sorted { a, b in
                guard let collectionA = a.collection, let collectionB = b.collection else {
                    return a.collection != nil
                }
                return collectionA.name.articleStrippedCompare(collectionB.name)
                    == .orderedAscending
            }
        }

        mutating func publicationYearGroups(_ kind: MediaKind) -> [LibraryNamedBooksGroup] {
            namedGroups(kind) {
                BookMetadata.publicationYear(from: $0.publicationDate) ?? "Unknown"
            }
            .sorted {
                if $0.name == "Unknown" { return false }
                if $1.name == "Unknown" { return true }
                return $0.name > $1.name
            }
        }

        mutating func tagGroups(_ kind: MediaKind) -> [LibraryNamedBooksGroup] {
            var tagMap: [String: LibraryNamedBooksGroup] = [:]
            for book in books(matching: kind) {
                for tagName in book.tagNames {
                    let key = normalizedCategoryKey(tagName)
                    var group =
                        tagMap[key]
                        ?? LibraryNamedBooksGroup(name: tagName, books: [])
                    if !group.books.contains(where: { $0.id == book.id }) {
                        group.books.append(book)
                    }
                    tagMap[key] = group
                }
            }
            return sortedNamedGroups(Array(tagMap.values))
        }

        mutating func ratingGroups(_ kind: MediaKind) -> [LibraryNamedBooksGroup] {
            namedGroups(kind) { book in
                if let rating = book.rating, rating > 0 {
                    return "\(Int(rating.rounded()))"
                }
                return "Unrated"
            }
            .sorted {
                if $0.name == "Unrated" { return false }
                if $1.name == "Unrated" { return true }
                return (Int($0.name) ?? 0) > (Int($1.name) ?? 0)
            }
        }

        mutating func statusGroups(_ kind: MediaKind) -> [LibraryNamedBooksGroup] {
            let statusOrder = ["Reading", "To read", "Read", "Unknown"]
            return namedGroups(kind) { $0.status?.name ?? "Unknown" }
                .sorted { a, b in
                    let indexA = statusOrder.firstIndex(of: a.name) ?? statusOrder.count
                    let indexB = statusOrder.firstIndex(of: b.name) ?? statusOrder.count
                    if indexA != indexB { return indexA < indexB }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
        }

        mutating func sourceGroups(_ kind: MediaKind) -> [LibraryNamedBooksGroup] {
            let sourceOrder = ["Storyteller", "Local Files", "Unknown"]
            return namedGroups(kind) { book in
                if input.localStandaloneBookIds.contains(book.id) {
                    return "Local Files"
                }
                if input.storytellerBookIds.contains(book.id) {
                    return "Storyteller"
                }
                return "Unknown"
            }
            .sorted { a, b in
                let indexA = sourceOrder.firstIndex(of: a.name) ?? sourceOrder.count
                let indexB = sourceOrder.firstIndex(of: b.name) ?? sourceOrder.count
                if indexA != indexB { return indexA < indexB }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }

        private func namedGroups(
            _ kind: MediaKind,
            nameForBook: (BookMetadata) -> String,
        ) -> [LibraryNamedBooksGroup] {
            var map: [String: LibraryNamedBooksGroup] = [:]
            for book in books(matching: kind) {
                let name = nameForBook(book)
                map[name, default: LibraryNamedBooksGroup(name: name, books: [])].books.append(book)
            }
            return sortedNamedGroups(Array(map.values))
        }

        private func sortedNamedGroups(_ groups: [LibraryNamedBooksGroup])
            -> [LibraryNamedBooksGroup]
        {
            groups.map { group in
                var mutableGroup = group
                mutableGroup.books.sort {
                    $0.title.articleStrippedCompare($1.title) == .orderedAscending
                }
                return mutableGroup
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }
}
