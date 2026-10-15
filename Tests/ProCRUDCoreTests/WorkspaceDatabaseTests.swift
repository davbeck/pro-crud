import CSQLite
import Foundation
import Testing
@testable import ProCRUDCore

@Suite("Read-only closed WAL snapshots")
struct WorkspaceDatabaseTests {
	@Test func checkpointedClosedWALReadsWithoutCreatingSidecarsOrChangingSource() throws {
		try withClosedWAL { url in
			let before = try Data(contentsOf: url)
			#expect(before[18] == 2 && before[19] == 2)
			let snapshot = try WorkspaceDatabase(snapshotOf: url)
			#expect(try snapshot.integer("SELECT value FROM sample") == 42)
			#expect(try Data(contentsOf: url) == before)
			#expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == [url.lastPathComponent])
		}
	}

	@Test func committedExternalChangeDuringOfflineReadRetriesTheSnapshot() throws {
		try withClosedWAL { url in
			var reads = 0
			let snapshot = try WorkspaceDatabase(snapshotOf: url) {
				reads += 1
				if reads == 1 {
					try update(url, sql: "UPDATE sample SET value=84")
				}
			}
			#expect(reads == 2)
			#expect(try snapshot.integer("SELECT value FROM sample") == 84)
			#expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
			#expect(!FileManager.default.fileExists(atPath: url.path + "-shm"))
		}
	}

	@Test func writerOpeningWALDuringOfflineCaptureUsesCommittedWALOnRetry() throws {
		try withClosedWAL { url in
			var writer: OpaquePointer?
			defer {
				if let writer {
					sqlite3_exec(writer, "ROLLBACK", nil, nil, nil)
					sqlite3_close(writer)
				}
			}
			var reads = 0
			let snapshot = try WorkspaceDatabase(snapshotOf: url) {
				reads += 1
				let opened = sqlite3_open(url.path, &writer)
				#expect(opened == SQLITE_OK)
				let handle = try #require(writer)
				try execute("PRAGMA wal_autocheckpoint=0; UPDATE sample SET value=84; BEGIN; UPDATE sample SET value=999;", in: handle)
			}
			#expect(reads == 1)
			#expect(try snapshot.integer("SELECT value FROM sample") == 84)
			#expect(FileManager.default.fileExists(atPath: url.path + "-wal"))
		}
	}

	@Test func continuouslyChangingOfflineImageFailsAfterBoundedRetries() throws {
		try withClosedWAL { url in
			var reads = 0
			#expect(throws: NativeWorkspaceError.self) {
				try WorkspaceDatabase(snapshotOf: url) {
					reads += 1
					try update(url, sql: "UPDATE sample SET value=value+1")
				}
			}
			#expect(reads == 3)
			let settled = try WorkspaceDatabase(snapshotOf: url)
			#expect(try settled.integer("SELECT value FROM sample") == 45)
		}
	}

	@Test(arguments: ["-wal", "-shm"]) func incompleteSidecarPairIsNeverIgnoredOrRepaired(suffix: String) throws {
		try withClosedWAL { url in
			let before = try Data(contentsOf: url)
			let sidecar = Data("uninspected sidecar cannot be discarded".utf8)
			try sidecar.write(to: URL(fileURLWithPath: url.path + suffix))
			#expect(throws: NativeWorkspaceError.self) { try WorkspaceDatabase(snapshotOf: url) }
			#expect(try Data(contentsOf: url) == before)
			#expect(try Data(contentsOf: URL(fileURLWithPath: url.path + suffix)) == sidecar)
			let other = suffix == "-wal" ? "-shm" : "-wal"
			#expect(!FileManager.default.fileExists(atPath: url.path + other))
		}
	}

	private func withClosedWAL(_ body: (URL) throws -> Void) throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let url = root.appendingPathComponent("workspace.sqlite3")
		try update(url, sql: "PRAGMA journal_mode=WAL; CREATE TABLE sample(value INTEGER); INSERT INTO sample VALUES(42)")
		#expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
		#expect(!FileManager.default.fileExists(atPath: url.path + "-shm"))
		try body(url)
	}

	private func update(_ url: URL, sql: String) throws {
		var pointer: OpaquePointer?
		let opened = sqlite3_open(url.path, &pointer)
		#expect(opened == SQLITE_OK)
		let handle = try #require(pointer)
		defer { sqlite3_close(handle) }
		// This macOS SQLite defaults to persistent WAL sidecars. The fixture
		// explicitly requests normal last-writer cleanup to model the observed
		// native closed workspace; it never deletes an uncheckpointed WAL.
		var persistence: Int32 = 0
		let persistStatus = sqlite3_file_control(handle, "main", SQLITE_FCNTL_PERSIST_WAL, &persistence)
		#expect(persistStatus == SQLITE_OK)
		try execute(sql, in: handle)
	}

	private func execute(_ sql: String, in handle: OpaquePointer) throws {
		guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw NativeWorkspaceError.database(String(cString: sqlite3_errmsg(handle))) }
	}
}
