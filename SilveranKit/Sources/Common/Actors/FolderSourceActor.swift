import Foundation

public actor FolderSourceActor: BookSourceActor {
    private let sourceRecordValue: BookSourceRecord
    private let localMediaActor: LocalMediaActor

    public init(
        sourceRecord: BookSourceRecord,
        localMediaActor: LocalMediaActor = .shared,
    ) {
        self.sourceRecordValue = sourceRecord
        self.localMediaActor = localMediaActor
    }

    public var sourceRecord: BookSourceRecord {
        sourceRecordValue
    }

    public var connectionStatus: ConnectionStatus {
        .connected
    }

    public func fetchLibraryInformation() async -> [BookMetadata]? {
        do {
            return try await localMediaActor.fetchFolderSourceLibrary(sourceRecord: sourceRecordValue)
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
        guard let data = await localMediaActor.extractLocalCover(
            for: bookId,
            sourceID: sourceRecordValue.id,
        ) else {
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
        await localMediaActor.updateBookProgress(
            bookId: bookId,
            locator: locator,
            timestamp: timestamp,
        )
        return .success
    }

    public func fetchBookPosition(bookId: String) async -> BookReadingPosition? {
        await localMediaActor.bookPosition(bookId: bookId, sourceID: sourceRecordValue.id)
    }
}
