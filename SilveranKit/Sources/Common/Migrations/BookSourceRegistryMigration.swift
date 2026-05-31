import Foundation

extension FilesystemActor {
    static let bookSourceRegistryMigrationID = "book-source-registry-v1"

    func migrateLegacyBookSourceRegistry() throws -> [BookSourceRecord] {
        let sources = try createLegacyBookSourceRecords()
        try saveBookSources(sources)
        writeMigrationSentinelBestEffort(Self.bookSourceRegistryMigrationID)
        markSourceDomainLayoutMigrationCompletedBestEffort()
        return sources
    }

    private func createLegacyBookSourceRecords() throws -> [BookSourceRecord] {
        let now = ISO8601DateFormatter().string(from: Date())
        let storytellerID = try migrateLegacyDomainDirectory(domain: .storyteller)
        let localFolderID = try migrateLegacyDomainDirectory(domain: .local)

        return [
            BookSourceRecord(
                id: storytellerID,
                name: "My Storyteller Server",
                kind: .storyteller,
                capabilities: .storyteller,
                createdAt: now,
                updatedAt: now,
                storagePath: getDomainDirectory(for: .storyteller, sourceID: storytellerID).path,
            ),
            BookSourceRecord(
                id: localFolderID,
                name: BookSourceKind.localFolder.defaultName,
                kind: .localFolder,
                capabilities: .localFolder,
                createdAt: now,
                updatedAt: now,
                storagePath: getDomainDirectory(for: .local, sourceID: localFolderID).path,
            ),
        ]
    }

    private func migrateLegacyDomainDirectory(domain: LocalMediaDomain) throws -> BookSourceID {
        let root = getDomainDirectory(for: domain)
        try ensureDirectoryExists(at: root)

        if let existingID = try sourceIDFromChildDirectory(in: root) {
            try migrateLegacyTopLevelContents(
                domain: domain,
                sourceID: existingID,
                configuredSourceIDs: [existingID],
            )
            return existingID
        }

        let markerURL = root.appendingPathComponent(
            BookSourceRecord.sourceIDFilename,
            isDirectory: false,
        )
        let sourceID: BookSourceID
        if let existing = try? String(contentsOf: markerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            sourceID = existing
        } else {
            sourceID = UUID().uuidString
            try sourceID.write(to: markerURL, atomically: true, encoding: .utf8)
        }

        let destination = getDomainDirectory(for: domain, sourceID: sourceID)
        try ensureDirectoryExists(at: destination)
        let destinationMarker = destination.appendingPathComponent(
            BookSourceRecord.sourceIDFilename,
            isDirectory: false,
        )
        try sourceID.write(to: destinationMarker, atomically: true, encoding: .utf8)

        try migrateLegacyTopLevelContents(
            domain: domain,
            sourceID: sourceID,
            configuredSourceIDs: [sourceID],
        )

        return sourceID
    }

    private func markSourceDomainLayoutMigrationCompletedBestEffort() {
        do {
            try markSourceDomainLayoutMigrationCompleted()
        } catch {
            debugLog(
                "[FilesystemActor] Failed to write source domain layout migration sentinel: \(error)"
            )
        }
    }

    private func writeMigrationSentinelBestEffort(_ migrationID: String) {
        do {
            try writeMigrationSentinel(migrationID)
        } catch {
            debugLog("[FilesystemActor] Failed to write migration sentinel \(migrationID): \(error)")
        }
    }

    private func sourceIDFromChildDirectory(in root: URL) throws -> BookSourceID? {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )

        for url in contents {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let marker = url.appendingPathComponent(
                BookSourceRecord.sourceIDFilename,
                isDirectory: false,
            )
            guard fm.fileExists(atPath: marker.path),
                let id = try? String(contentsOf: marker, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !id.isEmpty
            else {
                continue
            }
            return id
        }

        return nil
    }

}
