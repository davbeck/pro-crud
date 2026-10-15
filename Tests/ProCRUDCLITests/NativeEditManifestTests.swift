import ArgumentParser
import Foundation
import ProCRUDCore
import Testing
@testable import ProCRUDCLI

@Suite("Native edit manifest")
struct NativeEditManifestTests {
	@Test func orderedOperationsDecodeWithoutImplicitConversionOrFieldLoss() throws {
		let stream = UUID(), group = UUID(), cue = UUID(), anchor = UUID(), arrangement = UUID(), action = UUID()
		let instructions: [[String: Any]] = [
			["stream": stream.uuidString, "op": "set-copyright-title", "title": ""],
			["stream": stream.uuidString, "op": "set-notes", "text": "Operator notes"],
			["stream": stream.uuidString, "op": "set-slide-notes", "action": action.uuidString, "text": "Rich notes"],
			["stream": stream.uuidString, "op": "move-cue", "cue": cue.uuidString, "after": anchor.uuidString],
			["stream": stream.uuidString, "op": "transfer-cue", "cue": cue.uuidString, "group": group.uuidString],
			["stream": stream.uuidString, "op": "rename-cue-group", "group": group.uuidString, "name": "Verse"],
			["stream": stream.uuidString, "op": "set-arrangement-groups", "arrangement": arrangement.uuidString, "groups": [group.uuidString, group.uuidString]],
			["stream": stream.uuidString, "op": "set-arrangement-groups", "arrangement": arrangement.uuidString, "groups": []],
		]
		let operations = try decode(instructions)
		#expect(operations.map(\.documentID) == Array(repeating: stream, count: instructions.count))
		#expect(operations.map(\.edit) == [.copyrightTitle(""), .notes("Operator notes"), .slideNotes(actionID: action, content: .text("Rich notes")), .moveCue(cue, after: anchor), .transferCue(cue, to: group, after: nil), .cueGroupName(group, "Verse"), .arrangementGroups(arrangement, [group, group]), .arrangementGroups(arrangement, [])])
		let base = ["/tmp/Exact", "--file", "/tmp/native-edits.json", "--registry", "/tmp/registry-v1.sqlite3"]
		#expect(try ProCRUD.parseAsRoot(["workspace", "apply"] + base) is WorkspaceApply)
		#expect(throws: (any Error).self) { try WorkspaceApply.parse(base + ["--target-version", "21"]) }
	}

	@Test func unsupportedVersionsFieldsAndMalformedOperationsFail() throws {
		let valid: [String: Any] = ["stream": UUID().uuidString, "op": "set-notes", "text": "Notes"]
		#expect(throws: ValidationError.self) { try decode([valid], version: 2) }
		#expect(throws: ValidationError.self) { try decode([]) }
		for replacement: [String: Any] in [
			["stream": "bad"], ["op": "set-media"], ["target-version": 21], ["typo": "ignored?"], ["text": NSNull()],
		] {
			#expect(throws: ValidationError.self) { try decode([valid.merging(replacement) { _, new in new }]) }
		}
		#expect(throws: ValidationError.self) { try decode([["stream": UUID().uuidString, "op": "set-slide-notes", "action": UUID().uuidString, "text": "X", "rtfFile": "Notes.rtf"]]) }
	}

