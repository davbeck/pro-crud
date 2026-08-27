import CustomDump
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite("Edit set-media command")
struct EditSetMediaCommandTests {
	@Test
	func editsRawPresentationAndThemeDocumentsFromSource() throws {
		try withMediaTemporaryDirectory { directory in
			let sourceURL = directory.appendingPathComponent("new-series.png")
			try writePNG(to: sourceURL)

			let presentationURL = directory.appendingPathComponent("Main Service Sections.pro")
			try writePresentation(to: presentationURL)
			let presentationPath = "/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[name=Background]/element"
			try EditSetMedia.parse([
				presentationURL.path,
				"--path", presentationPath,
				"--source", sourceURL.path,
			]).run()

			guard case let .presentation(presentation) = try DocumentLoader.load(from: presentationURL).payload else {
				Issue.record("Expected a presentation document")
				return
			}
			let presentationMedia = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media
			expectNoDifference(presentationMedia.url.absoluteString, sourceURL.absoluteString)
			#expect(!presentationMedia.uuid.string.isEmpty)

			let themeURL = directory.appendingPathComponent("Series/Theme")
			try writeTheme(to: themeURL)
			let themePath = "/slides[name=Series]/base_slide/elements[name=Background]/element/fill/media"
			try EditSetMedia.parse([
				themeURL.path,
				"--path", themePath,
				"--source", sourceURL.path,
			]).run()

			guard case let .theme(theme) = try DocumentLoader.load(from: themeURL).payload else {
				Issue.record("Expected a theme document")
				return
			}
			let themeMedia = theme.slides[0].baseSlide.elements[0].element.fill.media
			expectNoDifference(themeMedia.url.absoluteString, sourceURL.absoluteString)
			#expect(!themeMedia.uuid.string.isEmpty)
		}
	}

	@Test
	func batchEditsPresentationAndThemeArchivesFromPlaylist() throws {
		try withMediaTemporaryDirectory { directory in
			let sourceURL = directory.appendingPathComponent("canonical-series.png")
			try writePNG(to: sourceURL)
			let playlistURL = directory.appendingPathComponent("data")
			try writeMediaPlaylist(mediaURL: sourceURL, to: playlistURL)

			let presentationWorkspace = directory.appendingPathComponent("Presentation Workspace")
			let presentationURL = presentationWorkspace.appendingPathComponent("Main Service Sections.pro")
			try writePresentation(to: presentationURL)
			let presentationArchive = try DocumentArchive.bundle(
				presentationWorkspace,
				to: directory.appendingPathComponent("Main Service Sections.probundle"),
			)
			try applyPlaylistMedia(
				to: presentationArchive,
				path: "/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[name=Background]/element",
				playlistURL: playlistURL,
				batchURL: directory.appendingPathComponent("presentation-edits.json"),
			)

			guard case let .presentation(presentation) = try DocumentLoader.load(from: presentationArchive).payload else {
				Issue.record("Expected a presentation archive")
				return
			}
			let presentationMedia = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media
			assertCanonicalArchiveMedia(presentationMedia)

			let themeWorkspace = directory.appendingPathComponent("Theme Workspace")
			let themeURL = themeWorkspace.appendingPathComponent("Series/Theme")
			try writeTheme(to: themeURL)
			let themeArchive = try DocumentArchive.bundle(
				themeWorkspace,
				to: directory.appendingPathComponent("Series.proTheme"),
			)
			try applyPlaylistMedia(
				to: themeArchive,
				path: "/slides[name=Series]/base_slide/elements[name=Background]/element/fill/media",
				playlistURL: playlistURL,
				batchURL: directory.appendingPathComponent("theme-edits.json"),
			)

			let loadedThemeArchive = try DocumentLoader.load(from: themeArchive)
			guard case let .theme(theme) = loadedThemeArchive.payload else {
				Issue.record("Expected a theme archive")
				return
			}
			let themeMedia = theme.slides[0].baseSlide.elements[0].element.fill.media
			assertCanonicalArchiveMedia(themeMedia)
			#expect(loadedThemeArchive.archiveEntries.contains(sourceURL.lastPathComponent))
		}
	}
}

private func writePresentation(to url: URL) throws {
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	var presentation = DocumentFactory.presentation(name: "Main Service Sections")
	try DocumentEditor.addElement(
		to: &presentation,
		at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
		name: "Background",
		bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
		color: DocumentEditor.color(hex: "#000000"),
	)
	try DocumentWriter.writeRaw(
		ProPresenterDocument(payload: .presentation(presentation), origin: .raw(url)),
		to: url,
	)
}

private func writeTheme(to url: URL) throws {
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	var theme = DocumentFactory.theme()
	DocumentEditor.addTemplate(to: &theme, name: "Series")
	var element = Rv_Data_Graphics.Element()
	element.uuid.string = "THEME-BACKGROUND-ELEMENT"
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

private func writeMediaPlaylist(mediaURL: URL, to url: URL) throws {
	var media = Rv_Data_Media()
	media.uuid.string = "CANONICAL-SERIES-MEDIA"
	media.url.absoluteString = mediaURL.absoluteString
	media.metadata.artist = "Values playlist"
	media.image.drawing.naturalSize.width = 1920
	media.image.drawing.naturalSize.height = 1080
	var action = Rv_Data_Action()
	action.type = .media
	action.media.element = media
	var cue = Rv_Data_Cue()
	cue.actions = [action]
	var item = Rv_Data_PlaylistItem()
	item.name = "New Series"
	item.cue = cue
	var playlist = DocumentFactory.playlist(name: "Values")
	playlist.rootNode.playlists.playlists[0].items.items = [item]
	try DocumentWriter.writeRaw(
		ProPresenterDocument(payload: .playlist(playlist), origin: .raw(url)),
		to: url,
	)
}

private func applyPlaylistMedia(to inputURL: URL, path: String, playlistURL: URL, batchURL: URL) throws {
	let operations: [[String: Any]] = [[
		"command": "set-media",
		"path": path,
		"from-playlist": playlistURL.path,
		"playlist": "Values",
		"item": "New Series",
	]]
	try JSONSerialization.data(withJSONObject: operations, options: [.prettyPrinted, .sortedKeys])
		.write(to: batchURL)
	try EditApply.parse([
		inputURL.path,
		"--file", batchURL.path,
	]).run()
}

private func assertCanonicalArchiveMedia(_ media: Rv_Data_Media) {
	expectNoDifference(media.uuid.string, "CANONICAL-SERIES-MEDIA")
	expectNoDifference(media.url.relativePath, "canonical-series.png")
	expectNoDifference(media.metadata.artist, "Values playlist")
	expectNoDifference(media.image.drawing.naturalSize.width, 1920)
	expectNoDifference(media.image.drawing.naturalSize.height, 1080)
}

private func writePNG(to url: URL) throws {
	let encoded = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
	try #require(Data(base64Encoded: encoded)).write(to: url)
}

private func withMediaTemporaryDirectory<Result>(_ operation: (URL) throws -> Result) throws -> Result {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("pro-crud-set-media-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: directory) }
	return try operation(directory)
}
