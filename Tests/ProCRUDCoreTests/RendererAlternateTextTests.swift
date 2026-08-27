import AppKit
import CustomDump
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite(
	"Alternate Text Rendering",
	.timeLimit(.minutes(1)),
)
struct RendererAlternateTextTests {
	@Test
	func resolvesSourceByUUIDAndAppliesTransformsWithTargetFormatting() throws {
		let sourceFont = try #require(NSFont(name: "AvenirNext-Regular", size: 46))
		let multilineFont = try #require(NSFont(name: "Menlo-Regular", size: 31))
		let flattenedFont = try #require(NSFont(name: "AvenirNext-DemiBold", size: 27))
		let sourceColor = NSColor(srgbRed: 0.9, green: 0.1, blue: 0.2, alpha: 1)
		let multilineColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
		let flattenedColor = NSColor(srgbRed: 0.2, green: 0.7, blue: 0.3, alpha: 1)

		let source = try textElement(
			name: "Source",
			uuid: "00000000-0000-4000-8000-000000000001",
			content: "First line\nSecond line",
			font: sourceFont,
			color: sourceColor,
			alignment: .left,
			y: 20,
		)
		var multiline = try textElement(
			name: "Multiline target",
			uuid: "00000000-0000-4000-8000-000000000002",
			content: "Stored multiline placeholder",
			font: multilineFont,
			color: multilineColor,
			alignment: .right,
			y: 120,
		)
		multiline.dataLinks = [alternateTextLink(
			sourceUUID: source.element.uuid,
			sourceName: "A deliberately incorrect name",
			transform: .none,
		)]
		var flattened = try textElement(
			name: "Flattened target",
			uuid: "00000000-0000-4000-8000-000000000003",
			content: "Stored flattened placeholder",
			font: flattenedFont,
			color: flattenedColor,
			alignment: .center,
			y: 220,
		)
		flattened.dataLinks = [alternateTextLink(
			sourceUUID: source.element.uuid,
			sourceName: "Another incorrect name",
			transform: .removeLineReturns,
		)]

		let layers = try effectiveLayers(elements: [source, multiline, flattened])
		let layersByName = Dictionary(uniqueKeysWithValues: layers.compactMap { layer in
			layer.name.map { ($0, layer) }
		})
		let multilineLayer = try #require(layersByName["Multiline target"])
		let multilineText = try #require(multilineLayer.text)
		expectNoDifference(multilineText.plainText, "First line\nSecond line")
		#expect(multilineLayer.alternateTextOutline == true)
		try assertFormatting(
			of: multilineText,
			matches: multilineFont,
			color: multilineColor,
			alignment: "right",
		)

		let flattenedLayer = try #require(layersByName["Flattened target"])
		let flattenedText = try #require(flattenedLayer.text)
		expectNoDifference(flattenedText.plainText, "First line Second line")
		#expect(flattenedLayer.alternateTextOutline == true)
		try assertFormatting(
			of: flattenedText,
			matches: flattenedFont,
			color: flattenedColor,
			alignment: "center",
		)
	}

	@Test
	func missingSourcePreservesStoredTargetTextAndRendersSafely() throws {
		let targetFont = try #require(NSFont(name: "AvenirNext-DemiBold", size: 29))
		let targetColor = NSColor(srgbRed: 0.75, green: 0.35, blue: 0.1, alpha: 1)
		var target = try textElement(
			name: "Missing source target",
			uuid: "00000000-0000-4000-8000-000000000004",
			content: "Stored fallback",
			font: targetFont,
			color: targetColor,
			alignment: .left,
			y: 120,
		)
		var missingUUID = Rv_Data_UUID()
		missingUUID.string = "00000000-0000-4000-8000-999999999999"
		target.dataLinks = [alternateTextLink(
			sourceUUID: missingUUID,
			sourceName: "Missing source",
			transform: .removeLineReturns,
		)]

		let presentation = presentation(elements: [target])
		let document = PresentationDocument(presentation: presentation)
		let renderer = PresentationRenderer(document: document)
		let layer = try #require(renderer.effectiveRendering().slides.first?.layers.first)
		let text = try #require(layer.text)
		expectNoDifference(text.plainText, "Stored fallback")
		#expect(layer.alternateTextOutline == true)
		try assertFormatting(
			of: text,
			matches: targetFont,
			color: targetColor,
			alignment: "left",
		)

		let bitmap = try renderer.render(cue: presentation.cues[0])
		#expect(bitmap.pixelsWide == 640)
		#expect(bitmap.pixelsHigh == 360)
	}

	private func effectiveLayers(
		elements: [Rv_Data_Slide.Element],
	) throws -> [EffectiveRendering.Layer] {
		let document = PresentationDocument(presentation: presentation(elements: elements))
		return try #require(PresentationRenderer(document: document).effectiveRendering().slides.first?.layers)
	}

	private func presentation(
		elements: [Rv_Data_Slide.Element],
	) -> Rv_Data_Presentation {
		var presentation = DocumentFactory.presentation(
			name: "Alternate text",
			canvasSize: CGSize(width: 640, height: 360),
		)
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements = elements
		return presentation
	}

	private func textElement(
		name: String,
		uuid: String,
		content: String,
		font: NSFont,
		color: NSColor,
		alignment: NSTextAlignment,
		y: Double,
	) throws -> Rv_Data_Slide.Element {
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = alignment
		let attributed = NSAttributedString(
			string: content,
			attributes: [
				.font: font,
				.foregroundColor: color,
				.paragraphStyle: paragraph,
			],
		)
		var element = Rv_Data_Graphics.Element()
		element.uuid.string = uuid
		element.name = name
		element.bounds.origin.x = 20
		element.bounds.origin.y = y
		element.bounds.size.width = 600
		element.bounds.size.height = 80
		element.opacity = 1
		element.text.rtfData = try attributed.data(
			from: NSRange(location: 0, length: attributed.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)
		element.text.verticalAlignment = .top
		var slideElement = Rv_Data_Slide.Element()
		slideElement.element = element
		return slideElement
	}

	private func alternateTextLink(
		sourceUUID: Rv_Data_UUID,
		sourceName: String,
		transform: Rv_Data_Slide.Element.DataLink.AlternateElementText.TextTransformOption,
	) -> Rv_Data_Slide.Element.DataLink {
		var alternateText = Rv_Data_Slide.Element.DataLink.AlternateElementText()
		alternateText.otherElementUuid = sourceUUID
		alternateText.otherElementName = sourceName
		alternateText.textTransform = transform
		var link = Rv_Data_Slide.Element.DataLink()
		link.alternateText = alternateText
		return link
	}

	private func assertFormatting(
		of text: EffectiveRendering.Text,
		matches font: NSFont,
		color: NSColor,
		alignment: String?,
	) throws {
		let run = try #require(text.runs.first)
		let renderedFont = try #require(run.font)
		expectNoDifference(renderedFont.postscriptName, font.fontName)
		#expect(abs(renderedFont.pointSize - Double(font.pointSize)) < 0.01)
		expectNoDifference(run.paragraph?.alignment, alignment)

		let renderedColor = try #require(run.foregroundColor)
		let expectedColor = try #require(color.usingColorSpace(.sRGB))
		#expect(abs((renderedColor.red ?? 0) - Double(expectedColor.redComponent)) < 0.01)
		#expect(abs((renderedColor.green ?? 0) - Double(expectedColor.greenComponent)) < 0.01)
		#expect(abs((renderedColor.blue ?? 0) - Double(expectedColor.blueComponent)) < 0.01)
	}
}
