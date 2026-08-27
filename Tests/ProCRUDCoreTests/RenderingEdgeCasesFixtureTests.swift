import AppKit
import Foundation
import ProCRUDCore
import ProPresenterProto
import SnapshotTesting
import Testing

@Suite(
	"Rendering Edge Cases",
	.snapshots(diffTool: .ksdiff),
	.timeLimit(.minutes(1)),
)
struct RenderingEdgeCasesFixtureTests {
	private let expectedCueNames = [
		"Lists and Insets",
		"Line Mask Height Offsets",
		"Element Rotations and Clipping",
		"Alternate Text Links",
	]

	@Test("Focused replacement coverage")
	func rendersRenderingEdgeCasesSlides() throws {
		let document = try PresentationLoader.load(
			from: fixtureURL("ProPresenter/RenderingEdgeCases/RenderingEdgeCases.probundle"),
		)
		let cues = document.orderedCues
		#expect(cues.map(\.name) == expectedCueNames)

		for (index, cue) in cues.enumerated() {
			let slide = try #require(cue.actions.first(where: { $0.type == .presentationSlide })?.slide.presentation.baseSlide)
			switch cue.name {
			case "Lists and Insets":
				try assertListsAndInsets(in: slide)
			case "Line Mask Height Offsets":
				assertLineMaskHeightOffsets(in: slide)
			case "Element Rotations and Clipping":
				assertElementRotationsAndClipping(in: slide)
			case "Alternate Text Links":
				try assertAlternateTextLinks(in: slide)
			default:
				Issue.record("Unexpected rendering edge-case cue \(cue.name)")
			}

			let bitmap = try PresentationRenderer(document: document).render(cue: cue)
			#expect(bitmap.pixelsWide == 1920)
			#expect(bitmap.pixelsHigh == 1080)
			let rendered = NSImage(size: bitmap.size)
			rendered.addRepresentation(bitmap)
			if cue.name == "Alternate Text Links" {
				withKnownIssue {
					assertRenderingSnapshot(rendered, number: index + 1)
				}
			} else {
				assertRenderingSnapshot(rendered, number: index + 1)
			}
		}
	}

	private func assertRenderingSnapshot(_ image: NSImage, number: Int) {
		assertSnapshot(
			of: image,
			as: .proCRUDImage(precision: 0.99, perceptualPrecision: 0.99),
			named: "slide-\(number)",
			testName: "rendersRenderingEdgeCasesSlide",
		)
	}

	private func assertListsAndInsets(in slide: Rv_Data_Slide) throws {
		let decimal = try #require(slide.elements.first { $0.element.name == "Decimal List" }?.element.text)
		let disc = try #require(slide.elements.first { $0.element.name == "Disc List" }?.element.text)
		#expect(decimal.attributes.paragraphStyle.textList.isEnabled)
		#expect(decimal.attributes.paragraphStyle.textList.numberType == .decimal)
		#expect(decimal.attributes.paragraphStyle.textLists.map(\.numberType).contains(.decimal))
		#expect(disc.attributes.paragraphStyle.textList.isEnabled)
		#expect(disc.attributes.paragraphStyle.textList.numberType == .disc)
		#expect(disc.attributes.paragraphStyle.textLists.map(\.numberType).contains(.disc))
		for text in [decimal, disc] {
			#expect(text.attributes.paragraphStyle.firstLineHeadIndent == 24)
			#expect(text.attributes.paragraphStyle.headIndent == 110)
			#expect(text.attributes.paragraphStyle.defaultTabInterval == 36)
			#expect(text.attributes.paragraphStyle.tabStops.map(\.location) == [54, 110])
			let attributed = try attributedString(from: text)
			var containsList = false
			attributed.enumerateAttribute(
				.paragraphStyle,
				in: NSRange(location: 0, length: attributed.length),
			) { value, _, _ in
				guard let paragraph = value as? NSParagraphStyle else { return }
				containsList = containsList || !paragraph.textLists.isEmpty
			}
			#expect(containsList)
		}
		let decimalRTF = try #require(String(data: decimal.rtfData, encoding: .utf8))
		let discRTF = try #require(String(data: disc.rtfData, encoding: .utf8))
		#expect(decimalRTF.components(separatedBy: "\\listtext").count == 4)
		#expect(decimalRTF.contains("{\\listtext\t1.\t}"))
		#expect(discRTF.components(separatedBy: "\\listtext").count == 4)
		#expect(discRTF.contains("{\\listtext\t\\uc0\\u8226 \t}"))

		let inset = try #require(slide.elements.first { $0.element.name == "Asymmetric Inset" }?.element.text)
		#expect(inset.margins.left == 205)
		#expect(inset.margins.right == 30)
	}

	private func assertLineMaskHeightOffsets(in slide: Rv_Data_Slide) {
		let masks = slide.elements.compactMap { slideElement -> Rv_Data_Graphics.Text.LineFillMask? in
			guard case let .textLineMask(mask)? = slideElement.element.mask else { return nil }
			return mask
		}
		#expect(masks.count == 4)
		#expect(Set(masks.map(\.heightOffset)) == [0, 10, 55, 60])
		#expect(masks.allSatisfy { $0.enabled && $0.maskStyle == .lineWidth })
		let constrained = slide.elements.first { $0.element.name == "Offset 60 Constrained" }?.element
		#expect(constrained?.bounds.size.height == 82)
	}

	private func assertElementRotationsAndClipping(in slide: Rv_Data_Slide) {
		let elements = Dictionary(uniqueKeysWithValues: slide.elements.map { ($0.element.name, $0.element) })
		#expect(elements["Rotation 270"]?.rotation == 270)
		#expect(elements["Rotation 315"]?.rotation == 315)
		#expect(elements["Stored Rotation 360"]?.rotation == 360)
		#expect(elements["Rotated Off Canvas"]?.bounds.origin.x == -150)
		#expect(elements["Rotated Off Canvas"]?.rotation == 315)
		#expect(elements["Roundness 0.5"]?.path.shape.type == .roundedRectangle)
		#expect(elements["Roundness 0.5"]?.path.shape.roundedRectangle.roundness == 0.5)
	}

	private func assertAlternateTextLinks(in slide: Rv_Data_Slide) throws {
		let source = try #require(slide.elements.first { $0.element.name == "Source Lyrics" }?.element)
		let linked = slide.elements.filter { !$0.dataLinks.isEmpty }
		#expect(linked.count == 3)
		for element in linked {
			#expect(element.dataLinks.count == 1)
			guard case let .alternateText(link)? = element.dataLinks[0].propertyType else {
				Issue.record("Expected an alternate-text data link")
				continue
			}
			#expect(link.otherElementUuid.string == source.uuid.string)
			#expect(link.otherElementName == source.name)
		}
		#expect(linked.contains { $0.element.opacity == 0.12 })
		let outlined = try #require(linked.first { $0.element.name == "Outlined Scale-down Link" }?.element.text)
		#expect(outlined.scaleBehavior == .scaleFontDown)
		let attributed = try attributedString(from: outlined)
		var hasStroke = false
		attributed.enumerateAttribute(
			.strokeWidth,
			in: NSRange(location: 0, length: attributed.length),
		) { value, _, _ in
			hasStroke = hasStroke || ((value as? NSNumber)?.doubleValue ?? 0) != 0
		}
		#expect(hasStroke)
	}

	private func attributedString(from text: Rv_Data_Graphics.Text) throws -> NSAttributedString {
		try NSAttributedString(
			data: text.rtfData,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		)
	}
}
