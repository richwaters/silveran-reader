import Foundation

enum MetadataEditorTab: String, CaseIterable, Identifiable {
    case titleDetails = "Title & Details"
    case description = "Description"
    case authors = "Authors"
    case narrators = "Narrators"
    case otherCreators = "Other Creators"
    case organization = "Tags"
    case covers = "Cover"

    var id: String { rawValue }
}
