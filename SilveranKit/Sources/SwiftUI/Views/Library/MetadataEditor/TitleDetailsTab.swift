import SwiftUI

struct TitleDetailsTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel
    let openHardcoverImport: () -> Void
    @State private var selectedPublicationDateSource: MetadataEditorViewModel.HardcoverImportSource = .text
    private let scalarRowHeight: CGFloat = 78
    private let publicationRowHeight: CGFloat = 108

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                MetadataColumnHeaders(centerTitle: "Current Details")
                    .frame(height: 22, alignment: .top)

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        scalarField(label: "Title", field: "title",
                            get: { $0.title },
                            set: { $0.title = $1 }
                        )

                        scalarField(label: "Subtitle", field: "subtitle",
                            get: { $0.subtitle },
                            set: { $0.subtitle = $1 }
                        )

                        scalarField(label: "Language", field: "language",
                            get: { $0.language },
                            set: { $0.language = $1 }
                        )

                        publicationDateField

                        ratingField

                        Divider()

                        seriesRow
                    }

                    if !hasHardcoverImportData {
                        rightColumnHardcoverImportPlaceholder
                    }
                }
            }
            .padding()
        }
    }

    private var hasHardcoverImportData: Bool {
        viewModel.books.first { $0.id == bookId }?.hardcoverImports.isEmpty == false
    }

    private var rightColumnHardcoverImportPlaceholder: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let arrowWidth: CGFloat = 34
            let columnWidth = max(geo.size.width - arrowWidth * 2 - spacing * 4, 0)
            let rightWidth = columnWidth / 3
            let rightX = columnWidth * 2 / 3 + arrowWidth * 2 + spacing * 4

            ImportHardcoverDataPlaceholder(action: openHardcoverImport)
                .frame(width: rightWidth, height: geo.size.height, alignment: .center)
                .position(x: rightX + rightWidth / 2, y: geo.size.height / 2)
        }
    }

    // MARK: - Scalar Field

    @ViewBuilder
    private func scalarField(
        label: String,
        field: String,
        get: @escaping (MetadataEditorViewModel.EditableBook) -> String,
        set: @escaping (inout MetadataEditorViewModel.EditableBook, String) -> Void
    ) -> some View {
        let currentValue = viewModel.books.first(where: { $0.id == bookId }).map(get) ?? ""

        TransferColumnRow(
            leftCanCopy: viewModel.originalScalarValue(field: field, for: bookId) != currentValue,
            leftHelp: "Copy server \(label.lowercased()) into current metadata",
            leftAction: { viewModel.revertFieldToOriginal(field: field, for: bookId) },
            rightCanCopy: viewModel.hardcoverScalarValue(field: field, for: bookId).map { $0 != currentValue } ?? false,
            rightHelp: "Copy Hardcover \(label.lowercased()) into current metadata",
            rightAction: { viewModel.revertToHardcover(field: field, for: bookId) }
        ) {
            SourceScalarValue(
                label: label,
                value: viewModel.originalScalarValue(field: field, for: bookId),
                currentValue: currentValue
            )
            .frame(maxHeight: .infinity, alignment: .center)
        } center: {
            LabeledEditableField(
                label: label,
                field: field,
                bookId: bookId,
                viewModel: viewModel,
                value: Binding(
                    get: {
                        guard let book = viewModel.books.first(where: { $0.id == bookId })
                        else { return "" }
                        return get(book)
                    },
                    set: { newValue in
                        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        set(&viewModel.books[index], newValue)
                        viewModel.markDirty(field: field, for: bookId)
                    }
                )
            )
            .frame(maxHeight: .infinity, alignment: .center)
        } right: {
            if hasHardcoverImportData {
                SourceScalarValue(
                    label: label,
                    value: viewModel.hardcoverScalarValue(field: field, for: bookId) ?? "",
                    currentValue: currentValue
                )
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: scalarRowHeight, alignment: .center)
    }

    // MARK: - Publication Date

    private static let dateToNoonUTC: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let dateFromNoonUTC: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    @ViewBuilder
    private var publicationDateField: some View {
        let dateString = viewModel.books.first { $0.id == bookId }?.publicationDate ?? ""
        let hasDate = !dateString.isEmpty
        let textDate = viewModel.hardcoverScalarValue(
            field: "publicationDate",
            for: bookId,
            source: .text
        )
        let audioDate = viewModel.hardcoverScalarValue(
            field: "publicationDate",
            for: bookId,
            source: .audiobook
        )
        let effectivePublicationDateSource = selectedPublicationDateSource == .text && textDate == nil && audioDate != nil
            ? MetadataEditorViewModel.HardcoverImportSource.audiobook
            : selectedPublicationDateSource
        let selectedHardcoverDate = effectivePublicationDateSource == .text ? textDate : audioDate

        TransferColumnRow(
            leftCanCopy: viewModel.originalScalarValue(field: "publicationDate", for: bookId) != dateString,
            leftHelp: "Copy server publication date into current metadata",
            leftAction: { viewModel.revertFieldToOriginal(field: "publicationDate", for: bookId) },
            rightCanCopy: selectedHardcoverDate.map { $0 != dateString } ?? false,
            rightHelp: "Copy Hardcover publication date into current metadata",
            rightAction: {
                viewModel.importPublicationDateFromHardcoverSource(
                    effectivePublicationDateSource,
                    for: bookId
                )
            }
        ) {
            SourceScalarValue(
                label: "Publication Date",
                value: viewModel.originalScalarValue(field: "publicationDate", for: bookId),
                currentValue: dateString
            )
            .frame(maxHeight: .infinity, alignment: .center)
        } center: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Publication Date")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: {
                                if let d = Self.dateToNoonUTC.date(from: "\(dateString)T12:00:00.000Z") { return d }
                                let today = Self.dateFromNoonUTC.string(from: Date())
                                return Self.dateToNoonUTC.date(from: "\(today)T12:00:00.000Z") ?? Date()
                            },
                            set: { newDate in
                                guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                                else { return }
                                viewModel.books[index].publicationDate = Self.dateFromNoonUTC.string(from: newDate)
                                viewModel.markDirty(field: "publicationDate", for: bookId)
                            }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .disabled(!hasDate)

                    Toggle("No date", isOn: Binding(
                        get: { !hasDate },
                        set: { noDate in
                            guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                            else { return }
                            viewModel.books[index].publicationDate = noDate
                                ? "" : Self.dateFromNoonUTC.string(from: Date())
                            viewModel.markDirty(field: "publicationDate", for: bookId)
                        }
                    ))
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
                    .font(.callout)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .metadataEditorFieldBoundary()
        } right: {
            if hasHardcoverImportData {
                hardcoverPublicationDateChoices(
                    textDate: textDate,
                    audioDate: audioDate,
                    currentValue: dateString,
                    selectedSource: effectivePublicationDateSource
                )
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: publicationRowHeight, alignment: .center)
    }

    private func hardcoverPublicationDateChoices(
        textDate: String?,
        audioDate: String?,
        currentValue: String,
        selectedSource: MetadataEditorViewModel.HardcoverImportSource
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HardcoverPublicationDateChoice(
                label: "Book Publication Date",
                value: textDate,
                currentValue: currentValue,
                isSelected: selectedSource == .text
            ) {
                selectedPublicationDateSource = .text
            }
            HardcoverPublicationDateChoice(
                label: "Audiobook Publication Date",
                value: audioDate,
                currentValue: currentValue,
                isSelected: selectedSource == .audiobook
            ) {
                selectedPublicationDateSource = .audiobook
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .metadataEditorFieldBoundary()
    }

    // MARK: - Rating

    @ViewBuilder
    private var ratingField: some View {
        let rating = viewModel.books.first { $0.id == bookId }?.rating ?? ""
        let hasRating = !rating.isEmpty

        TransferColumnRow(
            leftCanCopy: viewModel.originalScalarValue(field: "rating", for: bookId) != rating,
            leftHelp: "Copy server rating into current metadata",
            leftAction: { viewModel.revertFieldToOriginal(field: "rating", for: bookId) },
            rightCanCopy: viewModel.hardcoverScalarValue(field: "rating", for: bookId).map { $0 != rating } ?? false,
            rightHelp: "Copy Hardcover rating into current metadata",
            rightAction: { viewModel.revertToHardcover(field: "rating", for: bookId) }
        ) {
            SourceScalarValue(
                label: "Rating",
                value: viewModel.originalScalarValue(field: "rating", for: bookId),
                currentValue: rating
            )
            .frame(maxHeight: .infinity, alignment: .center)
        } center: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rating")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("0.0", text: Binding(
                        get: { viewModel.books.first { $0.id == bookId }?.rating ?? "" },
                        set: { newValue in
                            guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                            else { return }
                            viewModel.books[index].rating = newValue
                            viewModel.markDirty(field: "rating", for: bookId)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
                    .disabled(!hasRating)

                    Toggle("No rating", isOn: Binding(
                        get: { !hasRating },
                        set: { noRating in
                            guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                            else { return }
                            viewModel.books[index].rating = noRating ? "" : "0"
                            viewModel.markDirty(field: "rating", for: bookId)
                        }
                    ))
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif
                    .font(.callout)
                }
            }
            .metadataEditorFieldBoundary()
            .frame(maxHeight: .infinity, alignment: .center)
        } right: {
            if hasHardcoverImportData {
                SourceScalarValue(
                    label: "Rating",
                    value: viewModel.hardcoverScalarValue(field: "rating", for: bookId) ?? "",
                    currentValue: rating
                )
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: scalarRowHeight, alignment: .center)
    }

    // MARK: - Series

    @ViewBuilder
    private var seriesRow: some View {
        TransferColumnRow(
            leftCanCopy: originalSeriesDisplay != currentSeriesDisplay,
            leftHelp: "Copy server series into current metadata",
            leftAction: { viewModel.revertFieldToOriginal(field: "series", for: bookId) },
            rightCanCopy: viewModel.hardcoverSeriesList(for: bookId).map { $0 != currentSeriesDisplay } ?? false,
            rightHelp: "Copy Hardcover series into current metadata",
            rightAction: { viewModel.revertToHardcover(field: "series", for: bookId) }
        ) {
            seriesSource(
                values: originalSeriesDisplay
            )
        } center: {
            seriesEditor
        } right: {
            if hasHardcoverImportData {
                seriesSource(
                    values: viewModel.hardcoverSeriesList(for: bookId) ?? [],
                    onImportHardcover: nil
                )
            }
        }
        .frame(height: max(CGFloat(max(currentSeriesDisplay.count, 1)) * 32 + 28, 64), alignment: .top)
    }

    @ViewBuilder
    private var seriesEditor: some View {
        let seriesList = viewModel.books.first { $0.id == bookId }?.series ?? []

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Series")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: {
                    guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                    else { return }
                    viewModel.books[index].series.append(
                        MetadataEditorViewModel.EditableSeries(
                            name: "", position: "", featured: false, uuid: nil
                        )
                    )
                    viewModel.markDirty(field: "series", for: bookId)
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            ForEach(seriesList) { series in
                HStack(spacing: 4) {
                    if viewModel.isImported(
                        field: "series", value: series.name, for: bookId)
                    {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                    }
                    TextField(
                        "Series Name",
                        text: seriesBinding(seriesId: series.id, keyPath: \.name)
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "#",
                        text: seriesBinding(seriesId: series.id, keyPath: \.position)
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 60)

                    Toggle(
                        "Featured",
                        isOn: Binding(
                            get: {
                                viewModel.books.first { $0.id == bookId }?
                                    .series.first { $0.id == series.id }?.featured ?? false
                            },
                            set: { newValue in
                                guard
                                    let bookIndex = viewModel.books.firstIndex(where: {
                                        $0.id == bookId
                                    }),
                                    let seriesIndex = viewModel.books[bookIndex].series
                                        .firstIndex(where: { $0.id == series.id })
                                else { return }
                                viewModel.books[bookIndex].series[seriesIndex].featured = newValue
                                viewModel.markDirty(field: "series", for: bookId)
                            }
                        )
                    )
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif

                    Button(action: {
                        guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        viewModel.books[bookIndex].series.removeAll { $0.id == series.id }
                        viewModel.markDirty(field: "series", for: bookId)
                    }) {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .metadataEditorFieldBoundary()
    }

    private var originalSeriesDisplay: [String] {
        let origSeries = viewModel.books.first { $0.id == bookId }?
            .originalMetadata.series ?? []
        return origSeries.map { s in
            let pos = s.position.map { p -> String in
                p.truncatingRemainder(dividingBy: 1) == 0
                    ? " #\(Int(p))" : " #\(p)"
            } ?? ""
            return "\(s.name)\(pos)"
        }
    }

    private var currentSeriesDisplay: [String] {
        let seriesList = viewModel.books.first { $0.id == bookId }?.series ?? []
        return seriesList.map { s -> String in
            if s.position.isEmpty { return s.name }
            return "\(s.name) #\(s.position)"
        }
    }

    @ViewBuilder
    private func seriesSource(
        values: [String]?,
        onImportHardcover: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Series").font(.callout).foregroundStyle(.secondary)
            SourceListValues(
                values: values,
                currentValues: currentSeriesDisplay,
                onImportHardcover: onImportHardcover
            )
        }
        .metadataEditorFieldBoundary()
    }

    private func seriesBinding(
        seriesId: UUID,
        keyPath: WritableKeyPath<MetadataEditorViewModel.EditableSeries, String>
    ) -> Binding<String> {
        Binding(
            get: {
                viewModel.books.first { $0.id == bookId }?
                    .series.first { $0.id == seriesId }?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let bookIndex = viewModel.books.firstIndex(where: { $0.id == bookId }),
                    let seriesIndex = viewModel.books[bookIndex].series.firstIndex(where: {
                        $0.id == seriesId
                    })
                else { return }
                viewModel.books[bookIndex].series[seriesIndex][keyPath: keyPath] = newValue
                viewModel.markDirty(field: "series", for: bookId)
            }
        )
    }
}

private struct HardcoverPublicationDateChoice: View {
    let label: String
    let value: String?
    let currentValue: String
    let isSelected: Bool
    let selectAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let value, !value.isEmpty {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.body)
                        .foregroundStyle(isSelected ? Color.accentColor : value == currentValue ? .secondary : .primary)
                        .textSelection(.enabled)

                    Button("Use") {
                        selectAction()
                    }
                    .controlSize(.mini)
                    .disabled(isSelected)
                }
            } else {
                Text("(empty)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}
