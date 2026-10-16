import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native arrangement selection and names")
struct NativeArrangementEditingTests {
	@Test func masterSelectionMatchesTheIndependentNativeEditExactly() throws {
		let source = try stream("native-before")
		let id = try #require(source.presentationLayout().selectedArrangementID)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .selectedArrangement(nil)))
		let master = try stream("native-before", patch: patch)
		#expect(try master.decodedValue() == stream("native-master").decodedValue())
		#expect(try NativeLocalPatch.prepare(stream: master, edit: .selectedArrangement(nil)) == nil)
		let selected = try #require(try NativeLocalPatch.prepare(stream: master, edit: .selectedArrangement(id)))
		#expect(try stream("native-before", patch: selected).decodedValue() == source.decodedValue())
	}

	@Test func nameEditMatchesTheNativeManagerAndRetainsEveryOtherField() throws {
		let source = try stream("native-master")
		let id = try source.presentationLayout().arrangements[0].id
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .arrangementName(id, "Native Arrangement Control")))
		let updated = try stream("native-master", patch: patch)
		let before = try root(source), after = try root(updated), native = try root(stream("native-duplicated"))
		let arrays = try after.required("arrangements", at: "/root").array(at: "/root/arrangements")
		#expect(try arrays[0] == native.required("arrangements", at: "/root").array(at: "/root/arrangements")[0])
		#expect(after.filter { $0.key != "arrangements" } == before.filter { $0.key != "arrangements" })
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: .arrangementName(id, "Native Arrangement Control")) == nil)
		let replay = LoroDoc()
		_ = try replay.import(bytes: #require(source.snapshot))
		_ = try replay.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(replay.getDeepValue()) == updated.decodedValue())
	}

	@Test func batchCanRenameAndSelectAnExistingArrangementWithoutChangingSequences() throws {
		let source = try stream("native-duplicated")
		let before = try source.presentationLayout()
		let id = before.arrangements[0].id
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edits: [.arrangementName(id, "CLI Arrangement — café"), .selectedArrangement(id)]))
		let updated = try stream("native-duplicated", patch: patch)
		let after = try updated.presentationLayout()
		#expect(after.selectedArrangementID == id)
		#expect(after.arrangements[0].name == "CLI Arrangement — café")
		#expect(after.arrangements.map(\.groupIDs) == before.arrangements.map(\.groupIDs))
		#expect(after.arrangements.map(\.id) == before.arrangements.map(\.id))
		#expect(after.arrangements[1] == before.arrangements[1])
		#expect(after.placements == before.placements)
		#expect(after.cues == before.cues)
		#expect(try NativeLocalPatch.prepare(stream: updated, edits: [.arrangementName(id, "CLI Arrangement — café"), .selectedArrangement(id)]) == nil)
	}

	@Test func invalidSelectionAndNamesFailBeforePublication() throws {
		let source = try stream("native-before")
		let id = try source.presentationLayout().arrangements[0].id
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .selectedArrangement(UUID())) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .arrangementName(UUID(), "Unknown")) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .arrangementName(id, "")) }
	}

	@Test func metadataEditsPreserveUnknownContainersAndStoredUUIDSpelling() throws {
		let source = try stream("native-master")
		let document = LoroDoc()
		_ = try document.import(bytes: #require(source.snapshot))
		let root = document.getMap(id: "root")
		let list = try #require(root.get(key: "arrangements")?.asLoroMovableList())
		let arrangement = try #require(list.get(index: 0)?.asLoroMap())
		let id = try source.presentationLayout().arrangements[0].id
		try arrangement.insert(key: "uuid", v: id.uuidString.lowercased())
		let future = try arrangement.insertContainer(key: "future_policy", child: LoroMap())
		try future.insert(key: "opaque_reference", v: "preserved")
		let augmented = try NativeWorkspaceStream(identity: source.identity, snapshot: document.exportSnapshot(), versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
		let patch = try #require(try NativeLocalPatch.prepare(stream: augmented, edits: [.arrangementName(id, "Future policy"), .selectedArrangement(id)]))
		let updated = LoroDoc()
		_ = try updated.import(bytes: patch.snapshot)
		let updatedRoot = updated.getMap(id: "root")
		let updatedList = try #require(updatedRoot.get(key: "arrangements")?.asLoroMovableList())
		let updatedArrangement = try #require(updatedList.get(index: 0)?.asLoroMap())
		let updatedFuture = try #require(updatedArrangement.get(key: "future_policy")?.asLoroMap())
		#expect(list.id() == updatedList.id())
		#expect(arrangement.id() == updatedArrangement.id())
		#expect(future.id() == updatedFuture.id())
		#expect(updatedFuture.get(key: "opaque_reference")?.asValue() == .string(value: "preserved"))
		#expect(updatedRoot.get(key: "selected_arrangement")?.asValue() == .string(value: id.uuidString.lowercased()))
	}

	@Test func productionBatchReopensWithoutRepairAndSupportsNativeContinuation() throws {
		let before = try stream("cli-before")
		let cli = try stream("cli-after")
		let opened = try stream("native-open")
		let continued = try stream("native-continued")
		#expect(cli.snapshot == opened.snapshot)
		#expect(cli.versionVector == opened.versionVector)
		let original = try before.presentationLayout(), result = try cli.presentationLayout()
		#expect(result.selectedArrangementID == original.arrangements[0].id)
		#expect(result.arrangements[0].name == "CLI Arrangement — café")
		#expect(result.arrangements[1] == original.arrangements[1])
		#expect(try continued.presentationLayout().selectedArrangementID == nil)
		#expect(try continued.presentationLayout().arrangements == result.arrangements)
		let history = LoroDoc()
		_ = try history.import(bytes: #require(cli.snapshot))
		let native = LoroDoc()
		_ = try native.import(bytes: #require(continued.snapshot))
		_ = try history.import(bytes: native.exportUpdates(vv: history.oplogVv()))
		#expect(try NativeWorkspaceValue(history.getDeepValue()) == continued.decodedValue())
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeReexport.pro")))
		let projected = try continued.protobufProjection().presentation()
		#expect(exported.arrangements == projected.arrangements)
		#expect(exported.hasSelectedArrangement == projected.hasSelectedArrangement)
	}

	private func root(_ stream: NativeWorkspaceStream) throws -> [String: NativeWorkspaceValue] {
		try stream.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root")
	}

	private func stream(_ name: String, patch: NativeLocalPatch? = nil) throws -> NativeWorkspaceStream {
		let base = fixtures.appendingPathComponent(name)
		let bytes = try patch?.snapshot ?? Data(contentsOf: base.appendingPathExtension("loro"))
		let vector = try patch?.versionVector ?? Data(contentsOf: base.appendingPathExtension("vector"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(bytes.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: bytes, versionVector: vector, lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/Arrangements")
	}
}
