import Foundation
import ProCRUDCore
import Testing

@Suite("ProPresenter 22 native interchange")
struct ProPresenter22InterchangeTests {
	@Test(arguments: ["NativePresentation.pro", "MetadataFreeTheme/Theme", "EmptyPlaylist.proPlaylist", "NativeEditedTarget21.pro", "NativeEditedTarget22.pro"])
	func nativeExportsLoadValidateAndPreserveTheirPayloads(name: String) throws {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let input = root.appendingPathComponent("Fixtures/ProPresenter22/Interchange/\(name)")
		let loaded = try DocumentLoader.load(from: input)
		#expect(!DocumentValidator.structuralDiagnostics(in: loaded).contains { $0.severity == .error })
		let bytes = try loaded.payload.serializedData()
		let decoded = try DocumentLoader.decode(bytes, as: loaded.kind, location: name)
		#expect(try decoded.serializedData() == bytes)
		if case let .theme(theme) = loaded.payload {
			#expect(!theme.hasApplicationInfo)
			#expect(!theme.slides.isEmpty)
		}
		if case let .presentation(presentation) = loaded.payload {
			#expect(presentation.applicationInfo.applicationVersion.majorVersion == 22)
			#expect(presentation.cues.count == 1)
			if name == "NativeEditedTarget21.pro" {
				#expect(presentation.ccli.songTitle == "Native Acceptance 21")
			}
			if name == "NativeEditedTarget22.pro" {
				#expect(presentation.ccli.songTitle == "Native Acceptance 22")
			}
		}
	}

	@Test
	func emptyNativePlaylistCanExpandAndRebundle() throws {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let input = root.appendingPathComponent("Fixtures/ProPresenter22/Interchange/EmptyPlaylist.proPlaylist")
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let expanded = try DocumentArchive.expand(input, to: directory.appendingPathComponent("Expanded"))
		#expect(try DocumentLoader.load(from: expanded).kind == .playlist)
		let bundled = try DocumentArchive.bundle(expanded, to: directory.appendingPathComponent("Again.proPlaylist"))
		#expect(try DocumentLoader.load(from: bundled).payload.serializedData() == DocumentLoader.load(from: input).payload.serializedData())
	}
}
