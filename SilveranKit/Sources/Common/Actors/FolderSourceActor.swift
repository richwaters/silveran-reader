import Foundation

public actor FolderSourceActor: BookSourceActor {
    private let sourceRecordValue: BookSourceRecord
    private let filesystem: FilesystemActor
    private let localLibrary: LocalLibraryManager

    private var metadataCache: [BookMetadata] = []
    private var pathCache: [String: MediaPaths] = [:]

    public init(
        sourceRecord: BookSourceRecord,
        filesystem: FilesystemActor = .shared,
        localLibrary: LocalLibraryManager = LocalLibraryManager(),
    ) {
        self.sourceRecordValue = sourceRecord
        self.filesystem = filesystem
        self.localLibrary = localLibrary
    }

    public var sourceRecord: BookSourceRecord {
        sourceRecordValue
    }

    public var connectionStatus: ConnectionStatus {
        .connected
    }

    public func fetchLibraryInformation() async -> [BookMetadata]? {
        do {
            let library = try await scanLibrary()
            metadataCache = library.metadata
            pathCache = library.paths
            return library.metadata
        } catch {
            debugLog("[FolderSourceActor] Failed to fetch library: \(error)")
            return nil
        }
    }

    public func fetchCoverImage(
        for bookId: String,
        audio _: Bool,
        width _: Int?,
        height _: Int?,
        version _: String?,
        ifNoneMatch _: String?,
        ifModifiedSince _: String?,
    ) async -> BookCover? {
        guard let data = await extractCover(for: bookId) else {
            return nil
        }
        return BookCover(
            data: data,
            contentType: nil,
            etag: nil,
            lastModified: nil,
            cacheControl: nil,
            contentDisposition: nil,
        )
    }

    public func sendProgressToServer(
        bookId: String,
        locator: BookLocator,
        timestamp: Double,
    ) async -> HTTPResult {
        do {
            try await updateBookProgress(bookId: bookId, locator: locator, timestamp: timestamp)
            return .success
        } catch {
            debugLog("[FolderSourceActor] Failed to save progress: \(error)")
            return .failure
        }
    }

    public func fetchBookPosition(bookId: String) async -> BookReadingPosition? {
        if let position = metadataCache.first(where: { $0.uuid == bookId })?.position {
            return position
        }
        guard let metadata = await fetchLibraryInformation() else { return nil }
        return metadata.first(where: { $0.uuid == bookId })?.position
    }

    public func copyMediaToTemporaryFile(
        for bookID: String,
        category: LocalMediaCategory,
    ) async throws -> (url: URL, filename: String)? {
        if pathCache[bookID] == nil {
            _ = await fetchLibraryInformation()
        }
        guard let paths = pathCache[bookID] else { return nil }
        let sourceURL: URL?
        switch category {
            case .ebook:
                sourceURL = paths.ebookPath
            case .audio:
                sourceURL = paths.audioPath
            case .synced:
                sourceURL = paths.syncedPath
        }
        guard let sourceURL else { return nil }

        let resolved = try await resolvedFolderURL()
        defer { resolved.stopAccessing?() }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SilveranFolderSourceDownloads", isDirectory: true)
        try await filesystem.ensureDirectoryExists(at: tempDirectory)

        let filename = sourceURL.lastPathComponent
        let tempURL = tempDirectory.appendingPathComponent(
            "\(UUID().uuidString)-\(filename)",
            isDirectory: false,
        )
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        return (tempURL, filename)
    }

    public func folderDirectory() async throws -> URL {
        let resolved = try await resolvedFolderURL()
        resolved.stopAccessing?()
        return resolved.url
    }

    public func importMedia(
        from sourceFileURL: URL,
        category: LocalMediaCategory,
        bookName: String,
        bookUUID: String? = nil,
    ) async throws -> URL {
        let shouldStopAccessingSource = sourceFileURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessingSource {
                sourceFileURL.stopAccessingSecurityScopedResource()
            }
        }

        let resolved = try await resolvedFolderURL()
        defer { resolved.stopAccessing?() }

        let extractedMetadata = try await localLibrary.extractMetadata(
            from: sourceFileURL,
            category: category,
        )
        let importUUID = bookUUID ?? extractedMetadata.uuid
        var metadata = mergedBookMetadata(
            scanned: extractedMetadata,
            saved: BookMetadata(
                uuid: importUUID,
                title: extractedMetadata.title,
                subtitle: extractedMetadata.subtitle,
                description: extractedMetadata.description,
                language: extractedMetadata.language,
                createdAt: extractedMetadata.createdAt,
                updatedAt: extractedMetadata.updatedAt,
                publicationDate: extractedMetadata.publicationDate,
                authors: extractedMetadata.authors,
                narrators: extractedMetadata.narrators,
                creators: extractedMetadata.creators,
                series: extractedMetadata.series,
                tags: extractedMetadata.tags,
                collections: extractedMetadata.collections,
                ebook: extractedMetadata.ebook,
                audiobook: extractedMetadata.audiobook,
                readaloud: extractedMetadata.readaloud,
                status: extractedMetadata.status,
                position: extractedMetadata.position,
                rating: extractedMetadata.rating,
            ),
        )
        metadata.sourceID = sourceRecordValue.id
        metadata.source = sourceRecordValue.name

        let effectiveCategory: LocalMediaCategory
        if metadata.hasAvailableReadaloud {
            effectiveCategory = .synced
        } else if metadata.hasAvailableAudiobook {
            effectiveCategory = .audio
        } else {
            effectiveCategory = category
        }

        let bookFolder = resolved.url.appendingPathComponent(
            folderName(title: bookName, uuid: metadata.uuid),
            isDirectory: true,
        )
        let destinationDirectory = bookFolder.appendingPathComponent(
            effectiveCategory.rawValue,
            isDirectory: true,
        )
        try await filesystem.ensureDirectoryExists(at: destinationDirectory)

        let destinationURL = destinationDirectory.appendingPathComponent(
            sourceFileURL.lastPathComponent,
            isDirectory: false,
        )
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: sourceFileURL, to: destinationURL)

        _ = try await scanLibrary(in: resolved.url)
        return destinationURL
    }

    public func deleteBook(_ bookID: String) async throws {
        if pathCache[bookID] == nil {
            _ = await fetchLibraryInformation()
        }
        guard let paths = pathCache[bookID] else {
            try await removeMetadata(bookID: bookID)
            return
        }

        var bookFolder: URL?
        if let ebookPath = paths.ebookPath {
            bookFolder = ebookPath.deletingLastPathComponent().deletingLastPathComponent()
        } else if let audioPath = paths.audioPath {
            bookFolder = audioPath.deletingLastPathComponent().deletingLastPathComponent()
        } else if let syncedPath = paths.syncedPath {
            bookFolder = syncedPath.deletingLastPathComponent().deletingLastPathComponent()
        }

        if let bookFolder, FileManager.default.fileExists(atPath: bookFolder.path) {
            try FileManager.default.removeItem(at: bookFolder)
        }
        try await removeMetadata(bookID: bookID)
    }

    private func scanLibrary() async throws -> LocalLibraryManager.ScanResult {
        let resolved = try await resolvedFolderURL()
        defer { resolved.stopAccessing?() }
        return try await scanLibrary(in: resolved.url)
    }

    private func scanLibrary(in folderURL: URL) async throws -> LocalLibraryManager.ScanResult {
        try await filesystem.ensureDirectoryExists(at: folderURL)
        try await filesystem.ensureSourceIDMarker(in: folderURL, sourceID: sourceRecordValue.id)

        let localScanResult = try await localLibrary.scanLocalMedia(
            folderURL: folderURL,
            sourceID: sourceRecordValue.id,
        )

        let savedMetadata = try await savedMetadata(in: folderURL)
        let savedByFilename = savedMetadataByFilename(savedMetadata)
        var mergedMetadata: [BookMetadata] = []
        var mergedPaths: [String: MediaPaths] = [:]

        for scanned in localScanResult.metadata {
            let scannedFilepath =
                scanned.ebook?.filepath ?? scanned.audiobook?.filepath
                ?? scanned.readaloud?.filepath

            if let filepath = scannedFilepath, let saved = savedByFilename[filepath] {
                var merged = mergedBookMetadata(scanned: scanned, saved: saved)
                merged.sourceID = sourceRecordValue.id
                merged.source = sourceRecordValue.name
                mergedMetadata.append(merged)

                if let scannedPaths = localScanResult.paths[scanned.uuid] {
                    mergedPaths[saved.uuid] = scannedPaths
                }
            } else {
                var stamped = scanned
                stamped.sourceID = sourceRecordValue.id
                stamped.source = sourceRecordValue.name
                mergedMetadata.append(stamped)
                if let scannedPaths = localScanResult.paths[scanned.uuid] {
                    mergedPaths[scanned.uuid] = scannedPaths
                }
            }
        }

        try await filesystem.saveFolderSourceLibraryMetadata(mergedMetadata, in: folderURL)
        metadataCache = mergedMetadata
        pathCache = mergedPaths

        return LocalLibraryManager.ScanResult(metadata: mergedMetadata, paths: mergedPaths)
    }

    private func savedMetadata(in folderURL: URL) async throws -> [BookMetadata] {
        if let folderMetadata = try await filesystem.loadFolderSourceLibraryMetadata(in: folderURL) {
            return folderMetadata.map { book in
                var stamped = book
                stamped.sourceID = sourceRecordValue.id
                stamped.source = sourceRecordValue.name
                return stamped
            }
        }

        if let migrated = try? await filesystem.loadLocalLibraryMetadata(sourceID: sourceRecordValue.id)
        {
            let stamped = migrated.map { book in
                var stamped = book
                stamped.sourceID = sourceRecordValue.id
                stamped.source = sourceRecordValue.name
                return stamped
            }
            try await filesystem.saveFolderSourceLibraryMetadata(stamped, in: folderURL)
            return stamped
        }

        return []
    }

    private func savedMetadataByFilename(_ metadata: [BookMetadata]) -> [String: BookMetadata] {
        var savedByFilename: [String: BookMetadata] = [:]
        for saved in metadata {
            if let filepath = saved.ebook?.filepath {
                savedByFilename[filepath] = saved
            }
            if let filepath = saved.audiobook?.filepath {
                savedByFilename[filepath] = saved
            }
            if let filepath = saved.readaloud?.filepath {
                savedByFilename[filepath] = saved
            }
        }
        return savedByFilename
    }

    private func updateBookProgress(
        bookId: String,
        locator: BookLocator,
        timestamp: Double,
    ) async throws {
        let resolved = try await resolvedFolderURL()
        defer { resolved.stopAccessing?() }

        if metadataCache.isEmpty {
            _ = try await scanLibrary(in: resolved.url)
        }

        guard let index = metadataCache.firstIndex(where: { $0.uuid == bookId }) else {
            return
        }
        let existing = metadataCache[index]
        let existingTimestamp = existing.position?.timestamp ?? 0
        guard timestamp > existingTimestamp else { return }

        let updatedAtString = Date(timeIntervalSince1970: timestamp / 1000).ISO8601Format()
        let newPosition = BookReadingPosition(
            uuid: existing.position?.uuid,
            locator: locator,
            timestamp: timestamp,
            createdAt: existing.position?.createdAt,
            updatedAt: updatedAtString,
        )
        var updatedMetadata = mergedBookMetadata(
            scanned: existing,
            saved: existing,
            position: newPosition,
        )
        updatedMetadata.sourceID = sourceRecordValue.id
        updatedMetadata.source = sourceRecordValue.name
        metadataCache[index] = updatedMetadata
        try await filesystem.saveFolderSourceLibraryMetadata(metadataCache, in: resolved.url)
    }

    private func removeMetadata(bookID: String) async throws {
        let resolved = try await resolvedFolderURL()
        defer { resolved.stopAccessing?() }

        metadataCache.removeAll { $0.uuid == bookID }
        pathCache.removeValue(forKey: bookID)
        try await filesystem.saveFolderSourceLibraryMetadata(metadataCache, in: resolved.url)
    }

    private func extractCover(for bookID: String) async -> Data? {
        if pathCache[bookID] == nil {
            _ = await fetchLibraryInformation()
        }
        guard let paths = pathCache[bookID] else { return nil }

        if let ebookPath = paths.ebookPath,
            let data = localLibrary.extractCoverFromEpub(at: ebookPath)
        {
            return data
        }

        if let syncedPath = paths.syncedPath,
            let data = localLibrary.extractCoverFromEpub(at: syncedPath)
        {
            return data
        }

        if let audioPath = paths.audioPath,
            let data = await localLibrary.extractCoverFromAudiobook(at: audioPath)
        {
            return data
        }

        return nil
    }

    private func resolvedFolderURL() async throws -> (
        url: URL,
        stopAccessing: (() -> Void)?
    ) {
        if let resolved = sourceFolderURL(sourceRecordValue) {
            try await filesystem.ensureDirectoryExists(at: resolved.url)
            return resolved
        }

        let directory = try await filesystem.ensureSourceDirectory(
            for: .local,
            sourceID: sourceRecordValue.id,
        )
        return (directory, nil)
    }

    private func sourceFolderURL(_ sourceRecord: BookSourceRecord) -> (
        url: URL,
        stopAccessing: (() -> Void)?
    )? {
        #if os(macOS)
        if let bookmarkData = sourceRecord.storageBookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale,
            ) {
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                return (
                    url,
                    didStartAccessing
                        ? { url.stopAccessingSecurityScopedResource() }
                        : nil
                )
            }
        }
        #elseif os(iOS)
        if let bookmarkData = sourceRecord.storageBookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale,
            ) {
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                return (
                    url,
                    didStartAccessing
                        ? { url.stopAccessingSecurityScopedResource() }
                        : nil
                )
            }
        }
        #endif

        guard let storagePath = sourceRecord.storagePath, !storagePath.isEmpty else {
            return nil
        }
        return (URL(fileURLWithPath: storagePath, isDirectory: true), nil)
    }

    private func folderName(title: String, uuid: String) -> String {
        let sanitizedTitle = sanitizedPathComponent(title)
        let sanitizedUUID = sanitizedPathComponent(uuid)
        guard !sanitizedTitle.isEmpty else { return sanitizedUUID.isEmpty ? "Book" : sanitizedUUID }
        guard !sanitizedUUID.isEmpty else { return sanitizedTitle }
        if sanitizedTitle.caseInsensitiveCompare(sanitizedUUID) == .orderedSame {
            return sanitizedTitle
        }
        return "\(sanitizedTitle) - \(sanitizedUUID)"
    }

    private func sanitizedPathComponent(_ input: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = input
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Book" : sanitized
    }

    private func mergedBookMetadata(
        scanned: BookMetadata,
        saved: BookMetadata,
        position: BookReadingPosition? = nil,
    ) -> BookMetadata {
        BookMetadata(
            uuid: saved.uuid,
            title: scanned.title,
            subtitle: scanned.subtitle,
            description: scanned.description,
            language: scanned.language,
            createdAt: saved.createdAt,
            updatedAt: saved.updatedAt,
            publicationDate: scanned.publicationDate,
            authors: scanned.authors,
            narrators: scanned.narrators,
            creators: scanned.creators,
            series: scanned.series,
            tags: scanned.tags,
            collections: scanned.collections,
            ebook: scanned.ebook.map { asset in
                BookAsset(
                    uuid: saved.uuid,
                    filepath: asset.filepath,
                    missing: asset.missing,
                    createdAt: asset.createdAt,
                    updatedAt: asset.updatedAt,
                )
            },
            audiobook: scanned.audiobook.map { asset in
                BookAsset(
                    uuid: saved.uuid,
                    filepath: asset.filepath,
                    missing: asset.missing,
                    createdAt: asset.createdAt,
                    updatedAt: asset.updatedAt,
                )
            },
            readaloud: scanned.readaloud.map { asset in
                BookReadaloud(
                    uuid: saved.uuid,
                    filepath: asset.filepath,
                    missing: asset.missing,
                    status: asset.status,
                    currentStage: asset.currentStage,
                    stageProgress: asset.stageProgress,
                    queuePosition: asset.queuePosition,
                    restartPending: asset.restartPending,
                    createdAt: asset.createdAt,
                    updatedAt: asset.updatedAt,
                )
            },
            status: saved.status,
            position: position ?? saved.position,
            rating: saved.rating,
        )
    }
}
