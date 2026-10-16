import CryptoKit
import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native local persistence operations")
struct NativePersistenceTests {
	@Test func nativeRestartAndContinuedEditRetainTheCLIHistory() throws {
		let directory = fixtures.deletingLastPathComponent().appendingPathComponent("LocalCommit")
		func read(_ name: String) throws -> LoroDoc {
			let doc = LoroDoc()
			_ = try doc.import(bytes: Data(contentsOf: directory.appendingPathComponent("\(name).loro")))
			#expect(try doc.oplogVv().eq(other: VersionVector.decode(bytes: Data(contentsOf: directory.appendingPathComponent("\(name).vector")))))
			return doc
		}
		let before = try read("before")
		let cli = try read("cli-after")
		let native = try read("native-after")
		let update = try cli.exportUpdates(vv: before.oplogVv())
		let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("receipt.json"))) as? [String: Any]
		#expect(hex(Data(SHA256.hash(data: update))) == receipt?["payload_fingerprint"] as? String)
		_ = try before.import(bytes: update)
		#expect(before.oplogVv().eq(other: cli.oplogVv()))
		let continuation = try native.exportUpdates(vv: cli.oplogVv())
		_ = try cli.import(bytes: continuation)
		#expect(cli.oplogVv().eq(other: native.oplogVv()))
		#expect(try NativeWorkspaceValue(cli.getDeepValue()) == NativeWorkspaceValue(native.getDeepValue()))
		let root = try NativeWorkspaceValue(native.getDeepValue()).object(at: "/").required("root", at: "/").object(at: "/root")
		#expect(try root.required("ccli", at: "/root").object(at: "/root/ccli")["song_title"] == .string("Native Continued Edit After CLI"))
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: directory.appendingPathComponent("NativeReexport.pro")))
		#expect(exported.ccli.songTitle == "Native Continued Edit After CLI")
		#expect(exported.cues.count == 1)
	}

	@Test func nativeReceiptFingerprintsTheExactLoroUpdate() throws {
		let before = try document("before")
		let after = try document("after")
		let patch = try Data(contentsOf: fixtures.appendingPathComponent("native-edit.loro"))
		let expected = "76a4d85b8b021606e80da9b1d138975546fc9e1734779229510ce3c7e03276a8"
		#expect(hex(Data(SHA256.hash(data: patch))) == expected)
		let exported = try after.exportUpdates(vv: before.oplogVv())
		#expect(hex(Data(SHA256.hash(data: exported))) == expected)
		_ = try before.import(bytes: patch)
		#expect(try NativeWorkspaceValue(before.getDeepValue()) == NativeWorkspaceValue(after.getDeepValue()))
		#expect(before.oplogVv().eq(other: after.oplogVv()))
		// The update is idempotent; a retry cannot duplicate native history.
		_ = try before.import(bytes: patch)
		#expect(before.oplogVv().eq(other: after.oplogVv()))
	}

	@Test func preparedFieldEditPreservesEveryUnrelatedValueAndOriginalHistory() throws {
		let source = try stream()
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .copyrightTitle("CLI Local Acceptance")))
		let original = try source.decodedValue().object(at: "/")
		let updated = LoroDoc()
		_ = try updated.import(bytes: patch.snapshot)
		var expectedRoot = try original.required("root", at: "/").object(at: "/root")
		var ccli = try expectedRoot.required("ccli", at: "/root").object(at: "/root/ccli")
		ccli["song_title"] = .string("CLI Local Acceptance")
		expectedRoot["ccli"] = .map(ccli)
		var expected = original
		expected["root"] = .map(expectedRoot)
		#expect(try NativeWorkspaceValue(updated.getDeepValue()) == .map(expected))
		let replayed = try document("before")
		_ = try replayed.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(replayed.getDeepValue()) == .map(expected))
		#expect(replayed.oplogVv().eq(other: updated.oplogVv()))
		#expect(patch.originalSnapshot == source.snapshot)
		#expect(patch.originalVersionVector == source.versionVector)
		#expect(patch.sha256 == Data(SHA256.hash(data: patch.snapshot)))
		#expect(patch.payloadFingerprint == Data(SHA256.hash(data: patch.update)))
	}

	@Test func noOpProducesNoPatchOrHistoryChange() throws {
		let source = try stream()
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .copyrightTitle("Native Acceptance 22")) == nil)
	}

	private func document(_ name: String) throws -> LoroDoc {
		let document = LoroDoc()
		_ = try document.import(bytes: Data(contentsOf: fixtures.appendingPathComponent("\(name).loro")))
		#expect(try document.oplogVv().eq(other: VersionVector.decode(bytes: Data(contentsOf: fixtures.appendingPathComponent("\(name).vector")))))
		return document
	}

	private func stream() throws -> NativeWorkspaceStream {
		let snapshot = try Data(contentsOf: fixtures.appendingPathComponent("before.loro"))
		let vector = try Data(contentsOf: fixtures.appendingPathComponent("before.vector"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "4eb485bd-667d-56db-9525-779a88cfce0f")), scope: .shared, kind: "Presentation", corePath: "MISC/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(snapshot.count), sha256: hex(Data(SHA256.hash(data: snapshot))), updatedAtMilliseconds: 0), snapshot: snapshot, versionVector: vector, lastSharedVersionVector: nil)
	}

	private func hex(_ data: Data) -> String {
		data.map { String(format: "%02x", $0) }.joined()
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/Persistence")
	}
}
