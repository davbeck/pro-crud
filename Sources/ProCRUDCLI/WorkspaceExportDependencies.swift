import ArgumentParser
import Foundation
import ProCRUDCore

struct WorkspaceExportDependencies: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "export-dependencies", abstract: "Export a playlist and its file/configuration dependencies as a separate target-22 legacy workspace directory.")
	@Argument(help: "Exact native source workspace root.") var input: String
	@Option(help: "Library playlist node UUID.") var playlist: String
	@Option(help: "New directory outside the source workspace. Import it as a separate workspace in ProPresenter.") var output: String

	mutating func validate() throws {
		guard UUID(uuidString: playlist) != nil else { throw ValidationError("--playlist requires a UUID.") }
	}

	func run() throws {
		guard let id = UUID(uuidString: playlist) else { throw ValidationError("--playlist requires a UUID.") }
		let snapshot = try NativeWorkspaceSnapshot.read(from: URL(fileURLWithPath: input))
		try print(prettyJSON(NativeWorkspaceDependencyExporter.export(from: snapshot, playlistID: id, to: URL(fileURLWithPath: output))))
	}
}
