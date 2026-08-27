import CustomDump
import Foundation
import ProPresenterProto
import SwiftProtobuf
import Testing
@testable import ProCRUDCore

@Suite(
	"Presentation cue groups",
	.timeLimit(.minutes(1)),
)
struct PresentationCueGroupTests {
	@Test
	func addingAndSettingGroupsTransferCueOwnershipExplicitly() throws {
		var fixture = makeCueGroupFixture()
		let createdUUID = try DocumentEditor.addCueGroup(
			to: &fixture.presentation,
			name: "Transferred",
			cuePaths: [
				cuePath(fixture.cueB1),
				cuePath(fixture.cueA1),
			],
			after: groupPath(fixture.groupB),
		)

		expectNoDifference(
			fixture.presentation.cueGroups.map(\.group.name),
			["A", "B", "Transferred", "C"],
		)
		expectNoDifference(
			fixture.presentation.cueGroups.map { $0.cueIdentifiers.map(\.string) },
			[
				[fixture.cueA2.string],
				[],
				[fixture.cueB1.string, fixture.cueA1.string],
				[fixture.cueC1.string],
			],
		)
		#expect(createdUUID == fixture.presentation.cueGroups[2].group.uuid.string)
		expectExclusiveCueOwnership(in: fixture.presentation)

		#expect(throws: CueGroupEditError.self) {
			try DocumentEditor.setCueGroupCues(
				in: &fixture.presentation,
				at: groupPath(fixture.groupB),
				cuePaths: [cuePath(fixture.cueA2), cuePath(fixture.cueB1)],
			)
		}

		try DocumentEditor.setCueGroupCues(
			in: &fixture.presentation,
			at: groupPath(fixture.groupB),
			cuePaths: [cuePath(fixture.cueA2), cuePath(fixture.cueB1)],
			ownershipPolicy: .transferFromOtherGroups,
		)
		expectNoDifference(
			fixture.presentation.cueGroups.map { $0.cueIdentifiers.map(\.string) },
			[
				[],
				[fixture.cueA2.string, fixture.cueB1.string],
				[fixture.cueA1.string],
				[fixture.cueC1.string],
			],
		)
		expectExclusiveCueOwnership(in: fixture.presentation)

