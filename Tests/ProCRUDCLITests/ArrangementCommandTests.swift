import ArgumentParser
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite(
	"Arrangement commands",
	.timeLimit(.minutes(2)),
)
struct ArrangementCommandTests {
	@Test
	func helpAndParsersExposeArrangementOptionsAndEditCommands() throws {
		let render = try Render.parse([
			"Song.pro",
			"--arrangement", "selected",
		])
		#expect(render.arrangement == "selected")
		#expect(Render.helpMessage().contains("--arrangement"))
		#expect(Render.helpMessage().contains("UUID, selected, or native"))

		let groupA = "/cue_groups[uuid=GROUP-A]"
		let groupB = "/cue_groups[uuid=GROUP-B]"
		let add = try EditAddArrangement.parse([
			"Song.pro",
			"--name", "Evening",
			"--group", groupA,
			"--group", groupB,
			"--group", groupA,
			"--select",
		])
		#expect(add.name == "Evening")
		#expect(add.group == [groupA, groupB, groupA])
		#expect(add.select)

		let set = try EditSetArrangementGroups.parse([
			"Song.pro",
			"--path", "/arrangements[index=0]",
			"--empty",
		])
		#expect(set.empty)
		#expect(set.group.isEmpty)

		let select = try EditSelectArrangement.parse([
			"Song.pro",
			"--path", "/arrangements[index=0]",
		])
		#expect(select.path == "/arrangements[index=0]")
		_ = try EditClearSelectedArrangement.parse(["Song.pro"])

		let editHelp = Edit.helpMessage()
		#expect(editHelp.contains("add-arrangement"))
		#expect(editHelp.contains("set-arrangement-groups"))
		#expect(editHelp.contains("select-arrangement"))
		#expect(editHelp.contains("clear-selected-arrangement"))
		#expect(EditAddArrangement.helpMessage().contains("--group"))
		#expect(EditAddArrangement.helpMessage().contains("--empty"))
		#expect(EditAddArrangement.helpMessage().contains("--select"))
	}

