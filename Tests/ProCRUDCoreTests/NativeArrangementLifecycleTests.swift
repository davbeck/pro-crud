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
		// Independent native control for selected-arrangement removal.
		#expect(try stream("native-created").presentationLayout().selectedArrangementID != nil)
		#expect(try stream("native-deleted").decodedValue() == stream("native-before").decodedValue())
	}

	@Test func deletionMatchesNativeAndRejectsStoredDocumentActionLinks() throws {
		let source = try stream("native-created")
		let arrangement = try #require(source.presentationLayout().arrangements.last)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .removeArrangement(arrangement.id)))
		#expect(try stream("native-created", patch: patch).decodedValue() == stream("native-deleted").decodedValue())
		#expect(try NativeLocalWorkspaceWriter.prepare([.init(documentID: source.identity.documentID, edit: .removeArrangement(arrangement.id))], in: snapshot([source])).count == 1)
		let macro = try macroReference(target: source.identity.documentID, arrangement: arrangement.id)
		let linked = snapshot([source, macro])
		let inventory = try NativeArrangementReferenceInventory(snapshot: linked)
		#expect(inventory.uninspected.isEmpty && inventory.references.count == 1)
		#expect(inventory.references.first?.role == .documentAction)
		#expect(inventory.references.first?.targetDocumentID == nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalWorkspaceWriter.prepare([.init(documentID: source.identity.documentID, edit: .removeArrangement(arrangement.id))], in: linked) }
		#expect(throws: NativeSemanticError.self) { try NativeArrangementDeletion.validate([patch], in: linked) }
		#expect(try NativeLocalWorkspaceWriter.prepare([.init(documentID: source.identity.documentID, edit: .copyrightTitle("Unrelated metadata"))], in: linked).count == 1)
	}

	@Test func sameArrangementUUIDInAnotherPresentationDoesNotTurnItsLinksIntoLocalReferences() throws {
		let source = try stream("native-created")
		let arrangement = try #require(source.presentationLayout().arrangements.last)
		let copy = LoroDoc(); _ = try copy.import(bytes: #require(source.snapshot))
		let otherID = UUID(); try copy.getMap(id: "root").insert(key: "uuid", v: otherID.uuidString)
		var identity = source.identity; identity.documentID = otherID; identity.corePath = "Default/OtherOwnedPresentation"
		let other = try NativeWorkspaceStream(identity: identity, snapshot: copy.exportSnapshot(), versionVector: copy.stateVv().encode(), lastSharedVersionVector: nil)
		let playlist = try playlistReference(arrangement: arrangement.id, name: nil, path: "Libraries/Default/OtherOwnedPresentation.pro")
		#expect(try NativeLocalWorkspaceWriter.prepare([.init(documentID: source.identity.documentID, edit: .removeArrangement(arrangement.id))], in: snapshot([source, other, playlist])).count == 1)
	}

	@Test func playlistUUIDNameOnlyAndUnresolvedLinksPreventDeletion() throws {
		let source = try stream("native-created")
		let arrangement = try #require(source.presentationLayout().arrangements.last)
		for (id, name, path): (UUID?, String?, String) in [(arrangement.id, nil, "Libraries/Default/ProCRUDTarget22Acceptance.pro"), (nil, arrangement.name, "Libraries/Default/ProCRUDTarget22Acceptance.pro"), (arrangement.id, nil, "Libraries/Missing/Unresolved.pro")] {
			let playlist = try playlistReference(arrangement: id, name: name, path: path)
			let linked = snapshot([source, playlist])
			let inventory = try NativeArrangementReferenceInventory(snapshot: linked)
			#expect(inventory.uninspected.isEmpty && inventory.references.count == 1)
			#expect(inventory.references.first?.role == .playlist)
			#expect(throws: NativeSemanticError.self) { try NativeLocalWorkspaceWriter.prepare([.init(documentID: source.identity.documentID, edit: .removeArrangement(arrangement.id))], in: linked) }
		}
	}

	@Test func unavailableOrUnknownReferenceScopesBlockDeletionAndRetainMetadataEditing() throws {
		let source = try stream("native-created")
		let arrangement = try #require(source.presentationLayout().arrangements.last)
		var identity = source.identity; identity.documentID = UUID(); identity.kind = "FutureRoot"
		let unknown = NativeWorkspaceStream(identity: identity, snapshot: source.snapshot, versionVector: source.versionVector, lastSharedVersionVector: nil)
		identity.kind = "Macros"; identity.availability = .unavailable
		let unavailable = NativeWorkspaceStream(identity: identity, snapshot: nil, versionVector: nil, lastSharedVersionVector: nil)
		for stream in [unknown, unavailable] {
			let state = snapshot([source, stream])
			#expect(try NativeArrangementReferenceInventory(snapshot: state).uninspected.count == 1)
			#expect(throws: NativeSemanticError.self) { try NativeLocalWorkspaceWriter.prepare([.init(documentID: source.identity.documentID, edit: .removeArrangement(arrangement.id))], in: state) }
			#expect(try NativeLocalWorkspaceWriter.prepare([.init(documentID: source.identity.documentID, edit: .copyrightTitle("Preserved unknown references"))], in: state).count == 1)
		}
	}

	private func snapshot(_ streams: [NativeWorkspaceStream]) -> NativeWorkspaceSnapshot {
		.init(root: fixtures, workspaceID: UUID(), metadata: [:], streams: streams)
	}

	private func macroReference(target: UUID, arrangement: UUID) throws -> NativeWorkspaceStream {
		let document = LoroDoc()
		let action: LoroValue = .map(value: ["uuid": .string(value: UUID().uuidString), "type": .i64(value: 14), "ActionTypeData": .map(value: ["__tag": .string(value: "presentation_document"), "presentation_document": .map(value: ["identification": .map(value: ["parameter_uuid": .string(value: target.uuidString)]), "selected_arrangement": .string(value: arrangement.uuidString)])])])
		try document.getMap(id: "root").insert(key: "macros", v: LoroValue.list(value: [.map(value: ["uuid": .string(value: UUID().uuidString), "name": .string(value: "Owned arrangement reference"), "actions": .list(value: [action])])]))
		return try referenceStream(document, kind: "Macros")
	}

	private func playlistReference(arrangement: UUID?, name: String?, path: String) throws -> NativeWorkspaceStream {
		let document = LoroDoc(), root = document.getMap(id: "root")
		try root.insert(key: "type", v: 0)
		let tree = try root.insertContainer(key: "playlists", child: LoroTree())
		let playlist = try tree.create(parent: .root), item = try tree.create(parent: .node(id: playlist))
		func metadata(_ node: TreeId, kind: String, value: LoroValue) throws {
			let map = try tree.getMeta(target: node)
			try map.insert(key: "uuid", v: UUID().uuidString); try map.insert(key: "name", v: "Owned reference node")
			try map.insert(key: "Kind", v: LoroValue.map(value: ["__tag": .string(value: kind), kind: value]))
		}
		try metadata(playlist, kind: "playlist", value: .map(value: [:]))
		var link: [String: LoroValue] = ["document_path": .map(value: ["RelativeFilePath": .map(value: ["__tag": .string(value: "local"), "local": .map(value: ["root": .i64(value: 10), "path": .string(value: path)])])])]
		if let arrangement {
			link["arrangement"] = .string(value: arrangement.uuidString)
		}
		if let name {
			link["arrangement_name"] = .string(value: name)
		}
		try metadata(item, kind: "item", value: .map(value: ["ItemType": .map(value: ["__tag": .string(value: "presentation"), "presentation": .map(value: link)])]))
		_ = try root.insertContainer(key: "live_video_playlist_nodes", child: LoroTree())
		return try referenceStream(document, kind: "PlaylistLibrary")
	}

	private func referenceStream(_ document: LoroDoc, kind: String) throws -> NativeWorkspaceStream {
		document.commit(); let data = try document.exportSnapshot()
		return .init(identity: .init(documentID: UUID(), scope: .shared, kind: kind, corePath: nil, availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
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