		#expect(throws: CueGroupEditError.self) {
			try DocumentEditor.setCueGroupCues(
				in: &fixture.presentation,
				at: groupPath(fixture.groupB),
				cuePaths: [cuePath(fixture.cueB1)],
			)
		}
		try DocumentEditor.setCueGroupCues(
			in: &fixture.presentation,
			at: groupPath(fixture.groupB),
			cuePaths: [cuePath(fixture.cueB1)],
			omittedCuePolicy: .leaveUngrouped,
		)
		expectNoDifference(
			fixture.presentation.cueGroups[1].cueIdentifiers.map(\.string),
			[fixture.cueB1.string],
		)
		#expect(!fixture.presentation.cueGroups.contains { $0.cueIdentifiers.contains(fixture.cueA2) })
	}

	@Test
	func transferringCuesViaAddSetAndMovePreservesReferenceMetadataAndRequestedOrder() throws {
		var added = makeCueGroupFixture()
		added.presentation.cueGroups[0].cueIdentifiers[1] = try addingUnknownField(
			to: added.presentation.cueGroups[0].cueIdentifiers[1],
			marker: 1,
		)
		let addedUnknownFields = added.presentation.cueGroups[0].cueIdentifiers[1].unknownFields
		_ = try DocumentEditor.addCueGroup(
			to: &added.presentation,
			name: "Transferred by add",
			cuePaths: [cuePath(added.cueA2)],
			after: groupPath(added.groupC),
		)
		#expect(added.presentation.cueGroups[3].cueIdentifiers[0].unknownFields == addedUnknownFields)
		expectExclusiveCueOwnership(in: added.presentation)

		var set = makeCueGroupFixture()
		set.presentation.cueGroups[0].cueIdentifiers[1] = try addingUnknownField(
			to: set.presentation.cueGroups[0].cueIdentifiers[1],
			marker: 2,
		)
		let setUnknownFields = set.presentation.cueGroups[0].cueIdentifiers[1].unknownFields
		try DocumentEditor.setCueGroupCues(
			in: &set.presentation,
			at: groupPath(set.groupB),
			cuePaths: [cuePath(set.cueB1), cuePath(set.cueA2)],
			ownershipPolicy: .transferFromOtherGroups,
		)
		#expect(set.presentation.cueGroups[1].cueIdentifiers[1].unknownFields == setUnknownFields)
		expectExclusiveCueOwnership(in: set.presentation)

		var moved = makeCueGroupFixture()
		moved.presentation.cueGroups[0].cueIdentifiers[1] = try addingUnknownField(
			to: moved.presentation.cueGroups[0].cueIdentifiers[1],
			marker: 3,
		)
		let movedUnknownFields = moved.presentation.cueGroups[0].cueIdentifiers[1].unknownFields

		try DocumentEditor.moveCueToGroup(
			in: &moved.presentation,
			at: cuePath(moved.cueA2),
			groupPath: groupPath(moved.groupB),
			insertion: .start,
		)
		try DocumentEditor.moveCueToGroup(
			in: &moved.presentation,
			at: cuePath(moved.cueA1),
			groupPath: groupPath(moved.groupB),
			insertion: .after(cuePath(moved.cueB1)),
		)

		expectNoDifference(moved.presentation.cueGroups[0].cueIdentifiers, [])
		expectNoDifference(
			moved.presentation.cueGroups[1].cueIdentifiers.map(\.string),
			[moved.cueA2.string, moved.cueB1.string, moved.cueA1.string],
		)
		#expect(moved.presentation.cueGroups[1].cueIdentifiers[0].unknownFields == movedUnknownFields)
		expectExclusiveCueOwnership(in: moved.presentation)
	}

	@Test
	func addingFromMetadataPrototypeFreshensOnlyTheLocalIdentity() throws {
		var fixture = makeCueGroupFixture()
		var prototype = Rv_Data_Group()
		prototype.uuid = try addingUnknownField(
			to: makeCueGroupUUID("PROTOTYPE-GROUP"),
			marker: 9,
		)
		prototype.name = "Verse"
		prototype.color = try DocumentEditor.color(hex: "#336699")
		prototype.hotKey.code = .ansiV
		prototype.hotKey.controlIdentifier = "verse-control"
		prototype.applicationGroupIdentifier = makeCueGroupUUID("APPLICATION-VERSE")
		prototype.applicationGroupName = "Verse Label"
		prototype = try addingUnknownField(to: prototype, marker: 2)

		let createdUUID = try DocumentEditor.addCueGroup(
			to: &fixture.presentation,
			group: prototype,
			after: groupPath(fixture.groupA),
		)
		let added = fixture.presentation.cueGroups[1].group

		#expect(createdUUID == added.uuid.string)
		#expect(added.uuid != prototype.uuid)
		#expect(!added.uuid.string.isEmpty)
		#expect(added.uuid.unknownFields == prototype.uuid.unknownFields)
		expectNoDifference(added.name, prototype.name)
		expectNoDifference(added.color, prototype.color)
		expectNoDifference(added.hotKey, prototype.hotKey)
		expectNoDifference(added.applicationGroupIdentifier, prototype.applicationGroupIdentifier)
		expectNoDifference(added.applicationGroupName, prototype.applicationGroupName)
		#expect(added.unknownFields == prototype.unknownFields)
		#expect(fixture.presentation.cueGroups[1].cueIdentifiers.isEmpty)
	}

	@Test
	func cueGroupHotKeysUsePresentEmptyDefaultsAndPreserveMetadataWhenEdited() throws {
		let factoryPresentation = DocumentFactory.presentation(name: "Hot-key defaults")
		let factoryGroup = try #require(factoryPresentation.cueGroups.first?.group)
		#expect(factoryGroup.hasHotKey)
		#expect(factoryGroup.hotKey.code == .unknown)
		#expect(factoryGroup.hotKey.controlIdentifier.isEmpty)

		var added = makeCueGroupFixture()
		let addedUUID = try DocumentEditor.addCueGroup(
			to: &added.presentation,
			name: "Added",
		)
		let addedGroup = try #require(added.presentation.cueGroups.first {
			$0.group.uuid.string == addedUUID
		})
		#expect(addedGroup.group.hasHotKey)
		#expect(addedGroup.group.hotKey.code == .unknown)
		#expect(addedGroup.group.hotKey.controlIdentifier.isEmpty)

		var edited = makeCueGroupFixture()
		edited.presentation.cueGroups[0].group.hotKey = try addingUnknownField(
			to: edited.presentation.cueGroups[0].group.hotKey,
			marker: 25,
		)
		edited.presentation.cueGroups[0].group.applicationGroupIdentifier = makeCueGroupUUID("APPLICATION-A")
		edited.presentation.cueGroups[0].group.applicationGroupName = "Application A"
		let hotKeyUnknownFields = edited.presentation.cueGroups[0].group.hotKey.unknownFields

		try DocumentEditor.setCueGroupHotKey(
			in: &edited.presentation,
			at: groupPath(edited.groupA),
			code: .ansiV,
			controlIdentifier: "verse-control",
		)
		let setGroup = edited.presentation.cueGroups[0].group
		#expect(setGroup.hasHotKey)
		#expect(setGroup.hotKey.code == .ansiV)
		expectNoDifference(setGroup.hotKey.controlIdentifier, "verse-control")
		#expect(setGroup.hotKey.unknownFields == hotKeyUnknownFields)
		#expect(!setGroup.hasApplicationGroupIdentifier)
		#expect(setGroup.applicationGroupName.isEmpty)

		edited.presentation.cueGroups[0].group.applicationGroupIdentifier = makeCueGroupUUID("APPLICATION-A")
		edited.presentation.cueGroups[0].group.applicationGroupName = "Application A"
		try DocumentEditor.clearCueGroupHotKey(
			in: &edited.presentation,
			at: groupPath(edited.groupA),
		)
		let clearedGroup = edited.presentation.cueGroups[0].group
		#expect(clearedGroup.hasHotKey)
		#expect(clearedGroup.hotKey.code == .unknown)
		#expect(clearedGroup.hotKey.controlIdentifier.isEmpty)
		#expect(clearedGroup.hotKey.unknownFields == hotKeyUnknownFields)
		#expect(!clearedGroup.hasApplicationGroupIdentifier)
		#expect(clearedGroup.applicationGroupName.isEmpty)
	}

	@Test
	func renamingAndColoringDetachApplicationGroupMetadata() throws {
		var fixture = makeCueGroupFixture()
		fixture.presentation.cueGroups[0].group.applicationGroupIdentifier = makeCueGroupUUID("APPLICATION-A")
		fixture.presentation.cueGroups[0].group.applicationGroupName = "Application A"
		fixture.presentation.cueGroups[0].group.hotKey.code = .ansiA
		fixture.presentation.cueGroups[0].group = try addingUnknownField(
			to: fixture.presentation.cueGroups[0].group,
			marker: 3,
		)
		fixture.presentation.cueGroups[0].group.color = try addingUnknownField(
			to: DocumentEditor.color(hex: "#336699"),
			marker: 10,
		)
		let unknownFields = fixture.presentation.cueGroups[0].group.unknownFields
		let colorUnknownFields = fixture.presentation.cueGroups[0].group.color.unknownFields

		try DocumentEditor.renameCueGroup(
			in: &fixture.presentation,
			at: groupPath(fixture.groupA),
			to: "A",
		)
		#expect(fixture.presentation.cueGroups[0].group.hasApplicationGroupIdentifier)

		var document = cueGroupDocument(fixture.presentation)
		try DocumentEditor.rename(
			&document,
			at: groupPath(fixture.groupA),
			to: "Renamed A",
		)
		guard case var .presentation(presentation) = document.payload else {
			Issue.record("Expected presentation payload")
			return
		}
		#expect(presentation.cueGroups[0].group.name == "Renamed A")
		#expect(!presentation.cueGroups[0].group.hasApplicationGroupIdentifier)
		#expect(presentation.cueGroups[0].group.applicationGroupName.isEmpty)

		presentation.cueGroups[0].group.applicationGroupIdentifier = makeCueGroupUUID("APPLICATION-A")
		presentation.cueGroups[0].group.applicationGroupName = "Application A"
		let replacementColor = try DocumentEditor.color(hex: "#CC5500")
		try DocumentEditor.setCueGroupColor(
			in: &presentation,
			at: groupPath(fixture.groupA),
			to: replacementColor,
		)

		expectNoDifference(presentation.cueGroups[0].group.color.red, replacementColor.red)
		expectNoDifference(presentation.cueGroups[0].group.color.green, replacementColor.green)
		expectNoDifference(presentation.cueGroups[0].group.color.blue, replacementColor.blue)
		expectNoDifference(presentation.cueGroups[0].group.color.alpha, replacementColor.alpha)
		#expect(presentation.cueGroups[0].group.color.unknownFields == colorUnknownFields)
		#expect(!presentation.cueGroups[0].group.hasApplicationGroupIdentifier)
		#expect(presentation.cueGroups[0].group.applicationGroupName.isEmpty)
		#expect(presentation.cueGroups[0].group.hotKey.code == .ansiA)
		#expect(presentation.cueGroups[0].group.unknownFields == unknownFields)
	}

	@Test
	func movingGroupsChangesMasterOrderWithoutChangingArrangementOrder() throws {
		var fixture = makeCueGroupFixture()
		let arrangement = makeCueGroupArrangement(
			name: "A, B, A",
			uuid: "ARRANGEMENT-ABA",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]
		fixture.presentation.selectedArrangement = arrangement.uuid
		let selectedNamesBefore = try PresentationDocument(
			presentation: fixture.presentation,
		).cueOccurrences().map(\.cue.name)
		let cueStorageBefore = fixture.presentation.cues.map(\.uuid.string)
		var document = cueGroupDocument(fixture.presentation)

		try DocumentEditor.move(
			&document,
			at: groupPath(fixture.groupA),
			after: groupPath(fixture.groupB),
		)
		guard case let .presentation(presentation) = document.payload else {
			Issue.record("Expected presentation payload")
			return
		}

		expectNoDifference(presentation.cueGroups.map(\.group.name), ["B", "A", "C"])
		expectNoDifference(
			PresentationDocument(
				presentation: presentation,
				arrangementSelection: .native,
			).orderedCues.map(\.name),
			["B1", "A1", "A2", "C1"],
		)
		expectNoDifference(presentation.arrangements[0].groupIdentifiers, arrangement.groupIdentifiers)
		try expectNoDifference(
			PresentationDocument(presentation: presentation).cueOccurrences().map(\.cue.name),
			selectedNamesBefore,
		)
		expectNoDifference(presentation.cues.map(\.uuid.string), cueStorageBefore)
	}

	@Test
	func duplicatingAGroupDeepCopiesGraphsAndRemapsInterCueCompletion() throws {
		var fixture = makeCueGroupFixture()
		let a1Index = try #require(fixture.presentation.cues.firstIndex { $0.uuid == fixture.cueA1 })
		let a2Index = try #require(fixture.presentation.cues.firstIndex { $0.uuid == fixture.cueA2 })
		fixture.presentation.cues[a1Index].completionTargetType = .cue
		fixture.presentation.cues[a1Index].completionTargetUuid = fixture.cueA2
		fixture.presentation.cues[a2Index].completionTargetType = .cue
		fixture.presentation.cues[a2Index].completionTargetUuid = fixture.cueA1
		fixture.presentation.cueGroups[0].group.uuid = try addingUnknownField(
			to: fixture.presentation.cueGroups[0].group.uuid,
			marker: 11,
		)
		fixture.presentation.cueGroups[0].cueIdentifiers[0] = try addingUnknownField(
			to: fixture.presentation.cueGroups[0].cueIdentifiers[0],
			marker: 12,
		)
		fixture.presentation.cueGroups[0].cueIdentifiers[1] = try addingUnknownField(
			to: fixture.presentation.cueGroups[0].cueIdentifiers[1],
			marker: 13,
		)
		fixture.presentation.cues[a1Index].uuid = try addingUnknownField(
			to: fixture.presentation.cues[a1Index].uuid,
			marker: 14,
		)
		fixture.presentation.cues[a2Index].uuid = try addingUnknownField(
			to: fixture.presentation.cues[a2Index].uuid,
			marker: 15,
		)
		fixture.presentation.cues[a1Index].completionTargetUuid = try addingUnknownField(
			to: fixture.presentation.cues[a1Index].completionTargetUuid,
			marker: 16,
		)
		fixture.presentation.cues[a2Index].completionTargetUuid = try addingUnknownField(
			to: fixture.presentation.cues[a2Index].completionTargetUuid,
			marker: 17,
		)

		var element = Rv_Data_Graphics.Element()
		element.uuid = makeCueGroupUUID("ELEMENT-A1")
		element.name = "A1 element"
		var slideElement = Rv_Data_Slide.Element()
		slideElement.element = element
		fixture.presentation.cues[a1Index].actions[0].slide.presentation.baseSlide.elements = [slideElement]

		fixture.presentation.cueGroups[0] = try addingUnknownField(
			to: fixture.presentation.cueGroups[0],
			marker: 4,
		)
		fixture.presentation.cueGroups[0].group = try addingUnknownField(
			to: fixture.presentation.cueGroups[0].group,
			marker: 5,
		)
		fixture.presentation.cues[a1Index] = try addingUnknownField(
			to: fixture.presentation.cues[a1Index],
			marker: 6,
		)
		fixture.presentation.cues[a1Index].actions[0] = try addingUnknownField(
			to: fixture.presentation.cues[a1Index].actions[0],
			marker: 7,
		)
		fixture.presentation.cues[a1Index].actions[0].slide.presentation.baseSlide = try addingUnknownField(
			to: fixture.presentation.cues[a1Index].actions[0].slide.presentation.baseSlide,
			marker: 8,
		)
		fixture.presentation.cueGroups[0].group.applicationGroupIdentifier = makeCueGroupUUID("APPLICATION-A")
		let sourceGroup = fixture.presentation.cueGroups[0]
		let sourceA1 = fixture.presentation.cues[a1Index]
		let sourceA2 = fixture.presentation.cues[a2Index]
		let arrangement = makeCueGroupArrangement(
			name: "A, B, A",
			uuid: "ARRANGEMENT-ABA",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]

		let duplicateUUID = try DocumentEditor.duplicateCueGroup(
			in: &fixture.presentation,
			at: groupPath(fixture.groupA),
		)
		let duplicateGroup = fixture.presentation.cueGroups[1]
		let duplicateA1 = try cue(with: duplicateGroup.cueIdentifiers[0], in: fixture.presentation)
		let duplicateA2 = try cue(with: duplicateGroup.cueIdentifiers[1], in: fixture.presentation)

		#expect(duplicateGroup.group.uuid.string == duplicateUUID)
		#expect(duplicateGroup.group.uuid != sourceGroup.group.uuid)
		#expect(duplicateGroup.group.uuid.unknownFields == sourceGroup.group.uuid.unknownFields)
		expectNoDifference(duplicateGroup.group.name, sourceGroup.group.name)
		expectNoDifference(
			duplicateGroup.group.applicationGroupIdentifier,
			sourceGroup.group.applicationGroupIdentifier,
		)
		#expect(duplicateGroup.unknownFields == sourceGroup.unknownFields)
		#expect(duplicateGroup.group.unknownFields == sourceGroup.group.unknownFields)
		#expect(duplicateA1.uuid != sourceA1.uuid)
		#expect(duplicateA2.uuid != sourceA2.uuid)
		#expect(duplicateA1.uuid.unknownFields == sourceA1.uuid.unknownFields)
		#expect(duplicateA2.uuid.unknownFields == sourceA2.uuid.unknownFields)
		#expect(duplicateGroup.cueIdentifiers[0].string == duplicateA1.uuid.string)
		#expect(duplicateGroup.cueIdentifiers[1].string == duplicateA2.uuid.string)
		#expect(
			duplicateGroup.cueIdentifiers[0].unknownFields ==
				sourceGroup.cueIdentifiers[0].unknownFields,
		)
		#expect(
			duplicateGroup.cueIdentifiers[1].unknownFields ==
				sourceGroup.cueIdentifiers[1].unknownFields,
		)
		#expect(duplicateA1.actions[0].uuid != sourceA1.actions[0].uuid)
		#expect(duplicateA2.actions[0].uuid != sourceA2.actions[0].uuid)
		#expect(duplicateA1.actions[0].slide.presentation.baseSlide.uuid != sourceA1.actions[0].slide.presentation.baseSlide.uuid)
		#expect(duplicateA2.actions[0].slide.presentation.baseSlide.uuid != sourceA2.actions[0].slide.presentation.baseSlide.uuid)
		#expect(
			duplicateA1.actions[0].slide.presentation.baseSlide.elements[0].element.uuid !=
				sourceA1.actions[0].slide.presentation.baseSlide.elements[0].element.uuid,
		)
		#expect(duplicateA1.completionTargetType == .cue)
		#expect(duplicateA2.completionTargetType == .cue)
		#expect(duplicateA1.completionTargetUuid.string == duplicateA2.uuid.string)
		#expect(duplicateA2.completionTargetUuid.string == duplicateA1.uuid.string)
		#expect(
			duplicateA1.completionTargetUuid.unknownFields ==
				sourceA1.completionTargetUuid.unknownFields,
		)
		#expect(
			duplicateA2.completionTargetUuid.unknownFields ==
				sourceA2.completionTargetUuid.unknownFields,
		)
		#expect(duplicateA1.unknownFields == sourceA1.unknownFields)
		#expect(duplicateA1.actions[0].unknownFields == sourceA1.actions[0].unknownFields)
		#expect(
			duplicateA1.actions[0].slide.presentation.baseSlide.unknownFields ==
				sourceA1.actions[0].slide.presentation.baseSlide.unknownFields,
		)
		expectNoDifference(fixture.presentation.arrangements[0].groupIdentifiers, arrangement.groupIdentifiers)
		expectExclusiveCueOwnership(in: fixture.presentation)
	}

	@Test
	func removalRejectsImplicitDestructivePoliciesWithoutMutation() throws {
		var fixture = makeCueGroupFixture()
		let arrangement = makeCueGroupArrangement(
			name: "A twice",
			uuid: "ARRANGEMENT-A",
			groups: [fixture.groupA, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]
		let original = fixture.presentation

		#expect(throws: CueGroupEditError.self) {
			try DocumentEditor.removeCueGroup(
				in: &fixture.presentation,
				at: groupPath(fixture.groupA),
			)
		}
		expectNoDifference(fixture.presentation, original)

		#expect(throws: CueGroupEditError.self) {
			try DocumentEditor.removeCueGroup(
				in: &fixture.presentation,
				at: groupPath(fixture.groupA),
				arrangementPolicy: .removeAllOccurrences,
			)
		}
		expectNoDifference(fixture.presentation, original)
	}

	@Test
	func removalCanLeaveCuesUngroupedAndRemoveEveryArrangementOccurrence() throws {
		var fixture = makeCueGroupFixture()
		let arrangement = makeCueGroupArrangement(
			name: "A, B, A",
			uuid: "ARRANGEMENT-ABA",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]
		fixture.presentation.selectedArrangement = arrangement.uuid
		let storedCueIDs = fixture.presentation.cues.map(\.uuid.string)

		let report = try DocumentEditor.removeCueGroup(
			in: &fixture.presentation,
			at: groupPath(fixture.groupA),
			cuePolicy: .leaveUngrouped,
			arrangementPolicy: .removeAllOccurrences,
		)

		expectNoDifference(
			report,
			CueGroupRemovalReport(
				groupUUID: fixture.groupA.string,
				removedCueUUIDs: [],
				movedCueUUIDs: [],
				removedArrangementOccurrences: 2,
			),
		)
		expectNoDifference(fixture.presentation.cueGroups.map(\.group.uuid.string), [fixture.groupB.string, fixture.groupC.string])
		expectNoDifference(fixture.presentation.cues.map(\.uuid.string), storedCueIDs)
		expectNoDifference(fixture.presentation.arrangements[0].groupIdentifiers.map(\.string), [fixture.groupB.string])
		#expect(fixture.presentation.selectedArrangement == arrangement.uuid)
		expectNoDifference(
			PresentationDocument(presentation: fixture.presentation).orderedCues.map(\.name),
			["B1", "C1", "A1", "A2"],
		)
	}

	@Test
	func removalCanMoveOrDeleteOwnedCues() throws {
		var moved = makeCueGroupFixture()
		moved.presentation.arrangements = [makeCueGroupArrangement(
			name: "A, B, A",
			uuid: "ARRANGEMENT-ABA",
			groups: [moved.groupA, moved.groupB, moved.groupA],
		)]
		let moveReport = try DocumentEditor.removeCueGroup(
			in: &moved.presentation,
			at: groupPath(moved.groupA),
			cuePolicy: .moveCues(to: groupPath(moved.groupB)),
			arrangementPolicy: .removeAllOccurrences,
		)
		expectNoDifference(
			moveReport,
			CueGroupRemovalReport(
				groupUUID: moved.groupA.string,
				removedCueUUIDs: [],
				movedCueUUIDs: [moved.cueA1.string, moved.cueA2.string],
				removedArrangementOccurrences: 2,
			),
		)
		expectNoDifference(
			moved.presentation.cueGroups[0].cueIdentifiers.map(\.string),
			[moved.cueB1.string, moved.cueA1.string, moved.cueA2.string],
		)
		expectNoDifference(
			PresentationDocument(presentation: moved.presentation).orderedCues.map(\.name),
			["B1", "A1", "A2", "C1"],
		)
		expectExclusiveCueOwnership(in: moved.presentation)

		var deleted = makeCueGroupFixture()
		deleted.presentation.arrangements = [makeCueGroupArrangement(
			name: "A then B",
			uuid: "ARRANGEMENT-AB",
			groups: [deleted.groupA, deleted.groupB],
		)]
		let deleteReport = try DocumentEditor.removeCueGroup(
			in: &deleted.presentation,
			at: groupPath(deleted.groupA),
			cuePolicy: .deleteOwnedCues,
			arrangementPolicy: .removeAllOccurrences,
		)
		expectNoDifference(
			deleteReport,
			CueGroupRemovalReport(
				groupUUID: deleted.groupA.string,
				removedCueUUIDs: [deleted.cueA1.string, deleted.cueA2.string],
				movedCueUUIDs: [],
				removedArrangementOccurrences: 1,
			),
		)
		expectNoDifference(deleted.presentation.cues.map(\.uuid.string), [deleted.cueC1.string, deleted.cueB1.string])
		expectNoDifference(
			PresentationDocument(presentation: deleted.presentation).orderedCues.map(\.name),
			["B1", "C1"],
		)
	}

	@Test
	func deletingOwnedCuesRejectsExternalReferencesAndInvalidMinimums() throws {
		var referenced = makeCueGroupFixture()
		let c1Index = try #require(referenced.presentation.cues.firstIndex { $0.uuid == referenced.cueC1 })
		referenced.presentation.cues[c1Index].completionTargetType = .cue
		referenced.presentation.cues[c1Index].completionTargetUuid = referenced.cueA1
		let original = referenced.presentation
		#expect(throws: CueGroupEditError.self) {
			try DocumentEditor.removeCueGroup(
				in: &referenced.presentation,
				at: groupPath(referenced.groupA),
				cuePolicy: .deleteOwnedCues,
			)
		}
		expectNoDifference(referenced.presentation, original)

		var oneGroup = DocumentFactory.presentation(name: "One group")
		#expect(throws: CueGroupEditError.self) {
			try DocumentEditor.removeCueGroup(
				in: &oneGroup,
				at: ComponentPath("/cue_groups[index=0]"),
				cuePolicy: .leaveUngrouped,
			)
		}

		var allCues = DocumentFactory.presentation(name: "All cues")
		_ = try DocumentEditor.addCueGroup(to: &allCues, name: "Empty")
		#expect(throws: CueGroupEditError.self) {
			try DocumentEditor.removeCueGroup(
				in: &allCues,
				at: ComponentPath("/cue_groups[index=0]"),
				cuePolicy: .deleteOwnedCues,
			)
		}
	}

	@Test
	func genericCueEditingAndDumpMatchCueGroupReferencesByUUIDString() throws {
		var duplicated = makeCueGroupFixture()
		duplicated.presentation.cueGroups[0].cueIdentifiers[0] = try addingUnknownField(
			to: duplicated.presentation.cueGroups[0].cueIdentifiers[0],
			marker: 18,
		)
		var duplicateDocument = cueGroupDocument(duplicated.presentation)
		let duplicatedReferenceUnknownFields = duplicated.presentation.cueGroups[0].cueIdentifiers[0].unknownFields
		let duplicatedUUID = try DocumentEditor.duplicate(
			&duplicateDocument,
			at: cuePath(duplicated.cueA1),
		)
		let duplicatePresentation = try presentation(from: duplicateDocument)
		expectNoDifference(
			duplicatePresentation.cueGroups[0].cueIdentifiers.map(\.string),
			[duplicated.cueA1.string, duplicatedUUID, duplicated.cueA2.string],
		)
		#expect(
			duplicatePresentation.cueGroups[0].cueIdentifiers[0].unknownFields ==
				duplicatedReferenceUnknownFields,
		)

		var removed = makeCueGroupFixture()
		removed.presentation.cueGroups[0].cueIdentifiers[0] = try addingUnknownField(
			to: removed.presentation.cueGroups[0].cueIdentifiers[0],
			marker: 19,
		)
		var removeDocument = cueGroupDocument(removed.presentation)
		try DocumentEditor.remove(&removeDocument, at: cuePath(removed.cueA1))
		let removePresentation = try presentation(from: removeDocument)
		#expect(!removePresentation.cues.contains { $0.uuid.string == removed.cueA1.string })
		#expect(!removePresentation.cueGroups.contains { group in
			group.cueIdentifiers.contains { $0.string == removed.cueA1.string }
		})

		var moved = makeCueGroupFixture()
		moved.presentation.cueGroups[0].cueIdentifiers[0] = try addingUnknownField(
			to: moved.presentation.cueGroups[0].cueIdentifiers[0],
			marker: 20,
		)
		moved.presentation.cueGroups[0].cueIdentifiers[1] = try addingUnknownField(
			to: moved.presentation.cueGroups[0].cueIdentifiers[1],
			marker: 21,
		)
		let movedA1ReferenceUnknownFields = moved.presentation.cueGroups[0].cueIdentifiers[0].unknownFields
		let movedA2ReferenceUnknownFields = moved.presentation.cueGroups[0].cueIdentifiers[1].unknownFields
		var moveDocument = cueGroupDocument(moved.presentation)
		try DocumentEditor.move(
			&moveDocument,
			at: cuePath(moved.cueA1),
			after: cuePath(moved.cueA2),
		)
		let movePresentation = try presentation(from: moveDocument)
		expectNoDifference(
			movePresentation.cueGroups[0].cueIdentifiers.map(\.string),
			[moved.cueA2.string, moved.cueA1.string],
		)
		#expect(movePresentation.cueGroups[0].cueIdentifiers[0].unknownFields == movedA2ReferenceUnknownFields)
		#expect(movePresentation.cueGroups[0].cueIdentifiers[1].unknownFields == movedA1ReferenceUnknownFields)

		var added = makeCueGroupFixture()
		added.presentation.cueGroups[0].cueIdentifiers[0] = try addingUnknownField(
			to: added.presentation.cueGroups[0].cueIdentifiers[0],
			marker: 22,
		)
		let addedReferenceUnknownFields = added.presentation.cueGroups[0].cueIdentifiers[0].unknownFields
		try DocumentEditor.addBlankSlide(
			to: &added.presentation,
			groupPath: groupPath(added.groupA),
			after: cuePath(added.cueA1),
		)
		let addedGroupCueIDs = added.presentation.cueGroups[0].cueIdentifiers.map(\.string)
		#expect(addedGroupCueIDs.count == 3)
		#expect(addedGroupCueIDs[0] == added.cueA1.string)
		#expect(addedGroupCueIDs[1] != added.cueA1.string)
		#expect(addedGroupCueIDs[1] != added.cueA2.string)
		#expect(addedGroupCueIDs[2] == added.cueA2.string)
		#expect(added.presentation.cueGroups[0].cueIdentifiers[0].unknownFields == addedReferenceUnknownFields)

		let dumpDocument = cueGroupDocument(added.presentation)
		let dump = try DocumentDumpReport.make(from: dumpDocument)
		let dumpedA1 = try #require(dump.presentation?.cues.first {
			$0.uuid == added.cueA1.string
		})
		expectNoDifference(dumpedA1.groupUUIDs, [added.groupA.string])
	}

	@Test
	func completionUUIDsOnlyActAsCueReferencesForCueCompletionTargets() throws {
		var duplicated = makeCueGroupFixture()
		let a1Index = try #require(duplicated.presentation.cues.firstIndex {
			$0.uuid.string == duplicated.cueA1.string
		})
		let a2Index = try #require(duplicated.presentation.cues.firstIndex {
			$0.uuid.string == duplicated.cueA2.string
		})
		duplicated.presentation.cues[a1Index].completionTargetType = .next
		duplicated.presentation.cues[a1Index].completionTargetUuid = try addingUnknownField(
			to: duplicated.cueA2,
			marker: 23,
		)
		duplicated.presentation.cues[a1Index].completionActionType = .first
		duplicated.presentation.cues[a1Index].completionActionUuid = try addingUnknownField(
			to: duplicated.presentation.cues[a1Index].actions[0].uuid,
			marker: 26,
		)
		duplicated.presentation.cues[a2Index].completionActionType = .afterAction
		duplicated.presentation.cues[a2Index].completionActionUuid = try addingUnknownField(
			to: duplicated.presentation.cues[a2Index].actions[0].uuid,
			marker: 27,
		)
		let sourceTarget = duplicated.presentation.cues[a1Index].completionTargetUuid
		let irrelevantAction = duplicated.presentation.cues[a1Index].completionActionUuid
		let semanticActionUnknownFields = duplicated.presentation.cues[a2Index].completionActionUuid.unknownFields
		_ = try DocumentEditor.duplicateCueGroup(
			in: &duplicated.presentation,
			at: groupPath(duplicated.groupA),
		)
		let duplicateGroup = duplicated.presentation.cueGroups[1]
		let duplicateA1 = try cue(with: duplicateGroup.cueIdentifiers[0], in: duplicated.presentation)
		let duplicateA2 = try cue(with: duplicateGroup.cueIdentifiers[1], in: duplicated.presentation)
		#expect(duplicateA1.completionTargetType == .next)
		expectNoDifference(duplicateA1.completionTargetUuid, sourceTarget)
		#expect(duplicateA1.completionActionType == .first)
		expectNoDifference(duplicateA1.completionActionUuid, irrelevantAction)
		#expect(duplicateA2.completionActionType == .afterAction)
		#expect(duplicateA2.completionActionUuid.string == duplicateA2.actions[0].uuid.string)
		#expect(duplicateA2.completionActionUuid.unknownFields == semanticActionUnknownFields)

		var deleted = makeCueGroupFixture()
		let c1Index = try #require(deleted.presentation.cues.firstIndex {
			$0.uuid.string == deleted.cueC1.string
		})
		deleted.presentation.cues[c1Index].completionTargetType = .random
		deleted.presentation.cues[c1Index].completionTargetUuid = try addingUnknownField(
			to: deleted.cueA1,
			marker: 24,
		)
		let irrelevantTarget = deleted.presentation.cues[c1Index].completionTargetUuid

		let report = try DocumentEditor.removeCueGroup(
			in: &deleted.presentation,
			at: groupPath(deleted.groupA),
			cuePolicy: .deleteOwnedCues,
		)
		expectNoDifference(
			report.removedCueUUIDs,
			[deleted.cueA1.string, deleted.cueA2.string],
		)
		let retainedC1 = try cue(with: deleted.cueC1, in: deleted.presentation)
		#expect(retainedC1.completionTargetType == .random)
		expectNoDifference(retainedC1.completionTargetUuid, irrelevantTarget)
	}

	@Test
	func effectiveRenderingReportsNativeAndRepeatedArrangementGroupContext() throws {
		var fixture = makeCueGroupFixture()
		let arrangement = makeCueGroupArrangement(
			name: "A, B, A",
			uuid: "ARRANGEMENT-ABA",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]

		let native = try PresentationRenderer(document: PresentationDocument(
			presentation: fixture.presentation,
			arrangementSelection: .native,
		)).effectiveRendering()
		expectNoDifference(native.slides.map { $0.cueGroup?.name }, ["A", "A", "B", "C"])
		expectNoDifference(
			native.slides.map { $0.cueGroup?.uuid },
			[fixture.groupA.string, fixture.groupA.string, fixture.groupB.string, fixture.groupC.string],
		)
		expectNoDifference(
			native.slides.map { slide -> Int? in
				slide.cueGroup?.arrangementOccurrenceIndex
			},
			[nil, nil, nil, nil],
		)
		#expect(native.slides.allSatisfy { $0.cueGroup?.path.contains("/cue_groups[uuid=") == true })

		let arranged = try PresentationRenderer(document: PresentationDocument(
			presentation: fixture.presentation,
			arrangementSelection: .uuid(arrangement.uuid.string),
		)).effectiveRendering()
		expectNoDifference(arranged.slides.map(\.name), ["A1", "A2", "B1", "A1", "A2"])
		expectNoDifference(arranged.slides.map { $0.cueGroup?.name }, ["A", "A", "B", "A", "A"])
		expectNoDifference(
			arranged.slides.map { slide -> Int? in
				slide.cueGroup?.arrangementOccurrenceIndex
			},
			[0, 0, 1, 2, 2],
		)
	}
}

