import SwiftUI

struct MediaCompactListRowView: View {
    let item: BookMetadata
    let isSelected: Bool
    let onSelect: (BookMetadata) -> Void
    let onInfo: (BookMetadata) -> Void
    @Environment(MediaViewModel.self) private var mediaViewModel
    #if os(macOS)
    @State private var hoveredMediaType: MediaType?
    #endif

    private let rowHeight: CGFloat = 32

    var body: some View {
        #if os(iOS)
        NavigationLink(value: item) {
            rowContent
        }
        .buttonStyle(.plain)
        #else
        rowContent
        #endif
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            let progress = mediaViewModel.progress(for: item.id)
            progressBar(progress: progress)

            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let authorName = item.authors?.first?.name {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Text(authorName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            mediaButtons
                .layoutPriority(1)

            #if os(macOS)
            Button {
                onInfo(item)
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
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
        #endif
    }

    private func progressBar(progress: Double) -> some View {
        let clamped = min(max(progress, 0), 1)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.accentColor.opacity(0.2))
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 40 * CGFloat(clamped))
        }
        .frame(width: 40, height: 3)
    }

    private var mediaButtons: some View {
        HStack(spacing: 2) {
            mediaButton(for: .ebook)
            mediaButton(for: .audio)
            mediaButton(for: .synced)
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

    private func mediaColor(for status: (available: Bool, downloaded: Bool, downloading: Bool, progress: Double?)) -> Color {
        if !status.available {
            return .gray.opacity(0.3)
        } else if status.downloaded {
            return .green
        } else {
            return .blue
        }
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
                            .font(.system(size: 14))
                            .foregroundStyle(color)
                    } else if let progress = status.progress {
                        ZStack {
                            Circle()
                                .stroke(color.opacity(0.3), lineWidth: 1.5)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(color, lineWidth: 1.5)
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 14, height: 14)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                } else if isHovered && status.available && !status.downloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                } else if isHovered && status.downloaded {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                } else if type == .synced {
                    ReadaloudIcon(size: 12)
                        .foregroundStyle(color)
                } else {
                    Image(systemName: type.iconName)
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 22, height: 22)
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
}
