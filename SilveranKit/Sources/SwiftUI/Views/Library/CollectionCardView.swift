import SwiftUI

struct CollectionCardView: View {
    let collection: BookCollectionSummary?
    let books: [BookMetadata]
    let mediaKind: MediaKind
    let coverPreference: CoverPreference
    let onTap: () -> Void
    @Environment(MediaViewModel.self) private var mediaViewModel

    private let cardWidth: CGFloat = 180
    private let coverHeight: CGFloat = 160
    private let cornerRadius: CGFloat = 12

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .center, spacing: 10) {
                coverStack
                    .frame(width: cardWidth - 16, height: coverHeight)

                VStack(alignment: .center, spacing: 4) {
                    Text(collection?.name ?? "Unknown Collection")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text("\(books.count) book\(books.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            }
            .padding(8)
            .frame(width: cardWidth)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var coverStack: some View {
        let displayBooks = Array(books.prefix(3))
        let placeholderColor = Color(white: 0.2)

        ZStack {
            ForEach(Array(displayBooks.reversed().enumerated()), id: \.offset) { index, book in
                let coverVariant = resolveCoverVariant(for: book)
                let aspectRatio = coverVariant.preferredAspectRatio
                let coverState = mediaViewModel.coverState(for: book, variant: coverVariant)
                let offset = CGFloat(displayBooks.count - 1 - index) * 8

                ZStack {
                    placeholderColor
                    if let image = coverState.image {
                        image
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                    }
                }
                .frame(width: coverHeight * aspectRatio * 0.7, height: coverHeight * 0.85)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                .offset(x: offset, y: -offset)
                .task {
                    mediaViewModel.ensureCoverLoaded(for: book, variant: coverVariant)
                }
            }
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
