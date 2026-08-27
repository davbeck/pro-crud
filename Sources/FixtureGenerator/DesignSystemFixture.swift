import AppKit
import Foundation
import ProCRUDCore
import ProPresenterProto
import SwiftProtobuf

enum DesignSystemFixture {
	private static let canvasWidth = 1920.0
	private static let canvasHeight = 1080.0
	private static let themeRelativePath = "assets/themes/ProCRUD Design System.proTheme"

	static func generate(in repositoryRoot: URL, check: Bool) throws {
		let temporaryDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("ProCRUDDesignSystem-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

		let generatedThemeURL = temporaryDirectory.appendingPathComponent("ProCRUD Design System.proTheme")
		try writeTheme(makeThemeGroups(), to: generatedThemeURL, in: temporaryDirectory)

		let themeURL = repositoryRoot
			.appendingPathComponent("skills/pro-crud", isDirectory: true)
			.appendingPathComponent(themeRelativePath)
		if check {
			try requireEquivalentTheme(at: themeURL, to: generatedThemeURL)
		} else {
			try install(generatedThemeURL, at: themeURL)
			print("Generated \(themeURL.path)")
		}
	}

	private static func makeThemeGroups() throws -> [ThemeGroup] {
		let identifiers = IdentifierFactory()
		return try [
			ThemeGroup(
				relativePath: "ProCRUD - Streaming/Theme",
				templates: makeStreamingTemplates(identifiers: identifiers),
			),
			ThemeGroup(
				relativePath: "ProCRUD - Teaching/Theme",
				templates: makeTeachingTemplates(identifiers: identifiers),
			),
			ThemeGroup(
				relativePath: "ProCRUD - Worship 1/Theme",
				templates: makeClassicWorshipTemplates(identifiers: identifiers),
			),
			ThemeGroup(
				relativePath: "ProCRUD - Worship 2/Theme",
				templates: makeCreativeWorshipTemplates(identifiers: identifiers),
			),
		]
	}

	private static func makeStreamingTemplates(
		identifiers: IdentifierFactory,
	) throws -> [Rv_Data_Template.Slide] {
		let lyric = "Your love awakens me\nand calls me home"
		let lyricCaps = lyric.uppercased()
		let extended = "Your love awakens me and calls me home"
		let scripture = "The light shines in the darkness,\nand the darkness did not overcome it."
		let reference = "JOHN 1:5 · NRSVUE"
		let point = "GRACE MAKES A WAY"

		return try [
			template("Bold", identifiers: identifiers, elements: [
				text("Lyrics", content: lyric, bounds: rect(170, 740, 900, 230), font: "AvenirNext-Bold", size: 64, alignment: .left, shadow: true, identifiers: identifiers),
			]),
			template("Bold CAPS", identifiers: identifiers, elements: [
				text("Lyrics", content: lyricCaps, bounds: rect(170, 740, 950, 230), font: "AvenirNext-Bold", size: 58, alignment: .left, tracking: 2, shadow: true, identifiers: identifiers),
			]),
			template("Bold Extended", identifiers: identifiers, elements: [
				text("Lyrics", content: extended, bounds: rect(150, 820, 1500, 135), font: "AvenirNext-Bold", size: 52, alignment: .left, shadow: true, identifiers: identifiers),
			]),
			template("Bold Extended CAPS", identifiers: identifiers, elements: [
				text("Lyrics", content: extended.uppercased(), bounds: rect(150, 820, 1600, 135), font: "AvenirNext-Bold", size: 46, alignment: .left, tracking: 2, shadow: true, identifiers: identifiers),
			]),
			template("Dark Wide Bar", identifiers: identifiers, elements: [
				text("Lyrics", content: extended, bounds: rect(140, 845, 1640, 110), font: "AvenirNext-DemiBold", size: 45, alignment: .center, identifiers: identifiers),
				shape("Bar", bounds: rect(100, 820, 1720, 160), fill: .ink82, identifiers: identifiers),
			]),
			template("Dark Wide Bar CAPS", identifiers: identifiers, elements: [
				text("Lyrics", content: extended.uppercased(), bounds: rect(140, 845, 1640, 110), font: "AvenirNext-DemiBold", size: 42, alignment: .center, tracking: 2, identifiers: identifiers),
				shape("Bar", bounds: rect(100, 820, 1720, 160), fill: .ink82, identifiers: identifiers),
			]),
			template("Line Frame", identifiers: identifiers, elements: [
				text("Lyrics", content: lyric, bounds: rect(170, 715, 960, 250), font: "AvenirNext-Bold", size: 58, alignment: .left, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(125, 680, 1050, 320), stroke: .ivory90, strokeWidth: 4, identifiers: identifiers),
			]),
			template("Single Phrase Line Frame", identifiers: identifiers, elements: [
				text("Lyrics", content: extended, bounds: rect(165, 805, 1510, 120), font: "AvenirNext-Bold", size: 48, alignment: .center, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(125, 770, 1590, 190), stroke: .ivory90, strokeWidth: 4, identifiers: identifiers),
			]),
			template("Light Bar", identifiers: identifiers, elements: [
				text("Lyrics", content: lyric, bounds: rect(140, 760, 1080, 210), font: "AvenirNext-DemiBold", size: 54, color: .ink, alignment: .left, identifiers: identifiers),
				shape("Bar", bounds: rect(105, 730, 1150, 270), fill: .ivory92, identifiers: identifiers),
			]),
			template("Dark Bar", identifiers: identifiers, elements: [
				text("Lyrics", content: lyric, bounds: rect(140, 760, 1080, 210), font: "AvenirNext-DemiBold", size: 54, alignment: .left, identifiers: identifiers),
				shape("Bar", bounds: rect(105, 730, 1150, 270), fill: .ink82, identifiers: identifiers),
			]),
			template("Double Bar Light", identifiers: identifiers, elements: [
				text("Lyrics", content: lyric, bounds: rect(140, 745, 1050, 230), font: "AvenirNext-Bold", size: 54, color: .ink, alignment: .left, identifiers: identifiers),
				shape("Accent", bounds: rect(105, 710, 1120, 12), fill: .aqua, identifiers: identifiers),
				shape("Bar", bounds: rect(105, 722, 1120, 285), fill: .ivory92, identifiers: identifiers),
			]),
			template("Double Bar Dark", identifiers: identifiers, elements: [
				text("Lyrics", content: lyric, bounds: rect(140, 745, 1050, 230), font: "AvenirNext-Bold", size: 54, alignment: .left, identifiers: identifiers),
				shape("Accent", bounds: rect(105, 710, 1120, 12), fill: .amber, identifiers: identifiers),
				shape("Bar", bounds: rect(105, 722, 1120, 285), fill: .ink82, identifiers: identifiers),
			]),
			template("Name Heavy", identifiers: identifiers, elements: [
				text("Name", content: "MORGAN LEE", bounds: rect(130, 820, 850, 105), font: "AvenirNext-Heavy", size: 52, alignment: .left, tracking: 2, shadow: true, identifiers: identifiers),
				text("Position", content: "WORSHIP LEADER", bounds: rect(130, 930, 850, 60), font: "AvenirNext-Medium", size: 25, color: .aqua, alignment: .left, tracking: 3, shadow: true, identifiers: identifiers),
				shape("Rule", bounds: rect(105, 805, 12, 195), fill: .aqua, identifiers: identifiers),
			]),
			template("Name Light Bar", identifiers: identifiers, elements: [
				text("Name", content: "Morgan Lee", bounds: rect(145, 825, 760, 90), font: "AvenirNext-Bold", size: 48, color: .ink, alignment: .left, identifiers: identifiers),
				text("Position", content: "Worship Leader", bounds: rect(145, 915, 760, 55), font: "AvenirNext-Medium", size: 25, color: .ink, alignment: .left, identifiers: identifiers),
				shape("Bar", bounds: rect(110, 795, 840, 205), fill: .ivory92, identifiers: identifiers),
			]),
			template("Name Line Frame", identifiers: identifiers, elements: [
				text("Name", content: "Morgan Lee", bounds: rect(150, 815, 780, 95), font: "AvenirNext-Bold", size: 46, alignment: .left, shadow: true, identifiers: identifiers),
				text("Position", content: "WORSHIP LEADER", bounds: rect(150, 910, 780, 55), font: "AvenirNext-Medium", size: 24, color: .amber, alignment: .left, tracking: 2, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(115, 785, 855, 215), stroke: .ivory90, strokeWidth: 4, identifiers: identifiers),
			]),
			template("Scripture", identifiers: identifiers, elements: scriptureOverlay(scripture, reference: reference, x: 115, y: 685, width: 1140, panel: nil, centered: false, extended: false, identifiers: identifiers)),
			template("Scripture Bar", identifiers: identifiers, elements: scriptureOverlay(scripture, reference: reference, x: 115, y: 675, width: 1180, panel: .ink82, centered: false, extended: false, identifiers: identifiers)),
			template("Scripture Center", identifiers: identifiers, elements: scriptureOverlay(scripture, reference: reference, x: 330, y: 710, width: 1260, panel: nil, centered: true, extended: false, identifiers: identifiers)),
			template("Scripture Extended", identifiers: identifiers, elements: scriptureOverlay(scripture, reference: reference, x: 110, y: 775, width: 1620, panel: nil, centered: false, extended: true, identifiers: identifiers)),
			template("Scripture Extended Bar", identifiers: identifiers, elements: scriptureOverlay(scripture, reference: reference, x: 110, y: 745, width: 1620, panel: .ink82, centered: false, extended: true, identifiers: identifiers)),
			template("Scripture Center Extended", identifiers: identifiers, elements: scriptureOverlay(scripture, reference: reference, x: 150, y: 775, width: 1620, panel: nil, centered: true, extended: true, identifiers: identifiers)),
			template("Point Line Frame", identifiers: identifiers, elements: [
				text("Teaching Point", content: point, bounds: rect(145, 805, 1300, 125), font: "AvenirNext-Heavy", size: 53, alignment: .left, tracking: 2, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(105, 770, 1380, 195), stroke: .ivory90, strokeWidth: 4, identifiers: identifiers),
			]),
			template("Point Bold", identifiers: identifiers, elements: [
				text("Teaching Point", content: point, bounds: rect(125, 785, 1370, 155), font: "AvenirNext-Heavy", size: 65, alignment: .left, tracking: 2, shadow: true, identifiers: identifiers),
			]),
			template("Point Light Bar", identifiers: identifiers, elements: [
				text("Teaching Point", content: point, bounds: rect(145, 805, 1300, 125), font: "AvenirNext-Bold", size: 52, color: .ink, alignment: .left, tracking: 2, identifiers: identifiers),
				shape("Bar", bounds: rect(105, 770, 1380, 195), fill: .ivory92, identifiers: identifiers),
			]),
		]
	}

	private static func scriptureOverlay(
		_ scripture: String,
		reference: String,
		x: Double,
		y: Double,
		width: Double,
		panel: DesignColor?,
		centered: Bool,
		extended: Bool,
		identifiers: IdentifierFactory,
	) throws -> [Rv_Data_Slide.Element] {
		let alignment: Rv_Data_Graphics.Text.Attributes.Paragraph.Alignment = centered ? .center : .left
		let textHeight = extended ? 120.0 : 195.0
		let needsShadow = panel == nil
		var elements = try [
			text("Bible Text", content: scripture, bounds: rect(x + 30, y + 25, width - 60, textHeight), font: "AvenirNext-DemiBold", size: extended ? 40 : 44, alignment: alignment, lineHeight: 1.18, shadow: needsShadow, identifiers: identifiers),
			text("Bible Reference", content: reference, bounds: rect(x + 30, y + textHeight + 27, width - 60, 55), font: "AvenirNext-Medium", size: 23, color: .aqua, alignment: alignment, tracking: 2, shadow: needsShadow, identifiers: identifiers),
		]
		if let panel {
			elements.append(shape("Bar", bounds: rect(x, y, width, textHeight + 115), fill: panel, identifiers: identifiers))
		}
		return elements
	}

	private static func makeTeachingTemplates(
		identifiers: IdentifierFactory,
	) throws -> [Rv_Data_Template.Slide] {
		let title = "PRACTICING PRESENCE"
		let subtitle = "A life attentive to grace"
		let scripture = "Be still, and know that I am God."
		let reference = "PSALM 46:10 · NRSVUE"
		let teachingPoint = "ATTENTION IS AN ACT OF LOVE"
		let quotation = "The spiritual life begins when we learn to notice."

		return try [
			template("Title Heavy", identifiers: identifiers, elements: [
				text("Title", content: title, bounds: rect(180, 315, 1560, 260), font: "AvenirNext-Heavy", size: 104, alignment: .center, tracking: 2, shadow: true, identifiers: identifiers),
				text("Subtitle", content: subtitle, bounds: rect(300, 590, 1320, 100), font: "AvenirNext-Medium", size: 40, color: .aqua, alignment: .center, shadow: true, identifiers: identifiers),
				shape("Rule", bounds: rect(710, 735, 500, 10), fill: .aqua, identifiers: identifiers),
			]),
			template("Title Bars Single", identifiers: identifiers, elements: [
				text("Title", content: title, bounds: rect(210, 335, 1500, 230), font: "AvenirNext-Bold", size: 90, alignment: .left, shadow: true, identifiers: identifiers),
				text("Subtitle", content: subtitle, bounds: rect(215, 580, 1400, 90), font: "AvenirNext-Medium", size: 38, alignment: .left, shadow: true, identifiers: identifiers),
				shape("Bar", bounds: rect(155, 300, 18, 405), fill: .amber, identifiers: identifiers),
			]),
			template("Title Bars Triple Dark", identifiers: identifiers, elements: [
				text("Title", content: title, bounds: rect(235, 350, 1450, 215), font: "AvenirNext-Heavy", size: 86, alignment: .center, shadow: true, identifiers: identifiers),
				text("Subtitle", content: subtitle, bounds: rect(300, 580, 1320, 90), font: "AvenirNext-Medium", size: 36, color: .aqua, alignment: .center, shadow: true, identifiers: identifiers),
				shape("Top Rule", bounds: rect(225, 290, 1470, 10), fill: .aqua, identifiers: identifiers),
				shape("Middle Rule", bounds: rect(365, 310, 1190, 5), fill: .ivory90, identifiers: identifiers),
				shape("Bottom Rule", bounds: rect(505, 330, 910, 5), fill: .amber, identifiers: identifiers),
			]),
			template("Title Box Double", identifiers: identifiers, elements: [
				text("Title", content: title, bounds: rect(265, 330, 1390, 235), font: "AvenirNext-Heavy", size: 84, alignment: .center, shadow: true, identifiers: identifiers),
				text("Subtitle", content: subtitle, bounds: rect(315, 580, 1290, 85), font: "AvenirNext-Medium", size: 35, color: .amber, alignment: .center, shadow: true, identifiers: identifiers),
				shape("Inner Frame", bounds: rect(205, 280, 1510, 455), stroke: .aqua, strokeWidth: 4, identifiers: identifiers),
				shape("Outer Frame", bounds: rect(175, 250, 1570, 515), stroke: .ivory90, strokeWidth: 2, identifiers: identifiers),
			]),
			template("Title Line Frame", identifiers: identifiers, elements: [
				text("Title", content: title, bounds: rect(260, 345, 1400, 220), font: "AvenirNext-Bold", size: 84, alignment: .center, shadow: true, identifiers: identifiers),
				text("Subtitle", content: subtitle, bounds: rect(320, 575, 1280, 85), font: "AvenirNext-Medium", size: 35, alignment: .center, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(195, 275, 1530, 470), stroke: .ivory90, strokeWidth: 4, identifiers: identifiers),
			]),
			template("Title Bars Triple Light", identifiers: identifiers, elements: [
				text("Title", content: title, bounds: rect(245, 350, 1430, 215), font: "AvenirNext-Heavy", size: 84, color: .ink, alignment: .center, identifiers: identifiers),
				text("Subtitle", content: subtitle, bounds: rect(320, 580, 1280, 85), font: "AvenirNext-Medium", size: 35, color: .ink, alignment: .center, identifiers: identifiers),
				shape("Accent Top", bounds: rect(205, 285, 1510, 10), fill: .aqua, identifiers: identifiers),
				shape("Accent Bottom", bounds: rect(205, 720, 1510, 10), fill: .amber, identifiers: identifiers),
				shape("Panel", bounds: rect(175, 255, 1570, 505), fill: .ivory92, identifiers: identifiers),
			]),
			template("Name Heavy", identifiers: identifiers, elements: [
				text("Name", content: "DR. MORGAN LEE", bounds: rect(205, 405, 1510, 180), font: "AvenirNext-Heavy", size: 86, alignment: .center, tracking: 2, shadow: true, identifiers: identifiers),
				text("Position", content: "LEAD PASTOR", bounds: rect(400, 600, 1120, 75), font: "AvenirNext-Medium", size: 31, color: .aqua, alignment: .center, tracking: 3, shadow: true, identifiers: identifiers),
				shape("Rule", bounds: rect(710, 715, 500, 9), fill: .aqua, identifiers: identifiers),
			]),
			template("Name Bars", identifiers: identifiers, elements: [
				text("Name", content: "Morgan Lee", bounds: rect(265, 410, 1390, 170), font: "AvenirNext-Bold", size: 78, color: .ink, alignment: .center, identifiers: identifiers),
				text("Position", content: "Lead Pastor", bounds: rect(400, 595, 1120, 70), font: "AvenirNext-Medium", size: 31, color: .ink, alignment: .center, identifiers: identifiers),
				shape("Top Accent", bounds: rect(260, 350, 1400, 12), fill: .amber, identifiers: identifiers),
				shape("Panel", bounds: rect(220, 320, 1480, 410), fill: .ivory92, identifiers: identifiers),
			]),
			template("Name Line Frame", identifiers: identifiers, elements: [
				text("Name", content: "Morgan Lee", bounds: rect(275, 410, 1370, 170), font: "AvenirNext-Bold", size: 76, alignment: .center, shadow: true, identifiers: identifiers),
				text("Position", content: "LEAD PASTOR", bounds: rect(400, 600, 1120, 70), font: "AvenirNext-Medium", size: 29, color: .amber, alignment: .center, tracking: 3, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(220, 345, 1480, 380), stroke: .ivory90, strokeWidth: 4, identifiers: identifiers),
			]),
			template("Scripture Bar", identifiers: identifiers, elements: teachingScripture(scripture, reference: reference, placement: .leftCenter, panel: .ink72, frame: false, identifiers: identifiers)),
			template("Scripture Bar Center", identifiers: identifiers, elements: teachingScripture(scripture, reference: reference, placement: .center, panel: .ink72, frame: false, identifiers: identifiers)),
			template("Scripture Bar Bottom", identifiers: identifiers, elements: teachingScripture(scripture, reference: reference, placement: .leftBottom, panel: .ink72, frame: false, identifiers: identifiers)),
			template("Scripture Bar Bottom Center", identifiers: identifiers, elements: teachingScripture(scripture, reference: reference, placement: .centerBottom, panel: .ink72, frame: false, identifiers: identifiers)),
			template("Scripture", identifiers: identifiers, elements: teachingScripture(scripture, reference: reference, placement: .leftCenter, panel: nil, frame: false, identifiers: identifiers)),
			template("Scripture Frame", identifiers: identifiers, elements: teachingScripture(scripture, reference: reference, placement: .center, panel: nil, frame: true, identifiers: identifiers)),
			template("Point Line Frame", identifiers: identifiers, elements: [
				text("Teaching Point", content: teachingPoint, bounds: rect(250, 365, 1420, 280), font: "AvenirNext-Heavy", size: 78, alignment: .center, tracking: 2, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(185, 300, 1550, 410), stroke: .ivory90, strokeWidth: 4, identifiers: identifiers),
			]),
			template("Point", identifiers: identifiers, elements: [
				text("Teaching Point", content: teachingPoint, bounds: rect(230, 340, 1460, 340), font: "AvenirNext-Heavy", size: 82, alignment: .center, tracking: 2, shadow: true, identifiers: identifiers),
			]),
			template("Point Light Box", identifiers: identifiers, elements: [
				text("Teaching Point", content: teachingPoint, bounds: rect(260, 380, 1400, 270), font: "AvenirNext-Bold", size: 72, color: .ink, alignment: .center, tracking: 2, identifiers: identifiers),
				shape("Panel", bounds: rect(195, 315, 1530, 400), fill: .ivory92, identifiers: identifiers),
			]),
			template("List", identifiers: identifiers, elements: [
				text("Title", content: "A PRACTICE FOR THE WEEK", bounds: rect(220, 170, 1480, 120), font: "AvenirNext-Bold", size: 49, color: .aqua, alignment: .left, tracking: 2, shadow: true, identifiers: identifiers),
				text("List", content: "1. Pause before reacting\n2. Notice what is present\n3. Respond with care", bounds: rect(220, 320, 1480, 520), font: "AvenirNext-DemiBold", size: 58, alignment: .left, lineHeight: 1.35, shadow: true, identifiers: identifiers),
			]),
			template("List Bar", identifiers: identifiers, elements: [
				text("Title", content: "A PRACTICE FOR THE WEEK", bounds: rect(255, 190, 1410, 110), font: "AvenirNext-Bold", size: 45, color: .ink, alignment: .left, tracking: 2, identifiers: identifiers),
				text("List", content: "1. Pause before reacting\n2. Notice what is present\n3. Respond with care", bounds: rect(255, 340, 1410, 470), font: "AvenirNext-DemiBold", size: 55, color: .ink, alignment: .left, lineHeight: 1.32, identifiers: identifiers),
				shape("Accent", bounds: rect(185, 145, 14, 740), fill: .aqua, identifiers: identifiers),
				shape("Panel", bounds: rect(150, 120, 1620, 790), fill: .ivory92, identifiers: identifiers),
			]),
			template("Quote", identifiers: identifiers, elements: quoteElements(quotation, centered: false, panel: nil, identifiers: identifiers)),
			template("Quote Center", identifiers: identifiers, elements: quoteElements(quotation, centered: true, panel: nil, identifiers: identifiers)),
			template("Quote Light Bar", identifiers: identifiers, elements: quoteElements(quotation, centered: false, panel: .ivory92, identifiers: identifiers)),
			template("Quote Light Bar Center", identifiers: identifiers, elements: quoteElements(quotation, centered: true, panel: .ivory92, identifiers: identifiers)),
		]
	}

	private enum ScripturePlacement: Equatable {
		case leftCenter
		case center
		case leftBottom
		case centerBottom
	}

	private static func teachingScripture(
		_ scripture: String,
		reference: String,
		placement: ScripturePlacement,
		panel: DesignColor?,
		frame: Bool,
		identifiers: IdentifierFactory,
	) throws -> [Rv_Data_Slide.Element] {
		let centered = placement == .center || placement == .centerBottom
		let bottom = placement == .leftBottom || placement == .centerBottom
		let x = centered ? 260.0 : 190.0
		let y = bottom ? 610.0 : 285.0
		let width = centered ? 1400.0 : 1370.0
		let alignment: Rv_Data_Graphics.Text.Attributes.Paragraph.Alignment = centered ? .center : .left
		let needsShadow = panel == nil
		var elements = try [
			text("Bible Text", content: scripture, bounds: rect(x + 45, y + 45, width - 90, 220), font: "AvenirNext-DemiBold", size: 66, alignment: alignment, lineHeight: 1.2, shadow: needsShadow, identifiers: identifiers),
			text("Bible Reference", content: reference, bounds: rect(x + 45, y + 285, width - 90, 65), font: "AvenirNext-Medium", size: 29, color: .aqua, alignment: alignment, tracking: 2, shadow: needsShadow, identifiers: identifiers),
		]
		if let panel {
			elements.append(shape("Panel", bounds: rect(x, y, width, 390), fill: panel, identifiers: identifiers))
		} else if frame {
			elements.append(shape("Frame", bounds: rect(x, y, width, 390), stroke: .ivory90, strokeWidth: 4, identifiers: identifiers))
		}
		return elements
	}

	private static func quoteElements(
		_ quotation: String,
		centered: Bool,
		panel: DesignColor?,
		identifiers: IdentifierFactory,
	) throws -> [Rv_Data_Slide.Element] {
		let alignment: Rv_Data_Graphics.Text.Attributes.Paragraph.Alignment = centered ? .center : .left
		let foreground: DesignColor
		let secondary: DesignColor
		if case .none = panel {
			foreground = .ivory
			secondary = .aqua
		} else {
			foreground = .ink
			secondary = .ink
		}
		let needsShadow = panel == nil
		var elements = try [
			text("Quote", content: "“\(quotation)”", bounds: rect(260, 280, 1400, 390), font: "AvenirNext-HeavyItalic", size: 65, color: foreground, alignment: alignment, lineHeight: 1.18, shadow: needsShadow, identifiers: identifiers),
			text("Name", content: "— MORGAN LEE", bounds: rect(270, 690, 1380, 70), font: "AvenirNext-Medium", size: 29, color: secondary, alignment: alignment, tracking: 2, shadow: needsShadow, identifiers: identifiers),
		]
		if let panel {
			elements.append(shape("Panel", bounds: rect(195, 220, 1530, 600), fill: panel, identifiers: identifiers))
		}
		return elements
	}

	private static func makeClassicWorshipTemplates(
		identifiers: IdentifierFactory,
	) throws -> [Rv_Data_Template.Slide] {
		let lyrics = "Your love awakens me\nand calls me home"
		let caps = lyrics.uppercased()
		let extended = "Your love awakens me and calls me home"

		return try [
			classicLyricTemplate("Medium", content: lyrics, font: "AvenirNext-Medium", size: 78, identifiers: identifiers),
			classicLyricTemplate("Bold", content: lyrics, font: "AvenirNext-Bold", size: 78, identifiers: identifiers),
			classicLyricTemplate("Heavy", content: lyrics, font: "AvenirNext-Heavy", size: 78, identifiers: identifiers),
			classicLyricTemplate("Medium Zoom", content: lyrics, font: "AvenirNext-Medium", size: 104, zoom: true, identifiers: identifiers),
			classicLyricTemplate("Bold Zoom", content: lyrics, font: "AvenirNext-Bold", size: 104, zoom: true, identifiers: identifiers),
			classicLyricTemplate("Heavy Zoom", content: lyrics, font: "AvenirNext-Heavy", size: 104, zoom: true, identifiers: identifiers),
			classicLyricTemplate("Medium CAPS", content: caps, font: "AvenirNext-Medium", size: 72, tracking: 2, identifiers: identifiers),
			classicLyricTemplate("Bold CAPS", content: caps, font: "AvenirNext-Bold", size: 72, tracking: 2, identifiers: identifiers),
			classicLyricTemplate("Heavy CAPS", content: caps, font: "AvenirNext-Heavy", size: 72, tracking: 2, identifiers: identifiers),
			classicLyricTemplate("Medium Zoom CAPS", content: caps, font: "AvenirNext-Medium", size: 92, zoom: true, tracking: 2, identifiers: identifiers),
			classicLyricTemplate("Bold Zoom CAPS", content: caps, font: "AvenirNext-Bold", size: 92, zoom: true, tracking: 2, identifiers: identifiers),
			classicLyricTemplate("Heavy Zoom CAPS", content: caps, font: "AvenirNext-Heavy", size: 92, zoom: true, tracking: 2, identifiers: identifiers),
			classicLyricTemplate("Bold Extended", content: extended, font: "AvenirNext-Bold", size: 61, extended: true, identifiers: identifiers),
			classicLyricTemplate("Bold Extended CAPS", content: extended.uppercased(), font: "AvenirNext-Bold", size: 54, extended: true, tracking: 2, identifiers: identifiers),
			classicLyricTemplate("Extended Line Frame", content: extended, font: "AvenirNext-Bold", size: 55, extended: true, decoration: .frame, identifiers: identifiers),
			classicLyricTemplate("Line Frame", content: lyrics, font: "AvenirNext-Bold", size: 76, decoration: .frame, identifiers: identifiers),
			classicLyricTemplate("Line Frame Zoom", content: lyrics, font: "AvenirNext-Heavy", size: 96, zoom: true, decoration: .frame, identifiers: identifiers),
			classicLyricTemplate("Double Bar Dark Wide", content: extended, font: "AvenirNext-Bold", size: 55, extended: true, decoration: .doubleBarDark(wide: true), identifiers: identifiers),
			classicLyricTemplate("Double Bar Dark", content: lyrics, font: "AvenirNext-Bold", size: 70, decoration: .doubleBarDark(wide: false), identifiers: identifiers),
			classicLyricTemplate("Double Bar Light", content: lyrics, font: "AvenirNext-Bold", size: 70, decoration: .doubleBarLight(wide: false), identifiers: identifiers),
			classicLyricTemplate("Double Bar Light Wide", content: extended, font: "AvenirNext-Bold", size: 55, extended: true, decoration: .doubleBarLight(wide: true), identifiers: identifiers),
			classicLyricTemplate("Dark Box", content: lyrics, font: "AvenirNext-Bold", size: 72, decoration: .darkBox(opacity: 0.92), identifiers: identifiers),
			classicLyricTemplate("Dark Translucent Box", content: lyrics, font: "AvenirNext-Bold", size: 72, decoration: .darkBox(opacity: 0.62), identifiers: identifiers),
			classicLyricTemplate("Light Box", content: lyrics, font: "AvenirNext-Bold", size: 72, decoration: .lightBox, identifiers: identifiers),
		]
	}

	private enum ClassicDecoration {
		case none
		case frame
		case doubleBarDark(wide: Bool)
		case doubleBarLight(wide: Bool)
		case darkBox(opacity: CGFloat)
		case lightBox
	}

	private static func classicLyricTemplate(
		_ name: String,
		content: String,
		font: String,
		size: CGFloat,
		zoom: Bool = false,
		extended: Bool = false,
		tracking: CGFloat = 0,
		decoration: ClassicDecoration = .none,
		identifiers: IdentifierFactory,
	) throws -> Rv_Data_Template.Slide {
		let bounds: CGRect
		if extended {
			bounds = rect(145, 425, 1630, 230)
		} else if zoom {
			bounds = rect(145, 205, 1630, 670)
		} else {
			bounds = rect(190, 250, 1540, 580)
		}
		let usesDarkText: Bool
		switch decoration {
		case .doubleBarLight, .lightBox: usesDarkText = true
		default: usesDarkText = false
		}
		var elements = try [
			text(
				"Lyrics",
				content: content,
				bounds: bounds,
				font: font,
				size: size,
				color: usesDarkText ? .ink : .ivory,
				alignment: .center,
				tracking: tracking,
				lineHeight: 1.2,
				shadow: !usesDarkText,
				identifiers: identifiers,
			),
		]
		switch decoration {
		case .none:
			break
		case .frame:
			elements.append(shape("Frame", bounds: bounds.insetBy(dx: -55, dy: -45), stroke: .ivory90, strokeWidth: 5, identifiers: identifiers))
		case let .doubleBarDark(wide):
			let panelBounds = wide ? rect(105, 370, 1710, 340) : rect(145, 205, 1630, 670)
			elements.append(shape("Accent", bounds: rect(panelBounds.minX, panelBounds.minY - 12, panelBounds.width, 12), fill: .aqua, identifiers: identifiers))
			elements.append(shape("Bar", bounds: panelBounds, fill: .ink82, identifiers: identifiers))
		case let .doubleBarLight(wide):
			let panelBounds = wide ? rect(105, 370, 1710, 340) : rect(145, 205, 1630, 670)
			elements.append(shape("Accent", bounds: rect(panelBounds.minX, panelBounds.minY - 12, panelBounds.width, 12), fill: .amber, identifiers: identifiers))
			elements.append(shape("Bar", bounds: panelBounds, fill: .ivory92, identifiers: identifiers))
		case let .darkBox(opacity):
			elements.append(shape("Box", bounds: bounds.insetBy(dx: -55, dy: -45), fill: .ink.withAlpha(opacity), identifiers: identifiers))
		case .lightBox:
			elements.append(shape("Box", bounds: bounds.insetBy(dx: -55, dy: -45), fill: .ivory92, identifiers: identifiers))
		}
		return try template(name, identifiers: identifiers, elements: elements)
	}

	private static func makeCreativeWorshipTemplates(
		identifiers: IdentifierFactory,
	) throws -> [Rv_Data_Template.Slide] {
		let lyrics = "Mercy found me\ngrace will lead me home"
		let extended = "Mercy found me and grace will lead me home"
		let phrase = "THIS IS OUR FREEDOM SONG"

		return try [
			template("Line Borders", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(220, 280, 1480, 500), font: "AvenirNext-Bold", size: 78, alignment: .center, lineHeight: 1.2, shadow: true, identifiers: identifiers),
				shape("Top Line", bounds: rect(220, 220, 1480, 8), fill: .aqua, identifiers: identifiers),
				shape("Bottom Line", bounds: rect(220, 832, 1480, 8), fill: .aqua, identifiers: identifiers),
			]),
			template("Line Borders Tall", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(280, 180, 1360, 700), font: "AvenirNext-Heavy", size: 88, alignment: .center, lineHeight: 1.2, shadow: true, identifiers: identifiers),
				shape("Left Line", bounds: rect(215, 135, 8, 790), fill: .amber, identifiers: identifiers),
				shape("Right Line", bounds: rect(1697, 135, 8, 790), fill: .amber, identifiers: identifiers),
			]),
			template("Extended Line Borders", identifiers: identifiers, elements: [
				text("Lyrics", content: extended, bounds: rect(170, 415, 1580, 220), font: "AvenirNext-Bold", size: 57, alignment: .center, shadow: true, identifiers: identifiers),
				shape("Top Line", bounds: rect(140, 355, 1640, 7), fill: .ivory90, identifiers: identifiers),
				shape("Bottom Line", bounds: rect(140, 698, 1640, 7), fill: .ivory90, identifiers: identifiers),
			]),
			template("Short Line", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(260, 270, 1400, 510), font: "AvenirNext-Bold", size: 80, alignment: .center, lineHeight: 1.2, shadow: true, identifiers: identifiers),
				shape("Line", bounds: rect(760, 805, 400, 10), fill: .aqua, identifiers: identifiers),
			]),
			template("Middle Line", identifiers: identifiers, elements: [
				text("Lyrics", content: "Mercy found me\n\ngrace will lead me home", bounds: rect(250, 220, 1420, 620), font: "AvenirNext-Bold", size: 70, alignment: .center, lineHeight: 1.05, shadow: true, identifiers: identifiers),
				shape("Line", bounds: rect(650, 528, 620, 9), fill: .amber, identifiers: identifiers),
			]),
			template("Left Line", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(300, 260, 1320, 540), font: "AvenirNext-Heavy", size: 82, alignment: .left, lineHeight: 1.2, shadow: true, identifiers: identifiers),
				shape("Line", bounds: rect(220, 275, 13, 510), fill: .aqua, identifiers: identifiers),
			]),
			template("Short Translucent Bar", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(320, 330, 1280, 400), font: "AvenirNext-Bold", size: 73, alignment: .center, lineHeight: 1.2, identifiers: identifiers),
				shape("Bar", bounds: rect(260, 285, 1400, 490), fill: .ink60, identifiers: identifiers),
			]),
			template("Translucent Circle", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(475, 300, 970, 460), font: "AvenirNext-Bold", size: 67, alignment: .center, lineHeight: 1.2, identifiers: identifiers),
				shape("Circle", bounds: rect(385, 105, 1150, 850), fill: .ink60, kind: .ellipse, identifiers: identifiers),
			]),
			template("Translucent Vertical Bar", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(250, 170, 720, 720), font: "AvenirNext-Bold", size: 67, alignment: .left, lineHeight: 1.2, identifiers: identifiers),
				shape("Bar", bounds: rect(150, 80, 920, 900), fill: .ink60, identifiers: identifiers),
			]),
			template("Translucent Diamond", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(430, 300, 1060, 460), font: "AvenirNext-Bold", size: 66, alignment: .center, lineHeight: 1.2, identifiers: identifiers),
				shape("Diamond", bounds: rect(515, 135, 890, 790), fill: .ink60, rotation: 45, identifiers: identifiers),
			]),
			template("Translucent Wide Bar", identifiers: identifiers, elements: [
				text("Lyrics", content: extended, bounds: rect(130, 425, 1660, 210), font: "AvenirNext-Bold", size: 55, alignment: .center, identifiers: identifiers),
				shape("Bar", bounds: rect(70, 365, 1780, 330), fill: .ink60, identifiers: identifiers),
			]),
			template("Translucent Large Box", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(260, 245, 1400, 570), font: "AvenirNext-Heavy", size: 85, alignment: .center, lineHeight: 1.2, identifiers: identifiers),
				shape("Box", bounds: rect(170, 145, 1580, 770), fill: .ink60, identifiers: identifiers),
			]),
			template("Translucent Stroke Bar", identifiers: identifiers, elements: [
				text("Lyrics", content: extended, bounds: rect(155, 425, 1610, 210), font: "AvenirNext-Bold", size: 54, alignment: .center, identifiers: identifiers),
				shape("Bar", bounds: rect(105, 370, 1710, 320), fill: .ink60, stroke: .aqua, strokeWidth: 5, identifiers: identifiers),
			]),
			template("Translucent Stroke Diamond", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(445, 305, 1030, 450), font: "AvenirNext-Bold", size: 65, alignment: .center, lineHeight: 1.2, identifiers: identifiers),
				shape("Diamond", bounds: rect(520, 145, 880, 770), fill: .ink60, stroke: .amber, strokeWidth: 5, rotation: 45, identifiers: identifiers),
			]),
			template("Line Frame", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(280, 275, 1360, 510), font: "AvenirNext-Bold", size: 79, alignment: .center, lineHeight: 1.2, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(210, 205, 1500, 650), stroke: .ivory90, strokeWidth: 5, identifiers: identifiers),
			]),
			template("Line Frame Large", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(220, 200, 1480, 660), font: "AvenirNext-Heavy", size: 92, alignment: .center, lineHeight: 1.2, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(140, 120, 1640, 820), stroke: .ivory90, strokeWidth: 5, identifiers: identifiers),
			]),
			template("Line Frame Wide", identifiers: identifiers, elements: [
				text("Lyrics", content: extended, bounds: rect(170, 425, 1580, 210), font: "AvenirNext-Bold", size: 56, alignment: .center, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(105, 355, 1710, 350), stroke: .ivory90, strokeWidth: 5, identifiers: identifiers),
			]),
			template("Top Bar", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(200, 130, 1520, 300), font: "AvenirNext-Bold", size: 70, alignment: .center, lineHeight: 1.2, identifiers: identifiers),
				shape("Bar", bounds: rect(115, 70, 1690, 420), fill: .ink72, identifiers: identifiers),
			]),
			template("Top Bar CAPS", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics.uppercased(), bounds: rect(200, 130, 1520, 300), font: "AvenirNext-Bold", size: 63, alignment: .center, tracking: 2, lineHeight: 1.2, identifiers: identifiers),
				shape("Bar", bounds: rect(115, 70, 1690, 420), fill: .ink72, identifiers: identifiers),
			]),
			template("Top", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(210, 100, 1500, 360), font: "AvenirNext-Heavy", size: 79, alignment: .center, lineHeight: 1.2, shadow: true, identifiers: identifiers),
			]),
			template("White Translucent Circle", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(475, 300, 970, 460), font: "AvenirNext-Bold", size: 67, color: .ink, alignment: .center, lineHeight: 1.2, identifiers: identifiers),
				shape("Circle", bounds: rect(385, 105, 1150, 850), fill: .ivory85, kind: .ellipse, identifiers: identifiers),
			]),
			template("Narrow Line Frame", identifiers: identifiers, elements: [
				text("Lyrics", content: lyrics, bounds: rect(565, 210, 790, 640), font: "AvenirNext-Bold", size: 64, alignment: .center, lineHeight: 1.2, shadow: true, identifiers: identifiers),
				shape("Frame", bounds: rect(500, 145, 920, 770), stroke: .ivory90, strokeWidth: 5, identifiers: identifiers),
			]),
			template("Single Word Light", identifiers: identifiers, elements: [
				text("Lyrics", content: "WONDER", bounds: rect(185, 350, 1550, 360), font: "AvenirNext-Heavy", size: 178, color: .ink, alignment: .center, tracking: 5, identifiers: identifiers),
				shape("Bar", bounds: rect(105, 315, 1710, 430), fill: .ivory92, identifiers: identifiers),
			]),
			template("Single Word Dark", identifiers: identifiers, elements: [
				text("Lyrics", content: "WONDER", bounds: rect(185, 350, 1550, 360), font: "AvenirNext-Heavy", size: 178, alignment: .center, tracking: 5, identifiers: identifiers),
				shape("Bar", bounds: rect(105, 315, 1710, 430), fill: .ink82, identifiers: identifiers),
			]),
			linkedPhraseTemplate("Single Phrase Fade", content: phrase, treatment: .fade, identifiers: identifiers),
			linkedPhraseTemplate("Single Phrase Emphasis", content: phrase, treatment: .emphasis, identifiers: identifiers),
			linkedPhraseTemplate("Single Phrase Outline", content: phrase, treatment: .outline, identifiers: identifiers),
		]
	}

	private enum LinkedPhraseTreatment {
		case fade
		case emphasis
		case outline
	}

	private static func linkedPhraseTemplate(
		_ name: String,
		content: String,
		treatment: LinkedPhraseTreatment,
		identifiers: IdentifierFactory,
	) throws -> Rv_Data_Template.Slide {
		let main = try text(
			"Lyrics",
			content: content,
			bounds: rect(110, 435, 1700, 190),
			font: "AvenirNext-Heavy",
			size: 91,
			alignment: .center,
			tracking: 2,
			shadow: true,
			identifiers: identifiers,
		)
		var elements = [main]
		switch treatment {
		case .fade:
			let layers: [(String, Double, CGFloat)] = [
				("Echo Top 3", 85, 0.12), ("Echo Top 2", 180, 0.2), ("Echo Top 1", 275, 0.3),
				("Echo Bottom 1", 595, 0.3), ("Echo Bottom 2", 690, 0.2), ("Echo Bottom 3", 785, 0.12),
			]
			for (layerName, y, alpha) in layers {
				var echo = try text(layerName, content: content, bounds: rect(110, y, 1700, 150), font: "AvenirNext-Medium", size: 61, color: .ivory.withAlpha(alpha), alignment: .center, tracking: 2, identifiers: identifiers)
				echo.dataLinks = [alternateTextLink(to: main.element)]
				elements.append(echo)
			}
		case .emphasis:
			var echo = try text("Background Lyrics", content: content, bounds: rect(-220, -60, 2360, 1160), font: "AvenirNext-HeavyItalic", size: 235, color: .aqua.withAlpha(0.16), alignment: .center, tracking: 1, identifiers: identifiers)
			echo.dataLinks = [alternateTextLink(to: main.element)]
			elements.append(echo)
		case .outline:
			let layers: [(String, Double)] = [
				("Outline Top 2", 105), ("Outline Top 1", 270),
				("Outline Bottom 1", 600), ("Outline Bottom 2", 765),
			]
			for (layerName, y) in layers {
				var echo = try text(
					layerName,
					content: content,
					bounds: rect(110, y, 1700, 160),
					font: "AvenirNext-Bold",
					size: 68,
					color: .clear,
					alignment: .center,
					tracking: 2,
					stroke: .ivory85,
					strokeWidth: 3,
					identifiers: identifiers,
				)
				echo.dataLinks = [alternateTextLink(to: main.element)]
				elements.append(echo)
			}
		}
		return try template(name, identifiers: identifiers, elements: elements)
	}

	private static func alternateTextLink(to element: Rv_Data_Graphics.Element) -> Rv_Data_Slide.Element.DataLink {
		var link = Rv_Data_Slide.Element.DataLink()
		link.alternateText.otherElementUuid = element.uuid
		link.alternateText.otherElementName = element.name
		return link
	}

	private static func template(
		_ name: String,
		identifiers: IdentifierFactory,
		elements: [Rv_Data_Slide.Element],
	) throws -> Rv_Data_Template.Slide {
		var template = Rv_Data_Template.Slide()
		template.name = name
		template.baseSlide.uuid = identifiers.next()
		template.baseSlide.size.width = canvasWidth
		template.baseSlide.size.height = canvasHeight
		template.baseSlide.drawsBackgroundColor = false
		template.baseSlide.backgroundColor = DesignColor.clear.protobuf
		template.baseSlide.elements = elements.enumerated().map { index, source in
			var element = source
			element.info = UInt32(index + 1)
			return element
		}
		return template
	}

	private static func text(
		_ name: String,
		content: String,
		bounds: CGRect,
		font fontName: String,
		size: CGFloat,
		color: DesignColor = .ivory,
		alignment: Rv_Data_Graphics.Text.Attributes.Paragraph.Alignment,
		tracking: CGFloat = 0,
		lineHeight: CGFloat = 1,
		stroke: DesignColor? = nil,
		strokeWidth: CGFloat = 0,
		shadow: Bool = false,
		identifiers: IdentifierFactory,
	) throws -> Rv_Data_Slide.Element {
		guard let font = NSFont(name: fontName, size: size) else {
			throw DesignSystemFixtureError.missingFont(fontName)
		}
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = appKitAlignment(alignment)
		paragraph.lineHeightMultiple = lineHeight
		var attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: color.appKit,
			.paragraphStyle: paragraph,
		]
		if tracking != 0 {
			attributes[.kern] = tracking
		}
		if let stroke, strokeWidth != 0 {
			attributes[.strokeColor] = stroke.appKit
			attributes[.strokeWidth] = strokeWidth
		}
		let attributed = NSAttributedString(string: content, attributes: attributes)
		let rtf = try attributed.data(
			from: NSRange(location: 0, length: attributed.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)

		var slideElement = shape(name, bounds: bounds, identifiers: identifiers)
		var element = slideElement.element
		element.text.rtfData = rtf
		element.text.verticalAlignment = .middle
		element.text.scaleBehavior = .scaleFontDown
		element.text.isSuperscriptStandardized = true
		element.text.margins.left = 10
		element.text.margins.right = 10
		element.text.margins.top = 10
		element.text.margins.bottom = 10
		element.text.attributes.font.name = font.fontName
		element.text.attributes.font.family = font.familyName ?? "Avenir Next"
		element.text.attributes.font.face = font.displayName ?? ""
		element.text.attributes.font.size = size
		element.text.attributes.font.bold = font.fontDescriptor.symbolicTraits.contains(.bold)
		element.text.attributes.font.italic = font.fontDescriptor.symbolicTraits.contains(.italic)
		element.text.attributes.textSolidFill = color.protobuf
		element.text.attributes.kerning = tracking
		element.text.attributes.paragraphStyle.alignment = alignment
		element.text.attributes.paragraphStyle.lineHeightMultiple = lineHeight
		if let stroke, strokeWidth != 0 {
			element.text.attributes.strokeColor = stroke.protobuf
			element.text.attributes.strokeWidth = strokeWidth
		}
		if shadow {
			element.text.shadow.enable = true
			element.text.shadow.angle = 180
			element.text.shadow.offset = 0
			element.text.shadow.radius = 20
			element.text.shadow.opacity = 0.35
			element.text.shadow.color = DesignColor.ink.protobuf
		}
		slideElement.element = element
		return slideElement
	}

	private static func shape(
		_ name: String,
		bounds: CGRect,
		fill: DesignColor? = nil,
		stroke: DesignColor? = nil,
		strokeWidth: Double = 0,
		kind: Rv_Data_Graphics.Path.Shape.TypeEnum = .rectangle,
		rotation: Double = 0,
		identifiers: IdentifierFactory,
	) -> Rv_Data_Slide.Element {
		var element = Rv_Data_Graphics.Element()
		element.uuid = identifiers.next()
		element.name = name
		element.opacity = 1
		element.rotation = rotation
		element.bounds.origin.x = bounds.origin.x
		element.bounds.origin.y = bounds.origin.y
		element.bounds.size.width = bounds.width
		element.bounds.size.height = bounds.height
		element.path.closed = true
		element.path.shape.type = kind
		if kind == .roundedRectangle {
			element.path.shape.roundedRectangle.roundness = 0.22
		}
		element.path.points = [(0.0, 0.0), (1, 0), (1, 1), (0, 1)].map { x, y in
			var point = Rv_Data_Graphics.Path.BezierPoint()
			point.point.x = x
			point.point.y = y
			point.q0 = point.point
			point.q1 = point.point
			return point
		}
		if let fill {
			element.fill.enable = true
			element.fill.color = fill.protobuf
		}
		if let stroke, strokeWidth > 0 {
			element.stroke.enable = true
			element.stroke.width = strokeWidth
			element.stroke.color = stroke.protobuf
		}
		var result = Rv_Data_Slide.Element()
		result.element = element
		return result
	}

	private static func writeTheme(
		_ groups: [ThemeGroup],
		to outputURL: URL,
		in temporaryDirectory: URL,
	) throws {
		let workspace = temporaryDirectory.appendingPathComponent("Theme Workspace", isDirectory: true)
		for group in groups {
			let themeURL = workspace.appendingPathComponent(group.relativePath)
			try FileManager.default.createDirectory(at: themeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			var theme = DocumentFactory.theme()
			theme.slides = group.templates
			try theme.serializedData().write(to: themeURL, options: .atomic)
		}
		_ = try DocumentArchive.bundle(workspace, to: outputURL, replace: true)
	}

	private static func install(_ sourceURL: URL, at destinationURL: URL) throws {
		let fileManager = FileManager.default
		try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		if fileManager.fileExists(atPath: destinationURL.path) {
			_ = try fileManager.replaceItemAt(destinationURL, withItemAt: sourceURL)
		} else {
			try fileManager.copyItem(at: sourceURL, to: destinationURL)
		}
	}

	private static func requireEquivalentTheme(at currentURL: URL, to expectedURL: URL) throws {
		guard FileManager.default.fileExists(atPath: currentURL.path) else {
			throw DesignSystemFixtureError.outOfDate(currentURL)
		}
		let current = try DocumentLoader.load(from: currentURL)
		let expected = try DocumentLoader.load(from: expectedURL)
		let currentEntries = try current.themeEntries.map { try ($0.relativePath, $0.document.serializedData()) }
		let expectedEntries = try expected.themeEntries.map { try ($0.relativePath, $0.document.serializedData()) }
		guard
			currentEntries.elementsEqual(expectedEntries, by: { $0.0 == $1.0 && $0.1 == $1.1 }),
			current.archiveEntries.sorted() == expected.archiveEntries.sorted(),
			current.embeddedAssetPaths.sorted() == expected.embeddedAssetPaths.sorted()
		else {
			throw DesignSystemFixtureError.outOfDate(currentURL)
		}
	}

	private static func appKitAlignment(
		_ alignment: Rv_Data_Graphics.Text.Attributes.Paragraph.Alignment,
	) -> NSTextAlignment {
		switch alignment {
		case .left: .left
		case .right: .right
		case .center: .center
		case .justified: .justified
		case .natural, .UNRECOGNIZED: .natural
		}
	}

	private static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
		CGRect(x: x, y: y, width: width, height: height)
	}
}

