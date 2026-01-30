#if os(macOS)
import SwiftUI

struct PinConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaViewModel.self) private var mediaViewModel
    @State private var groups: [PinGroup]
    @State private var editingItemId: String?
    @State private var editingGroupId: UUID?
    @FocusState private var focusedItemId: String?
    @FocusState private var focusedGroupId: UUID?

    init() {
        _groups = State(initialValue: SidebarPinHelper.pinGroups)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
            Divider()
            footerBar
        }
        .frame(width: 400, height: 500)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var headerBar: some View {
        HStack {
            Text("Configure Pins")
                .font(.headline)
            Spacer()
        }
        .padding()
    }

    private var contentArea: some View {
        List {
            ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                Section {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, item in
                        itemRow(item: item, groupIndex: groupIndex, itemIndex: itemIndex)
                    }
                    .onMove { from, to in
                        groups[groupIndex].items.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    groupHeader(group: group, groupIndex: groupIndex)
                }
            }

            Section {
                addGroupButton
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func groupHeader(group: PinGroup, groupIndex: Int) -> some View {
        HStack {
            if editingGroupId == group.id {
                TextField("Group Name", text: Binding(
                    get: { groups[groupIndex].name },
                    set: { groups[groupIndex].name = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.subheadline.weight(.semibold))
                .focused($focusedGroupId, equals: group.id)
                .onSubmit { editingGroupId = nil; focusedGroupId = nil }

                Button {
                    editingGroupId = nil
                    focusedGroupId = nil
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            } else {
                Text(group.name)
                    .font(.subheadline.weight(.semibold))

                Button {
                    editingGroupId = group.id
                    focusedGroupId = group.id
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if groups.count > 1 || group.items.isEmpty {
                Button(role: .destructive) {
                    deleteGroup(at: groupIndex)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete group")
            }
        }
    }

    @ViewBuilder
    private func itemRow(item: PinItem, groupIndex: Int, itemIndex: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12, weight: .bold))

            Toggle("", isOn: Binding(
                get: { groups[groupIndex].items[itemIndex].visible },
                set: { groups[groupIndex].items[itemIndex].visible = $0 }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            if editingItemId == item.id {
                let defaultName = resolveDefaultName(for: item.id)
                TextField(defaultName, text: Binding(
                    get: { groups[groupIndex].items[itemIndex].alias ?? "" },
                    set: { groups[groupIndex].items[itemIndex].alias = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .focused($focusedItemId, equals: item.id)
                .onSubmit { editingItemId = nil; focusedItemId = nil }

                Button {
                    editingItemId = nil
                    focusedItemId = nil
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            } else {
                let hasAlias = item.alias != nil && !item.alias!.isEmpty
                Text(displayName(for: item))
                    .font(.callout)
                    .foregroundStyle(item.visible ? .primary : .secondary)
                    .strikethrough(!item.visible)

                Button {
                    editingItemId = item.id
                    focusedItemId = item.id
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Rename")

                if hasAlias {
                    Button {
                        groups[groupIndex].items[itemIndex].alias = nil
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Revert to default name")
                }
            }

            Spacer()

            if groups.count > 1 {
                Menu {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { targetIndex, targetGroup in
                        if targetIndex != groupIndex {
                            Button("Move to \(targetGroup.name)") {
                                moveItem(fromGroup: groupIndex, itemIndex: itemIndex, toGroup: targetIndex)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }

            Button(role: .destructive) {
                removeItem(fromGroup: groupIndex, itemIndex: itemIndex)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func displayName(for item: PinItem) -> String {
        if let alias = item.alias, !alias.isEmpty {
            return alias
        }
        return resolveDefaultName(for: item.id)
    }

    private func resolveDefaultName(for id: String) -> String {
        if id.hasPrefix("pin.smartShelf:") {
            let uuidString = String(id.dropFirst("pin.smartShelf:".count))
            if let uuid = UUID(uuidString: uuidString),
               let shelf = mediaViewModel.smartShelves.first(where: { $0.id == uuid }) {
                return shelf.name
            }
            return "Smart Shelf"
        }
        if id.hasPrefix("pin.series:") { return String(id.dropFirst("pin.series:".count)) }
        if id.hasPrefix("pin.author:") { return String(id.dropFirst("pin.author:".count)) }
        if id.hasPrefix("pin.collection:") { return String(id.dropFirst("pin.collection:".count)) }
        if id.hasPrefix("pin.tag:") { return String(id.dropFirst("pin.tag:".count)) }
        if id.hasPrefix("pin.narrator:") { return String(id.dropFirst("pin.narrator:".count)) }
        if id.hasPrefix("pin.translator:") { return String(id.dropFirst("pin.translator:".count)) }
        if id.hasPrefix("pin.year:") { return String(id.dropFirst("pin.year:".count)) }
        if id.hasPrefix("pin.rating:") {
            let rating = String(id.dropFirst("pin.rating:".count))
            return RatingDisplayHelper.label(for: rating)
        }
        if id.hasPrefix("pin.status:") { return String(id.dropFirst("pin.status:".count)) }
        return id
    }

    private var addGroupButton: some View {
        Button {
            groups.append(PinGroup(name: "New Group"))
        } label: {
            Label("Add Group", systemImage: "plus.circle")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func deleteGroup(at index: Int) {
        let group = groups[index]
        if !group.items.isEmpty && groups.count > 1 {
            let targetIndex = index == 0 ? 1 : 0
            groups[targetIndex].items.append(contentsOf: group.items)
        }
        groups.remove(at: index)
        if groups.isEmpty {
            groups = []
        }
    }

    private func moveItem(fromGroup: Int, itemIndex: Int, toGroup: Int) {
        let item = groups[fromGroup].items.remove(at: itemIndex)
        groups[toGroup].items.append(item)
    }

    private func removeItem(fromGroup: Int, itemIndex: Int) {
        groups[fromGroup].items.remove(at: itemIndex)
        if groups.allSatisfy({ $0.items.isEmpty }) {
            groups = []
        }
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                SidebarPinHelper.pinGroups = groups.filter { !$0.items.isEmpty || groups.count == 1 }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}
#endif
