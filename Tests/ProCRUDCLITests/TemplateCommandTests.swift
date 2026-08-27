import AppKit
import Foundation
import ProCRUDCore
import ProPresenterProto
import SwiftProtobuf
import Testing
@testable import ProCRUDCLI

@Suite("Template commands")
struct TemplateCommandTests {
	@Test
	func renderAppliesTemplateToEveryFormatInputWithoutMutatingSource() throws {
		try withTemplateTemporaryDirectory { directory in
			let presentationURL = directory.appendingPathComponent("Source.pro")
			let themeURL = directory.appendingPathComponent("Theme Source/Theme")
			try writeTemplatePresentation(to: presentationURL)
			try writeTemplateTheme(to: themeURL)
			let original = try Data(contentsOf: presentationURL)
			let outputURL = directory.appendingPathComponent("resolved.json")
			let reportURL = directory.appendingPathComponent("template-report.json")

			try Render.parse([
				presentationURL.path,
				"--format", "json",
				"--theme", themeURL.path,
				"--template", "Body Template",
				"--size", "1000x500",
				"--template-report", reportURL.path,
				"--output", outputURL.path,
			]).run()

			#expect(try Data(contentsOf: presentationURL) == original)
			let rendering = try JSONDecoder().decode(EffectiveRendering.self, from: Data(contentsOf: outputURL))
			let slide = try #require(rendering.presentations.first?.slides.first)
			#expect(slide.canvasSize.width == 1000)
			#expect(slide.canvasSize.height == 500)
			let layer = try #require(slide.layers.first)
			#expect(layer.name == "Body")
			#expect(layer.uuid == "SOURCE-BODY")
			#expect(abs((layer.bounds.x ?? 0) - 25) < 0.01)
			#expect(abs(layer.bounds.width - 500) < 0.01)
			#expect(abs(layer.bounds.height - (500.0 / 3.0)) < 0.01)
			#expect(layer.text?.plainText == "SOURCE WORDS")

			let reports = try JSONDecoder().decode([TemplateResolutionReport].self, from: Data(contentsOf: reportURL))
			#expect(reports.count == 1)
			#expect(reports[0].mode == .runtimeLook)
			#expect(reports[0].transform.xScale == 2.5)
			#expect(abs(reports[0].transform.yScale - (5.0 / 3.0)) < 0.000_001)
		}
	}

	@Test
	func renderResolvesOnlySelectedSlides() throws {
		try withTemplateTemporaryDirectory { directory in
			let presentationURL = directory.appendingPathComponent("Selected Source.pro")
			let themeURL = directory.appendingPathComponent("Theme Source/Theme")
			try writeTemplatePresentation(to: presentationURL)
			try writeTemplateTheme(to: themeURL)
			var presentation = try loadedPresentation(presentationURL)
			var invalidCue = presentation.cues[0]
			invalidCue.uuid.string = "INVALID-CUE"
			invalidCue.actions[0].uuid.string = "INVALID-ACTION"
			invalidCue.actions[0].slide.presentation.baseSlide.uuid.string = "INVALID-SLIDE"
			invalidCue.actions[0].slide.presentation.baseSlide.size.width = 0
			invalidCue.actions[0].slide.presentation.baseSlide.size.height = 0
			presentation.cues.append(invalidCue)
			presentation.cueGroups[0].cueIdentifiers.append(invalidCue.uuid)
			try DocumentWriter.writeRaw(
				ProPresenterDocument(payload: .presentation(presentation), origin: .raw(presentationURL)),
				to: presentationURL,
				replace: true,
			)

			let outputURL = directory.appendingPathComponent("selected.json")
			let reportURL = directory.appendingPathComponent("selected-report.json")
			try Render.parse([
				presentationURL.path,
				"--format", "json",
				"--slide", "1",
				"--theme", themeURL.path,
				"--template", "Body Template",
				"--template-report", reportURL.path,
				"--output", outputURL.path,
			]).run()

			let rendering = try JSONDecoder().decode(EffectiveRendering.self, from: Data(contentsOf: outputURL))
			#expect(rendering.presentations.first?.slides.count == 1)
			#expect(rendering.presentations.first?.slides.first?.index == 0)
			let reports = try JSONDecoder().decode([TemplateResolutionReport].self, from: Data(contentsOf: reportURL))
			#expect(reports.count == 1)
			#expect(reports[0].sourceSlideUUID == "SOURCE-SLIDE")
		}
	}

