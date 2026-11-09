import ArgumentParser
import Foundation
import ProCRUDCore

struct Render: ParsableCommand {
	enum Format: String, CaseIterable { case png, jpg, heic, pdf, json }

	struct FormatList: CustomStringConvertible, ExpressibleByArgument {
		let values: [Format]
		var description: String {
			values.map(\.rawValue).joined(separator: ",")
		}

		init(_ values: [Format]) {
			self.values = values
		}

		init?(argument: String) {
			let components = argument.split(separator: ",", omittingEmptySubsequences: false)
			let values = components.compactMap { Format(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
			guard !values.isEmpty, values.count == components.count, Set(values).count == values.count else { return nil }
			self.values = values
		}
	}

	static let configuration = CommandConfiguration(abstract: "Render ProPresenter presentations, themes, and playlists to images, PDF, or structured JSON.")
	@Argument(help: "Path to a raw presentation, theme, playlist, matching archive, or native workspace root with --native-stream.") var input: String
	@Option(help: "Exact shared native Presentation stream UUID. INPUT must be its native workspace root; --output must be separate from that root.") var nativeStream: String?
	@Option(name: .customLong("format"), help: "Comma-delimited output formats: png, jpg, heic, pdf, or json.") var formats = FormatList([.png])
	@Option(help: "One-based slide number to render. Repeat to select multiple slides.") var slide: [Int] = []
	@Flag(help: "Render the initial state and each settled Build Order step to images or PDF pages.") var buildSteps = false
	@Option(help: "Arrangement UUID, selected, or native. Overrides playlist-item and presentation selections.") var arrangement: String?
	@Option(help: "Theme file, theme directory, or .proTheme archive applied transiently before rendering.") var theme: String?
	@Option(help: "Archive-relative Theme payload path when a theme archive contains multiple documents.") var themeDocument: String?
	@Option(help: "Exact template name, UUID path, or source path.") var template: String?
	@Option(help: "Look-style destination canvas, WIDTHxHEIGHT. Requires --theme.") var size: String?
	@Flag(help: "Include identity-safe copies of template actions in the transient render.") var includeTemplateActions = false
	@Option(help: "ProPresenter workspace root containing Looks, Macros, screens, and Themes. Defaults to INPUT with --native-stream.") var workspace: String?
	@Option(help: "Fixed audience Look name or UUID. Defaults to the main audience screen; requires --workspace.") var look: String?
	@Option(help: "Macro name or UUID whose recursive Look actions select a fixed variation. Requires --workspace.") var macro: String?
	@Option(name: [.customLong("screen"), .customLong("screens")], parsing: .upToNextOption, help: "Audience screen names or UUIDs, or all. Repeat or pass several values. Defaults to the first configured audience screen. Requires --workspace.") var screen: [String] = []
	@Option(help: "Write template assignment and scaling diagnostics as JSON.") var templateReport: String?
	@Option(name: [.short, .long], help: "Output folder for images or multiple formats; output file for a single PDF or JSON.") var output: String?
	@Flag(help: "Add output files without replacing existing files.") var merge = false
	@Flag(help: "Replace an existing output file or folder.") var replace = false

	private var configurationWorkspace: String? {
		workspace ?? (nativeStream != nil && (look != nil || macro != nil || !screen.isEmpty) ? input : nil)
	}

	func run() throws {
		guard !buildSteps || !formats.values.contains(.json) else {
			throw ValidationError("--build-steps supports image and PDF formats; omit json from --format.")
		}
		let inputURL = URL(fileURLWithPath: input)
		if let workspace, nativeStream == nil {
			let root = URL(fileURLWithPath: workspace).resolvingSymlinksInPath().standardizedFileURL.path
			let destination = formats.values.count == 1 ? resolvedSingleOutputURL(for: inputURL, format: formats.values[0]) : resolvedMultipleOutputURL(for: inputURL)
			for url in [destination] + (templateReport.map { [URL(fileURLWithPath: $0)] } ?? []) {
				let path = url.resolvingSymlinksInPath().standardizedFileURL.path
				guard path != root, !path.hasPrefix(root + "/"), !root.hasPrefix(path == "/" ? "/" : path + "/") else {
					throw ValidationError("Workspace render output and template reports must be separate from the configuration workspace and its parent directories.")
				}
			}
		}
		let nativeSnapshot: NativeWorkspaceSnapshot?
		var documents: [LoadedPresentationDocument]
		if let nativeStream {
			guard let id = UUID(uuidString: nativeStream) else { throw ValidationError("--native-stream requires a UUID.") }
			try preflightNativeOutput(inputURL)
			let snapshot = try NativeWorkspaceSnapshot.read(from: inputURL)
			nativeSnapshot = snapshot
			documents = try [PresentationLoader.load(nativeDocumentID: id, from: snapshot)]
		} else {
			nativeSnapshot = nil
			documents = try PresentationLoader.loadPresentations(from: inputURL)
		}
		if let selection = arrangementSelection() {
			for index in documents.indices {
				documents[index].document.arrangementSelection = selection
			}
		}
		let slideIndices = try selectedSlideIndices(in: documents)
		let templateResolution = try resolveTemplates(in: documents, slideIndices: slideIndices, nativeSnapshot: nativeSnapshot)
		documents = templateResolution.documents
		// Reject unsupported representations before --replace removes an
		// existing output. Use the same selected slides as the actual render.
		_ = try PresentationRenderer.effectiveRendering(documents: documents.map(\.document), slideIndices: slideIndices)
		for report in templateResolution.reports {
			for warning in report.warnings {
				print("Warning [template \(report.templateName)]: \(warning)")
			}
		}
		var diagnostics: [(sourceName: String, diagnostic: RenderingDiagnostic)] = []
		for loaded in documents {
			for occurrence in try loaded.document.cueOccurrences()
				where slideIndices?.contains(occurrence.sequenceIndex) ?? true
			{
				diagnostics.append(contentsOf:
					loaded.document.renderingDiagnostics(for: occurrence.cue).map { (loaded.sourceName, $0) })
			}
		}
		for (sourceName, diagnostic) in diagnostics where diagnostic.severity == .warning {
			print("Warning [\(sourceName)]: \(diagnostic.description)")
		}
		if let (sourceName, diagnostic) = diagnostics.first(where: { $0.1.severity == .error }) {
			throw ValidationError("[\(sourceName)] \(diagnostic.description)")
		}

		if buildSteps {
			for loaded in documents {
				_ = try PresentationRenderer(document: loaded.document).imageFileNames(
					slideIndices: slideIndices,
					buildSteps: true,
				)
			}
		}

		if formats.values.count == 1, let format = formats.values.first {
			let outputURL = resolvedSingleOutputURL(for: inputURL, format: format)
			try preflightTemplateReport(renderOutputURL: outputURL)
			try prepareSingleOutput(outputURL, format: format)
			try preflightImageOutputs(format: format, outputURL: outputURL, documents: documents, slideIndices: slideIndices)
			try render(format: format, to: outputURL, documents: documents, slideIndices: slideIndices)
			try writeTemplateReport(templateResolution.reports)
			return
		}

		let outputDirectory = resolvedMultipleOutputURL(for: inputURL)
		try preflightTemplateReport(renderOutputURL: outputDirectory)
		try prepareMultipleOutput(outputDirectory)
		for format in formats.values {
			let outputURL = multipleFormatOutputURL(format: format, directory: outputDirectory, inputURL: inputURL)
			if format.isSingleFile, FileManager.default.fileExists(atPath: outputURL.path) {
				throw ValidationError("Refusing to overwrite existing output: \(outputURL.path)")
			}
			try preflightImageOutputs(format: format, outputURL: outputURL, documents: documents, slideIndices: slideIndices)
		}
		for format in formats.values {
			let outputURL = multipleFormatOutputURL(format: format, directory: outputDirectory, inputURL: inputURL)
			try render(format: format, to: outputURL, documents: documents, slideIndices: slideIndices)
		}
		try writeTemplateReport(templateResolution.reports)
	}

	private func preflightNativeOutput(_ inputURL: URL) throws {
		guard output != nil else { throw ValidationError("Native rendering requires an explicit --output outside the workspace.") }
		let roots = ([inputURL] + (workspace.map { [URL(fileURLWithPath: $0)] } ?? []))
			.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
		for path in [output, templateReport].compactMap(\.self) {
			let destination = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
			guard roots.allSatisfy({ root in
				destination.path != root && !destination.path.hasPrefix(root + "/") && !root.hasPrefix(destination.path == "/" ? "/" : destination.path + "/")
			}) else {
				throw ValidationError("Native render output and template reports must be separate from the source workspace and its parent directories.")
			}
			try WorkspaceInspector.requireLegacyAccess(at: destination)
		}
	}

	private struct ResolvedDocuments {
		var documents: [LoadedPresentationDocument]
		var reports: [TemplateResolutionReport]
	}

	private func resolveTemplates(
		in source: [LoadedPresentationDocument],
		slideIndices: Set<Int>?,
		nativeSnapshot: NativeWorkspaceSnapshot?,
	) throws -> ResolvedDocuments {
		let hasLookOptions = configurationWorkspace != nil || look != nil || macro != nil || !screen.isEmpty
		guard !hasLookOptions || configurationWorkspace != nil else { throw ValidationError("Screen, Look, and Macro rendering requires --workspace.") }
		guard look == nil || macro == nil else { throw ValidationError("--look and --macro select alternative fixed variations; provide only one.") }
		let hasDirectThemeOptions = theme != nil || themeDocument != nil || template != nil || size != nil || includeTemplateActions
		guard !hasLookOptions || !hasDirectThemeOptions else {
			throw ValidationError("Workspace rendering cannot be combined with --theme, --theme-document, --template, --size, or --include-template-actions.")
		}
		guard theme != nil || !hasDirectThemeOptions else { throw ValidationError("--theme-document, --template, --size, and --include-template-actions require --theme.") }
		guard theme != nil || hasLookOptions || templateReport == nil else { throw ValidationError("--template-report requires direct Theme or workspace rendering.") }
		if let workspace = configurationWorkspace {
			return try resolveLooks(in: source, workspace: workspace, slideIndices: slideIndices, nativeSnapshot: nativeSnapshot)
		}
		let candidate: ThemeTemplateSource.Candidate
		let destinationSize: CGSize?
		if let theme {
			candidate = try ThemeTemplateSource.select(
				ThemeTemplateSource.candidates(
					from: URL(fileURLWithPath: theme),
					themeDocument: themeDocument,
				),
				named: template,
			)
			destinationSize = try size.map(DocumentFactory.canvasSize)
		} else {
			return ResolvedDocuments(documents: source, reports: [])
		}

		var documents = source
		var reports: [TemplateResolutionReport] = []
		for index in documents.indices {
			let nativeSlideIndices = try documents[index].document.nativeCueIndices(
				forRenderedSlideIndices: slideIndices,
			)
			let resolution = try PresentationTemplateResolver.resolve(
				document: documents[index].document,
				template: candidate,
				destinationSize: destinationSize,
				includeTemplateActions: includeTemplateActions,
				slideIndices: nativeSlideIndices,
			)
			documents[index].document = resolution.document
			reports.append(contentsOf: resolution.reports)
		}
		return ResolvedDocuments(documents: documents, reports: reports)
	}

	private func resolveLooks(in source: [LoadedPresentationDocument], workspace: String, slideIndices: Set<Int>?, nativeSnapshot: NativeWorkspaceSnapshot?) throws -> ResolvedDocuments {
		let url = URL(fileURLWithPath: workspace).resolvingSymlinksInPath().standardizedFileURL
		let configuration: RenderConfiguration
		if let nativeSnapshot, url == nativeSnapshot.root.resolvingSymlinksInPath().standardizedFileURL {
			configuration = try RenderConfiguration(snapshot: nativeSnapshot)
		} else {
			configuration = try RenderConfiguration(workspace: url)
		}
		let screens = try configuration.selectScreens(screen)
		var documents: [LoadedPresentationDocument] = []
		var reports: [TemplateResolutionReport] = []
		for selected in screens {
			for var loaded in source {
				let resolution = try PresentationLookResolver.resolve(document: loaded.document, configuration: configuration, screen: selected, look: look, macro: macro, slideIndices: slideIndices)
				loaded.document = resolution.document
				if screens.count > 1 {
					let safeName = selected.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
					let directory = "\(safeName)-\(selected.uuid)"
					loaded.sourceName = loaded.usesOutputSubdirectory ? directory + "/" + loaded.sourceName : directory
					loaded.usesOutputSubdirectory = true
				}
				documents.append(loaded)
				reports.append(contentsOf: resolution.reports)
			}
		}
		return ResolvedDocuments(documents: documents, reports: reports)
	}

	private func preflightTemplateReport(renderOutputURL: URL) throws {
		guard let templateReport else { return }
		let url = URL(fileURLWithPath: templateReport).standardizedFileURL
		let renderURL = renderOutputURL.standardizedFileURL
		let samePath = url.path == renderURL.path
		let reportContainsOutput = renderURL.path.hasPrefix(url.path + "/")
		let outputContainsReport = url.path.hasPrefix(renderURL.path + "/")
		guard !samePath, !reportContainsOutput, !outputContainsReport else {
			throw ValidationError("--template-report must not collide with the render output path.")
		}
		if FileManager.default.fileExists(atPath: url.path), !replace {
			throw ValidationError("Template report already exists: \(url.path). Use --replace.")
		}
	}

	private func writeTemplateReport(_ reports: [TemplateResolutionReport]) throws {
		guard let templateReport else { return }
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		var data = try encoder.encode(reports)
		data.append(0x0A)
		let url = URL(fileURLWithPath: templateReport)
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try data.write(to: url, options: .atomic)
		print("Wrote template report to \(url.path)")
	}

	private func render(
		format: Format,
		to outputURL: URL,
		documents: [LoadedPresentationDocument],
		slideIndices: Set<Int>?,
	) throws {
		if format == .json {
			let rendering = try PresentationRenderer.effectiveRendering(
				documents: documents.map(\.document),
				slideIndices: slideIndices,
			)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
			var data = try encoder.encode(rendering)
			data.append(0x0A)
			try data.write(to: outputURL)
			print("Described \(rendering.presentations.flatMap(\.slides).count) slides at \(outputURL.path)")
			return
		}

		if format == .pdf {
			let result = try PresentationRenderer.renderPDF(
				documents: documents.map(\.document),
				to: outputURL,
				slideIndices: slideIndices,
				buildSteps: buildSteps,
			)
			print("Rendered \(result.slideCount) \(buildSteps ? "build states" : "slides") to \(outputURL.path)")
			return
		}

		let imageType: RenderOptions.ImageType = switch format {
		case .png: .png
		case .jpg: .jpg
		case .heic: .heic
		case .pdf, .json: fatalError("handled above")
		}
		var rendered = 0
		for loaded in documents {
			let directory = loaded.usesOutputSubdirectory
				? outputURL.appendingPathComponent(loaded.sourceName, isDirectory: true)
				: outputURL
			let result = try PresentationRenderer(document: loaded.document).render(
				options: RenderOptions(outputDirectory: directory, imageType: imageType, buildSteps: buildSteps),
				slideIndices: slideIndices,
			)
			rendered += result.slideCount
		}
		print("Rendered \(rendered) \(buildSteps ? "build states" : "slides") to \(outputURL.path)")
	}

	private func selectedSlideIndices(in documents: [LoadedPresentationDocument]) throws -> Set<Int>? {
		guard !slide.isEmpty else { return nil }
		guard slide.allSatisfy({ $0 > 0 }) else { throw ValidationError("--slide values must be one or greater.") }
		let indices = Set(slide.map { $0 - 1 })
		for loaded in documents {
			let cueCount = try loaded.document.cueOccurrences().count
			if let missing = indices.sorted().first(where: { $0 >= cueCount }) {
				throw ValidationError("Slide \(missing + 1) does not exist in \(loaded.sourceName).")
			}
		}
		return indices
	}

	private func arrangementSelection() -> ArrangementSelection? {
		guard let arrangement else { return nil }
		return switch arrangement {
		case "native": .native
		case "selected": .selected
		default: .uuid(arrangement)
		}
	}

	private func resolvedSingleOutputURL(for inputURL: URL, format: Format) -> URL {
		if let output {
			return URL(fileURLWithPath: output, isDirectory: !format.isSingleFile)
		}
		let base = inputURL.deletingPathExtension()
		return format.isSingleFile
			? base.appendingPathExtension(format.rawValue)
			: base.appendingPathComponent("Rendered", isDirectory: true)
	}

	private func resolvedMultipleOutputURL(for inputURL: URL) -> URL {
		if let output {
			return URL(fileURLWithPath: output, isDirectory: true)
		}
		return inputURL.deletingPathExtension().appendingPathComponent("Rendered", isDirectory: true)
	}

	private func multipleFormatOutputURL(format: Format, directory: URL, inputURL: URL) -> URL {
		guard format.isSingleFile else { return directory }
		let name = inputURL.deletingPathExtension().lastPathComponent
		return directory.appendingPathComponent(name).appendingPathExtension(format.rawValue)
	}

	private func prepareSingleOutput(_ url: URL, format: Format) throws {
		let fileManager = FileManager.default
		guard fileManager.fileExists(atPath: url.path) else { return }
		if replace {
			try fileManager.removeItem(at: url)
		} else if !merge || format.isSingleFile {
			throw ValidationError("Output already exists: \(url.path). Use --merge or --replace.")
		}
	}

	private func prepareMultipleOutput(_ url: URL) throws {
		let fileManager = FileManager.default
		var isDirectory: ObjCBool = false
		if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
			if replace {
				try fileManager.removeItem(at: url)
			} else if !merge {
				throw ValidationError("Output already exists: \(url.path). Use --merge or --replace.")
			} else if !isDirectory.boolValue {
				throw ValidationError("Multiple formats require an output directory: \(url.path)")
			}
		}
		try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
	}

	private func preflightImageOutputs(
		format: Format,
		outputURL: URL,
		documents: [LoadedPresentationDocument],
		slideIndices: Set<Int>?,
	) throws {
		guard !format.isSingleFile else { return }
		for loaded in documents {
			let directory = loaded.usesOutputSubdirectory
				? outputURL.appendingPathComponent(loaded.sourceName, isDirectory: true)
				: outputURL
			let imageType: RenderOptions.ImageType = switch format {
			case .png: .png
			case .jpg: .jpg
			case .heic: .heic
			case .pdf, .json: fatalError("Single-file formats handled above")
			}
			let names = try PresentationRenderer(document: loaded.document).imageFileNames(
				imageType: imageType,
				slideIndices: slideIndices,
				buildSteps: buildSteps,
			)
			for name in names {
				let destination = directory.appendingPathComponent(name)
				if FileManager.default.fileExists(atPath: destination.path) {
					throw ValidationError("Refusing to overwrite existing image: \(destination.path)")
				}
			}
		}
	}
}

private extension Render.Format {
	var isSingleFile: Bool {
		self == .pdf || self == .json
	}
}
