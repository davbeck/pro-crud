import Foundation
import ProCRUDCore
import Testing
@testable import ProCRUDCLI

@Suite("Render command")
struct RenderCommandTests {
	@Test(arguments: ["json", "pdf", "png", "png,pdf,json"])
	func unsupportedFileRepresentationDoesNotReplaceExistingOutput(format: String) throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let input = directory.appendingPathComponent("Unsupported.pro")
		var bytes = try DocumentFactory.presentation(name: "Unsupported").serializedData()
		bytes.append(contentsOf: [0xC2, 0x01, 0x00]) // Presentation.cue_group_placements = 24
		try bytes.write(to: input)

		let output = directory.appendingPathComponent("existing")
		let sentinelURL: URL
		if format == "json" || format == "pdf" {
			sentinelURL = output
		} else {
			try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
			sentinelURL = output.appendingPathComponent("1.png")
		}
		let sentinel = Data("existing output".utf8)
		try sentinel.write(to: sentinelURL)

		#expect(throws: DocumentCompatibilityError.self) {
			try Render.parse([input.path, "--format", format, "--output", output.path, "--replace"]).run()
		}
		#expect(try Data(contentsOf: sentinelURL) == sentinel)
		if sentinelURL != output {
			#expect(try FileManager.default.contentsOfDirectory(atPath: output.path) == ["1.png"])
		}
		#expect(try Data(contentsOf: input) == bytes)
	}
}
