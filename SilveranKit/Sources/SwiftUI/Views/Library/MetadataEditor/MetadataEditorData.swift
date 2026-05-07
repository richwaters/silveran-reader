import Foundation

enum MetadataEditorSection: String, CaseIterable, Identifiable {
    case covers = "Covers"
    case titleDetails = "Title & Details"
    case description = "Description"
    case authors = "Authors"
    case narrators = "Narrators"
    case otherCreators = "Other Creators"
    case organization = "Tags"
    case collections = "Collections"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .covers: "photo.on.rectangle"
        case .titleDetails: "info.circle"
        case .description: "text.alignleft"
        case .authors: "person.2"
        case .narrators: "mic"
        case .otherCreators: "person.text.rectangle"
        case .organization: "tag"
        case .collections: "rectangle.stack"
        }
    }
}

public struct MetadataEditorData: Codable, Hashable {
    public let bookIds: [String]

    public init(bookIds: [String]) {
        self.bookIds = bookIds
    }

    public init(bookId: String) {
        self.bookIds = [bookId]
    }
}
