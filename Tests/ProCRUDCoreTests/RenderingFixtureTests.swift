import AppKit
import Foundation
import ProCRUDCore
import SnapshotTesting
import Testing

@Suite("Element Layering", .snapshots(diffTool: .ksdiff), .timeLimit(.minutes(1)))
struct ElementLayeringRenderingFixtureTests {
	@Test("Reverse Stored Element Paint Order")
	func reverseStoredElementPaintOrder() throws {
		let presentations = try PresentationLoader.loadPresentations(
			from: fixtureURL("ProPresenter/ReferenceSlides.proPlaylist"),
		)
		let document = try #require(presentations.first(where: {
			$0.sourceName.replacing(/^\d+\s*-\s*/, with: "") == "Element Layering"
		})?.document)
		let action = try #require(document.orderedCues.first?.actions.first)
		#expect(action.type == .presentationSlide)
		let baseSlide = action.slide.presentation.baseSlide
		#expect(baseSlide.elements.map(\.info) == [0, 2, 1])

		let rendering = try PresentationRenderer.effectiveRendering(documents: [document])
		let effectiveSlide = try #require(rendering.presentations.first?.slides.first)
		#expect(effectiveSlide.layers.map(\.sourceIndex) == [2, 1, 0])

		try assertRenderingFixture(in: "Element Layering", slideNumber: 1)
	}
}

@Suite("Text Attributes", .snapshots(diffTool: .ksdiff), .timeLimit(.minutes(1)))
struct TextAttributesRenderingFixtureTests {
	@Test("Capitalization")
	func capitalization() throws {
		try assertRenderingFixture(in: "Text Attributes", slideNumber: 9)
	}

	@Test("Strikethrough")
	func strikethrough() throws {
		try assertRenderingFixture(
			in: "Text Attributes",
			slideNumber: 7,
		)
	}

	@Test("Baseline Offset")
	func baselineOffset() throws {
		try assertRenderingFixture(
			in: "Text Attributes",
			slideNumber: 12,
		)
	}

	@Test("Line Spacing")
	func lineSpacing() throws {
		try assertRenderingFixture(in: "Text Attributes", slideNumber: 3)
	}

	@Test("Line Height")
	func lineHeight() throws {
		try assertRenderingFixture(
			in: "Text Attributes",
			slideNumber: 2,
		)
	}

	@Test("Character Spacing")
	func characterSpacing() throws {
		try assertRenderingFixture(in: "Text Attributes", slideNumber: 11)
	}

	@Test("Bold")
	func bold() throws {
		try assertRenderingFixture(in: "Text Attributes", slideNumber: 4)
	}

	@Test("Foreground Color")
	func foregroundColor() throws {
		try assertRenderingFixture(in: "Text Attributes", slideNumber: 8)
	}

	@Test("Italic")
	func italic() throws {
		try assertRenderingFixture(in: "Text Attributes", slideNumber: 5)
	}

	@Test("Underline")
	func underline() throws {
		try assertRenderingFixture(in: "Text Attributes", slideNumber: 6)
	}

	@Test("Background and Foreground Colors")
	func backgroundAndForegroundColors() throws {
		try assertRenderingFixture(in: "Text Attributes", slideNumber: 10)
	}

	@Test("Paragraph Spacing")
	func paragraphSpacing() throws {
		try assertRenderingFixture(in: "Text Attributes", slideNumber: 1)
	}
}

@Suite("Text Scaling", .snapshots(diffTool: .ksdiff), .timeLimit(.minutes(1)))
struct TextScalingRenderingFixtureTests {
	@Test("Scale Font Up - Small Text")
	func scaleFontUpSmallText() throws {
		try assertRenderingFixture(in: "Text Scaling", slideNumber: 7)
	}

	@Test("Scale Font Up or Down - Large Text")
	func scaleFontUpOrDownLargeText() throws {
		try assertRenderingFixture(in: "Text Scaling", slideNumber: 4)
	}

	@Test("Adjust Container Height - Contract")
	func adjustContainerHeightContract() throws {
		try assertRenderingFixture(
			in: "Text Scaling",
			slideNumber: 5,
			precision: 0.99,
		)
	}

	@Test("Scale Font Down - Fits Without Scaling")
	func scaleFontDownFitsWithoutScaling() throws {
		try assertRenderingFixture(in: "Text Scaling", slideNumber: 8)
	}

	@Test("Scale Font Up - Large Text")
	func scaleFontUpLargeText() throws {
		try assertRenderingFixture(
			in: "Text Scaling",
			slideNumber: 3,
		)
	}

	@Test("Scale Font Up or Down - Small Text")
	func scaleFontUpOrDownSmallText() throws {
		try assertRenderingFixture(in: "Text Scaling", slideNumber: 6)
	}

	@Test("Adjust Container Height - Expand")
	func adjustContainerHeightExpand() throws {
		try assertRenderingFixture(
			in: "Text Scaling",
			slideNumber: 1,
		)
	}