	@Test
	func createAddAndApplyUseCorrectResolutionModes() throws {
		try withTemplateTemporaryDirectory { directory in
			let themeURL = directory.appendingPathComponent("Theme Source/Theme")
			try writeTemplateTheme(to: themeURL)
			let createdURL = directory.appendingPathComponent("Created.pro")
			try CreatePresentation.parse([
				"--output", createdURL.path,
				"--name", "Created",
				"--size", "800x600",
				"--theme", themeURL.path,
				"--template", "Body Template",
			]).run()
			var created = try loadedPresentation(createdURL)
			var createdSlide = created.cues[0].actions[0].slide.presentation.baseSlide
			#expect(createdSlide.size.width == 800)
			#expect(createdSlide.size.height == 600)
			#expect(createdSlide.elements[0].element.bounds.origin.x == 20)
			#expect(try decodeText(createdSlide.elements[0]).string.isEmpty)
			#expect(createdSlide.elements[0].element.text.attributes.font.size == 20)

			try EditAddSlide.parse([
				createdURL.path,
				"--group", "/cue_groups[index=0]",
				"--theme", themeURL.path,
				"--template", "Body Template",
			]).run()
			created = try loadedPresentation(createdURL)
			#expect(created.cues.count == 2)
			let addedSlide = created.cues[1].actions[0].slide.presentation.baseSlide
			#expect(addedSlide.size.width == 800)
			#expect(try decodeText(addedSlide.elements[0]).string.isEmpty)
			#expect(addedSlide.uuid != createdSlide.uuid)
			#expect(addedSlide.elements[0].element.uuid != createdSlide.elements[0].element.uuid)

			let sourceURL = directory.appendingPathComponent("Apply Source.pro")
			try writeTemplatePresentation(to: sourceURL)
			let sourceBytes = try Data(contentsOf: sourceURL)
			try EditApplyTemplate.parse([
				sourceURL.path,
				"--path", "/cues[index=0]",
				"--theme", themeURL.path,
				"--template", "Body Template",
				"--dry-run",
			]).run()
			#expect(try Data(contentsOf: sourceURL) == sourceBytes)

			let appliedURL = directory.appendingPathComponent("Applied.pro")
			try EditApplyTemplate.parse([
				sourceURL.path,
				"--path", "/cues[index=0]",
				"--theme", themeURL.path,
				"--template", "Body Template",
				"--output", appliedURL.path,
			]).run()
			#expect(try Data(contentsOf: sourceURL) == sourceBytes)
			let applied = try loadedPresentation(appliedURL)
			createdSlide = applied.cues[0].actions[0].slide.presentation.baseSlide
			#expect(createdSlide.uuid.string == "SOURCE-SLIDE")
			#expect(createdSlide.elements[0].element.uuid.string == "SOURCE-BODY")
			#expect(try decodeText(createdSlide.elements[0]).string == "SOURCE WORDS")
			#expect(createdSlide.elements[0].element.bounds.origin.x == 20)
		}
	}

