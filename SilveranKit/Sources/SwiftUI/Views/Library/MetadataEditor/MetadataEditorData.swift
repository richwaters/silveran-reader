import Foundation

public extension Notification.Name {
    static let metadataEditorAddBooks = Notification.Name("metadataEditorAddBooks")
}

public enum MetadataEditorNotification {
    public static func post(bookIds: [String]) {
        NotificationCenter.default.post(
            name: .metadataEditorAddBooks,
            object: nil,
            userInfo: ["bookIds": bookIds]
        )
    }

    public static func bookIds(from notification: Notification) -> [String]? {
        notification.userInfo?["bookIds"] as? [String]
    }
}
