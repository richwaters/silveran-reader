import SwiftUI

struct HardcoverImportView: View {
    @State private var viewModel = HardcoverImportViewModel()
    let bookTitle: String
    let bookAuthor: String?
    let onImport: (HardcoverBookDetails, Set<String>) -> Void
    let onAutoImportAll: ((Set<String>) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            tokenSection
            Divider()

            searchSection
            Divider()
            resultsList
            Divider()
            fieldsSection
            Divider()
            bottomBar
        }
        .frame(width: 600, height: 500)
        .task {
            viewModel.loadFieldSelection()
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

    @State private var expandedResultIds: Set<Int> = []
    @State private var infoPopoverId: Int?
    @State private var filterPopoverId: Int?
    @AppStorage("hardcoverImport.filterLanguage") private var editionFilterLanguage: String?
    @AppStorage("hardcoverImport.filterFormat") private var editionFilterFormat: String?
    @State private var editionPreviewId: Int?

    @ViewBuilder
    private var resultsList: some View {
        List {
            ForEach(viewModel.searchResults) { result in
                searchResultRow(result: result)
            }
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
            HStack {
                Text("Fields to Import")
                    .font(.headline)
                Spacer()
                Button("All") { viewModel.selectAllFields() }
                    .font(.callout)
                    .buttonStyle(.borderless)
                Text("/").foregroundStyle(.secondary)
                Button("None") { viewModel.selectNoFields() }
                    .font(.callout)
                    .buttonStyle(.borderless)
            }

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
                }
            }
        }
        .padding(12)
    }

    // MARK: - Search Result Row

    @ViewBuilder
    private func searchResultRow(result: HardcoverSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            searchResultHeader(result: result)

            if expandedResultIds.contains(result.id),
                let details = viewModel.infoDetails[result.id]
            {
                editionsList(details: details, result: result)
            }
        }
    }

    @ViewBuilder
    private func searchResultHeader(result: HardcoverSearchResult) -> some View {
        HStack {
            chevronButton(result: result)

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

            resultActionButtons(result: result)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if expandedResultIds.contains(result.id) {
                expandedResultIds.remove(result.id)
            } else {
                expandedResultIds.insert(result.id)
                Task { await viewModel.fetchInfo(for: result) }
            }
            Task { await viewModel.selectResult(result) }
        }
        .padding(.vertical, 2)
        .background(
            viewModel.selectedResult?.id == result.id
                && viewModel.selectedEditionId == nil
                ? Color.accentColor.opacity(0.2) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func chevronButton(result: HardcoverSearchResult) -> some View {
        Button(action: {
            if expandedResultIds.contains(result.id) {
                expandedResultIds.remove(result.id)
            } else {
                expandedResultIds.insert(result.id)
                Task { await viewModel.fetchInfo(for: result) }
            }
        }) {
            if viewModel.infoFetchingId == result.id {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 12)
            } else {
                Image(
                    systemName: expandedResultIds.contains(result.id)
                        ? "chevron.down" : "chevron.right"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12)
            }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func resultActionButtons(result: HardcoverSearchResult) -> some View {
        if expandedResultIds.contains(result.id) {
            let hasFilter = editionFilterLanguage != nil || editionFilterFormat != nil
            Button(action: {
                filterPopoverId = filterPopoverId == result.id ? nil : result.id
            }) {
                Image(
                    systemName: hasFilter
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                .foregroundStyle(hasFilter ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: Binding(
                get: { filterPopoverId == result.id },
                set: { if !$0 { filterPopoverId = nil } }
            )) {
                editionFilterPopover(for: result.id)
            }
        }

        Button(action: {
            infoPopoverId = infoPopoverId == result.id ? nil : result.id
            Task { await viewModel.fetchInfo(for: result) }
        }) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: Binding(
            get: { infoPopoverId == result.id },
            set: { if !$0 { infoPopoverId = nil } }
        )) {
            bookInfoPopover(for: result.id)
        }

        if viewModel.selectedResult?.id == result.id && viewModel.isFetching {
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Edition Filter

    private static let digitalNormalized: Set<String> = [
        "Ebook", "Kindle", "Audible", "Audiobook",
    ]
    private static let physicalNormalized: Set<String> = [
        "Hardcover", "Paperback", "Mass Market Paperback",
    ]

    private func filteredEditions(_ editions: [HardcoverEditionInfo]) -> [HardcoverEditionInfo] {
        editions.filter { edition in
            if let lang = editionFilterLanguage {
                guard edition.language?.lowercased() == lang.lowercased() else { return false }
            }
            if let fmt = editionFilterFormat {
                let normalized = normalizedFormat(edition.format)
                switch fmt {
                case "digital":
                    guard Self.digitalNormalized.contains(normalized) else { return false }
                case "physical":
                    guard Self.physicalNormalized.contains(normalized) else { return false }
                default:
                    guard normalized == fmt else { return false }
                }
            }
            return true
        }
    }

    @ViewBuilder
    private func editionFilterPopover(for bookId: Int) -> some View {
        let editions = viewModel.infoDetails[bookId]?.editions ?? []
        let languages = Array(Set(editions.compactMap(\.language))).sorted()
        let formats = Array(Set(editions.map { normalizedFormat($0.format) })).sorted()

        VStack(alignment: .leading, spacing: 10) {
            Text("Filter Editions").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Language").font(.subheadline).foregroundStyle(.secondary)
                Picker("", selection: $editionFilterLanguage) {
                    Text("All").tag(String?.none)
                    ForEach(languages, id: \.self) { lang in
                        Text(lang).tag(Optional(lang))
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Format").font(.subheadline).foregroundStyle(.secondary)
                Picker("", selection: $editionFilterFormat) {
                    Text("All").tag(String?.none)
                    Divider()
                    Text("Digital Only").tag(Optional("digital"))
                    Text("Physical Only").tag(Optional("physical"))
                    Divider()
                    ForEach(formats, id: \.self) { fmt in
                        Text(fmt).tag(Optional(fmt))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Clear Filters") {
                    editionFilterLanguage = nil
                    editionFilterFormat = nil
                }
                .disabled(editionFilterLanguage == nil && editionFilterFormat == nil)
                .font(.callout)
            }
        }
        .padding()
        .frame(width: 220)
    }

    // MARK: - Editions List

    @ViewBuilder
    private func editionsList(
        details: HardcoverBookDetails, result: HardcoverSearchResult
    ) -> some View {
        let filtered = filteredEditions(details.editions)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(filtered) { edition in
                HStack(spacing: 4) {
                    Spacer().frame(width: 16)
                    Image(systemName: editionIcon(edition.format))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(normalizedFormat(edition.format))
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)
                        .lineLimit(1)
                    Text(edition.language ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 55, alignment: .leading)
                        .lineLimit(1)
                    Text(countryAbbreviation(edition.country) ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                        .lineLimit(1)
                    Text(edition.pages.map { "\($0) pp" } ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    Text(edition.isbn13 ?? "")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 105, alignment: .trailing)
                    if !edition.narrators.isEmpty {
                        Text(edition.narrators.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: {
                        editionPreviewId = editionPreviewId == edition.id ? nil : edition.id
                    }) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: Binding(
                        get: { editionPreviewId == edition.id },
                        set: { if !$0 { editionPreviewId = nil } }
                    )) {
                        editionPreviewPopover(
                            edition: edition, bookDetails: details)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .background(
                    viewModel.selectedEditionId == edition.id
                        ? Color.accentColor.opacity(0.2) : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture {
                    viewModel.selectEdition(edition, bookId: result.id)
                }
            }
        }
        .padding(.top, 4)
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func editionPreviewPopover(
        edition: HardcoverEditionInfo, bookDetails: HardcoverBookDetails
    ) -> some View {
        let narrators = edition.narrators.isEmpty ? bookDetails.narrators : edition.narrators
        let creators = edition.otherContributors.isEmpty
            ? bookDetails.creators : edition.otherContributors
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(edition.editionInfo ?? edition.format).font(.headline)

                editionPreviewFields(edition: edition, bookDetails: bookDetails)
                editionPreviewPeople(
                    bookDetails: bookDetails, narrators: narrators, creators: creators)
                editionPreviewCollections(bookDetails: bookDetails)
            }
            .padding()
        }
        .frame(width: 380, height: 320)
    }

    @ViewBuilder
    private func editionPreviewFields(
        edition: HardcoverEditionInfo, bookDetails: HardcoverBookDetails
    ) -> some View {
        row("Title", edition.title ?? bookDetails.title)
        row("Subtitle", edition.subtitle ?? bookDetails.subtitle)
        row("Language", edition.language ?? bookDetails.language)
        row("Country", edition.country)
        row("Release Date", edition.releaseDate ?? bookDetails.releaseDate)
        row("Publisher", edition.publisher)
        row("Pages", edition.pages.map { "\($0)" })
        if let secs = edition.audioSeconds, secs > 0 {
            let hrs = secs / 3600
            let mins = (secs % 3600) / 60
            row("Audio Length", "\(hrs)h \(mins)m")
        }
        row("ISBN-13", edition.isbn13)
        row("ISBN-10", edition.isbn10)
        row("ASIN", edition.asin)
    }

    @ViewBuilder
    private func editionPreviewPeople(
        bookDetails: HardcoverBookDetails, narrators: [String],
        creators: [(name: String, role: String)]
    ) -> some View {
        if !bookDetails.authors.isEmpty {
            row("Authors", bookDetails.authors.joined(separator: ", "))
        }
        if !narrators.isEmpty {
            row("Narrators", narrators.joined(separator: ", "))
        }
        if !creators.isEmpty {
            row(
                "Creators",
                creators.map { "\($0.name) (\($0.role))" }.joined(separator: ", "))
        }
    }

    @ViewBuilder
    private func editionPreviewCollections(bookDetails: HardcoverBookDetails) -> some View {
        if !bookDetails.series.isEmpty {
            row(
                "Series",
                bookDetails.series.map { s in
                    s.position != nil ? "\(s.name) #\(s.position!.formatted())" : s.name
                }.joined(separator: ", "))
        }
        if !bookDetails.tags.isEmpty {
            row("Tags", bookDetails.tags.prefix(10).joined(separator: ", "))
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) {
                Text(value)
                    .lineLimit(2)
            }
            .font(.callout)
        }
    }

    private func countryAbbreviation(_ name: String?) -> String? {
        guard let name else { return nil }
        let target = name.lowercased()
        let english = Locale(identifier: "en")
        for code in Locale.isoRegionCodes {
            if let localized = english.localizedString(forRegionCode: code)?.lowercased(),
                localized == target || target.contains(localized) || localized.contains(target)
            {
                return code
            }
        }
        return String(name.prefix(3))
    }

    private static let formatNormalization: [String: String] = [
        "ebook": "Ebook",
        "e-book": "Ebook",
        "kindle": "Kindle",
        "epub3": "Ebook",
        "audible": "Audible",
        "audiobook": "Audiobook",
        "unabridged audiobook": "Audiobook",
        "hardcover": "Hardcover",
        "paperback": "Paperback",
        "mass market paperback": "Mass Market Paperback",
    ]

    private func normalizedFormat(_ format: String) -> String {
        Self.formatNormalization[format.lowercased()]
            ?? {
                guard let first = format.first else { return format }
                return String(first).uppercased() + format.dropFirst()
            }()
    }

    private func editionIcon(_ format: String) -> String {
        switch format.lowercased() {
        case "audiobook", "audio": return "headphones"
        case "ebook", "kindle", "digital": return "tablet.landscape"
        case "hardcover": return "book.closed.fill"
        case "paperback": return "book.closed"
        default: return "book"
        }
    }

    // MARK: - Book Info Popover

    @ViewBuilder
    private func bookInfoPopover(for bookId: Int) -> some View {
        if let details = viewModel.infoDetails[bookId] {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let title = details.title {
                        Text(title).font(.headline)
                    }
                    if let subtitle = details.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !details.authors.isEmpty {
                        LabeledContent("Authors") {
                            Text(details.authors.joined(separator: ", "))
                        }
                    }
                    if !details.narrators.isEmpty {
                        LabeledContent("Narrators") {
                            Text(details.narrators.joined(separator: ", "))
                        }
                    }
                    if !details.series.isEmpty {
                        LabeledContent("Series") {
                            VStack(alignment: .trailing) {
                                ForEach(details.series, id: \.name) { s in
                                    Text(
                                        s.position != nil
                                            ? "\(s.name) #\(s.position!.formatted())"
                                            : s.name)
                                }
                            }
                        }
                    }
                    if let date = details.releaseDate, !date.isEmpty {
                        LabeledContent("Release Date", value: date)
                    }
                    if let rating = details.rating {
                        LabeledContent("Rating", value: String(format: "%.1f", rating))
                    }
                    if !details.tags.isEmpty {
                        LabeledContent("Tags") {
                            Text(details.tags.prefix(10).joined(separator: ", "))
                        }
                    }

                    let isbns = details.editions.compactMap { ed -> String? in
                        guard let isbn = ed.isbn13 else { return nil }
                        return "\(ed.format): \(isbn)"
                    }
                    if !isbns.isEmpty {
                        LabeledContent("ISBNs") {
                            VStack(alignment: .trailing, spacing: 2) {
                                ForEach(isbns.prefix(6), id: \.self) { isbn in
                                    Text(isbn).font(.caption)
                                }
                                if isbns.count > 6 {
                                    Text("+\(isbns.count - 6) more")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }

                    if let desc = details.description, !desc.isEmpty {
                        Divider()
                        Text(desc)
                            .font(.callout)
                            .lineLimit(10)
                    }
                }
                .padding()
            }
            .frame(width: 380, height: 320)
        } else {
            ProgressView()
                .padding()
                .frame(width: 150, height: 60)
        }
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

            if let onAutoImportAll {
                Button("Auto Import All Books") {
                    onAutoImportAll(viewModel.selectedFields)
                    dismiss()
                }
                .disabled(viewModel.selectedFields.isEmpty || !viewModel.hasToken)
            }

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

}
