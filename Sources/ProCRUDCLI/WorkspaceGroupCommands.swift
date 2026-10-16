import ArgumentParser
import Foundation
import ProCRUDCore

struct WorkspaceRenameCueGroup: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "rename-cue-group", abstract: "Rename an existing native cue group without changing its identity, color, hotkey or arrangements. Quit ProPresenter and stop workspace helpers first.")
	@Argument(help: "Exact registered local native workspace root.") var input: String
	@Option(help: "Shared Presentation stream UUID.") var stream: String
	@Option(help: "Existing native cue-group UUID.") var group: String
	@Option(help: "Nonempty replacement group name.") var name: String
	@Option(help: "Exact local registry-v1.sqlite3 path.") var registry: String

	func validate() throws {
		guard UUID(uuidString: stream) != nil, UUID(uuidString: group) != nil else { throw ValidationError("--stream and --group require UUIDs.") }
		guard !name.isEmpty else { throw ValidationError("--name requires a nonempty group name.") }
	}

	func run() throws {
		guard let streamID = UUID(uuidString: stream), let groupID = UUID(uuidString: group) else { throw ValidationError("--stream and --group require UUIDs.") }
		let receipts = try NativeLocalWorkspaceWriter.edit(.cueGroupName(groupID, name), documentID: streamID, in: URL(fileURLWithPath: input), registry: URL(fileURLWithPath: registry))
		try print(prettyJSON(Result(documentID: streamID, groupID: groupID, changed: !receipts.isEmpty, receipts: receipts)))
	}

	private struct Result: Encodable {
		let documentID: UUID
		let groupID: UUID
		let changed: Bool
		let receipts: [NativeLocalCommitReceipt]
	}
}

struct WorkspaceSetArrangementGroups: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "set-arrangement-groups", abstract: "Set an existing native arrangement's ordered group occurrences, retaining repeated groups and native history. Quit ProPresenter and stop workspace helpers first.")
	@Argument(help: "Exact registered local native workspace root.") var input: String
	@Option(help: "Shared Presentation stream UUID.") var stream: String
	@Option(help: "Existing arrangement UUID.") var arrangement: String
	@Option(name: .customLong("group"), help: "Group UUID in the desired sequence. Repeat this option for each occurrence, including duplicates.") var groups: [String] = []
	@Flag(help: "Make the arrangement empty instead of supplying --group options.") var clear = false
	@Option(help: "Exact local registry-v1.sqlite3 path.") var registry: String

	func validate() throws {
		guard [stream, arrangement].allSatisfy({ UUID(uuidString: $0) != nil }), groups.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw ValidationError("--stream, --arrangement and every --group require UUIDs.") }
		guard clear != !groups.isEmpty else { throw ValidationError("Provide ordered --group options or --clear.") }
	}

	func run() throws {
		guard let streamID = UUID(uuidString: stream), let arrangementID = UUID(uuidString: arrangement) else { throw ValidationError("--stream and --arrangement require UUIDs.") }
		let ids = try groups.map { value in
			guard let id = UUID(uuidString: value) else { throw ValidationError("Every --group requires a UUID.") }
			return id
		}
		let receipts = try NativeLocalWorkspaceWriter.edit(.arrangementGroups(arrangementID, ids), documentID: streamID, in: URL(fileURLWithPath: input), registry: URL(fileURLWithPath: registry))
		try print(prettyJSON(Result(documentID: streamID, arrangementID: arrangementID, groupIDs: ids, changed: !receipts.isEmpty, receipts: receipts)))
	}

	private struct Result: Encodable {
		let documentID: UUID
		let arrangementID: UUID
		let groupIDs: [UUID]
		let changed: Bool
		let receipts: [NativeLocalCommitReceipt]
	}
}

struct WorkspaceTransferCue: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "transfer-cue", abstract: "Move an existing cue into a native group, preserving cue/placement identity. An emptied source group and its arrangement occurrences are removed. Quit ProPresenter and stop workspace helpers first.")
	@Argument(help: "Exact registered local native workspace root.") var input: String
	@Option(help: "Shared Presentation stream UUID.") var stream: String
	@Option(help: "Existing cue UUID.") var cue: String
	@Option(help: "Destination cue-group UUID.") var group: String
	@Option(help: "Cue UUID in the destination group to insert after. Omit to append.") var after: String?
	@Option(help: "Exact local registry-v1.sqlite3 path.") var registry: String

	func validate() throws {
		guard [stream, cue, group].allSatisfy({ UUID(uuidString: $0) != nil }), after.map({ UUID(uuidString: $0) != nil }) ?? true else { throw ValidationError("--stream, --cue, --group and --after require UUIDs.") }
	}

	func run() throws {
		guard let streamID = UUID(uuidString: stream), let cueID = UUID(uuidString: cue), let groupID = UUID(uuidString: group) else { throw ValidationError("--stream, --cue and --group require UUIDs.") }
		let anchor = after.flatMap(UUID.init(uuidString:))
		let receipts = try NativeLocalWorkspaceWriter.edit(.transferCue(cueID, to: groupID, after: anchor), documentID: streamID, in: URL(fileURLWithPath: input), registry: URL(fileURLWithPath: registry))
		try print(prettyJSON(Result(documentID: streamID, cueID: cueID, groupID: groupID, afterCueID: anchor, changed: !receipts.isEmpty, receipts: receipts)))
	}

	private struct Result: Encodable {
		let documentID: UUID
		let cueID: UUID
		let groupID: UUID
		let afterCueID: UUID?
		let changed: Bool
		let receipts: [NativeLocalCommitReceipt]
	}
}
