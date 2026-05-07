import Foundation
import SwiftUI

@MainActor
@Observable
final class MetadataEditorViewModel {
    enum HardcoverImportSource: String, CaseIterable, Identifiable {
        case text
        case audiobook

        var id: String { rawValue }

        var label: String {
            switch self {
            case .text: return "Text / Ebook"
            case .audiobook: return "Audiobook"
            }
        }
    }

    struct EditableCreator: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var fileAs: String
        var role: String
        var uuid: String?
    }

    struct EditableSeries: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var position: String
        var featured: Bool
        var uuid: String?
    }

    struct EditableBook: Identifiable {
        let id: String
        var originalMetadata: BookMetadata

        var title: String
        var subtitle: String
        var description: String
        var language: String
        var publicationDate: String
        var rating: String
        var authors: [String]
        var narrators: [String]
        var creators: [EditableCreator]
        var series: [EditableSeries]
        var tags: [String]
        var collectionUuids: [String]

        var dirtyFields: Set<String> = []
        var importedFields: Set<String> = []
        var importedItems: [String: Set<String>] = [:]
        var hardcoverImports: [HardcoverImportSource: HardcoverBookDetails] = [:]
        var hardcoverImportFields: [HardcoverImportSource: Set<String>] = [:]
        var lastImportedDetails: HardcoverBookDetails? {
            hardcoverImports[.text] ?? hardcoverImports[.audiobook]
        }
        var lastImportedFields: Set<String> {
            hardcoverImportFields[.text] ?? hardcoverImportFields[.audiobook] ?? []
        }
        var replacementEbookCover: (data: Data, filename: String)?
        var replacementAudiobookCover: (data: Data, filename: String)?

        var displayTitle: String {
            title.isEmpty ? "(Untitled)" : title
        }

        init(from metadata: BookMetadata) {
            self.id = metadata.uuid
            self.originalMetadata = metadata
            self.title = metadata.title
            self.subtitle = metadata.subtitle ?? ""
            self.description = metadata.description ?? ""
            self.language = metadata.language ?? ""
            self.publicationDate = Self.dateOnly(metadata.publicationDate) ?? ""
            self.rating = metadata.rating.map { String($0) } ?? ""
            self.authors = metadata.authors?.compactMap { $0.name } ?? []
            self.narrators = metadata.narrators?.compactMap { $0.name } ?? []
            self.creators = metadata.creators?.map { creator in
                EditableCreator(
                    name: creator.name ?? "",
                    fileAs: creator.fileAs ?? "",
                    role: creator.role ?? "",
                    uuid: creator.uuid
                )
            } ?? []
            self.series = metadata.series?.map { s in
                EditableSeries(
                    name: s.name,
                    position: s.position.map {
                        $0.truncatingRemainder(dividingBy: 1) == 0
                            ? String(Int($0)) : String($0)
                    } ?? "",
                    featured: s.featured == 1,
                    uuid: s.uuid
                )
            } ?? []
            self.tags = metadata.tags?.map { $0.name } ?? []
            self.collectionUuids = metadata.collections?.compactMap { $0.uuid } ?? []
        }

        static func dateOnly(_ isoDate: String?) -> String? {
            guard let isoDate, !isoDate.isEmpty else { return nil }
            if isoDate.contains("T") { return String(isoDate.prefix(10)) }
            return isoDate
        }

        var hasDirtyFields: Bool {
            !dirtyFields.isEmpty || replacementEbookCover != nil || replacementAudiobookCover != nil
        }

        func stringList(for field: String) -> [String] {
            switch field {
            case "authors": return authors
            case "narrators": return narrators
            case "tags": return tags
            default: return []
            }
        }

        mutating func appendToStringList(field: String, value: String) {
            switch field {
            case "authors": authors.append(value)
            case "narrators": narrators.append(value)
            case "tags": tags.append(value)
            default: break
            }
        }

        mutating func updateStringList(field: String, index: Int, value: String) {
            switch field {
            case "authors" where index < authors.count: authors[index] = value
            case "narrators" where index < narrators.count: narrators[index] = value
            case "tags" where index < tags.count: tags[index] = value
            default: break
            }
        }

        mutating func removeFromStringList(field: String, index: Int) {
            switch field {
            case "authors" where index < authors.count: authors.remove(at: index)
            case "narrators" where index < narrators.count: narrators.remove(at: index)
            case "tags" where index < tags.count: tags.remove(at: index)
            default: break
            }
        }

        mutating func removeFromStringList(field: String, indices: IndexSet) {
            switch field {
            case "authors": authors.remove(atOffsets: indices)
            case "narrators": narrators.remove(atOffsets: indices)
            case "tags": tags.remove(atOffsets: indices)
            default: break
            }
        }
    }

    struct CollectionChoice: Identifiable, Hashable {
        let id: Int
        let uuid: String
        let name: String
    }

    var books: [EditableBook] = []
    var selectedBookId: String?
    var isSaving = false
    var saveError: String?
    var saveResults: [String: Bool] = [:]
    var itunesResultsByBookId: [String: [ITunesCoverResult]] = [:]
    var searchingItunesBookIds: Set<String> = []
    var libraryTagNames: [String] = []
    var libraryCollections: [BookCollectionSummary] = []
    var libraryCollectionChoices: [CollectionChoice] = []
    var libraryCollectionNamesByUuid: [String: String] = [:]
    var deletedCollectionUuids: Set<String> = []

    var selectedBook: EditableBook? {
        get { books.first { $0.id == selectedBookId } }
        set {
            guard let newValue, let index = books.firstIndex(where: { $0.id == newValue.id }) else {
                return
            }
            books[index] = newValue
        }
    }

    func addBooks(ids: [String], from library: BookLibrary) {
        updateLibraryTags(from: library)
        updateLibraryCollections(from: library)

        for id in ids {
            guard !books.contains(where: { $0.id == id }) else { continue }
            guard let metadata = library.bookMetaData.first(where: { $0.uuid == id }) else {
                continue
            }
            books.append(EditableBook(from: metadata))
        }
        if selectedBookId == nil {
            selectedBookId = books.first?.id
        }
    }

    private func updateLibraryTags(from library: BookLibrary) {
        var tagsByKey: [String: String] = [:]
        for book in library.bookMetaData {
            for tag in book.tagNames {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                if tagsByKey[key] == nil {
                    tagsByKey[key] = trimmed
                }
            }
        }
        libraryTagNames = tagsByKey.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func updateLibraryCollections(from library: BookLibrary) {
        var collectionsByKey: [String: BookCollectionSummary] = [:]
        for book in library.bookMetaData {
            for collection in book.collections ?? [] {
                let key = collection.uuid ?? collection.name.lowercased()
                if collectionsByKey[key] == nil {
                    collectionsByKey[key] = collection
                }
            }
        }
        libraryCollections = collectionsByKey.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        rebuildLibraryCollectionCaches()
        deletedCollectionUuids.removeAll()
    }

    func createCollection(named name: String) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let created = await StorytellerActor.shared.createCollection(
            StorytellerCollectionCreatePayload(
                name: trimmed,
                description: "",
                isPublic: false,
                users: nil
            )
        )
        guard let created else { return nil }

        upsertLibraryCollection(
            uuid: created.uuid,
            name: created.name,
            description: created.description,
            isPublic: created.isPublic,
            importPath: created.importPath,
            createdAt: created.createdAt,
            updatedAt: created.updatedAt
        )
        deletedCollectionUuids.remove(created.uuid)
        await StorytellerActor.shared.fetchLibraryInformation()
        return created.uuid
    }

    func deleteCollection(uuid: String) async -> Bool {
        guard await StorytellerActor.shared.deleteCollection(uuid: uuid) else { return false }

        deletedCollectionUuids.insert(uuid)
        removeLibraryCollection(uuid: uuid)
        for index in books.indices {
            books[index].collectionUuids.removeAll { $0 == uuid }
        }
        await StorytellerActor.shared.fetchLibraryInformation()
        return true
    }

    private func upsertLibraryCollection(
        uuid: String,
        name: String,
        description: String?,
        isPublic: Bool?,
        importPath: String?,
        createdAt: String?,
        updatedAt: String?
    ) {
        let summary = BookCollectionSummary(
            uuid: uuid,
            name: name,
            description: description,
            isPublic: isPublic,
            importPath: importPath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        libraryCollections.removeAll { $0.uuid == uuid }
        libraryCollections.append(summary)
        rebuildLibraryCollectionCaches()
    }

    private func removeLibraryCollection(uuid: String) {
        libraryCollections.removeAll { $0.uuid == uuid }
        rebuildLibraryCollectionCaches()
    }

    private func rebuildLibraryCollectionCaches() {
        libraryCollections.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        libraryCollectionNamesByUuid = Dictionary(
            uniqueKeysWithValues: libraryCollections.compactMap { collection in
                guard let uuid = collection.uuid else { return nil }
                return (uuid, collection.name)
            }
        )
        libraryCollectionChoices = libraryCollections.enumerated().compactMap { index, collection in
            guard let uuid = collection.uuid else { return nil }
            return CollectionChoice(id: index, uuid: uuid, name: collection.name)
        }
    }

    func removeBook(id: String) {
        removeBooks(ids: [id])
    }

    func removeBooks(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let previousSelected = selectedBookId
        books.removeAll { ids.contains($0.id) }
        for id in ids {
            itunesResultsByBookId[id] = nil
            searchingItunesBookIds.remove(id)
        }

        if let previousSelected, !ids.contains(previousSelected),
            books.contains(where: { $0.id == previousSelected })
        {
            selectedBookId = previousSelected
        } else {
            selectedBookId = books.first?.id
        }
    }

    func clearTransientImportState() {
        itunesResultsByBookId.removeAll()
        searchingItunesBookIds.removeAll()
    }

    func markDirty(field: String, for bookId: String) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
        let book = books[index]
        let orig = book.originalMetadata

        let isChanged: Bool
        switch field {
        case "title": isChanged = book.title != orig.title
        case "subtitle": isChanged = book.subtitle != (orig.subtitle ?? "")
        case "description": isChanged = book.description != (orig.description ?? "")
        case "language": isChanged = book.language != (orig.language ?? "")
        case "publicationDate":
            isChanged = book.publicationDate != (EditableBook.dateOnly(orig.publicationDate) ?? "")
        case "rating": isChanged = book.rating != (orig.rating.map { String($0) } ?? "")
        case "authors":
            isChanged = book.authors != (orig.authors?.compactMap { $0.name } ?? [])
        case "narrators":
            isChanged = book.narrators != (orig.narrators?.compactMap { $0.name } ?? [])
        case "tags":
            isChanged = Set(book.tags) != Set(orig.tags?.map { $0.name } ?? [])
        case "creators":
            let origCreators = orig.creators ?? []
            if book.creators.count != origCreators.count {
                isChanged = true
            } else {
                isChanged = zip(book.creators, origCreators).contains { edited, original in
                    edited.name != (original.name ?? "")
                        || edited.role != (original.role ?? "")
                        || edited.fileAs != (original.fileAs ?? "")
                }
            }
        case "series":
            let origSeries = orig.series ?? []
            if book.series.count != origSeries.count {
                isChanged = true
            } else {
                isChanged = zip(book.series, origSeries).contains { edited, original in
                    edited.name != original.name
                        || edited.position != (original.position.map {
                            $0.truncatingRemainder(dividingBy: 1) == 0
                                ? String(Int($0)) : String($0)
                        } ?? "")
                        || edited.featured != (original.featured == 1)
                }
            }
        case "collections":
            isChanged = book.collectionUuids != (orig.collections?.compactMap { $0.uuid } ?? [])
        default:
            isChanged = true
        }

        if isChanged {
            books[index].dirtyFields.insert(field)
        } else {
            books[index].dirtyFields.remove(field)
        }
    }

    func isDirty(field: String, for bookId: String) -> Bool {
        books.first { $0.id == bookId }?.dirtyFields.contains(field) ?? false
    }

    var hasAnyDirtyBooks: Bool {
        books.contains { $0.hasDirtyFields }
    }

    struct ValidationError {
        let field: String
        let message: String
    }

    func validationErrors(for bookId: String) -> [ValidationError] {
        guard let book = books.first(where: { $0.id == bookId }) else { return [] }
        var errors: [ValidationError] = []

        if book.dirtyFields.contains("title") && book.title.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(ValidationError(field: "title", message: "Title cannot be empty"))
        }

        for (index, series) in book.series.enumerated() {
            let pos = series.position.trimmingCharacters(in: .whitespaces)
            if !pos.isEmpty && Double(pos) == nil {
                errors.append(ValidationError(
                    field: "series.\(index).position",
                    message: "Series position '\(pos)' is not a number"
                ))
            }
        }

        let ratingStr = book.rating.trimmingCharacters(in: .whitespaces)
        if book.dirtyFields.contains("rating") && !ratingStr.isEmpty && Double(ratingStr) == nil {
            errors.append(ValidationError(field: "rating", message: "Invalid rating"))
        }

        if book.dirtyFields.contains("publicationDate") {
            let pubDate = book.publicationDate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pubDate.isEmpty {
                let dateRegex = /^\d{4}-\d{2}-\d{2}$/
                let fullFmt = ISO8601DateFormatter()
                fullFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let isValidDate = pubDate.wholeMatch(of: dateRegex) != nil
                let isValidFull = fullFmt.date(from: pubDate) != nil
                if !isValidDate && !isValidFull {
                    errors.append(ValidationError(
                        field: "publicationDate",
                        message: "Publication date must be yyyy-mm-dd format"
                    ))
                }
            }
        }

        return errors
    }

    func hasValidationErrors(for bookId: String) -> Bool {
        !validationErrors(for: bookId).isEmpty
    }

    var hasAnyValidationErrors: Bool {
        books.contains { hasValidationErrors(for: $0.id) }
    }

    func fieldHasError(_ field: String, for bookId: String) -> Bool {
        validationErrors(for: bookId).contains { $0.field == field }
    }

    func seriesPositionHasError(bookId: String, seriesId: UUID) -> Bool {
        guard let book = books.first(where: { $0.id == bookId }),
            let index = book.series.firstIndex(where: { $0.id == seriesId })
        else { return false }
        return validationErrors(for: bookId).contains { $0.field == "series.\(index).position" }
    }

    private func coverUploads(for book: EditableBook) -> (text: StorytellerCoverUpload?, audio: StorytellerCoverUpload?) {
        let text = book.replacementEbookCover.map {
            StorytellerCoverUpload(filename: $0.filename, data: $0.data, contentType: nil)
        }
        let audio = book.replacementAudiobookCover.map {
            StorytellerCoverUpload(filename: $0.filename, data: $0.data, contentType: nil)
        }
        return (text, audio)
    }

    func buildPayload(for book: EditableBook) -> StorytellerBookUpdatePayload? {
        guard book.hasDirtyFields else { return nil }
        var payload = StorytellerBookUpdatePayload(uuid: book.id)

        if book.dirtyFields.contains("title") {
            payload.title = book.title
        }
        if book.dirtyFields.contains("subtitle") {
            payload.subtitle = book.subtitle
        }
        if book.dirtyFields.contains("description") {
            payload.description = book.description
        }
        if book.dirtyFields.contains("language") {
            payload.language = book.language
        }
        if book.dirtyFields.contains("publicationDate") {
            let trimmed = book.publicationDate.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                payload.publicationDate = .null
            } else if trimmed.contains("T") {
                payload.publicationDate = .value(trimmed)
            } else {
                payload.publicationDate = .value(trimmed + "T12:00:00.000Z")
            }
        }
        if book.dirtyFields.contains("rating") {
            let trimmed = book.rating.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                payload.rating = .null
            } else if let rating = Double(trimmed) {
                payload.rating = .value(rating)
            } else {
                saveError = "Invalid rating: \(trimmed)"
                return nil
            }
        }
        let anyCreatorFieldDirty = !book.dirtyFields.isDisjoint(
            with: ["authors", "narrators", "creators"])
        if anyCreatorFieldDirty {
            payload.authors = book.authors.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            payload.narrators = book.narrators.filter {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
            var originalCreatorNamesByUuid: [String: String] = [:]
            for creator in book.originalMetadata.creators ?? [] {
                guard let uuid = creator.uuid else { continue }
                originalCreatorNamesByUuid[uuid] = creator.name ?? ""
            }
            payload.creators = book.creators.compactMap { creator in
                let name = creator.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                let role = creator.role.trimmingCharacters(in: .whitespaces)
                guard !role.isEmpty && role != "Role" else { return nil }
                let originalName = creator.uuid.flatMap { originalCreatorNamesByUuid[$0] } ?? ""
                let uuid = originalName == name ? creator.uuid : nil
                return StorytellerCreatorRelationUpdate(
                    uuid: uuid,
                    id: nil,
                    name: name,
                    fileAs: creator.fileAs.isEmpty ? name : creator.fileAs,
                    role: role
                )
            }
        }
        if book.dirtyFields.contains("series") {
            var originalSeriesNamesByUuid: [String: String] = [:]
            for series in book.originalMetadata.series ?? [] {
                guard let uuid = series.uuid else { continue }
                originalSeriesNamesByUuid[uuid] = series.name
            }
            payload.series = book.series.compactMap { s in
                let name = s.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                let originalName = s.uuid.flatMap { originalSeriesNamesByUuid[$0] } ?? ""
                let uuid = originalName == name ? s.uuid : nil
                return StorytellerSeriesRelationUpdate(
                    uuid: uuid,
                    name: name,
                    featured: s.featured,
                    position: Double(s.position)
                )
            }
        }
        if book.dirtyFields.contains("tags") {
            payload.tags = book.tags.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        if book.dirtyFields.contains("collections") {
            payload.collections = book.collectionUuids
        }

        return payload
    }

    func saveAll(mediaViewModel: MediaViewModel) async {
        isSaving = true
        saveError = nil
        saveResults = [:]

        for book in books where book.hasDirtyFields {
            let result = await saveBook(book)
            if let updatedMetadata = result.metadata {
                saveResults[book.id] = true
                if let index = books.firstIndex(where: { $0.id == book.id }) {
                    books[index].originalMetadata = updatedMetadata
                    if result.metadataSaved {
                        books[index].dirtyFields.removeAll()
                    }
                    if result.coversSaved {
                        books[index].replacementEbookCover = nil
                        books[index].replacementAudiobookCover = nil
                    }
                }
                await refreshSavedCovers(
                    result: result,
                    metadata: updatedMetadata,
                    mediaViewModel: mediaViewModel
                )
            } else {
                saveResults[book.id] = false
                let serverError = await StorytellerActor.shared.lastUpdateBookError
                saveError =
                    "\(book.displayTitle): \(serverError ?? "Unknown error")"
            }
        }

        await StorytellerActor.shared.fetchLibraryInformation()
        isSaving = false
    }

    func saveSingle(_ bookId: String, mediaViewModel: MediaViewModel) async {
        guard let book = books.first(where: { $0.id == bookId }),
            book.hasDirtyFields
        else { return }

        isSaving = true
        saveError = nil

        let result = await saveBook(book)
        if let updatedMetadata = result.metadata {
            saveResults[bookId] = true
            if let index = books.firstIndex(where: { $0.id == bookId }) {
                books[index].originalMetadata = updatedMetadata
                if result.metadataSaved {
                    books[index].dirtyFields.removeAll()
                }
                if result.coversSaved {
                    books[index].replacementEbookCover = nil
                    books[index].replacementAudiobookCover = nil
                }
            }
            await refreshSavedCovers(
                result: result,
                metadata: updatedMetadata,
                mediaViewModel: mediaViewModel
            )
        } else {
            saveResults[bookId] = false
            let serverError = await StorytellerActor.shared.lastUpdateBookError
            saveError =
                "\(book.displayTitle): \(serverError ?? "Unknown error")"
        }

        await StorytellerActor.shared.fetchLibraryInformation()
        isSaving = false
    }

    private struct SaveBookResult {
        let metadata: BookMetadata?
        let metadataSaved: Bool
        let textCoverSaved: Bool
        let audioCoverSaved: Bool

        var coversSaved: Bool {
            textCoverSaved || audioCoverSaved
        }
    }

    private func saveBook(_ book: EditableBook) async -> SaveBookResult {
        let covers = coverUploads(for: book)
        let hasMetadataChanges = !book.dirtyFields.isEmpty

        let payload = buildPayload(for: book) ?? StorytellerBookUpdatePayload(uuid: book.id)
        let result = await StorytellerActor.shared.updateBook(
            payload,
            textCover: covers.text,
            audioCover: covers.audio
        )
        return SaveBookResult(
            metadata: result,
            metadataSaved: hasMetadataChanges && result != nil,
            textCoverSaved: covers.text != nil && result != nil,
            audioCoverSaved: covers.audio != nil && result != nil
        )
    }

    private func refreshSavedCovers(
        result: SaveBookResult,
        metadata: BookMetadata,
        mediaViewModel: MediaViewModel
    ) async {
        guard result.coversSaved else { return }

        if metadata.hasAvailableEbook {
            await mediaViewModel.refreshCover(for: metadata, variant: .standard)
        }
        if metadata.hasAvailableAudiobook {
            await mediaViewModel.refreshCover(for: metadata, variant: .audioSquare)
        }
    }

    // MARK: - Hardcover Import

    func applyImport(
        imports: [HardcoverImportSource: HardcoverBookDetails],
        fields: Set<String>,
        for bookId: String
    ) {
        guard !imports.isEmpty else { return }
        for (source, details) in imports {
            applyImport(details: details, source: source, fields: fields, for: bookId)
        }
    }

    func applyImport(
        details: HardcoverBookDetails,
        source: HardcoverImportSource = .text,
        fields: Set<String>,
        for bookId: String
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }

        let allFields: Set<String> = [
            "title", "subtitle", "description", "language", "publicationDate",
            "rating", "authors", "narrators", "creators", "series", "tags",
        ]
        books[index].hardcoverImports[source] = details
        books[index].hardcoverImportFields[source] = allFields

        let shouldApplyToCurrent = { (field: String) -> Bool in
            fields.contains(field) && Self.defaultHardcoverSource(for: field) == source
        }

        if shouldApplyToCurrent("title"), let value = details.title, !value.isEmpty,
            value != books[index].title
        {
            books[index].title = value
            books[index].importedFields.insert("title")
            markDirty(field: "title", for: bookId)
        }
        if shouldApplyToCurrent("subtitle"), let value = details.subtitle, !value.isEmpty,
            value != books[index].subtitle
        {
            books[index].subtitle = value
            books[index].importedFields.insert("subtitle")
            markDirty(field: "subtitle", for: bookId)
        }
        if shouldApplyToCurrent("description"), let value = details.description, !value.isEmpty,
            value != books[index].description
        {
            books[index].description = value
            books[index].importedFields.insert("description")
            markDirty(field: "description", for: bookId)
        }
        if shouldApplyToCurrent("language"), let value = details.language, !value.isEmpty {
            let code = Self.languageNameToCode(value)
            if code != books[index].language {
                books[index].language = code
                books[index].importedFields.insert("language")
                markDirty(field: "language", for: bookId)
            }
        }
        if shouldApplyToCurrent("publicationDate"), let value = details.releaseDate, !value.isEmpty {
            let dateOnly = EditableBook.dateOnly(value) ?? value
            if dateOnly != books[index].publicationDate {
                books[index].publicationDate = dateOnly
                books[index].importedFields.insert("publicationDate")
                markDirty(field: "publicationDate", for: bookId)
            }
        }
        if shouldApplyToCurrent("rating"), let value = details.rating {
            let ratingStr = String(format: "%.2f", value)
            if ratingStr != books[index].rating {
                books[index].rating = ratingStr
                books[index].importedFields.insert("rating")
                markDirty(field: "rating", for: bookId)
            }
        }

        if shouldApplyToCurrent("authors") && !details.authors.isEmpty {
            var seen = Set(books[index].authors.map { $0.lowercased() })
            var imported = Set<String>()
            for author in details.authors {
                guard !seen.contains(author.lowercased()) else { continue }
                seen.insert(author.lowercased())
                books[index].authors.append(author)
                imported.insert(author)
            }
            if !imported.isEmpty {
                books[index].importedItems["authors", default: []].formUnion(imported)
                markDirty(field: "authors", for: bookId)
            }
        }

        if shouldApplyToCurrent("narrators") && !details.narrators.isEmpty {
            var seen = Set(books[index].narrators.map { $0.lowercased() })
            var imported = Set<String>()
            for narrator in details.narrators {
                guard !seen.contains(narrator.lowercased()) else { continue }
                seen.insert(narrator.lowercased())
                books[index].narrators.append(narrator)
                imported.insert(narrator)
            }
            if !imported.isEmpty {
                books[index].importedItems["narrators", default: []].formUnion(imported)
                markDirty(field: "narrators", for: bookId)
            }
        }

        if shouldApplyToCurrent("creators") && !details.creators.isEmpty {
            var seenKeys = Set(
                books[index].creators.map {
                    "\($0.name.lowercased())|\($0.role.lowercased())"
                })
            var imported = Set<String>()
            for creator in details.creators {
                let key = "\(creator.name.lowercased())|\(creator.role.lowercased())"
                guard !seenKeys.contains(key) else { continue }
                seenKeys.insert(key)
                books[index].creators.append(
                    EditableCreator(
                        name: creator.name,
                        fileAs: "",
                        role: creator.role
                    ))
                imported.insert(creator.name)
            }
            if !imported.isEmpty {
                books[index].importedItems["creators", default: []].formUnion(imported)
                markDirty(field: "creators", for: bookId)
            }
        }

        if shouldApplyToCurrent("series") && !details.series.isEmpty {
            var seenNames = Set(
                books[index].series.map { $0.name.lowercased() })
            var imported = Set<String>()
            var updated = false
            for s in details.series {
                if seenNames.contains(s.name.lowercased()) {
                    if let existingIdx = books[index].series.firstIndex(where: {
                        $0.name.lowercased() == s.name.lowercased()
                    }) {
                        if let pos = s.position {
                            let posStr =
                                pos.truncatingRemainder(dividingBy: 1) == 0
                                ? String(Int(pos)) : String(pos)
                            if books[index].series[existingIdx].position != posStr {
                                books[index].series[existingIdx].position = posStr
                                updated = true
                            }
                        }
                        if books[index].series[existingIdx].featured != s.featured {
                            books[index].series[existingIdx].featured = s.featured
                            updated = true
                        }
                    }
                } else {
                    seenNames.insert(s.name.lowercased())
                    let posStr: String = s.position.map {
                        $0.truncatingRemainder(dividingBy: 1) == 0
                            ? String(Int($0)) : String($0)
                    } ?? ""
                    books[index].series.append(
                        EditableSeries(
                            name: s.name,
                            position: posStr,
                            featured: s.featured
                        ))
                    imported.insert(s.name)
                }
            }
            if !imported.isEmpty {
                books[index].importedItems["series", default: []].formUnion(imported)
            }
            if !imported.isEmpty || updated {
                markDirty(field: "series", for: bookId)
            }
        }

        if shouldApplyToCurrent("tags") && !details.tags.isEmpty {
            let tagNames = details.tags.map(\.name)
            books[index].tags = tagNames
            books[index].importedItems["tags"] = Set(tagNames)
            markDirty(field: "tags", for: bookId)
        }
    }

    static func defaultHardcoverSource(for field: String) -> HardcoverImportSource {
        field == "narrators" ? .audiobook : .text
    }

    private static func languageNameToCode(_ name: String) -> String {
        let target = name.lowercased()
        let english = Locale(identifier: "en")
        for code in Locale.isoLanguageCodes {
            if let localized = english.localizedString(forLanguageCode: code),
                localized.lowercased() == target
            {
                return code
            }
        }
        return name
    }

    func isImportedField(_ field: String, for bookId: String) -> Bool {
        guard let book = books.first(where: { $0.id == bookId }) else { return false }
        return book.importedFields.contains(field)
    }

    func isImported(field: String, value: String, for bookId: String) -> Bool {
        guard let book = books.first(where: { $0.id == bookId }) else { return false }
        return book.importedItems[field]?.contains(value) ?? false
    }

    // MARK: - Hardcover Accessors

    func hasHardcoverImport(
        field: String,
        for bookId: String,
        source: HardcoverImportSource? = nil
    ) -> Bool {
        guard let book = books.first(where: { $0.id == bookId }) else { return false }
        let resolvedSource = source ?? Self.defaultHardcoverSource(for: field)
        return book.hardcoverImports[resolvedSource] != nil
            && book.hardcoverImportFields[resolvedSource]?.contains(field) == true
    }

    private func hardcoverDetails(
        field: String,
        for bookId: String,
        source: HardcoverImportSource? = nil
    ) -> HardcoverBookDetails? {
        guard let book = books.first(where: { $0.id == bookId }),
              let details = book.hardcoverImports[source ?? Self.defaultHardcoverSource(for: field)],
              book.hardcoverImportFields[source ?? Self.defaultHardcoverSource(for: field)]?.contains(field) == true
        else { return nil }
        return details
    }

    func hasHardcoverValue(
        field: String,
        for bookId: String,
        source: HardcoverImportSource? = nil
    ) -> Bool {
        guard let details = hardcoverDetails(field: field, for: bookId, source: source) else {
            return false
        }
        switch field {
        case "title": return details.title != nil && !details.title!.isEmpty
        case "subtitle": return details.subtitle != nil && !details.subtitle!.isEmpty
        case "description": return details.description != nil && !details.description!.isEmpty
        case "language": return details.language != nil && !details.language!.isEmpty
        case "publicationDate": return details.releaseDate != nil && !details.releaseDate!.isEmpty
        case "rating": return details.rating != nil
        case "authors": return !details.authors.isEmpty
        case "narrators": return !details.narrators.isEmpty
        case "creators": return !details.creators.isEmpty
        case "series": return !details.series.isEmpty
        case "tags": return !details.tags.isEmpty
        default: return false
        }
    }

    func hardcoverScalarValue(
        field: String,
        for bookId: String,
        source: HardcoverImportSource? = nil
    ) -> String? {
        guard let details = hardcoverDetails(field: field, for: bookId, source: source) else {
            return nil
        }
        switch field {
        case "title": return details.title
        case "subtitle": return details.subtitle
        case "description": return details.description
        case "language":
            if let lang = details.language { return Self.languageNameToCode(lang) }
            return nil
        case "publicationDate":
            if let date = details.releaseDate { return EditableBook.dateOnly(date) ?? date }
            return nil
        case "rating":
            return details.rating.map { String(format: "%.2f", $0) }
        default: return nil
        }
    }

    func importPublicationDateFromHardcoverSource(
        _ source: HardcoverImportSource,
        for bookId: String
    ) {
        revertToHardcover(field: "publicationDate", for: bookId, source: source)
    }

    func importFirstAvailableHardcoverPublicationDate(for bookId: String) {
        let current = books.first { $0.id == bookId }?.publicationDate ?? ""
        for source in [HardcoverImportSource.text, .audiobook] {
            guard let value = hardcoverScalarValue(
                field: "publicationDate",
                for: bookId,
                source: source
            ), value != current else { continue }
            importPublicationDateFromHardcoverSource(source, for: bookId)
            return
        }
    }

    func rawHardcoverDataDump(for bookId: String) -> String {
        guard let book = books.first(where: { $0.id == bookId }) else {
            return "No book selected."
        }
        guard !book.hardcoverImports.isEmpty else {
            return "No Hardcover data has been imported for this book."
        }

        var parts: [String] = []
        parts.append("Hardcover imported data for \(book.displayTitle)")

        for source in HardcoverImportSource.allCases {
            guard let details = book.hardcoverImports[source] else { continue }
            parts.append("\n\n=== \(source.label) ===")
            if let rawJSON = details.rawJSON {
                parts.append(rawJSON)
            } else {
                parts.append(Self.fallbackHardcoverDump(details))
            }
        }

        return parts.joined(separator: "\n")
    }

    private static func fallbackHardcoverDump(_ details: HardcoverBookDetails) -> String {
        var lines: [String] = []
        func row(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            lines.append("\(name): \(value)")
        }
        row("Title", details.title)
        row("Subtitle", details.subtitle)
        row("Description", details.description)
        row("Release Date", details.releaseDate)
        row("Language", details.language)
        if let rating = details.rating { lines.append("Rating: \(rating)") }
        if !details.authors.isEmpty {
            lines.append("Authors: \(details.authors.joined(separator: ", "))")
        }
        if !details.narrators.isEmpty {
            lines.append("Narrators: \(details.narrators.joined(separator: ", "))")
        }
        if !details.creators.isEmpty {
            let creators = details.creators.map { "\($0.name) (\($0.role))" }
            lines.append("Creators: \(creators.joined(separator: ", "))")
        }
        if !details.series.isEmpty {
            lines.append("Series: \(details.series.map(\.name).joined(separator: ", "))")
        }
        if !details.tags.isEmpty {
            let tags = details.tags.map { "\($0.name) [\($0.count)]" }
            lines.append("Tags: \(tags.joined(separator: ", "))")
        }
        if !details.editions.isEmpty {
            lines.append("\nEditions:")
            for edition in details.editions {
                lines.append("- \(edition.id): \(edition.title ?? "(untitled)")")
                row("  Format", edition.format)
                row("  Edition Info", edition.editionInfo)
                row("  Release Date", edition.releaseDate)
                row("  Language", edition.language)
                row("  Publisher", edition.publisher)
                row("  ISBN-13", edition.isbn13)
                row("  ISBN-10", edition.isbn10)
                row("  ASIN", edition.asin)
            }
        }
        return lines.joined(separator: "\n")
    }

    func hardcoverStringList(
        field: String,
        for bookId: String,
        source: HardcoverImportSource? = nil
    ) -> [String]? {
        guard let details = hardcoverDetails(field: field, for: bookId, source: source) else {
            return nil
        }
        switch field {
        case "authors": return details.authors.isEmpty ? nil : details.authors
        case "narrators": return details.narrators.isEmpty ? nil : details.narrators
        case "creators": return details.creators.isEmpty ? nil : details.creators.map { "\($0.name) (\($0.role))" }
        case "tags": return details.tags.isEmpty ? nil : details.tags.map(\.name)
        default: return nil
        }
    }

    func revertToHardcover(
        field: String,
        for bookId: String,
        source: HardcoverImportSource? = nil
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookId }),
              let details = hardcoverDetails(field: field, for: bookId, source: source)
        else { return }

        switch field {
        case "title":
            if let value = details.title, !value.isEmpty {
                books[index].title = value
                books[index].importedFields.insert("title")
                markDirty(field: "title", for: bookId)
            }
        case "subtitle":
            if let value = details.subtitle, !value.isEmpty {
                books[index].subtitle = value
                books[index].importedFields.insert("subtitle")
                markDirty(field: "subtitle", for: bookId)
            }
        case "description":
            if let value = details.description, !value.isEmpty {
                books[index].description = value
                books[index].importedFields.insert("description")
                markDirty(field: "description", for: bookId)
            }
        case "language":
            if let value = details.language, !value.isEmpty {
                books[index].language = Self.languageNameToCode(value)
                books[index].importedFields.insert("language")
                markDirty(field: "language", for: bookId)
            }
        case "publicationDate":
            if let value = details.releaseDate, !value.isEmpty {
                books[index].publicationDate = EditableBook.dateOnly(value) ?? value
                books[index].importedFields.insert("publicationDate")
                markDirty(field: "publicationDate", for: bookId)
            }
        case "rating":
            if let value = details.rating {
                books[index].rating = String(format: "%.2f", value)
                books[index].importedFields.insert("rating")
                markDirty(field: "rating", for: bookId)
            }
        case "authors":
            books[index].authors = details.authors
            books[index].importedFields.insert("authors")
            books[index].importedItems["authors"] = Set(details.authors)
            markDirty(field: "authors", for: bookId)
        case "narrators":
            books[index].narrators = details.narrators
            books[index].importedFields.insert("narrators")
            books[index].importedItems["narrators"] = Set(details.narrators)
            markDirty(field: "narrators", for: bookId)
        case "creators":
            books[index].creators = details.creators.map {
                EditableCreator(name: $0.name, fileAs: "", role: $0.role, uuid: nil)
            }
            books[index].importedFields.insert("creators")
            books[index].importedItems["creators"] = Set(details.creators.map(\.name))
            markDirty(field: "creators", for: bookId)
        case "series":
            books[index].series = details.series.map { series in
                let posStr = series.position.map {
                    $0.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int($0)) : String($0)
                } ?? ""
                return EditableSeries(
                    name: series.name,
                    position: posStr,
                    featured: series.featured,
                    uuid: nil
                )
            }
            books[index].importedFields.insert("series")
            books[index].importedItems["series"] = Set(details.series.map(\.name))
            markDirty(field: "series", for: bookId)
        case "tags":
            let tagNames = details.tags.map(\.name)
            books[index].tags = tagNames
            books[index].importedFields.insert("tags")
            books[index].importedItems["tags"] = Set(tagNames)
            markDirty(field: "tags", for: bookId)
        default:
            break
        }
    }

    func revertFieldToOriginal(field: String, for bookId: String) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
        let orig = books[index].originalMetadata

        switch field {
        case "title":
            books[index].title = orig.title
        case "subtitle":
            books[index].subtitle = orig.subtitle ?? ""
        case "description":
            books[index].description = orig.description ?? ""
        case "language":
            books[index].language = orig.language ?? ""
        case "publicationDate":
            books[index].publicationDate = EditableBook.dateOnly(orig.publicationDate) ?? ""
        case "rating":
            books[index].rating = orig.rating.map { String($0) } ?? ""
        case "authors":
            books[index].authors = orig.authors?.compactMap { $0.name } ?? []
        case "narrators":
            books[index].narrators = orig.narrators?.compactMap { $0.name } ?? []
        case "creators":
            books[index].creators = orig.creators?.map { creator in
                EditableCreator(
                    name: creator.name ?? "",
                    fileAs: creator.fileAs ?? "",
                    role: creator.role ?? "",
                    uuid: creator.uuid
                )
            } ?? []
        case "series":
            books[index].series = orig.series?.map { s in
                EditableSeries(
                    name: s.name,
                    position: s.position.map {
                        $0.truncatingRemainder(dividingBy: 1) == 0
                            ? String(Int($0)) : String($0)
                    } ?? "",
                    featured: s.featured == 1,
                    uuid: s.uuid
                )
            } ?? []
        case "tags":
            books[index].tags = orig.tags?.map { $0.name } ?? []
        default:
            break
        }

        books[index].dirtyFields.remove(field)
        books[index].importedFields.remove(field)
        books[index].importedItems[field] = nil
    }

    func revertAllFields(for bookId: String) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
        let orig = books[index].originalMetadata
        books[index].title = orig.title
        books[index].subtitle = orig.subtitle ?? ""
        books[index].description = orig.description ?? ""
        books[index].language = orig.language ?? ""
        books[index].publicationDate = EditableBook.dateOnly(orig.publicationDate) ?? ""
        books[index].rating = orig.rating.map { String($0) } ?? ""
        books[index].authors = orig.authors?.compactMap { $0.name } ?? []
        books[index].narrators = orig.narrators?.compactMap { $0.name } ?? []
        books[index].creators = orig.creators?.map { creator in
            EditableCreator(
                name: creator.name ?? "",
                fileAs: creator.fileAs ?? "",
                role: creator.role ?? "",
                uuid: creator.uuid
            )
        } ?? []
        books[index].series = orig.series?.map { s in
            EditableSeries(
                name: s.name,
                position: s.position.map {
                    $0.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int($0)) : String($0)
                } ?? "",
                featured: s.featured == 1,
                uuid: s.uuid
            )
        } ?? []
        books[index].tags = orig.tags?.map { $0.name } ?? []
        books[index].collectionUuids = orig.collections?.compactMap { $0.uuid } ?? []
        books[index].dirtyFields.removeAll()
        books[index].importedFields.removeAll()
        books[index].importedItems.removeAll()
        books[index].replacementEbookCover = nil
        books[index].replacementAudiobookCover = nil
    }

    func importTags(_ tags: [String], for bookId: String, fromHardcover: Bool = false) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
        var seen = Set(books[index].tags.map { $0.lowercased() })
        var imported = Set<String>()
        for tag in tags {
            guard !seen.contains(tag.lowercased()) else { continue }
            seen.insert(tag.lowercased())
            books[index].tags.append(tag)
            imported.insert(tag)
        }
        if !imported.isEmpty {
            if fromHardcover {
                books[index].importedItems["tags", default: []].formUnion(imported)
            }
            markDirty(field: "tags", for: bookId)
        }
    }

    func hardcoverTagsWithCounts(
        for bookId: String,
        source: HardcoverImportSource = .text
    ) -> [HardcoverTagInfo]? {
        guard let details = hardcoverDetails(field: "tags", for: bookId, source: source),
              !details.tags.isEmpty
        else { return nil }
        return details.tags
    }

    func originalScalarValue(field: String, for bookId: String) -> String {
        guard let book = books.first(where: { $0.id == bookId }) else { return "" }
        let orig = book.originalMetadata
        switch field {
        case "title": return orig.title
        case "subtitle": return orig.subtitle ?? ""
        case "description": return orig.description ?? ""
        case "language": return orig.language ?? ""
        case "publicationDate":
            return EditableBook.dateOnly(orig.publicationDate) ?? ""
        case "rating": return orig.rating.map { String($0) } ?? ""
        default: return ""
        }
    }

    func originalStringList(field: String, for bookId: String) -> [String] {
        guard let book = books.first(where: { $0.id == bookId }) else { return [] }
        let orig = book.originalMetadata
        switch field {
        case "authors": return orig.authors?.compactMap { $0.name } ?? []
        case "narrators": return orig.narrators?.compactMap { $0.name } ?? []
        case "tags": return orig.tags?.map { $0.name } ?? []
        default: return []
        }
    }

    // MARK: - iTunes Search

    func itunesResults(for bookId: String) -> [ITunesCoverResult] {
        itunesResultsByBookId[bookId] ?? []
    }

    func isSearchingItunes(for bookId: String) -> Bool {
        searchingItunesBookIds.contains(bookId)
    }

    func clearItunesResults(for bookId: String) {
        itunesResultsByBookId[bookId] = nil
    }

    func searchItunes(book: EditableBook) {
        let bookId = book.id
        searchingItunesBookIds.insert(bookId)
        itunesResultsByBookId[bookId] = []
        Task {
            defer { searchingItunesBookIds.remove(bookId) }
            do {
                itunesResultsByBookId[bookId] = try await ITunesSearchActor.search(
                    title: book.title,
                    author: book.authors.first
                )
            } catch {
                debugLog("[MetadataEditor] iTunes search failed: \(error)")
            }
        }
    }

    // MARK: - Auto Import All

    var isAutoImporting = false
    var autoImportProgress: (current: Int, total: Int) = (0, 0)
    var autoImportError: String?

    func autoImportAll(fields: Set<String>) async {
        isAutoImporting = true
        autoImportError = nil
        let total = books.count
        autoImportProgress = (0, total)

        for (i, book) in books.enumerated() {
            autoImportProgress = (i, total)

            var query = book.title
            if let author = book.authors.first, !author.isEmpty {
                query += " \(author)"
            }

            do {
                let results = try await HardcoverActor.shared.searchBooks(query: query)
                guard let first = results.first else { continue }
                let details = try await HardcoverActor.shared.fetchBookDetails(id: first.id)
                applyImport(details: details, fields: fields, for: book.id)
            } catch {
                autoImportError = "\(book.displayTitle): \(error.localizedDescription)"
            }
        }

        autoImportProgress = (total, total)
        isAutoImporting = false
    }
}
