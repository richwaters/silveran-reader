import SwiftUI

struct MediaListRowView: View {
    let item: BookMetadata
    let mediaKind: MediaKind
    let coverPreference: CoverPreference
    let showAudioIndicator: Bool
    let sourceLabel: String?
    let seriesPositionBadge: String?
    let isSelected: Bool
    let onSelect: (BookMetadata) -> Void
    let onInfo: (BookMetadata) -> Void
    @Environment(MediaViewModel.self) private var mediaViewModel
    #if os(macOS)
    @State private var hoveredMediaType: MediaType?
    #endif

    private let rowHeight: CGFloat = 72
    private let coverSize: CGFloat = 56
    private let horizontalPadding: CGFloat = 12
    private let contentSpacing: CGFloat = 12

    var body: some View {
        #if os(iOS)
        if let playerData = preferredPlayerBookData {
            NavigationLink(value: playerData) {
                rowContent
            }
            .buttonStyle(.plain)
            .contextMenu { iOSContextMenu }
        } else {
            NavigationLink(value: item) {
                rowContent
            }
            .buttonStyle(.plain)
            .contextMenu { iOSContextMenu }
        }
        #else
        rowContent
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var iOSContextMenu: some View {
        Button {
            onInfo(item)
        } label: {
            Label("View Details", systemImage: "info.circle")
        }
    }

    private var preferredPlayerBookData: PlayerBookData? {
        let settings = mediaViewModel.cachedConfig.library
        guard settings.tapToPlayPreferredPlayer else { return nil }

        let syncedDownloaded = mediaViewModel.isCategoryDownloaded(.synced, for: item)
        let audioDownloaded = mediaViewModel.isCategoryDownloaded(.audio, for: item)
        let ebookDownloaded = mediaViewModel.isCategoryDownloaded(.ebook, for: item)

        let category: LocalMediaCategory?
        if syncedDownloaded {
            category = .synced
        } else if audioDownloaded && ebookDownloaded {
            category = settings.preferAudioOverEbook ? .audio : .ebook
        } else if audioDownloaded {
            category = .audio
        } else if ebookDownloaded {
            category = .ebook
        } else {
            category = nil
        }

        guard let category else { return nil }
        let freshMetadata = mediaViewModel.library.bookMetaData.first { $0.id == item.id } ?? item
        let path = mediaViewModel.localMediaPath(for: item.id, category: category)
        let variant: MediaViewModel.CoverVariant = freshMetadata.hasAvailableAudiobook ? .audioSquare : .standard
        let cover = mediaViewModel.coverImage(for: freshMetadata, variant: variant)
        let ebookCover = freshMetadata.hasAvailableAudiobook
            ? mediaViewModel.coverImage(for: freshMetadata, variant: .standard)
            : nil
        return PlayerBookData(
            metadata: freshMetadata,
            localMediaPath: path,
            category: category,
            coverArt: cover,
            ebookCoverArt: ebookCover
        )
    }
    #endif

    private var rowContent: some View {
        HStack(spacing: contentSpacing) {
            coverView
            contentView
            Spacer(minLength: 0)
            trailingView
        }
        #if os(iOS)
        .padding(.leading, horizontalPadding)
        .padding(.trailing, 28)
        #else
        .padding(.horizontal, horizontalPadding)
        #endif
        .padding(.vertical, 8)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                #if os(macOS)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                #else
                .fill(Color.clear)
                #endif
        )
        .contentShape(Rectangle())
        #if os(macOS)
        .onTapGesture {
            onSelect(item)
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onInfo(item)
                }
        )
        .contextMenu {
            contextMenu
        }
        #endif
    }

    private var coverView: some View {
        let coverVariant = resolveCoverVariant(for: item)
        let aspectRatio = coverVariant.preferredAspectRatio
        let coverWidth = coverSize * aspectRatio
        let coverState = mediaViewModel.coverState(for: item, variant: coverVariant)
        let placeholderColor = Color(white: 0.2)

        return ZStack {
            placeholderColor
            if let image = coverState.image {
                image
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            }
        }
        .frame(width: coverWidth, height: coverSize)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if showAudioIndicator && coverVariant == .standard && (item.hasAvailableReadaloud || item.hasAvailableAudiobook) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.7))
                    if item.hasAvailableReadaloud {
                        Image("readalong")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                            .foregroundStyle(.gray)
                    } else {
                        Image(systemName: "headphones")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.gray)
                    }
                }
                .frame(width: 16, height: 16)
                .padding(2)
            }
        }
        .task {
            mediaViewModel.ensureCoverLoaded(for: item, variant: coverVariant)
        }
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let badge = seriesPositionBadge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let authorName = item.authors?.first?.name {
                Text(authorName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            let progress = mediaViewModel.progress(for: item.id)
            if progress > 0 {
                GeometryReader { geometry in
                    let clamped = min(max(progress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.2))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * CGFloat(clamped))
                    }
                }
                .frame(height: 3)
                .frame(maxWidth: 120)
            }
        }
    }

    private var trailingView: some View {
        HStack(spacing: 4) {
            mediaButton(for: .ebook)
            mediaButton(for: .audio)
            mediaButton(for: .synced)

            #if os(macOS)
            Button {
                onInfo(item)
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    private enum MediaType {
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

    private func mediaColor(for status: (available: Bool, downloaded: Bool, downloading: Bool, progress: Double?)) -> Color {
        if !status.available {
            return .gray.opacity(0.3)
        } else if status.downloaded {
            return .green
        } else {
            return .blue
        }
    }

    private func mediaStatus(for type: MediaType) -> (available: Bool, downloaded: Bool, downloading: Bool, progress: Double?) {
        let category = type.category
        let downloading = mediaViewModel.isCategoryDownloadInProgress(for: item, category: category)
        let downloaded = mediaViewModel.isCategoryDownloaded(category, for: item)
        let progress = downloading ? mediaViewModel.downloadProgressFraction(for: item, category: category) : nil

        let available: Bool
        switch type {
        case .ebook: available = item.hasAvailableEbook
        case .audio: available = item.hasAvailableAudiobook
        case .synced: available = item.hasAvailableReadaloud
        }

        return (available, downloaded, downloading, progress)
    }

    @ViewBuilder
    private func mediaButton(for type: MediaType) -> some View {
        let status = mediaStatus(for: type)
        let color = mediaColor(for: status)
        #if os(macOS)
        let isHovered = hoveredMediaType == type
        #else
        let isHovered = false
        #endif

        Button {
            handleMediaTap(for: type, status: status)
        } label: {
            ZStack {
                if status.downloading {
                    if isHovered {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(color)
                    } else if let progress = status.progress {
                        ZStack {
                            Circle()
                                .stroke(color.opacity(0.3), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(color, lineWidth: 2)
                                .rotationEffect(.degrees(-90))
                            #if os(iOS)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(color)
                            #endif
                        }
                        .frame(width: 18, height: 18)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else if isHovered && status.available && !status.downloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(color)
                } else if isHovered && status.downloaded {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(color)
                } else if type == .synced {
                    ReadaloudIcon(size: 16)
                        .foregroundStyle(color)
                } else {
                    Image(systemName: type.iconName)
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!status.available)
        #if os(macOS)
        .onHover { hovering in
            hoveredMediaType = hovering ? type : nil
        }
        #endif
    }

    private func handleMediaTap(for type: MediaType, status: (available: Bool, downloaded: Bool, downloading: Bool, progress: Double?)) {
        let category = type.category

        if status.downloading {
            mediaViewModel.cancelDownload(for: item, category: category)
        } else if status.downloaded {
            #if os(macOS)
            openMedia(for: category)
            #endif
        } else if status.available {
            mediaViewModel.startDownload(for: item, category: category)
        }
    }

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow

    private func openMedia(for category: LocalMediaCategory) {
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
    #endif

    private func resolveCoverVariant(for item: BookMetadata) -> MediaViewModel.CoverVariant {
        switch coverPreference {
        case .preferEbook:
            if item.hasAvailableEbook {
                return .standard
            }
            return item.hasAvailableAudiobook ? .audioSquare : .standard
        case .preferAudiobook:
            if item.hasAvailableAudiobook || item.isAudiobookOnly {
                return .audioSquare
            }
            return .standard
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var contextMenu: some View {
        let ebookDownloaded = mediaViewModel.isCategoryDownloaded(.ebook, for: item)
        let audioDownloaded = mediaViewModel.isCategoryDownloaded(.audio, for: item)
        let syncedDownloaded = mediaViewModel.isCategoryDownloaded(.synced, for: item)

        if ebookDownloaded || audioDownloaded || syncedDownloaded {
            if ebookDownloaded {
                Button(role: .destructive) {
                    mediaViewModel.deleteDownload(for: item, category: .ebook)
                } label: {
                    Label("Local Ebook", systemImage: "trash")
                }
            }

            if audioDownloaded {
                Button(role: .destructive) {
                    mediaViewModel.deleteDownload(for: item, category: .audio)
                } label: {
                    Label("Local Audiobook", systemImage: "trash")
                }
            }

            if syncedDownloaded {
                Button(role: .destructive) {
                    mediaViewModel.deleteDownload(for: item, category: .synced)
                } label: {
                    Label("Local Readaloud", systemImage: "trash")
                }
            }
        }
    }
    #endif
}
