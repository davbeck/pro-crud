import AppKit
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Text Delivery")
struct TextDeliveryTests {
	@Test(arguments: ["zero", "one", "two", "boundaries"])
	func matchesNativeSchedule(name: String) throws {
		var slide = try nativeSlide(name)
		let original = slide
		#expect(try TextDelivery.unitCount(slide.elements[0].element.text.rtfData) == 4)
		#expect(try TextDelivery.issue(in: slide, elementIndex: 0) == nil)
		try TextDelivery.refresh(in: &slide, elementIndex: 0)
		#expect(slide.elements[0].childBuilds == original.elements[0].childBuilds)
		#expect(slide.elementBuildOrder == original.elementBuildOrder)
		#expect(slide.elements[0].revealFromIndex == original.elements[0].revealFromIndex)
		#expect(slide.elements[0].buildIn.transition == original.elements[0].buildIn.transition)
	}

	@Test
	func repairsSermonAndPreservesInterleavedBuildsAndTiming() throws {
		var slide = try nativeSlide("two")
		let lastID = slide.elements[0].childBuilds.removeLast().uuid.string
		slide.elementBuildOrder.removeAll { $0.string == lastID }
		// Reproduce the original bundle's stale schedule: children 0 and 1,
		// both scheduled despite revealFromIndex 2.
		slide.elementBuildOrder = slide.elements[0].childBuilds.map(\.uuid)
		var unrelated = Rv_Data_UUID()
		unrelated.string = "OTHER-OBJECT"
		slide.elementBuildOrder.insert(unrelated, at: 1)
		slide.elements[0].childBuilds[1].delayTime = 0.75
		let retained = slide.elements[0].childBuilds[1]
		#expect(try TextDelivery.issue(in: slide, elementIndex: 0) != nil)
		try TextDelivery.refresh(in: &slide, elementIndex: 0, initiallyVisible: 1)
		#expect(slide.elements[0].childBuilds.map(\.index) == [0, 1, 2])
		#expect(slide.elements[0].childBuilds[1] == retained)
		#expect(slide.elementBuildOrder[1] == unrelated)
		#expect(slide.elementBuildOrder.last == slide.elements[0].childBuilds.last?.uuid)
		#expect(slide.elements[0].revealFromIndex == 1)
		#expect(try TextDelivery.issue(in: slide, elementIndex: 0) == nil)
	}

	@Test
	func createsClearsAndRejectsInvalidCountsAtomically() throws {
		var slide = try nativeSlide("one")
		TextDelivery.clear(in: &slide, elementIndex: 0)
		let cleared = slide
		#expect(!slide.elements[0].hasBuildIn)
		#expect(throws: DocumentEditError.self) { try TextDelivery.refresh(in: &slide, elementIndex: 0, initiallyVisible: -1) }
		#expect(slide == cleared)
		#expect(throws: DocumentEditError.self) { try TextDelivery.refresh(in: &slide, elementIndex: 0, initiallyVisible: 5) }
		#expect(slide == cleared)
		try TextDelivery.refresh(in: &slide, elementIndex: 0, initiallyVisible: 0)
		#expect(slide.elementBuildOrder.count == 4)
		#expect(slide.elementBuildOrder.first == slide.elements[0].buildIn.uuid)
		#expect(try TextDelivery.issue(in: slide, elementIndex: 0) == nil)
	}

	@Test
	func shrinkingTextRemovesObsoleteReferencesAndRetainsBuildOut() throws {
		var slide = try nativeSlide("one")
		slide.elements[0].buildOut.uuid.string = "BUILD-OUT"
		slide.elementBuildOrder.append(slide.elements[0].buildOut.uuid)
		let text = NSAttributedString(string: "Heading\nOnly point")
		slide.elements[0].element.text.rtfData = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
		try TextDelivery.refresh(in: &slide, elementIndex: 0)
		#expect(slide.elements[0].childBuilds.count == 1)
		#expect(slide.elementBuildOrder.count == 2)
		#expect(slide.elementBuildOrder.last?.string == "BUILD-OUT")
		TextDelivery.clear(in: &slide, elementIndex: 0)
		#expect(slide.elementBuildOrder.map(\.string) == ["BUILD-OUT"])
	}

	private func nativeSlide(_ name: String) throws -> Rv_Data_Slide {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		return try Rv_Data_Slide(jsonUTF8Data: Data(contentsOf: root.appendingPathComponent("Fixtures/ProPresenter/TextDelivery/\(name).json")))
	}
}
