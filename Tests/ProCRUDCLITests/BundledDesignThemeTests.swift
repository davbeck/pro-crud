import AppKit
import CustomDump
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite("Bundled design theme", .timeLimit(.minutes(1)))
struct BundledDesignThemeTests {
	private let templateGroups: [(path: String, names: [String])] = [
		(
			path: "ProCRUD - Streaming/Theme",
			names: [
				"Bold",
				"Bold CAPS",
				"Bold Extended",
				"Bold Extended CAPS",
				"Dark Wide Bar",
				"Dark Wide Bar CAPS",
				"Line Frame",
				"Single Phrase Line Frame",
				"Light Bar",
				"Dark Bar",
				"Double Bar Light",
				"Double Bar Dark",
				"Name Heavy",
				"Name Light Bar",
				"Name Line Frame",
				"Scripture",
				"Scripture Bar",
				"Scripture Center",
				"Scripture Extended",
				"Scripture Extended Bar",
				"Scripture Center Extended",
				"Point Line Frame",
				"Point Bold",
				"Point Light Bar",
			],
		),
		(
			path: "ProCRUD - Teaching/Theme",
			names: [
				"Title Heavy",
				"Title Bars Single",
				"Title Bars Triple Dark",
				"Title Box Double",
				"Title Line Frame",
				"Title Bars Triple Light",
				"Name Heavy",
				"Name Bars",
				"Name Line Frame",
				"Scripture Bar",
				"Scripture Bar Center",
				"Scripture Bar Bottom",
				"Scripture Bar Bottom Center",
				"Scripture",
				"Scripture Frame",
				"Point Line Frame",
				"Point",
				"Point Light Box",
				"List",
				"List Bar",
				"Quote",
				"Quote Center",
				"Quote Light Bar",
				"Quote Light Bar Center",
			],
		),
		(
			path: "ProCRUD - Worship 1/Theme",
			names: [
				"Medium",
				"Bold",
				"Heavy",
				"Medium Zoom",
				"Bold Zoom",
				"Heavy Zoom",
				"Medium CAPS",
				"Bold CAPS",
				"Heavy CAPS",
				"Medium Zoom CAPS",
				"Bold Zoom CAPS",
				"Heavy Zoom CAPS",
				"Bold Extended",
				"Bold Extended CAPS",
				"Extended Line Frame",
				"Line Frame",
				"Line Frame Zoom",
				"Double Bar Dark Wide",
				"Double Bar Dark",
				"Double Bar Light",
				"Double Bar Light Wide",
				"Dark Box",
				"Dark Translucent Box",
				"Light Box",
			],
		),
		(
			path: "ProCRUD - Worship 2/Theme",
			names: [
				"Line Borders",
				"Line Borders Tall",
				"Extended Line Borders",
				"Short Line",
				"Middle Line",
				"Left Line",
				"Short Translucent Bar",
				"Translucent Circle",
				"Translucent Vertical Bar",
				"Translucent Diamond",
				"Translucent Wide Bar",
				"Translucent Large Box",
				"Translucent Stroke Bar",
				"Translucent Stroke Diamond",
				"Line Frame",
				"Line Frame Large",
				"Line Frame Wide",
				"Top Bar",
				"Top Bar CAPS",
				"Top",
				"White Translucent Circle",
				"Narrow Line Frame",
				"Single Word Light",
				"Single Word Dark",
				"Single Phrase Fade",
				"Single Phrase Emphasis",
				"Single Phrase Outline",
			],
		),
	]

	private let allowedFontNames: Set<String> = [
		"AvenirNext-Medium",
		"AvenirNext-DemiBold",
		"AvenirNext-Bold",
		"AvenirNext-Heavy",
		"AvenirNext-HeavyItalic",
	]

