import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite(
	"Cue-group commands",
	.timeLimit(.minutes(2)),
)
struct CueGroupCommandTests {
	@Test
	func helpAndParsersExposeCueGroupCommandsAndPolicies() throws {
		let cueA = "/cues[uuid=CUE-A1]"
		let cueB = "/cues[uuid=CUE-B1]"
		let groupA = "/cue_groups[uuid=GROUP-A]"
		let groupB = "/cue_groups[uuid=GROUP-B]"

		let add = try EditAddCueGroup.parse([
			"Song.pro",
			"--name", "New",
			"--cue", cueA,
			"--cue", cueB,
			"--color", "#123456",
			"--after", groupA,
		])
		#expect(add.name == "New")
		#expect(add.cue == [cueA, cueB])
		#expect(add.color == "#123456")
		#expect(add.after == groupA)

		let set = try EditSetCueGroupCues.parse([
			"Song.pro",
			"--path", groupA,
			"--cue", cueB,
			"--transfer",
			"--leave-omitted-ungrouped",
		])
		#expect(set.path == groupA)
		#expect(set.cue == [cueB])
		#expect(set.transfer)
		#expect(set.leaveOmittedUngrouped)

		let move = try EditMoveCueToGroup.parse([
			"Song.pro",
			"--path", cueA,
			"--group", groupB,
			"--first",
		])
		#expect(move.path == cueA)
		#expect(move.group == groupB)
		#expect(move.first)

		let setColor = try EditSetCueGroupColor.parse([
			"Song.pro",
			"--path", groupA,
			"--color", "#ABCDEF",
		])
		#expect(setColor.color == "#ABCDEF")
		#expect(!setColor.clear)
		let clearColor = try EditSetCueGroupColor.parse([
			"Song.pro",
			"--path", groupA,
			"--clear",
		])
		#expect(clearColor.clear)
		#expect(clearColor.color == nil)

		for spelling in ["ansiV", "ansi-v", "ansi_v", "KEY_CODE_ANSI_V", "V", "22"] {
			let hotKey = try EditSetCueGroupHotKey.parse([
				"Song.pro",
				"--path", groupA,
				"--code", spelling,
				"--control-identifier", "remote.v",
			])
			#expect(hotKey.code?.value == .ansiV)
			#expect(hotKey.controlIdentifier == "remote.v")
			#expect(!hotKey.clear)
		}
		let futureHotKey = try EditSetCueGroupHotKey.parse([
			"Song.pro",
			"--path", groupA,
			"--code", "999",
		])
		#expect(futureHotKey.code?.value.rawValue == 999)
		let clearHotKey = try EditSetCueGroupHotKey.parse([
			"Song.pro",
			"--path", groupA,
			"--clear",
		])
		#expect(clearHotKey.code?.value == nil)
		#expect(clearHotKey.clear)

		let duplicate = try EditDuplicateCueGroup.parse([
			"Song.pro",
			"--path", groupA,
			"--name", "A Copy",
		])
		#expect(duplicate.path == groupA)
		#expect(duplicate.name == "A Copy")

		let remove = try EditRemoveCueGroup.parse([
			"Song.pro",
			"--path", groupA,
			"--move-cues-to", groupB,
			"--remove-from-arrangements",
		])
		#expect(remove.moveCuesTo == groupB)
		#expect(remove.removeFromArrangements)

		let editHelp = Edit.helpMessage()
		for command in [
			"add-cue-group",
			"set-cue-group-cues",
			"move-cue-to-group",
			"set-cue-group-color",
			"set-cue-group-hotkey",
			"duplicate-cue-group",
			"remove-cue-group",
		] {
			#expect(editHelp.contains(command))
		}
		#expect(EditSetCueGroupCues.helpMessage().contains("--transfer"))
		#expect(EditSetCueGroupCues.helpMessage().contains("--leave-omitted-ungrouped"))
		#expect(EditMoveCueToGroup.helpMessage().contains("--first"))
		#expect(EditSetCueGroupColor.helpMessage().contains("--clear"))
		#expect(EditSetCueGroupHotKey.helpMessage().contains("--control-identifier"))
		#expect(EditSetCueGroupHotKey.helpMessage().contains("--clear"))
		#expect(EditRemoveCueGroup.helpMessage().contains("--delete-cues"))
		#expect(EditRemoveCueGroup.helpMessage().contains("--leave-cues-ungrouped"))
		#expect(EditRemoveCueGroup.helpMessage().contains("--move-cues-to"))
		#expect(EditRemoveCueGroup.helpMessage().contains("--remove-from-arrangements"))
	}

