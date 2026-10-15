import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native group and arrangement operations")
struct NativeGroupEditingTests {
	@Test func nativeAuthoredRepeatedArrangementAndRenameAreIndependentEvidence() throws {
		let before = try stream("native-repeated").presentationLayout()
		let after = try stream("native-renamed").presentationLayout()
		#expect(before.groups[0].name == "Slides")
		#expect(after.groups[0].name == "Native Verse")
		#expect(before.groups[0].id == after.groups[0].id)
		#expect(before.groups[0].nodeID == after.groups[0].nodeID)
		#expect(before.arrangements == after.arrangements)
		#expect(before.arrangements[0].groupIDs == [before.groups[0].id, before.groups[0].id])
		#expect(try before.orderedCueIDs(arrangement: before.arrangements[0].id) == before.orderedCueIDs() + before.orderedCueIDs())
	}

	@Test func renameChangesOnlyTheExistingGroupName() throws {
		let source = try stream("native-renamed")
		let before = try source.presentationLayout()
		let group = before.groups[0]
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .cueGroupName(group.id, "CLI Verse — café")))
		let updated = reloaded(source, patch)
		let after = try updated.presentationLayout()
		#expect(after.groups[0].name == "CLI Verse — café")
		#expect(after.cues == before.cues)
		#expect(after.arrangements == before.arrangements)
		#expect(after.master == before.master)
		#expect(after.placements[0].children == before.placements[0].children)
		var attributes = try group.attributes.object(at: "/group")
		attributes["name"] = .string("CLI Verse — café")
		#expect(after.groups[0].attributes == .map(attributes))
		#expect(after.groups[0].nodeID == group.nodeID)
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: .cueGroupName(group.id, "CLI Verse — café")) == nil)
		try assertReplay(source, patch: patch)
	}

	@Test(arguments: [0, 1, 3]) func sequenceRetainsDuplicatesAndChangesOnlyArrangementOccurrences(count: Int) throws {
		let source = try stream("native-repeated")
		let before = try source.presentationLayout()
		let arrangement = before.arrangements[0]
		let ids = Array(repeating: before.groups[0].id, count: count)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .arrangementGroups(arrangement.id, ids)))
		let updated = reloaded(source, patch)
		let after = try updated.presentationLayout()
		#expect(after.arrangements[0].groupIDs == ids)
		#expect(after.arrangements[0].id == arrangement.id)
		#expect(after.arrangements[0].name == arrangement.name)
		#expect(after.cues == before.cues)
		#expect(after.placements == before.placements)
		#expect(after.selectedArrangementID == before.selectedArrangementID)
		#expect(try after.orderedCueIDs(arrangement: arrangement.id).count == count * 3)
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: .arrangementGroups(arrangement.id, ids)) == nil)
		try assertReplay(source, patch: patch)
	}

	@Test func nativeRestartExportAndContinuedEditingRetainBothOperations() throws {
		let before = try stream("native-renamed")
		let renamed = try stream("cli-renamed")
		let cli = try stream("cli-after")
		let continued = try stream("native-continued")
		let initial = try before.presentationLayout()
		let result = try cli.presentationLayout()
		#expect(try renamed.presentationLayout().arrangements == initial.arrangements)
		#expect(result.groups[0].name == "CLI Verse — café")
		#expect(result.arrangements[0].groupIDs == Array(repeating: initial.groups[0].id, count: 3))
		#expect(result.cues == initial.cues)
		#expect(try continued.presentationLayout() == result)
		#expect(try continued.protobufProjection().presentation().notes == "Native continuation after CLI group and arrangement edits")
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeReexport.pro")))
		let projected = try cli.protobufProjection().presentation()
		#expect(exported.cueGroups == projected.cueGroups)
		#expect(exported.arrangements == projected.arrangements)
		#expect(exported.selectedArrangement == projected.selectedArrangement)
		#expect(Set(exported.cues.map(\.uuid.string)) == Set(projected.cues.map(\.uuid.string)))
		let replay = LoroDoc()
		_ = try replay.import(bytes: #require(before.snapshot))
		let native = LoroDoc()
		_ = try native.import(bytes: #require(continued.snapshot))
		_ = try replay.import(bytes: native.exportUpdates(vv: replay.oplogVv()))
		#expect(replay.oplogVv().eq(other: native.oplogVv()))
		#expect(try NativeWorkspaceValue(replay.getDeepValue()) == continued.decodedValue())
	}

	@Test func sequenceReordersUsingOneMoveOfAnExistingOccurrence() throws {
		let source = try stream("native-repeated")
		let group = try source.presentationLayout().groups[0].id
		let other = UUID()
		let document = LoroDoc()
		_ = try document.import(bytes: #require(source.snapshot))
		let root = document.getMap(id: "root")
		let list = try #require(root.get(key: "arrangements")?.asLoroMovableList()?.get(index: 0)?.asLoroMap()?.get(key: "group_identifiers_v2")?.asLoroMovableList())
		try list.insert(pos: 1, v: other.uuidString)
		document.commit()
		let version = document.oplogVv()
		let container = list.id()
		try NativeStructuralEditing.setGroups([group, group, other], replacing: [group, other, group], at: 0, root: root)
		document.commit()
		#expect(list.id() == container)
		#expect(try NativeWorkspaceValue(list.getDeepValue()) == .list([.string(group.uuidString), .string(group.uuidString), .string(other.uuidString)]))
		let json = document.exportJsonUpdates(startVv: version, endVv: document.oplogVv())
		let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
		let changes = try #require(object["changes"] as? [[String: Any]])
		let operations = changes.flatMap { $0["ops"] as? [[String: Any]] ?? [] }
		#expect(operations.count == 1)
		let content = try #require(operations.first?["content"] as? [String: Any])
		#expect(content["type"] as? String == "move")
		#expect(content["from"] as? Int == 2)
		#expect(content["to"] as? Int == 1)
		#expect(content["elem_id"] as? String != nil)
	}

	@Test(arguments: [true, false]) func editsRetainUnknownContainerIdentityAndValues(rename: Bool) throws {
		let source = try stream("native-renamed")
		let layout = try source.presentationLayout()
		let document = LoroDoc()
		_ = try document.import(bytes: #require(source.snapshot))
		let root = document.getMap(id: "root")
		let tree = try #require(root.get(key: "cue_group_placements")?.asLoroTree())
		let group = try #require(try tree.getMeta(target: NativeStructuralEditing.treeID(layout.groups[0].nodeID)).get(key: "Kind")?.asLoroMap()?.get(key: "group")?.asLoroMap())
		let arrangement = try #require(root.get(key: "arrangements")?.asLoroMovableList()?.get(index: 0)?.asLoroMap())
		let targets = [root, group, arrangement]
		let future = try targets.map { map in
			let child = try map.insertContainer(key: "future_container", child: LoroMap())
			try child.insert(key: "opaque", v: LoroValue.binary(value: Data([0, 128, 255])))
			return child
		}
		let augmented = try reloaded(source, snapshot: document.exportSnapshot(), vector: document.stateVv().encode())
		let edit: NativePresentationEdit = rename ? .cueGroupName(layout.groups[0].id, "Future preserved") : .arrangementGroups(layout.arrangements[0].id, [])
		let patch = try #require(try NativeLocalPatch.prepare(stream: augmented, edit: edit))
		let updated = LoroDoc()
		_ = try updated.import(bytes: patch.snapshot)
		for container in future {
			let retained = updated.getMap(id: container.id())
			#expect(retained.id() == container.id())
			#expect(retained.getDeepValue() == container.getDeepValue())
		}
	}

	@Test func unresolvedOrEmptyNamesAndParallelLegacySequencesFail() throws {
		let source = try stream("native-repeated")
		let layout = try source.presentationLayout()
		let group = layout.groups[0].id
		let arrangement = layout.arrangements[0].id
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .arrangementGroups(arrangement, [group, group])) == nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .cueGroupName(group, "")) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .cueGroupName(UUID(), "Missing")) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .arrangementGroups(UUID(), [])) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .arrangementGroups(arrangement, [UUID()])) }
		let document = LoroDoc()
		_ = try document.import(bytes: #require(source.snapshot))
		let map = try #require(document.getMap(id: "root").get(key: "arrangements")?.asLoroMovableList()?.get(index: 0)?.asLoroMap())
		try map.insert(key: "group_identifiers", v: LoroValue.list(value: [.string(value: group.uuidString), .string(value: group.uuidString)]))
		let mixed = try reloaded(source, snapshot: document.exportSnapshot(), vector: document.stateVv().encode())
		#expect(try mixed.presentationLayout().arrangements == layout.arrangements)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: mixed, edit: .arrangementGroups(arrangement, [group])) }
	}

	@Test func parallelLegacyGroupOrderCannotBecomeStaleAfterMove() throws {
		let source = try stream("native-repeated")
		let layout = try source.presentationLayout()
		let group = layout.groups[0]
		let document = LoroDoc()
		_ = try document.import(bytes: #require(source.snapshot))
		let legacy = LoroValue.map(value: ["group": .map(value: ["uuid": .string(value: group.id.uuidString)]), "cue_identifiers_v2": .list(value: group.cueIDs.map { .string(value: $0.uuidString) })])
		try document.getMap(id: "root").insert(key: "cue_groups", v: LoroValue.list(value: [legacy]))
		let mixed = try reloaded(source, snapshot: document.exportSnapshot(), vector: document.stateVv().encode())
		#expect(try mixed.presentationLayout().groups == layout.groups)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: mixed, edit: .moveCue(group.cueIDs[0], after: group.cueIDs[2])) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: mixed, edit: .cueGroupName(group.id, "New")) }
	}

	private func assertReplay(_ source: NativeWorkspaceStream, patch: NativeLocalPatch) throws {
		let document = LoroDoc()
		_ = try document.import(bytes: #require(source.snapshot))
		_ = try document.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(document.getDeepValue()) == reloaded(source, patch).decodedValue())
	}

	private func reloaded(_ source: NativeWorkspaceStream, _ patch: NativeLocalPatch) -> NativeWorkspaceStream {
		reloaded(source, snapshot: patch.snapshot, vector: patch.versionVector)
	}

	private func reloaded(_ source: NativeWorkspaceStream, snapshot: Data, vector: Data) -> NativeWorkspaceStream {
		.init(identity: source.identity, snapshot: snapshot, versionVector: vector, lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/Groups")
	}

	private func stream(_ name: String) throws -> NativeWorkspaceStream {
		let bytes = try Data(contentsOf: fixtures.appendingPathComponent("\(name).loro"))
		let vector = try Data(contentsOf: fixtures.appendingPathComponent("\(name).vector"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(bytes.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: bytes, versionVector: vector, lastSharedVersionVector: nil)
	}
}
