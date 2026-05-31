import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

extension FilesystemActor {
    private static let sourceDomainLayoutMigrationID = "source-domain-layout-v1"
    private static let legacyM4BAudiobookMigrationID = "legacy-m4b-audiobook-manifests-v1"

    func runStorageMigrations(for sources: [BookSourceRecord]) async throws {
        try runSourceDomainLayoutMigrationIfNeeded(for: sources)
        try await runLegacyM4BAudiobookMigrationIfNeeded(for: sources)
    }

    func markSourceDomainLayoutMigrationCompleted() throws {
        try writeMigrationSentinel(Self.sourceDomainLayoutMigrationID)
    }

    private func runLegacyM4BAudiobookMigrationIfNeeded(
        for sources: [BookSourceRecord],
    ) async throws {
        guard !migrationSentinelExists(Self.legacyM4BAudiobookMigrationID) else { return }

        var failed = false
        for source in sources {
            let domain: LocalMediaDomain
            switch source.kind {
                case .storyteller:
                    domain = .storyteller
                case .localFolder:
                    domain = .local
            }

            do {
                try await migrateLegacyM4BAudiobooks(
                    in: getDomainDirectory(for: domain, sourceID: source.id),
                )
            } catch {
                failed = true
                debugLog(
                    "[FilesystemActor] Legacy M4B migration failed for source \(source.id): \(error)"
                )
            }
        }

        guard !failed else {
            return
        }

        try writeMigrationSentinel(Self.legacyM4BAudiobookMigrationID)
    }

    private func runSourceDomainLayoutMigrationIfNeeded(
        for sources: [BookSourceRecord],
    ) throws {
        guard !migrationSentinelExists(Self.sourceDomainLayoutMigrationID) else { return }

        let storytellerIDs = Set(
            sources
                .filter { $0.kind == .storyteller }
                .map(\.id)
        )
        if let sourceID = sources.first(where: { $0.kind == .storyteller })?.id {
            try migrateLegacyTopLevelContents(
                domain: .storyteller,
                sourceID: sourceID,
                configuredSourceIDs: storytellerIDs,
            )
        }

        let localFolderIDs = Set(
            sources
                .filter { $0.kind == .localFolder }
                .map(\.id)
        )
        if let sourceID = sources.first(where: { $0.kind == .localFolder })?.id {
            try migrateLegacyTopLevelContents(
                domain: .local,
                sourceID: sourceID,
                configuredSourceIDs: localFolderIDs,
            )
        }

        try writeMigrationSentinel(Self.sourceDomainLayoutMigrationID)
    }

    func migrateLegacyTopLevelContents(
        domain: LocalMediaDomain,
        sourceID: BookSourceID,
        configuredSourceIDs: Set<BookSourceID>,
    ) throws {
        let root = getDomainDirectory(for: domain)
        let destination = getDomainDirectory(for: domain, sourceID: sourceID)
        try ensureDirectoryExists(at: destination)

        let destinationMarker = destination.appendingPathComponent(
            BookSourceRecord.sourceIDFilename,
            isDirectory: false,
        )
        try sourceID.write(to: destinationMarker, atomically: true, encoding: .utf8)

        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
        )

        for item in contents {
            if item.lastPathComponent == BookSourceRecord.sourceIDFilename {
                try? fm.removeItem(at: item)
                continue
            }
            if item.standardizedFileURL == destination.standardizedFileURL { continue }

            let isDirectory =
                (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory, try isSourceDirectory(item, configuredSourceIDs: configuredSourceIDs) {
                continue
            }

            let target = destination.appendingPathComponent(
                item.lastPathComponent,
                isDirectory: isDirectory,
            )

            if fm.fileExists(atPath: target.path) {
                if item.lastPathComponent == "library_metadata.json" {
                    try fm.removeItem(at: item)
                }
                continue
            }

            try fm.moveItem(at: item, to: target)
        }
    }

    private func isSourceDirectory(
        _ directory: URL,
        configuredSourceIDs: Set<BookSourceID>,
    ) throws -> Bool {
        if configuredSourceIDs.contains(directory.lastPathComponent) {
            return true
        }

        let marker = directory.appendingPathComponent(
            BookSourceRecord.sourceIDFilename,
            isDirectory: false,
        )
        guard FileManager.default.fileExists(atPath: marker.path) else {
            return false
        }

        let markerID = try String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !markerID.isEmpty
    }

