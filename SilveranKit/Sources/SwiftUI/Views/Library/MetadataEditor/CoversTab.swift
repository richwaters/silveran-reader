import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

struct CoversTab: View {
    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel
    @Environment(MediaViewModel.self) private var mediaViewModel

    @State private var showEbookPicker = false
    @State private var showAudiobookPicker = false
    @State private var isLoadingHCImage = false
    @State private var isRefreshingCoverCache = false
    @State private var infoPopoverId: Int?
    @State private var previewingCover: PreviewCover?
    @State private var showBookIdPopover = false
    @State private var didCopyBookId = false

    @AppStorage("hardcoverImport.filterLanguage") private var editionFilterLanguage: String?
    @AppStorage("hardcoverImport.filterFormat") private var editionFilterFormat: String?
    @State private var minResolution: Int?
    @State private var showFilterPopover = false

    private var itunesResults: [ITunesCoverResult] {
        viewModel.itunesResults(for: bookId)
    }

    private var book: MetadataEditorViewModel.EditableBook? {
        viewModel.books.first { $0.id == bookId }
    }

    private var metadata: BookMetadata? {
        book?.originalMetadata
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            editedColumn
                .frame(width: 180)
            Divider()
            serverColumn
                .frame(width: 180)
            Divider()
            hardcoverColumn
                .frame(maxWidth: .infinity)
        }
        .padding()
        .onAppear { loadCovers() }
        .sheet(item: $previewingCover) { cover in
            coverPreviewSheet(cover)
        }
    }

    private func loadCovers() {
        guard let metadata else { return }
        mediaViewModel.ensureCoverLoaded(for: metadata, variant: .standard)
        if metadata.hasAvailableAudiobook {
            mediaViewModel.ensureCoverLoaded(for: metadata, variant: .audioSquare)
        }
    }

    // MARK: - Preview Cover

    private enum PreviewCover: Identifiable {
        case swiftImage(Image, String)
        case data(Data, String)
        case url(URL, String)

        var id: String {
            switch self {
            case .swiftImage(_, let label): return "img-\(label)"
            case .data(_, let label): return "data-\(label)"
            case .url(let url, _): return url.absoluteString
            }
        }
    }

    @ViewBuilder
    private func coverPreviewSheet(_ cover: PreviewCover) -> some View {
        VStack(spacing: 0) {
            HStack {
                switch cover {
                case .swiftImage(_, let label), .data(_, let label), .url(_, let label):
                    Text(label).font(.headline)
                }
                Spacer()
                Button("Done") { previewingCover = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            switch cover {
            case .swiftImage(let image, _):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .data(let data, _):
                dataImage(data)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .url(let url, _):
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if case .failure = phase {
                        Text("Failed to load image")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding()
        .frame(width: 600, height: 700)
    }

    private func dataImage(_ data: Data) -> Image {
        #if canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        #elseif canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #endif
        return Image(systemName: "photo")
    }

    private func resolutionString(from data: Data) -> String? {
        #if canImport(AppKit)
        guard let img = NSImage(data: data), let rep = img.representations.first else { return nil }
        return "\(rep.pixelsWide) x \(rep.pixelsHigh)"
        #elseif canImport(UIKit)
        guard let img = UIImage(data: data) else { return nil }
        let w = Int(img.size.width * img.scale)
        let h = Int(img.size.height * img.scale)
        return "\(w) x \(h)"
        #else
        return nil
        #endif
    }

    private func serverCoverResolution(variant: MediaViewModel.CoverVariant) -> String? {
        guard let metadata else { return nil }
        #if canImport(AppKit)
        let state = mediaViewModel.coverState(for: metadata, variant: variant)
        guard let nsImage = state.nsImage, let rep = nsImage.representations.first else { return nil }
        return "\(rep.pixelsWide) x \(rep.pixelsHigh)"
        #else
        return nil
        #endif
    }

    private func magnifyButton(preview: PreviewCover) -> some View {
        Button(action: { previewingCover = preview }) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var refreshCacheButton: some View {
        Button {
            Task { await refreshCoverCache() }
        } label: {
            if isRefreshingCoverCache {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
            }
        }
        .buttonStyle(.borderless)
        .disabled(isRefreshingCoverCache || metadata == nil)
        .help("Reload this book's covers from Storyteller")
    }

    // MARK: - Server Column

    @ViewBuilder
    private var serverColumn: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack(spacing: 6) {
                Text("Storyteller Server")
                    .font(.headline)
                    .foregroundStyle(.white)
                refreshCacheButton
            }

            if let metadata {
                referenceCover(
                    label: "Ebook Cover",
                    image: mediaViewModel.coverImage(for: metadata, variant: .standard),
                    aspectRatio: 2.0 / 3.0,
                    color: .white,
                    help: "Revert to server ebook cover",
                    preview: mediaViewModel.coverImage(for: metadata, variant: .standard)
                        .map { .swiftImage($0, "Server Ebook Cover") },
                    resolution: serverCoverResolution(variant: .standard),
                    onRevert: { clearCover(audio: false) }
                )

                if metadata.hasAvailableAudiobook {
                    referenceCover(
                        label: "Audiobook Cover",
                        image: mediaViewModel.coverImage(for: metadata, variant: .audioSquare),
                        aspectRatio: 1.0,
                        color: .white,
                        help: "Revert to server audiobook cover",
                        preview: mediaViewModel.coverImage(for: metadata, variant: .audioSquare)
                            .map { .swiftImage($0, "Server Audiobook Cover") },
                        resolution: serverCoverResolution(variant: .audioSquare),
                        onRevert: { clearCover(audio: true) }
                    )
                }
            }
        }
    }

    // MARK: - Edited Column

    @ViewBuilder
    private var editedColumn: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack(spacing: 6) {
                Text("Covers to save")
                    .font(.headline)

                Button {
                    didCopyBookId = false
                    showBookIdPopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Show book UUID for Storyteller image cache cleanup")
                .popover(isPresented: $showBookIdPopover, arrowEdge: .bottom) {
                    bookIdPopover
                }
            }

            editedCoverSlot(
                label: "Ebook Cover",
                replacementData: book?.replacementEbookCover?.data,
                serverImage: metadata.flatMap {
                    mediaViewModel.coverImage(for: $0, variant: .standard)
                },
                serverResolution: serverCoverResolution(variant: .standard),
                aspectRatio: 2.0 / 3.0,
                onReplace: { showEbookPicker = true }
            )
            #if canImport(UniformTypeIdentifiers)
            .fileImporter(
                isPresented: $showEbookPicker,
                allowedContentTypes: [.png, .jpeg, .webP, .heic],
                onCompletion: { result in handleFilePick(result, audio: false) }
            )
            #endif

            if metadata?.hasAvailableAudiobook == true {
                editedCoverSlot(
                    label: "Audiobook Cover",
                    replacementData: book?.replacementAudiobookCover?.data,
                    serverImage: metadata.flatMap {
                        mediaViewModel.coverImage(for: $0, variant: .audioSquare)
                    },
                    serverResolution: serverCoverResolution(variant: .audioSquare),
                    aspectRatio: 1.0,
                    onReplace: { showAudiobookPicker = true }
                )
                #if canImport(UniformTypeIdentifiers)
                .fileImporter(
                    isPresented: $showAudiobookPicker,
                    allowedContentTypes: [.png, .jpeg, .webP, .heic],
                    onCompletion: { result in handleFilePick(result, audio: true) }
                )
                #endif
            }
        }
    }

    private var bookIdPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Book UUID")
                .font(.headline)

            Text(bookId)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Button {
                copyBookIdToClipboard()
                didCopyBookId = true
            } label: {
                Label(
                    didCopyBookId ? "Copied" : "Copy UUID",
                    systemImage: didCopyBookId ? "checkmark" : "doc.on.doc"
                )
            }
        }
        .padding()
        .frame(width: 320, alignment: .leading)
    }

    private func copyBookIdToClipboard() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bookId, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = bookId
        #endif
    }

    // MARK: - Hardcover Column

    private struct EditionCover: Identifiable {
        let id: Int
        let edition: HardcoverEditionInfo
        let url: URL
        let isDefault: Bool
    }

    private var editionCovers: [EditionCover] {
        guard let details = book?.lastImportedDetails else { return [] }
        var covers: [EditionCover] = []
        var seenUrls: Set<URL> = []

        for edition in filteredEditions(details.editions) {
            guard let imageUrl = edition.imageUrl, let url = URL(string: imageUrl) else { continue }
            guard seenUrls.insert(url).inserted else { continue }
            let isDefault = imageUrl == details.imageUrl
            covers.append(EditionCover(id: edition.id, edition: edition, url: url, isDefault: isDefault))
        }

        return covers
    }

    private var rectangularEditionCovers: [EditionCover] {
        editionCovers.filter { !isAudiobookEdition($0.edition) }
    }

    private var squareEditionCovers: [EditionCover] {
        editionCovers.filter { isAudiobookEdition($0.edition) }
    }

    private var rectangularItunesResults: [ITunesCoverResult] {
        itunesResults.filter { $0.mediaType != "audiobook" }
    }

    private var squareItunesResults: [ITunesCoverResult] {
        itunesResults.filter { $0.mediaType == "audiobook" }
    }

    @ViewBuilder
    private var hardcoverColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Text("Hardcover / iTunes Import")
                    .font(.headline)
                    .foregroundStyle(.blue)

                HStack(spacing: 8) {
                    Spacer()

                    hardcoverClearButton
                        .controlSize(.small)

                    itunesSearchButton
                        .controlSize(.small)

                    let hasFilter = editionFilterLanguage != nil || editionFilterFormat != nil || minResolution != nil
                    Button(action: { showFilterPopover.toggle() }) {
                        Image(systemName: hasFilter
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(hasFilter ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showFilterPopover) {
                        editionFilterPopover
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 28, alignment: .top)

            let covers = editionCovers
            if covers.isEmpty && itunesResults.isEmpty {
                if book?.lastImportedDetails != nil {
                    Text("No editions match filters")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else {
                    Text("--")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                }
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 16) {
                        coverResultGroup(
                            title: "Ebook / Print",
                            editionCovers: rectangularEditionCovers,
                            itunesResults: rectangularItunesResults
                        )

                        coverResultGroup(
                            title: "Audiobook",
                            editionCovers: squareEditionCovers,
                            itunesResults: squareItunesResults
                        )
                    }
                    .padding(.horizontal, 4)
                }
            }

            if isLoadingHCImage {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func coverResultGroup(
        title: String,
        editionCovers: [EditionCover],
        itunesResults: [ITunesCoverResult]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 100, maximum: 180), spacing: 12),
                    GridItem(.flexible(minimum: 100, maximum: 180), spacing: 12),
                ],
                spacing: 16
            ) {
                ForEach(editionCovers) { cover in
                    hcCoverCard(cover: cover)
                }
                ForEach(itunesResults) { result in
                    itunesCoverCard(result: result)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var hardcoverClearButton: some View {
        if book?.lastImportedDetails != nil {
            Button("Clear Hardcover Covers") {
                guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else {
                    return
                }
                viewModel.books[index].lastImportedDetails = nil
                viewModel.books[index].lastImportedFields = []
            }
            .help("Clear imported Hardcover covers")
        }
    }

    @ViewBuilder
    private var itunesSearchButton: some View {
        if itunesResults.isEmpty {
            Button("Download Covers from iTunes") {
                guard let book else { return }
                viewModel.searchItunes(book: book)
            }
            .disabled(book == nil || viewModel.isSearchingItunes(for: bookId))
            .help("Download covers from iTunes")
        } else {
            Button("Clear iTunes Covers") {
                viewModel.clearItunesResults(for: bookId)
            }
            .help("Clear covers from iTunes")
        }
    }

    @ViewBuilder
    private func hcCoverCard(cover: EditionCover) -> some View {
        let edition = cover.edition
        VStack(spacing: 6) {
            AsyncImage(url: cover.url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(radius: 1)
                case .failure:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .overlay {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                case .empty:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .overlay { ProgressView().controlSize(.small) }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxHeight: 200)

            HStack(spacing: 2) {
                let label = editionLabel(edition, isDefault: cover.isDefault)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)

                Button(action: {
                    infoPopoverId = infoPopoverId == cover.id ? nil : cover.id
                }) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .popover(isPresented: Binding(
                    get: { infoPopoverId == cover.id },
                    set: { if !$0 { infoPopoverId = nil } }
                )) {
                    editionInfoPopover(edition: edition)
                }

                magnifyButton(preview: .url(cover.url, editionLabel(edition, isDefault: cover.isDefault)))
            }

            if let w = edition.imageWidth, let h = edition.imageHeight {
                Text("\(w) x \(h)")
                    .font(.caption)
                    .foregroundStyle(.blue.opacity(0.7))
            }

            VStack(spacing: 4) {
                Button("Use as Ebook Cover") {
                    Task { await downloadAndStage(url: cover.url, audio: false) }
                }
                .controlSize(.small)
                .disabled(isLoadingHCImage)

                if metadata?.hasAvailableAudiobook == true {
                    Button("Use as Audiobook Cover") {
                        Task { await downloadAndStage(url: cover.url, audio: true) }
                    }
                    .controlSize(.small)
                    .disabled(isLoadingHCImage)
                }
            }
        }
    }

    // MARK: - iTunes Cover Card

    @ViewBuilder
    private func itunesCoverCard(result: ITunesCoverResult) -> some View {
        VStack(spacing: 6) {
            AsyncImage(url: result.thumbnailUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(radius: 1)
                case .failure:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .overlay {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                case .empty:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .overlay { ProgressView().controlSize(.small) }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxHeight: 200)

            HStack(spacing: 2) {
                Text(result.mediaType == "ebook" ? "iTunes Ebook" : "iTunes Audiobook")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                magnifyButton(preview: .url(result.hiresUrl, result.title))
            }

            Text(result.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                Button("Use as Ebook Cover") {
                    Task {
                        await downloadAndStage(
                            urls: result.artworkUrls,
                            audio: false,
                            source: "iTunes ebook cover"
                        )
                    }
                }
                .controlSize(.small)
                .disabled(isLoadingHCImage)

                if metadata?.hasAvailableAudiobook == true {
                    Button("Use as Audiobook Cover") {
                        Task {
                            await downloadAndStage(
                                urls: result.artworkUrls,
                                audio: true,
                                source: "iTunes audiobook cover"
                            )
                        }
                    }
                    .controlSize(.small)
                    .disabled(isLoadingHCImage)
                }
            }
        }
    }

    private func editionLabel(_ edition: HardcoverEditionInfo, isDefault: Bool) -> String {
        if isDefault && edition.id == 0 { return "Default" }
        var label = normalizedFormat(edition.format)
        if let lang = edition.language { label += " (\(lang))" }
        if isDefault { label += " *" }
        return label
    }

    // MARK: - Edition Info Popover

    @ViewBuilder
    private func editionInfoPopover(edition: HardcoverEditionInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(edition.editionInfo ?? edition.format).font(.headline)
                infoRow("Title", edition.title)
                infoRow("Subtitle", edition.subtitle)
                infoRow("Language", edition.language)
                infoRow("Release Date", edition.releaseDate)
                infoRow("Pages", edition.pages.map { "\($0)" })
                if let secs = edition.audioSeconds, secs > 0 {
                    infoRow("Audio Length", "\(secs / 3600)h \((secs % 3600) / 60)m")
                }
                infoRow("Publisher", edition.publisher)
                infoRow("Country", edition.country)
                infoRow("ISBN-13", edition.isbn13)
                infoRow("ISBN-10", edition.isbn10)
                infoRow("ASIN", edition.asin)
                if let w = edition.imageWidth, let h = edition.imageHeight {
                    infoRow("Cover Resolution", "\(w) x \(h)")
                }
                if !edition.narrators.isEmpty {
                    infoRow("Narrators", edition.narrators.joined(separator: ", "))
                }
                if !edition.otherContributors.isEmpty {
                    infoRow("Contributors",
                        edition.otherContributors.map { "\($0.name) (\($0.role))" }
                            .joined(separator: ", "))
                }
            }
            .padding()
        }
        .frame(width: 320, height: 280)
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) {
                Text(value).lineLimit(2)
            }
            .font(.callout)
        }
    }

    // MARK: - Edition Filters

    private static let digitalFormats: Set<String> = ["Ebook", "Kindle", "Audible", "Audiobook"]
    private static let physicalFormats: Set<String> = ["Hardcover", "Paperback", "Mass Market Paperback"]
    private static let ebookFormats: Set<String> = ["Ebook", "Kindle"]
    private static let audiobookFormats: Set<String> = ["Audible", "Audiobook"]

    private func filteredEditions(_ editions: [HardcoverEditionInfo]) -> [HardcoverEditionInfo] {
        editions.filter { edition in
            if let lang = editionFilterLanguage {
                guard edition.language?.lowercased() == lang.lowercased() else { return false }
            }
            if let fmt = editionFilterFormat {
                let normalized = normalizedFormat(edition.format)
                switch fmt {
                case "digital":
                    guard Self.digitalFormats.contains(normalized) else { return false }
                case "physical":
                    guard Self.physicalFormats.contains(normalized) else { return false }
                case "ebook":
                    guard Self.ebookFormats.contains(normalized) else { return false }
                case "audiobook":
                    guard Self.audiobookFormats.contains(normalized) else { return false }
                default:
                    guard normalized == fmt else { return false }
                }
            }
            if let minRes = minResolution {
                let maxDim = max(edition.imageWidth ?? 0, edition.imageHeight ?? 0)
                guard maxDim >= minRes else { return false }
            }
            return true
        }
    }

    private func isAudiobookEdition(_ edition: HardcoverEditionInfo) -> Bool {
        Self.audiobookFormats.contains(normalizedFormat(edition.format))
            || (edition.audioSeconds ?? 0) > 0
    }

    private static let formatNormalization: [String: String] = [
        "ebook": "Ebook", "e-book": "Ebook", "kindle": "Kindle", "epub3": "Ebook",
        "audible": "Audible", "audiobook": "Audiobook", "unabridged audiobook": "Audiobook",
        "hardcover": "Hardcover", "paperback": "Paperback",
        "mass market paperback": "Mass Market Paperback",
    ]

    private func normalizedFormat(_ format: String) -> String {
        Self.formatNormalization[format.lowercased()]
            ?? {
                guard let first = format.first else { return format }
                return String(first).uppercased() + format.dropFirst()
            }()
    }

    private var availableResolutions: [Int] {
        let editions = book?.lastImportedDetails?.editions ?? []
        let dims = editions.compactMap { ed -> Int? in
            guard let w = ed.imageWidth, let h = ed.imageHeight else { return nil }
            return max(w, h)
        }
        return Array(Set(dims)).sorted()
    }

    @ViewBuilder
    private var editionFilterPopover: some View {
        let editions = book?.lastImportedDetails?.editions ?? []
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
                    Text("Ebook Only").tag(Optional("ebook"))
                    Text("Audiobook Only").tag(Optional("audiobook"))
                    Divider()
                    ForEach(formats, id: \.self) { fmt in
                        Text(fmt).tag(Optional(fmt))
                    }
                }
                .labelsHidden()
            }

            let resolutions = availableResolutions
            if !resolutions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Min Resolution").font(.subheadline).foregroundStyle(.secondary)
                    Picker("", selection: $minResolution) {
                        Text("Any").tag(Int?.none)
                        ForEach(resolutions, id: \.self) { res in
                            Text("\(res)px+").tag(Optional(res))
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button("Clear Filters") {
                    editionFilterLanguage = nil
                    editionFilterFormat = nil
                    minResolution = nil
                }
                .disabled(
                    editionFilterLanguage == nil && editionFilterFormat == nil
                    && minResolution == nil
                )
                .font(.callout)
            }
        }
        .padding()
        .frame(width: 220)
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func referenceCover(
        label: String, image: Image?, aspectRatio: CGFloat,
        color: Color, help: String, preview: PreviewCover?,
        resolution: String?,
        onRevert: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 2)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxHeight: 240)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
            }
            if let resolution {
                Text(resolution)
                    .font(.caption)
                    .foregroundStyle(color.opacity(0.7))
            }
            HStack(spacing: 4) {
                RevertButton(color: color, help: help, action: onRevert)
                if let preview {
                    magnifyButton(preview: preview)
                }
            }
        }
    }

    @ViewBuilder
    private func editedCoverSlot(
        label: String,
        replacementData: Data?,
        serverImage: Image?,
        serverResolution: String?,
        aspectRatio: CGFloat,
        onReplace: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let data = replacementData {
                #if canImport(AppKit)
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(radius: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange, lineWidth: 2)
                        )
                }
                #elseif canImport(UIKit)
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(radius: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange, lineWidth: 2)
                        )
                }
                #endif
                if let res = resolutionString(from: data) {
                    Text(res)
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.7))
                }
            } else if let serverImage {
                serverImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 2)
                if let serverResolution {
                    Text(serverResolution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxHeight: 240)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
            }

            HStack(spacing: 4) {
                Button("From file...") { onReplace() }
                    .controlSize(.small)
                if let data = replacementData {
                    magnifyButton(preview: .data(data, label))
                } else if let serverImage {
                    magnifyButton(preview: .swiftImage(serverImage, label))
                }
            }
        }
    }

    // MARK: - Actions

    private func handleFilePick(_ result: Result<URL, Error>, audio: Bool) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else { return }
        let filename = url.lastPathComponent

        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        if audio {
            viewModel.books[index].replacementAudiobookCover = (data: data, filename: filename)
        } else {
            viewModel.books[index].replacementEbookCover = (data: data, filename: filename)
        }
    }

    private func clearCover(audio: Bool) {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        if audio {
            viewModel.books[index].replacementAudiobookCover = nil
        } else {
            viewModel.books[index].replacementEbookCover = nil
        }
    }

    private func refreshCoverCache() async {
        guard let metadata else { return }
        isRefreshingCoverCache = true
        defer { isRefreshingCoverCache = false }

        await mediaViewModel.refreshCover(for: metadata, variant: .standard)
        if metadata.hasAvailableAudiobook {
            await mediaViewModel.refreshCover(for: metadata, variant: .audioSquare)
        }
    }

    private func downloadAndStage(url: URL, audio: Bool) async {
        await downloadAndStage(urls: [url], audio: audio, source: "cover")
    }

    private func downloadAndStage(urls: [URL], audio: Bool, source: String) async {
        isLoadingHCImage = true
        defer { isLoadingHCImage = false }

        var lastFailure: String?

        for url in urls {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                if let httpResponse = response as? HTTPURLResponse,
                    !(200..<300).contains(httpResponse.statusCode)
                {
                    lastFailure = "HTTP \(httpResponse.statusCode)"
                    continue
                }

                if let mimeType = response.mimeType?.lowercased(),
                    !mimeType.hasPrefix("image/")
                {
                    lastFailure = "unexpected content type \(mimeType)"
                    continue
                }

                guard !data.isEmpty else {
                    lastFailure = "empty response"
                    continue
                }

                guard isValidImageData(data) else {
                    lastFailure = "response was not a valid image"
                    continue
                }

                let filename = coverFilename(from: url, response: response)
                stageCover(data: data, filename: filename, audio: audio)
                viewModel.saveError = nil
                return
            } catch {
                lastFailure = error.localizedDescription
            }
        }

        viewModel.saveError =
            "Failed to download \(source): \(lastFailure ?? "no valid image variants were available")"
    }

    private func stageCover(data: Data, filename: String, audio: Bool) {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        if audio {
            viewModel.books[index].replacementAudiobookCover = (data: data, filename: filename)
        } else {
            viewModel.books[index].replacementEbookCover = (data: data, filename: filename)
        }
    }

    private func isValidImageData(_ data: Data) -> Bool {
        #if canImport(AppKit)
        return NSImage(data: data) != nil
        #elseif canImport(UIKit)
        return UIImage(data: data) != nil
        #else
        return !data.isEmpty
        #endif
    }

    private func coverFilename(from url: URL, response: URLResponse) -> String {
        let filename = url.lastPathComponent
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]
        if imageExtensions.contains(url.pathExtension.lowercased()) {
            return filename
        }

        switch response.mimeType?.lowercased() {
        case "image/png":
            return "cover.png"
        case "image/webp":
            return "cover.webp"
        case "image/heic", "image/heif":
            return "cover.heic"
        default:
            return "cover.jpg"
        }
    }
}
