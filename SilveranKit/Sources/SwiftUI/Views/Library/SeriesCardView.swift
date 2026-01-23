import SwiftUI

struct SeriesCardView: View {
    let series: BookSeries?
    let books: [BookMetadata]
    let mediaKind: MediaKind
    let coverPreference: CoverPreference
    let onTap: () -> Void
    @Environment(MediaViewModel.self) private var mediaViewModel
    @State private var isHovered = false

    private let tileWidth: CGFloat = 125
    private let cardPadding: CGFloat = 4
    private var coverWidth: CGFloat { max(tileWidth - (cardPadding * 2), tileWidth * 0.90) }
    private let coverCornerRadius: CGFloat = 12
    private let contentSpacing: CGFloat = 8
    private let titleContainerHeight: CGFloat = 32

    private var containerAspectRatio: CGFloat { coverPreference.preferredContainerAspectRatio }
    private var coverHeight: CGFloat { coverWidth / containerAspectRatio }

    private var maxCardHeight: CGFloat {
        let progressBarHeight: CGFloat = 3
        let subtitleRowHeight: CGFloat = 20
        let subtitleBottomPadding: CGFloat = 4
        let titleToSubtitleGap: CGFloat = 2
        return (cardPadding * 2) + coverHeight + progressBarHeight + contentSpacing + titleContainerHeight + titleToSubtitleGap + subtitleRowHeight + subtitleBottomPadding
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                fanCoverStack
                    .frame(width: coverWidth, height: coverHeight)

                Color.clear
                    .frame(width: coverWidth, height: 3)

                Spacer(minLength: contentSpacing)
                    .frame(height: contentSpacing)

                VStack(alignment: .leading, spacing: 0) {
                    Text(series?.name ?? "No Series")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 8)
                        .frame(height: titleContainerHeight, alignment: .top)

                    subtitleRow
                        .padding(.top, 2)
                }
            }
            .padding(cardPadding)
            .frame(width: tileWidth, height: maxCardHeight, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.25)) {
                isHovered = hovering
            }
        }
        #endif
    }

    private var subtitleRow: some View {
        HStack(spacing: 2) {
            Text("\(books.count) book\(books.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var fanCoverStack: some View {
        let displayBooks = Array(books.prefix(3))
        let placeholderColor = Color(white: 0.2)

        let fanSpread: CGFloat = isHovered ? 18 : 6
        let fanRotation: Double = isHovered ? 8 : 3
        let centerOffset = CGFloat(displayBooks.count - 1) * fanSpread / 2

        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let availableHeight = geometry.size.height
            let singleCoverHeight = availableHeight * (isHovered ? 0.92 : 0.88)
            let singleCoverWidth = singleCoverHeight * containerAspectRatio

            ZStack {
                ForEach(Array(displayBooks.reversed().enumerated()), id: \.offset) { index, book in
                    let coverVariant = resolveCoverVariant(for: book)
                    let coverState = mediaViewModel.coverState(for: book, variant: coverVariant)
                    let position = displayBooks.count - 1 - index
                    let xOffset = CGFloat(position) * fanSpread - centerOffset
                    let rotation = Double(position - (displayBooks.count - 1) / 2) * fanRotation

                    ZStack {
                        placeholderColor
                        if let image = coverState.image {
                            image
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                        }
                    }
                    .frame(width: singleCoverWidth, height: singleCoverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                    .rotationEffect(.degrees(rotation))
                    .offset(x: xOffset)
                    .task {
                        mediaViewModel.ensureCoverLoaded(for: book, variant: coverVariant)
                    }
                }
            }
            .frame(width: availableWidth, height: availableHeight)
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
}