	@Test
	func themeContainsEveryGroupedVariation() throws {
		try withBundledDesignTheme { themeURL in
			let document = try DocumentLoader.load(from: themeURL)
			#expect(document.kind == .theme)
			#expect(document.embeddedAssetPaths.isEmpty)
			expectNoDifference(document.themeEntries.map(\.relativePath), templateGroups.map(\.path))
			#expect(document.themeEntries.count == 4)

			for (entry, expected) in zip(document.themeEntries, templateGroups) {
				expectNoDifference(entry.document.slides.map(\.name), expected.names)
			}

			let templates = try ThemeTemplateSource.candidates(from: themeURL)
			#expect(templates.count == 99)
			for group in templateGroups {
				let groupTemplates = templates.filter { $0.themeDocumentPath == group.path }
				expectNoDifference(groupTemplates.map(\.name), group.names)
			}
		}
	}

	@Test
	func duplicateNamesRequireAThemeDocument() throws {
		try withBundledDesignTheme { themeURL in
			let candidates = try ThemeTemplateSource.candidates(from: themeURL)
			#expect(throws: ThemeTemplateSourceError.self) {
				try ThemeTemplateSource.select(candidates, named: "Bold")
			}
			let selected = try qualifiedTemplate(
				in: themeURL,
				document: "ProCRUD - Worship 1/Theme",
				name: "Bold",
			)
			#expect(selected.name == "Bold")
			#expect(selected.themeDocumentPath == "ProCRUD - Worship 1/Theme")
		}
	}

	@Test
	func templatesAreTransparentAndContainNoMedia() throws {
		try withBundledDesignTheme { themeURL in
			let templates = try ThemeTemplateSource.candidates(from: themeURL)
			for template in templates {
				let slide = template.slide.baseSlide
				#expect(slide.size.width == 1920)
				#expect(slide.size.height == 1080)
				#expect(!slide.drawsBackgroundColor)
				#expect(slide.backgroundColor.alpha == 0)
				#expect(!slide.elements.contains { hasMediaFill($0.element) })
				#expect(!template.slide.actions.contains(where: containsMediaAction))
				#expect(ThemeTemplateSource.mediaReferences(in: template.slide).isEmpty)
				if template.themeDocumentPath == "ProCRUD - Streaming/Theme" {
					#expect(!slide.elements.contains { element in
						element.element.bounds.origin.x == 0
							&& element.element.bounds.origin.y == 0
							&& element.element.bounds.size.width == 1920
							&& element.element.bounds.size.height == 1080
					})
				}
			}
		}
	}

	@Test
	func textSlotsUseMeaningfulSamplesAndResolvableAvenirFonts() throws {
		try withBundledDesignTheme { themeURL in
			let templates = try ThemeTemplateSource.candidates(from: themeURL)
			var metadataFontNames = Set<String>()
			var rtfFontNames = Set<String>()
			var textElementCount = 0
			var decorationCount = 0

			for template in templates {
				for slideElement in template.slide.baseSlide.elements {
					let element = slideElement.element
					guard element.hasText else {
						decorationCount += 1
						#expect(element.hasPath)
						#expect([
							Rv_Data_Graphics.Path.Shape.TypeEnum.rectangle,
							.roundedRectangle,
							.ellipse,
						].contains(element.path.shape.type))
						continue
					}

					textElementCount += 1
					let text = element.text
					let attributed = try attributedString(from: text)
					#expect(!attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

					let metadataFontName = text.attributes.font.name
					metadataFontNames.insert(metadataFontName)
					#expect(allowedFontNames.contains(metadataFontName))
					#expect(!metadataFontName.localizedCaseInsensitiveContains("CMGSans"))
					#expect(NSFont(name: metadataFontName, size: text.attributes.font.size) != nil)

					var fonts: [NSFont] = []
					attributed.enumerateAttribute(
						.font,
						in: NSRange(location: 0, length: attributed.length),
					) { value, _, _ in
						if let font = value as? NSFont {
							fonts.append(font)
						}
					}
					#expect(!fonts.isEmpty)
					for font in fonts {
						rtfFontNames.insert(font.fontName)
						#expect(allowedFontNames.contains(font.fontName))
						#expect(!font.fontName.localizedCaseInsensitiveContains("CMGSans"))
						#expect(NSFont(name: font.fontName, size: font.pointSize) != nil)
					}
				}
			}

			#expect(textElementCount > 0)
			#expect(decorationCount > 0)
			#expect(!metadataFontNames.isEmpty)
			#expect(!rtfFontNames.isEmpty)
			#expect(metadataFontNames.isSubset(of: allowedFontNames))
			#expect(rtfFontNames.isSubset(of: allowedFontNames))
		}
	}

	@Test
	func outlineVariationUsesARealAvenirStroke() throws {
		try withBundledDesignTheme { themeURL in
			let template = try qualifiedTemplate(
				in: themeURL,
				document: "ProCRUD - Worship 2/Theme",
				name: "Single Phrase Outline",
			)
			let textElements = template.slide.baseSlide.elements
				.map(\.element)
				.filter(\.hasText)
			#expect(!textElements.isEmpty)

			var outlinedRunCount = 0
			for element in textElements {
				let attributed = try attributedString(from: element.text)
				attributed.enumerateAttributes(
					in: NSRange(location: 0, length: attributed.length),
				) { attributes, _, _ in
					guard let strokeWidth = attributes[.strokeWidth] as? NSNumber,
					      abs(strokeWidth.doubleValue) > 0,
					      let strokeColor = attributes[.strokeColor] as? NSColor,
					      strokeColor.alphaComponent > 0,
					      let font = attributes[.font] as? NSFont
					else {
						return
					}
					outlinedRunCount += 1
					#expect(allowedFontNames.contains(font.fontName))
					#expect(!font.fontName.localizedCaseInsensitiveContains("CMGSans"))
				}
			}
			#expect(outlinedRunCount > 0)
		}
	}

	@Test
	func linkedPhraseVariationsResolveLyricsThroughCompleteIntraSlideLinks() throws {
		try withBundledDesignTheme { themeURL in
			let expectations: [(name: String, linkCount: Int)] = [
				("Single Phrase Fade", 6),
				("Single Phrase Emphasis", 1),
				("Single Phrase Outline", 4),
			]

			for expectation in expectations {
				let template = try qualifiedTemplate(
					in: themeURL,
					document: "ProCRUD - Worship 2/Theme",
					name: expectation.name,
				)
				let templateSlide = template.slide.baseSlide
				let identifiers = templateSlide.elements.map(\.element.uuid.string)
				#expect(identifiers.allSatisfy { !$0.isEmpty })
				#expect(Set(identifiers).count == identifiers.count)

				let primary = try #require(templateSlide.elements.first { $0.element.name == "Lyrics" })
				let templateLinkCount = templateSlide.elements.reduce(0) { $0 + $1.dataLinks.count }
				let templateLinks = alternateTextLinks(in: templateSlide)
				#expect(templateLinkCount == expectation.linkCount)
				#expect(templateLinks.count == expectation.linkCount)
				for link in templateLinks {
					#expect(link.source.uuid != primary.element.uuid)
					#expect(link.target.otherElementUuid.string == primary.element.uuid.string)
					#expect(link.target.otherElementName == primary.element.name)
				}

				let source = try sourceSlide(fields: [
					(name: "Lyrics", content: "This is our freedom song"),
				])
				let result = try TemplateResolver.resolve(
					template: template.slide,
					source: source,
					destinationSize: CGSize(width: 1920, height: 1080),
					mode: .applyExisting,
				)
				let resolvedPrimary = try #require(result.slide.elements.first { $0.element.name == "Lyrics" })
				#expect(resolvedPrimary.element.uuid.string == "SOURCE-TEXT-0")
				#expect(try attributedString(from: resolvedPrimary.element.text).string == "This is our freedom song")
				#expect(result.report.assignments.count == 1)
				#expect(result.report.assignments.first?.reason == "exact-name")
				#expect(result.report.assignments.first?.template.name == "Lyrics")

				let resolvedLinkCount = result.slide.elements.reduce(0) { $0 + $1.dataLinks.count }
				let resolvedLinks = alternateTextLinks(in: result.slide)
				#expect(resolvedLinkCount == expectation.linkCount)
				#expect(resolvedLinks.count == expectation.linkCount)
				for link in resolvedLinks {
					#expect(link.target.otherElementUuid.string == resolvedPrimary.element.uuid.string)
					#expect(link.target.otherElementName == resolvedPrimary.element.name)
				}
			}
		}
	}

	@Test
	func unboxedStreamingAndTeachingTextUsesTheStandardContrastShadow() throws {
		try withBundledDesignTheme { themeURL in
			let shadowedElements = [
				(document: "ProCRUD - Streaming/Theme", template: "Bold", element: "Lyrics"),
				(document: "ProCRUD - Streaming/Theme", template: "Scripture", element: "Bible Text"),
				(document: "ProCRUD - Streaming/Theme", template: "Point Bold", element: "Teaching Point"),
				(document: "ProCRUD - Teaching/Theme", template: "Title Heavy", element: "Title"),
				(document: "ProCRUD - Teaching/Theme", template: "Scripture", element: "Bible Text"),
				(document: "ProCRUD - Teaching/Theme", template: "Quote", element: "Quote"),
			]
			for expected in shadowedElements {
				let template = try qualifiedTemplate(
					in: themeURL,
					document: expected.document,
					name: expected.template,
				)
				let element = try #require(template.slide.baseSlide.elements.first {
					$0.element.name == expected.element
				})
				let shadow = element.element.text.shadow
				#expect(shadow.enable)
				#expect(abs(Double(shadow.opacity) - 0.35) < 0.000_001)
				#expect(abs(Double(shadow.radius) - 20) < 0.000_001)
				#expect(shadow.color.alpha == 1)
			}

			let panelElements = [
				(document: "ProCRUD - Streaming/Theme", template: "Dark Bar", element: "Lyrics"),
				(document: "ProCRUD - Teaching/Theme", template: "Quote Light Bar", element: "Quote"),
			]
			for expected in panelElements {
				let template = try qualifiedTemplate(
					in: themeURL,
					document: expected.document,
					name: expected.template,
				)
				let element = try #require(template.slide.baseSlide.elements.first {
					$0.element.name == expected.element
				})
				#expect(!element.element.text.shadow.enable)
			}
		}
	}

	@Test
	func populatedRepresentativeVariationFromEachGroupRendersVisibleContent() throws {
		try withBundledDesignTheme { themeURL in
			let representatives = [
				(
					document: "ProCRUD - Streaming/Theme",
					name: "Bold",
					fields: [(name: "Lyrics", content: "Mercy found me\nand grace will lead me home")],
				),
				(
					document: "ProCRUD - Teaching/Theme",
					name: "Title Heavy",
					fields: [
						(name: "Title", content: "Practicing Presence"),
						(name: "Subtitle", content: "A life attentive to grace"),
					],
				),
				(
					document: "ProCRUD - Worship 1/Theme",
					name: "Medium",
					fields: [(name: "Lyrics", content: "Mercy found me\nand grace will lead me home")],
				),
				(
					document: "ProCRUD - Worship 2/Theme",
					name: "Line Borders",
					fields: [(name: "Lyrics", content: "Mercy found me\nand grace will lead me home")],
				),
			]

			for representative in representatives {
				let template = try qualifiedTemplate(
					in: themeURL,
					document: representative.document,
					name: representative.name,
				)
				let source = try sourceSlide(fields: representative.fields)
				let resolution = try TemplateResolver.resolve(
					template: template.slide,
					source: source,
					destinationSize: CGSize(width: 1920, height: 1080),
					mode: .applyExisting,
				)
				#expect(resolution.report.assignments.count == representative.fields.count)
				for field in representative.fields {
					let populated = try #require(resolution.slide.elements.first {
						$0.element.name == field.name
					})
					#expect(try attributedString(from: populated.element.text).string == field.content)
				}

				var presentation = DocumentFactory.presentation(name: representative.name)
				presentation.cues[0].actions[0].slide.presentation.baseSlide = resolution.slide
				let bitmap = try PresentationRenderer(
					document: PresentationDocument(presentation: presentation),
				).render(cue: presentation.cues[0])
				#expect(bitmap.pixelsWide == 1920)
				#expect(bitmap.pixelsHigh == 1080)
				let bytes = try #require(bitmap.bitmapData)
				let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
				#expect(UnsafeBufferPointer(start: bytes, count: byteCount).contains { $0 != 0 })
			}
		}
	}

	@Test
	func themeExercisesTheBroadRenderingFeatureMatrix() throws {
		try withBundledDesignTheme { themeURL in
			let templates = try ThemeTemplateSource.candidates(from: themeURL)
			let slideElements = templates.flatMap(\.slide.baseSlide.elements)
			let elements = slideElements.map(\.element)
			let textElements = elements.filter(\.hasText)

			expectNoDifference(Set(textElements.map(\.text.attributes.font.name)), allowedFontNames)
			#expect(textElements.contains { $0.text.attributes.kerning > 0 })
			#expect(textElements.contains { $0.text.attributes.paragraphStyle.lineHeightMultiple != 1 })
			#expect(textElements.contains { $0.text.shadow.enable })
			#expect(elements.contains { $0.fill.enable && $0.fill.color.alpha > 0 && $0.fill.color.alpha < 1 })
			#expect(elements.contains { $0.stroke.enable && $0.stroke.width > 0 })
			#expect(elements.contains { $0.rotation != 0 })
			#expect(elements.contains { $0.path.shape.type == .ellipse })
			#expect(slideElements.contains { !$0.dataLinks.isEmpty })

			var hasOutlinedRTF = false
			for element in textElements {
				let attributed = try attributedString(from: element.text)
				attributed.enumerateAttribute(
					.strokeWidth,
					in: NSRange(location: 0, length: attributed.length),
				) { value, _, stop in
					guard let width = value as? NSNumber, width.doubleValue != 0 else { return }
					hasOutlinedRTF = true
					stop.pointee = true
				}
				if hasOutlinedRTF {
					break
				}
			}
			#expect(hasOutlinedRTF)
		}
	}

	@Test
	func everyVariationRendersVisibleContentAtItsNativeSize() throws {
		try withBundledDesignTheme { themeURL in
			let templates = try ThemeTemplateSource.candidates(from: themeURL)
			expectNoDifference(templates.count, 99)

			for template in templates {
				var presentation = DocumentFactory.presentation(name: template.name)
				presentation.cues[0].actions[0].slide.presentation.baseSlide = template.slide.baseSlide
				let bitmap = try PresentationRenderer(
					document: PresentationDocument(presentation: presentation),
				).render(cue: presentation.cues[0])
				expectNoDifference(bitmap.pixelsWide, 1920)
				expectNoDifference(bitmap.pixelsHigh, 1080)
				let bytes = try #require(bitmap.bitmapData)
				let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
				#expect(UnsafeBufferPointer(start: bytes, count: byteCount).contains { $0 != 0 })
			}
		}
	}

	private func withBundledDesignTheme<Result>(
		_ operation: (URL) throws -> Result,
	) throws -> Result {
		let skill = try #require(CLIResources.agentSkills["pro-crud"])
		let theme = try #require(skill["assets/themes/ProCRUD Design System.proTheme"])
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("pro-crud-bundled-theme-tests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let themeURL = directory.appendingPathComponent("ProCRUD Design System.proTheme")
		try theme.write(to: themeURL, options: .atomic)
		return try operation(themeURL)
	}

	private func qualifiedTemplate(
		in themeURL: URL,
		document: String,
		name: String,
	) throws -> ThemeTemplateSource.Candidate {
		let candidates = try ThemeTemplateSource.candidates(from: themeURL, themeDocument: document)
		return try ThemeTemplateSource.select(candidates, named: name)
	}

	private func attributedString(from text: Rv_Data_Graphics.Text) throws -> NSAttributedString {
		try NSAttributedString(
			data: text.rtfData,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		)
	}

	private func alternateTextLinks(
		in slide: Rv_Data_Slide,
	) -> [(source: Rv_Data_Graphics.Element, target: Rv_Data_Slide.Element.DataLink.AlternateElementText)] {
		slide.elements.flatMap { slideElement in
			slideElement.dataLinks.compactMap { link in
				guard case let .alternateText(target)? = link.propertyType else { return nil }
				return (slideElement.element, target)
			}
		}
	}

	private func sourceSlide(fields: [(name: String, content: String)]) throws -> Rv_Data_Slide {
		let font = try #require(NSFont(name: "AvenirNext-Medium", size: 64))
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center
		paragraph.lineHeightMultiple = 1.2
		var slide = Rv_Data_Slide()
		slide.uuid.string = "SOURCE-SLIDE"
		slide.size.width = 1920
		slide.size.height = 1080
		slide.elements = try fields.enumerated().map { index, field in
			let attributed = NSAttributedString(
				string: field.content,
				attributes: [
					.font: font,
					.foregroundColor: NSColor.white,
					.paragraphStyle: paragraph,
				],
			)
			var element = Rv_Data_Graphics.Element()
			element.uuid.string = "SOURCE-TEXT-\(index)"
			element.name = field.name
			element.opacity = 1
			element.bounds.size.width = 1920
			element.bounds.size.height = 1080
			element.path.closed = true
			element.path.shape.type = .rectangle
			element.text.rtfData = try attributed.data(
				from: NSRange(location: 0, length: attributed.length),
				documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
			)
			element.text.attributes.font.name = font.fontName
			element.text.attributes.font.family = font.familyName ?? "Avenir Next"
			element.text.attributes.font.face = font.displayName ?? "Avenir Next Regular"
			element.text.attributes.font.size = font.pointSize
			element.text.attributes.paragraphStyle.alignment = .center
			element.text.attributes.paragraphStyle.lineHeightMultiple = 1.2
			element.text.attributes.textSolidFill.red = 1
			element.text.attributes.textSolidFill.green = 1
			element.text.attributes.textSolidFill.blue = 1
			element.text.attributes.textSolidFill.alpha = 1
			element.text.scaleBehavior = .scaleFontDown
			var slideElement = Rv_Data_Slide.Element()
			slideElement.element = element
			slideElement.info = UInt32(index + 1)
			return slideElement
		}
		return slide
	}

	private func hasMediaFill(_ element: Rv_Data_Graphics.Element) -> Bool {
		if case .media? = element.fill.fillType {
			return true
		}
		guard element.hasText else { return false }
		if case .mediaFill? = element.text.attributes.fill {
			return true
		}
		return element.text.attributes.customAttributes.contains {
			if case .mediaFill? = $0.attribute {
				true
			} else {
				false
			}
		}
	}

	private func containsMediaAction(_ action: Rv_Data_Action) -> Bool {
		switch action.type {
		case .media, .backgroundMedia, .foregroundMedia:
			true
		case .presentationSlide:
			action.slide.presentation.baseSlide.elements.contains { hasMediaFill($0.element) }
		case .propSlide:
			action.slide.prop.baseSlide.elements.contains { hasMediaFill($0.element) }
		default:
			false
		}
	}
}
