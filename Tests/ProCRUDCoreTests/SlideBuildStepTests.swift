import AppKit
import CustomDump
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Build step rendering")
struct SlideBuildStepTests {
	@Test(arguments: [("zero", 5, 0), ("one", 4, 1), ("two", 3, 2), ("boundaries", 3, 2)])
	func nativeBulletStates(name: String, count: Int, initiallyVisible: Int) throws {
		let slide = try nativeSlide(name)
		let cue = cue(slide)
		let states = try SlideBuildStep.states(for: cue)
		expectNoDifference(states.count, count)
		expectNoDifference(states[0].visibleTextUnits[0], Set(0 ..< initiallyVisible))
		expectNoDifference(states[0].hiddenElements, initiallyVisible == 0 ? [0] : [])
		expectNoDifference(states.last?.visibleTextUnits[0], Set(0 ..< 4))
		#expect(states.last?.hiddenElements.isEmpty == true)
	}

	@Test func interleavedObjectBuildsFollowStoredOrder() throws {
		var slide = try nativeSlide("two")
		var object = Rv_Data_Slide.Element()
		object.buildIn.uuid.string = "OBJECT-IN"
		object.buildOut.uuid.string = "OBJECT-OUT"
		slide.elements.append(object)
		slide.elementBuildOrder.insert(object.buildIn.uuid, at: 1)
		slide.elementBuildOrder.append(object.buildOut.uuid)
		let states = try SlideBuildStep.states(for: cue(slide))
		expectNoDifference(states.map(\.hiddenElements), [[1], [1], [], [], [1]])
		expectNoDifference(states[1].visibleTextUnits[0], [0, 1, 2])
		expectNoDifference(states[2].visibleTextUnits[0], [0, 1, 2])
		expectNoDifference(states[3].visibleTextUnits[0], [0, 1, 2, 3])
	}

	@Test func maskingKeepsTextAndLayoutAttributesAndHidesEveryPaint() {
		let style = NSMutableParagraphStyle()
		style.alignment = .center
		let text = NSAttributedString(string: "Heading\r\n\r\nSecond\u{2028}wrapped\nThird\n", attributes: [
			.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.white,
			.paragraphStyle: style, .strokeColor: NSColor.red, .strokeWidth: -2,
			.underlineStyle: 1, .shadow: NSShadow(),
		])
		let masked = SlideBuildStep.maskedText(text, visibleUnits: [0, 2])
		expectNoDifference(masked.string, text.string)
		let hidden = (text.string as NSString).range(of: "Second").location
		#expect((masked.attribute(.foregroundColor, at: hidden, effectiveRange: nil) as? NSColor)?.alphaComponent == 0)
		#expect((masked.attribute(.strokeColor, at: hidden, effectiveRange: nil) as? NSColor)?.alphaComponent == 0)
		#expect(masked.attribute(.shadow, at: hidden, effectiveRange: nil) == nil)
		#expect(masked.attribute(.underlineStyle, at: hidden, effectiveRange: nil) == nil)
		#expect((masked.attribute(.font, at: hidden, effectiveRange: nil) as? NSFont)?.pointSize == 42)
		let third = (text.string as NSString).range(of: "Third").location
		#expect((masked.attribute(.foregroundColor, at: third, effectiveRange: nil) as? NSColor)?.alphaComponent == 1)
	}

	@Test func unsupportedAndBrokenSchedulesFailExplicitly() throws {
		var slide = try nativeSlide("one")
		slide.elements[0].revealType = .underline
		#expect(throws: RenderError.self) { try SlideBuildStep.states(for: cue(slide)) }
		slide = try nativeSlide("one")
		slide.elementBuildOrder.append(slide.elementBuildOrder[0])
		#expect(throws: RenderError.self) { try SlideBuildStep.states(for: cue(slide)) }
		slide = try nativeSlide("one")
		var missing = Rv_Data_UUID()
		missing.string = "MISSING"
		slide.elementBuildOrder.append(missing)
		#expect(throws: RenderError.self) { try SlideBuildStep.states(for: cue(slide)) }
	}

	private func cue(_ slide: Rv_Data_Slide) -> Rv_Data_Cue {
		var presentation = DocumentFactory.presentation(name: "Builds")
		presentation.cues[0].actions[0].slide.presentation.baseSlide = slide
		return presentation.cues[0]
	}

	private func nativeSlide(_ name: String) throws -> Rv_Data_Slide {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		return try Rv_Data_Slide(jsonUTF8Data: Data(contentsOf: root.appendingPathComponent("Fixtures/ProPresenter/TextDelivery/\(name).json")))
	}
}
