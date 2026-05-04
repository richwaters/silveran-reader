import SwiftUI

struct CoversTab: View {
    var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: "photo",
            description: Text("Cover import will be available in a future update.")
        )
    }
}
