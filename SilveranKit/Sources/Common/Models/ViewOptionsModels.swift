import Foundation

public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

public enum LibraryLayoutStyle: String, CaseIterable, Identifiable, Sendable {
    case grid
    case compactGrid
    case table
    case fan

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .grid: "Grid"
        case .compactGrid: "Compact Grid"
        case .table: "Table"
        case .fan: "Fan"
        }
    }

    public var iconName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .compactGrid: "square.grid.3x3"
        case .table: "list.bullet"
        case .fan: "rectangle.stack"
        }
    }
}

public enum CoverSizeRange {
    public static let min: CGFloat = 80
    public static let max: CGFloat = 200
    public static let defaultValue: CGFloat = 125
}

public enum CoverPreference: String, CaseIterable, Identifiable, Sendable {
    case preferEbook
    case preferAudiobook

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .preferEbook: "Prefer Ebook"
        case .preferAudiobook: "Prefer Audiobook"
        }
    }

    public var preferredContainerAspectRatio: CGFloat {
        switch self {
        case .preferEbook: 0.67
        case .preferAudiobook: 1.0
        }
    }
}
