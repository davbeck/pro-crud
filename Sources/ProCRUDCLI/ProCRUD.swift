import ArgumentParser
import ProCRUDCore

@main
struct ProCRUD: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "pro-crud",
		abstract: "Create, inspect, package, and render ProPresenter documents.",
		version: proCRUDVersion,
		subcommands: [Create.self, Edit.self, Dump.self, Expand.self, BundleCommand.self, Render.self, Validate.self, Docs.self, SkillCommand.self],
		defaultSubcommand: Dump.self,
	)
}
