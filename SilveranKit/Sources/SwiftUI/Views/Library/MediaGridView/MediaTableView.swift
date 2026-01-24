#if os(macOS)
import SwiftUI

struct MediaTableView: View {
    let items: [BookMetadata]
    let mediaKind: MediaKind
    let coverPreference: CoverPreference
    let showAudioIndicator: Bool
    let compact: Bool
    @Binding var selection: BookMetadata.ID?
    @Binding var columnCustomization: TableColumnCustomization<BookMetadata>
    @Binding var sortOrder: [KeyPathComparator<BookMetadata>]
    let onSelect: (BookMetadata) -> Void
    let onInfo: (BookMetadata) -> Void

    @Environment(MediaViewModel.self) private var mediaViewModel
    @FocusState private var isTableFocused: Bool

    private var coverHeight: CGFloat { compact ? 24 : 40 }

    var body: some View {
        Table(of: BookMetadata.self, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("") { item in
                TableCoverCell(
                    item: item,
                    coverPreference: coverPreference,
                    height: coverHeight,
                    mediaViewModel: mediaViewModel
                )
            }
            .width(min: 30, ideal: compact ? 36 : 50, max: 70)
            .customizationID("cover")
            .defaultVisibility(.visible)

            TableColumn("Title", value: \.title) { item in
                if compact {
                    Text(item.title)
                        .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .lineLimit(1)
                        if let author = item.authors?.first?.name {
                            Text(author)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .width(min: 100, ideal: 200)
            .customizationID("title")
            .defaultVisibility(.visible)

            TableColumn("Author", value: \.sortableAuthor) { item in
                Text(item.authors?.first?.name ?? "")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 150)
            .customizationID("author")
            .defaultVisibility(.visible)

            TableColumn("Series", value: \.sortableSeries) { item in
                TableSeriesCell(item: item)
            }
            .width(min: 80, ideal: 140)
            .customizationID("series")
            .defaultVisibility(.visible)

            TableColumn("Progress", value: \.progress) { item in
                TableProgressCell(
                    item: item,
                    compact: compact,
                    mediaViewModel: mediaViewModel
                )
            }
            .width(min: 60, ideal: 100, max: 140)
            .customizationID("progress")
            .defaultVisibility(.hidden)

            TableColumn("Narrator", value: \.sortableNarrator) { item in
                Text(item.narrators?.first?.name ?? "")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
            .customizationID("narrator")
            .defaultVisibility(.hidden)

            TableColumn("Status", value: \.sortableStatus) { item in
                Text(item.status?.name ?? "")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            .customizationID("status")
            .defaultVisibility(.hidden)

            TableColumn("Added", value: \.sortableAdded) { item in
                Text(formatDate(item.createdAt))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
            .customizationID("added")
            .defaultVisibility(.hidden)

            TableColumn("Tags", value: \.sortableTags) { item in
                Text(item.sortableTags)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
            .customizationID("tags")
            .defaultVisibility(.hidden)

            TableColumn("Media") { item in
                TableMediaIndicatorCell(
                    item: item,
                    compact: compact,
                    mediaViewModel: mediaViewModel
                )
            }
            .width(min: 100, ideal: 120, max: 150)
            .customizationID("media")
            .defaultVisibility(.visible)
        } rows: {
            ForEach(items) { item in
                TableRow(item)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .onChange(of: selection) { _, newValue in
            if let id = newValue, let item = items.first(where: { $0.id == id }) {
                onSelect(item)
                onInfo(item)
            }
        }
        .contextMenu(forSelectionType: BookMetadata.ID.self) { selectedIDs in
            if let id = selectedIDs.first, let item = items.first(where: { $0.id == id }) {
                Button("Show Details") {
                    onInfo(item)
                }
            }
        } primaryAction: { selectedIDs in
            if let id = selectedIDs.first, let item = items.first(where: { $0.id == id }) {
                onInfo(item)
            }
        }
        .focused($isTableFocused)
        .onAppear {
            isTableFocused = true
        }
        .onHover { hovering in
            if hovering {
                isTableFocused = true
            }
        }
        .id(TableIdentity(sortOrder: sortOrder))
    }

    private func formatDate(_ dateString: String?) -> String {
        guard let dateString, !dateString.isEmpty else { return "" }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var date: Date?
        date = isoFormatter.date(from: dateString)

        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: dateString)
        }

        if date == nil {
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.dateFormat = "yyyy-MM-dd"
            date = fallbackFormatter.date(from: dateString)
        }

        guard let parsedDate = date else { return dateString }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .none
        return displayFormatter.string(from: parsedDate)
    }
}

private struct TableCoverCell: View {
    let item: BookMetadata
    let coverPreference: CoverPreference
    let height: CGFloat
    let mediaViewModel: MediaViewModel

    var body: some View {
        let coverVariant = resolveCoverVariant(for: item)
        let aspectRatio = coverVariant.preferredAspectRatio
        let width = height * aspectRatio
        let coverState = mediaViewModel.coverState(for: item, variant: coverVariant)

        ZStack {
            Color(white: 0.2)
            if let image = coverState.image {
                image
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .task {
            mediaViewModel.ensureCoverLoaded(for: item, variant: coverVariant)
        }
    }

    private func resolveCoverVariant(for item: BookMetadata) -> MediaViewModel.CoverVariant {
        switch coverPreference {
        case .preferEbook:
            if item.hasAvailableEbook { return .standard }
            return item.hasAvailableAudiobook ? .audioSquare : .standard
        case .preferAudiobook:
            if item.hasAvailableAudiobook || item.isAudiobookOnly { return .audioSquare }
            return .standard
        }
    }
}

private struct TableSeriesCell: View {
    let item: BookMetadata

    var body: some View {
        if let series = item.series?.first {
            HStack(spacing: 4) {
                Text(series.name)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                if let position = series.position {
                    Text("#\(position)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Text("")
        }
    }
}

private struct TableProgressCell: View {
    let item: BookMetadata
    let compact: Bool
    let mediaViewModel: MediaViewModel

    var body: some View {
        let progress = mediaViewModel.progress(for: item.id)
        let clamped = min(max(progress, 0), 1)

        HStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.2))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * CGFloat(clamped))
                }
            }
            .frame(height: compact ? 3 : 4)

            Text("\(Int(clamped * 100))%")
                .font(.system(size: compact ? 10 : 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

private struct TableMediaIndicatorCell: View {
    let item: BookMetadata
    let compact: Bool
    let mediaViewModel: MediaViewModel

    @Environment(\.openWindow) private var openWindow
    @State private var hoveredType: MediaType?
    @State private var showConnectionAlert = false

    private var iconSize: CGFloat { compact ? 14 : 20 }
    private var smallIconSize: CGFloat { compact ? 11 : 16 }
    private var readaloudSize: CGFloat { compact ? 12 : 18 }
    private var buttonSize: CGFloat { compact ? 20 : 28 }

    private var hasConnectionError: Bool {
        if mediaViewModel.lastNetworkOpSucceeded == false { return true }
        if case .error = mediaViewModel.connectionStatus { return true }
        return false
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            mediaButton(for: .ebook)
            mediaButton(for: .audio)
            mediaButton(for: .synced)
        }
        .alert("Connection Error", isPresented: $showConnectionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cannot download media while disconnected from the server.")
        }
    }

    private enum MediaType: CaseIterable {
        case ebook, audio, synced

        var category: LocalMediaCategory {
            switch self {
            case .ebook: return .ebook
            case .audio: return .audio
            case .synced: return .synced
            }
        }

        var iconName: String {
            switch self {
            case .ebook: return "book.fill"
            case .audio: return "headphones"
            case .synced: return "text.bubble"
            }
        }
    }

    private enum MediaStatus: Equatable {
        case unavailable
        case availableNotDownloaded
        case downloaded
        case downloading(progress: Double?)

        var color: Color {
            switch self {
            case .unavailable: return .gray.opacity(0.3)
            case .availableNotDownloaded: return .blue
            case .downloaded: return .green
            case .downloading: return .blue
            }
        }
    }

    private func mediaStatus(for type: MediaType) -> MediaStatus {
        let category = type.category

        if mediaViewModel.isCategoryDownloadInProgress(for: item, category: category) {
            let progress = mediaViewModel.downloadProgressFraction(for: item, category: category)
            return .downloading(progress: progress)
        }

        if mediaViewModel.isCategoryDownloaded(category, for: item) {
            return .downloaded
        }

        let available: Bool
        switch type {
        case .ebook: available = item.hasAvailableEbook
        case .audio: available = item.hasAvailableAudiobook
        case .synced: available = item.hasAvailableReadaloud
        }

        return available ? .availableNotDownloaded : .unavailable
    }

    @ViewBuilder
    private func mediaButton(for type: MediaType) -> some View {
        let status = mediaStatus(for: type)
        let isHovered = hoveredType == type

        Button {
            handleTap(for: type, status: status)
        } label: {
            ZStack {
                if case .downloading(let progress) = status {
                    if isHovered {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: iconSize))
                    } else if let progress {
                        ZStack {
                            Circle()
                                .stroke(status.color.opacity(0.3), lineWidth: compact ? 2 : 2.5)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(status.color, lineWidth: compact ? 2 : 2.5)
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: iconSize, height: iconSize)
                    } else {
                        ProgressView()
                            .controlSize(compact ? .mini : .small)
                    }
                } else if isHovered && status == .availableNotDownloaded {
                    if hasConnectionError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: smallIconSize))
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: iconSize))
                    }
                } else if isHovered && status == .downloaded {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: iconSize))
                } else {
                    if type == .synced {
                        ReadaloudIcon(size: readaloudSize)
                    } else {
                        Image(systemName: type.iconName)
                            .font(.system(size: smallIconSize))
                    }
                }
            }
            .foregroundStyle(status.color)
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(status == .unavailable)
        .onHover { hovering in
            hoveredType = hovering ? type : nil
        }
        .contextMenu {
            if status == .downloaded {
                Button(role: .destructive) {
                    mediaViewModel.deleteDownload(for: item, category: type.category)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func handleTap(for type: MediaType, status: MediaStatus) {
        let category = type.category

        switch status {
        case .availableNotDownloaded:
            if hasConnectionError {
                showConnectionAlert = true
            } else {
                mediaViewModel.startDownload(for: item, category: category)
            }
        case .downloaded:
            openMedia(for: category)
        case .downloading:
            mediaViewModel.cancelDownload(for: item, category: category)
        case .unavailable:
            break
        }
    }

    private func openMedia(for category: LocalMediaCategory) {
        guard #available(macOS 13.0, *) else { return }
        let windowID: String
        switch category {
        case .audio:
            windowID = "AudiobookPlayer"
        case .ebook, .synced:
            windowID = "EbookPlayer"
        }
        let path = mediaViewModel.localMediaPath(for: item.id, category: category)
        let variant: MediaViewModel.CoverVariant = item.hasAvailableAudiobook ? .audioSquare : .standard
        let cover = mediaViewModel.coverImage(for: item, variant: variant)
        let ebookCover = item.hasAvailableAudiobook
            ? mediaViewModel.coverImage(for: item, variant: .standard)
            : nil
        let bookData = PlayerBookData(
            metadata: item,
            localMediaPath: path,
            category: category,
            coverArt: cover,
            ebookCoverArt: ebookCover
        )
        openWindow(id: windowID, value: bookData)
    }
}

private struct TableIdentity: Hashable {
    let sortKeyPath: String
    let sortOrder: SortOrder

    init(sortOrder: [KeyPathComparator<BookMetadata>]) {
        if let first = sortOrder.first {
            self.sortKeyPath = String(describing: first.keyPath)
            self.sortOrder = first.order
        } else {
            self.sortKeyPath = ""
            self.sortOrder = .forward
        }
    }
}
#endif
