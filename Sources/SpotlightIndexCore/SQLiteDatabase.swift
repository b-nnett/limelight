import Foundation
import SQLite3

final class SQLiteDatabase {
    enum Error: Swift.Error, LocalizedError {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message), .prepareFailed(let message), .stepFailed(let message):
                message
            }
        }
    }

    private let db: OpaquePointer?

    init(path: String, readOnly: Bool = true) throws {
        var handle: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "failed to open SQLite database"
            sqlite3_close(handle)
            throw Error.openFailed(message)
        }
        db = handle
    }

    deinit {
        sqlite3_close(db)
    }

    func rows(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [[String: SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Error.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch binding {
            case .text(let value):
                sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            case .int(let value):
                sqlite3_bind_int64(statement, position, value)
            case .double(let value):
                sqlite3_bind_double(statement, position, value)
            }
        }

        var output: [[String: SQLiteValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return output
            }
            guard result == SQLITE_ROW else {
                throw Error.stepFailed(String(cString: sqlite3_errmsg(db)))
            }

            var row: [String: SQLiteValue] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER:
                    row[name] = .int(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT:
                    row[name] = .double(sqlite3_column_double(statement, column))
                case SQLITE_TEXT:
                    row[name] = .text(String(cString: sqlite3_column_text(statement, column)))
                case SQLITE_BLOB:
                    let byteCount = Int(sqlite3_column_bytes(statement, column))
                    if let bytes = sqlite3_column_blob(statement, column) {
                        row[name] = .blob(Data(bytes: bytes, count: byteCount))
                    } else {
                        row[name] = .null
                    }
                default:
                    row[name] = .null
                }
            }
            output.append(row)
        }
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw Error.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}

enum SQLiteBinding {
    case text(String)
    case int(Int64)
    case double(Double)
}

enum SQLiteValue: Equatable {
    case text(String)
    case int(Int64)
    case double(Double)
    case blob(Data)
    case null

    var string: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var textValue: String? {
        switch self {
        case .text(let value):
            value
        case .int(let value):
            String(value)
        case .double(let value):
            String(value)
        case .blob, .null:
            nil
        }
    }

    var int64: Int64? {
        if case .int(let value) = self { return value }
        return nil
    }

    var double: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    var data: Data? {
        if case .blob(let value) = self { return value }
        return nil
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
