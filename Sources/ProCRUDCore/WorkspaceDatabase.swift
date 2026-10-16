import CSQLite
import Darwin
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

/// Captures committed WAL data through SQLite's backup API. A closed WAL
/// database without sidecars uses a verified stable main image, deserialized
/// into memory. Neither path opens a writable live handle or creates sidecars.
final class WorkspaceDatabase {
	private let handle: OpaquePointer
	private enum CaptureError: Error { case changed }
	private static let maximumBytes = 512 * 1024 * 1024

	init(snapshotOf url: URL, afterOfflineRead: (() throws -> Void)? = nil) throws {
		let url = url.resolvingSymlinksInPath().standardizedFileURL
		for _ in 0 ..< 3 {
			do {
				handle = try Self.capture(url, afterOfflineRead: afterOfflineRead)
				return
			} catch CaptureError.changed { continue }
		}
		throw NativeWorkspaceError.database("Database changed while capturing its offline image. Retry after the active writer settles.")
	}

	private static func capture(_ url: URL, afterOfflineRead: (() throws -> Void)?) throws -> OpaquePointer {
		guard FileManager.default.fileExists(atPath: url.path) else {
			throw NativeWorkspaceError.database("Database is missing at \(url.path).")
		}
		// Even a READONLY SQLite connection can initialize WAL sidecars when
		// their directory is writable. Capture an offline image before opening
		// SQLite whenever no journal/sidecars exist.
		if noSidecars(url) {
			return try captureOffline(url, afterRead: afterOfflineRead)
		}
		let hasWAL = FileManager.default.fileExists(atPath: url.path + "-wal")
		let hasSharedMemory = FileManager.default.fileExists(atPath: url.path + "-shm")
		if hasWAL != hasSharedMemory {
			throw NativeWorkspaceError.database("Incomplete WAL/shared-memory sidecar pair. Open the workspace in ProPresenter or obtain a SQLite backup; read-only inspection will not initialize missing sidecars.")
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
		else {
			if sqlite3_errcode(source) == SQLITE_CANTOPEN, noSidecars(url) {
				return try captureOffline(url, afterRead: afterOfflineRead)
			}
			throw NativeWorkspaceError.database("Cannot determine snapshot size: \(String(cString: sqlite3_errmsg(source)))")
		}
		defer { sqlite3_finalize(sizeStatement) }
		guard sqlite3_step(sizeStatement) == SQLITE_ROW,
		      sqlite3_column_int64(sizeStatement, 0) <= maximumBytes
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
		return destination
	}

	private static func noSidecars(_ url: URL) -> Bool {
		["-wal", "-shm", "-journal"].allSatisfy { !FileManager.default.fileExists(atPath: url.path + $0) }
	}

	private struct FileState: Equatable {
		let device: dev_t
		let inode: ino_t
		let size: off_t
		let modifiedSeconds: Int
		let modifiedNanoseconds: Int
		let changedSeconds: Int
		let changedNanoseconds: Int

		init(_ stat: stat) {
			device = stat.st_dev
			inode = stat.st_ino
			size = stat.st_size
			modifiedSeconds = stat.st_mtimespec.tv_sec
			modifiedNanoseconds = stat.st_mtimespec.tv_nsec
			changedSeconds = stat.st_ctimespec.tv_sec
			changedNanoseconds = stat.st_ctimespec.tv_nsec
		}
	}

	private static func captureOffline(_ url: URL, afterRead: (() throws -> Void)?) throws -> OpaquePointer {
		guard noSidecars(url) else { throw CaptureError.changed }
		let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
		guard descriptor >= 0 else { throw NativeWorkspaceError.database("Cannot open the offline database image.") }
		let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
		defer { try? file.close() }
		var before = stat()
		guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
		      before.st_size >= 100, before.st_size <= maximumBytes
		else { throw NativeWorkspaceError.database("Offline database must be a regular SQLite file within the 512 MiB inspection limit.") }
		var data = Data()
		while let chunk = try file.read(upToCount: 64 * 1024), !chunk.isEmpty {
			data.append(chunk)
			guard data.count <= before.st_size else { throw CaptureError.changed }
		}
		try afterRead?()
		var after = stat()
		var current = stat()
		guard fstat(descriptor, &after) == 0, lstat(url.path, &current) == 0,
		      FileState(before) == FileState(after), FileState(before) == FileState(current),
		      data.count == before.st_size, noSidecars(url)
		else { throw CaptureError.changed }
		guard data.starts(with: Data("SQLite format 3\0".utf8)), [1, 2].contains(data[18]), [1, 2].contains(data[19]) else {
			throw NativeWorkspaceError.database("Offline capture requires a complete SQLite main image with a supported journal format and no sidecars.")
		}
		// SQLite documents normalizing these journal-version bytes in a private
		// buffer before deserialize. Never mark the mutable source immutable or
		// ignore a source WAL. The stable image above has no WAL to replay.
		// https://sqlite.org/c3ref/deserialize.html
		let capacity = data.count + 20
		guard let memory = sqlite3_malloc64(UInt64(capacity)) else { throw NativeWorkspaceError.database("Cannot allocate the offline database image.") }
		let bytes = memory.bindMemory(to: UInt8.self, capacity: capacity)
		bytes.initialize(repeating: 0, count: capacity)
		data.copyBytes(to: bytes, count: data.count)
		bytes[18] = 1
		bytes[19] = 1
		var destination: OpaquePointer?
		let opened = sqlite3_open_v2(":memory:", &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
		guard opened == SQLITE_OK, let destination else {
			sqlite3_free(memory)
			if let destination {
				sqlite3_close(destination)
			}
			throw NativeWorkspaceError.database("Cannot allocate the offline SQLite snapshot.")
		}
		let status = sqlite3_deserialize(destination, "main", bytes, Int64(data.count), Int64(capacity), UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_READONLY))
		guard status == SQLITE_OK else {
			// FREEONCLOSE also frees the buffer when deserialize fails.
			let message = String(cString: sqlite3_errmsg(destination))
			sqlite3_close(destination)
			throw NativeWorkspaceError.database("Cannot deserialize the offline SQLite image: \(message)")
		}
		return destination
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
