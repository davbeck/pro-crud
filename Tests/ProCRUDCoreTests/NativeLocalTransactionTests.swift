import CryptoKit
import CSQLite
import Foundation
import Loro
import Testing
@testable import ProCRUDCore

@Suite("Native local SQLite transactions")
struct NativeLocalTransactionTests {
	@Test func commitRetainsLocationAndSharedBookkeepingAndRetryIsIdempotent() throws {
		try withDatabase { url, database, streams in
			let source = try #require(streams.first)
			let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .copyrightTitle("Committed")))
			let receipt = try NativeLocalWorkspaceWriter.commitPrepared([patch], database: url)
			#expect(receipt.first?.alreadyApplied == false)
			let current = try snapshot(database, id: source.identity.documentID)
			#expect(current == patch.snapshot)
			#expect(try scalar(database, "SELECT count(*) FROM workspace_streams WHERE core_path='MISC/ProCRUDTarget22Acceptance' AND last_shared_version_vector IS NULL AND last_shared_version_vector_absence_reason=2 AND scope=0") == 1)
			let retry = try NativeLocalWorkspaceWriter.commitPrepared([patch], database: url)
			#expect(retry.first?.alreadyApplied == true)
			#expect(try scalar(database, "SELECT count(*) FROM workspace_operation_receipts") == 1)
			#expect(try snapshot(database, id: source.identity.documentID) == current)
		}
	}

	@Test func externalEditAfterPreparationCausesConflict() throws {
		try withDatabase { url, database, streams in
			let source = try #require(streams.first)
			let first = try #require(try NativeLocalPatch.prepare(stream: source, edit: .copyrightTitle("External")))
			let stale = try #require(try NativeLocalPatch.prepare(stream: source, edit: .copyrightTitle("Stale")))
			_ = try NativeLocalWorkspaceWriter.commitPrepared([first], database: url)
			#expect(throws: NativeWriteError.conflict(source.identity.documentID)) { try NativeLocalWorkspaceWriter.commitPrepared([stale], database: url) }
			#expect(try snapshot(database, id: source.identity.documentID) == first.snapshot)
			#expect(try scalar(database, "SELECT count(*) FROM workspace_operation_receipts") == 1)
		}
	}

	@Test func laterConflictRollsBackAllEarlierStreamsAndReceipts() throws {
		try withDatabase { url, database, streams in
			let first = try #require(try NativeLocalPatch.prepare(stream: streams[0], edit: .copyrightTitle("First")))
			let second = try #require(try NativeLocalPatch.prepare(stream: streams[1], edit: .copyrightTitle("Second")))
			let external = try #require(try NativeLocalPatch.prepare(stream: streams[1], edit: .copyrightTitle("External")))
			_ = try NativeLocalWorkspaceWriter.commitPrepared([external], database: url)
			#expect(throws: NativeWriteError.conflict(streams[1].identity.documentID)) { try NativeLocalWorkspaceWriter.commitPrepared([first, second], database: url) }
			#expect(try snapshot(database, id: streams[0].identity.documentID) == streams[0].snapshot)
			#expect(try snapshot(database, id: streams[1].identity.documentID) == external.snapshot)
			#expect(try scalar(database, "SELECT count(*) FROM workspace_operation_receipts") == 1)
		}
	}

	@Test func batchPreparationGroupsDocumentsAndFailsBeforeAnyPublication() throws {
		try withDatabase { url, database, streams in
			let workspace = NativeWorkspaceSnapshot(root: url.deletingLastPathComponent(), workspaceID: UUID(), metadata: [:], streams: streams)
			let operations: [NativePresentationOperation] = [
				.init(documentID: streams[0].identity.documentID, edit: .notes("First notes")),
				.init(documentID: streams[1].identity.documentID, edit: .copyrightTitle("Second title")),
				.init(documentID: streams[0].identity.documentID, edit: .copyrightTitle("First title")),
			]
			let invalid = operations + [.init(documentID: UUID(), edit: .notes("Missing"))]
			#expect(throws: NativeSemanticError.self) { try NativeLocalWorkspaceWriter.prepare(invalid, in: workspace) }
			#expect(try snapshot(database, id: streams[0].identity.documentID) == streams[0].snapshot)
			#expect(try snapshot(database, id: streams[1].identity.documentID) == streams[1].snapshot)
			#expect(try scalar(database, "SELECT count(*) FROM workspace_operation_receipts") == 0)
			let patches = try NativeLocalWorkspaceWriter.prepare(operations, in: workspace)
			#expect(patches.map(\.identity.documentID) == streams.map(\.identity.documentID))
			let receipts = try NativeLocalWorkspaceWriter.commitPrepared(patches, database: url)
			#expect(receipts.count == 2)
			let first = NativeWorkspaceStream(identity: streams[0].identity, snapshot: patches[0].snapshot, versionVector: patches[0].versionVector, lastSharedVersionVector: nil)
			#expect(try first.protobufProjection().presentation().notes == "First notes")
			#expect(try first.protobufProjection().presentation().ccli.songTitle == "First title")
			#expect(try scalar(database, "SELECT count(*) FROM workspace_operation_receipts") == 2)
		}
	}

	@Test func finalEnvironmentFailureRollsBackTheWholeCommit() throws {
		try withDatabase { url, database, streams in
			let patch = try #require(try NativeLocalPatch.prepare(stream: streams[0], edit: .notes("Changed")))
			#expect(throws: NativeWriteError.activeWriters(["writer resumed"])) {
				try NativeLocalWorkspaceWriter.commitPrepared([patch], database: url) { throw NativeWriteError.activeWriters(["writer resumed"]) }
			}
			#expect(try snapshot(database, id: streams[0].identity.documentID) == streams[0].snapshot)
			#expect(try scalar(database, "SELECT count(*) FROM workspace_operation_receipts") == 0)
		}
	}

	@Test func operationIdentityCannotBeReusedForDifferentContent() throws {
		try withDatabase { url, database, streams in
			let operation = UUID()
			let first = try #require(try NativeLocalPatch.prepare(stream: streams[0], edit: .notes("First"), operationID: operation))
			let second = try #require(try NativeLocalPatch.prepare(stream: streams[0], edit: .notes("Second"), operationID: operation))
			_ = try NativeLocalWorkspaceWriter.commitPrepared([first], database: url)
			#expect(throws: NativeWriteError.operationCollision(operation)) { try NativeLocalWorkspaceWriter.commitPrepared([second], database: url) }
			#expect(try snapshot(database, id: streams[0].identity.documentID) == first.snapshot)
		}
	}

	@Test func aChangedReferenceStreamRejectsTheTransactionBeforePublishingItsPatch() throws {
		try withDatabase { url, database, streams in
			let pending = try #require(try NativeLocalPatch.prepare(stream: streams[0], edit: .notes("Pending deletion transaction")))
			let external = try #require(try NativeLocalPatch.prepare(stream: streams[1], edit: .notes("Reference source changed")))
			_ = try NativeLocalWorkspaceWriter.commitPrepared([external], database: url)
			#expect(throws: NativeWriteError.conflict(streams[1].identity.documentID)) {
				try NativeLocalWorkspaceWriter.commitPrepared([pending], expectedReferenceStreams: streams, database: url)
			}
			#expect(try snapshot(database, id: streams[0].identity.documentID) == streams[0].snapshot)
			#expect(try scalar(database, "SELECT count(*) FROM workspace_operation_receipts") == 1)
		}
	}

	@Test func anAddedReferenceStreamRejectsTheTransactionBeforePublishingItsPatch() throws {
		try withDatabase { url, database, streams in
			let pending = try #require(try NativeLocalPatch.prepare(stream: streams[0], edit: .notes("Pending deletion transaction")))
			let added = UUID(), original = streams[1].identity.documentID.uuidString.replacingOccurrences(of: "-", with: "")
			try execute("""
			INSERT INTO workspace_streams(document_id,scope,location_type,kind,core_path,availability,snapshot,version_vector,sha256,byte_count,updated_at_ms,last_shared_version_vector,last_shared_version_vector_absence_reason,core_path_key)
			SELECT X'\(added.uuidString.replacingOccurrences(of: "-", with: ""))',scope,location_type,kind,'MISC/Added',availability,snapshot,version_vector,sha256,byte_count,updated_at_ms,last_shared_version_vector,last_shared_version_vector_absence_reason,'misc/added'
			FROM workspace_streams WHERE document_id=X'\(original)'
			""", database)
			#expect(throws: NativeWriteError.conflict(added)) {
				try NativeLocalWorkspaceWriter.commitPrepared([pending], expectedReferenceStreams: streams, database: url)
			}
			#expect(try snapshot(database, id: streams[0].identity.documentID) == streams[0].snapshot)
			#expect(try scalar(database, "SELECT count(*) FROM workspace_operation_receipts") == 0)
		}
	}

	@Test func anAppliedDeletionReceiptRetriesWithoutRecheckingUnrelatedFutureContent() throws {
		try withDatabase { url, _, streams in
			let source = streams[0], id = UUID()
			let create = try #require(try NativeLocalPatch.prepare(stream: source, edit: .createArrangement(id: id, name: "Owned retry control", groups: [], select: true)))
			_ = try NativeLocalWorkspaceWriter.commitPrepared([create], database: url)
			let created = NativeWorkspaceStream(identity: source.identity, snapshot: create.snapshot, versionVector: create.versionVector, lastSharedVersionVector: nil)
			let remove = try #require(try NativeLocalPatch.prepare(stream: created, edit: .removeArrangement(id)))
			_ = try NativeLocalWorkspaceWriter.commitPrepared([remove], database: url)
			let deleted = NativeWorkspaceStream(identity: source.identity, snapshot: remove.snapshot, versionVector: remove.versionVector, lastSharedVersionVector: nil)
			var unknownID = source.identity; unknownID.documentID = UUID(); unknownID.kind = "FutureRoot"
			let unknown = NativeWorkspaceStream(identity: unknownID, snapshot: source.snapshot, versionVector: source.versionVector, lastSharedVersionVector: nil)
			let current = NativeWorkspaceSnapshot(root: url.deletingLastPathComponent(), workspaceID: UUID(), metadata: [:], streams: [deleted, streams[1], unknown])
			let receipts = try NativeLocalWorkspaceWriter.commitPrepared([remove], arrangementReferenceSnapshot: current, database: url)
			#expect(receipts.count == 1 && receipts.first?.alreadyApplied == true)
		}
	}

	private func withDatabase(_ body: (URL, OpaquePointer, [NativeWorkspaceStream]) throws -> Void) throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("workspace-v1.sqlite3")
		var pointer: OpaquePointer?
		#expect(sqlite3_open(url.path, &pointer) == SQLITE_OK)
		let database = try #require(pointer)
		defer { sqlite3_close(database) }
		try execute(String(contentsOf: fixtures.appendingPathComponent("schema-9.sql"), encoding: .utf8), database)
		let data = try Data(contentsOf: fixtures.appendingPathComponent("Persistence/before.loro"))
		var streams: [NativeWorkspaceStream] = []
		for index in 0 ..< 2 {
			let document = LoroDoc()
			_ = try document.import(bytes: data)
			let id = index == 0 ? try #require(UUID(uuidString: "4eb485bd-667d-56db-9525-779a88cfce0f")) : UUID()
			if index == 1 {
				try document.getMap(id: "root").insert(key: "uuid", v: id.uuidString)
			}
			let snapshot = try document.exportSnapshot()
			let vector = document.oplogVv().encode()
			let hash = Data(SHA256.hash(data: snapshot))
			let path = index == 0 ? "MISC/ProCRUDTarget22Acceptance" : "MISC/Second"
			try execute("""
			INSERT INTO workspace_streams(document_id,scope,location_type,kind,core_path,availability,snapshot,version_vector,sha256,byte_count,updated_at_ms,last_shared_version_vector,last_shared_version_vector_absence_reason,core_path_key)
			VALUES(X'\(id.uuidString.replacingOccurrences(of: "-", with: ""))',0,1,'Presentation','\(path)',0,X'\(hex(snapshot))',X'\(hex(vector))',X'\(hex(hash))',\(snapshot.count),0,NULL,2,'\(path.lowercased())')
			""", database)
			streams.append(.init(identity: .init(documentID: id, scope: .shared, kind: "Presentation", corePath: path, availability: .available, byteCount: Int64(snapshot.count), sha256: hex(hash), updatedAtMilliseconds: 0), snapshot: snapshot, versionVector: vector, lastSharedVersionVector: nil))
		}
		try body(url, database, streams)
	}

	private func execute(_ sql: String, _ database: OpaquePointer) throws {
		let result = sqlite3_exec(database, sql, nil, nil, nil)
		guard result == SQLITE_OK else { throw NativeWriteError.database(code: result, message: String(cString: sqlite3_errmsg(database))) }
	}

	private func scalar(_ database: OpaquePointer, _ sql: String) throws -> Int64 {
		var pointer: OpaquePointer?
		#expect(sqlite3_prepare_v2(database, sql, -1, &pointer, nil) == SQLITE_OK)
		let statement = try #require(pointer)
		defer { sqlite3_finalize(statement) }
		#expect(sqlite3_step(statement) == SQLITE_ROW)
		return sqlite3_column_int64(statement, 0)
	}

	private func snapshot(_ database: OpaquePointer, id: UUID) throws -> Data {
		var pointer: OpaquePointer?
		let sql = "SELECT snapshot FROM workspace_streams WHERE document_id=X'\(id.uuidString.replacingOccurrences(of: "-", with: ""))' AND scope=0"
		#expect(sqlite3_prepare_v2(database, sql, -1, &pointer, nil) == SQLITE_OK)
		let statement = try #require(pointer)
		defer { sqlite3_finalize(statement) }
		#expect(sqlite3_step(statement) == SQLITE_ROW)
		return try #require(WorkspaceDatabase.data(statement, 0))
	}

	private func hex(_ data: Data) -> String {
		data.map { String(format: "%02x", $0) }.joined()
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native")
	}
}