    private func migrateLegacyM4BAudiobooks(in sourceDirectory: URL) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceDirectory.path) else { return }

        let bookDirectories = try fm.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )

        for bookDirectory in bookDirectories {
            let values = try? bookDirectory.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let audioDirectory = bookDirectory.appendingPathComponent(
                LocalMediaCategory.audio.rawValue,
                isDirectory: true,
            )
            do {
                try await writeLegacyM4BManifestIfNeeded(in: audioDirectory)
            } catch {
                debugLog(
                    "[FilesystemActor] Legacy M4B migration failed for \(audioDirectory.path): \(error)"
                )
                throw error
            }
        }
    }

    private func writeLegacyM4BManifestIfNeeded(in audioDirectory: URL) async throws {
        let fm = FileManager.default
        let manifestURL = audioDirectory.appendingPathComponent(
            "manifest.json",
            isDirectory: false,
        )
        if fm.fileExists(atPath: manifestURL.path) {
            return
        }

        guard fm.fileExists(atPath: audioDirectory.path) else {
            return
        }

        let contents = try fm.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )

        let m4bFiles = contents.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory != true
            else {
                return false
            }
            return url.pathExtension.lowercased() == "m4b"
        }

        guard m4bFiles.count == 1, let m4bURL = m4bFiles.first else {
            return
        }

        try await writeLegacyM4BManifest(for: m4bURL, manifestURL: manifestURL)
    }

    private func writeLegacyM4BManifest(for m4bURL: URL, manifestURL: URL) async throws {
        let duration = await audioDuration(for: m4bURL)
        let title =
            await audioTitle(for: m4bURL) ?? m4bURL.deletingPathExtension().lastPathComponent
        let mediaType = "audio/mp4"
        let href = m4bURL.lastPathComponent

        var readingOrderItem: [String: Any] = [
            "href": href,
            "type": mediaType,
        ]
        if let duration {
            readingOrderItem["duration"] = duration
        }
        let readingOrder = [readingOrderItem]

        let toc = await legacyM4BTOC(for: m4bURL)
        let manifest: [String: Any] = [
            "metadata": [
                "@type": "http://schema.org/Audiobook",
                "title": title,
            ],
            "links": [
                [
                    "rel": "self",
                    "href": "manifest.json",
                    "type": "application/audiobook+json",
                ]
            ],
            "readingOrder": readingOrder,
            "toc": toc.isEmpty
                ? [["href": "\(href)#t=0", "title": "Full Book"]]
                : toc,
        ]

        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys],
        )
        let tmpURL = manifestURL.appendingPathExtension("tmp")
        try data.write(to: tmpURL, options: .atomic)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
        try FileManager.default.moveItem(at: tmpURL, to: manifestURL)
    }

    private func audioDuration(for url: URL) async -> Double? {
        #if canImport(AVFoundation)
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
        #else
        return nil
        #endif
    }

    private func audioTitle(for url: URL) async -> String? {
        #if canImport(AVFoundation)
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        for item in metadata where item.commonKey == .commonKeyTitle {
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    private func legacyM4BTOC(for url: URL) async -> [[String: Any]] {
        #if canImport(AVFoundation)
        let asset = AVURLAsset(url: url)
        guard
            let locales = try? await asset.load(.availableChapterLocales),
            let locale = locales.first,
            let groups = try? await asset.loadChapterMetadataGroups(
                withTitleLocale: locale,
                containingItemsWithCommonKeys: [.commonKeyTitle],
            ),
            !groups.isEmpty
        else {
            return []
        }

        var toc: [[String: Any]] = []
        for (index, group) in groups.enumerated() {
            let start = CMTimeGetSeconds(group.timeRange.start)
            guard start.isFinite else { continue }
            var title = "Chapter \(index + 1)"
            for item in group.items where item.commonKey == .commonKeyTitle {
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    title = value
                    break
                }
            }
            toc.append(["href": "\(url.lastPathComponent)#t=\(start)", "title": title])
        }
        return toc
        #else
        return []
        #endif
    }

    func migrationSentinelExists(_ migrationID: String) -> Bool {
        FileManager.default.fileExists(atPath: migrationSentinelURL(migrationID).path)
    }

    func writeMigrationSentinel(_ migrationID: String) throws {
        let sentinelDir = migrationSentinelDirectory()
        try ensureDirectoryExists(at: sentinelDir)
        let payload = "\(ISO8601DateFormatter().string(from: Date()))\n"
        try payload.write(
            to: migrationSentinelURL(migrationID),
            atomically: true,
            encoding: .utf8,
        )
    }

    private func migrationSentinelDirectory() -> URL {
        getConfigDirectory()
            .appendingPathComponent("MigrationSentinels", isDirectory: true)
    }

    private func migrationSentinelURL(_ migrationID: String) -> URL {
        migrationSentinelDirectory()
            .appendingPathComponent(migrationID, isDirectory: false)
    }
}