	@Test
	func commandsReturnCanonicalAffectedCreatedAndRemovedPaths() throws {
		var fixture = try makeCueGroupCommandFixture()
		let input = "/tmp/CueGroupPaths.pro"

		let addOutputs = try EditAddCueGroup.parse([
			input,
			"--name", "Canonical",
			"--empty",
		]).apply(to: &fixture.presentation)
		let created = try #require(addOutputs.first)
		#expect(created.kind == .created)
		try expectCanonical(created, in: fixture.presentation)

		let colorOutputs = try EditSetCueGroupColor.parse([
			input,
			"--path", created.path,
			"--color", "#123456",
		]).apply(to: &fixture.presentation)
		let colored = try #require(colorOutputs.first)
		#expect(colored.kind == .affected)
		#expect(colored.path == created.path)
		try expectCanonical(colored, in: fixture.presentation)

		let setOutputs = try EditSetCueGroupCues.parse([
			input,
			"--path", created.path,
			"--cue", cueGroupCuePath(fixture.cueC1),
			"--transfer",
		]).apply(to: &fixture.presentation)
		let set = try #require(setOutputs.first)
		#expect(set.kind == .affected)
		#expect(set.path == created.path)
		try expectCanonical(set, in: fixture.presentation)

		let moveOutputs = try EditMoveCueToGroup.parse([
			input,
			"--path", cueGroupCuePath(fixture.cueA1),
			"--group", created.path,
			"--first",
		]).apply(to: &fixture.presentation)
		let moved = try #require(moveOutputs.first)
		#expect(moved.kind == .affected)
		#expect(moved.path.contains("/cues[uuid="))
		try expectCanonical(moved, in: fixture.presentation)

		let duplicateOutputs = try EditDuplicateCueGroup.parse([
			input,
			"--path", created.path,
			"--name", "Canonical Copy",
		]).apply(to: &fixture.presentation)
		#expect(duplicateOutputs.count == 2)
		#expect(duplicateOutputs[0] == .init(kind: .affected, path: created.path))
		#expect(duplicateOutputs[1].kind == .created)
		try expectCanonical(duplicateOutputs[0], in: fixture.presentation)
		try expectCanonical(duplicateOutputs[1], in: fixture.presentation)

		let removedPath = cueGroupGroupPath(fixture.groupC)
		let removeOutputs = try EditRemoveCueGroup.parse([
			input,
			"--path", removedPath,
			"--remove-from-arrangements",
		]).apply(to: &fixture.presentation)
		let removed = try #require(removeOutputs.first)
		#expect(removeOutputs.count == 1)
		#expect(removed.kind == .removed)
		#expect(removed.path.contains(fixture.groupC.string))
		#expect(!fixture.presentation.cueGroups.contains { $0.group.uuid == fixture.groupC })
	}

	@Test
	func moveCueToGroupStabilizesIndexAddressedOutputBeforeChangingCueOrder() throws {
		var fixture = try makeCueGroupCommandFixture()
		let indexedPath = "/cues[index=0]"
		let expectedPath = try canonicalPath(ComponentPath(indexedPath), in: fixture.presentation)
		#expect(
			try expectedPath == canonicalPath(
				ComponentPath(cueGroupCuePath(fixture.cueA1)),
				in: fixture.presentation,
			),
		)

