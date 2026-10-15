import ArgumentParser
import Foundation
import ProCRUDCore

struct WorkspaceCommand: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "workspace", abstract: "Inspect explicitly selected ProPresenter workspace storage.",
		subcommands: [WorkspaceInspect.self],
	)
}

struct WorkspaceInspect: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "inspect", abstract: "Report storage evidence and supported operations without selecting or migrating a workspace.")

	@Argument(help: "Exact workspace root. Retained legacy copies and native workspaces are independent.") var input: String

	func run() throws {
		let report = try WorkspaceInspector.inspect(URL(fileURLWithPath: input))
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		try print(String(decoding: encoder.encode(report), as: UTF8.self))
	}
}
