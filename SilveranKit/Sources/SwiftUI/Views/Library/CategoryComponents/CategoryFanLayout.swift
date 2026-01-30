import SwiftUI

struct CategoryFanLayout<Header: View>: View {
    let groups: [CategoryGroup]
    let mediaKind: MediaKind
    let coverPreference: CoverPreference
    let onNavigate: (CategoryGroup, BookMetadata?) -> Void
    @ViewBuilder let header: () -> Header

    private let sectionSpacing: CGFloat = 32
    private let horizontalPadding: CGFloat = 24

    init(
        groups: [CategoryGroup],
        mediaKind: MediaKind,
        coverPreference: CoverPreference,
        onNavigate: @escaping (CategoryGroup, BookMetadata?) -> Void,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() }
    ) {
        self.groups = groups
        self.mediaKind = mediaKind
        self.coverPreference = coverPreference
        self.onNavigate = onNavigate
        self.header = header
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width
            let stackWidth = max(contentWidth - (horizontalPadding * 2), 100)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    header()
                        .padding(.horizontal, horizontalPadding)

                    LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                        ForEach(groups) { group in
                            CategoryFanSection(
                                group: group,
                                mediaKind: mediaKind,
                                stackWidth: stackWidth,
                                coverPreference: coverPreference,
                                onNavigate: onNavigate
                            )
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .frame(width: contentWidth)
            .contentMargins(.trailing, 10, for: .scrollIndicators)
            .modifier(SoftScrollEdgeModifier())
        }
    }
}

struct CategoryFanSection: View {
    let group: CategoryGroup
    let mediaKind: MediaKind
    let stackWidth: CGFloat
    let coverPreference: CoverPreference
    let onNavigate: (CategoryGroup, BookMetadata?) -> Void

    @State private var settingsViewModel = SettingsViewModel()

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            SeriesStackView(
                books: group.books,
                mediaKind: mediaKind,
                availableWidth: stackWidth,
                showAudioIndicator: settingsViewModel.showAudioIndicator,
                coverPreference: coverPreference,
                onSelect: { book in
                    onNavigate(group, book)
                }
            )
            .frame(maxWidth: stackWidth, alignment: .center)

            VStack(alignment: .center, spacing: 6) {
                Button {
                    onNavigate(group, nil)
                } label: {
                    Text(group.name)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)

                Text("\(group.books.count) book\(group.books.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            if let pinId = group.pinId {
                Button {
                    SidebarPinHelper.togglePin(pinId)
                } label: {
                    Label(
                        SidebarPinHelper.isPinned(pinId) ? "Unpin from Sidebar" : "Pin to Sidebar",
                        systemImage: SidebarPinHelper.isPinned(pinId) ? "pin.slash" : "pin"
                    )
                }
            }
        }
    }
}
