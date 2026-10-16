import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite("HLS interchange commands")
struct HLSInterchangeCommandTests {
	@Test func editAndBundlePreserveTheMediaWhile21AndStaticRenderingRejectAtomically() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("HLSCommands-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/HLSInterchange/ConstructedInput.pro")
		let source = root.appendingPathComponent("Stream.pro"), edited = root.appendingPathComponent("Edited.pro"), archive = root.appendingPathComponent("Stream.probundle")
		try FileManager.default.copyItem(at: fixture, to: source)
		let sourceBytes = try Data(contentsOf: source)
		try EditPatch.parse([source.path, "--path", "/ccli", "--json", "{\"song_title\":\"CLI HLS\"}", "--output", edited.path]).run()
		let original = try Rv_Data_Presentation(serializedBytes: sourceBytes), changed = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: edited))
		#expect(changed.ccli.songTitle == "CLI HLS")
		#expect(original.cues == changed.cues)
		try BundleCommand.parse([edited.path, "--output", archive.path, "--target-version", "22"]).run()
		let expanded = try DocumentArchive.expand(archive, to: root.appendingPathComponent("expanded"))
		#expect(try FileManager.default.contentsOfDirectory(atPath: expanded.path) == ["Edited.pro"])
		#expect(try Data(contentsOf: expanded.appendingPathComponent("Edited.pro")) == Data(contentsOf: edited))
		let sentinel = Data("Existing output".utf8)
		try sentinel.write(to: archive)
		#expect(throws: DocumentCompatibilityError.self) { try BundleCommand.parse([edited.path, "--output", archive.path, "--target-version", "21", "--replace"]).run() }
		#expect(try Data(contentsOf: archive) == sentinel)
		let render = root.appendingPathComponent("render.json")
		try sentinel.write(to: render)
		#expect(throws: (any Error).self) { try Render.parse([edited.path, "--format", "json", "--output", render.path, "--replace"]).run() }
		#expect(try Data(contentsOf: render) == sentinel && Data(contentsOf: source) == sourceBytes)
	}
}
