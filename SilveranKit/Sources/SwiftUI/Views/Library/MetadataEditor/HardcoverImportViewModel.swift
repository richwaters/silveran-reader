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

    var selectedFields: Set<String> = [
        "title", "subtitle", "description", "publicationDate",
        "rating", "authors", "narrators", "creators", "series", "tags",
    ]

    static let allFields: [(key: String, label: String)] = [
        ("title", "Title"),
        ("subtitle", "Subtitle"),
        ("description", "Description"),
        ("publicationDate", "Publication Date"),
        ("rating", "Rating"),
        ("authors", "Authors"),
        ("narrators", "Narrators"),
        ("creators", "Other Creators"),
        ("series", "Series"),
        ("tags", "Tags"),
    ]

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

    func selectResult(_ result: HardcoverSearchResult) async {
        selectedResult = result
        isFetching = true
        error = nil
        fetchedDetails = nil

        do {
            fetchedDetails = try await HardcoverActor.shared.fetchBookDetails(id: result.id)
        } catch {
            self.error = error.localizedDescription
        }

        isFetching = false
    }

    func toggleField(_ field: String) {
        if selectedFields.contains(field) {
            selectedFields.remove(field)
        } else {
            selectedFields.insert(field)
        }
    }

    func prefill(title: String, author: String?) {
        var query = title
        if let author, !author.isEmpty {
            query += " \(author)"
        }
        searchQuery = query
    }
}