	@Test("Scale Font Down - Requires Scaling")
	func scaleFontDownRequiresScaling() throws {
		try assertRenderingFixture(in: "Text Scaling", slideNumber: 2)
	}
}

@Suite("Text Alignment", .snapshots(diffTool: .ksdiff), .timeLimit(.minutes(1)))
struct TextAlignmentRenderingFixtureTests {
	@Test("Bottom Left")
	func bottomLeft() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 9)
	}

	@Test("Top Right")
	func topRight() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 1)
	}

	@Test("Justified")
	func justified() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 10)
	}

	@Test("Bottom Center")
	func bottomCenter() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 8)
	}

	@Test("Top Left")
	func topLeft() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 3)
	}

	@Test("Bottom Right")
	func bottomRight() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 7)
	}

	@Test("Middle Right")
	func middleRight() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 4)
	}

	@Test("Middle Center")
	func middleCenter() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 5)
	}

	@Test("Middle Left")
	func middleLeft() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 6)
	}

	@Test("Top Center")
	func topCenter() throws {
		try assertRenderingFixture(in: "Text Alignment", slideNumber: 2)
	}
}

@Suite("Text Effects", .snapshots(diffTool: .ksdiff), .timeLimit(.minutes(1)))
struct TextEffectsRenderingFixtureTests {
	@Test("Line Fill Mask - Per-Line Width")
	func lineFillMaskPerLineWidth() throws {
		try assertRenderingFixture(
			in: "Text Effects",
			slideNumber: 6,
		)
	}

	@Test("Shadow")
	func shadow() throws {
		try assertRenderingFixture(
			in: "Text Effects",
			slideNumber: 4,
		)
	}

	@Test("Combined Stroke, Shadow, and Line Fill Mask")
	func combinedStrokeShadowAndLineFillMask() throws {
		try assertRenderingFixture(
			in: "Text Effects",
			slideNumber: 3,
			precision: 0.98,
		)
	}

	@Test("Stroke")
	func stroke() throws {
		try assertRenderingFixture(
			in: "Text Effects",
			slideNumber: 5,
		)
	}

	@Test("Line Fill Mask - Maximum Line Width")
	func lineFillMaskMaximumLineWidth() throws {
		try assertRenderingFixture(
			in: "Text Effects",
			slideNumber: 1,
		)
	}

	@Test("Line Fill Mask - Container Width")
	func lineFillMaskContainerWidth() throws {
		try assertRenderingFixture(
			in: "Text Effects",
			slideNumber: 2,
		)
	}
}

@Suite("Shapes", .snapshots(diffTool: .ksdiff), .timeLimit(.minutes(1)))
struct ShapesRenderingFixtureTests {
	@Test("Stars - 4, 5, and 7 Points")
	func stars45And7Points() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 2)
	}

	@Test("Polygons - 3, 5, and 8 Sides")
	func polygons35And8Sides() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 3)
	}

	@Test("Rhombus")
	func rhombus() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 6)
	}

	@Test("Custom Bezier Path")
	func customBezierPath() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 1)
	}

	@Test("Isosceles Triangle")
	func isoscelesTriangle() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 8)
	}

	@Test("Double Arrow")
	func doubleArrow() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 5)
	}

	@Test("Right Triangle")
	func rightTriangle() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 7)
	}

	@Test("Ellipse")
	func ellipse() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 9)
	}

	@Test("Right Arrow")
	func rightArrow() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 4)
	}

	@Test("Rectangle")
	func rectangle() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 10)
	}

	@Test("Rounded Rectangle")
	func roundedRectangle() throws {
		try assertRenderingFixture(in: "Shapes", slideNumber: 11)
	}
}

