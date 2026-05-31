import Foundation
import ZIPFoundation

public struct MediaPaths: Sendable {
    public var ebookPath: URL?
    public var audioPath: URL?
    public var syncedPath: URL?

    public init(ebookPath: URL? = nil, audioPath: URL? = nil, syncedPath: URL? = nil) {
        self.ebookPath = ebookPath
        self.audioPath = audioPath
        self.syncedPath = syncedPath
    }
}

public enum LocalMediaImportEvent: Sendable {
    case started(book: BookMetadata, category: LocalMediaCategory, expectedBytes: Int64?)
    case progress(
        book: BookMetadata,
        category: LocalMediaCategory,
        receivedBytes: Int64,
        expectedBytes: Int64?,
    )
    case finished(book: BookMetadata, category: LocalMediaCategory, destination: URL)
    case skipped(book: BookMetadata, category: LocalMediaCategory)
}

@globalActor
public actor LocalMediaActor: GlobalActor {
    public static let shared = LocalMediaActor()
    private(set) public var localStorytellerMetadata: [BookMetadata] = []
    private(set) public var localStorytellerBookPaths: [String: MediaPaths] = [:]
    private let filesystem: FilesystemActor
    private let localLibrary: LocalLibraryManager
    private var periodicScanTask: Task<Void, Never>?

    private static let extensionCategoryMap: [String: LocalMediaCategory] = [
        "epub": .ebook,
        "m4b": .audio,
    ]

    public static var allowedExtensions: [String] {
        Array(extensionCategoryMap.keys).sorted()
    }

    private var observers: [UUID: @Sendable @MainActor () -> Void] = [:]

    public init(
        filesystem: FilesystemActor = .shared,
        localLibrary: LocalLibraryManager = LocalLibraryManager(),
    ) {
        self.filesystem = filesystem
        self.localLibrary = localLibrary
        Task { [weak self] in
            try? await filesystem.ensureLocalStorageDirectories()
            try? await self?.scanForMedia()
            await self?.startPeriodicScan()
        }
    }

    private func startPeriodicScan() {
        periodicScanTask?.cancel()
        periodicScanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled else { break }
                try? await self?.scanForMedia()
            }
        }
    }

    @discardableResult
    public func addObserver(_ callback: @escaping @Sendable @MainActor () -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        debugLog("[LMA] addObserver: id=\(id), total observers=\(observers.count)")
        return id
    }

    public func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
        debugLog("[LMA] removeObserver: id=\(id), total observers=\(observers.count)")
    }

    private func notifyObservers() async {
        debugLog("[LMA] notifyObservers: notifying \(observers.count) observers")
        for (_, callback) in observers {
            await callback()
        }
    }

    private func metadata(
        _ metadata: [BookMetadata],
        stampedWith sourceID: BookSourceID,
    ) -> [BookMetadata] {
        metadata.map { book in
            var stamped = book
            stamped.sourceID = stamped.sourceID ?? sourceID
            return stamped
        }
    }

    private func migratedSourceID(
        for kind: BookSourceKind
    ) async -> BookSourceID? {
        guard let sources = try? await filesystem.loadOrCreateBookSources(),
            let source = sources.first(where: { $0.kind == kind })
        else {
            return nil
        }
        return source.id
    }

    public func updateStorytellerMetadata(
        _ metadata: [BookMetadata],
        replacingSourceID sourceID: BookSourceID? = nil,
    ) async throws {
        let targetSourceID: BookSourceID?
        if let sourceID {
            targetSourceID = sourceID
        } else {
            targetSourceID = await migratedSourceID(for: .storyteller)
        }
        guard let targetSourceID else { return }
        let stampedMetadata = self.metadata(
            metadata,
            stampedWith: targetSourceID,
        )
        _ = try await filesystem.loadOrCreateBookSources()
        let nextMetadata: [BookMetadata]
        if let sourceID {
            let preserved = localStorytellerMetadata.filter {
                $0.sourceID != sourceID
            }
            nextMetadata = preserved + stampedMetadata
        } else {
            nextMetadata = stampedMetadata
        }
        localStorytellerMetadata = nextMetadata
        let grouped = Dictionary(grouping: nextMetadata) { book in
            book.sourceID ?? targetSourceID
        }
        for (groupSourceID, groupMetadata) in grouped {
            try await filesystem.saveStorytellerLibraryMetadata(
                groupMetadata,
                sourceID: groupSourceID,
            )
        }

        var paths: [String: MediaPaths] = [:]
        for book in nextMetadata {
            let mediaPaths = await scanBookPaths(
                for: book.uuid,
                domain: .storyteller,
                sourceID: book.sourceID ?? targetSourceID,
            )
            paths[book.uuid] = mediaPaths
        }
        localStorytellerBookPaths = paths

        let positions = Dictionary(
            uniqueKeysWithValues: nextMetadata.compactMap { book -> (String, BookReadingPosition)? in
                guard let pos = book.position else { return nil }
                return (book.uuid, pos)
            }
        )
        await ProgressSyncActor.shared.updateServerPositions(positions)

        await notifyObservers()
    }

    public func updateBookProgress(bookId: String, locator: BookLocator, timestamp: Double) async {
        debugLog("[LocalMediaActor] updateBookProgress: bookId=\(bookId), timestamp=\(timestamp)")

        let updatedAtString = Date(timeIntervalSince1970: timestamp / 1000).ISO8601Format()

        if let index = localStorytellerMetadata.firstIndex(where: { $0.uuid == bookId }) {
            let existing = localStorytellerMetadata[index]
            let existingTimestamp = existing.position?.timestamp ?? 0

            if timestamp <= existingTimestamp {
                debugLog(
                    "[LocalMediaActor] updateBookProgress: skipping storyteller update, existing is newer (incoming: \(timestamp), existing: \(existingTimestamp))"
                )
            } else {
                let newPosition = BookReadingPosition(
                    uuid: existing.position?.uuid,
                    locator: locator,
                    timestamp: timestamp,
                    createdAt: existing.position?.createdAt,
                    updatedAt: updatedAtString,
                )
                var updatedMetadata = BookMetadata(
                    uuid: existing.uuid,
                    title: existing.title,
                    subtitle: existing.subtitle,
                    description: existing.description,
                    language: existing.language,
                    createdAt: existing.createdAt,
                    updatedAt: existing.updatedAt,
                    publicationDate: existing.publicationDate,
                    authors: existing.authors,
                    narrators: existing.narrators,
                    creators: existing.creators,
                    series: existing.series,
                    tags: existing.tags,
                    collections: existing.collections,
                    ebook: existing.ebook,
                    audiobook: existing.audiobook,
                    readaloud: existing.readaloud,
                    status: existing.status,
                    position: newPosition,
                    rating: existing.rating,
                )
                updatedMetadata.sourceID =
                    existing.sourceID
                updatedMetadata.source = existing.source
                localStorytellerMetadata[index] = updatedMetadata
                debugLog("[LocalMediaActor] updateBookProgress: updated storyteller metadata")
            }
        }

        // Folder sources persist progress through FolderSourceActor. LocalMediaActor only tracks
        // client-owned cache state.
    }

    public func updateBookStatus(bookId: String, status: BookStatus) async {
        guard let index = localStorytellerMetadata.firstIndex(where: { $0.uuid == bookId }) else {
            return
        }
        let existing = localStorytellerMetadata[index]
        var updatedMetadata = BookMetadata(
            uuid: existing.uuid,
            title: existing.title,
            subtitle: existing.subtitle,
            description: existing.description,
            language: existing.language,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
            publicationDate: existing.publicationDate,
            authors: existing.authors,
            narrators: existing.narrators,
            creators: existing.creators,
            series: existing.series,
            tags: existing.tags,
            collections: existing.collections,
            ebook: existing.ebook,
            audiobook: existing.audiobook,
            readaloud: existing.readaloud,
            status: status,
            position: existing.position,
            rating: existing.rating,
        )
        updatedMetadata.sourceID = existing.sourceID
        updatedMetadata.source = existing.source
        localStorytellerMetadata[index] = updatedMetadata
        await notifyObservers()
    }

    public func scanForMedia() async throws {
        try await filesystem.ensureLocalStorageDirectories()
        let bookSources = try await filesystem.loadOrCreateBookSources()

        var storytellerMetadata: [BookMetadata] = []
        let storytellerSourceIDs = bookSources.filter { $0.kind == .storyteller }.map(\.id)
        for (index, sourceID) in storytellerSourceIDs.enumerated() {
            let loadedMetadata: [BookMetadata]?
            if let loaded = try await filesystem.loadStorytellerLibraryMetadata(sourceID: sourceID) {
                loadedMetadata = loaded
            } else if index == 0,
                let legacy = try await filesystem.loadLegacyStorytellerLibraryMetadata()
            {
                loadedMetadata = legacy
            } else {
                loadedMetadata = nil
            }

            guard let loadedMetadata else { continue }
            let stampedMetadata = metadata(loadedMetadata, stampedWith: sourceID)
            storytellerMetadata.append(contentsOf: stampedMetadata)
            if stampedMetadata != loadedMetadata {
                try await filesystem.saveStorytellerLibraryMetadata(
                    stampedMetadata,
                    sourceID: sourceID,
                )
            }
        }

        localStorytellerMetadata = storytellerMetadata

        var storytellerPaths: [String: MediaPaths] = [:]
        for book in localStorytellerMetadata {
            guard let sourceID = book.sourceID else { continue }
            let mediaPaths = await scanBookPaths(
                for: book.uuid,
                domain: .storyteller,
                sourceID: sourceID,
            )
            storytellerPaths[book.uuid] = mediaPaths
        }
        localStorytellerBookPaths = storytellerPaths

        var allPositions: [String: BookReadingPosition] = [:]
        for book in storytellerMetadata {
            if let pos = book.position {
                allPositions[book.uuid] = pos
            }
        }
        await ProgressSyncActor.shared.updateServerPositions(allPositions)

        await notifyObservers()
    }

    private func scanBookPaths(
        for uuid: String,
        domain: LocalMediaDomain,
        sourceID: BookSourceID? = nil,
    ) async -> MediaPaths {
        var paths = MediaPaths()
        let fm = FileManager.default

        for category in LocalMediaCategory.allCases {
            guard
                let categoryDir = await filesystem.mediaDirectory(
                    for: uuid,
                    category: category,
                    in: domain,
                    sourceID: sourceID,
                )
            else {
                continue
            }

            guard
                let contents = try? fm.contentsOfDirectory(
                    at: categoryDir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles],
                )
            else {
                continue
            }

            switch category {
                case .ebook:
                    paths.ebookPath = firstMediaFile(in: contents, matchingExtensions: ["epub"])
                case .audio:
                    paths.audioPath = audioManifestFile(in: categoryDir)
                case .synced:
                    paths.syncedPath = firstMediaFile(in: contents, matchingExtensions: ["epub"])
            }
        }

        return paths
    }

    public func listAvailableUuids() async -> Set<String> {
        do {
            try await filesystem.ensureLocalStorageDirectories()
            guard let storytellerSourceID = await migratedSourceID(for: .storyteller) else {
                return Set(localStorytellerMetadata.map(\.uuid))
            }
            if let metadata = try await filesystem.loadStorytellerLibraryMetadata(
                sourceID: storytellerSourceID,
            ) {
                let stampedMetadata = self.metadata(
                    metadata,
                    stampedWith: storytellerSourceID,
                )
                localStorytellerMetadata = stampedMetadata
                return Set(stampedMetadata.map(\.uuid))
            } else if let metadata = try await filesystem.loadLegacyStorytellerLibraryMetadata() {
                let stampedMetadata = self.metadata(metadata, stampedWith: storytellerSourceID)
                localStorytellerMetadata = stampedMetadata
                return Set(stampedMetadata.map(\.uuid))
            } else {
                return Set(localStorytellerMetadata.map(\.uuid))
            }
        } catch {
            debugLog("[LocalMediaActor] listAvailableUuids failed: \(error)")
            return Set(localStorytellerMetadata.map(\.uuid))
        }
    }

    public func downloadedCategories(
        for uuid: String,
        sourceID explicitSourceID: BookSourceID? = nil,
    ) async -> Set<LocalMediaCategory> {
        guard let sourceID = await cacheSourceID(for: uuid, explicitSourceID: explicitSourceID)
        else { return [] }
        return await filesystem.downloadedCategories(
            for: uuid,
            in: .storyteller,
            sourceID: sourceID,
        )
    }

    public func cachedMediaPaths(for metadata: [BookMetadata]) async -> [String: MediaPaths] {
        var paths = localStorytellerBookPaths
        for book in metadata {
            guard let sourceID = book.sourceID else { continue }
            var mediaPaths = paths[book.uuid] ?? MediaPaths()
            if mediaPaths.ebookPath == nil {
                mediaPaths.ebookPath = await mediaFilePath(
                    for: book.uuid,
                    category: .ebook,
                    sourceID: sourceID,
                )
            }
            if mediaPaths.audioPath == nil {
                mediaPaths.audioPath = await mediaFilePath(
                    for: book.uuid,
                    category: .audio,
                    sourceID: sourceID,
                )
            }
            if mediaPaths.syncedPath == nil {
                mediaPaths.syncedPath = await mediaFilePath(
                    for: book.uuid,
                    category: .synced,
                    sourceID: sourceID,
                )
            }
            if mediaPaths.ebookPath != nil || mediaPaths.audioPath != nil
                || mediaPaths.syncedPath != nil
            {
                paths[book.uuid] = mediaPaths
            }
        }
        return paths
    }

    public func mediaDirectory(
        for uuid: String,
        category: LocalMediaCategory,
        sourceID explicitSourceID: BookSourceID? = nil,
    ) async -> URL? {
        guard let sourceID = await cacheSourceID(for: uuid, explicitSourceID: explicitSourceID)
        else { return nil }
        return await filesystem.mediaDirectory(
            for: uuid,
            category: category,
            in: .storyteller,
            sourceID: sourceID,
        )
    }

    public func mediaFilePath(
        for uuid: String,
        category: LocalMediaCategory,
        sourceID explicitSourceID: BookSourceID? = nil,
    ) async -> URL? {
        if let paths = localStorytellerBookPaths[uuid] {
            switch category {
                case .ebook: return paths.ebookPath
                case .audio: return paths.audioPath
                case .synced: return paths.syncedPath
            }
        }
        guard let sourceID = await cacheSourceID(for: uuid, explicitSourceID: explicitSourceID)
        else { return nil }
        guard
            let categoryDir = await filesystem.mediaDirectory(
                for: uuid,
                category: category,
                in: .storyteller,
                sourceID: sourceID,
            )
        else { return nil }

        var paths = await scanBookPaths(for: uuid, domain: .storyteller, sourceID: sourceID)
        localStorytellerBookPaths[uuid] = paths
        switch category {
            case .ebook:
                if paths.ebookPath == nil {
                    paths.ebookPath = firstCachedMediaFile(in: categoryDir, category: category)
                }
                return paths.ebookPath
            case .audio:
                if paths.audioPath == nil {
                    paths.audioPath = firstCachedMediaFile(in: categoryDir, category: category)
                }
                return paths.audioPath
            case .synced:
                if paths.syncedPath == nil {
                    paths.syncedPath = firstCachedMediaFile(in: categoryDir, category: category)
                }
                return paths.syncedPath
        }
    }

    private func cacheSourceID(
        for uuid: String,
        explicitSourceID: BookSourceID?,
    ) async -> BookSourceID? {
        if let explicitSourceID {
            return explicitSourceID
        }
        if let metadataSourceID = localStorytellerMetadata.first(where: { $0.uuid == uuid })?.sourceID
        {
            return metadataSourceID
        }
        return await migratedSourceID(for: .storyteller)
    }

    private func firstCachedMediaFile(in categoryDir: URL, category: LocalMediaCategory) -> URL? {
        switch category {
            case .ebook, .synced:
                guard
                    let contents = try? FileManager.default.contentsOfDirectory(
                        at: categoryDir,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles],
                    )
                else {
                    return nil
                }
                return firstMediaFile(in: contents, matchingExtensions: ["epub"])
            case .audio:
                return audioManifestFile(in: categoryDir)
        }
    }

    private func firstMediaFile(in contents: [URL], matchingExtensions extensions: Set<String>)
        -> URL?
    {
        return contents.first { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory != true
            else {
                return false
            }
            return extensions.contains(url.pathExtension.lowercased())
        }
    }

    private func audioManifestFile(in audioDirectory: URL) -> URL? {
        let manifestURL = audioDirectory.appendingPathComponent(
            "manifest.json",
            isDirectory: false,
        )
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        return manifestURL
    }

    public func deleteMedia(
        for uuid: String,
        category: LocalMediaCategory,
        sourceID explicitSourceID: BookSourceID? = nil,
    ) async throws {
        guard let sourceID = await cacheSourceID(for: uuid, explicitSourceID: explicitSourceID)
        else { return }
        try await filesystem.deleteMedia(
            for: uuid,
            category: category,
            in: .storyteller,
            sourceID: sourceID,
        )

        let updatedPaths = await scanBookPaths(
            for: uuid,
            domain: .storyteller,
            sourceID: sourceID,
        )
        if updatedPaths.ebookPath == nil && updatedPaths.audioPath == nil
            && updatedPaths.syncedPath == nil
        {
            localStorytellerBookPaths.removeValue(forKey: uuid)
        } else {
            localStorytellerBookPaths[uuid] = updatedPaths
        }

        await notifyObservers()
    }

    /// Returns the base directory for the given domain, e.g. `<ApplicationSupport>/storyteller_media`.
    public func getDomainDirectory(for domain: LocalMediaDomain) async -> URL {
        await filesystem.getDomainDirectory(for: domain)
    }

    /// Returns the directory for the supplied domain/category pair and book name.
    /// - Parameters:
    ///   - domain: Storage domain (e.g. `.local`).
    ///   - category: Media category (e.g. `.audio`).
    ///   - bookName: Display name used for the nested book folder.
    ///   - uuidIdentifier: Optional identifier used to produce a stable folder name (e.g. a Storyteller book UUID).
    /// - Returns: `<ApplicationSupport>/<domain>/foo/<category>` when `bookName == "foo"`. Supplying a UUID ensures all imports reuse the same folder; without a UUID (local media) a numeric suffix is appended when a folder already exists.
    public func getMediaDirectory(
        domain: LocalMediaDomain,
        category: LocalMediaCategory,
        bookName: String,
        uuidIdentifier: String? = nil,
        sourceID: BookSourceID? = nil,
    ) async -> URL {
        await filesystem.getMediaDirectory(
            domain: domain,
            category: category,
            bookName: bookName,
            uuidIdentifier: uuidIdentifier,
            sourceID: sourceID,
        )
    }

    public static func category(forFileURL url: URL) throws -> LocalMediaCategory {
        let ext = url.pathExtension.lowercased()
        guard let category = Self.extensionCategoryMap[ext] else {
            throw LocalMediaError.unsupportedFileExtension(ext)
        }
        return category
    }

    public func importMedia(
        for metadata: BookMetadata,
        category: LocalMediaCategory,
    ) -> AsyncThrowingStream<LocalMediaImportEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    try await self.streamStorytellerImport(
                        metadata: metadata,
                        category: category,
                        continuation: continuation,
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func streamStorytellerImport(
        metadata: BookMetadata,
        category: LocalMediaCategory,
        continuation: AsyncThrowingStream<LocalMediaImportEvent, Error>.Continuation,
    ) async throws {
        try await filesystem.ensureLocalStorageDirectories()
        let storytellerSourceID: BookSourceID
        if let sourceID = metadata.sourceID {
            storytellerSourceID = sourceID
        } else if let migrated = await migratedSourceID(for: .storyteller) {
            storytellerSourceID = migrated
        } else {
            continuation.yield(.skipped(book: metadata, category: category))
            return
        }

        let destinationDirectory = await filesystem.getMediaDirectory(
            domain: .storyteller,
            category: category,
            bookName: metadata.title,
            uuidIdentifier: metadata.uuid,
            sourceID: storytellerSourceID,
        )
        let bookRoot = destinationDirectory.deletingLastPathComponent()
        try await filesystem.ensureDirectoryExists(at: bookRoot)

        let fm = FileManager.default

        let assetInfo = storytellerAssetInfo(for: metadata, category: category)
        guard assetInfo.available else {
            continuation.yield(.skipped(book: metadata, category: category))
            return
        }

        guard let sourceID = metadata.sourceID,
            let download = await BookServiceActor.shared.fetchBook(
                for: metadata.uuid,
                sourceID: sourceID,
                format: assetInfo.format,
            )
        else {
            continuation.yield(.skipped(book: metadata, category: category))
            return
        }

        try await filesystem.ensureDirectoryExists(at: destinationDirectory)

        var currentFilename = download.initialFilename
        var expectedBytes: Int64? = nil
        var started = false
        var lastReported: Int64 = -1

        do {
            for try await event in download.events {
                try Task.checkCancellation()
                switch event {
                    case .response(let filename, let expected, _, _, _):
                        currentFilename = filename
                        expectedBytes = expected
                        if !started {
                            started = true
                            continuation.yield(
                                .started(
                                    book: metadata,
                                    category: category,
                                    expectedBytes: expectedBytes,
                                )
                            )
                        }
                    case .progress(let receivedBytes, let eventExpected):
                        if !started {
                            started = true
                            expectedBytes = eventExpected ?? expectedBytes
                            continuation.yield(
                                .started(
                                    book: metadata,
                                    category: category,
                                    expectedBytes: expectedBytes,
                                )
                            )
                        }
                        expectedBytes = eventExpected ?? expectedBytes
                        guard receivedBytes != lastReported else { continue }
                        lastReported = receivedBytes
                        continuation.yield(
                            .progress(
                                book: metadata,
                                category: category,
                                receivedBytes: receivedBytes,
                                expectedBytes: expectedBytes,
                            )
                        )
                    case .finished(let tempURL):
                        if !started {
                            started = true
                            continuation.yield(
                                .started(
                                    book: metadata,
                                    category: category,
                                    expectedBytes: expectedBytes,
                                )
                            )
                        }

                        if category == .audio {
                            if fm.fileExists(atPath: destinationDirectory.path) {
                                try fm.removeItem(at: destinationDirectory)
                            }
                            try await filesystem.ensureDirectoryExists(at: destinationDirectory)
                            try extractAudiobookPackage(from: tempURL, to: destinationDirectory)
                            guard
                                fm.fileExists(
                                    atPath: destinationDirectory.appendingPathComponent(
                                        "manifest.json"
                                    ).path
                                )
                            else {
                                throw LocalMediaError.missingAudiobookManifest
                            }
                            try? fm.removeItem(at: tempURL)
                            let destinationURL = destinationDirectory.appendingPathComponent(
                                "manifest.json"
                            )
                            continuation.yield(
                                .finished(
                                    book: metadata,
                                    category: category,
                                    destination: destinationURL,
                                )
                            )
                            do {
                                try await scanForMedia()
                            } catch {
                                debugLog(
                                    "[LocalMediaActor] scanForMedia post-download failed: \(error)"
                                )
                            }
                            return
                        }

                        let destinationURL = destinationDirectory.appendingPathComponent(
                            currentFilename
                        )
                        if fm.fileExists(atPath: destinationURL.path) {
                            try fm.removeItem(at: destinationURL)
                        }

                        var shouldRemoveTemp = true
                        defer {
                            if shouldRemoveTemp {
                                try? fm.removeItem(at: tempURL)
                            }
                        }

                        do {
                            try fm.moveItem(at: tempURL, to: destinationURL)
                            shouldRemoveTemp = false
                        } catch {
                            throw error
                        }

                        continuation.yield(
                            .finished(
                                book: metadata,
                                category: category,
                                destination: destinationURL,
                            )
                        )

                        do {
                            try await scanForMedia()
                        } catch {
                            debugLog(
                                "[LocalMediaActor] scanForMedia post-download failed: \(error)"
                            )
                        }
                        return
                }
            }
        } catch is CancellationError {
            download.cancel()
            throw CancellationError()
        } catch is StorytellerDownloadFailure {
            continuation.yield(.skipped(book: metadata, category: category))
        }
    }

    public func ensureLocalStorageDirectories() async throws {
        try await filesystem.ensureLocalStorageDirectories()
    }

    /// Import a pre-downloaded file into LMA storage. Used by watch for background downloads
    /// and iPhone transfers. Uses moveItem (not copy) to avoid doubling storage usage.
    public func importDownloadedFile(
        from tempURL: URL,
        metadata: BookMetadata,
        category: LocalMediaCategory,
        filename: String,
        audioIsPackage: Bool = true,
    ) async throws {
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try await filesystem.ensureLocalStorageDirectories()
        let storytellerSourceID: BookSourceID
        if let sourceID = metadata.sourceID {
            storytellerSourceID = sourceID
        } else if let migrated = await migratedSourceID(for: .storyteller) {
            storytellerSourceID = migrated
        } else {
            throw LocalMediaError.importFailed("Storyteller source is not configured")
        }

        let destinationDirectory = await filesystem.getMediaDirectory(
            domain: .storyteller,
            category: category,
            bookName: metadata.title,
            uuidIdentifier: metadata.uuid,
            sourceID: storytellerSourceID,
        )
        let bookRoot = destinationDirectory.deletingLastPathComponent()
        try await filesystem.ensureDirectoryExists(at: bookRoot)
        try await filesystem.ensureDirectoryExists(at: destinationDirectory)

        let fm = FileManager.default
        if category == .audio && audioIsPackage {
            if fm.fileExists(atPath: destinationDirectory.path) {
                try fm.removeItem(at: destinationDirectory)
            }
            try await filesystem.ensureDirectoryExists(at: destinationDirectory)

            do {
                try extractAudiobookPackage(from: tempURL, to: destinationDirectory)
                guard
                    fm.fileExists(
                        atPath: destinationDirectory.appendingPathComponent("manifest.json").path
                    )
                else {
                    throw LocalMediaError.missingAudiobookManifest
                }
                debugLog(
                    "[LMA] importDownloadedFile: extracted audiobook package to \(destinationDirectory.path)"
                )
                try await scanForMedia()
                return
            } catch {
                if fm.fileExists(atPath: destinationDirectory.path) {
                    try? fm.removeItem(at: destinationDirectory)
                }
                throw error
            }
        }

        let destinationURL = destinationDirectory.appendingPathComponent(filename)

        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        try fm.moveItem(at: tempURL, to: destinationURL)

        debugLog("[LMA] importDownloadedFile: moved \(filename) to \(destinationURL.path)")

        try await scanForMedia()
    }

    public func removeAllStorytellerData() async throws {
        try await filesystem.removeAllStorytellerData()

        localStorytellerMetadata = []
        localStorytellerBookPaths = [:]

        await notifyObservers()
    }

    public func removeStorytellerData(sourceID: BookSourceID) async throws {
        let booksToRemove = localStorytellerMetadata.filter {
            $0.sourceID == sourceID
        }

        for book in booksToRemove {
            try await filesystem.removeStorytellerBookData(uuid: book.uuid, sourceID: sourceID)
        }

        localStorytellerMetadata.removeAll {
            $0.sourceID == sourceID
        }
        try await filesystem.saveStorytellerLibraryMetadata([], sourceID: sourceID)

        var paths: [String: MediaPaths] = [:]
        for book in localStorytellerMetadata {
            let mediaPaths = await scanBookPaths(
                for: book.uuid,
                domain: .storyteller,
                sourceID: book.sourceID,
            )
            paths[book.uuid] = mediaPaths
        }
        localStorytellerBookPaths = paths

        await notifyObservers()
    }

    private func storytellerAssetInfo(
        for metadata: BookMetadata,
        category: LocalMediaCategory,
    ) -> (available: Bool, format: StorytellerBookFormat) {
        switch category {
            case .ebook:
                return (metadata.hasAvailableEbook, .ebook)
            case .audio:
                return (metadata.hasAvailableAudiobook, .audiobook)
            case .synced:
                return (metadata.hasAvailableReadaloud, .readaloud)
        }
    }

    private func extractAudiobookPackage(from archiveURL: URL, to destinationDirectory: URL) throws
    {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let fm = FileManager.default

        for entry in archive {
            guard !entry.path.hasPrefix("/"), !entry.path.split(separator: "/").contains("..")
            else {
                continue
            }
            let destinationURL = destinationDirectory.appendingPathComponent(entry.path)
            if entry.type == .directory {
                try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                continue
            }

            try fm.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            _ = try archive.extract(entry, to: destinationURL)
        }
    }

}

public enum LocalMediaDomain: String, CaseIterable, Sendable {
    case local = "local_media"
    case storyteller = "storyteller_media"

}

public enum LocalMediaCategory: String, CaseIterable, Sendable, Codable {
    case audio
    case ebook
    case synced
}

enum LocalMediaError: Error, Sendable {
    case unsupportedFileExtension(String)
    case missingAudiobookManifest
    case importFailed(String)
}

extension LocalMediaError: LocalizedError {
    var errorDescription: String? {
        switch self {
            case .unsupportedFileExtension(let ext):
                "Unsupported media file extension: \(ext)"
            case .missingAudiobookManifest:
                "Audiobook package is missing manifest.json"
            case .importFailed(let message):
                message
        }
    }
}
