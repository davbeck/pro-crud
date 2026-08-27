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
	@Argument(help: "Path to a raw presentation, theme, playlist, or matching archive.") var input: String
	@Option(name: .customLong("format"), help: "Comma-delimited output formats: png, jpg, heic, pdf, or json.") var formats = FormatList([.png])
	@Option(help: "One-based slide number to render. Repeat to select multiple slides.") var slide: [Int] = []
	@Option(help: "Arrangement UUID, selected, or native. Overrides playlist-item and presentation selections.") var arrangement: String?
	@Option(help: "Theme file, theme directory, or .proTheme archive applied transiently before rendering.") var theme: String?
	@Option(help: "Archive-relative Theme payload path when a theme archive contains multiple documents.") var themeDocument: String?
	@Option(help: "Exact template name, UUID path, or source path.") var template: String?
	@Option(help: "Look-style destination canvas, WIDTHxHEIGHT. Requires --theme.") var size: String?
	@Flag(help: "Include identity-safe copies of template actions in the transient render.") var includeTemplateActions = false
	@Option(help: "ProPresenter user-workspace root used to resolve a persisted Look.") var workspace: String?
	@Option(help: "Persisted audience Look name or UUID. Requires --workspace and --screen.") var look: String?
	@Option(help: "Audience screen name or UUID. Requires --workspace and --look.") var screen: String?
	@Option(help: "Write template assignment and scaling diagnostics as JSON.") var templateReport: String?
	@Option(name: [.short, .long], help: "Output folder for images or multiple formats; output file for a single PDF or JSON.") var output: String?
	@Flag(help: "Add output files without replacing existing files.") var merge = false
	@Flag(help: "Replace an existing output file or folder.") var replace = false

	func run() throws {
		let inputURL = URL(fileURLWithPath: input)
		var documents = try PresentationLoader.loadPresentations(from: inputURL)
		if let selection = arrangementSelection() {
			for index in documents.indices {
				documents[index].document.arrangementSelection = selection
			}
		}
		let slideIndices = try selectedSlideIndices(in: documents)
		let templateResolution = try resolveTemplates(in: documents, slideIndices: slideIndices)
		documents = templateResolution.documents
		for report in templateResolution.reports {
			for warning in report.warnings {
				print("Warning [template \(report.templateName)]: \(warning)")
			}
		}
		var diagnostics: [(sourceName: String, diagnostic: RenderingDiagnostic)] = []
		for loaded in documents {
			var diagnosedCueStorageIndices = Set<Int>()
			for occurrence in try loaded.document.cueOccurrences()
				where (slideIndices?.contains(occurrence.sequenceIndex) ?? true) &&
				diagnosedCueStorageIndices.insert(occurrence.cueStorageIndex).inserted
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

	private struct ResolvedDocuments {
		var documents: [LoadedPresentationDocument]
		var reports: [TemplateResolutionReport]
	}

	private func resolveTemplates(
		in source: [LoadedPresentationDocument],
		slideIndices: Set<Int>?,
	) throws -> ResolvedDocuments {
		let lookOptionCount = [workspace != nil, look != nil, screen != nil].count(where: { $0 })
		guard lookOptionCount == 0 || lookOptionCount == 3 else {
			throw ValidationError("--workspace, --look, and --screen must be provided together.")
		}
		let hasDirectThemeOptions = theme != nil || themeDocument != nil || template != nil || size != nil || includeTemplateActions
		guard lookOptionCount == 0 || !hasDirectThemeOptions else {
			throw ValidationError("Persisted Look options cannot be combined with --theme, --theme-document, --template, --size, or --include-template-actions.")
		}
		guard theme != nil || !hasDirectThemeOptions else {
			throw ValidationError("--theme-document, --template, --size, and --include-template-actions require --theme.")
		}
		guard theme != nil || lookOptionCount == 3 || templateReport == nil else {
			throw ValidationError("--template-report requires direct Theme or persisted Look rendering.")
		}

		let candidate: ThemeTemplateSource.Candidate
		let destinationSize: CGSize?
		var lookWarnings: [String] = []
		if let theme {
			candidate = try ThemeTemplateSource.select(
				ThemeTemplateSource.candidates(
					from: URL(fileURLWithPath: theme),
					themeDocument: themeDocument,
				),
				named: template,
			)
			destinationSize = try size.map(DocumentFactory.canvasSize)
		} else if let workspace, let look, let screen {
			let selection = try LookResolver.resolve(
				workspace: URL(fileURLWithPath: workspace),
				look: look,
				screen: screen,
			)
			candidate = selection.template
			destinationSize = selection.destinationSize
			lookWarnings = selection.warnings
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
			for var report in resolution.reports {
				report.warnings.append(contentsOf: lookWarnings)
				report.warnings = Array(Set(report.warnings)).sorted()
				reports.append(report)
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
			)
			print("Rendered \(result.slideCount) slides to \(outputURL.path)")
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
				options: RenderOptions(outputDirectory: directory, imageType: imageType),
				slideIndices: slideIndices,
			)
			rendered += result.slideCount
		}
		print("Rendered \(rendered) slides to \(outputURL.path)")
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
			let indices: Set<Int>
			if let slideIndices {
				indices = slideIndices
			} else {
				indices = try Set(loaded.document.cueOccurrences().indices)
			}
			for index in indices {
				let destination = directory.appendingPathComponent("\(index + 1).\(format.rawValue)")
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
