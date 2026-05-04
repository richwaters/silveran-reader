import SwiftUI

struct TitleDetailsTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TwoColumnRow {
                    Text("Edited").font(.headline)
                } right: {
                    HStack(spacing: 0) {
                        Text("Storyteller Server")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Hardcover Import")
                            .font(.headline)
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                scalarField(label: "Title", field: "title",
                    get: { $0.title },
                    set: { $0.title = $1 },
                    revert: { $0.title = $0.originalMetadata.title }
                )

                scalarField(label: "Subtitle", field: "subtitle",
                    get: { $0.subtitle },
                    set: { $0.subtitle = $1 },
                    revert: { $0.subtitle = $0.originalMetadata.subtitle ?? "" }
                )

                scalarField(label: "Language", field: "language",
                    get: { $0.language },
                    set: { $0.language = $1 },
                    revert: { $0.language = $0.originalMetadata.language ?? "" }
                )

                publicationDateField

                ratingField

                Divider()

                // Series
                TwoColumnRow {
                    seriesEditor
                } right: {
                    seriesReference
                }
            }
            .padding()
        }
    }

    // MARK: - Series Editor

    @ViewBuilder
    private var seriesEditor: some View {
        let isDirty = viewModel.isDirty(field: "series", for: bookId)
        let seriesList = viewModel.books.first { $0.id == bookId }?.series ?? []
        let hasImports = viewModel.books.first { $0.id == bookId }?
            .importedItems["series"]?.isEmpty == false
        let matchesHC: Bool = {
            guard let hcList = viewModel.hardcoverSeriesList(for: bookId) else { return false }
            let editedList = seriesList.map { s -> String in
                if s.position.isEmpty { return s.name }
                return "\(s.name) #\(s.position)"
            }
            return editedList == hcList
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Series")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        matchesHC ? Color.blue : isDirty ? Color.orange : .primary)
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
                    .border(
                        matchesHC ? Color.blue : isDirty ? Color.orange : Color.gray.opacity(0.3),
                        width: 2
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    TextField(
                        "#",
                        text: seriesBinding(seriesId: series.id, keyPath: \.position)
                    )
                    .textFieldStyle(.roundedBorder)
                    .border(
                        viewModel.seriesPositionHasError(bookId: bookId, seriesId: series.id)
                            ? Color.red
                            : matchesHC ? Color.blue
                            : isDirty ? Color.orange
                            : Color.gray.opacity(0.3),
                        width: 2
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
    }

    // MARK: - Series Reference

    @ViewBuilder
    private var seriesReference: some View {
        let origSeries = viewModel.books.first { $0.id == bookId }?
            .originalMetadata.series ?? []
        let hcSeries = viewModel.hardcoverSeriesList(for: bookId)

        VStack(alignment: .leading, spacing: 6) {
            Text("Series").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    RevertButton(color: .white, help: "Revert to server value") {
                        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                        else { return }
                        viewModel.books[index].series =
                            viewModel.books[index].originalMetadata.series?.map { s in
                                MetadataEditorViewModel.EditableSeries(
                                    name: s.name,
                                    position: s.position.map {
                                        $0.truncatingRemainder(dividingBy: 1) == 0
                                            ? String(Int($0)) : String($0)
                                    } ?? "",
                                    featured: s.featured == 1,
                                    uuid: s.uuid
                                )
                            } ?? []
                        viewModel.books[index].dirtyFields.remove("series")
                        viewModel.books[index].importedFields.remove("series")
                    }
                    if origSeries.isEmpty {
                        Text("(empty)")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.5))
                            .italic()
                    } else {
                        ForEach(origSeries, id: \.self) { s in
                            let pos = s.position.map { p -> String in
                                p.truncatingRemainder(dividingBy: 1) == 0
                                    ? " #\(Int(p))" : " #\(p)"
                            } ?? ""
                            Text("\(s.name)\(pos)")
                                .font(.callout)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 4) {
                    if let hcSeries {
                        RevertButton(color: .blue, help: "Revert to Hardcover value") {
                            viewModel.revertToHardcover(field: "series", for: bookId)
                        }
                        ForEach(hcSeries, id: \.self) { s in
                            Text(s)
                                .font(.callout)
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Text("--")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

    // MARK: - Scalar Field

    @ViewBuilder
    private func scalarField(
        label: String,
        field: String,
        get: @escaping (MetadataEditorViewModel.EditableBook) -> String,
        set: @escaping (inout MetadataEditorViewModel.EditableBook, String) -> Void,
        revert: @escaping (inout MetadataEditorViewModel.EditableBook) -> Void
    ) -> some View {
        TwoColumnRow {
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
        } right: {
            ReferenceValues(
                label: label,
                field: field,
                bookId: bookId,
                viewModel: viewModel,
                revertToOriginal: {
                    guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                    else { return }
                    revert(&viewModel.books[index])
                    viewModel.books[index].dirtyFields.remove(field)
                    viewModel.books[index].importedFields.remove(field)
                }
            )
        }
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

        TwoColumnRow {
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
                    .border(
                        fieldMatchColor(field: "publicationDate", bookId: bookId, viewModel: viewModel),
                        width: 2
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))

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
        } right: {
            ReferenceValues(
                label: "Publication Date",
                field: "publicationDate",
                bookId: bookId,
                viewModel: viewModel,
                revertToOriginal: {
                    guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                    else { return }
                    viewModel.books[index].publicationDate =
                        MetadataEditorViewModel.EditableBook.dateOnly(
                            viewModel.books[index].originalMetadata.publicationDate) ?? ""
                    viewModel.books[index].dirtyFields.remove("publicationDate")
                    viewModel.books[index].importedFields.remove("publicationDate")
                }
            )
        }
    }

    // MARK: - Rating

    @ViewBuilder
    private var ratingField: some View {
        let hasRating = !(viewModel.books.first { $0.id == bookId }?.rating ?? "").isEmpty

        TwoColumnRow {
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
                    .border(
                        fieldMatchColor(field: "rating", bookId: bookId, viewModel: viewModel),
                        width: 2
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))

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
        } right: {
            ReferenceValues(
                label: "Rating",
                field: "rating",
                bookId: bookId,
                viewModel: viewModel,
                revertToOriginal: {
                    guard let index = viewModel.books.firstIndex(where: { $0.id == bookId })
                    else { return }
                    viewModel.books[index].rating =
                        viewModel.books[index].originalMetadata.rating.map { String($0) } ?? ""
                    viewModel.books[index].dirtyFields.remove("rating")
                    viewModel.books[index].importedFields.remove("rating")
                }
            )
        }
    }
}
