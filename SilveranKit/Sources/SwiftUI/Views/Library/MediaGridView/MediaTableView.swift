#if os(macOS)
import SwiftUI

public struct TableColumnVisibility: Equatable, Hashable {
    public var cover: Bool
    public var title: Bool
    public var author: Bool
    public var series: Bool
    public var progress: Bool
    public var media: Bool
    public var narrator: Bool
    public var status: Bool
    public var added: Bool
    public var tags: Bool

    public static func defaultVisibility(compact: Bool) -> TableColumnVisibility {
        TableColumnVisibility(
            cover: true,
            title: true,
            author: compact,
            series: true,
            progress: true,
            media: true,
            narrator: false,
            status: false,
            added: false,
            tags: false
        )
    }

    public static var allVisible: TableColumnVisibility {
        TableColumnVisibility(
            cover: true,
            title: true,
            author: true,
            series: true,
            progress: true,
            media: true,
            narrator: true,
            status: true,
            added: true,
            tags: true
        )
    }
}

extension TableColumnVisibility: RawRepresentable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Bool]
        else { return nil }
        self.cover = json["cover"] ?? true
        self.title = json["title"] ?? true
        self.author = json["author"] ?? true
        self.series = json["series"] ?? true
        self.progress = json["progress"] ?? true
        self.media = json["media"] ?? true
        self.narrator = json["narrator"] ?? false
        self.status = json["status"] ?? false
        self.added = json["added"] ?? false
        self.tags = json["tags"] ?? false
    }

    public var rawValue: String {
        let dict: [String: Bool] = [
            "cover": cover,
            "title": title,
            "author": author,
            "series": series,
            "progress": progress,
            "media": media,
            "narrator": narrator,
            "status": status,
            "added": added,
            "tags": tags
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}

struct MediaTableView: View {
    let items: [BookMetadata]
    let mediaKind: MediaKind
    let coverPreference: CoverPreference
    let showAudioIndicator: Bool
    let compact: Bool
    @Binding var selection: BookMetadata.ID?
    @Binding var columnVisibility: TableColumnVisibility
    let onSelect: (BookMetadata) -> Void
    let onInfo: (BookMetadata) -> Void

    @Environment(MediaViewModel.self) private var mediaViewModel

    private var coverHeight: CGFloat { compact ? 24 : 40 }

    var body: some View {
        Table(items, selection: $selection) {
            if columnVisibility.cover {
                TableColumn("") { item in
                    TableCoverCell(
                        item: item,
                        coverPreference: coverPreference,
                        height: coverHeight,
                        mediaViewModel: mediaViewModel
                    )
                }
                .width(min: 30, ideal: compact ? 36 : 50, max: 70)
            }

            if columnVisibility.title {
                TableColumn("Title") { item in
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
            }

            if columnVisibility.author {
                TableColumn("Author") { item in
                    Text(item.authors?.first?.name ?? "")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 150)
            }

            if columnVisibility.series {
                TableColumn("Series") { item in
                    TableSeriesCell(item: item)
                }
                .width(min: 80, ideal: 140)
            }

            if columnVisibility.progress {
                TableColumn("Progress") { item in
                    TableProgressCell(
                        item: item,
                        compact: compact,
                        mediaViewModel: mediaViewModel
                    )
                }
                .width(min: 60, ideal: 100, max: 140)
            }

            if columnVisibility.media {
                TableColumn("Media") { item in
                    TableMediaIndicatorCell(
                        item: item,
                        mediaViewModel: mediaViewModel,
                        onInfo: { onInfo(item) }
                    )
                }
                .width(min: 100, ideal: 120, max: 150)
            }

            if columnVisibility.narrator {
                TableColumn("Narrator") { item in
                    Text(item.narrators?.first?.name ?? "")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)
            }

            if columnVisibility.status {
                TableColumn("Status") { item in
                    Text(item.status?.name ?? "")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 80)
            }

            if columnVisibility.added {
                TableColumn("Added") { item in
                    Text(formatDate(item.createdAt))
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100)
            }

            if columnVisibility.tags {
                TableColumn("Tags") { item in
                    Text(item.tagNames.joined(separator: ", "))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .onChange(of: selection) { _, newValue in
            if let id = newValue, let item = items.first(where: { $0.id == id }) {
                onSelect(item)
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
        .id(columnVisibility)
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
    let mediaViewModel: MediaViewModel
    let onInfo: () -> Void

    @Environment(\.openWindow) private var openWindow
    @State private var hoveredType: MediaType?
    @State private var showConnectionAlert = false

    private var hasConnectionError: Bool {
        if mediaViewModel.lastNetworkOpSucceeded == false { return true }
        if case .error = mediaViewModel.connectionStatus { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 4) {
            mediaButton(for: .ebook)
            mediaButton(for: .audio)
            mediaButton(for: .synced)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            Button {
                onInfo()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
                            .font(.system(size: 14))
                    } else if let progress {
                        ZStack {
                            Circle()
                                .stroke(status.color.opacity(0.3), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(status.color, lineWidth: 2)
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 14, height: 14)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                } else if isHovered && status == .availableNotDownloaded {
                    if hasConnectionError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                    }
                } else if isHovered && status == .downloaded {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 14))
                } else {
                    if type == .synced {
                        ReadaloudIcon(size: 12)
                    } else {
                        Image(systemName: type.iconName)
                            .font(.system(size: 11))
                    }
                }
            }
            .foregroundStyle(status.color)
            .frame(width: 20, height: 20)
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
#endif