		let outputs = try EditMoveCueToGroup.parse([
			"/tmp/CueGroupIndexedMove.pro",
			"--path", indexedPath,
			"--group", cueGroupGroupPath(fixture.groupC),
			"--first",
		]).apply(to: &fixture.presentation)

		#expect(outputs == [.init(kind: .affected, path: expectedPath)])
		#expect(
			try canonicalPath(ComponentPath(indexedPath), in: fixture.presentation) ==
				canonicalPath(
					ComponentPath(cueGroupCuePath(fixture.cueA2)),
					in: fixture.presentation,
				),
		)
	}

	@Test
	func setCueGroupHotKeyRejectsInvalidArguments() throws {
		var fixture = try makeCueGroupCommandFixture()
		let input = "/tmp/CueGroupInvalidHotKey.pro"
		let group = cueGroupGroupPath(fixture.groupA)

		#expect(throws: (any Error).self) {
			_ = try EditSetCueGroupHotKey.parse([
				input,
				"--path", group,
				"--code", "not-a-key",
			])
		}
		#expect(throws: (any Error).self) {
			try EditSetCueGroupHotKey.parse([
				input,
				"--path", group,
			]).apply(to: &fixture.presentation)
		}
		#expect(throws: (any Error).self) {
			try EditSetCueGroupHotKey.parse([
				input,
				"--path", group,
				"--code", "ansiV",
				"--clear",
			]).apply(to: &fixture.presentation)
		}
		#expect(throws: (any Error).self) {
			try EditSetCueGroupHotKey.parse([
				input,
				"--path", group,
				"--control-identifier", "remote.v",
				"--clear",
			]).apply(to: &fixture.presentation)
		}
	}

	@Test
	func setAndClearCueGroupHotKeysMatchAtomicBatch() throws {
		try withCueGroupCommandTemporaryDirectory { directory in
			let directInput = directory.appendingPathComponent("Direct.pro")
			let batchInput = directory.appendingPathComponent("Batch.pro")
			let fixture = try makeCueGroupCommandFixture()
			try fixture.presentation.serializedData().write(to: directInput)
			try fixture.presentation.serializedData().write(to: batchInput)
			let groupA = cueGroupGroupPath(fixture.groupA)
			let groupB = cueGroupGroupPath(fixture.groupB)

			try EditSetCueGroupHotKey.parse([
				directInput.path,
				"--path", groupA,
				"--code", "ansi_v",
				"--control-identifier", "remote.v",
			]).run()
			try EditSetCueGroupHotKey.parse([
				directInput.path,
				"--path", groupB,
				"--clear",
			]).run()

			try runCueGroupBatch(
				input: batchInput,
				directory: directory,
				name: "set-clear-hotkeys",
				operations: [
					[
						"command": "set-cue-group-hotkey",
						"path": groupA,
						"code": 22,
						"control-identifier": "remote.v",
					],
					[
						"command": "set-cue-group-hotkey",
						"path": groupB,
						"clear": true,
					],
				],
			)

			let direct = try loadedCueGroupPresentation(directInput)
			let batch = try loadedCueGroupPresentation(batchInput)
			#expect(cueGroupSnapshot(direct) == cueGroupSnapshot(batch))

			let directGroupA = try #require(direct.cueGroups.first { $0.group.uuid == fixture.groupA })
			#expect(directGroupA.group.hasHotKey)
			#expect(directGroupA.group.hotKey.code == .ansiV)
			#expect(directGroupA.group.hotKey.controlIdentifier == "remote.v")
			#expect(!directGroupA.group.hasApplicationGroupIdentifier)
			let batchGroupA = try #require(batch.cueGroups.first { $0.group.uuid == fixture.groupA })
			#expect(batchGroupA.group.hotKey.code == directGroupA.group.hotKey.code)
			#expect(batchGroupA.group.hotKey.controlIdentifier == directGroupA.group.hotKey.controlIdentifier)
			#expect(!batchGroupA.group.hasApplicationGroupIdentifier)

			let directGroupB = try #require(direct.cueGroups.first { $0.group.uuid == fixture.groupB })
			#expect(directGroupB.group.hasHotKey)
			#expect(directGroupB.group.hotKey.code.rawValue == 0)
			#expect(directGroupB.group.hotKey.controlIdentifier.isEmpty)
			#expect(!directGroupB.group.hasApplicationGroupIdentifier)
			let batchGroupB = try #require(batch.cueGroups.first { $0.group.uuid == fixture.groupB })
			#expect(batchGroupB.group.hasHotKey)
			#expect(batchGroupB.group.hotKey.code == directGroupB.group.hotKey.code)
			#expect(batchGroupB.group.hotKey.controlIdentifier == directGroupB.group.hotKey.controlIdentifier)
			#expect(!batchGroupB.group.hasApplicationGroupIdentifier)
		}
	}

	@Test
	func addSetMoveAndColorCommandsMatchAtomicBatch() throws {
		try withCueGroupCommandTemporaryDirectory { directory in
			let directInput = directory.appendingPathComponent("Direct.pro")
			let batchInput = directory.appendingPathComponent("Batch.pro")
			let fixture = try makeCueGroupCommandFixture()
			try fixture.presentation.serializedData().write(to: directInput)
			try fixture.presentation.serializedData().write(to: batchInput)

			let groupA = cueGroupGroupPath(fixture.groupA)
			let groupB = cueGroupGroupPath(fixture.groupB)
			let groupC = cueGroupGroupPath(fixture.groupC)
			let cueA1 = cueGroupCuePath(fixture.cueA1)
			let cueA2 = cueGroupCuePath(fixture.cueA2)
			let cueB1 = cueGroupCuePath(fixture.cueB1)
			let cueC1 = cueGroupCuePath(fixture.cueC1)
			let newGroup = "/cue_groups[name=New]"

			try EditAddCueGroup.parse([
				directInput.path,
				"--name", "New",
				"--cue", cueC1,
				"--color", "#123456",
				"--after", groupA,
			]).run()
			try EditSetCueGroupCues.parse([
				directInput.path,
				"--path", newGroup,
				"--cue", cueC1,
				"--cue", cueB1,
				"--transfer",
			]).run()
			try EditSetCueGroupCues.parse([
				directInput.path,
				"--path", groupA,
				"--cue", cueA2,
				"--leave-omitted-ungrouped",
			]).run()
			try EditMoveCueToGroup.parse([
				directInput.path,
				"--path", cueA1,
				"--group", groupB,
				"--first",
			]).run()
			try EditSetCueGroupColor.parse([
				directInput.path,
				"--path", groupB,
				"--color", "#ABCDEF",
			]).run()
			try EditSetCueGroupColor.parse([
				directInput.path,
				"--path", groupC,
				"--clear",
			]).run()

			try runCueGroupBatch(
				input: batchInput,
				directory: directory,
				name: "add-set-move-color",
				operations: [
					[
						"command": "add-cue-group",
						"name": "New",
						"cue": [cueC1],
						"color": "#123456",
						"after": groupA,
					],
					[
						"command": "set-cue-group-cues",
						"path": newGroup,
						"cue": [cueC1, cueB1],
						"transfer": true,
					],
					[
						"command": "set-cue-group-cues",
						"path": groupA,
						"cue": [cueA2],
						"leave-omitted-ungrouped": true,
					],
					[
						"command": "move-cue-to-group",
						"path": cueA1,
						"group": groupB,
						"first": true,
					],
					[
						"command": "set-cue-group-color",
						"path": groupB,
						"color": "#ABCDEF",
					],
					[
						"command": "set-cue-group-color",
						"path": groupC,
						"clear": true,
					],
				],
			)

			let direct = try loadedCueGroupPresentation(directInput)
			let batch = try loadedCueGroupPresentation(batchInput)
			let directSnapshot = cueGroupSnapshot(direct)
			#expect(directSnapshot == cueGroupSnapshot(batch))
			#expect(directSnapshot.groups.map(\.name) == ["A", "New", "B", "C"])
			#expect(directSnapshot.groups.map(\.cueNames) == [
				["A2"],
				["C1", "B1"],
				["A1"],
				[],
			])
			#expect(try directSnapshot.groups[1].color == colorSnapshot(DocumentEditor.color(hex: "#123456")))
			#expect(try directSnapshot.groups[2].color == colorSnapshot(DocumentEditor.color(hex: "#ABCDEF")))
			#expect(directSnapshot.groups[3].color == nil)
			#expect(directSnapshot.ungroupedCueNames.isEmpty)
			#expect(directSnapshot.arrangements[0].groupNames == ["A", "B", "A", "B", "C"])
		}
	}

	@Test
	func duplicateAndMoveRemovalPolicyMatchAtomicBatch() throws {
		try withCueGroupCommandTemporaryDirectory { directory in
			let directInput = directory.appendingPathComponent("Direct.pro")
			let batchInput = directory.appendingPathComponent("Batch.pro")
			let fixture = try makeCueGroupCommandFixture()
			try fixture.presentation.serializedData().write(to: directInput)
			try fixture.presentation.serializedData().write(to: batchInput)
			let groupA = cueGroupGroupPath(fixture.groupA)
			let groupB = cueGroupGroupPath(fixture.groupB)

			try EditDuplicateCueGroup.parse([
				directInput.path,
				"--path", groupB,
				"--name", "B Copy",
			]).run()
			try EditRemoveCueGroup.parse([
				directInput.path,
				"--path", groupB,
				"--move-cues-to", groupA,
				"--remove-from-arrangements",
			]).run()

			try runCueGroupBatch(
				input: batchInput,
				directory: directory,
				name: "duplicate-remove",
				operations: [
					[
						"command": "duplicate-cue-group",
						"path": groupB,
						"name": "B Copy",
					],
					[
						"command": "remove-cue-group",
						"path": groupB,
						"move-cues-to": groupA,
						"remove-from-arrangements": true,
					],
				],
			)

			let direct = try loadedCueGroupPresentation(directInput)
			let batch = try loadedCueGroupPresentation(batchInput)
			let directSnapshot = cueGroupSnapshot(direct)
			#expect(directSnapshot == cueGroupSnapshot(batch))
			#expect(directSnapshot.groups.map(\.name) == ["A", "B Copy", "C"])
			#expect(directSnapshot.groups.map(\.cueNames) == [
				["A1", "A2", "B1"],
				["B1 Copy"],
				["C1"],
			])
			#expect(directSnapshot.arrangements[0].groupNames == ["A", "A", "C"])
			try expectFreshDuplicatedBGroup(in: direct, sourceGroupUUID: fixture.groupB.string)
			try expectFreshDuplicatedBGroup(in: batch, sourceGroupUUID: fixture.groupB.string)
		}
	}

	@Test
	func removeRejectLeaveUngroupedAndDeletePoliciesMatchAtomicBatch() throws {
		try withCueGroupCommandTemporaryDirectory { directory in
			let fixture = try makeCueGroupCommandFixture()
			let groupB = cueGroupGroupPath(fixture.groupB)

			let rejectedDirect = directory.appendingPathComponent("RejectedDirect.pro")
			let rejectedBatch = directory.appendingPathComponent("RejectedBatch.pro")
			let originalBytes = try fixture.presentation.serializedData()
			try originalBytes.write(to: rejectedDirect)
			try originalBytes.write(to: rejectedBatch)
			#expect(throws: (any Error).self) {
				try EditRemoveCueGroup.parse([
					rejectedDirect.path,
					"--path", groupB,
				]).run()
			}
			#expect(try Data(contentsOf: rejectedDirect) == originalBytes)
			let rejectedManifest = try cueGroupBatchManifest(
				directory: directory,
				name: "rejected-remove",
				operations: [[
					"command": "remove-cue-group",
					"path": groupB,
				]],
			)
			#expect(throws: (any Error).self) {
				try EditApply.parse([
					rejectedBatch.path,
					"--file", rejectedManifest.path,
				]).run()
			}
			#expect(try Data(contentsOf: rejectedBatch) == originalBytes)

			for policy in [CueGroupRemovePolicyCase.leaveUngrouped, .delete] {
				let directInput = directory.appendingPathComponent("\(policy.name)Direct.pro")
				let batchInput = directory.appendingPathComponent("\(policy.name)Batch.pro")
				try originalBytes.write(to: directInput)
				try originalBytes.write(to: batchInput)

				try EditRemoveCueGroup.parse([
					directInput.path,
					"--path", groupB,
				] + policy.directFlags + ["--remove-from-arrangements"]).run()
				var operation = policy.batchOptions
				operation["command"] = "remove-cue-group"
				operation["path"] = groupB
				operation["remove-from-arrangements"] = true
				try runCueGroupBatch(
					input: batchInput,
					directory: directory,
					name: policy.name,
					operations: [operation],
				)

				let direct = try loadedCueGroupPresentation(directInput)
				let batch = try loadedCueGroupPresentation(batchInput)
				let directSnapshot = cueGroupSnapshot(direct)
				#expect(directSnapshot == cueGroupSnapshot(batch))
				#expect(directSnapshot.groups.map(\.name) == ["A", "C"])
				#expect(directSnapshot.arrangements[0].groupNames == ["A", "A", "C"])
				let retainsCue = direct.cues.contains { $0.uuid == fixture.cueB1 }
				#expect(retainsCue == policy.retainsCue)
				#expect(directSnapshot.ungroupedCueNames.contains("B1") == policy.retainsCue)
			}
		}
	}
}

