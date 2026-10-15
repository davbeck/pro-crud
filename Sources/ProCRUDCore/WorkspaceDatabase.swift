import CSQLite
import Foundation

public enum NativeWorkspaceError: Error, CustomStringConvertible, Sendable {
	case database(String)
	case unsupportedSchema(applicationID: Int64, version: Int64)
	case invalidStream(String)
	case unsupportedStorage(String)
	case unavailableStream(String)
	case incompleteLoroImport(String)

	public var description: String {
		switch self {
		case let .database(message): "Cannot read a consistent workspace database: \(message)"
		case let .unsupportedSchema(applicationID, version): "Unsupported workspace database application ID \(applicationID), schema \(version). Expected application ID 1381390163, schema 9. No migration or repair was attempted."
		case let .invalidStream(message): "Invalid native workspace stream: \(message)"
		case let .unsupportedStorage(marker): "Unsupported native workspace storage marker: \(marker)."
		case let .unavailableStream(id): "Native stream \(id) is unavailable locally. Materialize it in ProPresenter before reading its content."
		case let .incompleteLoroImport(id): "Native stream \(id) has unresolved Loro dependencies; it is not a complete snapshot."
		}
	}
}

/// Captures committed WAL data through SQLite's backup API. The destination is
/// an in-memory database, never a copied main file or a writable live handle.
final class WorkspaceDatabase {
	private let handle: OpaquePointer

	init(snapshotOf url: URL) throws {
		let url = url.resolvingSymlinksInPath().standardizedFileURL
		guard FileManager.default.fileExists(atPath: url.path) else {
			throw NativeWorkspaceError.database("Database is missing at \(url.path).")
		}
		let wal = url.path + "-wal"
		if FileManager.default.fileExists(atPath: wal),
		   !FileManager.default.fileExists(atPath: url.path + "-shm")
		{
			throw NativeWorkspaceError.database("WAL exists without its shared-memory file. Open the workspace in ProPresenter or obtain a SQLite backup; read-only inspection will not create database sidecars.")
		}
		var source: OpaquePointer?
		let sourceStatus = sqlite3_open_v2(url.path, &source, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
		guard sourceStatus == SQLITE_OK, let source else {
			let message = source.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database."
			if let source {
				sqlite3_close(source)
			}
			throw NativeWorkspaceError.database("Opening source: \(message)")
		}
		defer { sqlite3_close(source) }
		sqlite3_busy_timeout(source, 2000)
		guard sqlite3_exec(source, "BEGIN", nil, nil, nil) == SQLITE_OK else {
			throw NativeWorkspaceError.database(String(cString: sqlite3_errmsg(source)))
		}
		defer { sqlite3_exec(source, "ROLLBACK", nil, nil, nil) }
		var sizeStatement: OpaquePointer?
		guard sqlite3_prepare_v2(source, "SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()", -1, &sizeStatement, nil) == SQLITE_OK,
		      let sizeStatement
		else { throw NativeWorkspaceError.database("Cannot determine snapshot size: \(String(cString: sqlite3_errmsg(source)))") }
		defer { sqlite3_finalize(sizeStatement) }
		guard sqlite3_step(sizeStatement) == SQLITE_ROW,
		      sqlite3_column_int64(sizeStatement, 0) <= 512 * 1024 * 1024
		else { throw NativeWorkspaceError.database("Database exceeds the 512 MiB in-memory inspection limit.") }
		var destination: OpaquePointer?
		let status = sqlite3_open_v2(":memory:", &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
		guard status == SQLITE_OK, let destination else {
			if let destination {
				sqlite3_close(destination)
			}
			throw NativeWorkspaceError.database("Cannot allocate the SQLite snapshot.")
		}
		guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
			let message = String(cString: sqlite3_errmsg(destination))
			sqlite3_close(destination)
			throw NativeWorkspaceError.database(message)
		}
		let result = sqlite3_backup_step(backup, -1)
		let finish = sqlite3_backup_finish(backup)
		guard result == SQLITE_DONE, finish == SQLITE_OK else {
			let message = String(cString: sqlite3_errmsg(destination))
			sqlite3_close(destination)
			throw NativeWorkspaceError.database("Snapshot failed (\(result), \(finish)): \(message). Retry after the active writer settles.")
		}
		handle = destination
	}

	deinit { sqlite3_close(handle) }

	func query<T>(_ sql: String, row: (OpaquePointer) throws -> T) throws -> [T] {
		var statement: OpaquePointer?
		guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
			throw NativeWorkspaceError.database("Preparing query: \(String(cString: sqlite3_errmsg(handle)))")
		}
		defer { sqlite3_finalize(statement) }
		var result: [T] = []
		while true {
			switch sqlite3_step(statement) {
			case SQLITE_ROW: try result.append(row(statement))
			case SQLITE_DONE: return result
			default: throw NativeWorkspaceError.database("Reading query: \(String(cString: sqlite3_errmsg(handle)))")
			}
		}
	}

	func integer(_ sql: String) throws -> Int64 {
		guard let result = try query(sql, row: { sqlite3_column_int64($0, 0) }).first else {
			throw NativeWorkspaceError.database("Missing integer result.")
		}
		return result
	}

	static func text(_ row: OpaquePointer, _ index: Int32) -> String? {
		guard let pointer = sqlite3_column_text(row, index) else { return nil }
		return String(cString: pointer)
	}

	static func data(_ row: OpaquePointer, _ index: Int32) -> Data? {
		guard sqlite3_column_type(row, index) != SQLITE_NULL else { return nil }
		let count = Int(sqlite3_column_bytes(row, index))
		guard count > 0, let pointer = sqlite3_column_blob(row, index) else { return Data() }
		return Data(bytes: pointer, count: count)
	}
}
