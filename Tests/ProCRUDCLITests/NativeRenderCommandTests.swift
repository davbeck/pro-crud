import CryptoKit
import CSQLite
import CustomDump
import Foundation
import ProCRUDCore
import Testing
@testable import ProCRUDCLI

@Suite("Native Presentation rendering command")
struct NativeRenderCommandTests {
	@Test func nativeRenderingAgreesWithIndependentNativeExportAndPreservesSource() throws {
		try withWorkspace(media: false) { root, id in
			let database = root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3")
			let before = try Data(contentsOf: database)
			let output = root.deletingLastPathComponent().appendingPathComponent("native.json")
			try Render.parse([root.path, "--native-stream", id, "--format", "json", "--output", output.path]).run()
			let actual = try JSONDecoder().decode(EffectiveRendering.self, from: Data(contentsOf: output))
			let exported = try PresentationLoader.load(from: fixtures.appendingPathComponent("Interchange/NativePresentation.pro"))
			var expected = try PresentationRenderer.effectiveRendering(documents: [exported])
			let actualPresentation = try #require(actual.presentations.first)
			let expectedPresentation = try #require(expected.presentations.first)
			#expect(try #require(UUID(uuidString: actualPresentation.uuid)) == UUID(uuidString: expectedPresentation.uuid))
			// Native root UUID strings are lowercase; the independent export uses
			// uppercase. Compare identity before ignoring that spelling difference.
			expected.presentations[0].uuid = actualPresentation.uuid
			#expect(diff(actual, expected) == nil)
			#expect(try Data(contentsOf: database) == before)
		}
	}

	@Test func unqualifiedNativeMediaDoesNotReplaceExistingOutput() throws {
		try withWorkspace(media: true) { root, id in
			let output = root.deletingLastPathComponent().appendingPathComponent("existing.json")
			let sentinel = Data("existing output".utf8)
			try sentinel.write(to: output)
			#expect(throws: DocumentCompatibilityError.self) {
				try Render.parse([root.path, "--native-stream", id, "--format", "json", "--output", output.path, "--replace"]).run()
			}
			#expect(try Data(contentsOf: output) == sentinel)
		}
	}

	@Test func outputMustBeExplicitAndSeparateFromNativeStorage() throws {
		try withWorkspace(media: false) { root, id in
			let database = root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3")
			let before = try Data(contentsOf: database)
			let arguments = [root.path, "--native-stream", id, "--replace"]
			#expect(throws: (any Error).self) { try Render.parse(arguments).run() }
			for path in [root.path, database.path, root.deletingLastPathComponent().path] {
				#expect(throws: (any Error).self) { try Render.parse(arguments + ["--output", path]).run() }
			}
			#expect(throws: (any Error).self) {
				try Render.parse(arguments + ["--output", root.deletingLastPathComponent().appendingPathComponent("out").path, "--template-report", database.path]).run()
			}
			#expect(try Data(contentsOf: database) == before)
		}
	}

	@Test func missingOrMalformedNativeStreamDoesNotFallBackToRawLeftovers() throws {
		try withWorkspace(media: false) { root, _ in
			try Data(contentsOf: fixtures.appendingPathComponent("Interchange/NativePresentation.pro")).write(to: root.appendingPathComponent("Leftover.pro"))
			let output = root.deletingLastPathComponent().appendingPathComponent("missing.json")
			for id in ["not-a-uuid", UUID().uuidString] {
				#expect(throws: (any Error).self) {
					try Render.parse([root.path, "--native-stream", id, "--format", "json", "--output", output.path]).run()
				}
			}
			#expect(!FileManager.default.fileExists(atPath: output.path))
		}
	}

	private func withWorkspace(media: Bool, _ body: (URL, String) throws -> Void) throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let root = directory.appendingPathComponent("Native")
		let store = root.appendingPathComponent("DocumentStore")
		try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		try Data("sqlite-v1".utf8).write(to: store.appendingPathComponent("workspace-storage-v1"))
		try Data(UUID().uuidString.utf8).write(to: store.appendingPathComponent("workspace-id"))
		let prefix = media ? "MediaIdentity/Presentation" : "Presentation"
		let snapshot = try Data(contentsOf: fixtures.appendingPathComponent("Native/\(prefix).loro"))
		let vector = try Data(contentsOf: fixtures.appendingPathComponent("Native/\(prefix).\(media ? "vector" : "version-vector")"))
		let id = media ? "12080506-ffda-5a60-9e6d-4c99a9a8f82f" : "48e32307-7a5a-56cc-8cca-0bc82d6079c1"
		var pointer: OpaquePointer?
		#expect(sqlite3_open(store.appendingPathComponent("workspace-v1.sqlite3").path, &pointer) == SQLITE_OK)
		let database = try #require(pointer)
		do {
			defer { sqlite3_close(database) }
			let sql = try String(contentsOf: fixtures.appendingPathComponent("Native/schema-9.sql"), encoding: .utf8) + """
			INSERT INTO workspace_streams(document_id,scope,location_type,kind,core_path,availability,snapshot,version_vector,sha256,byte_count,updated_at_ms,last_shared_version_vector_absence_reason,core_path_key)
			VALUES(X'\(id.replacingOccurrences(of: "-", with: ""))',0,1,'Presentation','Owned/Probe',0,X'\(hex(snapshot))',X'\(hex(vector))',X'\(hex(Data(SHA256.hash(data: snapshot))))',\(snapshot.count),0,2,'owned/probe');
			"""
			let result = sqlite3_exec(database, sql, nil, nil, nil)
			guard result == SQLITE_OK else { throw NativeWorkspaceError.database(String(cString: sqlite3_errmsg(database))) }
		}
		try body(root, id)
	}

	private func hex(_ data: Data) -> String {
		data.map { String(format: "%02x", $0) }.joined()
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22")
	}
}
