import AppKit
import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCLI
@testable import ProCRUDCore

@Suite("Screen, Look, and Macro rendering")
struct LookRenderCommandTests {
	@Test func nestedMacrosAndDirectLookActionsCarryForwardInSelectedCueOrder() throws {
		try withFixture { fixture in
			var document = fixture.document
			document.presentation.cues[0].actions.append(fixture.macroAction(fixture.parent))
			document.presentation.cues[2].actions.append(fixture.lookAction(fixture.plain))
			let configuration = try RenderConfiguration(workspace: fixture.root)
			let screen = try #require(configuration.selectScreens(["Stream"]).first)
			let result = try PresentationLookResolver.resolve(document: document, configuration: configuration, screen: screen)
			#expect(result.reports.map { $0.context?.lookName } == ["Alternate", "Alternate", "Plain"])
			#expect(result.reports.map { $0.context?.slideIndex } == [1, 2, 3])
			#expect(result.reports.map(\.templateName) == ["Stream Theme", "Stream Theme", "Source slide (no alternate Theme)"])
			#expect(result.document.presentation == document.presentation)
			let slides = try PresentationRenderer(document: result.document).effectiveRendering().slides
			#expect(slides.allSatisfy { $0.canvasSize.width == 160 && $0.canvasSize.height == 90 })
			#expect(slides[0].layers.first?.name == "Template panel")
		}
	}

	@Test func fixedLookAndMacroIgnoreAttachedActionsAndDefaultToMainScreen() throws {
		try withFixture { fixture in
			var source = fixture.document
			source.presentation.cues[0].actions.append(fixture.macroAction(UUID().uuidString))
			try fixture.write(source)
			let before = try Data(contentsOf: fixture.input)
			for options in [["--look", "Alternate"], ["--macro", fixture.parent.lowercased()]] {
				let output = fixture.directory.appendingPathComponent(UUID().uuidString + ".json")
				try Render.parse([fixture.input.path, "--workspace", fixture.root.path, "--format", "json", "--output", output.path] + options).run()
				let rendering = try JSONDecoder().decode(EffectiveRendering.self, from: Data(contentsOf: output))
				#expect(rendering.presentations.first?.screen?.name == "Main")
				#expect(rendering.presentations.first?.slides.allSatisfy { $0.canvasSize.width == 320 } == true)
			}
			#expect(try Data(contentsOf: fixture.input) == before)
		}
	}

