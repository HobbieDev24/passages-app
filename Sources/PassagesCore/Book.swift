import Foundation

public struct Book: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let genre: String?
    public let path: String?
    public let coverURL: String?
    public var localCoverPath: String?
    public var highlightCount: Int

    public init(
        id: String,
        title: String,
        author: String,
        genre: String? = nil,
        path: String? = nil,
        coverURL: String? = nil,
        localCoverPath: String? = nil,
        highlightCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.genre = genre
        self.path = path
        self.coverURL = coverURL
        self.localCoverPath = localCoverPath
        self.highlightCount = highlightCount
    }

    public var displayAuthor: String {
        author.isEmpty ? "Unknown Author" : author
    }

    public var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }
}
