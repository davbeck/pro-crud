import ArgumentParser
import Foundation
import ProCRUDCore

struct WorkspaceArrangementReferences: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "arrangement-references", abstract: "Inspect native playlist and document-action arrangement links without changing content.")
	@Argument(help: "Exact native workspace root.") var input: String

	func run() throws {
		let snapshot = try NativeWorkspaceSnapshot.read(from: URL(fileURLWithPath: input))
		try print(prettyJSON(NativeArrangementReferenceInventory(snapshot: snapshot)))
	}
}
