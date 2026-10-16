import CSQLite
import Foundation

public enum NativeWriteError: Error, CustomStringConvertible, Sendable, Equatable {
	case activeWriters([String])
	case notRegisteredLocalWorkspace
	case conflict(UUID)
	case operationCollision(UUID)
	case database(code: Int32, message: String)
	case invalidBatch

	public var description: String {
		switch self {
		case let .activeWriters(writers): "Quit ProPresenter and stop its workspace helpers before local writes: \(writers.joined(separator: "; "))"
		case .notRegisteredLocalWorkspace: "Native writes require an explicitly selected, registered local workspace. Cloud workspaces are not supported."
		case let .conflict(id): "Native document \(id) changed after preparation. Reload before applying the edit."
		case let .operationCollision(id): "Native operation ID \(id) already has a different receipt."
		case let .database(code, message): "Cannot commit native workspace transaction (SQLite \(code)): \(message)"
		case .invalidBatch: "A native transaction requires distinct document and operation identities."
		}
	}
}

public struct NativeLocalCommitReceipt: Codable, Sendable, Equatable {
	public let operationID: UUID
	public let documentID: UUID
	public let versionVector: Data
	public let alreadyApplied: Bool
}

public struct NativePresentationOperation: Sendable, Equatable {
	public let documentID: UUID
	public let edit: NativePresentationEdit

	public init(documentID: UUID, edit: NativePresentationEdit) {
		self.documentID = documentID
		self.edit = edit
	}
}

public enum NativeLocalWorkspaceWriter {
	/// Explicit offline writer setup. SQLite may initialize its normal WAL
	/// sidecars; ordinary read-only inspection never takes this path. The normal
	/// handles remain open while the consistent reader and transaction run.
	public static func withOfflineWriteAccess<T>(to root: URL, registry: URL, body: (NativeWorkspaceSnapshot) throws -> T) throws -> T {
		try requireStoppedWriters()
		let root = root.resolvingSymlinksInPath()
		let inspection = try WorkspaceInspector.inspect(root)
		guard inspection.storage == .nativeLoro, inspection.storageMarker == "sqlite-v1" else { throw NativeWriteError.notRegisteredLocalWorkspace }
		let registryContext = try NativeTransactionDatabase(url: registry)
		_ = try registryContext.query("PRAGMA user_version") { sqlite3_column_int64($0, 0) }
		try verifyLocalWorkspace(root, registry: registry)
		let workspaceContext = try NativeTransactionDatabase(url: root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3"))
		_ = try workspaceContext.query("PRAGMA user_version") { sqlite3_column_int64($0, 0) }
		return try withExtendedLifetime((registryContext, workspaceContext)) {
			try body(NativeWorkspaceSnapshot.read(from: root))
		}
	}

	/// Qualified local/offline Presentation operations retain existing history.
	/// Media files, library locations, client streams and shared-version
	/// bookkeeping are not replaced.
	public static func edit(_ edit: NativePresentationEdit, documentID: UUID, in root: URL, registry: URL) throws -> [NativeLocalCommitReceipt] {
		try apply([.init(documentID: documentID, edit: edit)], in: root, registry: registry)
	}

	/// Prepare every operation against one consistent snapshot, then publish all
	/// changed documents and their receipts in one transaction.
	public static func apply(_ operations: [NativePresentationOperation], in root: URL, registry: URL) throws -> [NativeLocalCommitReceipt] {
		try withOfflineWriteAccess(to: root, registry: registry) { snapshot in
			let prepared = try prepareTransaction(operations, in: snapshot)
			return try commitPrepared(prepared.patches, expectedReferenceStreams: prepared.referenceReadSet, database: root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3")) {
				try verifyLocalWorkspace(root.resolvingSymlinksInPath(), registry: registry)
			}
		}
	}

	static func prepare(_ operations: [NativePresentationOperation], in snapshot: NativeWorkspaceSnapshot) throws -> [NativeLocalPatch] {
		try prepareTransaction(operations, in: snapshot).patches
	}

	private static func prepareTransaction(_ operations: [NativePresentationOperation], in snapshot: NativeWorkspaceSnapshot) throws -> (patches: [NativeLocalPatch], referenceReadSet: [NativeWorkspaceStream]?) {
		var order: [UUID] = []
		var grouped: [UUID: [NativePresentationEdit]] = [:]
		for operation in operations {
			if grouped[operation.documentID] == nil {
				order.append(operation.documentID)
			}
			grouped[operation.documentID, default: []].append(operation.edit)
		}
		let patches = try order.compactMap { id in
			guard let stream = snapshot.streams.first(where: { $0.identity.documentID == id && $0.identity.scope == .shared }) else { throw NativeSemanticError.missingReference(path: "/streams", identity: id.uuidString) }
			return try NativeLocalPatch.prepare(stream: stream, edits: grouped[id] ?? [])
		}
		let readSet = try NativeArrangementDeletion.validate(patches, in: snapshot)
		return (patches, readSet)
	}

	public static func commit(_ patches: [NativeLocalPatch], to root: URL, registry: URL) throws -> [NativeLocalCommitReceipt] {
		try withOfflineWriteAccess(to: root, registry: registry) { snapshot in
			try commitPrepared(patches, arrangementReferenceSnapshot: snapshot, database: root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3")) {
				try verifyLocalWorkspace(root.resolvingSymlinksInPath(), registry: registry)
			}
		}
	}

	private static func verifyLocalWorkspace(_ root: URL, registry: URL) throws {
		try requireStoppedWriters()
		let inspection = try WorkspaceInspector.inspect(root)
		let entries = try WorkspaceRegistry.read(from: registry).filter { URL(fileURLWithPath: $0.root).resolvingSymlinksInPath() == root }
		guard inspection.storage == .nativeLoro, entries.count == 1, let entry = entries.first,
		      entry.cloudID == nil, entry.availability == "local", entry.localID.lowercased() == inspection.workspaceID?.lowercased()
		else { throw NativeWriteError.notRegisteredLocalWorkspace }
	}

	static func requireStoppedWriters() throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/ps")
		process.arguments = ["-axo", "uid=,pid=,comm="]
		let pipe = Pipe()
		process.standardOutput = pipe
		try process.run()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { throw NativeWriteError.database(code: process.terminationStatus, message: "Cannot inspect workspace writers.") }
		let writers = String(decoding: data, as: UTF8.self).split(separator: "\n").filter { line in
			let columns = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
			guard columns.count == 3 else { return false }
			let path = String(columns[2])
			let name = URL(fileURLWithPath: path).lastPathComponent
			return name == "ProPresenter" || name.hasPrefix("ProPresenter Helper (") || path.contains("/Helpers/Workspaces/")
		}.map(String.init)
		guard writers.isEmpty else { throw NativeWriteError.activeWriters(writers) }
	}