private enum CueGroupRemovePolicyCase: Equatable {
	case leaveUngrouped
	case delete

	var name: String {
		switch self {
		case .leaveUngrouped: "leave-ungrouped"
		case .delete: "delete"
		}
	}

	var directFlags: [String] {
		switch self {
		case .leaveUngrouped: ["--leave-cues-ungrouped"]
		case .delete: ["--delete-cues"]
		}
	}

	var batchOptions: [String: Any] {
		switch self {
		case .leaveUngrouped: ["leave-cues-ungrouped": true]
		case .delete: ["delete-cues": true]
		}
	}

	var retainsCue: Bool {
		self == .leaveUngrouped
	}
}

private struct CueGroupCommandFixture {
	var presentation: Rv_Data_Presentation
	var groupA: Rv_Data_UUID
	var groupB: Rv_Data_UUID
	var groupC: Rv_Data_UUID
	var cueA1: Rv_Data_UUID
	var cueA2: Rv_Data_UUID
	var cueB1: Rv_Data_UUID
	var cueC1: Rv_Data_UUID
}

private struct CueGroupPresentationSnapshot: Equatable {
	struct Group: Equatable {
		var name: String
		var cueNames: [String]
		var color: CueGroupColorSnapshot?
		var hasHotKey: Bool
		var applicationGroupUUID: String?
	}

