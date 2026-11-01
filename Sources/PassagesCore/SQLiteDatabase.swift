import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "SQLiteError: \(message)" }
}

// SQLite must copy bound text before the Swift buffer is released.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteDatabase {
    private let handle: OpaquePointer

    public init(readOnlyPath path: String) throws {
        var source: OpaquePointer?
        let result = sqlite3_open_v2(path, &source, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK, let source else {
            let message = source.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let source { sqlite3_close(source) }
            throw SQLiteError(message)
        }
        defer { sqlite3_close(source) }
        sqlite3_busy_timeout(source, 2000)

        var destination: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let destination else {
            if let destination { sqlite3_close(destination) }
            throw SQLiteError("Couldn't create an in-memory library snapshot")
        }
        do {
            // SQLite coordinates the source WAL; the complete snapshot stays in RAM.
            guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
                throw SQLiteError(String(cString: sqlite3_errmsg(destination)))
            }
            var status: Int32 = SQLITE_OK
            do {
                defer { sqlite3_backup_finish(backup) }
                var retries = 0
                repeat {
                    try Task.checkCancellation()
                    status = sqlite3_backup_step(backup, 256)
                    if status == SQLITE_BUSY || status == SQLITE_LOCKED {
                        retries += 1
                        if retries > 100 { break }
                        sqlite3_sleep(20)
                    }
                } while status == SQLITE_OK || status == SQLITE_BUSY || status == SQLITE_LOCKED
            }
            guard status == SQLITE_DONE else {
                throw SQLiteError("Couldn't read a consistent Apple Books snapshot")
            }
            guard sqlite3_exec(destination, "PRAGMA query_only = ON; PRAGMA temp_store = MEMORY;", nil, nil, nil) == SQLITE_OK else {
                throw SQLiteError("Couldn't make the library snapshot read-only")
            }
        } catch {
            sqlite3_close(destination)
            throw error
        }
        self.handle = destination
    }

    deinit {
        sqlite3_close(handle)
    }

    public func query<T>(
        _ sql: String,
        parameters: [String] = [],
        rowMapper: (Row) throws -> T
    ) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError("prepare failed: \(lastErrorMessage)\nSQL: \(sql)")
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in parameters.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        var results: [T] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW {
                results.append(try rowMapper(Row(statement: statement)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLiteError("step failed: \(lastErrorMessage)")
            }
        }
        return results
    }

    public func tableExists(_ name: String) -> Bool {
        let rows = (try? query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name = ?1;",
            parameters: [name]
        ) { $0.string(0) }) ?? []
        return !rows.isEmpty
    }

    private var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }

    public struct Row {
        let statement: OpaquePointer?

        public func string(_ column: Int32) -> String? {
            guard let c = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: c)
        }

        public func int(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(statement, column))
        }

        public func double(_ column: Int32) -> Double? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
            return sqlite3_column_double(statement, column)
        }
    }
}
