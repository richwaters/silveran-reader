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
    enum CoverScope: String, CaseIterable, Identifiable {
        case audiobook
        case ebook

        var id: String { rawValue }

        var isAudio: Bool { self == .audiobook }
        var label: String { isAudio ? "Audiobook Cover" : "Ebook Cover" }
        var serverPreviewLabel: String { isAudio ? "Server Audiobook Cover" : "Server Ebook Cover" }
        var aspectRatio: CGFloat { isAudio ? 1.0 : 2.0 / 3.0 }
        var variant: MediaViewModel.CoverVariant { isAudio ? .audioSquare : .standard }
        var resultGroupTitle: String { isAudio ? "Audiobook" : "Ebook / Print" }
        var useButtonTitle: String { isAudio ? "Use as Audiobook Cover" : "Use as Ebook Cover" }
    }

    let bookId: String
    @Bindable var viewModel: MetadataEditorViewModel
    let scope: CoverScope
    let openHardcoverImport: () -> Void
    @Environment(MediaViewModel.self) private var mediaViewModel

    @State private var showEbookPicker = false
    @State private var showAudiobookPicker = false
    @State private var isLoadingHCImage = false
    @State private var isRefreshingCoverCache = false
    @State private var infoPopoverId: Int?
    @State private var previewingCover: PreviewCover?
    @State private var showBookIdPopover = false
    @State private var didCopyBookId = false
    @State private var selectedHardcoverCoverId: Int?
    @State private var selectedItunesResultId: String?
    @State private var stagedImportSourceId: String?

    @AppStorage("hardcoverImport.filterLanguage") private var editionFilterLanguage: String?
    @AppStorage("hardcoverImport.filterFormat") private var editionFilterFormat: String?
    @State private var minResolution: Int?
    @State private var showFilterPopover = false
    @State private var hardcoverSort: CoverImportSort = .relevance
    @State private var itunesSort: CoverImportSort = .relevance
    @State private var validatedItunesArtwork: [String: ValidatedItunesArtwork] = [:]
    @State private var validatingItunesArtwork: Set<String> = []

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
        TransferColumnRow(
            leftWeight: 1,
            centerWeight: 1,
            rightWeight: 2,
            leftCanCopy: stagedCoverData != nil,
            leftHelp: "Use server \(scope.label.lowercased())",
            leftAction: { clearCover(audio: scope.isAudio) },
            rightCanCopy: selectedImportCanCopy,
            rightHelp: selectedImportCanCopy
                ? "Use selected imported \(scope.label.lowercased())" : "Select an imported cover",
            rightAction: stageSelectedImportCover
        ) {
            serverColumn
        } center: {
            editedColumn
        } right: {
            importsColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .clipped()
        .onAppear { loadCovers() }
        .task(id: itunesValidationTaskId) {
            await validateScopedItunesArtwork()
        }
        .sheet(item: $previewingCover) { cover in
            coverPreviewSheet(cover)
        }
    }

    private var stagedCoverData: Data? {
        scope.isAudio ? book?.replacementAudiobookCover?.data : book?.replacementEbookCover?.data
    }

    private var selectedHardcoverCover: EditionCover? {
        guard let selectedHardcoverCoverId else { return nil }
        return scopedEditionCovers.first { $0.id == selectedHardcoverCoverId }
    }

    private var selectedItunesResult: ITunesCoverResult? {
        guard let selectedItunesResultId else { return nil }
        return scopedItunesResults.first { $0.id == selectedItunesResultId }
    }

    private var selectedImportCanCopy: Bool {
        guard let selectedImportSourceId else { return false }
        return selectedImportSourceId != stagedImportSourceId
    }

    private var selectedImportSourceId: String? {
        if let selectedHardcoverCover {
            return hardcoverImportSourceId(selectedHardcoverCover)
        }

        if let selectedItunesResult {
            return itunesImportSourceId(selectedItunesResult)
        }

        return nil
    }

    private var itunesValidationTaskId: String {
        scopedItunesResults.map(\.id).joined(separator: "|")
    }

    private func loadCovers() {
        guard let metadata else { return }
        mediaViewModel.ensureCoverLoaded(for: metadata, variant: scope.variant)
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
            coverColumnTitle("Storyteller Server", accessory: AnyView(refreshCacheButton))

            if let metadata {
                referenceCover(
                    label: scope.label,
                    image: mediaViewModel.coverImage(for: metadata, variant: scope.variant),
                    aspectRatio: scope.aspectRatio,
                    color: .white,
                    help: "Revert to server \(scope.label.lowercased())",
                    preview: mediaViewModel.coverImage(for: metadata, variant: scope.variant)
                        .map { .swiftImage($0, scope.serverPreviewLabel) },
                    resolution: serverCoverResolution(variant: scope.variant),
                    showRevertButton: false,
                    onRevert: { clearCover(audio: scope.isAudio) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Edited Column

    @ViewBuilder
    private var editedColumn: some View {
        VStack(alignment: .center, spacing: 16) {
            coverColumnTitle("Current Cover", accessory: AnyView(bookIdInfoButton))

            editedCoverSlot(
                label: scope.label,
                replacementData: scope.isAudio ? book?.replacementAudiobookCover?.data : book?.replacementEbookCover?.data,
                serverImage: metadata.flatMap {
                    mediaViewModel.coverImage(for: $0, variant: scope.variant)
                },
                serverResolution: serverCoverResolution(variant: scope.variant),
                aspectRatio: scope.aspectRatio,
                onReplace: {
                    if scope.isAudio {
                        showAudiobookPicker = true
                    } else {
                        showEbookPicker = true
                    }
                }
            )
            #if canImport(UniformTypeIdentifiers)
            .fileImporter(
                isPresented: $showEbookPicker,
                allowedContentTypes: [.png, .jpeg, .webP, .heic],
                onCompletion: { result in handleFilePick(result, audio: false) }
            )
            .fileImporter(
                isPresented: $showAudiobookPicker,
                allowedContentTypes: [.png, .jpeg, .webP, .heic],
                onCompletion: { result in handleFilePick(result, audio: true) }
            )
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func coverColumnTitle(_ title: String, accessory: AnyView? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let accessory {
                accessory
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var bookIdInfoButton: some View {
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

    // MARK: - Imports Column

    private struct EditionCover: Identifiable {
        let id: Int
        let edition: HardcoverEditionInfo
        let url: URL
        let isDefault: Bool
    }

    private enum CoverImportSort: String, CaseIterable, Identifiable {
        case relevance = "Relevance"
        case resolution = "Resolution"

        var id: String { rawValue }
    }

    private struct ValidatedItunesArtwork {
        let url: URL
        let width: Int
        let height: Int
    }

    private var editionCovers: [EditionCover] {
        guard let details = book?.hardcoverImports[hardcoverSource] else { return [] }
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

    private var hardcoverSource: MetadataEditorViewModel.HardcoverImportSource {
        scope.isAudio ? .audiobook : .text
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

    private var scopedEditionCovers: [EditionCover] {
        let covers = scope.isAudio ? squareEditionCovers : rectangularEditionCovers
        switch hardcoverSort {
        case .relevance:
            return covers
        case .resolution:
            return covers.sorted { hardcoverResolutionValue($0) > hardcoverResolutionValue($1) }
        }
    }

    private var scopedItunesResults: [ITunesCoverResult] {
        let results = scope.isAudio ? squareItunesResults : rectangularItunesResults
        switch itunesSort {
        case .relevance:
            return results
        case .resolution:
            return results.sorted { itunesResolutionValue($0) > itunesResolutionValue($1) }
        }
    }

    @ViewBuilder
    private var importsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Imports")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            importRow(
                title: "Hardcover",
                controls: {
                    hardcoverClearButton
                        .controlSize(.small)

                    sortButton(sort: $hardcoverSort)

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
                },
                empty: {
                    if book?.hardcoverImports[hardcoverSource] != nil {
                        Text("No editions match filters")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        ImportHardcoverDataLink(action: openHardcoverImport)
                    }
                }
            ) {
                ForEach(scopedEditionCovers) { cover in
                    hardcoverImportCard(cover)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()

            Divider()
                .padding(.leading, 34)

            importRow(
                title: "iTunes",
                controls: {
                    itunesClearButton
                        .controlSize(.small)

                    sortButton(sort: $itunesSort)
                },
                empty: {
                    Button("Import iTunes Data") {
                        guard let book else { return }
                        viewModel.searchItunes(book: book)
                    }
                    .buttonStyle(.link)
                    .font(.callout.weight(.semibold))
                    .disabled(book == nil || viewModel.isSearchingItunes(for: bookId))
                }
            ) {
                ForEach(scopedItunesResults) { result in
                    itunesImportCard(result)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if isLoadingHCImage {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func importRow<Controls: View, Empty: View, Content: View>(
        title: String,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder empty: () -> Empty,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                controls()
            }
            .frame(height: 24, alignment: .center)
            .padding(.leading, 34)

            if title == "Hardcover" && scopedEditionCovers.isEmpty
                || title == "iTunes" && scopedItunesResults.isEmpty
            {
                empty()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        content()
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.visible, axes: .horizontal)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var hardcoverClearButton: some View {
        Button("Clear Hardcover Covers") {
            if book?.hardcoverImports[hardcoverSource] != nil {
                guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else {
                    return
                }
                viewModel.books[index].hardcoverImports[hardcoverSource] = nil
                viewModel.books[index].hardcoverImportFields[hardcoverSource] = nil
            }
        }
        .disabled(book?.hardcoverImports[hardcoverSource] == nil)
        .opacity(book?.hardcoverImports[hardcoverSource] == nil ? 0 : 1)
        .help("Clear imported Hardcover covers")
    }

    private var itunesClearButton: some View {
        Button("Clear iTunes Covers") {
            if !itunesResults.isEmpty {
                viewModel.clearItunesResults(for: bookId)
            }
        }
        .disabled(itunesResults.isEmpty || viewModel.isSearchingItunes(for: bookId))
        .opacity(itunesResults.isEmpty ? 0 : 1)
        .help("Clear covers from iTunes")
    }

    private func sortButton(sort: Binding<CoverImportSort>) -> some View {
        Menu {
            Picker("Sort Covers", selection: sort) {
                ForEach(CoverImportSort.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Image(systemName: sort.wrappedValue == .resolution
                ? "arrow.up.arrow.down.circle.fill"
                : "arrow.up.arrow.down.circle")
            .foregroundStyle(sort.wrappedValue == .resolution ? Color.accentColor : .secondary)
        }
        .menuStyle(.borderlessButton)
        .help("Sort covers")
    }

    private func hardcoverResolutionValue(_ cover: EditionCover) -> Int {
        guard let width = cover.edition.imageWidth, let height = cover.edition.imageHeight else {
            return 0
        }
        return max(width, height)
    }

    private func itunesResolutionValue(_ result: ITunesCoverResult) -> Int {
        guard let artwork = validatedItunesArtwork[result.id] else { return 0 }
        return max(artwork.width, artwork.height)
    }

    private var importCardWidth: CGFloat { 148 }
    private var importCoverMaxWidth: CGFloat { scope.isAudio ? 134 : 100 }

    private func bestItunesUrl(for result: ITunesCoverResult) -> URL {
        validatedItunesArtwork[result.id]?.url ?? result.hiresUrl
    }

    private func itunesDownloadUrls(for result: ITunesCoverResult) -> [URL] {
        var urls: [URL] = []
        var seen: Set<URL> = []

        if let validatedUrl = validatedItunesArtwork[result.id]?.url, seen.insert(validatedUrl).inserted {
            urls.append(validatedUrl)
        }

        for url in result.artworkUrls where seen.insert(url).inserted {
            urls.append(url)
        }

        return urls
    }

    private func artworkResolution(from url: URL) -> (width: Int, height: Int)? {
        let fileName = url.lastPathComponent
        guard let range = fileName.range(
            of: #"\d+x\d+"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let parts = fileName[range].split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1])
        else {
            return nil
        }
        return (width, height)
    }

    private func validateScopedItunesArtwork() async {
        for result in scopedItunesResults {
            await validateItunesArtwork(result)
        }
    }

    private func validateItunesArtwork(_ result: ITunesCoverResult) async {
        guard validatedItunesArtwork[result.id] == nil,
              !validatingItunesArtwork.contains(result.id)
        else {
            return
        }

        validatingItunesArtwork.insert(result.id)
        defer { validatingItunesArtwork.remove(result.id) }

        for url in result.artworkUrls {
            guard let resolution = artworkResolution(from: url) else { continue }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard isUsableImageResponse(data: data, response: response) else { continue }
                validatedItunesArtwork[result.id] = ValidatedItunesArtwork(
                    url: url,
                    width: resolution.width,
                    height: resolution.height
                )
                return
            } catch {
                continue
            }
        }
    }

    @ViewBuilder
    private func hardcoverImportCard(_ cover: EditionCover) -> some View {
        let isSelected = selectedHardcoverCoverId == cover.id
        let edition = cover.edition

        Button {
            selectedHardcoverCoverId = cover.id
            selectedItunesResultId = nil
        } label: {
            VStack(spacing: 6) {
                AsyncImage(url: cover.url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        coverPlaceholder(systemName: "exclamationmark.triangle")
                    case .empty:
                        coverPlaceholder(systemName: nil)
                            .overlay { ProgressView().controlSize(.small) }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: importCoverMaxWidth, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .layoutPriority(1)

                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Text(editionLabel(edition, isDefault: cover.isDefault))
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
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(" ")
                            .font(.caption2)
                    }
                }
                .frame(height: 34, alignment: .top)
            }
            .frame(width: importCardWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func itunesImportCard(_ result: ITunesCoverResult) -> some View {
        let isSelected = selectedItunesResultId == result.id

        Button {
            selectedItunesResultId = result.id
            selectedHardcoverCoverId = nil
        } label: {
            VStack(spacing: 6) {
                AsyncImage(url: result.thumbnailUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        coverPlaceholder(systemName: "exclamationmark.triangle")
                    case .empty:
                        coverPlaceholder(systemName: nil)
                            .overlay { ProgressView().controlSize(.small) }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: importCoverMaxWidth, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .layoutPriority(1)

                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Text(result.mediaType == "ebook" ? "iTunes Ebook" : "iTunes Audiobook")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)

                        magnifyButton(preview: .url(bestItunesUrl(for: result), result.title))
                    }

                    if let artwork = validatedItunesArtwork[result.id] {
                        Text("\(artwork.width) x \(artwork.height)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if validatingItunesArtwork.contains(result.id) {
                        Text("Checking...")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(" ")
                            .font(.caption2)
                    }

                    Text(result.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 50, alignment: .top)
            }
            .frame(width: importCardWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func coverPlaceholder(systemName: String?) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .aspectRatio(scope.aspectRatio, contentMode: .fit)
            .overlay {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
                Button(scope.useButtonTitle) {
                    Task {
                        await downloadAndStage(
                            url: cover.url,
                            audio: scope.isAudio,
                            sourceId: hardcoverImportSourceId(cover)
                        )
                    }
                }
                .controlSize(.small)
                .disabled(isLoadingHCImage)
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

                magnifyButton(preview: .url(bestItunesUrl(for: result), result.title))
            }

            Text(result.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let artwork = validatedItunesArtwork[result.id] {
                Text("\(artwork.width) x \(artwork.height)")
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.7))
            } else if validatingItunesArtwork.contains(result.id) {
                Text("Checking...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 4) {
                Button(scope.useButtonTitle) {
                    Task {
                        await downloadAndStage(
                            urls: itunesDownloadUrls(for: result),
                            audio: scope.isAudio,
                            source: scope.isAudio ? "iTunes audiobook cover" : "iTunes ebook cover",
                            sourceId: itunesImportSourceId(result)
                        )
                    }
                }
                .controlSize(.small)
                .disabled(isLoadingHCImage)
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
        let editions = book?.hardcoverImports[hardcoverSource]?.editions ?? []
        let dims = editions.compactMap { ed -> Int? in
            guard let w = ed.imageWidth, let h = ed.imageHeight else { return nil }
            return max(w, h)
        }
        return Array(Set(dims)).sorted()
    }

    @ViewBuilder
    private var editionFilterPopover: some View {
        let editions = book?.hardcoverImports[hardcoverSource]?.editions ?? []
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
        showRevertButton: Bool = true,
        onRevert: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 220)
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 2)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: 220)
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
                if showRevertButton {
                    RevertButton(color: color, help: help, action: onRevert)
                }
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
            if let data = replacementData {
                #if canImport(AppKit)
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 220)
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
                        .frame(maxWidth: 220)
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
                    .frame(maxWidth: 220)
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
                    .frame(maxWidth: 220)
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
        stagedImportSourceId = nil
    }

    private func clearCover(audio: Bool) {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        if audio {
            viewModel.books[index].replacementAudiobookCover = nil
        } else {
            viewModel.books[index].replacementEbookCover = nil
        }
        stagedImportSourceId = nil
    }

    private func stageSelectedImportCover() {
        if let selectedHardcoverCover {
            Task {
                await downloadAndStage(
                    url: selectedHardcoverCover.url,
                    audio: scope.isAudio,
                    sourceId: hardcoverImportSourceId(selectedHardcoverCover)
                )
            }
            return
        }

        if let selectedItunesResult {
            Task {
                await downloadAndStage(
                    urls: itunesDownloadUrls(for: selectedItunesResult),
                    audio: scope.isAudio,
                    source: scope.isAudio ? "iTunes audiobook cover" : "iTunes ebook cover",
                    sourceId: itunesImportSourceId(selectedItunesResult)
                )
            }
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

    private func downloadAndStage(url: URL, audio: Bool, sourceId: String? = nil) async {
        await downloadAndStage(urls: [url], audio: audio, source: "cover", sourceId: sourceId)
    }

    private func downloadAndStage(urls: [URL], audio: Bool, source: String, sourceId: String? = nil) async {
        isLoadingHCImage = true
        defer { isLoadingHCImage = false }

        var lastFailure: String?

        for url in urls {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                if let failure = imageResponseFailure(data: data, response: response) {
                    lastFailure = failure
                    continue
                }

                let filename = coverFilename(from: url, response: response)
                stageCover(data: data, filename: filename, audio: audio, sourceId: sourceId)
                viewModel.saveError = nil
                return
            } catch {
                lastFailure = error.localizedDescription
            }
        }

        viewModel.saveError =
            "Failed to download \(source): \(lastFailure ?? "no valid image variants were available")"
    }

    private func isUsableImageResponse(data: Data, response: URLResponse) -> Bool {
        imageResponseFailure(data: data, response: response) == nil
    }

    private func imageResponseFailure(data: Data, response: URLResponse) -> String? {
        if let httpResponse = response as? HTTPURLResponse,
            !(200..<300).contains(httpResponse.statusCode)
        {
            return "HTTP \(httpResponse.statusCode)"
        }

        if let mimeType = response.mimeType?.lowercased(),
            !mimeType.hasPrefix("image/")
        {
            return "unexpected content type \(mimeType)"
        }

        guard !data.isEmpty else {
            return "empty response"
        }

        guard isValidImageData(data) else {
            return "response was not a valid image"
        }

        return nil
    }

    private func stageCover(data: Data, filename: String, audio: Bool, sourceId: String?) {
        guard let index = viewModel.books.firstIndex(where: { $0.id == bookId }) else { return }
        if audio {
            viewModel.books[index].replacementAudiobookCover = (data: data, filename: filename)
        } else {
            viewModel.books[index].replacementEbookCover = (data: data, filename: filename)
        }
        stagedImportSourceId = sourceId
    }

    private func hardcoverImportSourceId(_ cover: EditionCover) -> String {
        "hardcover:\(cover.id):\(cover.url.absoluteString)"
    }

    private func itunesImportSourceId(_ result: ITunesCoverResult) -> String {
        "itunes:\(result.id)"
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
