import Foundation

public final class BooksDatabase {

    public struct Location {
        public let libraryDB: URL
        public let annotationDB: URL
        public let bookInfoCacheDBs: [URL]
        public var container: URL = BooksDatabase.defaultContainer
    }

    public enum LookupError: Error, CustomStringConvertible {
        case accessDenied
        case libraryNotFound
        case annotationStoreNotFound

        public var description: String {
            switch self {
            case .accessDenied:
                return "Apple Books folder access is required. Choose its Data folder in Passages."
            case .libraryNotFound:
                return "Couldn't find the Apple Books library database. Is Apple Books installed and have you opened it at least once?"
            case .annotationStoreNotFound:
                return "Couldn't find the Apple Books annotation database. Have you highlighted anything yet?"
            }
        }
    }

    private let location: Location
    private let coverProvider: CoverProvider

    public static var defaultContainer: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.iBooksX/Data/Documents")
    }

    public static func locate(container: URL = defaultContainer) throws -> Location {
        let library = try findSQLite(
            in: container.appendingPathComponent("BKLibrary"),
            prefix: "BKLibrary"
        )
        guard let library else { throw LookupError.libraryNotFound }

        let annotation = try findSQLite(
            in: container.appendingPathComponent("AEAnnotation"),
            prefix: "AEAnnotation"
        )
        guard let annotation else { throw LookupError.annotationStoreNotFound }

        let bookInfoCaches = bookInfoCacheURLs(container: container)

        return Location(libraryDB: library, annotationDB: annotation, bookInfoCacheDBs: bookInfoCaches, container: container)
    }

    private static func bookInfoCacheURLs(container: URL) -> [URL] {
        let cacheDir = container.deletingLastPathComponent()
            .appendingPathComponent("Library/Caches")
        let fm = FileManager.default
        guard let entries = fm.enumerator(at: cacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return entries.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasPrefix("AEBookInfo") && $0.pathExtension == "sqlite" }
            .sorted {
                let left = modificationDate($0), right = modificationDate($1)
                return left == right ? $0.path < $1.path : left > right
            }
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private static func findSQLite(in directory: URL, prefix: String) throws -> URL? {
        let fm = FileManager.default
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
            if (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError)
                || (error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code)) {
                throw LookupError.accessDenied
            }
            throw error
        }

        return entries.sorted { modificationDate($0) > modificationDate($1) }.first { url in
            let name = url.lastPathComponent
            return name.hasPrefix(prefix) && name.hasSuffix(".sqlite")
        }
    }

    public init(location: Location) throws {
        self.location = location
        self.coverProvider = CoverProvider(container: location.container)
    }

    public convenience init(container: URL = BooksDatabase.defaultContainer) throws {
        try self.init(location: try BooksDatabase.locate(container: container))
    }

    public func loadBooksWithHighlights() throws -> [Book] {
        let counts = try highlightCounts()
        let allBooks = try loadAllBooks()
        let fallback = try loadBookInfoCache()

        var result: [Book] = []
        for (assetID, summary) in counts where summary.count > 0 {
            let key = Self.metadataKey(assetID)
            guard let primary = allBooks[key] else { continue }
            let cached = fallback[key]
            let title = Self.nonempty(primary.title) ?? Self.nonempty(cached?.title) ?? "Unknown Book"
            let author = Self.nonempty(primary.author) ?? Self.nonempty(cached?.author) ?? ""
            result.append(Book(
                id: assetID, title: title, author: author,
                genre: primary.genre ?? cached?.genre, path: primary.path, coverURL: primary.coverURL,
                localCoverPath: coverProvider.coverURL(for: assetID)?.path,
                highlightCount: summary.count
            ))
        }
        return result.sorted {
            let leftDate = counts[$0.id]?.modified ?? 0
            let rightDate = counts[$1.id]?.modified ?? 0
            if leftDate != rightDate { return leftDate > rightDate }
            return $0.id < $1.id
        }
    }

    public func loadAllBooks() throws -> [String: Book] {
        let db = try SQLiteDatabase(readOnlyPath: location.libraryDB.path)
        let sql = """
        SELECT ZASSETID, ZTITLE, ZAUTHOR, ZGENRE, ZPATH, ZCOVERURL
        FROM ZBKLIBRARYASSET
        WHERE ZASSETID IS NOT NULL;
        """
        let books = try db.query(sql) { row -> Book in
            Book(
                id: row.string(0) ?? "",
                title: row.string(1) ?? "",
                author: row.string(2) ?? "",
                genre: row.string(3),
                path: row.string(4),
                coverURL: row.string(5)
            )
        }
        return Dictionary(books.map { (Self.metadataKey($0.id), $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func loadBookInfoCache() throws -> [String: Book] {
        var merged: [String: Book] = [:]
        for cacheURL in location.bookInfoCacheDBs {
            // Old or incompatible caches must not prevent reading the current library.
            guard let books = try? readBookInfoCache(cacheURL) else { continue }
            for (key, older) in books {
                guard let newer = merged[key] else {
                    merged[key] = older
                    continue
                }
                merged[key] = Book(
                    id: newer.id,
                    title: Self.nonempty(newer.title) ?? older.title,
                    author: Self.nonempty(newer.author) ?? older.author,
                    genre: Self.nonempty(newer.genre) ?? older.genre
                )
            }
        }
        return merged
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readBookInfoCache(_ cacheURL: URL) throws -> [String: Book] {
        let db = try SQLiteDatabase(readOnlyPath: cacheURL.path)
        guard db.tableExists("ZAEBOOKINFO") else { return [:] }

        let columns = try db.query("PRAGMA table_info(ZAEBOOKINFO);") { $0.string(1) ?? "" }
        func field(_ candidates: [String]) -> String {
            candidates.first { columns.contains($0) } ?? "NULL"
        }
        let key = field(["ZDATABASEKEY", "ZASSETID", "ZBOOKID"])
        let title = field(["ZBOOKTITLE", "ZTITLE"])
        let author = field(["ZBOOKAUTHOR", "ZAUTHOR"])
        guard key != "NULL" else {
            throw SQLiteError("Unrecognized Apple Books metadata cache schema")
        }
        let sql = """
        SELECT \(key), \(title), \(author), \(field(["ZGENRE"]))
        FROM ZAEBOOKINFO
        WHERE \(key) IS NOT NULL
          AND COALESCE(\(field(["ZDELETEDFLAG"])), 0) = 0;
        """
        let books = try db.query(sql) { row -> Book in
            Book(
                id: row.string(0) ?? "",
                title: row.string(1) ?? "",
                author: row.string(2) ?? "",
                genre: row.string(3)
            )
        }
        return Dictionary(
            books.filter { !$0.id.isEmpty }.map { (Self.metadataKey($0.id), $0) },
            uniquingKeysWith: { a, _ in a }
        )
    }

    private func highlightCounts() throws -> [String: (count: Int, modified: Double)] {
        let db = try SQLiteDatabase(readOnlyPath: location.annotationDB.path)
        let modified = columnExists(db, table: "ZAEANNOTATION", column: "ZANNOTATIONMODIFICATIONDATE") ? "ZANNOTATIONMODIFICATIONDATE" : "NULL"
        let created = columnExists(db, table: "ZAEANNOTATION", column: "ZANNOTATIONCREATIONDATE") ? "ZANNOTATIONCREATIONDATE" : "NULL"
        let sql = """
        SELECT ZANNOTATIONASSETID, COUNT(*), MAX(COALESCE(\(modified), \(created), 0))
        FROM ZAEANNOTATION
        WHERE ZANNOTATIONDELETED = 0
          AND ZANNOTATIONSELECTEDTEXT IS NOT NULL
          AND TRIM(ZANNOTATIONSELECTEDTEXT) <> ''
        GROUP BY ZANNOTATIONASSETID;
        """
        var counts: [String: (count: Int, modified: Double)] = [:]
        _ = try db.query(sql) { row -> Void in
            if let id = row.string(0) { counts[id] = (row.int(1), row.double(2) ?? 0) }
        }
        return counts
    }

    public func loadHighlights(forBookID bookID: String) throws -> [Highlight] {
        let db = try SQLiteDatabase(readOnlyPath: location.annotationDB.path)

        let hasChapter = columnExists(db, table: "ZAEANNOTATION", column: "ZFUTUREPROOFING1")
        let chapterCol = hasChapter ? "ZFUTUREPROOFING1" : "NULL"

        let sql = """
        SELECT
            ZANNOTATIONUUID,
            ZANNOTATIONASSETID,
            ZANNOTATIONSELECTEDTEXT,
            ZANNOTATIONNOTE,
            ZANNOTATIONSTYLE,
            \(chapterCol),
            ZANNOTATIONLOCATION,
            ZANNOTATIONCREATIONDATE,
            ZANNOTATIONMODIFICATIONDATE
        FROM ZAEANNOTATION
        WHERE ZANNOTATIONASSETID = ?1
          AND ZANNOTATIONDELETED = 0
          AND ZANNOTATIONSELECTEDTEXT IS NOT NULL
          AND TRIM(ZANNOTATIONSELECTEDTEXT) <> ''
        ORDER BY ZPLABSOLUTEPHYSICALLOCATION ASC,
                 ZANNOTATIONLOCATION ASC,
                 ZANNOTATIONCREATIONDATE ASC;
        """

        return try db.query(sql, parameters: [bookID]) { row -> Highlight in
            Highlight(
                id: row.string(0) ?? UUID().uuidString,
                bookID: row.string(1) ?? bookID,
                text: (row.string(2) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                note: row.string(3).flatMap { $0.isEmpty ? nil : $0 },
                style: HighlightColor(style: row.int(4)),
                chapter: row.string(5).flatMap { $0.isEmpty ? nil : $0 },
                location: row.string(6),
                createdAt: AppleTimestamp.date(from: row.double(7)),
                modifiedAt: AppleTimestamp.date(from: row.double(8))
            )
        }
    }

    private static func metadataKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func columnExists(_ db: SQLiteDatabase, table: String, column: String) -> Bool {
        let rows = (try? db.query("PRAGMA table_info(\(table));") { row in
            row.string(1)
        }) ?? []
        return rows.compactMap { $0 }.contains(column)
    }
}
