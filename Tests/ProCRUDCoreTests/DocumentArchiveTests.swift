import AppKit
import CustomDump
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite(
	.timeLimit(.minutes(1)),
)
struct DocumentArchiveTests {
	@Test
	func bundleCopiesResolvableMediaAndReportsMissingReferences() throws {
		let root = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let directory = root.appendingPathComponent("document")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let media = root.appendingPathComponent("external.png")
		try writeArchivePNG(to: media)
		let source = directory.appendingPathComponent("Portable.pro")
		try writePresentation(with: [media, directory.appendingPathComponent("missing.png")], to: source)

		let archive = directory.appendingPathComponent("Portable.probundle")
		let result = try DocumentArchive.bundleWithReport(source, to: archive)
		#expect(result.warnings == ["Missing media asset: \(directory.appendingPathComponent("missing.png").absoluteString)"])

		let expanded = try DocumentArchive.expand(archive, to: directory.appendingPathComponent("expanded"))
		#expect(FileManager.default.fileExists(atPath: expanded.appendingPathComponent("external.png").path))
		let document = try DocumentLoader.loadRaw(expanded.appendingPathComponent("Portable.pro"))
		guard case let .presentation(presentation) = document.payload else { Issue.record("Expected presentation payload"); return }
		let firstElement = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element
		#expect(firstElement.fill.media.url.relativePath == "external.png")
		#expect(firstElement.fill.media.metadata.format == "png")
		if case .image? = firstElement.fill.media.typeProperties {
		} else {
			Issue.record("Expected the media fill to retain its image type")
		}
	}

