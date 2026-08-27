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

	func run() throws {
		let result = try DocumentArchive.bundleWithReport(
			URL(fileURLWithPath: input),
			to: output.map(URL.init(fileURLWithPath:)),
			replace: replace,
		)
		for warning in result.warnings {
			FileHandle.standardError.write(Data("Warning: \(warning)\n".utf8))
		}
		print("Bundled \(result.archiveURL.path)")
	}
}
