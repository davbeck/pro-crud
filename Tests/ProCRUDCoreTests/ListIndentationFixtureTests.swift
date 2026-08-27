import AppKit
import Foundation
import ProCRUDCore
import ProPresenterProto
import SnapshotTesting
import Testing

@Suite(
	"List Indentation",
	.snapshots(diffTool: .ksdiff),
	.timeLimit(.minutes(1)),
)
struct ListIndentationFixtureTests {
	@Test("Native list indentation and marker styling")
	func rendersListIndentationSlides() throws {
		let document = try PresentationLoader.load(
			from: fixtureURL("ProPresenter/ListIndentation/ListIndentation.probundle"),
		)
		let cues = document.orderedCues
		#expect(cues.count == 3)

		let nestedList = try attributedText(in: cues[2])
		let nestedParagraphs = paragraphStyles(in: nestedList).filter { !$0.textLists.isEmpty }
		#expect(nestedParagraphs.map(\.textLists.count) == [1, 2, 1, 2, 1])
		#expect(nestedParagraphs.map { $0.tabStops.map(\.location) } == [
			[1, 160],
			[100, 200],
			[1, 160],
			[161, 320],
			[1, 160],
		])

		let coloredMarkerRTF = try #require(String(data: rtfData(in: cues[0]), encoding: .utf8))
		#expect(coloredMarkerRTF.contains("\\cf3 {\\listtext"))

		for (index, cue) in cues.enumerated() {
			let bitmap = try PresentationRenderer(document: document).render(cue: cue)
			#expect(bitmap.pixelsWide == 1280)
			#expect(bitmap.pixelsHigh == 720)
			let rendered = NSImage(size: bitmap.size)
			rendered.addRepresentation(bitmap)
			assertSnapshot(
				of: rendered,
				as: .image(precision: 0.99, perceptualPrecision: 0.99),
				named: "slide-\(index + 1)",
				testName: "rendersListIndentationSlide",
			)
		}
	}

	private func attributedText(in cue: Rv_Data_Cue) throws -> NSAttributedString {
		try NSAttributedString(
			data: rtfData(in: cue),
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		)
	}

	private func rtfData(in cue: Rv_Data_Cue) throws -> Data {
		let data = cue.actions
			.filter { $0.type == .presentationSlide }
			.map(\.slide.presentation.baseSlide)
			.flatMap(\.elements)
			.map(\.element.text.rtfData)
			.first { !$0.isEmpty }
		return try #require(data)
	}

	private func paragraphStyles(in attributedText: NSAttributedString) -> [NSParagraphStyle] {
		var styles: [NSParagraphStyle] = []
		attributedText.enumerateAttribute(
			.paragraphStyle,
			in: NSRange(location: 0, length: attributedText.length),
		) { value, _, _ in
			guard let style = value as? NSParagraphStyle else { return }
			styles.append(style)
		}
		return styles
	}
}
