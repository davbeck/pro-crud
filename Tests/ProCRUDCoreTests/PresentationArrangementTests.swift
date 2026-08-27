import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite(
	"Presentation arrangements",
	.timeLimit(.minutes(1)),
)
struct PresentationArrangementTests {
	@Test
	func expandsRepeatedGroupsInSequenceWithoutNativeLeftovers() throws {
		var fixture = makeArrangementFixture()
		let arrangement = makeArrangement(
			name: "A, B, A",
			uuid: "ARRANGEMENT-ABA",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]
		let document = PresentationDocument(
			presentation: fixture.presentation,
			arrangementSelection: .uuid(arrangement.uuid.string),
		)

		let occurrences = try document.cueOccurrences()

		#expect(occurrences.map(\.cue.name) == ["A1", "A2", "B1", "A1", "A2"])
		#expect(occurrences.map(\.cueStorageIndex) == [1, 3, 2, 1, 3])
		#expect(occurrences.map(\.arrangementGroupOccurrenceIndex) == [0, 0, 1, 2, 2])
		#expect(!occurrences.contains { $0.cue.name == "Native leftover" })
		#expect(try document.nativeCueIndices(forRenderedSlideIndices: nil) == [0, 1, 2])
		#expect(try document.nativeCueIndices(forRenderedSlideIndices: [0, 3]) == [0])

		let firstAPath = fixture.presentation.componentPath(forCueAtStorageIndex: occurrences[0].cueStorageIndex)
		let repeatedAPath = fixture.presentation.componentPath(forCueAtStorageIndex: occurrences[3].cueStorageIndex)
		#expect(firstAPath == repeatedAPath)
		#expect(try ComponentResolver.resolve(
			ComponentPath(firstAPath),
			in: presentationDocument(fixture.presentation),
		).jsonObject["name"] as? String == "A1")
	}

	@Test
	func explicitEmptyArrangementProducesNoCueOccurrences() throws {
		var fixture = makeArrangementFixture()
		let arrangement = makeArrangement(name: "Empty", uuid: "ARRANGEMENT-EMPTY", groups: [])
		fixture.presentation.arrangements = [arrangement]
		let document = PresentationDocument(
			presentation: fixture.presentation,
			arrangementSelection: .uuid(arrangement.uuid.string),
		)

		#expect(try document.resolvedArrangement()?.uuid == arrangement.uuid.string)
		#expect(try document.cueOccurrences().isEmpty)
	}

	@Test
	func noStoredSelectionUsesNativeMasterOrder() throws {
		var fixture = makeArrangementFixture()
		fixture.presentation.arrangements = [makeArrangement(
			name: "Unselected",
			uuid: "ARRANGEMENT-UNSELECTED",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)]

		let document = PresentationDocument(presentation: fixture.presentation)

		#expect(try document.resolvedArrangement() == nil)
		#expect(try document.cueOccurrences().map(\.cue.name) == ["A1", "A2", "B1", "Native leftover"])
	}

	@Test
	func storedSelectionControlsTheDefaultRenderSequenceAndMetadata() throws {
		var fixture = makeArrangementFixture()
		let arrangement = makeArrangement(
			name: "Selected A, B, A",
			uuid: "ARRANGEMENT-SELECTED",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]
		fixture.presentation.selectedArrangement = arrangement.uuid
		let document = PresentationDocument(presentation: fixture.presentation)

		let rendering = try PresentationRenderer(document: document).effectiveRendering()

		#expect(rendering.arrangement?.name == arrangement.name)
		#expect(rendering.arrangement?.uuid == arrangement.uuid.string)
		#expect(rendering.arrangement?.path.contains("ARRANGEMENT-SELECTED") == true)
		#expect(rendering.slides.map(\.index) == [0, 1, 2, 3, 4])
		#expect(rendering.slides.map(\.name) == ["A1", "A2", "B1", "A1", "A2"])

		let encoded = try JSONEncoder().encode(EffectiveRendering(presentations: [rendering]))
		let root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
		let presentations = try #require(root["presentations"] as? [[String: Any]])
		let metadata = try #require(presentations.first?["arrangement"] as? [String: Any])
		#expect(metadata["name"] as? String == arrangement.name)
		#expect(metadata["uuid"] as? String == arrangement.uuid.string)
	}

	@Test
	func explicitNativeSelectionOverridesTheStoredArrangement() throws {
		var fixture = makeArrangementFixture()
		let arrangement = makeArrangement(
			name: "Selected A, B, A",
			uuid: "ARRANGEMENT-SELECTED",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]
		fixture.presentation.selectedArrangement = arrangement.uuid
		let document = PresentationDocument(
			presentation: fixture.presentation,
			arrangementSelection: .native,
		)

		#expect(try document.resolvedArrangement() == nil)
		#expect(try document.cueOccurrences().map(\.cue.name) == ["A1", "A2", "B1", "Native leftover"])
	}

	@Test
	func strictSelectedArrangementFailsWhenNoSelectionIsStored() {
		let fixture = makeArrangementFixture()
		let document = PresentationDocument(
			presentation: fixture.presentation,
			arrangementSelection: .selected,
		)

		#expect(throws: PresentationArrangementError.self) {
			_ = try document.cueOccurrences()
		}
	}

	@Test
	func unknownArrangementUUIDFailsWithoutFallingBackToNativeOrder() {
		let fixture = makeArrangementFixture()
		let document = PresentationDocument(
			presentation: fixture.presentation,
			arrangementSelection: .uuid("UNKNOWN-ARRANGEMENT"),
		)

		#expect(throws: PresentationArrangementError.self) {
			_ = try document.cueOccurrences()
		}
	}

	@Test
	func addingArrangementsDistinguishesDefaultNativeGroupsFromExplicitEmpty() throws {
		var fixture = makeArrangementFixture()

		let defaultUUID = try DocumentEditor.addArrangement(
			to: &fixture.presentation,
			name: "Default native groups",
		)
		let emptyUUID = try DocumentEditor.addArrangement(
			to: &fixture.presentation,
			name: "Explicit empty",
			groupPaths: [],
		)

		let defaultArrangement = try #require(fixture.presentation.arrangements.first {
			$0.uuid.string == defaultUUID
		})
		let emptyArrangement = try #require(fixture.presentation.arrangements.first {
			$0.uuid.string == emptyUUID
		})
		#expect(defaultArrangement.groupIdentifiers == [fixture.groupA, fixture.groupB, fixture.groupC])
		#expect(emptyArrangement.groupIdentifiers.isEmpty)
		#expect(!fixture.presentation.hasSelectedArrangement)
	}

	@Test
	func replacesArrangementGroupsWithAnOrderedRepeatedSequenceAndSelectsOrClearsIt() throws {
		var fixture = makeArrangementFixture()
		let arrangementUUID = try DocumentEditor.addArrangement(
			to: &fixture.presentation,
			name: "Editable",
			groupPaths: [],
		)
		let arrangementPath = try ComponentPath("/arrangements[uuid=\(arrangementUUID)]")

		try DocumentEditor.setArrangementGroups(
			in: &fixture.presentation,
			at: arrangementPath,
			groupPaths: [
				ComponentPath("/cue_groups[uuid=\(fixture.groupA.string)]"),
				ComponentPath("/cue_groups[uuid=\(fixture.groupB.string)]"),
				ComponentPath("/cue_groups[uuid=\(fixture.groupA.string)]"),
			],
		)
		try DocumentEditor.selectArrangement(in: &fixture.presentation, at: arrangementPath)

		#expect(fixture.presentation.arrangements[0].groupIdentifiers == [fixture.groupA, fixture.groupB, fixture.groupA])
		#expect(fixture.presentation.selectedArrangement.string == arrangementUUID)

		DocumentEditor.clearSelectedArrangement(in: &fixture.presentation)
		#expect(!fixture.presentation.hasSelectedArrangement)
	}

	@Test
	func duplicatingArrangementCreatesFreshIdentityAndPreservesSequenceAndUnknownFields() throws {
		var fixture = makeArrangementFixture()
		var arrangement = makeArrangement(
			name: "Source",
			uuid: "ARRANGEMENT-SOURCE",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		let unknown = try Rv_Data_Presentation.Arrangement(serializedBytes: Data([0xA0, 0x06, 0x01]))
		arrangement.unknownFields = unknown.unknownFields
		fixture.presentation.arrangements = [arrangement]
		fixture.presentation.selectedArrangement = arrangement.uuid
		var document = presentationDocument(fixture.presentation)

		let duplicateUUID = try DocumentEditor.duplicate(
			&document,
			at: ComponentPath("/arrangements[uuid=\(arrangement.uuid.string)]"),
		)

		guard case let .presentation(presentation) = document.payload else {
			Issue.record("Expected presentation payload")
			return
		}
		#expect(presentation.arrangements.count == 2)
		#expect(presentation.arrangements[0].uuid == arrangement.uuid)
		#expect(presentation.arrangements[1].uuid.string == duplicateUUID)
		#expect(presentation.arrangements[1].uuid != arrangement.uuid)
		#expect(presentation.arrangements[1].name == "Source Copy")
		#expect(presentation.arrangements[1].groupIdentifiers == arrangement.groupIdentifiers)
		#expect(presentation.arrangements[1].unknownFields == arrangement.unknownFields)
		#expect(presentation.selectedArrangement == arrangement.uuid)
	}

	@Test
	func removingTheSelectedArrangementClearsTheStoredSelection() throws {
		var fixture = makeArrangementFixture()
		let selected = makeArrangement(
			name: "Selected",
			uuid: "ARRANGEMENT-SELECTED",
			groups: [fixture.groupA],
		)
		fixture.presentation.arrangements = [selected]
		fixture.presentation.selectedArrangement = selected.uuid
		var document = presentationDocument(fixture.presentation)

		try DocumentEditor.remove(
			&document,
			at: ComponentPath("/arrangements[uuid=\(selected.uuid.string)]"),
		)

		guard case let .presentation(presentation) = document.payload else {
			Issue.record("Expected presentation payload")
			return
		}
		#expect(presentation.arrangements.isEmpty)
		#expect(!presentation.hasSelectedArrangement)
	}

	@Test
	func genericRenameAndMoveSupportArrangementPaths() throws {
		var fixture = makeArrangementFixture()
		let first = makeArrangement(name: "First", uuid: "ARRANGEMENT-FIRST", groups: [fixture.groupA])
		let second = makeArrangement(name: "Second", uuid: "ARRANGEMENT-SECOND", groups: [fixture.groupB])
		let third = makeArrangement(name: "Third", uuid: "ARRANGEMENT-THIRD", groups: [fixture.groupC])
		fixture.presentation.arrangements = [first, second, third]
		var document = presentationDocument(fixture.presentation)

		let firstPath = try ComponentPath("/arrangements[uuid=\(first.uuid.string)]")
		try DocumentEditor.rename(&document, at: firstPath, to: "Renamed")
		try DocumentEditor.move(
			&document,
			at: firstPath,
			after: ComponentPath("/arrangements[uuid=\(second.uuid.string)]"),
		)

		guard case let .presentation(presentation) = document.payload else {
			Issue.record("Expected presentation payload")
			return
		}
		#expect(presentation.arrangements.map(\.name) == ["Second", "Renamed", "Third"])
	}

	@Test
	func repeatedArrangementGroupsAreValidStructure() {
		var fixture = makeArrangementFixture()
		let arrangement = makeArrangement(
			name: "A, B, A",
			uuid: "ARRANGEMENT-ABA",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]
		fixture.presentation.selectedArrangement = arrangement.uuid
		let diagnostics = DocumentValidator.structuralDiagnostics(in: presentationDocument(fixture.presentation))

		#expect(!diagnostics.contains { $0.code == "structure.duplicate-arrangement-group-reference" })
		#expect(!diagnostics.contains { $0.severity == .error })
	}
}

