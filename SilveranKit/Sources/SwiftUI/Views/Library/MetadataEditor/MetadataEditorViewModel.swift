import Foundation
import SwiftUI

@MainActor
@Observable
final class MetadataEditorViewModel {
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
        var statusUuid: String?
        var authors: [String]
        var narrators: [String]
        var creators: [EditableCreator]
        var series: [EditableSeries]
        var tags: [String]
        var collectionUuids: [String]

        var dirtyFields: Set<String> = []
        var importedFields: Set<String> = []
        var importedItems: [String: Set<String>] = [:]

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
            self.statusUuid = metadata.status?.uuid
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

        var hasDirtyFields: Bool { !dirtyFields.isEmpty }

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
    }

    var books: [EditableBook] = []
    var selectedBookId: String?
    var isSaving = false
    var saveError: String?
    var saveResults: [String: Bool] = [:]

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

    func removeBook(id: String) {
        removeBooks(ids: [id])
    }

    func removeBooks(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let previousSelected = selectedBookId
        books.removeAll { ids.contains($0.id) }

        if let previousSelected, !ids.contains(previousSelected),
            books.contains(where: { $0.id == previousSelected })
        {
            selectedBookId = previousSelected
        } else {
            selectedBookId = books.first?.id
        }
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
        case "status": isChanged = book.statusUuid != orig.status?.uuid
        case "authors":
            isChanged = book.authors != (orig.authors?.compactMap { $0.name } ?? [])
        case "narrators":
            isChanged = book.narrators != (orig.narrators?.compactMap { $0.name } ?? [])
        case "tags":
            isChanged = book.tags != (orig.tags?.map { $0.name } ?? [])
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
                payload.publicationDate = .value(trimmed + "T00:00:00.000Z")
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
        if book.dirtyFields.contains("status") {
            if let statusUuid = book.statusUuid, !statusUuid.isEmpty {
                payload.status = statusUuid
            } else {
                if let index = books.firstIndex(where: { $0.id == book.id }) {
                    books[index].dirtyFields.remove("status")
                }
            }
        }

        let anyCreatorFieldDirty = !book.dirtyFields.isDisjoint(
            with: ["authors", "narrators", "creators"])
        if anyCreatorFieldDirty {
            payload.authors = book.authors.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            payload.narrators = book.narrators.filter {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            }
            payload.creators = book.creators.compactMap { creator in
                let name = creator.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                return StorytellerCreatorRelationUpdate(
                    uuid: creator.uuid,
                    id: nil,
                    name: name,
                    fileAs: creator.fileAs.isEmpty ? name : creator.fileAs,
                    role: creator.role.isEmpty ? nil : creator.role
                )
            }
        }
        if book.dirtyFields.contains("series") {
            payload.series = book.series.compactMap { s in
                let name = s.name.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return nil }
                return StorytellerSeriesRelationUpdate(
                    uuid: s.uuid,
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

    func saveAll() async {
        isSaving = true
        saveError = nil
        saveResults = [:]

        for book in books where book.hasDirtyFields {
            guard let payload = buildPayload(for: book) else { continue }
            let result = await StorytellerActor.shared.updateBook(payload)
            if let updatedMetadata = result {
                saveResults[book.id] = true
                if let index = books.firstIndex(where: { $0.id == book.id }) {
                    books[index].dirtyFields.removeAll()
                    books[index].originalMetadata = updatedMetadata
                }
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

    func saveSingle(_ bookId: String) async {
        guard let book = books.first(where: { $0.id == bookId }),
            let payload = buildPayload(for: book)
        else { return }

        isSaving = true
        saveError = nil

        let result = await StorytellerActor.shared.updateBook(payload)
        if let updatedMetadata = result {
            saveResults[bookId] = true
            if let index = books.firstIndex(where: { $0.id == bookId }) {
                books[index].dirtyFields.removeAll()
                books[index].originalMetadata = updatedMetadata
            }
        } else {
            saveResults[bookId] = false
            let serverError = await StorytellerActor.shared.lastUpdateBookError
            saveError =
                "\(book.displayTitle): \(serverError ?? "Unknown error")"
        }

        await StorytellerActor.shared.fetchLibraryInformation()
        isSaving = false
    }

    // MARK: - Hardcover Import

    func applyImport(details: HardcoverBookDetails, fields: Set<String>, for bookId: String) {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }

        if fields.contains("title"), let value = details.title, !value.isEmpty,
            value != books[index].title
        {
            books[index].title = value
            books[index].importedFields.insert("title")
            markDirty(field: "title", for: bookId)
        }
        if fields.contains("subtitle"), let value = details.subtitle, !value.isEmpty,
            value != books[index].subtitle
        {
            books[index].subtitle = value
            books[index].importedFields.insert("subtitle")
            markDirty(field: "subtitle", for: bookId)
        }
        if fields.contains("description"), let value = details.description, !value.isEmpty,
            value != books[index].description
        {
            books[index].description = value
            books[index].importedFields.insert("description")
            markDirty(field: "description", for: bookId)
        }
        if fields.contains("language"), let value = details.language, !value.isEmpty {
            let code = Self.languageNameToCode(value)
            if code != books[index].language {
                books[index].language = code
                books[index].importedFields.insert("language")
                markDirty(field: "language", for: bookId)
            }
        }
        if fields.contains("publicationDate"), let value = details.releaseDate, !value.isEmpty {
            let dateOnly = EditableBook.dateOnly(value) ?? value
            if dateOnly != books[index].publicationDate {
                books[index].publicationDate = dateOnly
                books[index].importedFields.insert("publicationDate")
                markDirty(field: "publicationDate", for: bookId)
            }
        }

        if fields.contains("authors") && !details.authors.isEmpty {
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

        if fields.contains("narrators") && !details.narrators.isEmpty {
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

        if fields.contains("creators") && !details.creators.isEmpty {
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

        if fields.contains("series") && !details.series.isEmpty {
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

        if fields.contains("tags") && !details.tags.isEmpty {
            var seen = Set(books[index].tags.map { $0.lowercased() })
            var imported = Set<String>()
            for tag in details.tags {
                guard !seen.contains(tag.lowercased()) else { continue }
                seen.insert(tag.lowercased())
                books[index].tags.append(tag)
                imported.insert(tag)
            }
            if !imported.isEmpty {
                books[index].importedItems["tags", default: []].formUnion(imported)
                markDirty(field: "tags", for: bookId)
            }
        }
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
