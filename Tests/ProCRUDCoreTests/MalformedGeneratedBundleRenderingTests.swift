import AppKit
import ProCRUDCore
import SnapshotTesting
import Testing

@Suite(
	"Malformed Generated Bundle",
	.snapshots(diffTool: .ksdiff),
	.timeLimit(.minutes(1)),
)
struct MalformedGeneratedBundleRenderingTests {
	@Test("Focused malformed bundle cases")
	func focusedMalformedBundleCases() throws {
		let document = try PresentationLoader.load(
			from: fixtureURL("ProPresenter/MalformedGeneratedBundle/MalformedGeneratedBundle.probundle"),
		)
		#expect(document.orderedCues.count == 5)
		#expect(document.renderingDiagnostics.filter { $0.message.contains("stale metadata") }.count == 7)
		let opacitySlide = try #require(document.orderedCues.last?.actions.first?.slide.presentation.baseSlide)
		#expect(Set(opacitySlide.elements.map(\.element.opacity)).isSuperset(of: [0, 0.25, 1]))

		for (index, cue) in document.orderedCues.enumerated() {
			let bitmap = try PresentationRenderer(document: document).render(cue: cue)
			let rendered = NSImage(size: bitmap.size)
			rendered.addRepresentation(bitmap)

			assertSnapshot(
				of: rendered,
				as: .proCRUDImage(precision: 0.99, perceptualPrecision: 0.99),
				named: "slide-\(index + 1)",
				testName: "rendersMalformedGeneratedBundleSlide",
			)
		}
	}
}