	@Test
	func semanticDumpReportsSelectionAndRepeatedGroupSequence() throws {
		var fixture = makeArrangementCommandFixture()
		let arrangement = makeCommandArrangement(
			name: "A, B, A",
			uuid: "ARRANGEMENT-ABA",
			groups: [fixture.groupA, fixture.groupB, fixture.groupA],
		)
		fixture.presentation.arrangements = [arrangement]
		fixture.presentation.selectedArrangement = arrangement.uuid
		let document = ProPresenterDocument(
			payload: .presentation(fixture.presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/ArrangementDump.pro")),
		)

		let text = try Dump.parse(["/tmp/ArrangementDump.pro"]).output(document: document)
		#expect(text.contains("Selected arrangement UUID: \(arrangement.uuid.string)"))
		#expect(text.contains("A, B, A (\(arrangement.uuid.string)) [selected]"))

		let json = try Dump.parse(["/tmp/ArrangementDump.pro", "--format", "json"]).output(document: document)
		let report = try JSONDecoder().decode(DocumentDumpReport.self, from: Data(json.utf8))
		#expect(report.presentation?.selectedArrangementUUID == arrangement.uuid.string)
		#expect(report.presentation?.arrangements.first?.groups.map(\.uuid) == [
			fixture.groupA.string,
			fixture.groupB.string,
			fixture.groupA.string,
		])
	}

	@Test
	func addArrangementPreservesRepeatedGroupsAndSelectsTheResult() throws {
		try withArrangementTemporaryDirectory { directory in
			let input = directory.appendingPathComponent("Song.pro")
			let fixture = makeArrangementCommandFixture()
			try fixture.presentation.serializedData().write(to: input)

			try EditAddArrangement.parse([
				input.path,
				"--name", "A, B, A",
				"--group", groupPath(fixture.groupA),
				"--group", groupPath(fixture.groupB),
				"--group", groupPath(fixture.groupA),
				"--select",
			]).run()

			let presentation = try loadedArrangementPresentation(input)
			let arrangement = try #require(presentation.arrangements.first)
			#expect(arrangement.name == "A, B, A")
			#expect(!arrangement.uuid.string.isEmpty)
			#expect(arrangement.groupIdentifiers == [fixture.groupA, fixture.groupB, fixture.groupA])
			#expect(presentation.hasSelectedArrangement)
			#expect(presentation.selectedArrangement == arrangement.uuid)
		}
	}

	@Test
	func selectSetEmptyAndClearCommandsPreserveOptionalSelectionSemantics() throws {
		try withArrangementTemporaryDirectory { directory in
			let input = directory.appendingPathComponent("Song.pro")
			var fixture = makeArrangementCommandFixture()
			let arrangement = makeCommandArrangement(
				name: "Editable",
				uuid: "ARRANGEMENT-EDITABLE",
				groups: [fixture.groupA, fixture.groupB, fixture.groupA],
			)
			fixture.presentation.arrangements = [arrangement]
			try fixture.presentation.serializedData().write(to: input)
			let path = arrangementPath(arrangement.uuid)

			try EditSelectArrangement.parse([
				input.path,
				"--path", path,
			]).run()
			#expect(try loadedArrangementPresentation(input).selectedArrangement == arrangement.uuid)

			try EditSetArrangementGroups.parse([
				input.path,
				"--path", path,
				"--empty",
			]).run()
			let emptied = try loadedArrangementPresentation(input)
			#expect(emptied.arrangements[0].groupIdentifiers.isEmpty)
			#expect(emptied.selectedArrangement == arrangement.uuid)

			try EditClearSelectedArrangement.parse([input.path]).run()
			let cleared = try loadedArrangementPresentation(input)
			#expect(!cleared.hasSelectedArrangement)
		}
	}

	@Test
	func genericDuplicateCreatesFreshArrangementIdentityWithExactGroupReferences() throws {
		try withArrangementTemporaryDirectory { directory in
			let input = directory.appendingPathComponent("Song.pro")
			var fixture = makeArrangementCommandFixture()
			let source = makeCommandArrangement(
				name: "Source",
				uuid: "ARRANGEMENT-SOURCE",
				groups: [fixture.groupA, fixture.groupB, fixture.groupA],
			)
			fixture.presentation.arrangements = [source]
			fixture.presentation.selectedArrangement = source.uuid
			try fixture.presentation.serializedData().write(to: input)

			try EditDuplicate.parse([
				input.path,
				"--path", arrangementPath(source.uuid),
			]).run()

			let presentation = try loadedArrangementPresentation(input)
			#expect(presentation.arrangements.count == 2)
			let duplicate = presentation.arrangements[1]
			#expect(duplicate.uuid != source.uuid)
			#expect(!duplicate.uuid.string.isEmpty)
			#expect(duplicate.name == "Source Copy")
			#expect(duplicate.groupIdentifiers == source.groupIdentifiers)
			#expect(presentation.selectedArrangement == source.uuid)
		}
	}

	@Test
	func renderJSONUsesRequestedArrangementOrderAndReportsMetadata() throws {
		try withArrangementTemporaryDirectory { directory in
			let input = directory.appendingPathComponent("Song.pro")
			let output = directory.appendingPathComponent("Rendering.json")
			var fixture = makeArrangementCommandFixture()
			let arrangement = makeCommandArrangement(
				name: "A, B, A",
				uuid: "ARRANGEMENT-ABA",
				groups: [fixture.groupA, fixture.groupB, fixture.groupA],
			)
			fixture.presentation.arrangements = [arrangement]
			try fixture.presentation.serializedData().write(to: input)

			try Render.parse([
				input.path,
				"--format", "json",
				"--arrangement", arrangement.uuid.string,
				"--output", output.path,
			]).run()

			let rendering = try JSONDecoder().decode(
				EffectiveRendering.self,
				from: Data(contentsOf: output),
			)
			let presentation = try #require(rendering.presentations.first)
			#expect(presentation.arrangement?.name == arrangement.name)
			#expect(presentation.arrangement?.uuid == arrangement.uuid.string)
			#expect(presentation.arrangement?.path.contains(arrangement.uuid.string) == true)
			#expect(presentation.slides.map(\.index) == [0, 1, 2, 3, 4])
			#expect(presentation.slides.map(\.name) == ["A1", "A2", "B1", "A1", "A2"])
		}
	}

	@Test
	func editApplyGroupArrayMatchesRepeatedDirectOptions() throws {
		try withArrangementTemporaryDirectory { directory in
			let directInput = directory.appendingPathComponent("Direct.pro")
			let batchInput = directory.appendingPathComponent("Batch.pro")
			let manifest = directory.appendingPathComponent("Edits.json")
			var fixture = makeArrangementCommandFixture()
			let arrangement = makeCommandArrangement(
				name: "Editable",
				uuid: "ARRANGEMENT-EDITABLE",
				groups: [],
			)
			fixture.presentation.arrangements = [arrangement]
			try fixture.presentation.serializedData().write(to: directInput)
			try fixture.presentation.serializedData().write(to: batchInput)
			let path = arrangementPath(arrangement.uuid)
			let groups = [groupPath(fixture.groupA), groupPath(fixture.groupB), groupPath(fixture.groupA)]

			try EditSetArrangementGroups.parse([
				directInput.path,
				"--path", path,
				"--group", groups[0],
				"--group", groups[1],
				"--group", groups[2],
			]).run()

			let operations: [[String: Any]] = [[
				"command": "set-arrangement-groups",
				"path": path,
				"group": groups,
			]]
			try JSONSerialization.data(withJSONObject: operations, options: [.prettyPrinted]).write(to: manifest)
			try EditApply.parse([
				batchInput.path,
				"--file", manifest.path,
			]).run()

			let direct = try loadedArrangementPresentation(directInput)
			let batch = try loadedArrangementPresentation(batchInput)
			#expect(direct.arrangements[0].groupIdentifiers == [fixture.groupA, fixture.groupB, fixture.groupA])
			#expect(batch.arrangements[0].groupIdentifiers == direct.arrangements[0].groupIdentifiers)
		}
	}
}