private struct ArrangementFixture {
	var presentation: Rv_Data_Presentation
	var groupA: Rv_Data_UUID
	var groupB: Rv_Data_UUID
	var groupC: Rv_Data_UUID
}

private func makeArrangementFixture() -> ArrangementFixture {
	var presentation = DocumentFactory.presentation(name: "Arrangement fixture")
	let prototype = presentation.cues[0]
	let cueA1 = makeCue(from: prototype, name: "A1", uuid: "CUE-A1")
	let cueA2 = makeCue(from: prototype, name: "A2", uuid: "CUE-A2")
	let cueB1 = makeCue(from: prototype, name: "B1", uuid: "CUE-B1")
	let nativeLeftover = makeCue(from: prototype, name: "Native leftover", uuid: "CUE-C1")
	let groupA = makeUUID("GROUP-A")
	let groupB = makeUUID("GROUP-B")
	let groupC = makeUUID("GROUP-C")

	// Storage order intentionally differs from native cue-group order.
	presentation.cues = [nativeLeftover, cueA1, cueB1, cueA2]
	presentation.cueGroups = [
		makeCueGroup(name: "A", uuid: groupA, cues: [cueA1.uuid, cueA2.uuid]),
		makeCueGroup(name: "B", uuid: groupB, cues: [cueB1.uuid]),
		makeCueGroup(name: "C", uuid: groupC, cues: [nativeLeftover.uuid]),
	]
	presentation.arrangements = []
	presentation.clearSelectedArrangement()
	return ArrangementFixture(presentation: presentation, groupA: groupA, groupB: groupB, groupC: groupC)
}

