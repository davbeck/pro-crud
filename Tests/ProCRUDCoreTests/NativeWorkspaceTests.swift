import CryptoKit
import CSQLite
import Foundation
import ProCRUDCore
import Testing

@Suite("ProPresenter 22 native snapshot reader")
struct NativeWorkspaceTests {
	@Test func nativeProjectionExportsBothTargetsWithoutChangingSource() throws {
		try withDatabase { root, database in
			try insertPresentation(database)
			let databaseURL = root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3")
			let before = try Data(contentsOf: databaseURL)
			let stream = try #require(NativeWorkspaceSnapshot.read(from: root).streams.first)
			let projection = try stream.protobufProjection()
			let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
			defer { try? FileManager.default.removeItem(at: destination) }
			for target in [ProPresenterTargetVersion.v21, .v22] {
				let output = destination.appendingPathComponent("Target\(target.rawValue).pro")
				let document = try ProPresenterDocument(payload: projection.payload(), origin: .raw(output))
				try DocumentWriter.writeRaw(document, to: output, targetVersion: target)
				#expect(try DocumentLoader.load(from: output).payload.serializedData() == document.payload.serializedData())
				#expect(try Data(contentsOf: databaseURL) == before)
				#expect(throws: (any Error).self) { try DocumentWriter.writeRaw(document, to: root.appendingPathComponent("Blocked.pro"), targetVersion: target) }
			}
		}
	}

	@Test
	func officialSwiftBindingDecodesIndependentNativeSnapshot() throws {
		try withDatabase { root, database in
			try insertPresentation(database)
			let snapshot = try NativeWorkspaceSnapshot.read(from: root)
			#expect(snapshot.streams.count == 1)
			let stream = try #require(snapshot.streams.first)
			#expect(stream.identity.documentID.uuidString == "48E32307-7A5A-56CC-8CCA-0BC82D6079C1")
			#expect(stream.identity.kind == "Presentation")
			#expect(stream.identity.scope == .shared)
			let value = try stream.decodedValue()
			guard case let .map(document) = value, case let .map(content)? = document["root"] else {
				Issue.record("Native snapshot has no root map.")
				return
			}
			#expect(content["name"] == .string("ProCRUD22Probe"))
			guard case let .map(cues)? = content["cues"], case let .list(placements)? = content["cue_group_placements"] else {
				Issue.record("Missing native cue map or placement tree.")
				return
			}
			#expect(cues.count == 1)
			#expect(placements.count == 1)
			#expect(content["cue_groups"] == nil)
		}
	}

