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
            self.publicationDate = metadata.publicationDate ?? ""
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
        case "publicationDate": isChanged = book.publicationDate != (orig.publicationDate ?? "")
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
            payload.publicationDate = trimmed.isEmpty ? .null : .value(trimmed)
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
}