private struct ThemeGroup {
	var relativePath: String
	var templates: [Rv_Data_Template.Slide]
}

private final class IdentifierFactory {
	private var value: Int

	init(startingAt value: Int = 1) {
		self.value = value
	}

	func next() -> Rv_Data_UUID {
		defer { value += 1 }
		var identifier = Rv_Data_UUID()
		identifier.string = String(format: "50524344-4553-4000-8000-%012d", value)
		return identifier
	}
}

private struct DesignColor {
	var red: CGFloat
	var green: CGFloat
	var blue: CGFloat
	var alpha: CGFloat = 1

	static let aqua = hex(0x57D3C2)
	static let amber = hex(0xF5C451)
	static let clear = Self(red: 0, green: 0, blue: 0, alpha: 0)
	static let ink = hex(0x111721)
	static let ink60 = hex(0x111721, alpha: 0.6)
	static let ink72 = hex(0x111721, alpha: 0.72)
	static let ink82 = hex(0x111721, alpha: 0.82)
	static let ivory = hex(0xF7F4EC)
	static let ivory85 = hex(0xF7F4EC, alpha: 0.85)
	static let ivory90 = hex(0xF7F4EC, alpha: 0.9)
	static let ivory92 = hex(0xF7F4EC, alpha: 0.92)

	var appKit: NSColor {
		NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
	}

	var protobuf: Rv_Data_Color {
		var color = Rv_Data_Color()
		color.red = Float(red)
		color.green = Float(green)
		color.blue = Float(blue)
		color.alpha = Float(alpha)
		return color
	}

	func withAlpha(_ alpha: CGFloat) -> Self {
		Self(red: red, green: green, blue: blue, alpha: alpha)
	}

	private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> Self {
		Self(
			red: CGFloat((value >> 16) & 0xFF) / 255,
			green: CGFloat((value >> 8) & 0xFF) / 255,
			blue: CGFloat(value & 0xFF) / 255,
			alpha: alpha,
		)
	}
}

private enum DesignSystemFixtureError: Error, CustomStringConvertible {
	case missingFont(String)
	case outOfDate(URL)

	var description: String {
		switch self {
		case let .missingFont(name):
			"The required macOS font is unavailable: \(name)."
		case let .outOfDate(url):
			"Generated design-system asset is out of date: \(url.path). Run swift run FixtureGenerator generate-design-system."
		}
	}
}