private struct CueGroupFixture {
	var presentation: Rv_Data_Presentation
	var groupA: Rv_Data_UUID
	var groupB: Rv_Data_UUID
	var groupC: Rv_Data_UUID
	var cueA1: Rv_Data_UUID
	var cueA2: Rv_Data_UUID
	var cueB1: Rv_Data_UUID
	var cueC1: Rv_Data_UUID
}

private func makeCueGroupFixture() -> CueGroupFixture {
	var presentation = DocumentFactory.presentation(name: "Cue-group fixture")
	let prototype = presentation.cues[0]
	let cueA1 = makeCueGroupCue(from: prototype, name: "A1", uuid: "CUE-A1")
	let cueA2 = makeCueGroupCue(from: prototype, name: "A2", uuid: "CUE-A2")
	let cueB1 = makeCueGroupCue(from: prototype, name: "B1", uuid: "CUE-B1")
	let cueC1 = makeCueGroupCue(from: prototype, name: "C1", uuid: "CUE-C1")
	let groupA = makeCueGroupUUID("GROUP-A")
	let groupB = makeCueGroupUUID("GROUP-B")
	let groupC = makeCueGroupUUID("GROUP-C")

	// Storage order intentionally differs from native cue-group order.
	presentation.cues = [cueC1, cueA1, cueB1, cueA2]
	presentation.cueGroups = [
		makePresentationCueGroup(name: "A", uuid: groupA, cues: [cueA1.uuid, cueA2.uuid]),
		makePresentationCueGroup(name: "B", uuid: groupB, cues: [cueB1.uuid]),
		makePresentationCueGroup(name: "C", uuid: groupC, cues: [cueC1.uuid]),
	]
	presentation.arrangements = []
	presentation.clearSelectedArrangement()
	return CueGroupFixture(
		presentation: presentation,
		groupA: groupA,
		groupB: groupB,
		groupC: groupC,
		cueA1: cueA1.uuid,
		cueA2: cueA2.uuid,
		cueB1: cueB1.uuid,
		cueC1: cueC1.uuid,
	)
}