@Suite("Shape Effects", .snapshots(diffTool: .ksdiff), .timeLimit(.minutes(1)))
struct ShapeEffectsRenderingFixtureTests {
	@Test("Standard - Fill")
	func standardFill() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 1,
		)
	}

	@Test("Shadow - Dashed Stroke")
	func shadowDashedStroke() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 8,
		)
	}

	@Test("Shadow - Fill")
	func shadowFill() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 6,
		)
	}

	@Test("Shadow - Fill + Dashed Stroke")
	func shadowFillDashedStroke() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 10,
		)
	}

	@Test("Standard - Dashed Stroke")
	func standardDashedStroke() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 3,
		)
	}

	@Test("Standard - Solid Stroke")
	func standardSolidStroke() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 2,
		)
	}

	@Test("Standard - Fill + Solid Stroke")
	func standardFillSolidStroke() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 4,
		)
	}

	@Test("Feather - Fill + Solid Stroke")
	func featherFillSolidStroke() {
		withKnownIssue {
			try assertRenderingFixture(
				in: "Shape Effects",
				slideNumber: 14,
			)
		}
	}

	@Test("Feather - Dashed Stroke")
	func featherDashedStroke() {
		withKnownIssue {
			try assertRenderingFixture(
				in: "Shape Effects",
				slideNumber: 13,
			)
		}
	}

	@Test("Feather - Fill + Dashed Stroke")
	func featherFillDashedStroke() {
		withKnownIssue {
			try assertRenderingFixture(
				in: "Shape Effects",
				slideNumber: 15,
			)
		}
	}

	@Test("Feather - Fill")
	func featherFill() {
		withKnownIssue {
			try assertRenderingFixture(
				in: "Shape Effects",
				slideNumber: 11,
			)
		}
	}

	@Test("Standard - Fill + Dashed Stroke")
	func standardFillDashedStroke() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 5,
		)
	}

	@Test("Feather - Solid Stroke")
	func featherSolidStroke() {
		withKnownIssue {
			try assertRenderingFixture(
				in: "Shape Effects",
				slideNumber: 12,
			)
		}
	}

	@Test("Shadow - Solid Stroke")
	func shadowSolidStroke() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 7,
		)
	}

	@Test("Shadow - Fill + Solid Stroke")
	func shadowFillSolidStroke() throws {
		try assertRenderingFixture(
			in: "Shape Effects",
			slideNumber: 9,
		)
	}
}

@Suite("Media Elements", .snapshots(diffTool: .ksdiff), .timeLimit(.minutes(1)))
struct MediaElementsRenderingFixtureTests {
	@Test("Transparent PNG Fill")
	func transparentPNGFill() throws {
		try assertRenderingFixture(
			in: "Media Elements",
			slideNumber: 2,
			precision: 0.985,
			perceptualPrecision: 0.5,
		)
	}

	@Test("Video Fill")
	func videoFill() {
		withKnownIssue {
			try assertRenderingFixture(
				in: "Media Elements",
				slideNumber: 1,
				precision: 0.98,
			)
		}
	}
}

@Suite("Media Backgrounds", .snapshots(diffTool: .ksdiff), .timeLimit(.minutes(1)))
struct MediaBackgroundsRenderingFixtureTests {
	@Test("Image - Fill")
	func imageFill() throws {
		try assertRenderingFixture(
			in: "Media Backgrounds",
			slideNumber: 4,
			precision: 0.985,
			perceptualPrecision: 0.5,
		)
	}

	@Test("Video - Custom Thumbnail Frame")
	func videoCustomThumbnailFrame() throws {
		try assertRenderingFixture(
			in: "Media Backgrounds",
			slideNumber: 2,
			precision: 0.95,
			perceptualPrecision: 0.50,
		)
	}

	@Test("Image - Stretch")
	func imageStretch() throws {
		try assertRenderingFixture(
			in: "Media Backgrounds",
			slideNumber: 5,
			precision: 0.95,
			perceptualPrecision: 0.50,
		)
	}

	@Test("Image - Fit")
	func imageFit() {
		withKnownIssue {
			try assertRenderingFixture(
				in: "Media Backgrounds",
				slideNumber: 3,
				precision: 0.98,
			)
		}
	}

	@Test("Image - Crop, Rotate, and Flip")
	func imageCropRotateAndFlip() throws {
		try assertRenderingFixture(
			in: "Media Backgrounds",
			slideNumber: 6,
			precision: 0.97,
		)
	}

	@Test("Video - Default Thumbnail Frame")
	func videoDefaultThumbnailFrame() throws {
		try assertRenderingFixture(
			in: "Media Backgrounds",
			slideNumber: 1,
			precision: 0.95,
			perceptualPrecision: 0.50,
		)
	}
}

private func assertRenderingFixture(
	in presentationName: String,
	slideNumber: Int,
	precision: Float = 0.99,
	perceptualPrecision: Float = 0.99,
	fileID: StaticString = #file,
	file filePath: StaticString = #filePath,
	testName: String = #function,
	line: UInt = #line,
	column: UInt = #column,
) throws {
	let playlistURL = fixtureURL("ProPresenter/ReferenceSlides.proPlaylist")

	let presentations = try PresentationLoader.loadPresentations(from: playlistURL)

	let document = try #require(presentations.first(where: {
		$0.sourceName.replacing(/^\d+\s*-\s*/, with: "") == presentationName
	})?.document)
	let cue = document.orderedCues[slideNumber - 1]

	let bitmap = try PresentationRenderer(document: document).render(cue: cue)
	let rendered = NSImage(size: bitmap.size)
	rendered.addRepresentation(bitmap)

	let words = presentationName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
	let snapshotTestName = "renders\(words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined())Slide"

	assertSnapshot(
		of: rendered,
		as: .image(precision: precision, perceptualPrecision: perceptualPrecision),
		named: "slide-\(slideNumber)",
		fileID: fileID,
		file: filePath,
		testName: snapshotTestName,
//			testName: testName,
		line: line,
		column: column,
	)
}
