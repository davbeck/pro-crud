import ArgumentParser
import Foundation
import ProCRUDCore

struct Create: ParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Create an editable, unbundled ProPresenter document.",
		subcommands: [CreatePresentation.self, CreateTheme.self, CreatePlaylist.self],
	)
}

private struct CreateOptions {
	var output: String
	var name: String
	var replace: Bool

	func write(_ payload: DocumentPayload) throws {
		let outputURL = URL(fileURLWithPath: output)
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: payload, origin: .raw(outputURL)),
			to: outputURL,
			replace: replace,
		)
		print("Created \(outputURL.path)")
	}
}

struct CreatePresentation: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "presentation", abstract: "Create a presentation with one blank slide.")

	@Option(help: "Output .pro path.") var output: String
	@Option(help: "Presentation name.") var name: String = "Untitled Presentation"
	@Option(help: "Initial slide canvas, WIDTHxHEIGHT.") var size: String = "1920x1080"
	@Option(help: "Theme file, theme directory, or .proTheme archive used for the initial slide.") var theme: String?
	@Option(help: "Archive-relative Theme payload path when a theme archive contains multiple documents.") var themeDocument: String?
	@Option(help: "Exact template name or source path when the theme contains multiple templates.") var template: String?
	@Flag(help: "Copy the selected template's actions into the initial cue.") var includeTemplateActions = false
	@Flag(help: "Replace an existing output file.") var replace = false

	func run() throws {
		let outputURL = URL(fileURLWithPath: output)
		guard outputURL.pathExtension.lowercased() == "pro" else {
			throw ValidationError("Presentation output must use a .pro extension.")
		}
		var presentation = try DocumentFactory.presentation(name: name, canvasSize: DocumentFactory.canvasSize(size))
		var templateMediaURLs: Set<String> = []
		var retainedTemplateCandidates: [ThemeTemplateSource.Candidate] = []
		if let theme {
			let candidate = try ThemeTemplateSource.select(
				ThemeTemplateSource.candidates(
					from: URL(fileURLWithPath: theme),
					themeDocument: themeDocument,
				),
				named: template,
			)
			let application = try DocumentFactory.applyingWithReport(
				template: candidate.slide,
				to: presentation,
				includeTemplateActions: includeTemplateActions,
			)
			presentation = application.presentation
			templateMediaURLs = candidate.preferredAbsoluteMediaURLs
			retainedTemplateCandidates.append(candidate)
			let warnings = candidate.mediaWarnings + (application.report?.warnings ?? [])
			for warning in Set(warnings).sorted() {
				print("Warning [template \(candidate.name)]: \(warning)")
			}
		} else if template != nil || themeDocument != nil || includeTemplateActions {
			throw ValidationError("--template, --theme-document, and --include-template-actions require --theme.")
		}
		guard replace || !FileManager.default.fileExists(atPath: outputURL.path) else {
			throw CocoaError(.fileWriteFileExists)
		}
		try withExtendedLifetime(retainedTemplateCandidates) {
			try TemplateMediaMaterializer.materialize(
				in: &presentation,
				absoluteURLs: templateMediaURLs,
				destinationDirectory: outputURL.deletingLastPathComponent(),
			)
			try CreateOptions(output: output, name: name, replace: replace).write(.presentation(presentation))
		}
	}
}

struct CreateTheme: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "theme", abstract: "Create an empty theme document.")

	@Option(help: "Output Theme file path.") var output: String
	@Option(help: "Theme name retained by the containing folder.") var name: String = "Untitled Theme"
	@Flag(help: "Replace an existing output file.") var replace = false

	func run() throws {
		guard URL(fileURLWithPath: output).lastPathComponent == "Theme" else {
			throw ValidationError("Theme output must be named Theme.")
		}
		try CreateOptions(output: output, name: name, replace: replace).write(.theme(DocumentFactory.theme()))
	}
}

struct CreatePlaylist: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "playlist", abstract: "Create an empty presentation playlist document.")

	@Option(help: "Output data file path.") var output: String
	@Option(help: "Playlist name.") var name: String = "Untitled Playlist"
	@Flag(help: "Replace an existing output file.") var replace = false

	func run() throws {
		guard URL(fileURLWithPath: output).lastPathComponent == "data" else {
			throw ValidationError("Playlist output must be named data.")
		}
		try CreateOptions(output: output, name: name, replace: replace).write(.playlist(DocumentFactory.playlist(name: name)))
	}
}
