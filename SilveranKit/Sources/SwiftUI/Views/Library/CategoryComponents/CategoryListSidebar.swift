import SwiftUI

#if os(macOS)
struct CategoryListSidebar<RowContent: View, DetailContent: View, ToolbarContent: View>: View {
    let headerTitle: String
    let sidebarTitle: String
    let groups: [CategoryGroup]
    @Binding var selectedGroupId: String?
    @Binding var listWidth: CGFloat
    @Binding var sortByCount: Bool
    @ViewBuilder let rowContent: (CategoryGroup, Bool) -> RowContent
    @ViewBuilder let detailContent: (CategoryGroup) -> DetailContent
    @ViewBuilder let toolbarContent: () -> ToolbarContent

    init(
        headerTitle: String,
        sidebarTitle: String,
        groups: [CategoryGroup],
        selectedGroupId: Binding<String?>,
        listWidth: Binding<CGFloat>,
        sortByCount: Binding<Bool>,
        @ViewBuilder rowContent: @escaping (CategoryGroup, Bool) -> RowContent,
        @ViewBuilder detailContent: @escaping (CategoryGroup) -> DetailContent,
        @ViewBuilder toolbarContent: @escaping () -> ToolbarContent = { EmptyView() }
    ) {
        self.headerTitle = headerTitle
        self.sidebarTitle = sidebarTitle
        self.groups = groups
        self._selectedGroupId = selectedGroupId
        self._listWidth = listWidth
        self._sortByCount = sortByCount
        self.rowContent = rowContent
        self.detailContent = detailContent
        self.toolbarContent = toolbarContent
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            HStack(spacing: 0) {
                sidebarList
                ResizableDivider(width: $listWidth, minWidth: 150, maxWidth: 400)
                contentArea
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headerTitle)
                .font(.system(size: 32, weight: .regular, design: .serif))
            HStack {
                toolbarContent()
                Spacer()
            }
            .font(.callout)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var sortedGroups: [CategoryGroup] {
        guard sortByCount else { return groups }
        return groups.sorted { lhs, rhs in
            if lhs.books.count != rhs.books.count {
                return lhs.books.count > rhs.books.count
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var sidebarList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(sidebarTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                SidebarSortButton(sortByCount: $sortByCount)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sortedGroups) { group in
                        Button {
                            selectedGroupId = group.id
                        } label: {
                            rowContent(group, selectedGroupId == group.id)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .frame(width: listWidth)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private var contentArea: some View {
        if let groupId = selectedGroupId, let group = groups.first(where: { $0.id == groupId }) {
            detailContent(group)
                .id(groupId)
        } else {
            VStack {
                Spacer()
                Text("Select an item")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}
#endif

struct CategoryRowContent: View {
    let iconName: String
    let name: String
    let bookCount: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: iconName)
                #if os(iOS)
                .font(.body)
                #else
                .font(.system(size: 14))
                #endif
                .foregroundStyle(.secondary)
                .frame(width: 28)

            Text(name)
                #if os(iOS)
                .font(.body)
                #else
                .font(.system(size: 14))
                #endif
                .lineLimit(1)

            Spacer()

            Text("\(bookCount)")
                #if os(iOS)
                .font(.subheadline)
                #else
                .font(.system(size: 12))
                #endif
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                )
        }
        .padding(.horizontal, 16)
        #if os(iOS)
        .padding(.vertical, 12)
        #else
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        #endif
    }
}

#if os(iOS)
struct CategoryListView: View {
    let groups: [CategoryGroup]
    let onNavigate: (CategoryGroup) -> Void
    @ViewBuilder let rowContent: (CategoryGroup) -> AnyView

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groups) { group in
                    Button {
                        onNavigate(group)
                    } label: {
                        rowContent(group)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 48)
                }
            }
            .padding(.top, 8)
        }
    }
}
#endif