private func makeCue(from prototype: Rv_Data_Cue, name: String, uuid: String) -> Rv_Data_Cue {
	var cue = prototype
	cue.uuid = makeUUID(uuid)
	cue.name = name
	for actionIndex in cue.actions.indices {
		cue.actions[actionIndex].uuid = makeUUID("ACTION-\(uuid)-\(actionIndex)")
		cue.actions[actionIndex].label.text = name
		if cue.actions[actionIndex].type == .presentationSlide {
			cue.actions[actionIndex].slide.presentation.baseSlide.uuid = makeUUID("SLIDE-\(uuid)-\(actionIndex)")
		}
	}
	return cue
}

private func makeCueGroup(
	name: String,
	uuid: Rv_Data_UUID,
	cues: [Rv_Data_UUID],
) -> Rv_Data_Presentation.CueGroup {
	var group = Rv_Data_Group()
	group.uuid = uuid
	group.name = name
	var cueGroup = Rv_Data_Presentation.CueGroup()
	cueGroup.group = group
	cueGroup.cueIdentifiers = cues
	return cueGroup
}

private func makeArrangement(
	name: String,
	uuid: String,
	groups: [Rv_Data_UUID],
) -> Rv_Data_Presentation.Arrangement {
	var arrangement = Rv_Data_Presentation.Arrangement()
	arrangement.uuid = makeUUID(uuid)
	arrangement.name = name
	arrangement.groupIdentifiers = groups
	return arrangement
}

private func makeUUID(_ string: String) -> Rv_Data_UUID {
	var uuid = Rv_Data_UUID()
	uuid.string = string
	return uuid
}

private func presentationDocument(_ presentation: Rv_Data_Presentation) -> ProPresenterDocument {
	ProPresenterDocument(
		payload: .presentation(presentation),
		origin: .raw(URL(fileURLWithPath: "/tmp/ArrangementFixture.pro")),
	)
}
