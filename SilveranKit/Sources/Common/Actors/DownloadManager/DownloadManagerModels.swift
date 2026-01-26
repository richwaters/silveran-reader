import Foundation

public enum DownloadState: Codable, Sendable, Equatable {
    case queued
    case downloading(progress: Double)
    case paused(hasResumeData: Bool)
    case failed(error: String, hasResumeData: Bool)
    case importing
    case completed
}

public struct DownloadRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let bookId: String
    public let category: LocalMediaCategory
    public let bookTitle: String
    public let format: StorytellerBookFormat

    public var state: DownloadState
    public var receivedBytes: Int64
    public var expectedBytes: Int64?

    public let createdAt: Date
    public var lastUpdatedAt: Date

    public init(
        bookId: String,
        category: LocalMediaCategory,
        bookTitle: String,
        format: StorytellerBookFormat
    ) {
        self.id = "\(bookId)-\(category.rawValue)"
        self.bookId = bookId
        self.category = category
        self.bookTitle = bookTitle
        self.format = format
        self.state = .queued
        self.receivedBytes = 0
        self.expectedBytes = nil
        self.createdAt = Date()
        self.lastUpdatedAt = Date()
    }

    public var progressFraction: Double {
        switch state {
        case .downloading(let progress):
            return progress
        case .completed:
            return 1.0
        default:
            guard let expected = expectedBytes, expected > 0 else { return 0 }
            return min(max(Double(receivedBytes) / Double(expected), 0), 1)
        }
    }

    public var isResumable: Bool {
        switch state {
        case .paused(let has), .failed(_, let has):
            return has
        default:
            return false
        }
    }

    public var isActive: Bool {
        switch state {
        case .queued, .downloading, .importing:
            return true
        default:
            return false
        }
    }

    public var isIncomplete: Bool {
        switch state {
        case .completed:
            return false
        default:
            return true
        }
    }
}

extension StorytellerBookFormat: Codable {}
