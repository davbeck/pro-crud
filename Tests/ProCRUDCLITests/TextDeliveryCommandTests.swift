import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite("Text Delivery commands")
struct TextDeliveryCommandTests {
	@Test
	func batchAuthorsAndUpdatesDeliveryAndFailureDoesNotWrite() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let input = directory.appendingPathComponent("Delivery.pro")
		let batch = directory.appendingPathComponent("edits.json")
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let slide = try Rv_Data_Slide(jsonUTF8Data: Data(contentsOf: root.appendingPathComponent("Fixtures/ProPresenter/TextDelivery/two.json")))
		var presentation = DocumentFactory.presentation(name: "Delivery")
		presentation.cues[0].actions[0].slide.presentation.baseSlide = slide
		try presentation.serializedData().write(to: input)
		let path = "/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text"
		let operations: [[String: Any]] = [
			["command": "set-text", "path": path, "text": "Heading\nPhysically\nCulturally\nSpiritually\nTogether"],
			["command": "set-text-delivery", "path": path, "initially-visible": 1],
		]
		try JSONSerialization.data(withJSONObject: operations).write(to: batch)
		try EditApply.parse([input.path, "--file", batch.path]).run()
		let output = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: input))
		let result = output.cues[0].actions[0].slide.presentation.baseSlide
		#expect(result.elements[0].childBuilds.count == 4)
		#expect(result.elements[0].revealFromIndex == 1)
		#expect(result.elementBuildOrder.count == 4)
		let saved = try Data(contentsOf: input)
		try JSONSerialization.data(withJSONObject: operations + [["command": "set-text-delivery", "path": path, "initially-visible": -1]]).write(to: batch)
		#expect(throws: (any Error).self) { try EditApply.parse([input.path, "--file", batch.path]).run() }
		#expect(try Data(contentsOf: input) == saved)
		try EditSetTextDelivery.parse([input.path, "--path", path, "--clear"]).run()
		let cleared = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: input))
		#expect(!cleared.cues[0].actions[0].slide.presentation.baseSlide.elements[0].hasBuildIn)
	}
}
