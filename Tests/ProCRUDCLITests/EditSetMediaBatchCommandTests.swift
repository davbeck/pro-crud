import CustomDump
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite("Edit set-media-batch command")
struct EditSetMediaBatchCommandTests {
	@Test
	func updatesPresentationAndThemeAsOneWorkspaceTransaction() throws {
		try withBatchTemporaryDirectory { workspaceURL in
			let mediaURL = workspaceURL.appendingPathComponent("Media/Assets/values.png")
			try writeBatchPNG(to: mediaURL)
			let playlistURL = workspaceURL.appendingPathComponent("Playlists/Media")
			try writeBatchPlaylist(mediaURL: mediaURL, to: playlistURL)

			let presentationURL = workspaceURL.appendingPathComponent("Libraries/Sections/Welcome.pro")
			try writeBatchPresentation(to: presentationURL)
			let themeURL = workspaceURL.appendingPathComponent("Themes/Series/Theme")
			try writeBatchTheme(to: themeURL)

			let manifestURL = workspaceURL.appendingPathComponent("media-replacements.json")
			try writeBatchManifest([
				[
					"document": "Libraries/Sections/Welcome.pro",
					"path": "/cues[index=0]/actions[index=1]/media/element",
					"from-playlist": ".",
					"playlist": "Values",
					"item": "Welcome",
					"sync-label": true,
				],
				[
					"document": "Themes/Series/Theme",
					"path": "/slides[name=Series]/base_slide/elements[name=Background]/element/fill/media",
					"from-playlist": "Playlists/Media",
					"playlist": "Values",
					"item": "Welcome",
				],
			], to: manifestURL)

			try EditSetMediaBatch.parse([
				workspaceURL.path,
				"--file", manifestURL.path,
			]).run()

			guard case let .presentation(presentation) = try DocumentLoader.loadRaw(presentationURL).payload else {
				Issue.record("Expected presentation")
				return
			}
			expectNoDifference(
				presentation.cues[0].actions[1].media.element.uuid.string,
				"VALUES-WELCOME",
			)
			expectNoDifference(presentation.cues[0].actions[1].label.text, "values.png")

			guard case let .theme(theme) = try DocumentLoader.loadRaw(themeURL).payload else {
				Issue.record("Expected theme")
				return
			}
			expectNoDifference(theme.slides[0].baseSlide.elements[0].element.fill.media.uuid.string, "VALUES-WELCOME")
			#expect(!FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent(".pro-crud-media-batch").path))
		}
	}

	@Test
	func lateInvalidOperationLeavesEveryOriginalByteIdentical() throws {
		try withBatchTemporaryDirectory { workspaceURL in
			let mediaURL = workspaceURL.appendingPathComponent("Media/Assets/values.png")
			try writeBatchPNG(to: mediaURL)
			let firstURL = workspaceURL.appendingPathComponent("Libraries/Sections/First.pro")
			let secondURL = workspaceURL.appendingPathComponent("Libraries/Sections/Second.pro")
			try writeBatchPresentation(to: firstURL)
			try writeBatchPresentation(to: secondURL)
			let firstOriginal = try Data(contentsOf: firstURL)
			let secondOriginal = try Data(contentsOf: secondURL)

			let manifestURL = workspaceURL.appendingPathComponent("invalid-late.json")
			try writeBatchManifest([
				[
					"document": "Libraries/Sections/First.pro",
					"path": "/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[name=Background]/element",
					"source": "Media/Assets/values.png",
				],
				[
					"document": "Libraries/Sections/Second.pro",
					"path": "/cues[index=99]/actions[index=0]/media/element",
					"source": "Media/Assets/values.png",
				],
			], to: manifestURL)

			#expect(throws: (any Error).self) {
				try EditSetMediaBatch.parse([
					workspaceURL.path,
					"--file", manifestURL.path,
				]).run()
			}
			try expectNoDifference(Data(contentsOf: firstURL), firstOriginal)
			try expectNoDifference(Data(contentsOf: secondURL), secondOriginal)
		}
	}

	@Test
	func commitFailureRestoresEveryAttemptedDocument() throws {
		try withBatchTemporaryDirectory { workspaceURL in
			let mediaURL = workspaceURL.appendingPathComponent("Media/Assets/values.png")
			try writeBatchPNG(to: mediaURL)
			let firstURL = workspaceURL.appendingPathComponent("Libraries/Sections/First.pro")
			let secondURL = workspaceURL.appendingPathComponent("Libraries/Sections/Second.pro")
			try writeBatchPresentation(to: firstURL)
			try writeBatchPresentation(to: secondURL)
			let firstOriginal = try Data(contentsOf: firstURL)
			let secondOriginal = try Data(contentsOf: secondURL)
			let manifest: [[String: Any]] = [firstURL, secondURL].map { documentURL in
				[
					"document": documentURL.path.replacingOccurrences(of: workspaceURL.path + "/", with: ""),
					"path": "/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[name=Background]/element",
					"source": "Media/Assets/values.png",
				]
			}
			let entries = try JSONDecoder().decode(
				[SetMediaBatchEntry].self,
				from: JSONSerialization.data(withJSONObject: manifest),
			)
			let transaction = try SetMediaBatchTransaction(workspaceURL: workspaceURL, entries: entries)
			var replacementCount = 0
			#expect(throws: (any Error).self) {
				try transaction.commit { fileManager, destinationURL, updatedURL in
					replacementCount += 1
					if replacementCount == 2 {
						throw CocoaError(.fileWriteUnknown)
					}
					_ = try fileManager.replaceItemAt(destinationURL, withItemAt: updatedURL)
				}
			}

			#expect(replacementCount == 2)
			try expectNoDifference(Data(contentsOf: firstURL), firstOriginal)
			try expectNoDifference(Data(contentsOf: secondURL), secondOriginal)
			let leftovers = try FileManager.default.contentsOfDirectory(atPath: workspaceURL.path)
				.filter { $0.hasPrefix(".pro-crud-media-batch-") }
			#expect(leftovers.isEmpty)
		}
	}

	@Test
	func rejectsSymlinkedWorkspaceInputs() throws {
		try withBatchTemporaryDirectory { workspaceURL in
			let outsideURL = FileManager.default.temporaryDirectory
				.appendingPathComponent("outside-\(UUID().uuidString).pro")
			try writeBatchPresentation(to: outsideURL)
			defer { try? FileManager.default.removeItem(at: outsideURL) }
			let linkedURL = workspaceURL.appendingPathComponent("Libraries/Linked.pro")
			try FileManager.default.createDirectory(at: linkedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: outsideURL)
			let sourceURL = workspaceURL.appendingPathComponent("Media/values.png")
			try writeBatchPNG(to: sourceURL)
			let manifestURL = workspaceURL.appendingPathComponent("symlink.json")
			try writeBatchManifest([[
				"document": "Libraries/Linked.pro",
				"path": "/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[name=Background]/element",
				"source": "Media/values.png",
			]], to: manifestURL)

			#expect(throws: (any Error).self) {
				try EditSetMediaBatch.parse([
					workspaceURL.path,
					"--file", manifestURL.path,
				]).run()
			}
		}
	}
}