	@Test
	func bundleDeduplicatesRepeatedReferencesToTheSameExternalMedia() throws {
		let root = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let directory = root.appendingPathComponent("document")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let mediaURL = root.appendingPathComponent("background.png")
		try writeArchivePNG(to: mediaURL)

		var presentation = DocumentFactory.presentation(name: "Repeated Background")
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		for cueIndex in presentation.cues.indices {
			var media = Rv_Data_Media()
			media.url.absoluteString = mediaURL.absoluteString
			var mediaType = Rv_Data_Action.MediaType()
			mediaType.element = media
			var action = Rv_Data_Action()
			action.type = .backgroundMedia
			action.media = mediaType
			presentation.cues[cueIndex].actions.append(action)
		}

		let source = directory.appendingPathComponent("Repeated Background.pro")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .presentation(presentation), origin: .raw(source)),
			to: source,
		)

		let archive = directory.appendingPathComponent("Repeated Background.probundle")
		let result = try DocumentArchive.bundleWithReport(source, to: archive)
		expectNoDifference(result.warnings, [])

		let expanded = try DocumentArchive.expand(archive, to: directory.appendingPathComponent("expanded"))
		let mediaEntries = try FileManager.default.contentsOfDirectory(at: expanded, includingPropertiesForKeys: nil)
			.filter { $0.lastPathComponent == mediaURL.lastPathComponent }
		expectNoDifference(mediaEntries.map(\.lastPathComponent), ["background.png"])

		let document = try DocumentLoader.loadRaw(expanded.appendingPathComponent(source.lastPathComponent))
		guard case let .presentation(bundledPresentation) = document.payload else {
			Issue.record("Expected presentation payload")
			return
		}
		let backgroundPaths = bundledPresentation.cues
			.flatMap(\.actions)
			.filter { $0.type == .backgroundMedia }
			.map(\.media.element.url.relativePath)
		expectNoDifference(backgroundPaths, ["background.png", "background.png"])
	}

	@Test
	func bundleDisambiguatesConflictingExternalMediaDestinations() throws {
		let root = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let directory = root.appendingPathComponent("document")
		let externalRoot = root.appendingPathComponent("external")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let first = externalRoot.appendingPathComponent("first/shared.png")
		let second = externalRoot.appendingPathComponent("second/shared.png")
		let third = externalRoot.appendingPathComponent("third/shared.png")
		try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: third.deletingLastPathComponent(), withIntermediateDirectories: true)
		try writeArchivePNG(to: first)
		try writeArchivePNG(to: second, width: 2)
		try writeArchivePNG(to: third, width: 3)
		let source = directory.appendingPathComponent("Collision.pro")
		try writePresentation(with: [first, second, third], to: source)

		let archive = try DocumentArchive.bundle(source, to: directory.appendingPathComponent("Collision.probundle"))
		let expanded = try DocumentArchive.expand(archive, to: directory.appendingPathComponent("expanded"))
		#expect(try Data(contentsOf: expanded.appendingPathComponent("shared.png")) == Data(contentsOf: first))
		#expect(try Data(contentsOf: expanded.appendingPathComponent("shared-1.png")) == Data(contentsOf: second))
		#expect(try Data(contentsOf: expanded.appendingPathComponent("shared-2.png")) == Data(contentsOf: third))

		let loaded = try DocumentLoader.loadRaw(expanded.appendingPathComponent("Collision.pro"))
		guard case let .presentation(presentation) = loaded.payload else {
			Issue.record("Expected presentation payload")
			return
		}
		let paths = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements
			.map(\.element.fill.media.url.relativePath)
		expectNoDifference(paths, ["shared.png", "shared-1.png", "shared-2.png"])
	}

	@Test(arguments: ["../outside.png", ".hidden.png"])
	func bundleRejectsUnsafeRelativeMediaPaths(path: String) throws {
		let directory = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = directory.appendingPathComponent("Unsafe.pro")
		try writePresentation(with: [directory.appendingPathComponent("missing.png")], to: source)
		try replaceFirstMediaURL(in: source) { $0.relativePath = path }

		#expect(throws: DocumentArchiveError.self) {
			_ = try DocumentArchive.bundle(
				source,
				to: directory.appendingPathComponent("Unsafe.probundle"),
			)
		}
	}

	@Test
	func bundleRejectsSymbolicLinkMedia() throws {
		let directory = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let target = directory.appendingPathComponent("target.png")
		let link = directory.appendingPathComponent("link.png")
		try writeArchivePNG(to: target)
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
		let source = directory.appendingPathComponent("Symlink.pro")
		try writePresentation(with: [directory.appendingPathComponent("missing.png")], to: source)
		try replaceFirstMediaURL(in: source) { $0.absoluteString = link.absoluteString }

		#expect(throws: ArchiveError.self) {
			_ = try DocumentArchive.bundle(
				source,
				to: directory.appendingPathComponent("Symlink.probundle"),
			)
		}
	}

	@Test
	func bundleCountsExternalMediaAgainstEntryLimit() throws {
		let root = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let directory = root.appendingPathComponent("document")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let external = root.appendingPathComponent("limited.png")
		try writeArchivePNG(to: external)
		let source = directory.appendingPathComponent("Limited.pro")
		try writePresentation(with: [external], to: source)

		var limits = ArchiveLimits.default
		limits.maximumEntryCount = 1
		#expect(throws: ArchiveError.self) {
			_ = try DocumentArchive.bundle(
				source,
				to: directory.appendingPathComponent("Limited.probundle"),
				limits: limits,
			)
		}
	}

	@Test
	func bundleExpandAndRebundlePreservesUnknownDataOrderingMediaAndCopiedIDs() throws {
		let root = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: root) }
		let directory = root.appendingPathComponent("document")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let media = root.appendingPathComponent("roundtrip.png")
		try writeArchivePNG(to: media)
		let source = directory.appendingPathComponent("Roundtrip.pro")
		try writePresentation(with: [media], to: source)

		var original = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: source))
		try DocumentEditor.addBlankSlide(to: &original, groupPath: ComponentPath("/cue_groups[index=0]"))
		try DocumentEditor.duplicateCue(in: &original, at: ComponentPath("/cues[index=1]"))
		var bytes = try original.serializedData()
		bytes.append(contentsOf: [0xA0, 0x06, 0x01])
		let document = try ProPresenterDocument(
			payload: DocumentLoader.decode(bytes, as: .presentation, location: source.path),
			origin: .raw(source),
		)
		try DocumentWriter.writeRaw(document, to: source, replace: true)

		let archive = try DocumentArchive.bundle(source, to: directory.appendingPathComponent("Roundtrip.probundle"))
		let expanded = try DocumentArchive.expand(archive, to: directory.appendingPathComponent("expanded"))
		let rebundled = try DocumentArchive.bundle(expanded, to: directory.appendingPathComponent("Rebundled.probundle"))
		let loaded = try DocumentLoader.load(from: rebundled)
		guard case let .presentation(presentation) = loaded.payload else { Issue.record("Expected presentation payload"); return }

		#expect(try loaded.payload.serializedData().contains([0xA0, 0x06, 0x01]))
		#expect(PresentationDocument(presentation: presentation).orderedCues.map(\.name) == ["Slide 1", "Slide 2", "Slide 2 Copy"])
		#expect(Set(presentation.cues.map(\.uuid.string)).count == presentation.cues.count)
		#expect(presentation.cues[1].actions[0].uuid != presentation.cues[2].actions[0].uuid)
		let mediaURL = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media.url
		#expect(mediaURL.relativePath == "roundtrip.png")
		#expect(loaded.archiveEntries.contains("roundtrip.png"))
	}

	@Test
	func editsPresentationBundlesWithoutRewritingExistingMediaAndIncludesNewMedia() throws {
		let directory = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let existingMedia = directory.appendingPathComponent("shared.png")
		try writeArchivePNG(to: existingMedia)
		let existingMediaData = try Data(contentsOf: existingMedia)
		let source = directory.appendingPathComponent("Editable.pro")
		try writePresentation(with: [existingMedia], to: source)
		let archive = try DocumentArchive.bundle(source, to: directory.appendingPathComponent("Editable.probundle"))
		let before = try DocumentLoader.load(from: archive)
		guard case let .presentation(beforePresentation) = before.payload else {
			Issue.record("Expected a presentation")
			return
		}
		let existingReference = beforePresentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media.url

		let replacementMedia = directory.appendingPathComponent("new/shared.png")
		try FileManager.default.createDirectory(at: replacementMedia.deletingLastPathComponent(), withIntermediateDirectories: true)
		try writeArchivePNG(to: replacementMedia, width: 2)
		let replacementMediaData = try Data(contentsOf: replacementMedia)
		let session = try DocumentEditSession.open(archive)
		guard case var .presentation(presentation) = session.document.payload else {
			Issue.record("Expected a presentation")
			return
		}
		try DocumentEditor.addElement(
			to: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
			name: "New media",
			bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
			color: DocumentEditor.color(hex: "#FFFFFF"),
		)
		try DocumentEditor.setMedia(
			in: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=1]/element"),
			sourceURL: replacementMedia,
		)
		presentation.name = "Edited bundle"
		session.document.payload = .presentation(presentation)
		try session.write(to: archive, replace: true)

		let after = try DocumentLoader.load(from: archive)
		guard case let .presentation(afterPresentation) = after.payload else {
			Issue.record("Expected a presentation")
			return
		}
		#expect(afterPresentation.name == "Edited bundle")
		let elements = afterPresentation.cues[0].actions[0].slide.presentation.baseSlide.elements
		#expect(elements[0].element.fill.media.url == existingReference)
		#expect(elements[1].element.fill.media.url.relativePath == "shared-1.png")
		let expanded = try DocumentArchive.expand(archive, to: directory.appendingPathComponent("expanded-edited"))
		#expect(try Data(contentsOf: expanded.appendingPathComponent("shared.png")) == existingMediaData)
		#expect(try Data(contentsOf: expanded.appendingPathComponent("shared-1.png")) == replacementMediaData)
	}

	@Test
	func archiveTemplateMediaMaterializationHonorsEntrySizeLimits() throws {
		let directory = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = directory.appendingPathComponent("Limited.pro")
		try writePresentation(with: [], to: source)
		let archive = try DocumentArchive.bundle(
			source,
			to: directory.appendingPathComponent("Limited.probundle"),
		)
		let originalArchive = try Data(contentsOf: archive)
		let templateMedia = directory.appendingPathComponent("template.bin")
		try Data(repeating: 0xA5, count: 64 * 1024).write(to: templateMedia)
		let output = directory.appendingPathComponent("Limited Output.probundle")
		var limits = ArchiveLimits.default
		limits.maximumEntrySize = 32 * 1024

		let session = try DocumentEditSession.open(archive, archiveLimits: limits)
		guard case var .presentation(presentation) = session.document.payload else {
			Issue.record("Expected a presentation")
			return
		}
		var action = Rv_Data_Action()
		action.uuid.string = "TEMPLATE-MEDIA-ACTION"
		action.type = .media
		action.media.element.uuid.string = "TEMPLATE-MEDIA"
		action.media.element.url.absoluteString = templateMedia.absoluteString
		presentation.cues[0].actions.append(action)
		session.document.payload = .presentation(presentation)

		do {
			try session.write(
				to: output,
				materializingTemplateMediaURLs: [templateMedia.absoluteString],
			)
			Issue.record("Expected the template asset to exceed the archive entry-size limit")
		} catch let error as ArchiveError {
			expectNoDifference(
				error,
				.entrySizeLimitExceeded(
					entry: "template.bin",
					size: UInt64(64 * 1024),
					limit: UInt64(32 * 1024),
				),
			)
		}
		#expect(!FileManager.default.fileExists(atPath: output.path))
		#expect(try Data(contentsOf: archive) == originalArchive)
	}

	@Test
	func editsPlaylistBundlesWhilePreservingEmbeddedPresentationsAndAssets() throws {
		let directory = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = fixtureURL("ProPresenter/ReferenceSlides.proPlaylist")
		let output = directory.appendingPathComponent("Edited.proPlaylist")
		let before = try DocumentLoader.load(from: source)
		let session = try DocumentEditSession.open(source)
		guard case var .playlist(playlist) = session.document.payload else {
			Issue.record("Expected a playlist")
			return
		}
		playlist.rootNode.name = "Edited playlist"
		session.document.payload = .playlist(playlist)
		try session.write(to: output)

		let originalDirectory = try DocumentArchive.expand(source, to: directory.appendingPathComponent("original-playlist"))
		let editedDirectory = try DocumentArchive.expand(output, to: directory.appendingPathComponent("edited-playlist"))
		let originalFiles = try FileManager.default.subpathsOfDirectory(atPath: originalDirectory.path)
		for relativePath in originalFiles where URL(fileURLWithPath: relativePath).lastPathComponent != "data" {
			let originalFile = originalDirectory.appendingPathComponent(relativePath)
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: originalFile.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
				continue
			}
			#expect(
				try Data(contentsOf: originalFile) == Data(contentsOf: editedDirectory.appendingPathComponent(relativePath)),
			)
		}
		let edited = try DocumentLoader.load(from: output)
		#expect(Set(edited.archiveEntries) == Set(before.archiveEntries))
		guard case let .playlist(editedPlaylist) = edited.payload else {
			Issue.record("Expected a playlist")
			return
		}
		#expect(editedPlaylist.rootNode.name == "Edited playlist")
	}

	@Test
	func editsThemeBundlesWhilePreservingOtherThemeDocuments() throws {
		let directory = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = repositoryURL("skills/pro-crud/assets/themes/ProCRUD Design System.proTheme")
		let output = directory.appendingPathComponent("Edited.proTheme")
		let before = try DocumentLoader.load(from: source)
		let session = try DocumentEditSession.open(source)
		guard case var .theme(theme) = session.document.payload else {
			Issue.record("Expected a theme")
			return
		}
		DocumentEditor.addTemplate(to: &theme, name: "Added directly")
		session.document.payload = .theme(theme)
		try session.write(to: output)

		let after = try DocumentLoader.load(from: output)
		#expect(after.themeEntries[0].document.slides.count == before.themeEntries[0].document.slides.count + 1)
		#expect(after.themeEntries[0].document.slides.last?.name == "Added directly")
		#expect(try after.themeEntries.dropFirst().map { try $0.document.serializedData() } == before.themeEntries.dropFirst().map { try $0.document.serializedData() })
	}

	@Test
	func archiveEditCannotChangeDocumentKind() throws {
		let directory = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = directory.appendingPathComponent("Kind.pro")
		try writePresentation(with: [], to: source)
		let archive = try DocumentArchive.bundle(source, to: directory.appendingPathComponent("Kind.probundle"))
		let output = directory.appendingPathComponent("Changed.probundle")

		let session = try DocumentEditSession.open(archive)
		session.document.payload = .playlist(DocumentFactory.playlist(name: "Changed"))
		#expect(throws: ArchiveError.self) {
			try session.write(to: output)
		}
		#expect(!FileManager.default.fileExists(atPath: output.path))
	}

	@Test
	func archiveEditRejectsHiddenNewMedia() throws {
		let directory = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = directory.appendingPathComponent("Hidden.pro")
		try writePresentation(with: [], to: source)
		let archive = try DocumentArchive.bundle(source, to: directory.appendingPathComponent("Hidden.probundle"))
		let hiddenMedia = directory.appendingPathComponent(".hidden.png")
		try writeArchivePNG(to: hiddenMedia)
		let output = directory.appendingPathComponent("Hidden Edited.probundle")

		let session = try DocumentEditSession.open(archive)
		try addMediaReference(hiddenMedia, to: session)
		#expect(throws: ArchiveError.self) {
			try session.write(to: output)
		}
		#expect(!FileManager.default.fileExists(atPath: output.path))
	}

	@Test
	func archiveEditRejectsSymbolicLinkNewMedia() throws {
		let directory = try archiveTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = directory.appendingPathComponent("Symlink.pro")
		try writePresentation(with: [], to: source)
		let archive = try DocumentArchive.bundle(source, to: directory.appendingPathComponent("Symlink.probundle"))
		let media = directory.appendingPathComponent("target.png")
		let symbolicLink = directory.appendingPathComponent("linked.png")
		try writeArchivePNG(to: media)
		try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: media)
		let output = directory.appendingPathComponent("Symlink Edited.probundle")

		let session = try DocumentEditSession.open(archive)
		try addMediaReference(symbolicLink, to: session)
		#expect(throws: ArchiveError.self) {
			try session.write(to: output)
		}
		#expect(!FileManager.default.fileExists(atPath: output.path))
	}

	private func addMediaReference(_ sourceURL: URL, to session: DocumentEditSession) throws {
		guard case var .presentation(presentation) = session.document.payload else {
			Issue.record("Expected a presentation")
			return
		}
		try DocumentEditor.addElement(
			to: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
			name: "New media",
			bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
			color: DocumentEditor.color(hex: "#FFFFFF"),
		)
		var media = Rv_Data_Media()
		media.uuid.string = UUID().uuidString.uppercased()
		media.url.absoluteString = sourceURL.absoluteString
		media.metadata.format = "png"
		try DocumentEditor.setMedia(
			in: &presentation,
			at: ComponentPath(
				"/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element",
			),
			to: media,
		)
		session.document.payload = .presentation(presentation)
	}

	private func writePresentation(with mediaURLs: [URL], to output: URL) throws {
		var presentation = DocumentFactory.presentation(name: "Media")
		for (index, source) in mediaURLs.enumerated() {
			try DocumentEditor.addElement(
				to: &presentation,
				at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
				name: "Media \(index)",
				bounds: CGRect(x: 100 + index * 300, y: 100, width: 200, height: 200),
				color: DocumentEditor.color(hex: "#FFFFFF"),
			)
			if FileManager.default.fileExists(atPath: source.path) {
				try DocumentEditor.setMedia(
					in: &presentation,
					at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=\(index)]/element"),
					sourceURL: source,
				)
			} else {
				var action = presentation.cues[0].actions[0]
				var slide = action.slide.presentation
				var element = slide.baseSlide.elements[index].element
				var media = Rv_Data_Media()
				media.url.absoluteString = source.absoluteString
				element.fill.enable = true
				element.fill.media = media
				slide.baseSlide.elements[index].element = element
				action.slide.presentation = slide
				presentation.cues[0].actions[0] = action
			}
		}
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .presentation(presentation), origin: .raw(output)),
			to: output,
		)
	}

	private func replaceFirstMediaURL(
		in presentationURL: URL,
		with update: (inout Rv_Data_URL) -> Void,
	) throws {
		var presentation = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: presentationURL))
		var action = presentation.cues[0].actions[0]
		var slide = action.slide.presentation
		var element = slide.baseSlide.elements[0].element
		var media = element.fill.media
		update(&media.url)
		element.fill.media = media
		slide.baseSlide.elements[0].element = element
		action.slide.presentation = slide
		presentation.cues[0].actions[0] = action
		try presentation.serializedData().write(to: presentationURL, options: .atomic)
	}
}

private func archiveTemporaryDirectory() throws -> URL {
	let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProCRUDArchiveTests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	return directory
}

private func writeArchivePNG(to url: URL, width: Int = 1, height: Int = 1) throws {
	try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
	let bitmap = try #require(NSBitmapImageRep(
		bitmapDataPlanes: nil,
		pixelsWide: width,
		pixelsHigh: height,
		bitsPerSample: 8,
		samplesPerPixel: 4,
		hasAlpha: true,
		isPlanar: false,
		colorSpaceName: .deviceRGB,
		bytesPerRow: 0,
		bitsPerPixel: 0,
	))
	let data = try #require(bitmap.representation(using: .png, properties: [:]))
	try data.write(to: url)
}
