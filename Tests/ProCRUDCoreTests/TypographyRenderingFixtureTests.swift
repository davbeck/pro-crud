import AppKit
import Foundation
import ProCRUDCore
import ProPresenterProto
import SnapshotTesting
import Testing

@Suite(
	"System Typography",
	.snapshots(diffTool: .ksdiff),
	.timeLimit(.minutes(1)),
)
struct TypographyRenderingFixtureTests {
	private let expectedCueNames = [
		"Avenir Next Faces",
		"Avenir Next Kerning",
		"Avenir Next Ligatures",
		"Backslant and Italic",
		"Menlo Spacing",
		"Emoji and Mixed Typography",
	]

	@Test("System font and RTF feature coverage")
	func rendersTypographySlides() throws {
		let document = try PresentationLoader.load(
			from: fixtureURL("ProPresenter/Typography/Typography.probundle"),
		)
		let cues = document.orderedCues
		#expect(cues.map(\.name) == expectedCueNames)

		for (index, cue) in cues.enumerated() {
			let attributedText = try attributedText(in: cue)
			switch cue.name {
			case "Avenir Next Faces":
				try assertFonts(
					[
						"AvenirNext-Regular",
						"AvenirNext-DemiBold",
						"AvenirNext-Heavy",
						"AvenirNextCondensed-Heavy",
					],
					in: attributedText,
				)

			case "Avenir Next Kerning":
				try assertFonts(["AvenirNext-Regular", "AvenirNext-DemiBold"], in: attributedText)
				let kernValues = numericAttributeValues(.kern, in: attributedText, defaultValue: 0)
				#expect(kernValues.contains(where: { abs($0 + 2) < 0.001 }))
				#expect(kernValues.contains(where: { abs($0) < 0.001 }))
				#expect(kernValues.contains(where: { abs($0 - 5) < 0.001 }))

			case "Avenir Next Ligatures":
				try assertFonts(["AvenirNext-Regular", "AvenirNext-DemiBold"], in: attributedText)
				#expect(attributedText.string.localizedCaseInsensitiveContains("office affinity fi fl ffi ffl"))
				let ligatureValues = numericAttributeValues(.ligature, in: attributedText, defaultValue: 1)
				#expect(ligatureValues.contains(0))
				#expect(ligatureValues.contains(where: { $0 > 0 }))

			case "Backslant and Italic":
				try assertFonts(
					["AvenirNext-DemiBold", "AvenirNext-Heavy", "AvenirNext-HeavyItalic"],
					in: attributedText,
				)
				let obliquenessValues = explicitNumericAttributeValues(.obliqueness, in: attributedText)
				#expect(obliquenessValues.contains(where: { abs($0 + 0.20) < 0.001 }))

			case "Menlo Spacing":
				try assertFonts(["AvenirNext-DemiBold", "Menlo-Regular"], in: attributedText)
				#expect(attributedText.string.contains("\t"))
				#expect(numericAttributeValues(.kern, in: attributedText, defaultValue: 0).contains(where: { $0 != 0 }))
				let paragraphs = paragraphStyles(in: attributedText)
				#expect(paragraphs.contains { $0.lineSpacing > 0 })
				#expect(paragraphs.contains { $0.tabStops.contains(where: { $0.location > 0 }) })

			case "Emoji and Mixed Typography":
				try assertFonts(
					["AvenirNext-Regular", "AvenirNext-DemiBold", "AvenirNext-HeavyItalic", "AppleColorEmoji"],
					in: attributedText,
				)
				#expect(attributedText.string.contains("🎉"))
				#expect(attributedText.string.contains("👩🏽‍💻"))
				#expect(paragraphStyles(in: attributedText).contains {
					$0.paragraphSpacing > 0 || $0.paragraphSpacingBefore > 0
				})

			default:
				Issue.record("Unexpected typography cue \(cue.name)")
			}

			let bitmap = try PresentationRenderer(document: document).render(cue: cue)
			#expect(bitmap.pixelsWide == 854)
			#expect(bitmap.pixelsHigh == 480)
			let rendered = NSImage(size: bitmap.size)
			rendered.addRepresentation(bitmap)
			assertSnapshot(
				of: rendered,
				as: .proCRUDImage(precision: 0.99, perceptualPrecision: 0.99),
				named: "slide-\(index + 1)",
				testName: "rendersTypographySlide",
			)
		}
	}

	private func attributedText(in cue: Rv_Data_Cue) throws -> NSAttributedString {
		let rtfData = cue.actions
			.filter { $0.type == .presentationSlide }
			.map(\.slide.presentation.baseSlide)
			.flatMap(\.elements)
			.map(\.element.text.rtfData)
			.filter { !$0.isEmpty }
		#expect(rtfData.count == 1)
		let data = try #require(rtfData.first)
		return try NSAttributedString(
			data: data,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		)
	}

	private func assertFonts(_ expectedNames: [String], in attributedText: NSAttributedString) throws {
		for name in expectedNames {
			_ = try #require(NSFont(name: name, size: 12))
		}

		var actualNames = Set<String>()
		attributedText.enumerateAttribute(.font, in: fullRange(of: attributedText)) { value, _, _ in
			guard let font = value as? NSFont else { return }
			actualNames.insert(font.fontName)
		}
		#expect(Set(expectedNames).isSubset(of: actualNames))
	}

	private func numericAttributeValues(
		_ key: NSAttributedString.Key,
		in attributedText: NSAttributedString,
		defaultValue: Double,
	) -> [Double] {
		var values: [Double] = []
		attributedText.enumerateAttributes(in: fullRange(of: attributedText)) { attributes, _, _ in
			values.append((attributes[key] as? NSNumber)?.doubleValue ?? defaultValue)
		}
		return values
	}

	private func explicitNumericAttributeValues(_ key: NSAttributedString.Key, in attributedText: NSAttributedString) -> [Double] {
		var values: [Double] = []
		attributedText.enumerateAttribute(key, in: fullRange(of: attributedText)) { value, _, _ in
			guard let value = value as? NSNumber else { return }
			values.append(value.doubleValue)
		}
		return values
	}

	private func paragraphStyles(in attributedText: NSAttributedString) -> [NSParagraphStyle] {
		var styles: [NSParagraphStyle] = []
		attributedText.enumerateAttribute(.paragraphStyle, in: fullRange(of: attributedText)) { value, _, _ in
			guard let style = value as? NSParagraphStyle else { return }
			styles.append(style)
		}
		return styles
	}

	private func fullRange(of attributedText: NSAttributedString) -> NSRange {
		NSRange(location: 0, length: attributedText.length)
	}
}
