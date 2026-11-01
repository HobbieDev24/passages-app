import Foundation

public struct HighlightExporter {

    public enum Format: String, Sendable, CaseIterable, Identifiable {
        case markdown
        case text
        public var id: String { rawValue }

        public var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .text: return "txt"
            }
        }

        public var displayName: String {
            switch self {
            case .markdown: return "Markdown (.md)"
            case .text: return "Plain Text (.txt)"
            }
        }
    }

    public struct Options: Sendable {
        public var includeNotes: Bool
        public var groupByChapter: Bool
        public var includeMetadata: Bool
        public var includeAuthor: Bool

        public init(
            includeNotes: Bool = true,
            groupByChapter: Bool = true,
            includeMetadata: Bool = false,
            includeAuthor: Bool = true
        ) {
            self.includeNotes = includeNotes
            self.groupByChapter = groupByChapter
            self.includeMetadata = includeMetadata
            self.includeAuthor = includeAuthor
        }

        public static let `default` = Options()
    }

    public let format: Format
    public let options: Options

    public init(format: Format, options: Options = .default) {
        self.format = format
        self.options = options
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    public func export(book: Book, highlights: [Highlight]) -> String {
        switch format {
        case .markdown: return renderMarkdown(book: book, highlights: highlights)
        case .text:     return renderText(book: book, highlights: highlights)
        }
    }

    public func suggestedFilename(for book: Book) -> String {
        let raw = book.displayTitle
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "highlights" : trimmed
    }

    private func renderMarkdown(book: Book, highlights: [Highlight]) -> String {
        var out = "# \(book.displayTitle)\n"
        if options.includeAuthor {
            out += "\n*\(book.displayAuthor)*\n"
        }

        for group in grouped(highlights) {
            if options.groupByChapter, let chapter = group.chapter {
                out += "\n## \(chapter)\n"
            }
            for highlight in group.highlights {
                out += "\n"
                for line in highlight.text.components(separatedBy: "\n") {
                    out += "> \(line)\n"
                }
                if options.includeNotes, let note = highlight.note {
                    out += "\n"
                    for line in note.components(separatedBy: "\n") {
                        out += "**Note:** \(line)\n"
                    }
                }
                if options.includeMetadata {
                    out += "\n`\(metadataLine(for: highlight))`\n"
                }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func renderText(book: Book, highlights: [Highlight]) -> String {
        var out = "\(book.displayTitle)\n"
        if options.includeAuthor {
            out += "\(book.displayAuthor)\n"
        }
        out += String(repeating: "=", count: max(book.displayTitle.count, 3)) + "\n"

        for group in grouped(highlights) {
            if options.groupByChapter, let chapter = group.chapter {
                out += "\n\n— \(chapter) —\n"
            }
            for highlight in group.highlights {
                out += "\n\n"
                out += highlight.text
                if options.includeNotes, let note = highlight.note {
                    out += "\n\nNote: \(note)"
                }
                if options.includeMetadata {
                    out += "\n[\(metadataLine(for: highlight))]"
                }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func metadataLine(for highlight: Highlight) -> String {
        var parts: [String] = [highlight.style.label]
        if let date = highlight.createdAt {
            parts.append(Self.dateFormatter.string(from: date))
        }
        return parts.joined(separator: " | ")
    }

    private struct Group {
        let chapter: String?
        let highlights: [Highlight]
    }

    private func grouped(_ highlights: [Highlight]) -> [Group] {
        guard options.groupByChapter else {
            return [Group(chapter: nil, highlights: highlights)]
        }
        var groups: [Group] = []
        var currentChapter: String?? = .none
        var bucket: [Highlight] = []

        func flush() {
            if !bucket.isEmpty {
                groups.append(Group(chapter: currentChapter ?? nil, highlights: bucket))
                bucket = []
            }
        }

        for highlight in highlights {
            if currentChapter == .none {
                currentChapter = .some(highlight.chapter)
            }
            if (currentChapter ?? nil) != highlight.chapter {
                flush()
                currentChapter = .some(highlight.chapter)
            }
            bucket.append(highlight)
        }
        flush()
        return groups
    }
}
