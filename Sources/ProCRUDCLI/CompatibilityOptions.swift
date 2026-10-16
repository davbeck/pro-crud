import ArgumentParser
import Foundation
import ProCRUDCore

extension ProPresenterTargetVersion: ExpressibleByArgument {}

struct TargetVersionOptions: ParsableArguments {
	@Option(help: "Output compatibility target: 21 or 22. New content and exports default to 22; ordinary edits preserve their source.")
	var targetVersion: ProPresenterTargetVersion = .v22
}

struct CompatibilityCommand: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "compatibility", abstract: "Report unqualified target features before writing an interchange document.")
	@Argument(help: "Raw document, expanded single export, or archive.") var input: String
	@OptionGroup var target: TargetVersionOptions

	func run() throws {
		let document = try DocumentLoader.load(from: URL(fileURLWithPath: input))
		let report: DocumentCompatibilityReport
		if case .playlist = document.payload, let resources = document.resourceDirectory,
		   document.origin != .raw(URL(fileURLWithPath: input))
		{
			report = try DocumentCompatibility.analyzeExportContents(in: resources, target: target.targetVersion)
		} else {
			report = try DocumentCompatibility.analyze(document, target: target.targetVersion)
		}
		try print(prettyJSON(report))
		if !report.canWrite {
			throw ExitCode.failure
		}
	}
}
