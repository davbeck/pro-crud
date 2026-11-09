import ArgumentParser
import ProCRUDCore

@main
struct ProCRUD: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "pro-crud",
		abstract: "Create, inspect, package, and render ProPresenter documents.",
		version: reportedVersion,
		subcommands: [PlanningCenterCommand.self, Create.self, Edit.self, Dump.self, Expand.self, BundleCommand.self, Render.self, Validate.self, WorkspaceCommand.self, CompatibilityCommand.self, Docs.self, SkillCommand.self],
		defaultSubcommand: Dump.self,
	)

	static var reportedVersion: String {
		#if DEBUG
			"DEBUG \(proCRUDVersion) (\(proCRUDGitCommit))"
		#else
			"\(proCRUDVersion) (\(proCRUDGitCommit))"
		#endif
	}
}
