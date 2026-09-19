import AppKit
import Foundation
import ProCRUDCore
import ProPresenterProto
import SnapshotTesting
import Testing

@Suite(
	"Sermon List Rendering",
	.snapshots(diffTool: .ksdiff),
	.timeLimit(.minutes(1)),
)
struct SermonListRenderingFixtureTests {
	@Test("Generated list matches the ProPresenter export")
	func rendersSermonListSlide() throws {
		let document = try PresentationLoader.load(
			from: fixtureURL("ProPresenter/SermonListRendering/SermonListRendering.probundle"),
		)
		#expect(document.orderedCues.count == 10)
		let cue = document.orderedCues[2]
		let text = try attributedText(in: cue)
		let listParagraphs = paragraphStyles(in: text).filter { !$0.textLists.isEmpty }

		#expect(listParagraphs.count == 3)
		#expect(listParagraphs.map { $0.tabStops.map(\.location) } == [
			[1, 101],
			[1, 101],
			[1, 101],
		])

		let bitmap = try PresentationRenderer(document: document).render(cue: cue)
		#expect(bitmap.pixelsWide == 3840)
		#expect(bitmap.pixelsHigh == 2160)
		let rendered = NSImage(size: bitmap.size)
		rendered.addRepresentation(bitmap)
		assertSnapshot(
			of: rendered,
			as: .proCRUDImage(precision: 0.99, perceptualPrecision: 0.99),
		)
	}

	private func attributedText(in cue: Rv_Data_Cue) throws -> NSAttributedString {
		let data = cue.actions
			.filter { $0.type == .presentationSlide }
			.map(\.slide.presentation.baseSlide)
			.flatMap(\.elements)
			.map(\.element.text.rtfData)
			.first { data in
				guard let rtf = String(data: data, encoding: .utf8) else { return false }
				return rtf.contains("BLESSED IN CHRIST")
			}
		return try NSAttributedString(
			data: #require(data),
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		)
	}

	private func paragraphStyles(in attributedText: NSAttributedString) -> [NSParagraphStyle] {
		var styles: [NSParagraphStyle] = []
		let string = attributedText.string as NSString
		var location = 0
		while location < string.length {
			let range = string.paragraphRange(for: NSRange(location: location, length: 0))
			if let style = attributedText.attribute(
				.paragraphStyle,
				at: location,
				effectiveRange: nil,
			) as? NSParagraphStyle {
				styles.append(style)
			}
			location = NSMaxRange(range)
		}
		return styles
	}
}
