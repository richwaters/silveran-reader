import Foundation

enum MetadataEditorTab: String, CaseIterable, Identifiable {
    case titleDetails = "Title & Details"
    case description = "Description"
    case creators = "Creators"
    case organization = "Tags"
    case covers = "Covers"

    var id: String { rawValue }
}
