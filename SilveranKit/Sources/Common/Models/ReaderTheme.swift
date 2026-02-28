import Foundation

public struct ReaderTheme: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public let isBuiltIn: Bool
    public var backgroundColor: String
    public var foregroundColor: String
    public var highlightColor: String
    public var highlightThickness: Double
    public var readaloudHighlightMode: String
    public var userHighlightColor1: String
    public var userHighlightColor2: String
    public var userHighlightColor3: String
    public var userHighlightColor4: String
    public var userHighlightColor5: String
    public var userHighlightColor6: String
    public var userHighlightMode: String
    public var customCSS: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        isBuiltIn: Bool = false,
        backgroundColor: String,
        foregroundColor: String,
        highlightColor: String,
        highlightThickness: Double = kDefaultHighlightThickness,
        readaloudHighlightMode: String = kDefaultReadaloudHighlightMode,
        userHighlightColor1: String = kDefaultUserHighlightColor1,
        userHighlightColor2: String = kDefaultUserHighlightColor2,
        userHighlightColor3: String = kDefaultUserHighlightColor3,
        userHighlightColor4: String = kDefaultUserHighlightColor4,
        userHighlightColor5: String = kDefaultUserHighlightColor5,
        userHighlightColor6: String = kDefaultUserHighlightColor6,
        userHighlightMode: String = kDefaultUserHighlightMode,
        customCSS: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.highlightColor = highlightColor
        self.highlightThickness = highlightThickness
        self.readaloudHighlightMode = readaloudHighlightMode
        self.userHighlightColor1 = userHighlightColor1
        self.userHighlightColor2 = userHighlightColor2
        self.userHighlightColor3 = userHighlightColor3
        self.userHighlightColor4 = userHighlightColor4
        self.userHighlightColor5 = userHighlightColor5
        self.userHighlightColor6 = userHighlightColor6
        self.userHighlightMode = userHighlightMode
        self.customCSS = customCSS
    }
}

extension ReaderTheme {
    public static let builtInLightBackground = ReaderTheme(
        id: "builtin-light-background",
        name: "Light (Background)",
        isBuiltIn: true,
        backgroundColor: kDefaultBackgroundColorLight,
        foregroundColor: kDefaultForegroundColorLight,
        highlightColor: "#CCCCCC",
        readaloudHighlightMode: "background"
    )

    public static let builtInDarkBackground = ReaderTheme(
        id: "builtin-dark-background",
        name: "Dark (Background)",
        isBuiltIn: true,
        backgroundColor: kDefaultBackgroundColorDark,
        foregroundColor: kDefaultForegroundColorDark,
        highlightColor: "#333333",
        readaloudHighlightMode: "background"
    )

    public static let builtInLightText = ReaderTheme(
        id: "builtin-light-text",
        name: "Light (Text)",
        isBuiltIn: true,
        backgroundColor: kDefaultBackgroundColorLight,
        foregroundColor: kDefaultForegroundColorLight,
        highlightColor: "#254DF4",
        readaloudHighlightMode: "text"
    )

    public static let builtInDarkText = ReaderTheme(
        id: "builtin-dark-text",
        name: "Dark (Text)",
        isBuiltIn: true,
        backgroundColor: kDefaultBackgroundColorDark,
        foregroundColor: kDefaultForegroundColorDark,
        highlightColor: "#65A8EE",
        readaloudHighlightMode: "text"
    )

    public static let builtInLightUnderline = ReaderTheme(
        id: "builtin-light-underline",
        name: "Light (Underline)",
        isBuiltIn: true,
        backgroundColor: kDefaultBackgroundColorLight,
        foregroundColor: kDefaultForegroundColorLight,
        highlightColor: "#254DF4",
        readaloudHighlightMode: "underline"
    )

    public static let builtInDarkUnderline = ReaderTheme(
        id: "builtin-dark-underline",
        name: "Dark (Underline)",
        isBuiltIn: true,
        backgroundColor: kDefaultBackgroundColorDark,
        foregroundColor: kDefaultForegroundColorDark,
        highlightColor: "#65A8EE",
        readaloudHighlightMode: "underline"
    )

    public static let allBuiltIn: [ReaderTheme] = [
        .builtInLightBackground,
        .builtInDarkBackground,
        .builtInLightText,
        .builtInDarkText,
        .builtInLightUnderline,
        .builtInDarkUnderline,
    ]

    public static func resolve(id: String, customThemes: [ReaderTheme]) -> ReaderTheme? {
        if let builtIn = allBuiltIn.first(where: { $0.id == id }) {
            return builtIn
        }
        return customThemes.first(where: { $0.id == id })
    }
}