	@Test
	func renderResolvesPersistedLookTemplateAndAudienceScreenCanvas() throws {
		try withTemplateTemporaryDirectory { directory in
			let presentationURL = directory.appendingPathComponent("Source.pro")
			let workspaceURL = directory.appendingPathComponent("Workspace")
			let themeURL = workspaceURL.appendingPathComponent("Themes/Stream/Theme")
			try writeTemplatePresentation(to: presentationURL)
			try writeTemplateTheme(to: themeURL)
			let lookAsset = workspaceURL.appendingPathComponent("Media/look.png")
			try FileManager.default.createDirectory(
				at: lookAsset.deletingLastPathComponent(),
				withIntermediateDirectories: true,
			)
			try onePixelPNG(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)).write(to: lookAsset)
			guard case var .theme(theme) = try DocumentLoader.loadRaw(themeURL).payload else {
				Issue.record("Expected Theme payload")
				return
			}
			var media = Rv_Data_Media()
			media.uuid.string = "LOOK-MEDIA"
			media.url.absoluteString = "file:///stale-workspace/Media/look.png"
			media.url.local.root = .show
			media.url.local.path = "Media/look.png"
			media.image.drawing.naturalSize.width = 1
			media.image.drawing.naturalSize.height = 1
			theme.slides[0].baseSlide.elements[0].element.fill.enable = true
			theme.slides[0].baseSlide.elements[0].element.fill.media = media
			try DocumentWriter.writeRaw(
				ProPresenterDocument(payload: .theme(theme), origin: .raw(themeURL)),
				to: themeURL,
				replace: true,
			)
			try writeWorkspace(to: workspaceURL, themeURL: themeURL)
			let outputURL = directory.appendingPathComponent("look.json")

			try Render.parse([
				presentationURL.path,
				"--format", "json",
				"--workspace", workspaceURL.path,
				"--look", "Stream Match",
				"--screen", "Projector",
				"--output", outputURL.path,
			]).run()

			let rendering = try JSONDecoder().decode(EffectiveRendering.self, from: Data(contentsOf: outputURL))
			let slide = try #require(rendering.presentations.first?.slides.first)
			#expect(slide.canvasSize.width == 1280)
			#expect(slide.canvasSize.height == 720)
			#expect(slide.layers.first?.text?.plainText == "SOURCE WORDS")
			#expect(slide.layers.first?.name == "Body")
			#expect(slide.layers.first?.fill?.media?.resolvedSource == lookAsset.standardizedFileURL.path)
		}
	}

	@Test
	func renderTemplateFeedsImageAndPDFBranches() throws {
		try withTemplateTemporaryDirectory { directory in
			let presentationURL = directory.appendingPathComponent("Source.pro")
			let themeURL = directory.appendingPathComponent("Theme Source/Theme")
			try writeTemplatePresentation(to: presentationURL)
			try writeTemplateTheme(to: themeURL)
			let output = directory.appendingPathComponent("Rendered")

			try Render.parse([
				presentationURL.path,
				"--format", "png,pdf",
				"--theme", themeURL.path,
				"--template", "Body Template",
				"--size", "100x50",
				"--output", output.path,
			]).run()

			let image = try #require(NSImage(contentsOf: output.appendingPathComponent("1.png")))
			let bitmap = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
			#expect(bitmap.pixelsWide == 100)
			#expect(bitmap.pixelsHigh == 50)
			let pdf = try Data(contentsOf: output.appendingPathComponent("Source.pdf"))
			#expect(String(data: pdf.prefix(4), encoding: .ascii) == "%PDF")
		}
	}

	@Test
	func renderRejectsTemplateReportOutputCollisionsBeforeWriting() throws {
		try withTemplateTemporaryDirectory { directory in
			let presentationURL = directory.appendingPathComponent("Source.pro")
			let themeURL = directory.appendingPathComponent("Theme Source/Theme")
			try writeTemplatePresentation(to: presentationURL)
			try writeTemplateTheme(to: themeURL)
			let sameOutput = directory.appendingPathComponent("same.json")
			#expect(throws: (any Error).self) {
				try Render.parse([
					presentationURL.path,
					"--format", "json",
					"--theme", themeURL.path,
					"--template", "Body Template",
					"--template-report", sameOutput.path,
					"--output", sameOutput.path,
				]).run()
			}
			#expect(!FileManager.default.fileExists(atPath: sameOutput.path))

			let imageOutput = directory.appendingPathComponent("Rendered")
			#expect(throws: (any Error).self) {
				try Render.parse([
					presentationURL.path,
					"--format", "png",
					"--theme", themeURL.path,
					"--template", "Body Template",
					"--template-report", imageOutput.appendingPathComponent("1.png").path,
					"--output", imageOutput.path,
				]).run()
			}
			#expect(!FileManager.default.fileExists(atPath: imageOutput.path))
		}
	}

	@Test
	func templateRelativeMediaKeepsItsOwnOriginWhenBasenamesCollide() throws {
		try withTemplateTemporaryDirectory { directory in
			let presentationURL = directory.appendingPathComponent("Source.pro")
			let themeURL = directory.appendingPathComponent("Theme Source/Theme")
			try writeTemplatePresentation(to: presentationURL)
			try writeTemplateTheme(to: themeURL)
			let sourceCollision = directory.appendingPathComponent("shared.png")
			let themeAsset = themeURL.deletingLastPathComponent().appendingPathComponent("shared.png")
			let redPixel = try onePixelPNG(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
			let bluePixel = try onePixelPNG(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
			#expect(redPixel != bluePixel)
			try redPixel.write(to: sourceCollision)
			try bluePixel.write(to: themeAsset)

			guard case var .presentation(sourcePresentation) = try DocumentLoader.loadRaw(presentationURL).payload else {
				Issue.record("Expected Presentation payload")
				return
			}
			var sourceMedia = Rv_Data_Media()
			sourceMedia.uuid.string = "SOURCE-MEDIA"
			sourceMedia.url.absoluteString = themeAsset.absoluteString
			sourceMedia.image.drawing.naturalSize.width = 1
			sourceMedia.image.drawing.naturalSize.height = 1
			sourcePresentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.enable = true
			sourcePresentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media = sourceMedia
			try DocumentWriter.writeRaw(
				ProPresenterDocument(payload: .presentation(sourcePresentation), origin: .raw(presentationURL)),
				to: presentationURL,
				replace: true,
			)

			let sourceOutputURL = directory.appendingPathComponent("source-media.json")
			try Render.parse([
				presentationURL.path,
				"--format", "json",
				"--output", sourceOutputURL.path,
			]).run()
			let sourceRendering = try JSONDecoder().decode(
				EffectiveRendering.self,
				from: Data(contentsOf: sourceOutputURL),
			)
			let sourceResolved = try #require(
				sourceRendering.presentations.first?.slides.first?.layers.first?.fill?.media?.resolvedSource,
			)
			#expect(URL(fileURLWithPath: sourceResolved).standardizedFileURL == sourceCollision.standardizedFileURL)

			guard case var .theme(theme) = try DocumentLoader.loadRaw(themeURL).payload else {
				Issue.record("Expected Theme payload")
				return
			}
			var media = Rv_Data_Media()
			media.uuid.string = "TEMPLATE-MEDIA"
			media.url.relativePath = "shared.png"
			media.image.drawing.naturalSize.width = 1
			media.image.drawing.naturalSize.height = 1
			theme.slides[0].baseSlide.elements[0].element.fill.enable = true
			theme.slides[0].baseSlide.elements[0].element.fill.media = media
			try DocumentWriter.writeRaw(
				ProPresenterDocument(payload: .theme(theme), origin: .raw(themeURL)),
				to: themeURL,
				replace: true,
			)

			let outputURL = directory.appendingPathComponent("media.json")
			try Render.parse([
				presentationURL.path,
				"--format", "json",
				"--theme", themeURL.path,
				"--template", "Body Template",
				"--output", outputURL.path,
			]).run()
			let rendering = try JSONDecoder().decode(EffectiveRendering.self, from: Data(contentsOf: outputURL))
			let resolved = try #require(rendering.presentations.first?.slides.first?.layers.first?.fill?.media?.resolvedSource)
			#expect(URL(fileURLWithPath: resolved).standardizedFileURL == themeAsset.standardizedFileURL)

			let portableDirectory = directory.appendingPathComponent("Portable Output")
			try FileManager.default.createDirectory(at: portableDirectory, withIntermediateDirectories: true)
			try onePixelPNG(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
				.write(to: portableDirectory.appendingPathComponent("shared.png"))
			let portableURL = portableDirectory.appendingPathComponent("Portable.pro")
			try EditApplyTemplate.parse([
				presentationURL.path,
				"--path", "/cues[index=0]",
				"--theme", themeURL.path,
				"--template", "Body Template",
				"--output", portableURL.path,
			]).run()
			let portable = try loadedPresentation(portableURL)
			let portableMedia = portable.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media
			guard case let .relativePath(relativePath)? = portableMedia.url.storage else {
				Issue.record("Expected materialized template media to use a relative path")
				return
			}
			#expect(relativePath == "shared-2.png")
			#expect(portableMedia.url.relativeFilePath == nil)
			#expect(FileManager.default.contentsEqual(
				atPath: themeAsset.path,
				andPath: portableDirectory.appendingPathComponent(relativePath).path,
			))
		}
	}

	@Test
	func archivedThemeMediaSurvivesRenderCreateAndDeferredBatchApplication() throws {
		try withTemplateTemporaryDirectory { directory in
			let presentationURL = directory.appendingPathComponent("Archived Source.pro")
			try writeTemplatePresentation(to: presentationURL)
			let themeContainer = directory.appendingPathComponent("Theme Export", isDirectory: true)
			let themeDirectory = themeContainer.appendingPathComponent("Archived Theme", isDirectory: true)
			let themeURL = themeDirectory.appendingPathComponent("Theme")
			try writeTemplateTheme(to: themeURL)
			let assetURL = themeDirectory.appendingPathComponent("archive.png")
			try onePixelPNG(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)).write(to: assetURL)
			guard case var .theme(theme) = try DocumentLoader.loadRaw(themeURL).payload else {
				Issue.record("Expected Theme payload")
				return
			}
			var media = Rv_Data_Media()
			media.uuid.string = "ARCHIVED-TEMPLATE-MEDIA"
			media.url.relativePath = "archive.png"
			media.image.drawing.naturalSize.width = 1
			media.image.drawing.naturalSize.height = 1
			theme.slides[0].baseSlide.elements[0].element.fill.enable = true
			theme.slides[0].baseSlide.elements[0].element.fill.media = media
			try DocumentWriter.writeRaw(
				ProPresenterDocument(payload: .theme(theme), origin: .raw(themeURL)),
				to: themeURL,
				replace: true,
			)
			let archiveURL = try DocumentArchive.bundle(
				themeContainer,
				to: directory.appendingPathComponent("Archived Theme.proTheme"),
			)

			let renderURL = directory.appendingPathComponent("archived-render.json")
			try Render.parse([
				presentationURL.path,
				"--format", "json",
				"--theme", archiveURL.path,
				"--template", "Body Template",
				"--output", renderURL.path,
			]).run()
			let rendering = try JSONDecoder().decode(EffectiveRendering.self, from: Data(contentsOf: renderURL))
			#expect(rendering.presentations.first?.slides.first?.layers.first?.fill?.media?.resolvedSource != nil)

			let createDirectory = directory.appendingPathComponent("Created", isDirectory: true)
			try FileManager.default.createDirectory(at: createDirectory, withIntermediateDirectories: true)
			let createdURL = createDirectory.appendingPathComponent("Created.pro")
			try CreatePresentation.parse([
				"--output", createdURL.path,
				"--theme", archiveURL.path,
				"--template", "Body Template",
			]).run()
			let created = try loadedPresentation(createdURL)
			let createdMedia = created.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media
			guard case let .relativePath(createdRelativePath)? = createdMedia.url.storage else {
				Issue.record("Expected created template media to use a relative path")
				return
			}
			#expect(FileManager.default.fileExists(atPath: createDirectory.appendingPathComponent(createdRelativePath).path))

			let batchURL = directory.appendingPathComponent("batch.json")
			let batch = [[
				"command": "apply-template",
				"path": "/cues[index=0]",
				"theme": archiveURL.path,
				"template": "Body Template",
			]]
			try JSONSerialization.data(withJSONObject: batch, options: [.prettyPrinted]).write(to: batchURL)
			let batchDirectory = directory.appendingPathComponent("Batch", isDirectory: true)
			try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
			let batchOutputURL = batchDirectory.appendingPathComponent("Batch.pro")
			try EditApply.parse([
				presentationURL.path,
				"--file", batchURL.path,
				"--output", batchOutputURL.path,
			]).run()
			let batchPresentation = try loadedPresentation(batchOutputURL)
			let batchMedia = batchPresentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media
			guard case let .relativePath(batchRelativePath)? = batchMedia.url.storage else {
				Issue.record("Expected batch template media to use a relative path")
				return
			}
			#expect(FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent(batchRelativePath).path))
		}
	}

	@Test
	func unresolvedTemplateMediaNeverFallsBackToSameNamedSourceAsset() throws {
		try withTemplateTemporaryDirectory { directory in
			let presentationURL = directory.appendingPathComponent("Source.pro")
			let themeURL = directory.appendingPathComponent("Theme Source/Theme")
			try writeTemplatePresentation(to: presentationURL)
			try writeTemplateTheme(to: themeURL)
			try onePixelPNG(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
				.write(to: directory.appendingPathComponent("missing.png"))
			guard case var .theme(theme) = try DocumentLoader.loadRaw(themeURL).payload else {
				Issue.record("Expected Theme payload")
				return
			}
			var media = Rv_Data_Media()
			media.uuid.string = "MISSING-TEMPLATE-MEDIA"
			media.url.relativePath = "missing.png"
			media.image.drawing.naturalSize.width = 1
			media.image.drawing.naturalSize.height = 1
			theme.slides[0].baseSlide.elements[0].element.fill.enable = true
			theme.slides[0].baseSlide.elements[0].element.fill.media = media
			try DocumentWriter.writeRaw(
				ProPresenterDocument(payload: .theme(theme), origin: .raw(themeURL)),
				to: themeURL,
				replace: true,
			)

			let outputURL = directory.appendingPathComponent("missing.json")
			try Render.parse([
				presentationURL.path,
				"--format", "json",
				"--theme", themeURL.path,
				"--template", "Body Template",
				"--output", outputURL.path,
			]).run()
			let rendering = try JSONDecoder().decode(EffectiveRendering.self, from: Data(contentsOf: outputURL))
			let resolved = rendering.presentations.first?.slides.first?.layers.first?.fill?.media?.resolvedSource
			#expect(resolved == nil)
		}
	}
}

