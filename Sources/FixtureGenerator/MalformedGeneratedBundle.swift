import Foundation
import ProCRUDCore
import ProPresenterProto
import SwiftProtobuf

enum MalformedGeneratedBundleFixture {
	static let slideCount = 5

	private static let directoryName = "MalformedGeneratedBundle"
	private static let presentationFilename = "Malformed Generated Bundle.pro"
	private static let bundleFilename = "MalformedGeneratedBundle.probundle"
	private static let canvasWidth = 854.0
	private static let canvasHeight = 480.0

	static func generate(in fixturesDirectory: URL, check: Bool) throws {
		let fixtureDirectory = fixturesDirectory.appendingPathComponent(directoryName, isDirectory: true)
		let expectedPresentation = try presentation().serializedData()

		if check {
			let checkedPresentation = try presentationData(in: fixtureDirectory)
			guard checkedPresentation == expectedPresentation else {
				throw MalformedGeneratedBundleFixtureError.outOfDate(
					fixtureDirectory.appendingPathComponent(bundleFilename),
				)
			}
			return
		}

		let workspace = FileManager.default.temporaryDirectory
			.appendingPathComponent("ProCRUD-malformed-fixture-\(UUID().uuidString)", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: workspace) }
		try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
		try expectedPresentation.write(to: workspace.appendingPathComponent(presentationFilename), options: .atomic)
		let bundleURL = fixtureDirectory.appendingPathComponent(bundleFilename)
		_ = try DocumentArchive.bundle(workspace, to: bundleURL, replace: true)
		print("Generated \(bundleURL.path)")
	}

	private static func presentationData(in fixtureDirectory: URL) throws -> Data {
		let bundleURL = fixtureDirectory.appendingPathComponent(bundleFilename)
		guard FileManager.default.fileExists(atPath: bundleURL.path) else {
			throw MalformedGeneratedBundleFixtureError.outOfDate(bundleURL)
		}
		let document = try DocumentLoader.load(from: bundleURL)
		return try document.payload.serializedData()
	}

	private static func presentation() throws -> Rv_Data_Presentation {
		let names = [
			"Single-face stale font metadata",
			"Font-table variants",
			"Malformed range shapes",
			"Explicit line breaks",
			"Zero opacity",
		]
		let slideElements = [
			singleFaceStaleFontElements(),
			fontTableVariantElements(),
			malformedRangeElements(),
			lineBreakElements(),
			opacityElements(),
		].map { elements in
			// ProPresenter stores slide elements front-to-back and paints the
			// repeated field in reverse. Keep the full-canvas background last so
			// it paints first without hiding the focused probes.
			Array(elements.dropFirst()) + Array(elements.prefix(1))
		}

		var presentation = DocumentFactory.presentation(name: "Malformed Generated Bundle")
		presentation.uuid = uuid(1)
		presentation.cues = zip(names.indices, names).map { index, name in
			cue(index: index, name: name, elements: slideElements[index])
		}
		presentation.cueGroups[0].group.uuid = uuid(2)
		presentation.cueGroups[0].group.name = "Focused malformed cases"
		presentation.cueGroups[0].cueIdentifiers = presentation.cues.map(\.uuid)
		return presentation
	}

	private static func singleFaceStaleFontElements() -> [Rv_Data_Slide.Element] {
		[
			background(),
			label("Single font table + inline bold", y: 28),
			label("Valid metadata", y: 108, size: 21),
			text(
				"VALID BOLD",
				y: 137,
				height: 75,
				rtf: singleFaceRTF("VALID BOLD", bold: true, size: 34),
				scaleBehavior: .none,
			),
			label("Stale originalFontSize range", y: 244, size: 21),
			text(
				"STALE BOLD",
				y: 273,
				height: 75,
				rtf: singleFaceRTF("STALE BOLD", bold: true, size: 34),
				customAttributes: [customAttribute(start: 0, end: 200, value: .originalFontSize(68))],
				scaleBehavior: .none,
			),
		]
	}

	private static func fontTableVariantElements() -> [Rv_Data_Slide.Element] {
		[
			background(),
			label("Stale range with different RTF font tables", y: 28),
			label("Single face + fontScaleFactor 0.5", y: 108, size: 21),
			text(
				"SCALE 0.5",
				y: 137,
				height: 75,
				rtf: singleFaceRTF("SCALE 0.5", bold: true, size: 34),
				customAttributes: [customAttribute(start: 0, end: 200, value: .fontScaleFactor(0.5))],
			),
			label("Two faces + fontScaleFactor 2.0", y: 244, size: 21),
			text(
				"SCALE 2.0",
				y: 273,
				height: 75,
				rtf: twoFaceBoldRTF("SCALE 2.0", size: 34),
				customAttributes: [customAttribute(start: 0, end: 200, value: .fontScaleFactor(2))],
			),
		]
	}

	private static func malformedRangeElements() -> [Rv_Data_Slide.Element] {
		let cases: [(String, Int32, Int32)] = [
			("VALID 0...4", 0, 4),
			("NEGATIVE START", -4, 5),
			("REVERSED", 8, 3),
			("PAST END", 0, 200),
		]
		var elements = [background(), label("Range-shape fuzz cases", y: 28)]
		for (index, rangeCase) in cases.enumerated() {
			let y = 100.0 + Double(index) * 82
			elements.append(label(rangeCase.0, x: 62, y: y, width: 250, size: 18))
			elements.append(text(
				"BOLD",
				x: 330,
				y: y - 12,
				width: 455,
				height: 65,
				rtf: singleFaceRTF("BOLD", bold: true, size: 30),
				customAttributes: [
					customAttribute(
						start: rangeCase.1,
						end: rangeCase.2,
						value: .shouldPreserveForegroundColor(true),
					),
				],
			))
		}
		return elements
	}

	private static func lineBreakElements() -> [Rv_Data_Slide.Element] {
		[
			background(),
			label("Explicit line-break layout", y: 28),
			label("Valid metadata", x: 75, y: 105, width: 300, size: 21),
			label("Stale range", x: 485, y: 105, width: 300, size: 21),
			text(
				"ALPHA\nBETA",
				x: 75,
				y: 145,
				width: 300,
				height: 220,
				rtf: singleFaceRTF("ALPHA\\line BETA", size: 31),
			),
			text(
				"ALPHA\nBETA",
				x: 485,
				y: 145,
				width: 300,
				height: 220,
				rtf: singleFaceRTF("ALPHA\\line BETA", size: 31),
				customAttributes: [customAttribute(start: 0, end: 200, value: .originalFontSize(62))],
			),
		]
	}

	private static func opacityElements() -> [Rv_Data_Slide.Element] {
		[
			background(),
			label("Element opacity boundary", y: 28),
			label("0%", x: 68, y: 115, width: 200, size: 23),
			label("25%", x: 327, y: 115, width: 200, size: 23),
			label("100%", x: 586, y: 115, width: 200, size: 23),
			text("TEXT", x: 68, y: 375, width: 200, height: 55, rtf: singleFaceRTF("TEXT", bold: true, size: 24), opacity: 0),
			text("TEXT", x: 327, y: 375, width: 200, height: 55, rtf: singleFaceRTF("TEXT", bold: true, size: 24), opacity: 0.25),
			text("TEXT", x: 586, y: 375, width: 200, height: 55, rtf: singleFaceRTF("TEXT", bold: true, size: 24), opacity: 1),
			rectangle(name: "Zero opacity", x: 68, y: 165, width: 200, height: 200, opacity: 0, color: color(0.92, 0.25, 0.2)),
			rectangle(name: "Quarter opacity", x: 327, y: 165, width: 200, height: 200, opacity: 0.25, color: color(0.2, 0.75, 0.35)),
			rectangle(name: "Full opacity", x: 586, y: 165, width: 200, height: 200, opacity: 1, color: color(0.15, 0.45, 0.95)),
		]
	}

	private static func cue(index: Int, name: String, elements: [Rv_Data_Slide.Element]) -> Rv_Data_Cue {
		var slide = Rv_Data_Slide()
		slide.uuid = uuid(100 + index)
		slide.size.width = canvasWidth
		slide.size.height = canvasHeight
		slide.elements = elements.enumerated().map { elementIndex, slideElement in
			var result = slideElement
			result.element.uuid = uuid(1000 + index * 100 + elementIndex)
			result.info = UInt32(elements.count - elementIndex)
			return result
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
			name: "White background",
			x: 0,
			y: 0,
			width: canvasWidth,
			height: canvasHeight,
			opacity: 1,
			color: color(0.97, 0.97, 0.96),
		)
	}

	private static func label(
		_ value: String,
		x: Double = 50,
		y: Double,
		width: Double = 754,
		size: Int = 26,
	) -> Rv_Data_Slide.Element {
		text(
			value,
			x: x,
			y: y,
			width: width,
			height: Double(size) + 24,
			rtf: singleFaceRTF(value, size: size),
		)
	}

	private static func text(
		_ name: String,
		x: Double = 50,
		y: Double,
		width: Double = 754,
		height: Double,
		rtf: Data,
		customAttributes: [Rv_Data_Graphics.Text.Attributes.CustomAttribute] = [],
		opacity: Double = 1,
		scaleBehavior: Rv_Data_Graphics.Text.ScaleBehavior = .scaleFontDown,
	) -> Rv_Data_Slide.Element {
		var element = rectangle(name: name, x: x, y: y, width: width, height: height, opacity: opacity, color: color(0, 0, 0, 0))
		element.element.fill.enable = false
		element.element.text.rtfData = rtf
		element.element.text.scaleBehavior = scaleBehavior
		element.element.text.verticalAlignment = .middle
		element.element.text.attributes.customAttributes = customAttributes
		if customAttributes.isEmpty {
			element.element.text.attributes.font.name = "Helvetica"
			element.element.text.attributes.font.family = "Helvetica"
		} else {
			// Reproduce the editor failure's contradictory state: replacement
			// RTF names one family while compatibility metadata from the previous
			// contents still names another.
			element.element.text.attributes.font.name = "Times-Roman"
			element.element.text.attributes.font.family = "Times"
		}
		element.element.text.attributes.font.size = 34
		element.element.text.attributes.textSolidFill = color(0.08, 0.1, 0.12)
		return element
	}

	private static func rectangle(
		name: String,
		x: Double,
		y: Double,
		width: Double,
		height: Double,
		opacity: Double,
		color: Rv_Data_Color,
	) -> Rv_Data_Slide.Element {
		var element = Rv_Data_Graphics.Element()
		element.name = name
		element.bounds.origin.x = x
		element.bounds.origin.y = y
		element.bounds.size.width = width
		element.bounds.size.height = height
		element.opacity = opacity
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
		var slideElement = Rv_Data_Slide.Element()
		slideElement.element = element
		return slideElement
	}

	private static func singleFaceRTF(_ body: String, bold: Bool = false, size: Int) -> Data {
		Data(
			"""
			{\\rtf1\\ansi\\ansicpg1252\\cocoartf2870
			{\\fonttbl\\f0\\fnil\\fcharset0 Helvetica;}
			{\\colortbl;\\red20\\green26\\blue31;}
			\\pard\\qc\\f0\(bold ? "\\b" : "\\b0")\\fs\(size * 2)\\cf1 \(body)}
			""".utf8,
		)
	}

	private static func twoFaceBoldRTF(_ body: String, size: Int) -> Data {
		Data(
			"""
			{\\rtf1\\ansi\\ansicpg1252\\cocoartf2870
			{\\fonttbl\\f0\\fnil\\fcharset0 Helvetica;\\f1\\fnil\\fcharset0 Helvetica-Bold;}
			{\\colortbl;\\red20\\green26\\blue31;}
			\\pard\\qc\\f1\\fs\(size * 2)\\cf1 \(body)}
			""".utf8,
		)
	}

	private static func customAttribute(
		start: Int32,
		end: Int32,
		value: Rv_Data_Graphics.Text.Attributes.CustomAttribute.OneOf_Attribute,
	) -> Rv_Data_Graphics.Text.Attributes.CustomAttribute {
		var attribute = Rv_Data_Graphics.Text.Attributes.CustomAttribute()
		attribute.range.start = start
		attribute.range.end = end
		attribute.attribute = value
		return attribute
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

private enum MalformedGeneratedBundleFixtureError: Error, CustomStringConvertible {
	case outOfDate(URL)

	var description: String {
		switch self {
		case let .outOfDate(url):
			"Generated malformed-bundle fixture is out of date: \(url.path). Run swift run FixtureGenerator generate-malformed-bundle."
		}
	}
}
