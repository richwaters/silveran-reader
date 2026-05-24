import Foundation
import SwiftUI

enum MetadataCoverScope: String, CaseIterable, Identifiable {
    case audiobook
    case ebook

    var id: String { rawValue }

    var isAudio: Bool { self == .audiobook }
    var label: String { isAudio ? "Audiobook Cover" : "Ebook Cover" }
    var serverPreviewLabel: String { isAudio ? "Server Audiobook Cover" : "Server Ebook Cover" }
    var aspectRatio: CGFloat { isAudio ? 1.0 : 2.0 / 3.0 }
    var variant: MediaViewModel.CoverVariant { isAudio ? .audioSquare : .standard }
}

public struct MetadataEditorData: Codable, Hashable {
    public let bookIds: [String]
    public let sessionId: UUID

    public init(bookIds: [String], sessionId: UUID = UUID()) {
        self.bookIds = bookIds
        self.sessionId = sessionId
    }

    public init(bookId: String) {
        self.bookIds = [bookId]
        self.sessionId = UUID()
    }
}