private func writeTemplatePresentation(to url: URL) throws {
	var presentation = DocumentFactory.presentation(
		name: "Source",
		canvasSize: CGSize(width: 800, height: 600),
	)
	var slide = presentation.cues[0].actions[0].slide.presentation.baseSlide
	slide.uuid.string = "SOURCE-SLIDE"
	slide.elements = try [commandTextElement(
		uuid: "SOURCE-BODY",
		name: "Body",
		bounds: CGRect(x: 0, y: 0, width: 400, height: 100),
		text: "SOURCE WORDS",
		fontName: "Helvetica",
		fontSize: 30,
		color: .white,
	)]
	presentation.cues[0].actions[0].slide.presentation.baseSlide = slide
	try DocumentWriter.writeRaw(
		ProPresenterDocument(payload: .presentation(presentation), origin: .raw(url)),
		to: url,
	)
}

private func writeTemplateTheme(to url: URL) throws {
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	var template = Rv_Data_Template.Slide()
	template.name = "Body Template"
	template.baseSlide.uuid.string = "TEMPLATE-SLIDE"
	template.baseSlide.size.width = 400
	template.baseSlide.size.height = 300
	template.baseSlide.elements = try [commandTextElement(
		uuid: "TEMPLATE-BODY",
		name: "Body",
		bounds: CGRect(x: 10, y: 20, width: 200, height: 100),
		text: "SAMPLE",
		fontName: "Courier New",
		fontSize: 20,
		color: .yellow,
	)]
	var theme = DocumentFactory.theme()
	theme.slides = [template]
	try DocumentWriter.writeRaw(
		ProPresenterDocument(payload: .theme(theme), origin: .raw(url)),
		to: url,
	)
}

