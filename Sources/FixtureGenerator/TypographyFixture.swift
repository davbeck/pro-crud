import AppKit
import Foundation
import ProCRUDCore
import ProPresenterProto
import SwiftProtobuf

enum TypographyFixture {
	static let slideCount = 6

	private static let directoryName = "Typography"
	private static let presentationFilename = "Typography.pro"
	private static let bundleFilename = "Typography.probundle"
	private static let canvasWidth = 854.0
	private static let canvasHeight = 480.0

	static func generate(in fixturesDirectory: URL, check: Bool) throws {
		let fixtureDirectory = fixturesDirectory.appendingPathComponent(directoryName, isDirectory: true)
		let expectedPresentation = try presentation().serializedData()

		if check {
			let checkedPresentation = try presentationData(in: fixtureDirectory)
			guard checkedPresentation == expectedPresentation else {
				throw TypographyFixtureError.outOfDate(
					fixtureDirectory.appendingPathComponent(bundleFilename),
				)
			}
			return
		}

		let workspace = FileManager.default.temporaryDirectory
			.appendingPathComponent("ProCRUD-typography-fixture-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: workspace) }
		try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
		try expectedPresentation.write(to: workspace.appendingPathComponent(presentationFilename), options: .atomic)
		let bundleURL = fixtureDirectory.appendingPathComponent(bundleFilename)
		_ = try DocumentArchive.bundle(workspace, to: bundleURL, replace: true)
		print("Generated \(bundleURL.path)")
	}

	private static func presentationData(in fixtureDirectory: URL) throws -> Data {
		let bundleURL = fixtureDirectory.appendingPathComponent(bundleFilename)
		guard FileManager.default.fileExists(atPath: bundleURL.path) else {
			throw TypographyFixtureError.outOfDate(bundleURL)
		}
		let document = try DocumentLoader.load(from: bundleURL)
		return try document.payload.serializedData()
	}

	private static func presentation() throws -> Rv_Data_Presentation {
		let cues: [(name: String, content: NSAttributedString, primaryFont: String)] = try [
			("Avenir Next Faces", avenirNextFaces(), "AvenirNext-Regular"),
			("Avenir Next Kerning", avenirNextKerning(), "AvenirNext-Regular"),
			("Avenir Next Ligatures", avenirNextLigatures(), "AvenirNext-Regular"),
			("Backslant and Italic", backslantAndItalic(), "AvenirNext-Heavy"),
			("Menlo Spacing", menloSpacing(), "Menlo-Regular"),
			("Emoji and Mixed Typography", emojiAndMixedTypography(), "AvenirNext-Regular"),
		]

		var presentation = DocumentFactory.presentation(
			name: "Typography",
			canvasSize: CGSize(width: canvasWidth, height: canvasHeight),
		)
		presentation.uuid = uuid(1)
		presentation.cues = try cues.enumerated().map { index, cue in
			try makeCue(
				index: index,
				name: cue.name,
				content: cue.content,
				primaryFont: cue.primaryFont,
			)
		}
		presentation.cueGroups[0].group.uuid = uuid(2)
		presentation.cueGroups[0].group.name = "System typography"
		presentation.cueGroups[0].cueIdentifiers = presentation.cues.map(\.uuid)
		return presentation
	}

	private static func avenirNextFaces() throws -> NSAttributedString {
		try attributed([
			run("Avenir Next Faces\n", font: "AvenirNext-DemiBold", size: 38, paragraph: headingParagraph()),
			run("Regular — AVATAR office fifty\n", font: "AvenirNext-Regular", size: 34, paragraph: bodyParagraph()),
			run("Demi Bold — AVATAR office fifty\n", font: "AvenirNext-DemiBold", size: 34, paragraph: bodyParagraph()),
			run("Heavy — AVATAR office fifty\n", font: "AvenirNext-Heavy", size: 34, paragraph: bodyParagraph()),
			run("Condensed Heavy — AVATAR office fifty", font: "AvenirNextCondensed-Heavy", size: 38, paragraph: bodyParagraph()),
		])
	}

	private static func avenirNextKerning() throws -> NSAttributedString {
		try attributed([
			run("Avenir Next Kerning\n", font: "AvenirNext-DemiBold", size: 38, paragraph: headingParagraph()),
			run("Tight (-2): AVATAR To WA\n", font: "AvenirNext-Regular", size: 46, kern: -2, paragraph: bodyParagraph()),
			run("Default (0): AVATAR To WA\n", font: "AvenirNext-Regular", size: 46, kern: 0, paragraph: bodyParagraph()),
			run("Loose (+5): AVATAR To WA", font: "AvenirNext-Regular", size: 46, kern: 5, paragraph: bodyParagraph()),
		])
	}

	private static func avenirNextLigatures() throws -> NSAttributedString {
		try attributed([
			run("Avenir Next Ligatures\n", font: "AvenirNext-DemiBold", size: 38, paragraph: headingParagraph()),
			run("Off: office affinity fi fl ffi ffl\n", font: "AvenirNext-Regular", size: 36, ligature: 0, paragraph: bodyParagraph()),
			run("On:  office affinity fi fl ffi ffl", font: "AvenirNext-Regular", size: 36, ligature: 1, paragraph: bodyParagraph()),
		])
	}

	private static func backslantAndItalic() throws -> NSAttributedString {
		try attributed([
			run("Backslant and Italic\n", font: "AvenirNext-DemiBold", size: 38, paragraph: headingParagraph()),
			run("Normal — Heavy Avenir Next\n", font: "AvenirNext-Heavy", size: 42, paragraph: bodyParagraph()),
			run(
				"Backslant — Heavy Avenir Next\n",
				font: "AvenirNext-Heavy",
				size: 42,
				obliqueness: -0.2,
				paragraph: bodyParagraph(),
			),
			run("Italic face — Heavy Avenir Next", font: "AvenirNext-HeavyItalic", size: 42, paragraph: bodyParagraph()),
		])
	}

	private static func menloSpacing() throws -> NSAttributedString {
		let tabs = paragraph(lineSpacing: 8, tabStops: [170, 340, 510])
		return try attributed([
			run("Menlo Spacing\n", font: "AvenirNext-DemiBold", size: 38, paragraph: headingParagraph()),
			run("INDEX\tSTART\tEND\tSTATUS\n", font: "Menlo-Regular", size: 24, paragraph: tabs),
			run("001\t10:30\t11:15\tREADY\n", font: "Menlo-Regular", size: 24, paragraph: tabs),
			run("Tracking +3: MONOSPACED TEXT\n", font: "Menlo-Regular", size: 28, kern: 3, paragraph: bodyParagraph()),
			run("Before\nSpaced line\nAfter", font: "Menlo-Regular", size: 28, paragraph: paragraph(lineSpacing: 15)),
		])
	}

	private static func emojiAndMixedTypography() throws -> NSAttributedString {
		let firstParagraph = paragraph(lineSpacing: 7, paragraphSpacing: 24)
		return try attributed([
			run("Emoji and Mixed Typography\n", font: "AvenirNext-DemiBold", size: 38, paragraph: headingParagraph()),
			run("Avenir Next meets ", font: "AvenirNext-Regular", size: 33, paragraph: firstParagraph),
			run("🎉", font: "AppleColorEmoji", size: 34, paragraph: firstParagraph),
			run(" and ", font: "AvenirNext-Regular", size: 33, paragraph: firstParagraph),
			run("👩🏽‍💻", font: "AppleColorEmoji", size: 34, paragraph: firstParagraph),
			run(".\n", font: "AvenirNext-Regular", size: 33, paragraph: firstParagraph),
			run("Avenir ", font: "AvenirNext-Regular", size: 33, paragraph: bodyParagraph()),
			run("Heavy Italic", font: "AvenirNext-HeavyItalic", size: 33, paragraph: bodyParagraph()),
			run(" and é remain in one RTF run.", font: "AvenirNext-Regular", size: 33, paragraph: bodyParagraph()),
		])
	}

	private static func makeCue(
		index: Int,
		name: String,
		content: NSAttributedString,
		primaryFont: String,
	) throws -> Rv_Data_Cue {
		var slide = Rv_Data_Slide()
		slide.uuid = uuid(100 + index)
		slide.size.width = canvasWidth
		slide.size.height = canvasHeight
		slide.elements = try [textElement(content, primaryFont: primaryFont), background()]
		for elementIndex in slide.elements.indices {
			slide.elements[elementIndex].element.uuid = uuid(1000 + index * 10 + elementIndex)
			slide.elements[elementIndex].info = UInt32(slide.elements.count - elementIndex)
		}

		var presentationSlide = Rv_Data_PresentationSlide()
		presentationSlide.baseSlide = slide
		var action = Rv_Data_Action()
		action.uuid = uuid(500 + index)
		action.label.text = name
		action.type = .presentationSlide
		action.isEnabled = true
		action.slide.presentation = presentationSlide

		var cue = Rv_Data_Cue()
		cue.uuid = uuid(300 + index)
		cue.name = name
		cue.isEnabled = true
		cue.completionActionType = .last
		cue.actions = [action]
		return cue
	}

	private static func background() -> Rv_Data_Slide.Element {
		rectangle(
			name: "Warm white background",
			x: 0,
			y: 0,
			width: canvasWidth,
			height: canvasHeight,
			color: color(0.97, 0.97, 0.95),
		)
	}

	private static func textElement(_ content: NSAttributedString, primaryFont: String) throws -> Rv_Data_Slide.Element {
		var result = rectangle(
			name: "Typography",
			x: 56,
			y: 42,
			width: 742,
			height: 396,
			color: color(0, 0, 0, 0),
		)
		result.element.fill.enable = false
		result.element.text.rtfData = try content.data(
			from: NSRange(location: 0, length: content.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)
		result.element.text.scaleBehavior = .scaleFontDown
		result.element.text.verticalAlignment = .top
		if let font = NSFont(name: primaryFont, size: 36) {
			result.element.text.attributes.font.name = font.fontName
			result.element.text.attributes.font.family = font.familyName ?? primaryFont
		}
		result.element.text.attributes.font.size = 36
		result.element.text.attributes.textSolidFill = color(0.08, 0.1, 0.12)
		return result
	}

	private static func rectangle(
		name: String,
		x: Double,
		y: Double,
		width: Double,
		height: Double,
		color: Rv_Data_Color,
	) -> Rv_Data_Slide.Element {
		var element = Rv_Data_Graphics.Element()
		element.name = name
		element.bounds.origin.x = x
		element.bounds.origin.y = y
		element.bounds.size.width = width
		element.bounds.size.height = height
		element.opacity = 1
		element.path.closed = true
		element.path.shape.type = .rectangle
		element.path.points = [(0, 0), (1, 0), (1, 1), (0, 1)].map { x, y in
			var point = Rv_Data_Graphics.Path.BezierPoint()
			point.point.x = Double(x)
			point.point.y = Double(y)
			point.q0 = point.point
			point.q1 = point.point
			return point
		}
		element.fill.enable = true
		element.fill.color = color
		var result = Rv_Data_Slide.Element()
		result.element = element
		return result
	}

	private static func attributed(_ runs: [TextRun]) throws -> NSAttributedString {
		let result = NSMutableAttributedString()
		for textRun in runs {
			guard let font = NSFont(name: textRun.font, size: textRun.size) else {
				throw TypographyFixtureError.missingFont(textRun.font)
			}
			var attributes: [NSAttributedString.Key: Any] = [
				.font: font,
				.foregroundColor: NSColor(srgbRed: 0.08, green: 0.1, blue: 0.12, alpha: 1),
				.paragraphStyle: textRun.paragraph,
			]
			if let kern = textRun.kern {
				attributes[.kern] = kern
			}
			if let ligature = textRun.ligature {
				attributes[.ligature] = ligature
			}
			if let obliqueness = textRun.obliqueness {
				attributes[.obliqueness] = obliqueness
			}
			result.append(NSAttributedString(string: textRun.string, attributes: attributes))
		}
		return result
	}

	private static func run(
		_ string: String,
		font: String,
		size: CGFloat,
		kern: CGFloat? = nil,
		ligature: Int? = nil,
		obliqueness: CGFloat? = nil,
		paragraph: NSParagraphStyle,
	) -> TextRun {
		TextRun(
			string: string,
			font: font,
			size: size,
			kern: kern,
			ligature: ligature,
			obliqueness: obliqueness,
			paragraph: paragraph,
		)
	}

	private static func paragraph(
		lineSpacing: CGFloat = 6,
		paragraphSpacing: CGFloat = 0,
		tabStops: [CGFloat] = [],
	) -> NSParagraphStyle {
		let style = NSMutableParagraphStyle()
		style.alignment = .left
		style.lineSpacing = lineSpacing
		style.paragraphSpacing = paragraphSpacing
		style.tabStops = tabStops.map { NSTextTab(textAlignment: .left, location: $0, options: [:]) }
		return style
	}

	private static func headingParagraph() -> NSParagraphStyle {
		paragraph(lineSpacing: 6, paragraphSpacing: 13)
	}

	private static func bodyParagraph() -> NSParagraphStyle {
		paragraph()
	}

	private static func uuid(_ value: Int) -> Rv_Data_UUID {
		var uuid = Rv_Data_UUID()
		uuid.string = String(format: "00000000-0000-4000-8000-%012d", value)
		return uuid
	}

	private static func color(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float = 1) -> Rv_Data_Color {
		var color = Rv_Data_Color()
		color.red = red
		color.green = green
		color.blue = blue
		color.alpha = alpha
		return color
	}
}

private struct TextRun {
	let string: String
	let font: String
	let size: CGFloat
	let kern: CGFloat?
	let ligature: Int?
	let obliqueness: CGFloat?
	let paragraph: NSParagraphStyle
}

private enum TypographyFixtureError: Error, CustomStringConvertible {
	case missingFont(String)
	case outOfDate(URL)

	var description: String {
		switch self {
		case let .missingFont(name):
			"The macOS system font \(name) is unavailable."
		case let .outOfDate(url):
			"Typography fixture is out of date: \(url.path). Run swift run FixtureGenerator generate-typography."
		}
	}
}
