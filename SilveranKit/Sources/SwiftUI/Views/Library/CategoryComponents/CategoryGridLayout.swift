import SwiftUI

struct CategoryGridLayout<Header: View, ContextMenu: View>: View {
    let groups: [CategoryGroup]
    let mediaKind: MediaKind
    let coverPreference: CoverPreference
    let showBookCountBadge: Bool
    let onNavigate: (CategoryGroup, BookMetadata?) -> Void
    @ViewBuilder let header: () -> Header
    let contextMenuBuilder: ((CategoryGroup) -> ContextMenu)?

    private let horizontalPadding: CGFloat = 24

    init(
        groups: [CategoryGroup],
        mediaKind: MediaKind,
        coverPreference: CoverPreference,
        showBookCountBadge: Bool,
        onNavigate: @escaping (CategoryGroup, BookMetadata?) -> Void,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() },
        @ViewBuilder contextMenuBuilder: @escaping (CategoryGroup) -> ContextMenu
    ) {
        self.groups = groups
        self.mediaKind = mediaKind
        self.coverPreference = coverPreference
        self.showBookCountBadge = showBookCountBadge
        self.onNavigate = onNavigate
        self.header = header
        self.contextMenuBuilder = contextMenuBuilder
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    header()
                        .padding(.horizontal, horizontalPadding)

                    let columns = [
                        GridItem(.adaptive(minimum: 125, maximum: 140), spacing: 16)
                    ]

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(groups) { group in
                            GroupedBooksCardView(
                                title: group.name,
                                books: group.books,
                                mediaKind: mediaKind,
                                coverPreference: coverPreference,
                                showBookCountBadge: showBookCountBadge,
                                pinId: group.pinId,
                                onTap: {
                                    onNavigate(group, nil)
                                }
                            )
                            .modifier(OptionalContextMenuModifier(content: contextMenuBuilder?(group)))
                            .id(group.id)
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

extension CategoryGridLayout where ContextMenu == EmptyView {
    init(
        groups: [CategoryGroup],
        mediaKind: MediaKind,
        coverPreference: CoverPreference,
        showBookCountBadge: Bool,
        onNavigate: @escaping (CategoryGroup, BookMetadata?) -> Void,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() }
    ) {
        self.groups = groups
        self.mediaKind = mediaKind
        self.coverPreference = coverPreference
        self.showBookCountBadge = showBookCountBadge
        self.onNavigate = onNavigate
        self.header = header
        self.contextMenuBuilder = nil
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
