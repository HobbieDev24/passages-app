import Foundation

public enum HighlightColor: Int, Sendable, CaseIterable {
    case underline = 0
    case green = 1
    case blue = 2
    case yellow = 3
    case pink = 4
    case purple = 5
    case unknown = -1

    public init(style: Int) {
        self = HighlightColor(rawValue: style) ?? .unknown
    }

    public var label: String {
        switch self {
        case .underline: return "Underline"
        case .green: return "Green"
        case .blue: return "Blue"
        case .yellow: return "Yellow"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .unknown: return "Highlight"
        }
    }
}

public struct Highlight: Identifiable, Hashable, Sendable {
    public let id: String
    public let bookID: String
    public let text: String
    public let note: String?
    public let style: HighlightColor
    public let chapter: String?
    public let location: String?
    public let createdAt: Date?
    public let modifiedAt: Date?

    public init(
        id: String,
        bookID: String,
        text: String,
        note: String?,
        style: HighlightColor,
        chapter: String?,
        location: String?,
        createdAt: Date?,
        modifiedAt: Date?
    ) {
        self.id = id
        self.bookID = bookID
        self.text = text
        self.note = note
        self.style = style
        self.chapter = chapter
        self.location = location
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// Core Data dates count seconds from 2001-01-01, rather than the Unix epoch.
public enum AppleTimestamp {
    public static let referenceOffset: TimeInterval = 978_307_200

    public static func date(from coreDataSeconds: Double?) -> Date? {
        guard let s = coreDataSeconds, s > 0 else { return nil }
        return Date(timeIntervalSince1970: s + referenceOffset)
    }
}
