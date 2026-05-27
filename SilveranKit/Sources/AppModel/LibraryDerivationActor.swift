import Foundation
import SilveranKitCommon

public struct LibraryViewSnapshot: Sendable {
    public var generation: Int
    public var badgeCounts: [String: Int]

    public init(generation: Int = 0, badgeCounts: [String: Int] = [:]) {
        self.generation = generation
        self.badgeCounts = badgeCounts
    }
}

public struct LibraryDerivationInput: Sendable {
    public var generation: Int
    public var metadata: [BookMetadata]
    public var paths: [String: MediaPaths]
    public var localStandaloneBookIds: Set<String>
    public var storytellerBookIds: Set<String>
    public var progress: [String: BookProgress]
    public var smartShelves: [SmartShelf]
    public var sidebarContents: [SidebarContentKind]

    public init(
        generation: Int,
        metadata: [BookMetadata],
        paths: [String: MediaPaths],
        localStandaloneBookIds: Set<String>,
        storytellerBookIds: Set<String>,
        progress: [String: BookProgress],
        smartShelves: [SmartShelf],
        sidebarContents: [SidebarContentKind],
    ) {
        self.generation = generation
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

        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1_000
        debugLog(
            "[PerfTrace][LibraryDerivationActor] deriveSnapshot generation=\(input.generation) contents=\(input.sidebarContents.count) badges=\(badgeCounts.count) elapsedMs=\(String(format: "%.1f", elapsed))"
        )
        return LibraryViewSnapshot(generation: input.generation, badgeCounts: badgeCounts)
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
                        keys.insert(series.uuid ?? series.name)
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
                        keys.insert(author.uuid ?? author.name ?? "__unknown__")
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
                        keys.insert(collection.uuid ?? collection.name)
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
                        keys.insert(narrator.uuid ?? narrator.name ?? "__unknown__")
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
                        keys.insert(translator.uuid ?? translator.name ?? "__unknown__")
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
    }
}
