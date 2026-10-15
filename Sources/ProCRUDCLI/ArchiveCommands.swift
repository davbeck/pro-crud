import ArgumentParser
import Foundation
import ProCRUDCore

struct Expand: ParsableCommand {
	static let configuration = CommandConfiguration(abstract: "Extract a ProPresenter bundle.")
	@Argument(help: "Path to a .probundle, .proPlaylist, or .proTheme archive.") var input: String
	@Option(help: "Directory where the archive should be extracted.") var output: String?

	func run() throws {
		let directory = try DocumentArchive.expand(
			URL(fileURLWithPath: input),
			to: output.map { URL(fileURLWithPath: $0, isDirectory: true) },
		)
		print("Expanded to \(directory.path)")
	}
}

struct BundleCommand: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "bundle", abstract: "Create a portable ProPresenter archive from a raw document or workspace.")
	@Argument(help: "Path to a raw .pro document or extracted workspace directory.") var input: String
	@Option(help: "Output archive path.") var output: String?
	@Flag(help: "Replace an existing output archive.") var replace = false
	@OptionGroup var target: TargetVersionOptions
	@Flag(help: "Print the archive path and structured compatibility report as JSON.") var json = false

	func run() throws {
		let result = try DocumentArchive.bundleWithReport(
			URL(fileURLWithPath: input),
			to: output.map(URL.init(fileURLWithPath:)),
			replace: replace,
			targetVersion: target.targetVersion,
		)
		for warning in result.warnings {
			FileHandle.standardError.write(Data("Warning: \(warning)\n".utf8))
		}
		if json {
			try print(prettyJSON(BundleCommandResult(path: result.archiveURL.path, compatibility: result.compatibility, warnings: result.warnings)))
		} else {
			for issue in result.compatibility.issues {
				FileHandle.standardError.write(Data("Warning [\(issue.feature)] \(issue.componentPath): \(issue.message)\n".utf8))
			}
			print("Bundled \(result.archiveURL.path) (target \(target.targetVersion.rawValue))")
		}
	}
}

private struct BundleCommandResult: Encodable {
	var path: String
	var compatibility: DocumentCompatibilityReport
	var warnings: [String]
}
