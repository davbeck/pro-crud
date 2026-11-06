import AppKit
import CustomDump
import Foundation
import PDFKit
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite("Build step render command")
struct BuildStepRenderCommandTests {
	@Test func selectedSlideProducesIndividualImagesAndPDFPages() throws {
		try withPresentation { input, directory in
			let output = directory.appendingPathComponent("Preview")
			try Render.parse([input.path, "--build-steps", "--slide", "2", "--format", "png,pdf", "--output", output.path]).run()
			try expectNoDifference(FileManager.default.contentsOfDirectory(atPath: output.path).sorted(), ["2-build-0.png", "2-build-1.png", "2-build-2.png", "Deck.pdf"])
			let pdf = try #require(PDFDocument(url: output.appendingPathComponent("Deck.pdf")))
			expectNoDifference(pdf.pageCount, 3)
			let document = try PresentationLoader.load(from: input)
			let renderer = PresentationRenderer(document: document)
			let normal = directory.appendingPathComponent("Normal")
			_ = try renderer.render(options: RenderOptions(outputDirectory: normal), slideIndices: [1])
			try expectNoDifference(
				Data(contentsOf: output.appendingPathComponent("2-build-2.png")),
				Data(contentsOf: normal.appendingPathComponent("2.png")),
			)
			let initial = try Data(contentsOf: output.appendingPathComponent("2-build-0.png"))
			#expect(try initial != Data(contentsOf: output.appendingPathComponent("2-build-1.png")))
			// --merge checks the actual build filenames before writing any images.
			#expect(throws: (any Error).self) {
				try Render.parse([input.path, "--build-steps", "--slide", "2", "--output", output.path, "--merge"]).run()
			}
			try expectNoDifference(Data(contentsOf: output.appendingPathComponent("2-build-0.png")), initial)
		}
	}

	@Test func objectBuildInAndOutChangeRenderedVisibility() throws {
		try withPresentation { input, directory in
			var presentation = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: input))
			var slide = presentation.cues[1].actions[0].slide.presentation.baseSlide
			slide.elements[0].revealType = .none
			slide.elements[0].childBuilds = []
			slide.elements[0].buildOut.uuid.string = "OUT"
			slide.elementBuildOrder = [slide.elements[0].buildIn.uuid, slide.elements[0].buildOut.uuid]
			presentation.cues[1].actions[0].slide.presentation.baseSlide = slide
			try presentation.serializedData().write(to: input)
			let output = directory.appendingPathComponent("Objects")
			try Render.parse([input.path, "--build-steps", "--slide", "2", "--output", output.path]).run()
			let initial = try Data(contentsOf: output.appendingPathComponent("2-build-0.png"))
			let builtIn = try Data(contentsOf: output.appendingPathComponent("2-build-1.png"))
			let builtOut = try Data(contentsOf: output.appendingPathComponent("2-build-2.png"))
			#expect(initial != builtIn)
			expectNoDifference(builtOut, initial)
		}
	}

	@Test func defaultRenderingAndSlidesWithoutBuildsKeepExistingNames() throws {
		try withPresentation { input, directory in
			let output = directory.appendingPathComponent("Default")
			try Render.parse([input.path, "--output", output.path]).run()
			try expectNoDifference(FileManager.default.contentsOfDirectory(atPath: output.path).sorted(), ["1.png", "2.png"])
			let plain = directory.appendingPathComponent("Plain")
			try Render.parse([input.path, "--build-steps", "--slide", "1", "--output", plain.path]).run()
			try expectNoDifference(FileManager.default.contentsOfDirectory(atPath: plain.path), ["1.png"])
		}
	}

	@Test func invalidBuildsAndJSONFailBeforeReplacingOutput() throws {
		try withPresentation { input, directory in
			let output = directory.appendingPathComponent("existing.pdf")
			let sentinel = Data("keep output".utf8)
			try sentinel.write(to: output)
			#expect(throws: (any Error).self) {
				try Render.parse([input.path, "--build-steps", "--format", "json", "--output", output.path, "--replace"]).run()
			}
			var presentation = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: input))
			presentation.cues[1].actions[0].slide.presentation.baseSlide.elements[0].revealType = .underline
			try presentation.serializedData().write(to: input)
			#expect(throws: RenderError.self) {
				try Render.parse([input.path, "--build-steps", "--format", "pdf", "--output", output.path, "--replace"]).run()
			}
			try expectNoDifference(Data(contentsOf: output), sentinel)
		}
	}

	private func withPresentation(_ body: (URL, URL) throws -> Void) throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		var slide = try Rv_Data_Slide(jsonUTF8Data: Data(contentsOf: root.appendingPathComponent("Fixtures/ProPresenter/TextDelivery/two.json")))
		// Smaller canvas keeps the export test inexpensive; the native text graph is unchanged.
		slide.size.width = 480
		slide.size.height = 270
		slide.elements[0].element.bounds.origin.x = 20
		slide.elements[0].element.bounds.origin.y = 20
		slide.elements[0].element.bounds.size.width = 440
		slide.elements[0].element.bounds.size.height = 230
		var presentation = DocumentFactory.presentation(name: "Deck", canvasSize: CGSize(width: 480, height: 270))
		var builtCue = presentation.cues[0]
		builtCue.uuid.string = UUID().uuidString
		builtCue.actions[0].slide.presentation.baseSlide = slide
		presentation.cues.append(builtCue)
		presentation.cueGroups[0].cueIdentifiers.append(builtCue.uuid)
		let input = directory.appendingPathComponent("Deck.pro")
		try presentation.serializedData().write(to: input)
		try body(input, directory)
	}
}
