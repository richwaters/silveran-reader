import Foundation

extension FilesystemActor {
    func createDefaultBookSources() throws -> [BookSourceRecord] {
        let now = ISO8601DateFormatter().string(from: Date())
        let sources = [
            try createDefaultBookSource(
                domain: .storyteller,
                kind: .storyteller,
                name: BookSourceKind.storyteller.defaultName,
                timestamp: now,
            ),
            try createDefaultBookSource(
                domain: .local,
                kind: .localFolder,
                name: BookSourceKind.localFolder.defaultName,
                timestamp: now,
            ),
        ]

        try saveBookSources(sources)
        return sources
    }

    private func createDefaultBookSource(
        domain: LocalMediaDomain,
        kind: BookSourceKind,
        name: String,
        timestamp: String,
    ) throws -> BookSourceRecord {
        let sourceID = UUID().uuidString
        let directory = try ensureSourceDirectory(for: domain, sourceID: sourceID)
        return BookSourceRecord(
            id: sourceID,
            name: name,
            kind: kind,
            capabilities: kind == .storyteller ? .storyteller : .localFolder,
            createdAt: timestamp,
            updatedAt: timestamp,
            storagePath: directory.path,
        )
    }
}
