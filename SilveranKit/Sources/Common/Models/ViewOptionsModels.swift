import Foundation

public enum LibraryLayoutStyle: String, CaseIterable, Identifiable, Sendable {
    case grid
    case compactGrid
    case list
    case fan

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .grid: "Grid"
        case .compactGrid: "Compact Grid"
        case .list: "List"
        case .fan: "Fan"
        }
    }

    public var iconName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .compactGrid: "square.grid.3x3"
        case .list: "list.bullet"
        case .fan: "rectangle.stack"
        }
    }
}

public enum CoverSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    public var gridTileWidth: CGFloat {
        switch self {
        case .small: 100
        case .medium: 125
        case .large: 160
        }
    }
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
