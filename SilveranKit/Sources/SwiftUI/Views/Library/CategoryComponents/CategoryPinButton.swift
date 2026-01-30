import SwiftUI

struct CategoryPinButton: View {
    let pinId: String
    @State private var isPinned: Bool

    init(pinId: String) {
        self.pinId = pinId
        self._isPinned = State(initialValue: SidebarPinHelper.isPinned(pinId))
    }

    var body: some View {
        Button {
            SidebarPinHelper.togglePin(pinId)
            isPinned = SidebarPinHelper.isPinned(pinId)
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12))
                .foregroundStyle(isPinned ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin from Sidebar" : "Pin to Sidebar")
    }
}
