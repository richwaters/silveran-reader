import SwiftUI

struct CategoryFanLayout<Header: View, ContextMenu: View>: View {
    let groups: [CategoryGroup]
    let mediaKind: MediaKind
    let coverPreference: CoverPreference
    let onNavigate: (CategoryGroup, BookMetadata?) -> Void
    @ViewBuilder let header: () -> Header
    let contextMenuBuilder: ((CategoryGroup) -> ContextMenu)?

    private let sectionSpacing: CGFloat = 32
    private let horizontalPadding: CGFloat = 24

    init(
        groups: [CategoryGroup],
        mediaKind: MediaKind,
        coverPreference: CoverPreference,
        onNavigate: @escaping (CategoryGroup, BookMetadata?) -> Void,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() },
        @ViewBuilder contextMenuBuilder: @escaping (CategoryGroup) -> ContextMenu
    ) {
        self.groups = groups
        self.mediaKind = mediaKind
        self.coverPreference = coverPreference
        self.onNavigate = onNavigate
        self.header = header
        self.contextMenuBuilder = contextMenuBuilder
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
                                onNavigate: onNavigate,
                                contextMenu: contextMenuBuilder?(group)
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

extension CategoryFanLayout where ContextMenu == EmptyView {
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
        self.contextMenuBuilder = nil
    }
}

struct CategoryFanSection<ContextMenu: View>: View {
    let group: CategoryGroup
    let mediaKind: MediaKind
    let stackWidth: CGFloat
    let coverPreference: CoverPreference
    let onNavigate: (CategoryGroup, BookMetadata?) -> Void
    let contextMenu: ContextMenu?

    @State private var settingsViewModel = SettingsViewModel()
    @State private var isCoverHovered = false
    @State private var isTitleHovered = false

    private var isHovered: Bool { isCoverHovered || isTitleHovered }

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
            .onHover { hovering in
                isCoverHovered = hovering
            }

            VStack(alignment: .center, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        onNavigate(group, nil)
                    } label: {
                        Text(group.name)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    if let pinId = group.pinId {
                        CategoryPinButton(pinId: pinId)
                            .opacity(isHovered || SidebarPinHelper.isPinned(pinId) ? 1 : 0)
                    }
                }

                Text("\(group.books.count) book\(group.books.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onHover { hovering in
                isTitleHovered = hovering
            }
        }
        .frame(maxWidth: .infinity)
        .modifier(OptionalContextMenuModifier(content: contextMenu))
    }
}

private struct OptionalContextMenuModifier<MenuContent: View>: ViewModifier {
    let content: MenuContent?

    func body(content: Content) -> some View {
        if let menuContent = self.content {
            content.contextMenu { menuContent }
        } else {
            content
        }
    }
}
