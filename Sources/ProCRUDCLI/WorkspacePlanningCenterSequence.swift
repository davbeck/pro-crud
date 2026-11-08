import ArgumentParser
import Foundation
import ProCRUDCore

struct WorkspacePlanningCenterSequence: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "planning-center-sequence", abstract: "Create/update a local arrangement from a stored Planning Center song sequence and link/select it atomically. No service requests are made.")
	@Argument(help: "Exact registered local native workspace root.") var input: String
	@Option(help: "Shared PlaylistLibrary stream UUID.") var stream: String
	@Option(help: "Outer Planning Center item UUID.") var item: String
	@Option(help: "Exact local Presentation stream UUID.") var presentation: String
	@Option(help: "Stable local arrangement UUID to create or update.") var arrangement: String
	@Option(help: "Local arrangement name.") var name: String
	@Option(help: "Stable nested item UUID, used only when linking an unlinked item.") var linkedItem: String
	@Option(help: "Exact local registry-v1.sqlite3 path. Required when applying.") var registry: String?
	@Flag(help: "Inspect the exact sequence/group mapping without writing. Does not require stopped writers.") var dryRun = false

	func run() throws {
		guard let stream = UUID(uuidString: stream), let item = UUID(uuidString: item), let presentation = UUID(uuidString: presentation), let arrangement = UUID(uuidString: arrangement), let linkedItem = UUID(uuidString: linkedItem) else { throw ValidationError("Stream, item, Presentation, arrangement and linked-item values must be UUIDs.") }
		let root = URL(fileURLWithPath: input)
		if dryRun {
			let plan = try NativePlanningCenterSequence(snapshot: .read(from: root), playlistStreamID: stream, itemID: item, presentationID: presentation, arrangementID: arrangement, name: name, linkedItemID: linkedItem)
			try print(prettyJSON(Preview(groupNames: plan.groupNames, groupIDs: plan.groupIDs, operationCount: plan.operations.count)))
		} else {
			guard let registry else { throw ValidationError("--registry is required when applying a local sequence.") }
			let receipts = try NativeLocalWorkspaceWriter.applyPlanningCenterSequence(in: root, registry: URL(fileURLWithPath: registry), playlistStreamID: stream, itemID: item, presentationID: presentation, arrangementID: arrangement, name: name, linkedItemID: linkedItem)
			try print(prettyJSON(receipts))
		}
	}

	private struct Preview: Encodable {
		let groupNames: [String]
		let groupIDs: [UUID]
		let operationCount: Int
	}
}
