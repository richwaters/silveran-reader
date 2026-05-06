import Foundation

public struct MetadataEditorData: Codable, Hashable {
    public let bookIds: [String]

    public init(bookIds: [String]) {
        self.bookIds = bookIds
    }

    public init(bookId: String) {
        self.bookIds = [bookId]
    }
}