	@Test func selectedSlideUsesEarlierLookActionsWithoutResolvingUnselectedContentOrLaterActions() throws {
		try withFixture { fixture in
			var source = fixture.document
			source.presentation.cues[0].actions.append(fixture.macroAction(fixture.parent))
			source.presentation.cues[0].actions[0].slide.presentation.baseSlide.size.width = 0
			source.presentation.cues[2].actions.append(fixture.macroAction(UUID().uuidString))
			let configuration = try RenderConfiguration(workspace: fixture.root)
			let result = try PresentationLookResolver.resolve(document: source, configuration: configuration, screen: #require(configuration.selectScreens(["Stream"]).first), slideIndices: [1])
			#expect(result.reports.count == 1)
			#expect(result.reports.first?.context?.lookName == "Alternate")
			#expect(result.reports.first?.context?.slideIndex == 2)
			#expect(try PresentationRenderer(document: result.document).effectiveRendering(slideIndices: [1]).slides.count == 1)
		}
	}

	@Test func repeatedArrangementCueCanHaveDifferentLookStateAtEachOccurrence() throws {
		try withFixture { fixture in
			var source = fixture.document
			source.presentation.cues[1].actions.append(fixture.lookAction(fixture.alternate))
			let first = Rv_Data_Presentation.CueGroup.with { $0.group.uuid.string = UUID().uuidString; $0.group.name = "A"; $0.cueIdentifiers = [source.presentation.cues[0].uuid] }
			let second = Rv_Data_Presentation.CueGroup.with { $0.group.uuid.string = UUID().uuidString; $0.group.name = "B"; $0.cueIdentifiers = [source.presentation.cues[1].uuid] }
			source.presentation.cueGroups = [first, second]
			let arrangement = Rv_Data_Presentation.Arrangement.with { $0.uuid.string = UUID().uuidString; $0.name = "Repeat"; $0.groupIdentifiers = [first.group.uuid, second.group.uuid, first.group.uuid] }
			source.presentation.arrangements = [arrangement]
			source.arrangementSelection = .uuid(arrangement.uuid.string)
			let configuration = try RenderConfiguration(workspace: fixture.root)
			let result = try PresentationLookResolver.resolve(document: source, configuration: configuration, screen: #require(configuration.selectScreens(["Stream"]).first))
			#expect(result.reports.map { $0.context?.lookName } == ["Plain", "Alternate", "Alternate"])
			let slides = try PresentationRenderer(document: result.document).effectiveRendering().slides
			#expect(slides[0].uuid == slides[2].uuid)
			#expect(slides[0].layers.first?.name == "Source panel")
			#expect(slides[2].layers.first?.name == "Template panel")
			#expect(slides.map(\.index) == [0, 1, 2])
		}
	}

	@Test func bundleRendersMultipleScreensAndAllFormatsWithScreenAndSlideDiagnostics() throws {
		try withFixture { fixture in
			let bundle = try DocumentArchive.bundle(fixture.input, to: fixture.directory.appendingPathComponent("Source.probundle"))
			let before = try Data(contentsOf: bundle)
			for options in [["--screens", "all"], ["--screen", "Main", "--screen", "Stream"], ["--screens", "Main", "Stream"]] {
				let output = fixture.directory.appendingPathComponent(UUID().uuidString)
				let report = fixture.directory.appendingPathComponent(UUID().uuidString + ".json")
				try Render.parse([bundle.path, "--workspace", fixture.root.path, "--macro", "Parent", "--format", "png,pdf,json", "--output", output.path, "--template-report", report.path] + options).run()
				let rendering = try JSONDecoder().decode(EffectiveRendering.self, from: Data(contentsOf: output.appendingPathComponent("Source.json")))
				#expect(rendering.presentations.map { $0.screen?.name } == ["Main", "Stream"])
				#expect(rendering.presentations.map(\.slides.count) == [3, 3])
				let reports = try JSONDecoder().decode([TemplateResolutionReport].self, from: Data(contentsOf: report))
				#expect(reports.count == 6)
				let files = try FileManager.default.subpathsOfDirectory(atPath: output.path)
				#expect(files.count(where: { $0.hasSuffix(".png") }) == 6)
				#expect(try String(decoding: Data(contentsOf: output.appendingPathComponent("Source.pdf")).prefix(4), as: UTF8.self) == "%PDF")
				let image = try #require(files.first { $0.contains("Stream-") && $0.hasSuffix("1.png") })
				let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: output.appendingPathComponent(image))))
				#expect(bitmap.pixelsWide == 160 && bitmap.pixelsHigh == 90)
			}
			#expect(try Data(contentsOf: bundle) == before)
		}
	}

	@Test func cyclesMissingReferencesAndTimedLookChangesFailBeforeReplacingOutput() throws {
		try withFixture { fixture in
			let output = fixture.directory.appendingPathComponent("existing.json")
			let sentinel = Data("keep output".utf8)
			try sentinel.write(to: output)
			var cycle = fixture.macroAction(fixture.parent)
			let macrosURL = fixture.root.appendingPathComponent("Configuration/Macros")
			let macros = Rv_Data_MacrosDocument.with {
				$0.macros = [.with { $0.uuid.string = fixture.parent; $0.name = "Parent"; $0.actions = [cycle] }]
			}
			try macros.serializedData().write(to: macrosURL)
			let arguments = [fixture.input.path, "--workspace", fixture.root.path, "--macro", "Parent", "--format", "json", "--output", output.path, "--replace"]
			#expect(throws: RenderConfigurationError.self) { try Render.parse(arguments).run() }
			#expect(try Data(contentsOf: output) == sentinel)
			cycle = fixture.lookAction(UUID().uuidString)
			cycle.audienceLook.identification.parameterName = "Alternate"
			for delayed in [false, true] {
				if delayed {
					cycle = fixture.lookAction(fixture.alternate); cycle.delayTime = 1
				}
				let invalid = Rv_Data_MacrosDocument.with { $0.macros = [.with { $0.uuid.string = fixture.parent; $0.name = "Parent"; $0.actions = [cycle] }] }
				try invalid.serializedData().write(to: macrosURL)
				#expect(throws: RenderConfigurationError.self) { try Render.parse(arguments).run() }
				#expect(try Data(contentsOf: output) == sentinel)
			}
		}
	}

	@Test func disabledActionsDoNotChangeLookAndAmbiguousNamesFail() throws {
		try withFixture { fixture in
			var source = fixture.document
			var action = fixture.macroAction(UUID().uuidString)
			action.isEnabled = false
			source.presentation.cues[0].actions.append(action)
			let configuration = try RenderConfiguration(workspace: fixture.root)
			let result = try PresentationLookResolver.resolve(document: source, configuration: configuration, screen: #require(configuration.selectScreens().first))
			#expect(result.reports.allSatisfy { $0.context?.lookName == "Plain" })
			let workspaceURL = fixture.root.appendingPathComponent("Configuration/Workspace")
			var workspace = try Rv_Data_ProPresenterWorkspace(serializedBytes: Data(contentsOf: workspaceURL))
			workspace.audienceLooks[1].name = workspace.audienceLooks[0].name
			try workspace.serializedData().write(to: workspaceURL)
			#expect(throws: RenderConfigurationError.self) { try RenderConfiguration(workspace: fixture.root).look("Plain") }
			#expect(throws: RenderConfigurationError.self) { try configuration.selectScreens(["missing"]) }
		}
	}

	@Test func outputScreenLinksRenderTheReferencedVariationAndRejectCycles() throws {
		try withFixture { fixture in
			let url = fixture.root.appendingPathComponent("Themes/Owned/Theme")
			var theme = try Rv_Data_Template.Document(serializedBytes: Data(contentsOf: url))
			theme.slides[0].baseSlide.elements[0].dataLinks = [.with { $0.outputScreen.screenID.string = fixture.main }]
			try theme.serializedData().write(to: url)
			var source = fixture.document
			for index in source.presentation.cues.indices {
				var element = source.presentation.cues[index].actions[0].slide.presentation.baseSlide.elements[0].element
				element.bounds.size.width = 160; element.bounds.size.height = 90
				element.fill.color.red = 1; element.fill.color.blue = 0
				source.presentation.cues[index].actions[0].slide.presentation.baseSlide.elements[0].element = element
			}
			let configuration = try RenderConfiguration(workspace: fixture.root)
			let screen = try #require(configuration.selectScreens(["Stream"]).first)
			let result = try PresentationLookResolver.resolve(document: source, configuration: configuration, screen: screen, look: "Alternate", slideIndices: [0])
			let cue = try #require(result.document.cueOccurrences().first?.cue)
			let media = try #require(cue.actions.first?.slide.presentation.baseSlide.elements.first?.element.fill.media)
			let imageURL = try #require(URL(string: media.url.absoluteString))
			let image = try #require(NSBitmapImageRep(data: Data(contentsOf: imageURL)))
			#expect(image.pixelsWide == 320 && image.pixelsHigh == 180)
			let pixel = try #require(image.colorAt(x: 160, y: 90)?.usingColorSpace(.deviceRGB))
			#expect(pixel.redComponent > 0.99 && pixel.blueComponent < 0.01)
			#expect(source.renderCueOverrides.isEmpty)
			theme.slides[0].baseSlide.elements[0].dataLinks[0].outputScreen.screenID.string = fixture.stream
			try theme.serializedData().write(to: url)
			#expect(throws: RenderConfigurationError.self) { try PresentationLookResolver.resolve(document: source, configuration: RenderConfiguration(workspace: fixture.root), screen: screen, look: "Alternate", slideIndices: [0]) }
		}
	}

	@Test func workspaceOutputsCannotReplaceConfigurationOrItsParent() throws {
		try withFixture { fixture in
			let workspace = fixture.root.appendingPathComponent("Configuration/Workspace")
			let original = try Data(contentsOf: workspace)
			for output in [fixture.root, fixture.directory, workspace] {
				#expect(throws: (any Error).self) {
					try Render.parse([fixture.input.path, "--workspace", fixture.root.path, "--look", "Plain", "--output", output.path, "--replace"]).run()
				}
			}
			#expect(try Data(contentsOf: workspace) == original)
		}
	}

	@Test func screenLinksOnlyResolveTheReferencedCueOccurrence() throws {
		try withFixture { fixture in
			let themeURL = fixture.root.appendingPathComponent("Themes/Owned/Theme")
			var theme = try Rv_Data_Template.Document(serializedBytes: Data(contentsOf: themeURL))
			theme.slides[0].baseSlide.elements[0].dataLinks = [.with { $0.outputScreen.screenID.string = fixture.main }]
			try theme.serializedData().write(to: themeURL)
			let mainThemeURL = fixture.root.appendingPathComponent("Themes/Main/Theme")
			try FileManager.default.createDirectory(at: mainThemeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			theme.slides[0].baseSlide.uuid.string = UUID().uuidString
			theme.slides[0].baseSlide.elements[0].dataLinks[0].outputScreen.screenID.string = fixture.stream
			try theme.serializedData().write(to: mainThemeURL)
			let workspaceURL = fixture.root.appendingPathComponent("Configuration/Workspace")
			var workspace = try Rv_Data_ProPresenterWorkspace(serializedBytes: Data(contentsOf: workspaceURL))
			workspace.audienceLooks[0].screenLooks[0].templateSlideUuid = theme.slides[0].baseSlide.uuid
			workspace.audienceLooks[0].screenLooks[0].templateDocumentFilePath.local.root = .show
			workspace.audienceLooks[0].screenLooks[0].templateDocumentFilePath.local.path = "Themes/Main/Theme"
			try workspace.serializedData().write(to: workspaceURL)
			var document = fixture.document
			document.presentation.cues[0].actions.append(fixture.lookAction(fixture.alternate))
			document.presentation.cues[1].actions.append(fixture.lookAction(fixture.plain))
			let configuration = try RenderConfiguration(workspace: fixture.root)
			let screen = try #require(configuration.selectScreens(["Stream"]).first)
			let result = try PresentationLookResolver.resolve(document: document, configuration: configuration, screen: screen)
			#expect(result.reports.count == 3)
		}
	}

	@Test func workspaceRelativeThemeWinsOverAReachableAbsolutePathFromAnotherLibrary() throws {
		try withFixture { fixture in
			let themeURL = fixture.root.appendingPathComponent("Themes/Owned/Theme")
			var decoy = try Rv_Data_Template.Document(serializedBytes: Data(contentsOf: themeURL))
			decoy.slides[0].name = "Wrong library"
			let decoyURL = fixture.directory.appendingPathComponent("WrongTheme")
			try decoy.serializedData().write(to: decoyURL)
			let workspaceURL = fixture.root.appendingPathComponent("Configuration/Workspace")
			var workspace = try Rv_Data_ProPresenterWorkspace(serializedBytes: Data(contentsOf: workspaceURL))
			workspace.audienceLooks[1].screenLooks[1].templateDocumentFilePath.absoluteString = decoyURL.absoluteString
			try workspace.serializedData().write(to: workspaceURL)
			let selection = try LookResolver.resolve(workspace: fixture.root, look: "Alternate", screen: "Stream")
			#expect(selection.template.name == "Stream Theme")
		}
	}

	@Test func noAlternateThemePreservesAnUnscaledSlideAndMediaOnlyCuesUseTheScreenCanvas() throws {
		try withFixture { fixture in
			let configuration = try RenderConfiguration(workspace: fixture.root)
			let screen = try #require(configuration.selectScreens(["Stream"]).first)
			var source = fixture.document
			let original = source.presentation.cues[0].actions[0].slide.presentation.baseSlide
			source.presentation.cues[1].actions = []
			let result = try PresentationLookResolver.resolve(document: source, configuration: configuration, screen: screen, look: "Plain")
			let cues = try result.document.cueOccurrences()
			#expect(cues[0].cue.actions[0].slide.presentation.baseSlide == original)
			let rendering = try PresentationRenderer(document: result.document).effectiveRendering()
			#expect(rendering.slides[1].canvasSize.width == 160 && rendering.slides[1].canvasSize.height == 90)
		}
	}

	private func withFixture(_ body: (Fixture) throws -> Void) throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let fixture = Fixture(directory: directory)
		try fixture.install()
		try body(fixture)
	}

	private struct Fixture {
		let directory: URL
		let plain = UUID().uuidString
		let alternate = UUID().uuidString
		let parent = UUID().uuidString
		let child = UUID().uuidString
		let main = UUID().uuidString
		let stream = UUID().uuidString
		let template = UUID().uuidString
		var root: URL {
			directory.appendingPathComponent("Workspace")
		}

		var input: URL {
			directory.appendingPathComponent("Source.pro")
		}

		var document: PresentationDocument {
			var presentation = DocumentFactory.presentation(name: "Source", canvasSize: CGSize(width: 160, height: 90))
			let original = presentation.cues[0]
			presentation.cues = (0 ..< 3).map { number in
				var cue = original
				cue.uuid.string = UUID().uuidString
				cue.name = "Slide \(number + 1)"
				cue.actions[0].uuid.string = UUID().uuidString
				cue.actions[0].slide.presentation.baseSlide.uuid.string = UUID().uuidString
				cue.actions[0].slide.presentation.baseSlide.elements = [panel("Source panel")]
				return cue
			}
			presentation.cueGroups[0].cueIdentifiers = presentation.cues.map(\.uuid)
			return .init(presentation: presentation)
		}

		func lookAction(_ uuid: String) -> Rv_Data_Action {
			.with { $0.uuid.string = UUID().uuidString; $0.type = .audienceLook; $0.isEnabled = true; $0.audienceLook.identification.parameterUuid.string = uuid }
		}

		func macroAction(_ uuid: String) -> Rv_Data_Action {
			.with { $0.uuid.string = UUID().uuidString; $0.type = .macro; $0.isEnabled = true; $0.macro.identification.parameterUuid.string = uuid }
		}

		func panel(_ name: String) -> Rv_Data_Slide.Element {
			.with {
				$0.element.uuid.string = UUID().uuidString
				$0.element.name = name; $0.element.opacity = 1
				$0.element.bounds.size.width = 40; $0.element.bounds.size.height = 20
				$0.element.fill.enable = true; $0.element.fill.color.blue = 1; $0.element.fill.color.alpha = 1
			}
		}

		func write(_ document: PresentationDocument) throws {
			try document.presentation.serializedData().write(to: input)
		}

		func install() throws {
			let configuration = root.appendingPathComponent("Configuration")
			let themeURL = root.appendingPathComponent("Themes/Owned/Theme")
			try FileManager.default.createDirectory(at: configuration, withIntermediateDirectories: true)
			try FileManager.default.createDirectory(at: themeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			let theme = Rv_Data_Template.Document.with { $0.slides = [.with { $0.name = "Stream Theme"; $0.baseSlide.uuid.string = template; $0.baseSlide.size.width = 160; $0.baseSlide.size.height = 90; $0.baseSlide.elements = [panel("Template panel")] }] }
			try theme.serializedData().write(to: themeURL)
			func screen(_ name: String, uuid: String, width: Double) -> Rv_Data_ProPresenterScreen {
				.with { $0.name = name; $0.uuid.string = uuid; $0.screenType = .audience; $0.arrangementSingle.screens = [.with { $0.bounds.size.width = width; $0.bounds.size.height = width * 9 / 16 }] }
			}
			func mapping(_ uuid: String, themed: Bool) -> Rv_Data_ProAudienceLook.ProScreenLook {
				.with {
					$0.proScreenUuid.string = uuid; $0.presentationBackgroundEnabled = true; $0.presentationForegroundEnabled = true
					if themed {
						$0.templateSlideUuid.string = template; $0.templateDocumentFilePath.local.root = .show; $0.templateDocumentFilePath.local.path = "Themes/Owned/Theme"
					}
				}
			}
			let plainLook = Rv_Data_ProAudienceLook.with { $0.uuid.string = plain; $0.name = "Plain"; $0.screenLooks = [mapping(main, themed: false), mapping(stream, themed: false)] }
			let alternateLook = Rv_Data_ProAudienceLook.with { $0.uuid.string = alternate; $0.name = "Alternate"; $0.screenLooks = [mapping(main, themed: false), mapping(stream, themed: true)] }
			let workspace = Rv_Data_ProPresenterWorkspace.with { $0.proScreens = [screen("Main", uuid: main, width: 320), screen("Stream", uuid: stream, width: 160)]; $0.audienceLooks = [plainLook, alternateLook]; $0.liveAudienceLook = plainLook }
			try workspace.serializedData().write(to: configuration.appendingPathComponent("Workspace"))
			let macros = Rv_Data_MacrosDocument.with { $0.macros = [.with { $0.uuid.string = parent; $0.name = "Parent"; $0.actions = [macroAction(child)] }, .with { $0.uuid.string = child; $0.name = "Child"; $0.actions = [lookAction(alternate)] }] }
			try macros.serializedData().write(to: configuration.appendingPathComponent("Macros"))
			try write(document)
		}
	}
}