private func writeWorkspace(to root: URL, themeURL: URL) throws {
	var physical = Rv_Data_Screen()
	physical.uuid.string = "PHYSICAL"
	physical.bounds.size.width = 1280
	physical.bounds.size.height = 720
	var arrangement = Rv_Data_ProPresenterScreen.SingleArrangement()
	arrangement.screens = [physical]
	var audience = Rv_Data_ProPresenterScreen()
	audience.uuid.string = "AUDIENCE"
	audience.name = "Projector"
	audience.screenType = .audience
	audience.arrangementSingle = arrangement

	var mapping = Rv_Data_ProAudienceLook.ProScreenLook()
	mapping.proScreenUuid = audience.uuid
	mapping.presentationBackgroundEnabled = true
	mapping.presentationForegroundEnabled = true
	mapping.templateDocumentFilePath.absoluteString = themeURL.absoluteString
	mapping.templateSlideUuid.string = "TEMPLATE-SLIDE"
	var look = Rv_Data_ProAudienceLook()
	look.uuid.string = "LOOK"
	look.name = "Stream Match"
	look.screenLooks = [mapping]
	var workspace = Rv_Data_ProPresenterWorkspace()
	workspace.proScreens = [audience]
	workspace.audienceLooks = [look]
	let file = root.appendingPathComponent("Configuration/Workspace")
	try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
	try workspace.serializedData().write(to: file)
}

