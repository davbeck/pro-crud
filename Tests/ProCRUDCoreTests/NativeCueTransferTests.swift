import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native cue ownership transfers")
struct NativeCueTransferTests {
	@Test func nativeGroupSplitMovesTheExistingCuePlacement() throws {
		let before = try stream("split-before").presentationLayout()
		let after = try stream("native-before").presentationLayout()
		let cue = try #require(UUID(uuidString: "E053CC8D-2DB9-4498-8DCE-FD56B900F02F"))
		let original = try node(cue, in: before)
		let transferred = try node(cue, in: after)
		#expect(before.groups.count == 1)
		#expect(after.groups.count == 2)
		#expect(original.nodeID == transferred.nodeID)
		#expect(original.metadata == transferred.metadata)
		#expect(original.parentID == before.groups[0].nodeID)
		#expect(transferred.parentID == after.groups[1].nodeID)
		#expect(before.cues[cue] == after.cues[cue])
		#expect(before.arrangements == after.arrangements)
	}

	@Test func transferRetainsAllCueValuesAndReferencesWhileRemovingEmptySourceGroup() throws {
		let source = try stream("native-before")
		let before = try source.presentationLayout()
		let first = before.groups[0], second = before.groups[1]
		let edits: [NativePresentationEdit] = [
			.transferCue(second.cueIDs[0], to: first.id, after: first.cueIDs[0]),
			.transferCue(second.cueIDs[1], to: first.id, after: nil),
		]
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edits: edits))
		let updated = reloaded(source, patch)
		let after = try updated.presentationLayout()
		let expected = [first.cueIDs[0], second.cueIDs[0], first.cueIDs[1], second.cueIDs[1]]
		#expect(after.groups[0].cueIDs == expected)
		#expect(after.groups.count == 1)
		#expect(after.cues == before.cues)
		#expect(after.master == before.master.filter { $0.id != second.id })
		#expect(after.arrangements == before.arrangements)
		#expect(after.groups.map(\.attributes) == [first.attributes])
		#expect(after.groups.map(\.nodeID) == [first.nodeID])
		#expect(try after.orderedCueIDs(arrangement: before.arrangements[0].id) == expected + expected)
		for cue in before.cues.keys {
			#expect(try node(cue, in: before).nodeID == node(cue, in: after).nodeID)
			#expect(try node(cue, in: before).metadata == node(cue, in: after).metadata)
		}
		let replay = LoroDoc()
		_ = try replay.import(bytes: #require(source.snapshot))
		_ = try replay.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(replay.getDeepValue()) == updated.decodedValue())
		let projection = try updated.protobufProjection().presentation()
		#expect(projection.cueGroups[0].cueIdentifiers.map(\.string) == expected.map(\.uuidString))
		#expect(projection.cueGroups.count == 1)
	}

	@Test func existingEmptyDestinationUsesTheOriginalGroupAndCueNode() throws {
		let source = try stream("empty-before-repair")
		let layout = try source.presentationLayout()
		let group = layout.groups[1]
		#expect(group.cueIDs.isEmpty)
		let cue = try #require(UUID(uuidString: "E053CC8D-2DB9-4498-8DCE-FD56B900F02F"))
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .transferCue(cue, to: group.id, after: nil)))
		let updated = reloaded(source, patch)
		let result = try updated.presentationLayout()
		#expect(result.groups[1].cueIDs == [cue])
		#expect(result.groups[1].nodeID == group.nodeID)
		#expect(try node(cue, in: result).nodeID == node(cue, in: layout).nodeID)
		#expect(result.cues == layout.cues)
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: .transferCue(cue, to: group.id, after: nil)) == nil)
	}

	@Test func emptiedGroupCleanupMatchesIndependentNativeRepairIncludingRepeatedReferences() throws {
		let source = try stream("referenced-native-before")
		let repaired = try stream("referenced-native-repair")
		let layout = try source.presentationLayout()
		let sourceGroup = layout.groups[1]
		#expect(layout.arrangements[0].groupIDs == [layout.groups[0].id, sourceGroup.id, layout.groups[0].id, sourceGroup.id])
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .transferCue(sourceGroup.cueIDs[0], to: layout.groups[0].id, after: nil)))
		let updated = reloaded(source, patch)
		#expect(try updated.decodedValue() == repaired.decodedValue())
		#expect(try updated.presentationLayout().arrangements[0].groupIDs == [layout.groups[0].id, layout.groups[0].id])
		let original = LoroDoc()
		_ = try original.import(bytes: #require(source.snapshot))
		_ = try original.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(original.getDeepValue()) == repaired.decodedValue())
	}

	@Test func removingAnEmptyGroupRequiresQualifiedNativeReferences() throws {
		let source = try stream("referenced-native-before")
		let layout = try source.presentationLayout()
		let document = LoroDoc()
		_ = try document.import(bytes: #require(source.snapshot))
		try document.getMap(id: "root").insert(key: "future_group_reference", v: layout.groups[1].id.uuidString)
		let augmented = try NativeWorkspaceStream(identity: source.identity, snapshot: document.exportSnapshot(), versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
		#expect(throws: NativeProjectionError.self) {
			try NativeLocalPatch.prepare(stream: augmented, edit: .transferCue(layout.groups[1].cueIDs[0], to: layout.groups[0].id, after: nil))
		}
	}

	@Test func productionTransferSurvivesNativeReopenWithoutRepairAndContinuedEditing() throws {
		let before = try stream("qualified-before")
		let cli = try stream("qualified-cli-after")
		let opened = try stream("qualified-native-open")
		let continued = try stream("qualified-native-continued")
		#expect(cli.snapshot == opened.snapshot)
		#expect(cli.versionVector == opened.versionVector)
		let original = try before.presentationLayout()
		let result = try cli.presentationLayout()
		#expect(original.groups.count == 2)
		#expect(result.groups.count == 1)
		#expect(result.cues == original.cues)
		#expect(result.groups[0].attributes == original.groups[0].attributes)
		#expect(result.arrangements[0].groupIDs == [original.groups[0].id, original.groups[0].id])
		#expect(try continued.presentationLayout() == result)
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeReexport.pro")))
		let projection = try continued.protobufProjection().presentation()
		#expect(exported.cueGroups == projection.cueGroups)
		#expect(exported.arrangements == projection.arrangements)
		#expect(exported.selectedArrangement == projection.selectedArrangement)
		#expect(exported.notes == "Native continued editing after qualified cue transfers")
		#expect(Set(exported.cues.compactMap { UUID(uuidString: $0.uuid.string) }) == Set(original.cues.keys))
		let history = LoroDoc(), final = LoroDoc()
		_ = try history.import(bytes: #require(before.snapshot))
		_ = try final.import(bytes: #require(continued.snapshot))
		_ = try history.import(bytes: final.exportUpdates(vv: history.oplogVv()))
		#expect(history.oplogVv().eq(other: final.oplogVv()))
		#expect(try NativeWorkspaceValue(history.getDeepValue()) == continued.decodedValue())
	}

	@Test func noOpsAndInvalidDestinationsDoNotProducePatches() throws {
		let source = try stream("native-before")
		let groups = try source.presentationLayout().groups
		let first = groups[0], second = groups[1]
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .transferCue(first.cueIDs[1], to: first.id, after: nil)) == nil)
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .transferCue(first.cueIDs[1], to: first.id, after: first.cueIDs[0])) == nil)
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .transferCue(first.cueIDs[0], to: first.id, after: first.cueIDs[0])) == nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .transferCue(UUID(), to: first.id, after: nil)) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .transferCue(first.cueIDs[0], to: UUID(), after: nil)) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .transferCue(first.cueIDs[0], to: first.id, after: second.cueIDs[0])) }
	}

	private func node(_ cue: UUID, in layout: NativePresentationLayout) throws -> NativePlacementNode {
		try #require(try layout.placements.flatMap { [$0] + $0.children }.first { node in
			let meta = try node.metadata.object(at: "/placement")
			return try meta.required("uuid", at: "/placement").uuid(at: "/placement/uuid") == cue
		})
	}

	private func reloaded(_ source: NativeWorkspaceStream, _ patch: NativeLocalPatch) -> NativeWorkspaceStream {
		.init(identity: source.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/CueTransfers")
	}

	private func stream(_ name: String) throws -> NativeWorkspaceStream {
		let bytes = try Data(contentsOf: fixtures.appendingPathComponent("\(name).loro"))
		let vector = try Data(contentsOf: fixtures.appendingPathComponent("\(name).vector"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(bytes.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: bytes, versionVector: vector, lastSharedVersionVector: nil)
	}
}