	@Test
	func committedWALIsVisibleAndUncommittedEditsAreNot() throws {
		try withDatabase { root, database in
			try execute("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;", in: database)
			try insertPresentation(database)
			try execute("BEGIN; UPDATE workspace_streams SET kind='Uncommitted';", in: database)
			let before = try Data(contentsOf: root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3"))
			let wal = try Data(contentsOf: root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3-wal"))
			let snapshot = try NativeWorkspaceSnapshot.read(from: root)
			#expect(snapshot.streams.map(\.identity.kind) == ["Presentation"])
			#expect(try Data(contentsOf: root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3")) == before)
			#expect(try Data(contentsOf: root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3-wal")) == wal)
			try execute("ROLLBACK", in: database)
		}
	}

	@Test(arguments: [8, 10, 99])
	func unsupportedSchemasFailWithoutMigration(version: Int) throws {
		try withDatabase { root, database in
			try execute("PRAGMA user_version=\(version)", in: database)
			let url = root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3")
			let before = try Data(contentsOf: url)
			#expect(throws: NativeWorkspaceError.self) { try NativeWorkspaceSnapshot.read(from: root) }
			#expect(try Data(contentsOf: url) == before)
		}
	}

	@Test(arguments: ["sha256=zeroblob(32)", "byte_count=1", "scope=7", "location_type=1,core_path=NULL", "availability=1"])
	func corruptEnvelopesFailBeforeProjection(update: String) throws {
		try withDatabase { root, database in
			try insertPresentation(database)
			try execute("UPDATE workspace_streams SET \(update)", in: database)
			#expect(throws: NativeWorkspaceError.self) { try NativeWorkspaceSnapshot.read(from: root) }
		}
	}

	@Test
	func unavailableStreamsRemainExplicitAndSharedAndClientStaySeparate() throws {
		try withDatabase { root, database in
			try insertPresentation(database)
			try execute("""
			INSERT INTO workspace_streams
			SELECT document_id,1,'Presentation',NULL,0,snapshot,version_vector,sha256,byte_count,updated_at_ms,NULL,0
			FROM workspace_streams;
			INSERT INTO workspace_streams VALUES(zeroblob(16),0,'Theme','Lazy/Theme',1,NULL,NULL,NULL,0,0,NULL,1);
			""", in: database)
			let snapshot = try NativeWorkspaceSnapshot.read(from: root)
			#expect(snapshot.streams.count == 3)
			#expect(snapshot.streams.filter { $0.identity.kind == "Presentation" }.map(\.identity.scope.rawValue).sorted() == [0, 1])
			let missing = try #require(snapshot.streams.first { $0.identity.availability == .unavailable })
			#expect(throws: NativeWorkspaceError.self) { try missing.decodedValue() }
		}
	}

	@Test
	func vectorMismatchDoesNotBecomeSuccessfulContent() throws {
		try withDatabase { root, database in
			try insertPresentation(database)
			try execute("UPDATE workspace_streams SET version_vector=X'00'", in: database)
			let snapshot = try NativeWorkspaceSnapshot.read(from: root)
			let stream = try #require(snapshot.streams.first)
			#expect(throws: (any Error).self) { try stream.decodedValue() }
		}
	}

	private func withDatabase(_ body: (URL, OpaquePointer) throws -> Void) throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let store = root.appendingPathComponent("DocumentStore")
		try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		try Data("sqlite-v1\n".utf8).write(to: store.appendingPathComponent("workspace-storage-v1"))
		try Data("a2c7b779-ae49-48f9-aaaf-ff7466561ba3\n".utf8).write(to: store.appendingPathComponent("workspace-id"))
		var pointer: OpaquePointer?
		#expect(sqlite3_open(store.appendingPathComponent("workspace-v1.sqlite3").path, &pointer) == SQLITE_OK)
		let database = try #require(pointer)
		defer { sqlite3_close(database) }
		try execute("""
		PRAGMA user_version=9; PRAGMA application_id=1381390163;
		CREATE TABLE workspace_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
		CREATE TABLE workspace_streams(document_id BLOB,scope INTEGER,kind TEXT,core_path TEXT,
		availability INTEGER,snapshot BLOB,version_vector BLOB,sha256 BLOB,byte_count INTEGER,
		updated_at_ms INTEGER,last_shared_version_vector BLOB,location_type INTEGER);
		""", in: database)
		try body(root, database)
	}

	private func insertPresentation(_ database: OpaquePointer) throws {
		let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Fixtures/ProPresenter22/Native")
		let snapshot = try Data(contentsOf: fixtures.appendingPathComponent("Presentation.loro"))
		let vector = try Data(contentsOf: fixtures.appendingPathComponent("Presentation.version-vector"))
		func hex(_ data: Data) -> String {
			data.map { String(format: "%02x", $0) }.joined()
		}
		try execute("""
		INSERT INTO workspace_streams VALUES(X'48e323077a5a56cc8cca0bc82d6079c1',0,'Presentation',
		'MISC/ProCRUD22Probe',0,X'\(hex(snapshot))',X'\(hex(vector))',X'\(hex(Data(SHA256.hash(data: snapshot))))',\(snapshot.count),0,NULL,1)
		""", in: database)
	}

	private func execute(_ sql: String, in database: OpaquePointer) throws {
		guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
			throw NativeWorkspaceError.database(String(cString: sqlite3_errmsg(database)))
		}
	}
}
