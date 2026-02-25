import SwiftUI

struct MediaCompactCardView: View {
    let item: BookMetadata
    let coverPreference: CoverPreference
    let tileSize: CGFloat
    let showAudioIndicator: Bool
    let sourceLabel: String?
    let seriesPositionBadge: String?
    let isSelected: Bool
    let onSelect: (BookMetadata) -> Void
    let onInfo: (BookMetadata) -> Void
    @Environment(MediaViewModel.self) private var mediaViewModel
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var isHovered = false
    @State private var hoveredTab: TabCategory?
    #endif

    var body: some View {
        #if os(iOS)
        NavigationLink(value: item) {
            cardContent
        }
        .buttonStyle(.plain)
        #else
        cardContent
        #endif
    }

    private var cardContent: some View {
        let coverVariant = resolveCoverVariant(for: item)
        let aspectRatio = coverPreference.preferredContainerAspectRatio
        let coverState = mediaViewModel.coverState(for: item, variant: coverVariant)
        let placeholderColor = Color(white: 0.2)
        let progress = mediaViewModel.progress(for: item.id)

        return VStack(spacing: 0) {
            ZStack {
                placeholderColor
                if let image = coverState.image {
                    image
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                }
            }
            .frame(width: tileSize, height: tileSize / aspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottom) {
                if progress > 0 {
                    GeometryReader { geometry in
                        let clamped = min(max(progress, 0), 1)
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.3))
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * CGFloat(clamped))
                        }
                    }
                    .frame(height: 3)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let sourceLabel = sourceLabel {
                    SourceBadge(label: sourceLabel)
                        .padding(2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showAudioIndicator {
                    AudioIndicatorBadge(item: item, coverVariant: coverVariant)
                        .padding(.trailing, 2)
                        .padding(.bottom, 2)
                }
            }
            .overlay(alignment: .topLeading) {
                if let badge = seriesPositionBadge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            .black.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                        .padding(2)
                }
            }
            #if os(macOS)
            .overlay(alignment: .top) {
                if isHovered {
                    topTabBar
                }
            }
            #endif
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onTapGesture {
            onSelect(item)
            onInfo(item)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
        .task(id: coverVariant) {
            mediaViewModel.ensureCoverLoaded(for: item, variant: coverVariant)
        }
    }

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
    private enum TabCategory: CaseIterable {
        case ebook, audio, synced

        var localCategory: LocalMediaCategory {
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

    private var topTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TabCategory.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .frame(width: tileSize, height: 40)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private enum TabStatus: Equatable {
        case unavailable
        case availableNotDownloaded
        case downloaded
        case downloading(progress: Double?)
        case failed
    }

    private func tabStatus(for tab: TabCategory) -> TabStatus {
        let category = tab.localCategory
        let downloading = mediaViewModel.isCategoryDownloadInProgress(for: item, category: category)
        if downloading {
            let progress = mediaViewModel.downloadProgressFraction(for: item, category: category)
            return .downloading(progress: progress)
        }

        let downloaded = mediaViewModel.isCategoryDownloaded(category, for: item)
        if downloaded { return .downloaded }

        if mediaViewModel.isCategoryDownloadFailed(for: item, category: category) {
            return .failed
        }

        let available: Bool
        switch tab {
            case .ebook: available = item.hasAvailableEbook
            case .audio: available = item.hasAvailableAudiobook
            case .synced: available = item.hasAvailableReadaloud
        }

        return available ? .availableNotDownloaded : .unavailable
    }

    private func statusColor(for status: TabStatus) -> Color {
        switch status {
            case .unavailable: return .gray.opacity(0.4)
            case .availableNotDownloaded: return .blue
            case .downloaded: return .green
            case .downloading: return .blue
            case .failed: return .red
        }
    }

    @ViewBuilder
    private func tabButton(for tab: TabCategory) -> some View {
        let status = tabStatus(for: tab)
        let color = statusColor(for: status)
        let isTabHovered = hoveredTab == tab

        Button {
            handleTabTap(for: tab)
        } label: {
            ZStack {
                if case .downloading(let progress) = status {
                    if isTabHovered {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                    } else if let progress = progress {
                        ZStack {
                            Circle()
                                .stroke(color.opacity(0.3), lineWidth: 2.5)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(color, lineWidth: 2.5)
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 24, height: 24)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(color)
                    }
                } else if status == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                } else if isTabHovered && status == .availableNotDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 24))
                } else if isTabHovered && status == .downloaded {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                } else if tab == .synced {
                    ReadaloudIcon(size: 26)
                } else {
                    Image(systemName: tab.iconName)
                        .font(.system(size: 20))
                }
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(status == .unavailable)
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
    }

    private func handleTabTap(for tab: TabCategory) {
        let category = tab.localCategory
        let status = tabStatus(for: tab)

        if case .downloading = status {
            mediaViewModel.cancelDownload(for: item, category: category)
        } else if status == .downloaded {
            openMedia(for: category)
        } else if status == .failed || status == .availableNotDownloaded {
            mediaViewModel.startDownload(for: item, category: category)
        }
    }

    private func openMedia(for category: LocalMediaCategory) {
        let windowID: String
        switch category {
            case .audio:
                windowID = "AudiobookPlayer"
            case .ebook, .synced:
                windowID = "EbookPlayer"
        }
        let path = mediaViewModel.localMediaPath(for: item.id, category: category)
        let variant: MediaViewModel.CoverVariant =
            item.hasAvailableAudiobook ? .audioSquare : .standard
        let cover = mediaViewModel.coverImage(for: item, variant: variant)
        let ebookCover =
            item.hasAvailableAudiobook
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
