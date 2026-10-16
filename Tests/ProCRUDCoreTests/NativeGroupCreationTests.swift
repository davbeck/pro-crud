import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native cue-group creation")
struct NativeGroupCreationTests {
	@Test func splittingMatchesTheIndependentNativeDefinitionAndRetainsCueNodes() throws {
		let source = try stream("native-created"), native = try stream("native-split-same")
		let before = try source.presentationLayout(), expected = try native.presentationLayout()
		let created = try #require(expected.groups.last), cue = try #require(created.cueIDs.first), template = before.groups[1]
		let edit = NativePresentationEdit.splitCueGroup(startingAt: cue, newID: created.id, template: template.id, name: created.name)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: edit))
		let actual = stream(source: source, patch: patch), after = try actual.presentationLayout()
		#expect(try actual.protobufProjection().presentation() == native.protobufProjection().presentation())
		#expect(after.arrangements == before.arrangements && after.cues == before.cues)
		#expect(try after.orderedCueIDs() == before.orderedCueIDs())
		#expect(after.groups.last?.attributes == created.attributes)
		#expect(after.placements.flatMap(\.children).map(\.nodeID) == before.placements.flatMap(\.children).map(\.nodeID))
		let document = LoroDoc(); _ = try document.import(bytes: #require(source.snapshot)); _ = try document.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(document.getDeepValue()) == actual.decodedValue())
		let node = try #require(after.groups.last)
		let tree = try #require(document.getMap(id: "root").get(key: "cue_group_placements")?.asLoroTree())
		let group = try #require(tree.getMeta(target: NativeStructuralEditing.treeID(node.nodeID)).get(key: "Kind")?.asLoroMap()?.get(key: "group")?.asLoroMap())
		#expect(group.get(key: "color")?.asValue() != nil && group.get(key: "color")?.asLoroMap() == nil)
		#expect(group.get(key: "hot_key")?.asLoroMap() != nil)
		#expect(try NativeLocalPatch.prepare(stream: actual, edit: edit) == nil)
	}

	@Test func orderedSplitsCanUseStableIDsAndExplicitNamesWithoutChangingArrangements() throws {
		let source = try stream("native-created"), before = try source.presentationLayout(), template = before.groups[1]
		let first = UUID(), second = UUID()
		let operations: [NativePresentationEdit] = [
			.splitCueGroup(startingAt: template.cueIDs[1], newID: first, template: template.id, name: "First split"),
			.splitCueGroup(startingAt: template.cueIDs[2], newID: second, template: template.id, name: "Second split"),
		]
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edits: operations))
		let actual = stream(source: source, patch: patch), after = try actual.presentationLayout()
		#expect(after.groups.map(\.name) == [before.groups[0].name, template.name, "First split", "Second split"])
		#expect(after.groups.suffix(3).map(\.cueIDs) == template.cueIDs.map { [$0] })
		#expect(after.arrangements == before.arrangements && after.cues == before.cues)
		#expect(try NativeLocalPatch.prepare(stream: actual, edits: operations) == nil)
	}

	@Test func invalidSplitsAndUnknownCopiedMetadataCannotProduceAPatch() throws {
		let source = try stream("native-created"), layout = try source.presentationLayout(), template = layout.groups[1]
		let invalid: [NativePresentationEdit] = [
			.splitCueGroup(startingAt: template.cueIDs[0], newID: UUID(), template: template.id, name: "First cue"),
			.splitCueGroup(startingAt: UUID(), newID: UUID(), template: template.id, name: "Missing cue"),
			.splitCueGroup(startingAt: template.cueIDs[1], newID: UUID(), template: UUID(), name: "Missing template"),
			.splitCueGroup(startingAt: template.cueIDs[1], newID: template.id, template: template.id, name: "Collision"),
			.splitCueGroup(startingAt: template.cueIDs[1], newID: UUID(), template: template.id, name: ""),
		]
		for edit in invalid {
			#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: edit) }
		}
		let document = LoroDoc(); _ = try document.import(bytes: #require(source.snapshot))
		let tree = try #require(document.getMap(id: "root").get(key: "cue_group_placements")?.asLoroTree())
		let group = try #require(tree.getMeta(target: NativeStructuralEditing.treeID(template.nodeID)).get(key: "Kind")?.asLoroMap()?.get(key: "group")?.asLoroMap())
		try group.insert(key: "future_reference", v: "owned unknown reference")
		let augmented = try NativeWorkspaceStream(identity: source.identity, snapshot: document.exportSnapshot(), versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: augmented, edit: .splitCueGroup(startingAt: template.cueIDs[1], newID: UUID(), template: template.id, name: "Unqualified copy")) }
		try group.delete(key: "future_reference")
		try group.insert(key: "color", v: LoroValue.map(value: ["red": .string(value: "invalid color component")]))
		let malformed = try NativeWorkspaceStream(identity: source.identity, snapshot: document.exportSnapshot(), versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: malformed, edit: .splitCueGroup(startingAt: template.cueIDs[1], newID: UUID(), template: template.id, name: "Malformed copy")) }
	}

	@Test func productionSplitReopensExactlyAndSupportsNativeEditingAndIndependentExport() throws {
		let before = try stream("cli-before"), cli = try stream("cli-after"), opened = try stream("native-open")
		#expect(cli.snapshot == opened.snapshot && cli.versionVector == opened.versionVector)
		let original = try before.presentationLayout(), result = try cli.presentationLayout()
		let created = try #require(result.groups.last)
		#expect(created.name == "CLI Split Group" && result.groups.count == original.groups.count + 1)
		#expect(result.groups.map(\.cueIDs).allSatisfy { $0.count == 1 })
		#expect(result.cues == original.cues)
		#expect(try result.orderedCueIDs() == original.orderedCueIDs())
		#expect(result.arrangements[0].groupIDs == [original.groups[0].id, created.id, created.id])
		#expect(result.arrangements.dropFirst().elementsEqual(original.arrangements.dropFirst()))
		#expect(result.selectedArrangementID == result.arrangements[0].id)
		#expect(try result.orderedCueIDs(arrangement: result.selectedArrangementID).count == 3)
		let continued = try stream("native-continued"), native = try continued.presentationLayout()
		#expect(native.cues == result.cues && native.arrangements == result.arrangements)
		#expect(native.selectedArrangementID == nil && native.groups.last?.id == created.id)
		#expect(native.groups.last?.name == "Native Continued Split")
		// Native Group > Edit assigns a fresh application link and clears the
		// shortcut for the new custom definition. CLI template copying retains
		// the explicitly selected definition until that native continuation.
		let attributes = try #require(native.groups.last).attributes.object(at: "/group")
		let cliAttributes = try created.attributes.object(at: "/group")
		#expect(attributes["color"] == cliAttributes["color"])
		#expect(attributes["application_group_identifier"] != cliAttributes["application_group_identifier"])
		#expect(try attributes.required("hot_key", at: "/group").object(at: "/hotkey").required("code", at: "/hotkey").int(at: "/code") == 0)
		let history = LoroDoc(); _ = try history.import(bytes: #require(cli.snapshot))
		let nativeHistory = LoroDoc(); _ = try nativeHistory.import(bytes: #require(continued.snapshot))
		_ = try history.import(bytes: nativeHistory.exportUpdates(vv: history.oplogVv()))
		#expect(try NativeWorkspaceValue(history.getDeepValue()) == continued.decodedValue())
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeReexport.pro")))
		let projected = try continued.protobufProjection().presentation()
		#expect(exported.cueGroups == projected.cueGroups && exported.arrangements == projected.arrangements)
		#expect(exported.selectedArrangement == projected.selectedArrangement)
		// Native export stores cues in map iteration order. The existing group
		// ordering adapter supplies Master, independently of raw array order.
		#expect(exported.cues.count == projected.cues.count && Set(exported.cues.map(\.uuid.string)) == Set(projected.cues.map(\.uuid.string)))
		#expect(PresentationDocument(presentation: exported).orderedCues.map(\.uuid) == PresentationDocument(presentation: projected).orderedCues.map(\.uuid))
	}

	private func stream(source: NativeWorkspaceStream, patch: NativeLocalPatch) -> NativeWorkspaceStream {
		.init(identity: source.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
	}

	private func stream(_ name: String) throws -> NativeWorkspaceStream {
		let base = fixtures.appendingPathComponent(name), data = try Data(contentsOf: base.appendingPathExtension("loro"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: base.appendingPathExtension("vector")), lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/GroupCreation")
	}
}