	struct Arrangement: Equatable {
		var name: String
		var groupNames: [String]
	}

	var groups: [Group]
	var cueNames: [String]
	var ungroupedCueNames: [String]
	var arrangements: [Arrangement]
	var selectedArrangementName: String?
}

private struct CueGroupColorSnapshot: Equatable {
	var red: Float
	var green: Float
	var blue: Float
	var alpha: Float
}

private func makeCueGroupCommandFixture() throws -> CueGroupCommandFixture {
	var presentation = DocumentFactory.presentation(name: "Cue-group command fixture")
	let prototype = presentation.cues[0]
	let cueA1 = makeCueGroupCommandCue(from: prototype, name: "A1", uuid: "CUE-A1")
	let cueA2 = makeCueGroupCommandCue(from: prototype, name: "A2", uuid: "CUE-A2")
	let cueB1 = makeCueGroupCommandCue(from: prototype, name: "B1", uuid: "CUE-B1")
	let cueC1 = makeCueGroupCommandCue(from: prototype, name: "C1", uuid: "CUE-C1")
	let groupA = cueGroupCommandUUID("GROUP-A")
	let groupB = cueGroupCommandUUID("GROUP-B")
	let groupC = cueGroupCommandUUID("GROUP-C")

	presentation.cues = [cueC1, cueA1, cueB1, cueA2]
	presentation.cueGroups = try [
		makeCueGroupCommandGroup(
			name: "A",
			uuid: groupA,
			cues: [cueA1.uuid, cueA2.uuid],
			color: "#804020",
			applicationGroupUUID: "APPLICATION-GROUP-A",
		),
		makeCueGroupCommandGroup(
			name: "B",
			uuid: groupB,
			cues: [cueB1.uuid],
			color: "#206080",
			applicationGroupUUID: "APPLICATION-GROUP-B",
		),
		makeCueGroupCommandGroup(
			name: "C",
			uuid: groupC,
			cues: [cueC1.uuid],
			color: "#408020",
			applicationGroupUUID: "APPLICATION-GROUP-C",
		),
	]
	var arrangement = Rv_Data_Presentation.Arrangement()
	arrangement.uuid = cueGroupCommandUUID("ARRANGEMENT")
	arrangement.name = "Service"
	arrangement.groupIdentifiers = [groupA, groupB, groupA, groupB, groupC]
	presentation.arrangements = [arrangement]
	presentation.selectedArrangement = arrangement.uuid

	return CueGroupCommandFixture(
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

private func makeCueGroupCommandCue(
	from prototype: Rv_Data_Cue,
	name: String,
	uuid: String,
) -> Rv_Data_Cue {
	var cue = prototype
	cue.uuid = cueGroupCommandUUID(uuid)
	cue.name = name
	for actionIndex in cue.actions.indices {
		cue.actions[actionIndex].uuid = cueGroupCommandUUID("ACTION-\(uuid)-\(actionIndex)")
		cue.actions[actionIndex].label.text = name
		if cue.actions[actionIndex].type == .presentationSlide {
			cue.actions[actionIndex].slide.presentation.baseSlide.uuid = cueGroupCommandUUID("SLIDE-\(uuid)-\(actionIndex)")
		}
	}
	return cue
}

private func makeCueGroupCommandGroup(
	name: String,
	uuid: Rv_Data_UUID,
	cues: [Rv_Data_UUID],
	color: String,
	applicationGroupUUID: String,
) throws -> Rv_Data_Presentation.CueGroup {
	var group = Rv_Data_Group()
	group.uuid = uuid
	group.name = name
	group.color = try DocumentEditor.color(hex: color)
	group.hotKey = Rv_Data_HotKey()
	group.applicationGroupIdentifier = cueGroupCommandUUID(applicationGroupUUID)
	var cueGroup = Rv_Data_Presentation.CueGroup()
	cueGroup.group = group
	cueGroup.cueIdentifiers = cues
	return cueGroup
}

private func cueGroupSnapshot(_ presentation: Rv_Data_Presentation) -> CueGroupPresentationSnapshot {
	let cuesByUUID = Dictionary(uniqueKeysWithValues: presentation.cues.map { ($0.uuid.string, $0) })
	let groupNamesByUUID = Dictionary(uniqueKeysWithValues: presentation.cueGroups.map {
		($0.group.uuid.string, $0.group.name)
	})
	let referencedCueUUIDs = Set(presentation.cueGroups.flatMap { $0.cueIdentifiers.map(\.string) })
	let groups = presentation.cueGroups.map { cueGroup in
		CueGroupPresentationSnapshot.Group(
			name: cueGroup.group.name,
			cueNames: cueGroup.cueIdentifiers.map { cuesByUUID[$0.string]?.name ?? "<unknown>" },
			color: cueGroup.group.hasColor ? colorSnapshot(cueGroup.group.color) : nil,
			hasHotKey: cueGroup.group.hasHotKey,
			applicationGroupUUID: cueGroup.group.hasApplicationGroupIdentifier
				? cueGroup.group.applicationGroupIdentifier.string
				: nil,
		)
	}
	let arrangements = presentation.arrangements.map { arrangement in
		CueGroupPresentationSnapshot.Arrangement(
			name: arrangement.name,
			groupNames: arrangement.groupIdentifiers.map {
				groupNamesByUUID[$0.string] ?? "<unknown:\($0.string)>"
			},
		)
	}
	let selectedName = presentation.hasSelectedArrangement
		? presentation.arrangements.first { $0.uuid == presentation.selectedArrangement }?.name
		: nil
	return CueGroupPresentationSnapshot(
		groups: groups,
		cueNames: presentation.cues.map(\.name),
		ungroupedCueNames: presentation.cues.compactMap {
			referencedCueUUIDs.contains($0.uuid.string) ? nil : $0.name
		},
		arrangements: arrangements,
		selectedArrangementName: selectedName,
	)
}

private func colorSnapshot(_ color: Rv_Data_Color) -> CueGroupColorSnapshot {
	CueGroupColorSnapshot(
		red: color.red,
		green: color.green,
		blue: color.blue,
		alpha: color.alpha,
	)
}

private func expectCanonical(
	_ output: EditPathOutput,
	in presentation: Rv_Data_Presentation,
) throws {
	let selection = try ComponentResolver.resolve(
		ComponentPath(output.path),
		in: transientDocument(for: presentation),
	)
	#expect(selection.canonicalPath == output.path)
}

private func expectFreshDuplicatedBGroup(
	in presentation: Rv_Data_Presentation,
	sourceGroupUUID: String,
) throws {
	let copyGroup = try #require(presentation.cueGroups.first { $0.group.name == "B Copy" })
	let originalCue = try #require(presentation.cues.first { $0.name == "B1" })
	let copiedCue = try #require(presentation.cues.first { $0.name == "B1 Copy" })
	#expect(copyGroup.group.uuid.string != sourceGroupUUID)
	#expect(copyGroup.cueIdentifiers == [copiedCue.uuid])
	#expect(copiedCue.uuid != originalCue.uuid)
	#expect(copiedCue.actions[0].uuid != originalCue.actions[0].uuid)
	#expect(
		copiedCue.actions[0].slide.presentation.baseSlide.uuid !=
			originalCue.actions[0].slide.presentation.baseSlide.uuid,
	)
	#expect(copyGroup.group.hasColor)
	#expect(copyGroup.group.hasHotKey)
	#expect(!copyGroup.group.hasApplicationGroupIdentifier)
}

private func cueGroupCommandUUID(_ string: String) -> Rv_Data_UUID {
	var uuid = Rv_Data_UUID()
	uuid.string = string
	return uuid
}

private func cueGroupGroupPath(_ uuid: Rv_Data_UUID) -> String {
	"/cue_groups[uuid=\(uuid.string)]"
}

private func cueGroupCuePath(_ uuid: Rv_Data_UUID) -> String {
	"/cues[uuid=\(uuid.string)]"
}

private func loadedCueGroupPresentation(_ url: URL) throws -> Rv_Data_Presentation {
	guard case let .presentation(presentation) = try DocumentLoader.load(from: url).payload else {
		throw CocoaError(.fileReadCorruptFile)
	}
	return presentation
}

private func runCueGroupBatch(
	input: URL,
	directory: URL,
	name: String,
	operations: [[String: Any]],
) throws {
	let manifest = try cueGroupBatchManifest(
		directory: directory,
		name: name,
		operations: operations,
	)
	try EditApply.parse([
		input.path,
		"--file", manifest.path,
	]).run()
}

private func cueGroupBatchManifest(
	directory: URL,
	name: String,
	operations: [[String: Any]],
) throws -> URL {
	let manifest = directory.appendingPathComponent("\(name).json")
	try JSONSerialization.data(
		withJSONObject: operations,
		options: [.prettyPrinted, .sortedKeys],
	).write(to: manifest)
	return manifest
}

private func withCueGroupCommandTemporaryDirectory<Result>(
	_ operation: (URL) throws -> Result,
) throws -> Result {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("pro-crud-cue-group-command-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: directory) }
	return try operation(directory)
}
