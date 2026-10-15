import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native arrangement creation and duplication")
struct NativeArrangementLifecycleTests {
	@Test func creationMatchesTheIndependentNativeOperationExactly() throws {
		let source = try stream("native-before")
		let native = try stream("native-created")
		let created = try #require(native.presentationLayout().arrangements.last)
		let edit = NativePresentationEdit.createArrangement(id: created.id, name: created.name, groups: created.groupIDs, select: true)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: edit))
		let updated = try stream("native-before", patch: patch)
		#expect(try updated.decodedValue() == native.decodedValue())
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: edit) == nil)
		try requireUpdateReplays(patch, source: source, result: updated)
	}

	@Test func duplicationAppendsAndSelectsAnIndependentCopyWithTheSameRepeatedSequence() throws {
		let source = try stream("native-deleted")
		let native = try stream("native-duplicated")
		let original = try #require(source.presentationLayout().arrangements.first)
		let copy = try #require(native.presentationLayout().arrangements.last)
		let edit = NativePresentationEdit.duplicateArrangement(original.id, newID: copy.id, name: copy.name, select: true)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: edit))
		let updated = try stream("native-deleted", patch: patch)
		#expect(try updated.decodedValue() == native.decodedValue())
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: edit) == nil)
		try requireUpdateReplays(patch, source: source, result: updated)
	}

	@Test func emptyAndRepeatedCreationCanKeepSelectionAndParticipateInAnOrderedBatch() throws {
		let source = try stream("native-created")
		let before = try source.presentationLayout()
		let group = try #require(before.groups.first?.id)
		let empty = UUID(), repeated = UUID()
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edits: [
			.createArrangement(id: empty, name: "Empty", groups: [], select: false),
			.createArrangement(id: repeated, name: "Repeated", groups: [group, group], select: false),
			.arrangementName(empty, "Empty renamed"),
		]))
		let updated = try stream("native-created", patch: patch)
		let after = try updated.presentationLayout()
		#expect(after.selectedArrangementID == before.selectedArrangementID)
		#expect(after.arrangements.prefix(before.arrangements.count).elementsEqual(before.arrangements))
		#expect(after.arrangements.suffix(2).map(\.groupIDs) == [[], [group, group]])
		#expect(after.cues == before.cues && after.placements == before.placements)
		#expect(try updated.protobufProjection().presentation().arrangements.count == before.arrangements.count + 2)
	}

	@Test func collidingIdentitiesInvalidGroupsAndUnknownSourceFieldsCannotPublishACopy() throws {
		let source = try stream("native-before")
		let arrangement = try #require(source.presentationLayout().arrangements.first)
		let invalid: [NativePresentationEdit] = [
			.createArrangement(id: UUID(), name: "", groups: [], select: false),
			.createArrangement(id: UUID(), name: "Invalid", groups: [UUID()], select: false),
			.createArrangement(id: arrangement.id, name: "Collision", groups: arrangement.groupIDs, select: false),
			.duplicateArrangement(UUID(), newID: UUID(), name: "Missing", select: true),
			.duplicateArrangement(arrangement.id, newID: arrangement.id, name: "Same identity", select: true),
		]
		for edit in invalid {
			#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: edit) }
		}
		let document = LoroDoc(); _ = try document.import(bytes: #require(source.snapshot))
		let root = document.getMap(id: "root")
		let list = try #require(root.get(key: "arrangements")?.asLoroMovableList())
		let stored = try #require(list.get(index: 0)?.asLoroMap())
		let future = try stored.insertContainer(key: "future_reference_policy", child: LoroMap())
		try future.insert(key: "opaque", v: arrangement.id.uuidString)
		let augmented = try NativeWorkspaceStream(identity: source.identity, snapshot: document.exportSnapshot(), versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: augmented, edit: .duplicateArrangement(arrangement.id, newID: UUID(), name: "Unknown policy", select: false)) }
		let creation = try #require(try NativeLocalPatch.prepare(stream: augmented, edit: .createArrangement(id: UUID(), name: "Independent", groups: [], select: false)))
		let created = try stream("native-before", patch: creation)
		let originalValue = try augmented.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root").required("arrangements", at: "/root").array(at: "/arrangements")[0]
		let retained = try created.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root").required("arrangements", at: "/root").array(at: "/arrangements")[0]
		#expect(retained == originalValue)
	}

	@Test func productionBatchReopensByteIdenticallyAndSupportsNativeEmptyArrangementDuplication() throws {
		let before = try stream("cli-before"), cli = try stream("cli-after"), opened = try stream("native-open")
		#expect(cli.snapshot == opened.snapshot && cli.versionVector == opened.versionVector)
		let original = try before.presentationLayout(), result = try cli.presentationLayout()
		let group = try #require(original.groups.first?.id)
		#expect(result.arrangements.count == original.arrangements.count + 3)
		#expect(result.arrangements.prefix(original.arrangements.count).elementsEqual(original.arrangements))
		#expect(result.arrangements.suffix(3).map(\.groupIDs) == [[group, group], [], [group, group]])
		#expect(result.selectedArrangementID == result.arrangements.last?.id)
		#expect(result.cues == original.cues && result.placements == original.placements)
		let empty = try stream("native-empty-selected").presentationLayout()
		#expect(empty.selectedArrangementID == result.arrangements[4].id)
		#expect(try empty.orderedCueIDs(arrangement: empty.selectedArrangementID).isEmpty)
		let continued = try stream("native-continued")
		let native = try continued.presentationLayout()
		#expect(native.arrangements.prefix(result.arrangements.count).elementsEqual(result.arrangements))
		#expect(native.arrangements.last?.groupIDs.isEmpty == true)
		#expect(native.arrangements.last?.name == "CLI Empty Arrangement 1")
		#expect(native.selectedArrangementID == native.arrangements.last?.id)
		let history = LoroDoc(); _ = try history.import(bytes: #require(cli.snapshot))
		let nativeHistory = LoroDoc(); _ = try nativeHistory.import(bytes: #require(continued.snapshot))
		_ = try history.import(bytes: nativeHistory.exportUpdates(vv: history.oplogVv()))
		#expect(try NativeWorkspaceValue(history.getDeepValue()) == continued.decodedValue())
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeReexport.pro")))
		let projected = try continued.protobufProjection().presentation()
		#expect(exported.arrangements == projected.arrangements)
		#expect(exported.selectedArrangement == projected.selectedArrangement)
	}

	@Test func independentNativeDeletionClearsSelectionAndRestoresTheOriginalDeepState() throws {
		// Native evidence only: deletion is not exposed until cross-document
		// arrangement-reference handling has its own qualified adapter.
		#expect(try stream("native-created").presentationLayout().selectedArrangementID != nil)
		#expect(try stream("native-deleted").decodedValue() == stream("native-before").decodedValue())
	}

	private func requireUpdateReplays(_ patch: NativeLocalPatch, source: NativeWorkspaceStream, result: NativeWorkspaceStream) throws {
		let document = LoroDoc(); _ = try document.import(bytes: #require(source.snapshot)); _ = try document.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(document.getDeepValue()) == result.decodedValue())
	}

	private func stream(_ name: String, patch: NativeLocalPatch? = nil) throws -> NativeWorkspaceStream {
		let base = fixtures.appendingPathComponent(name)
		let data = try patch?.snapshot ?? Data(contentsOf: base.appendingPathExtension("loro"))
		let vector = try patch?.versionVector ?? Data(contentsOf: base.appendingPathExtension("vector"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/ArrangementLifecycle")
	}
}