private func commandTextElement(
	uuid value: String,
	name: String,
	bounds: CGRect,
	text: String,
	fontName: String,
	fontSize: CGFloat,
	color: NSColor,
) throws -> Rv_Data_Slide.Element {
	let font = try #require(NSFont(name: fontName, size: fontSize))
	let attributed = NSAttributedString(
		string: text,
		attributes: [.font: font, .foregroundColor: color],
	)
	var element = Rv_Data_Graphics.Element()
	element.uuid.string = value
	element.name = name
	element.opacity = 1
	element.bounds.origin.x = bounds.origin.x
	element.bounds.origin.y = bounds.origin.y
	element.bounds.size.width = bounds.width
	element.bounds.size.height = bounds.height
	element.text.rtfData = try attributed.data(
		from: NSRange(location: 0, length: attributed.length),
		documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
	)
	element.text.attributes.font.name = font.fontName
	element.text.attributes.font.family = font.familyName ?? ""
	element.text.attributes.font.size = font.pointSize
	element.text.attributes.textSolidFill = commandColor(color)
	var result = Rv_Data_Slide.Element()
	result.element = element
	return result
}

private func commandColor(_ value: NSColor) -> Rv_Data_Color {
	let value = value.usingColorSpace(.deviceRGB) ?? value
	var color = Rv_Data_Color()
	color.red = Float(value.redComponent)
	color.green = Float(value.greenComponent)
	color.blue = Float(value.blueComponent)
	color.alpha = Float(value.alphaComponent)
	return color
}