	private static func verifyReferenceReadSet(_ expected: [NativeWorkspaceStream], database: NativeTransactionDatabase) throws {
		let current = try database.query("""
		SELECT document_id, scope, kind, core_path, availability, snapshot,
		       version_vector, sha256, byte_count, updated_at_ms, last_shared_version_vector, location_type
		FROM workspace_streams
		""", row: NativeWorkspaceSnapshot.readStream)
		func key(_ stream: NativeWorkspaceStream) -> String {
			"\(stream.identity.documentID):\(stream.identity.scope.rawValue)"
		}
		let byID = Dictionary(uniqueKeysWithValues: current.map { (key($0), $0) })
		let expectedIDs = Set(expected.map(key))
		if let added = current.first(where: { !expectedIDs.contains(key($0)) }) {
			throw NativeWriteError.conflict(added.identity.documentID)
		}
		for original in expected {
			guard let actual = byID[key(original)], actual.snapshot == original.snapshot, actual.versionVector == original.versionVector,
			      actual.identity.kind == original.identity.kind, actual.identity.corePath == original.identity.corePath,
			      actual.identity.availability == original.identity.availability
			else { throw NativeWriteError.conflict(original.identity.documentID) }
		}
	}

	/// Internal transaction primitive also used with isolated schema-9 fixtures.
	/// The public entry point always checks live writers and local registration.
	static func commitPrepared(_ patches: [NativeLocalPatch], expectedReferenceStreams: [NativeWorkspaceStream]? = nil, arrangementReferenceSnapshot: NativeWorkspaceSnapshot? = nil, database url: URL, beforeCommit: () throws -> Void = {}) throws -> [NativeLocalCommitReceipt] {
		guard !patches.isEmpty else { return [] }
		guard Set(patches.map(\.operationID)).count == patches.count, Set(patches.map(\.identity.documentID)).count == patches.count else { throw NativeWriteError.invalidBatch }
		let database = try NativeTransactionDatabase(url: url)
		try database.execute("BEGIN IMMEDIATE")
		defer { try? database.execute("ROLLBACK") }
		let schema = try database.query("SELECT (SELECT user_version FROM pragma_user_version), (SELECT application_id FROM pragma_application_id)") { (sqlite3_column_int64($0, 0), sqlite3_column_int64($0, 1)) }.first
		guard schema?.0 == NativeWorkspaceSnapshot.schemaVersion, schema?.1 == NativeWorkspaceSnapshot.applicationID else {
			throw NativeWorkspaceError.unsupportedSchema(applicationID: schema?.1 ?? -1, version: schema?.0 ?? -1)
		}
		if let expectedReferenceStreams {
			try verifyReferenceReadSet(expectedReferenceStreams, database: database)
		}
		if let arrangementReferenceSnapshot {
			// Receipt retries do not repeat deletion or apply an old snapshot over
			// later edits. Check graph dependencies only for pending operations.
			let pending = try patches.filter { patch in
				try database.query("SELECT 1 FROM workspace_operation_receipts WHERE operation_id=?", [.blob(uuidBytes(patch.operationID))]) { _ in true }.isEmpty
			}
			if let readSet = try NativeArrangementDeletion.validate(pending, in: arrangementReferenceSnapshot) {
				try verifyReferenceReadSet(readSet, database: database)
			}
		}
		var receipts: [NativeLocalCommitReceipt] = []
		for patch in patches {
			let operation = uuidBytes(patch.operationID)
			let id = uuidBytes(patch.identity.documentID)
			let existing = try database.query("SELECT document_id, scope, operation_kind, payload_fingerprint, durable_version_vector FROM workspace_operation_receipts WHERE operation_id=?", [.blob(operation)]) { row in
				(WorkspaceDatabase.data(row, 0), sqlite3_column_int(row, 1), WorkspaceDatabase.text(row, 2), WorkspaceDatabase.data(row, 3), WorkspaceDatabase.data(row, 4))
			}.first
			if let existing {
				guard existing.0 == id, existing.1 == 0, existing.2 == "patch", existing.3 == patch.payloadFingerprint, existing.4 == patch.versionVector else { throw NativeWriteError.operationCollision(patch.operationID) }
				receipts.append(.init(operationID: patch.operationID, documentID: patch.identity.documentID, versionVector: patch.versionVector, alreadyApplied: true))
				continue
			}
			let current = try database.query("SELECT snapshot, version_vector, core_path, kind, availability FROM workspace_streams WHERE document_id=? AND scope=0", [.blob(id)]) { row in
				(WorkspaceDatabase.data(row, 0), WorkspaceDatabase.data(row, 1), WorkspaceDatabase.text(row, 2), WorkspaceDatabase.text(row, 3), sqlite3_column_int(row, 4))
			}.first
			guard let current, current.0 == patch.originalSnapshot, current.1 == patch.originalVersionVector,
			      current.2 == patch.identity.corePath, current.3 == patch.identity.kind, current.4 == 0
			else { throw NativeWriteError.conflict(patch.identity.documentID) }
			try database.execute("""
			UPDATE workspace_streams SET snapshot=?, version_vector=?, sha256=?, byte_count=?, updated_at_ms=?
			WHERE document_id=? AND scope=0
			""", [.blob(patch.snapshot), .blob(patch.versionVector), .blob(patch.sha256), .integer(Int64(patch.snapshot.count)), .integer(patch.timestampMilliseconds), .blob(id)])
			// Generation zero belongs to this offline writer, not a fabricated live
			// helper session. Its acceptance is recorded by the local restart/edit test.
			try database.execute("""
			INSERT INTO workspace_operation_receipts(operation_id,operation_kind,workspace_generation,document_id,scope,
			payload_fingerprint,disposition,durable_version_vector,created_at_ms,operation_context_fingerprint)
			VALUES(?,'patch',0,?,0,?,0,?,?,zeroblob(32))
			""", [.blob(operation), .blob(id), .blob(patch.payloadFingerprint), .blob(patch.versionVector), .integer(patch.timestampMilliseconds)])
			receipts.append(.init(operationID: patch.operationID, documentID: patch.identity.documentID, versionVector: patch.versionVector, alreadyApplied: false))
		}
		try beforeCommit()
		try database.execute("COMMIT")
		return receipts
	}

