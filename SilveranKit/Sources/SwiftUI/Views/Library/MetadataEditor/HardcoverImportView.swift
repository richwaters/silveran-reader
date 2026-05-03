import SwiftUI

struct HardcoverImportView: View {
    @State private var viewModel = HardcoverImportViewModel()
    let bookTitle: String
    let bookAuthor: String?
    let onImport: (HardcoverBookDetails, Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            tokenSection
            Divider()

            searchSection
            Divider()
            resultsList
            Divider()

            if viewModel.fetchedDetails != nil {
                fieldsSection
                Divider()
            }

            bottomBar
        }
        .frame(width: 600, height: 500)
        .task {
            await viewModel.loadToken()
            viewModel.prefill(title: bookTitle, author: bookAuthor)
            if viewModel.hasToken {
                await viewModel.search()
            }
        }
    }

    // MARK: - Token

    @ViewBuilder
    private var tokenSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(viewModel.hasToken ? .green : .secondary)

            if viewModel.hasToken && !viewModel.isEditingToken {
                Text("Token saved")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Change") {
                    viewModel.isEditingToken = true
                }
                .font(.callout)
                Button("Clear") {
                    Task { await viewModel.clearToken() }
                }
                .font(.callout)
                .foregroundStyle(.red)
            } else {
                SecureField("Hardcover API Token", text: $viewModel.tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await viewModel.saveToken() }
                    }
                Button("Save") {
                    Task { await viewModel.saveToken() }
                }
                .disabled(
                    viewModel.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if viewModel.hasToken {
                    Button("Cancel") {
                        viewModel.isEditingToken = false
                        viewModel.tokenInput = ""
                    }
                }
            }
        }
        .padding(12)
        .background(viewModel.hasToken ? Color.clear : .yellow.opacity(0.05))
    }

    // MARK: - Search

    @ViewBuilder
    private var searchSection: some View {
        HStack(spacing: 8) {
            TextField("Search Hardcover...", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await viewModel.search() }
                }
            Button("Search") {
                Task { await viewModel.search() }
            }
            .disabled(
                viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isSearching || !viewModel.hasToken)
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
        List(viewModel.searchResults, selection: Binding(
            get: { viewModel.selectedResult?.id },
            set: { newId in
                if let result = viewModel.searchResults.first(where: { $0.id == newId }) {
                    Task { await viewModel.selectResult(result) }
                }
            }
        )) { result in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .lineLimit(1)
                        .font(.body)
                    if !result.authorNames.isEmpty {
                        Text(result.authorNames.joined(separator: ", "))
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let year = result.releaseYear {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.selectedResult?.id == result.id && viewModel.isFetching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .tag(result.id)
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.searchResults.isEmpty && !viewModel.isSearching {
                if !viewModel.hasToken {
                    ContentUnavailableView(
                        "Enter API Token",
                        systemImage: "key",
                        description: Text("Enter your Hardcover API token above to search")
                    )
                } else if !viewModel.hasSearched {
                    ContentUnavailableView(
                        "Search Hardcover",
                        systemImage: "magnifyingglass",
                        description: Text("Press Search or Enter to find books")
                    )
                } else {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "book.closed",
                        description: Text("Try a different search term")
                    )
                }
            }
        }
    }

    // MARK: - Field Selection

    @ViewBuilder
    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fields to Import")
                .font(.headline)
                .padding(.bottom, 2)

            LazyVGrid(
                columns: [
                    GridItem(.flexible()), GridItem(.flexible()),
                    GridItem(.flexible()),
                ], alignment: .leading, spacing: 6
            ) {
                ForEach(HardcoverImportViewModel.allFields, id: \.key) { field in
                    Toggle(
                        field.label,
                        isOn: Binding(
                            get: { viewModel.selectedFields.contains(field.key) },
                            set: { _ in viewModel.toggleField(field.key) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .disabled(!fieldHasData(field.key))
                }
            }
        }
        .padding(12)
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if let error = viewModel.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Import Selected") {
                guard let details = viewModel.fetchedDetails else { return }
                onImport(details, viewModel.selectedFields)
                dismiss()
            }
            .disabled(viewModel.fetchedDetails == nil || viewModel.selectedFields.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func fieldHasData(_ field: String) -> Bool {
        guard let details = viewModel.fetchedDetails else { return false }
        switch field {
        case "title": return details.title != nil && !details.title!.isEmpty
        case "subtitle": return details.subtitle != nil && !details.subtitle!.isEmpty
        case "description": return details.description != nil && !details.description!.isEmpty
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
}
