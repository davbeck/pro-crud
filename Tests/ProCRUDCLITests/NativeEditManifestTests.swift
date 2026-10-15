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
			["stream": stream.uuidString, "op": "rename-cue-group", "group": group.uuidString, "name": "Verse"],
			["stream": stream.uuidString, "op": "set-arrangement-groups", "arrangement": arrangement.uuidString, "groups": [group.uuidString, group.uuidString]],
			["stream": stream.uuidString, "op": "set-arrangement-groups", "arrangement": arrangement.uuidString, "groups": []],
		]
		let operations = try decode(instructions)
		#expect(operations.map(\.documentID) == Array(repeating: stream, count: instructions.count))
		#expect(operations.map(\.edit) == [.copyrightTitle(""), .notes("Operator notes"), .slideNotes(actionID: action, content: .text("Rich notes")), .moveCue(cue, after: anchor), .cueGroupName(group, "Verse"), .arrangementGroups(arrangement, [group, group]), .arrangementGroups(arrangement, [])])
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
	}

	private func decode(_ operations: [[String: Any]], version: Int = 1) throws -> [NativePresentationOperation] {
		let data = try JSONSerialization.data(withJSONObject: ["version": version, "operations": operations])
		return try NativeEditManifest.decode(data, relativeTo: URL(fileURLWithPath: "/tmp"))
	}
}