private struct ArrangementCommandFixture {
	var presentation: Rv_Data_Presentation
	var groupA: Rv_Data_UUID
	var groupB: Rv_Data_UUID
	var groupC: Rv_Data_UUID
}

private func makeArrangementCommandFixture() -> ArrangementCommandFixture {
	var presentation = DocumentFactory.presentation(name: "Arrangement command fixture")
	let prototype = presentation.cues[0]
	let cueA1 = makeCommandCue(from: prototype, name: "A1", uuid: "CUE-A1")
	let cueA2 = makeCommandCue(from: prototype, name: "A2", uuid: "CUE-A2")
	let cueB1 = makeCommandCue(from: prototype, name: "B1", uuid: "CUE-B1")
	let nativeLeftover = makeCommandCue(from: prototype, name: "Native leftover", uuid: "CUE-C1")
	let groupA = commandUUID("GROUP-A")
	let groupB = commandUUID("GROUP-B")
	let groupC = commandUUID("GROUP-C")

	presentation.cues = [nativeLeftover, cueA1, cueB1, cueA2]
	presentation.cueGroups = [
		makeCommandCueGroup(name: "A", uuid: groupA, cues: [cueA1.uuid, cueA2.uuid]),
		makeCommandCueGroup(name: "B", uuid: groupB, cues: [cueB1.uuid]),
		makeCommandCueGroup(name: "C", uuid: groupC, cues: [nativeLeftover.uuid]),
	]
	presentation.arrangements = []
	presentation.clearSelectedArrangement()
	return ArrangementCommandFixture(
		presentation: presentation,
		groupA: groupA,
		groupB: groupB,
		groupC: groupC,
	)
}

private func makeCommandCue(
	from prototype: Rv_Data_Cue,
	name: String,
	uuid: String,
) -> Rv_Data_Cue {
	var cue = prototype
	cue.uuid = commandUUID(uuid)
	cue.name = name
	for actionIndex in cue.actions.indices {
		cue.actions[actionIndex].uuid = commandUUID("ACTION-\(uuid)-\(actionIndex)")
		cue.actions[actionIndex].label.text = name
		if cue.actions[actionIndex].type == .presentationSlide {
			cue.actions[actionIndex].slide.presentation.baseSlide.uuid = commandUUID("SLIDE-\(uuid)-\(actionIndex)")
		}
	}
	return cue
}

private func makeCommandCueGroup(
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

private func makeCommandArrangement(
	name: String,
	uuid: String,
	groups: [Rv_Data_UUID],
) -> Rv_Data_Presentation.Arrangement {
	var arrangement = Rv_Data_Presentation.Arrangement()
	arrangement.uuid = commandUUID(uuid)
	arrangement.name = name
	arrangement.groupIdentifiers = groups
	return arrangement
}

private func commandUUID(_ string: String) -> Rv_Data_UUID {
	var uuid = Rv_Data_UUID()
	uuid.string = string
	return uuid
}

private func groupPath(_ uuid: Rv_Data_UUID) -> String {
	"/cue_groups[uuid=\(uuid.string)]"
}

private func arrangementPath(_ uuid: Rv_Data_UUID) -> String {
	"/arrangements[uuid=\(uuid.string)]"
}

private func loadedArrangementPresentation(_ url: URL) throws -> Rv_Data_Presentation {
	guard case let .presentation(presentation) = try DocumentLoader.load(from: url).payload else {
		throw CocoaError(.fileReadCorruptFile)
	}
	return presentation
}

private func withArrangementTemporaryDirectory<Result>(
	_ operation: (URL) throws -> Result,
) throws -> Result {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("pro-crud-arrangement-command-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: directory) }
	return try operation(directory)
}
