import AppKit
import Foundation
import ProCRUDCore
import ProPresenterProto
import SwiftProtobuf

enum RenderingEdgeCasesFixture {
	static let slideCount = 4

	private static let directoryName = "RenderingEdgeCases"
	private static let presentationFilename = "Rendering Edge Cases.pro"
	private static let bundleFilename = "RenderingEdgeCases.probundle"
	private static let canvasWidth = 1920.0
	private static let canvasHeight = 1080.0

	static func generate(in fixturesDirectory: URL, check: Bool) throws {
		let fixtureDirectory = fixturesDirectory.appendingPathComponent(directoryName, isDirectory: true)
		let expectedPresentation = try presentation().serializedData()

		if check {
			let checkedPresentation = try presentationData(in: fixtureDirectory)
			guard checkedPresentation == expectedPresentation else {
				throw RenderingEdgeCasesFixtureError.outOfDate(
					fixtureDirectory.appendingPathComponent(bundleFilename),
				)
			}
			return
		}

		let workspace = FileManager.default.temporaryDirectory
			.appendingPathComponent("ProCRUD-rendering-edge-cases-\(UUID().uuidString)", isDirectory: true)
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
			throw RenderingEdgeCasesFixtureError.outOfDate(bundleURL)
		}
		let document = try DocumentLoader.load(from: bundleURL)
		return try document.payload.serializedData()
	}

	private static func presentation() throws -> Rv_Data_Presentation {
		let slides: [(name: String, elements: [Rv_Data_Slide.Element])] = try [
			("Lists and Insets", listsAndInsets()),
			("Line Mask Height Offsets", lineMaskHeightOffsets()),
			("Element Rotations and Clipping", elementRotationsAndClipping()),
			("Alternate Text Links", alternateTextLinks()),
		]

		var presentation = DocumentFactory.presentation(
			name: "Rendering Edge Cases",
			canvasSize: CGSize(width: canvasWidth, height: canvasHeight),
		)
		presentation.uuid = uuid(1)
		presentation.cues = slides.enumerated().map { index, slide in
			makeCue(index: index, name: slide.name, elements: slide.elements)
		}
		presentation.cueGroups[0].group.uuid = uuid(2)
		presentation.cueGroups[0].group.name = "Rendering edge cases"
		presentation.cueGroups[0].cueIdentifiers = presentation.cues.map(\.uuid)
		return presentation
	}

	private static func listsAndInsets() throws -> [Rv_Data_Slide.Element] {
		var decimal = try listTextElement(
			name: "Decimal List",
			content: ["Prepare the room", "Welcome the people", "Begin on time"],
			numberType: .decimal,
			markerFormat: NSTextList.MarkerFormat(rawValue: "{decimal}."),
			bounds: CGRect(x: 105, y: 190, width: 795, height: 420),
		)
		decimal.element.fill.enable = true
		decimal.element.fill.color = color(0.10, 0.25, 0.42, 0.92)

		var disc = try listTextElement(
			name: "Disc List",
			content: ["Read the passage", "Notice the details", "Respond with care"],
			numberType: .disc,
			markerFormat: .disc,
			bounds: CGRect(x: 1020, y: 190, width: 795, height: 420),
		)
		disc.element.fill.enable = true
		disc.element.fill.color = color(0.17, 0.38, 0.32, 0.92)

		var inset = try textElement(
			name: "Asymmetric Inset",
			content: "This text begins after a 205-point left margin.",
			bounds: CGRect(x: 105, y: 690, width: 1710, height: 230),
			fontName: "AvenirNext-DemiBold",
			fontSize: 48,
			textColor: .white,
			alignment: .left,
		)
		inset.element.fill.enable = true
		inset.element.fill.color = color(0.48, 0.18, 0.42, 0.94)
		inset.element.text.margins.left = 205
		inset.element.text.margins.right = 30
		inset.element.text.margins.top = 24
		inset.element.text.margins.bottom = 24

		return try [
			heading("Lists and Insets"),
			decimal,
			disc,
			inset,
			background(),
		]
	}

	private static func lineMaskHeightOffsets() throws -> [Rv_Data_Slide.Element] {
		var title = try heading("Line Mask Height Offsets")
		title.element.bounds.origin.x = 220
		return try [
			title,
			maskedText(
				name: "Offset 0",
				content: "OFFSET 0\nCONTROL",
				bounds: CGRect(x: 110, y: 205, width: 790, height: 300),
				heightOffset: 0,
				fill: color(0.10, 0.55, 0.65),
			),
			maskedText(
				name: "Offset 10",
				content: "OFFSET 10\nROOMY BOX",
				bounds: CGRect(x: 1020, y: 205, width: 790, height: 300),
				heightOffset: 10,
				fill: color(0.90, 0.42, 0.16),
			),
			maskedText(
				name: "Offset 55",
				content: "OFFSET 55\nMULTILINE",
				bounds: CGRect(x: 110, y: 630, width: 790, height: 260),
				heightOffset: 55,
				fill: color(0.44, 0.28, 0.76),
			),
			maskedText(
				name: "Offset 60 Constrained",
				content: "OFFSET 60 — CONSTRAINED",
				bounds: CGRect(x: 1020, y: 710, width: 790, height: 82),
				heightOffset: 60,
				fill: color(0.78, 0.20, 0.36),
			),
			background(),
		]
	}

	private static func elementRotationsAndClipping() throws -> [Rv_Data_Slide.Element] {
		var rotation270 = rectangle(
			name: "Rotation 270",
			bounds: CGRect(x: 190, y: 300, width: 420, height: 180),
			fill: color(0.10, 0.62, 0.78),
		)
		rotation270.element.rotation = 270

		var rotation315 = rectangle(
			name: "Rotation 315",
			bounds: CGRect(x: 750, y: 300, width: 430, height: 180),
			fill: color(0.95, 0.50, 0.14),
		)
		rotation315.element.rotation = 315

		var rotation360 = rectangle(
			name: "Stored Rotation 360",
			bounds: CGRect(x: 1320, y: 300, width: 420, height: 180),
			fill: color(0.38, 0.74, 0.34),
		)
		rotation360.element.rotation = 360

		var clipped = rectangle(
			name: "Rotated Off Canvas",
			bounds: CGRect(x: -150, y: 720, width: 680, height: 210),
			fill: color(0.80, 0.18, 0.42),
		)
		clipped.element.rotation = 315

		var rounded = rectangle(
			name: "Roundness 0.5",
			bounds: CGRect(x: 720, y: 650, width: 480, height: 310),
			fill: color(0.46, 0.30, 0.80),
		)
		rounded.element.path.shape.type = .roundedRectangle
		rounded.element.path.shape.roundedRectangle.roundness = 0.5

		let labels = try [
			textElement(
				name: "Rotation Labels",
				content: "270°                              315°                              360° stored",
				bounds: CGRect(x: 145, y: 525, width: 1630, height: 80),
				fontName: "AvenirNext-DemiBold",
				fontSize: 32,
				textColor: .white,
				alignment: .left,
			),
			textElement(
				name: "Clipping Label",
				content: "OFF-CANVAS + ROTATION",
				bounds: CGRect(x: 65, y: 950, width: 620, height: 70),
				fontName: "AvenirNext-DemiBold",
				fontSize: 28,
				textColor: .white,
				alignment: .left,
			),
			textElement(
				name: "Roundness Label",
				content: "ROUNDED RECTANGLE · 0.5",
				bounds: CGRect(x: 760, y: 765, width: 400, height: 90),
				fontName: "AvenirNext-DemiBold",
				fontSize: 28,
				textColor: .white,
				alignment: .center,
			),
		]

		return try [heading("Element Rotations and Clipping")]
			+ labels
			+ [rotation270, rotation315, rotation360, clipped, rounded, background()]
	}

	private static func alternateTextLinks() throws -> [Rv_Data_Slide.Element] {
		let sourceUUID = uuid(4400)
		var source = try textElement(
			name: "Source Lyrics",
			content: "GRACE BUILDS\nA LIVING HOPE",
			bounds: CGRect(x: 230, y: 155, width: 1460, height: 230),
			fontName: "AvenirNext-Heavy",
			fontSize: 78,
			textColor: .white,
			alignment: .center,
		)
		source.element.uuid = sourceUUID

		var singleLine = try textElement(
			name: "Single-line Link",
			content: "GRACE BUILDS A LIVING HOPE",
			bounds: CGRect(x: 175, y: 440, width: 1570, height: 130),
			fontName: "AvenirNext-DemiBold",
			fontSize: 52,
			textColor: NSColor(srgbRed: 0.45, green: 0.82, blue: 0.78, alpha: 1),
			alignment: .center,
		)
		singleLine.dataLinks = [alternateTextLink(to: source.element, transform: .removeLineReturns)]

		var multiline = try textElement(
			name: "Multiline Partial-opacity Link",
			content: "GRACE BUILDS\nA LIVING HOPE",
			bounds: CGRect(x: 315, y: 610, width: 1290, height: 190),
			fontName: "AvenirNext-Bold",
			fontSize: 58,
			textColor: NSColor(srgbRed: 0.98, green: 0.76, blue: 0.30, alpha: 1),
			alignment: .center,
		)
		multiline.element.opacity = 0.12
		multiline.dataLinks = [alternateTextLink(to: source.element)]

		var outlined = try textElement(
			name: "Outlined Scale-down Link",
			content: "GRACE BUILDS A LIVING HOPE — LINKED OUTLINE",
			bounds: CGRect(x: 150, y: 850, width: 1620, height: 115),
			fontName: "AvenirNext-Heavy",
			fontSize: 62,
			textColor: .clear,
			alignment: .center,
			strokeColor: .white,
			strokeWidth: 3,
		)
		outlined.element.text.scaleBehavior = .scaleFontDown
		outlined.dataLinks = [alternateTextLink(to: source.element, transform: .removeLineReturns)]

		return try [
			heading("Alternate Text Links"),
			source,
			singleLine,
			multiline,
			outlined,
			background(),
		]
	}

	private static func makeCue(
		index: Int,
		name: String,
		elements: [Rv_Data_Slide.Element],
	) -> Rv_Data_Cue {
		var slide = Rv_Data_Slide()
		slide.uuid = uuid(100 + index)
		slide.size.width = canvasWidth
		slide.size.height = canvasHeight
		slide.elements = elements
		for elementIndex in slide.elements.indices {
			if slide.elements[elementIndex].element.uuid.string.isEmpty {
				slide.elements[elementIndex].element.uuid = uuid(1000 + index * 100 + elementIndex)
			}
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

	private static func heading(_ content: String) throws -> Rv_Data_Slide.Element {
		try textElement(
			name: "Heading",
			content: content,
			bounds: CGRect(x: 90, y: 55, width: 1740, height: 100),
			fontName: "AvenirNext-Heavy",
			fontSize: 48,
			textColor: .white,
			alignment: .left,
		)
	}

	private static func listTextElement(
		name: String,
		content: [String],
		numberType: Rv_Data_Graphics.Text.Attributes.Paragraph.TextList.NumberType,
		markerFormat: NSTextList.MarkerFormat,
		bounds: CGRect,
	) throws -> Rv_Data_Slide.Element {
		guard let font = NSFont(name: "AvenirNext-DemiBold", size: 42) else {
			throw RenderingEdgeCasesFixtureError.missingFont("AvenirNext-DemiBold")
		}
		let textList = NSTextList(markerFormat: markerFormat, options: 0)
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .left
		paragraph.firstLineHeadIndent = 24
		paragraph.headIndent = 110
		paragraph.defaultTabInterval = 36
		paragraph.tabStops = [
			NSTextTab(textAlignment: .right, location: 54, options: [:]),
			NSTextTab(textAlignment: .left, location: 110, options: [:]),
		]
		paragraph.textLists = [textList]
		paragraph.lineSpacing = 12
		let attributed = NSAttributedString(
			string: content.map { "\t\($0)" }.joined(separator: "\n"),
			attributes: [
				.font: font,
				.foregroundColor: NSColor.white,
				.paragraphStyle: paragraph,
			],
		)
		var element = try textElement(name: name, attributed: attributed, bounds: bounds, primaryFont: font)
		element.element.text.rtfData = try addingListTextDestinations(
			to: element.element.text.rtfData,
			content: content,
			numberType: numberType,
		)
		var list = Rv_Data_Graphics.Text.Attributes.Paragraph.TextList()
		list.isEnabled = true
		list.numberType = numberType
		list.startingNumber = 1
		if numberType == .decimal {
			list.postfix = "."
		}
		var firstTab = Rv_Data_Graphics.Text.Attributes.Paragraph.TabStop()
		firstTab.location = 54
		firstTab.alignment = .right
		var secondTab = Rv_Data_Graphics.Text.Attributes.Paragraph.TabStop()
		secondTab.location = 110
		secondTab.alignment = .left
		element.element.text.attributes.paragraphStyle.firstLineHeadIndent = 24
		element.element.text.attributes.paragraphStyle.headIndent = 110
		element.element.text.attributes.paragraphStyle.defaultTabInterval = 36
		element.element.text.attributes.paragraphStyle.tabStops = [firstTab, secondTab]
		element.element.text.attributes.paragraphStyle.textList = list
		element.element.text.attributes.paragraphStyle.textLists = [list]
		return element
	}

	private static func addingListTextDestinations(
		to data: Data,
		content: [String],
		numberType: Rv_Data_Graphics.Text.Attributes.Paragraph.TextList.NumberType,
	) throws -> Data {
		guard var rtf = String(data: data, encoding: .utf8) else {
			throw RenderingEdgeCasesFixtureError.invalidListRTF
		}

		for (index, line) in content.enumerated() {
			let destination: String
			if numberType == .decimal {
				destination = "{\\listtext\t\(index + 1).\t}"
			} else if numberType == .disc {
				destination = "{\\listtext\t\\uc0\\u8226 \t}"
			} else {
				throw RenderingEdgeCasesFixtureError.invalidListRTF
			}

			guard let lineRange = rtf.range(of: "\t\(line)") else {
				throw RenderingEdgeCasesFixtureError.invalidListRTF
			}
			rtf.replaceSubrange(lineRange, with: destination + line)
		}

		return Data(rtf.utf8)
	}

	private static func maskedText(
		name: String,
		content: String,
		bounds: CGRect,
		heightOffset: Double,
		fill: Rv_Data_Color,
	) throws -> Rv_Data_Slide.Element {
		var element = try textElement(
			name: name,
			content: content,
			bounds: bounds,
			fontName: "AvenirNext-Heavy",
			fontSize: 42,
			textColor: .white,
			alignment: .center,
		)
		element.element.fill.enable = true
		element.element.fill.color = fill
		var mask = Rv_Data_Graphics.Text.LineFillMask()
		mask.enabled = true
		mask.heightOffset = heightOffset
		mask.maskStyle = .lineWidth
		mask.widthOffset = 20
		element.element.textLineMask = mask
		return element
	}

	private static func textElement(
		name: String,
		content: String,
		bounds: CGRect,
		fontName: String,
		fontSize: CGFloat,
		textColor: NSColor,
		alignment: NSTextAlignment,
		strokeColor: NSColor? = nil,
		strokeWidth: CGFloat = 0,
	) throws -> Rv_Data_Slide.Element {
		guard let font = NSFont(name: fontName, size: fontSize) else {
			throw RenderingEdgeCasesFixtureError.missingFont(fontName)
		}
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = alignment
		paragraph.lineHeightMultiple = 1.05
		var attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: textColor,
			.paragraphStyle: paragraph,
		]
		if let strokeColor, strokeWidth != 0 {
			attributes[.strokeColor] = strokeColor
			attributes[.strokeWidth] = strokeWidth
		}
		let attributed = NSAttributedString(string: content, attributes: attributes)
		return try textElement(name: name, attributed: attributed, bounds: bounds, primaryFont: font)
	}

	private static func textElement(
		name: String,
		attributed: NSAttributedString,
		bounds: CGRect,
		primaryFont: NSFont,
	) throws -> Rv_Data_Slide.Element {
		var element = rectangle(name: name, bounds: bounds, fill: color(0, 0, 0, 0))
		element.element.fill.enable = false
		element.element.text.rtfData = try attributed.data(
			from: NSRange(location: 0, length: attributed.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)
		element.element.text.scaleBehavior = .scaleFontDown
		element.element.text.verticalAlignment = .middle
		element.element.text.isSuperscriptStandardized = true
		element.element.text.margins.left = 14
		element.element.text.margins.right = 14
		element.element.text.margins.top = 10
		element.element.text.margins.bottom = 10
		element.element.text.attributes.font.name = primaryFont.fontName
		element.element.text.attributes.font.family = primaryFont.familyName ?? "Avenir Next"
		element.element.text.attributes.font.size = primaryFont.pointSize
		element.element.text.attributes.textSolidFill = color(1, 1, 1)
		return element
	}

	private static func alternateTextLink(
		to element: Rv_Data_Graphics.Element,
		transform: Rv_Data_Slide.Element.DataLink.AlternateElementText.TextTransformOption = .none,
	) -> Rv_Data_Slide.Element.DataLink {
		var alternate = Rv_Data_Slide.Element.DataLink.AlternateElementText()
		alternate.otherElementUuid = element.uuid
		alternate.otherElementName = element.name
		alternate.textTransform = transform
		var link = Rv_Data_Slide.Element.DataLink()
		link.alternateText = alternate
		return link
	}

	private static func background() -> Rv_Data_Slide.Element {
		rectangle(
			name: "Midnight background",
			bounds: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight),
			fill: color(0.035, 0.055, 0.09),
		)
	}

	private static func rectangle(
		name: String,
		bounds: CGRect,
		fill: Rv_Data_Color,
	) -> Rv_Data_Slide.Element {
		var element = Rv_Data_Graphics.Element()
		element.name = name
		element.bounds.origin.x = bounds.origin.x
		element.bounds.origin.y = bounds.origin.y
		element.bounds.size.width = bounds.width
		element.bounds.size.height = bounds.height
		element.opacity = 1
		element.path.closed = true
		element.path.shape.type = .rectangle
		element.path.points = [(0.0, 0.0), (1, 0), (1, 1), (0, 1)].map { x, y in
			var point = Rv_Data_Graphics.Path.BezierPoint()
			point.point.x = x
			point.point.y = y
			point.q0 = point.point
			point.q1 = point.point
			return point
		}
		element.fill.enable = true
		element.fill.color = fill
		var result = Rv_Data_Slide.Element()
		result.element = element
		return result
	}

	private static func uuid(_ value: Int) -> Rv_Data_UUID {
		var uuid = Rv_Data_UUID()
		uuid.string = String(format: "45444745-4341-4000-8000-%012d", value)
		return uuid
	}

	private static func color(
		_ red: Float,
		_ green: Float,
		_ blue: Float,
		_ alpha: Float = 1,
	) -> Rv_Data_Color {
		var color = Rv_Data_Color()
		color.red = red
		color.green = green
		color.blue = blue
		color.alpha = alpha
		return color
	}
}

private enum RenderingEdgeCasesFixtureError: Error, CustomStringConvertible {
	case invalidListRTF
	case missingFont(String)
	case outOfDate(URL)

	var description: String {
		switch self {
		case .invalidListRTF:
			"Cannot add ProPresenter-compatible list markers to the generated RTF."
		case let .missingFont(name):
			"The macOS system font \(name) is unavailable."
		case let .outOfDate(url):
			"Rendering edge-cases fixture is out of date: \(url.path). Run swift run FixtureGenerator generate-rendering-edge-cases."
		}
	}
}
