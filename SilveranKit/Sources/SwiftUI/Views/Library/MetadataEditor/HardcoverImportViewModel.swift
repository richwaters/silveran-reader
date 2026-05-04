import Foundation
import SwiftUI

@MainActor
@Observable
final class HardcoverImportViewModel {
    var searchQuery: String = ""
    var searchResults: [HardcoverSearchResult] = []
    var selectedResult: HardcoverSearchResult?
    var fetchedDetails: HardcoverBookDetails?
    var isSearching = false
    var isFetching = false
    var error: String?

    var tokenInput: String = ""
    var hasToken = false
    var isEditingToken = false

    var infoDetails: [Int: HardcoverBookDetails] = [:]
    var infoFetchingId: Int?

    func fetchInfo(for result: HardcoverSearchResult) async {
        guard infoDetails[result.id] == nil else { return }
        infoFetchingId = result.id
        do {
            let details = try await HardcoverActor.shared.fetchBookDetails(id: result.id)
            infoDetails[result.id] = details
        } catch {
            self.error = error.localizedDescription
        }
        infoFetchingId = nil
    }

    var selectedFields: Set<String> = []

    static let allFields: [(key: String, label: String)] = [
        ("title", "Title"),
        ("subtitle", "Subtitle"),
        ("description", "Description"),
        ("language", "Language"),
        ("publicationDate", "Publication Date"),
        ("rating", "Rating"),
        ("authors", "Authors"),
        ("narrators", "Narrators"),
        ("creators", "Other Creators"),
        ("series", "Series"),
        ("tags", "Tags"),
    ]

    private static let defaultFields: Set<String> = [
        "title", "subtitle", "description", "language", "publicationDate",
        "rating", "authors", "narrators", "creators", "series", "tags",
    ]

    private static let selectedFieldsKey = "hardcoverImport.selectedFields"

    func loadFieldSelection() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.selectedFieldsKey) {
            selectedFields = Set(saved)
        } else {
            selectedFields = Self.defaultFields
        }
    }

    private func persistFieldSelection() {
        UserDefaults.standard.set(Array(selectedFields), forKey: Self.selectedFieldsKey)
    }

    func selectAllFields() {
        selectedFields = Set(Self.allFields.map(\.key))
        persistFieldSelection()
    }

    func selectNoFields() {
        selectedFields = []
        persistFieldSelection()
    }

    func loadToken() async {
        do {
            if let token = try await AuthenticationActor.shared.loadHardcoverToken() {
                await HardcoverActor.shared.setToken(token)
                hasToken = true
            }
        } catch {
            self.error = "Failed to load token: \(error.localizedDescription)"
        }
    }

    func saveToken() async {
        var trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer") {
            trimmed = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return }
        do {
            try await AuthenticationActor.shared.saveHardcoverToken(trimmed)
            await HardcoverActor.shared.setToken(trimmed)
            hasToken = true
            isEditingToken = false
            tokenInput = ""
            error = nil
        } catch {
            self.error = "Failed to save token: \(error.localizedDescription)"
        }
    }

    func clearToken() async {
        do {
            try await AuthenticationActor.shared.deleteHardcoverToken()
            await HardcoverActor.shared.setToken(nil)
            hasToken = false
            isEditingToken = false
            tokenInput = ""
        } catch {
            self.error = "Failed to clear token: \(error.localizedDescription)"
        }
    }

    var hasSearched = false

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        error = nil
        selectedResult = nil
        fetchedDetails = nil

        do {
            searchResults = try await HardcoverActor.shared.searchBooks(query: query)
            hasSearched = true
            if searchResults.isEmpty {
                error = "No results found for \"\(query)\""
            }
        } catch {
            self.error = error.localizedDescription
            searchResults = []
            hasSearched = true
        }

        isSearching = false
    }

    var selectedEditionId: Int?

    func selectResult(_ result: HardcoverSearchResult) async {
        selectedResult = result
        selectedEditionId = nil
        isFetching = true
        error = nil
        fetchedDetails = nil

        do {
            let details = try await HardcoverActor.shared.fetchBookDetails(id: result.id)
            infoDetails[result.id] = details
            fetchedDetails = details
        } catch {
            self.error = error.localizedDescription
        }

        isFetching = false
    }

    func selectEdition(_ edition: HardcoverEditionInfo, bookId: Int) {
        guard let bookDetails = infoDetails[bookId] else { return }
        selectedEditionId = edition.id

        let releaseDate: String? = {
            guard let raw = edition.releaseDate else { return bookDetails.releaseDate }
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withFullDate]
            if let date = df.date(from: raw) {
                let full = ISO8601DateFormatter()
                full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return full.string(from: date)
            }
            return raw
        }()

        fetchedDetails = HardcoverBookDetails(
            title: edition.title ?? bookDetails.title,
            subtitle: edition.subtitle ?? bookDetails.subtitle,
            description: bookDetails.description,
            releaseDate: releaseDate,
            rating: bookDetails.rating,
            language: edition.language ?? bookDetails.language,
            authors: bookDetails.authors,
            narrators: edition.narrators.isEmpty ? bookDetails.narrators : edition.narrators,
            creators: edition.otherContributors.isEmpty
                ? bookDetails.creators : edition.otherContributors,
            series: bookDetails.series,
            tags: bookDetails.tags,
            editions: bookDetails.editions
        )
    }

    func toggleField(_ field: String) {
        if selectedFields.contains(field) {
            selectedFields.remove(field)
        } else {
            selectedFields.insert(field)
        }
        persistFieldSelection()
    }

    func prefill(title: String, author: String?) {
        var query = title
        if let author, !author.isEmpty {
            query += " \(author)"
        }
        searchQuery = query
    }
}