private func writeBatchPresentation(to url: URL) throws {
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	var presentation = DocumentFactory.presentation(name: url.deletingPathExtension().lastPathComponent)
	try DocumentEditor.addElement(
		to: &presentation,
		at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
		name: "Background",
		bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
		color: DocumentEditor.color(hex: "#000000"),
	)
	var oldMedia = Rv_Data_Media()
	oldMedia.uuid.string = "OLD-MEDIA"
	oldMedia.url.absoluteString = "file:///old.png"
	var mediaAction = Rv_Data_Action()
	mediaAction.uuid.string = "MEDIA-ACTION"
	mediaAction.type = .media
	mediaAction.label.text = "old.png"
	mediaAction.media.element = oldMedia
	presentation.cues[0].actions.append(mediaAction)
	try DocumentWriter.writeRaw(
		ProPresenterDocument(payload: .presentation(presentation), origin: .raw(url)),
		to: url,
	)
}

private func writeBatchTheme(to url: URL) throws {
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	var theme = DocumentFactory.theme()
	DocumentEditor.addTemplate(to: &theme, name: "Series")
	var element = Rv_Data_Graphics.Element()
	element.uuid.string = "THEME-BACKGROUND"
	element.name = "Background"
	element.opacity = 1
	element.bounds.size.width = 1920
	element.bounds.size.height = 1080
	element.fill.enable = true
	element.fill.color = try DocumentEditor.color(hex: "#000000")
	var slideElement = Rv_Data_Slide.Element()
	slideElement.element = element
	theme.slides[0].baseSlide.elements = [slideElement]
	try DocumentWriter.writeRaw(
		ProPresenterDocument(payload: .theme(theme), origin: .raw(url)),
		to: url,
	)
}

private func writeBatchPlaylist(mediaURL: URL, to url: URL) throws {
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	var media = Rv_Data_Media()
	media.uuid.string = "VALUES-WELCOME"
	media.url.absoluteString = mediaURL.absoluteString
	var action = Rv_Data_Action()
	action.type = .media
	action.media.element = media
	var cue = Rv_Data_Cue()
	cue.actions = [action]
	var item = Rv_Data_PlaylistItem()
	item.name = "Welcome"
	item.cue = cue
	var playlist = DocumentFactory.playlist(name: "Values")
	playlist.rootNode.playlists.playlists[0].items.items = [item]
	try DocumentWriter.writeRaw(
		ProPresenterDocument(payload: .playlist(playlist), origin: .raw(url)),
		to: url,
	)
}

private func writeBatchManifest(_ manifest: [[String: Any]], to url: URL) throws {
	try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

private func writeBatchPNG(to url: URL) throws {
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
	try #require(Data(base64Encoded: encoded)).write(to: url)
}

private func withBatchTemporaryDirectory<Result>(_ operation: (URL) throws -> Result) throws -> Result {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("pro-crud-set-media-batch-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: directory) }
	return try operation(directory)
}