private func makeCueGroupCue(
	from prototype: Rv_Data_Cue,
	name: String,
	uuid: String,
) -> Rv_Data_Cue {
	var cue = prototype
	cue.uuid = makeCueGroupUUID(uuid)
	cue.name = name
	for actionIndex in cue.actions.indices {
		cue.actions[actionIndex].uuid = makeCueGroupUUID("ACTION-\(uuid)-\(actionIndex)")
		cue.actions[actionIndex].label.text = name
		if cue.actions[actionIndex].type == .presentationSlide {
			cue.actions[actionIndex].slide.presentation.baseSlide.uuid = makeCueGroupUUID("SLIDE-\(uuid)-\(actionIndex)")
		}
	}
	return cue
}

private func makePresentationCueGroup(
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

private func makeCueGroupArrangement(
	name: String,
	uuid: String,
	groups: [Rv_Data_UUID],
) -> Rv_Data_Presentation.Arrangement {
	var arrangement = Rv_Data_Presentation.Arrangement()
	arrangement.uuid = makeCueGroupUUID(uuid)
	arrangement.name = name
	arrangement.groupIdentifiers = groups
	return arrangement
}

private func makeCueGroupUUID(_ string: String) -> Rv_Data_UUID {
	var uuid = Rv_Data_UUID()
	uuid.string = string
	return uuid
}

private func cuePath(_ uuid: Rv_Data_UUID) -> ComponentPath {
	ComponentPath(segments: [
		.init(field: "cues", selector: .field(name: "uuid", value: uuid.string)),
	])
}

private func groupPath(_ uuid: Rv_Data_UUID) -> ComponentPath {
	ComponentPath(segments: [
		.init(field: "cue_groups", selector: .field(name: "uuid", value: uuid.string)),
	])
}

private func cue(
	with uuid: Rv_Data_UUID,
	in presentation: Rv_Data_Presentation,
) throws -> Rv_Data_Cue {
	try #require(presentation.cues.first { $0.uuid.string == uuid.string })
}

private func presentation(
	from document: ProPresenterDocument,
) throws -> Rv_Data_Presentation {
	guard case let .presentation(presentation) = document.payload else {
		Issue.record("Expected presentation payload")
		throw CueGroupTestError.expectedPresentation
	}
	return presentation
}

private func expectExclusiveCueOwnership(
	in presentation: Rv_Data_Presentation,
) {
	let referencedIDs = presentation.cueGroups.flatMap { $0.cueIdentifiers.map(\.string) }
	expectNoDifference(referencedIDs.count, presentation.cues.count)
	expectNoDifference(
		Set(referencedIDs),
		Set(presentation.cues.map(\.uuid.string)),
	)
}

private func addingUnknownField<Message: SwiftProtobuf.Message>(
	to message: Message,
	marker: UInt8,
) throws -> Message {
	var data = try message.serializedData()
	data.append(contentsOf: [0xA0, 0x06, marker])
	return try Message(serializedBytes: data)
}

private func cueGroupDocument(_ presentation: Rv_Data_Presentation) -> ProPresenterDocument {
	ProPresenterDocument(
		payload: .presentation(presentation),
		origin: .raw(URL(fileURLWithPath: "/tmp/CueGroupFixture.pro")),
	)
}

private enum CueGroupTestError: Error {
	case expectedPresentation
}
