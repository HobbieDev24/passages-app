import Foundation
import PassagesCore

actor LibraryReader {
    private var database: BooksDatabase?
    private var cache: [Book.ID: [Highlight]] = [:]

    func loadBooks(container: URL) throws -> [Book] {
        let database = try BooksDatabase(container: container)
        let books = try database.loadBooksWithHighlights()
        self.database = database
        cache.removeAll()
        return books
    }

    func highlights(for id: Book.ID) throws -> [Highlight] {
        if let cached = cache[id] { return cached }
        guard let database else { throw SQLiteError("Library not loaded") }
        let highlights = try database.loadHighlights(forBookID: id)
        cache[id] = highlights
        return highlights
    }

    func render(book: Book, highlights: [Highlight], format: HighlightExporter.Format,
                options: HighlightExporter.Options) -> String {
        HighlightExporter(format: format, options: options).export(book: book, highlights: highlights)
    }

    func write(contents: String, to url: URL) throws {
        try Task.checkCancellation()
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportAll(books: [Book], directory: URL, format: HighlightExporter.Format,
                   options: HighlightExporter.Options) throws -> Int {
        let exporter = HighlightExporter(format: format, options: options)
        var count = 0
        for book in books {
            try Task.checkCancellation()
            let highlights = try highlights(for: book.id)
            guard !highlights.isEmpty else { continue }
            let filename = exporter.suggestedFilename(for: book) + "." + format.fileExtension
            let url = uniqueURL(in: directory, filename: filename)
            try write(contents: exporter.export(book: book, highlights: highlights), to: url)
            count += 1
        }
        return count
    }

    func close() {
        database = nil
        cache.removeAll()
    }

    private func uniqueURL(in directory: URL, filename: String) -> URL {
        let manager = FileManager.default
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var number = 2
        while manager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(number)).\(ext)")
            number += 1
        }
        return candidate
    }
}