	@Test func richTextFilesResolveRelativeToTheManifest() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let data = Data("{\\rtf1 Notes}".utf8)
		try data.write(to: directory.appendingPathComponent("Notes.rtf"))
		let action = UUID()
		let instructions: [[String: Any]] = [["stream": UUID().uuidString, "op": "set-slide-notes", "action": action.uuidString, "rtfFile": "Notes.rtf"]]
		let bytes = try JSONSerialization.data(withJSONObject: ["version": 1, "operations": instructions])
		let result = try NativeEditManifest.decode(bytes, relativeTo: directory)
		#expect(result.first?.edit == .slideNotes(actionID: action, content: .rtf(data)))
		let element = UUID()
		let textInstructions: [[String: Any]] = [["stream": UUID().uuidString, "op": "set-text", "action": action.uuidString, "element": element.uuidString, "rtfFile": "Notes.rtf"]]
		let textBytes = try JSONSerialization.data(withJSONObject: ["version": 1, "operations": textInstructions])
		#expect(try NativeEditManifest.decode(textBytes, relativeTo: directory).first?.edit == .slideText(actionID: action, elementID: element, content: .rtf(data)))
	}

	@Test func nativeTextRequiresScopedIDsAndOneContentSource() throws {
		let stream = UUID(), action = UUID(), element = UUID()
		let valid: [String: Any] = ["stream": stream.uuidString, "op": "set-text", "action": action.uuidString, "element": element.uuidString, "text": ""]
		#expect(try decode([valid]).first?.edit == .slideText(actionID: action, elementID: element, content: .text("")))
		#expect(throws: ValidationError.self) { try decode([valid.merging(["rtfFile": "Notes.rtf"]) { _, new in new }]) }
		#expect(throws: ValidationError.self) { try decode([valid.filter { $0.key != "element" }]) }
		let base = ["/tmp/Exact", "--stream", stream.uuidString, "--action", action.uuidString, "--element", element.uuidString, "--registry", "/tmp/registry-v1.sqlite3"]
		#expect(try ProCRUD.parseAsRoot(["workspace", "set-text"] + base + ["--text", ""]) is WorkspaceSetText)
		#expect(throws: (any Error).self) { try WorkspaceSetText.parse(base) }
		#expect(throws: (any Error).self) { try WorkspaceSetText.parse(base + ["--text", "X", "--rtf", "Notes.rtf"]) }
	}

	@Test func arrangementCreationRequiresStableIdentitiesExplicitGroupsAndSelectionPolicy() throws {
		let stream = UUID(), arrangement = UUID(), copy = UUID(), group = UUID()
		let create: [String: Any] = ["stream": stream.uuidString, "op": "add-arrangement", "arrangement": arrangement.uuidString, "name": "Created", "groups": [group.uuidString, group.uuidString], "select": false]
		let duplicate: [String: Any] = ["stream": stream.uuidString, "op": "duplicate-arrangement", "arrangement": arrangement.uuidString, "newArrangement": copy.uuidString, "name": "Copy", "select": true]
		let remove: [String: Any] = ["stream": stream.uuidString, "op": "remove-arrangement", "arrangement": copy.uuidString]
		let operations = try decode([create, duplicate, remove])
		#expect(operations.map(\.edit) == [.createArrangement(id: arrangement, name: "Created", groups: [group, group], select: false), .duplicateArrangement(arrangement, newID: copy, name: "Copy", select: true), .removeArrangement(copy)])
		for key in ["arrangement", "groups", "select"] {
			var missing = create; missing.removeValue(forKey: key)
			#expect(throws: ValidationError.self) { try decode([missing]) }
		}
		var missing = duplicate; missing.removeValue(forKey: "newArrangement")
		#expect(throws: ValidationError.self) { try decode([missing]) }
	}

	@Test func arrangementSelectionRequiresExplicitUUIDOrNullForMaster() throws {
		let stream = UUID(), arrangement = UUID()
		let operations = try decode([
			["stream": stream.uuidString, "op": "rename-arrangement", "arrangement": arrangement.uuidString, "name": "Verse"],
			["stream": stream.uuidString, "op": "select-arrangement", "arrangement": arrangement.uuidString],
			["stream": stream.uuidString, "op": "select-arrangement", "arrangement": NSNull()],
		])
		#expect(operations.map(\.edit) == [.arrangementName(arrangement, "Verse"), .selectedArrangement(arrangement), .selectedArrangement(nil)])
		#expect(throws: ValidationError.self) { try decode([["stream": stream.uuidString, "op": "select-arrangement"]]) }
		#expect(throws: ValidationError.self) { try decode([["stream": stream.uuidString, "op": "select-arrangement", "arrangement": "Master"]]) }
	}

	@Test func arrangementUnlinkAndDeletionRequireExactIdentities() throws {
		let stream = UUID(), action = UUID(), arrangement = UUID()
		let unlink: [String: Any] = ["stream": stream.uuidString, "op": "clear-document-action-arrangement", "action": action.uuidString]
		let remove: [String: Any] = ["stream": stream.uuidString, "op": "remove-arrangement", "arrangement": arrangement.uuidString]
		#expect(try decode([unlink, remove]).map(\.edit) == [.clearDocumentActionArrangement(action), .removeArrangement(arrangement)])
		#expect(throws: ValidationError.self) { try decode([unlink.filter { $0.key != "action" }]) }
		#expect(throws: ValidationError.self) { try decode([remove.filter { $0.key != "arrangement" }]) }
		#expect(try ProCRUD.parseAsRoot(["workspace", "arrangement-references", "/tmp/Exact"]) is WorkspaceArrangementReferences)
	}

	private func decode(_ operations: [[String: Any]], version: Int = 1) throws -> [NativePresentationOperation] {
		let data = try JSONSerialization.data(withJSONObject: ["version": version, "operations": operations])
		return try NativeEditManifest.decode(data, relativeTo: URL(fileURLWithPath: "/tmp"))
	}
}