	private static func uuidBytes(_ value: UUID) -> Data {
		var bytes = value.uuid
		return withUnsafeBytes(of: &bytes) { Data($0) }
	}
}

private final class NativeTransactionDatabase {
	enum Binding { case blob(Data), integer(Int64) }
	private let handle: OpaquePointer

	init(url: URL) throws {
		var pointer: OpaquePointer?
		let result = sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
		guard result == SQLITE_OK, let pointer else {
			let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Database unavailable."
			if let pointer {
				sqlite3_close(pointer)
			}
			throw NativeWriteError.database(code: result, message: message)
		}
		handle = pointer
		sqlite3_busy_timeout(handle, 2000)
	}

	deinit { sqlite3_close(handle) }

	func execute(_ sql: String, _ bindings: [Binding] = []) throws {
		let statement = try prepare(sql, bindings)
		defer { sqlite3_finalize(statement) }
		let result = sqlite3_step(statement)
		guard result == SQLITE_DONE else { throw error(result) }
	}

	func query<T>(_ sql: String, _ bindings: [Binding] = [], row: (OpaquePointer) throws -> T) throws -> [T] {
		let statement = try prepare(sql, bindings)
		defer { sqlite3_finalize(statement) }
		var rows: [T] = []
		while true {
			let result = sqlite3_step(statement)
			if result == SQLITE_DONE {
				return rows
			}
			guard result == SQLITE_ROW else { throw error(result) }
			try rows.append(row(statement))
		}
	}

	private func prepare(_ sql: String, _ bindings: [Binding]) throws -> OpaquePointer {
		var statement: OpaquePointer?
		let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
		guard result == SQLITE_OK, let statement else { throw error(result) }
		for (offset, binding) in bindings.enumerated() {
			let index = Int32(offset + 1)
			let status: Int32
			switch binding {
			case let .blob(data): status = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
			case let .integer(value): status = sqlite3_bind_int64(statement, index, value)
			}
			if status != SQLITE_OK {
				sqlite3_finalize(statement); throw error(status)
			}
		}
		return statement
	}

	private func error(_ code: Int32) -> NativeWriteError {
		.database(code: code, message: String(cString: sqlite3_errmsg(handle)))
	}
}