private func decodeText(_ element: Rv_Data_Slide.Element) throws -> NSAttributedString {
	try NSAttributedString(
		data: element.element.text.rtfData,
		options: [.documentType: NSAttributedString.DocumentType.rtf],
		documentAttributes: nil,
	)
}

private func loadedPresentation(_ url: URL) throws -> Rv_Data_Presentation {
	guard case let .presentation(presentation) = try DocumentLoader.load(from: url).payload else {
		throw CocoaError(.fileReadCorruptFile)
	}
	return presentation
}

private func withTemplateTemporaryDirectory<Result>(_ operation: (URL) throws -> Result) throws -> Result {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("pro-crud-template-command-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: directory) }
	return try operation(directory)
}

private func onePixelPNG(_ color: NSColor = .white) throws -> Data {
	let bitmap = try #require(NSBitmapImageRep(
		bitmapDataPlanes: nil,
		pixelsWide: 1,
		pixelsHigh: 1,
		bitsPerSample: 8,
		samplesPerPixel: 4,
		hasAlpha: true,
		isPlanar: false,
		colorSpaceName: .deviceRGB,
		bytesPerRow: 4,
		bitsPerPixel: 32,
	))
	let converted = try #require(color.usingColorSpace(.deviceRGB))
	let bytes = try #require(bitmap.bitmapData)
	bytes[0] = UInt8((converted.redComponent * 255).rounded())
	bytes[1] = UInt8((converted.greenComponent * 255).rounded())
	bytes[2] = UInt8((converted.blueComponent * 255).rounded())
	bytes[3] = UInt8((converted.alphaComponent * 255).rounded())
	return try #require(bitmap.representation(using: .png, properties: [:]))
}
