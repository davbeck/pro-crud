import AppKit
import CustomDump
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite(
	.timeLimit(.minutes(1)),
)
struct DocumentModelTests {
	@Test
	func detectsAndRoundTripsEachRawRootType() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let presentation = DocumentFactory.presentation(name: "Presentation")
		let presentationURL = directory.appendingPathComponent("Test.pro")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .presentation(presentation), origin: .raw(presentationURL)),
			to: presentationURL,
		)
		let loadedPresentation = try DocumentLoader.load(from: presentationURL)
		#expect(loadedPresentation.kind == .presentation)

		var theme = DocumentFactory.theme()
		DocumentEditor.addTemplate(to: &theme, name: "Template")
		let themeURL = directory.appendingPathComponent("Theme")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .theme(theme), origin: .raw(themeURL)),
			to: themeURL,
		)
		let loadedTheme = try DocumentLoader.load(from: themeURL)
		#expect(loadedTheme.kind == .theme)

		let playlist = DocumentFactory.playlist(name: "Playlist")
		let playlistURL = directory.appendingPathComponent("data")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .playlist(playlist), origin: .raw(playlistURL)),
			to: playlistURL,
		)
		let loadedPlaylist = try DocumentLoader.load(from: playlistURL)
		#expect(loadedPlaylist.kind == .playlist)
	}

	@Test
	func loadsAndWritesLiveWorkspacePlaylistFiles() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let playlist = DocumentFactory.playlist(name: "Live playlist")
		for name in ["Library", "Media", "Audio"] {
			let url = directory.appendingPathComponent(name)
			try playlist.serializedData().write(to: url)
			let loaded = try DocumentLoader.load(from: url)
			#expect(loaded.kind == .playlist)
			try DocumentWriter.writeRaw(loaded, to: url, replace: true)
			#expect(try DocumentLoader.load(from: url).kind == .playlist)
		}
	}

	@Test
	func createsTheNativePresentationPlaylistHierarchy() {
		let playlist = DocumentFactory.playlist(name: "Sunday Service")

		#expect(playlist.type == .presentation)
		#expect(playlist.rootNode.name == "PLAYLIST")
		#expect(playlist.rootNode.playlists.playlists.count == 1)
		#expect(playlist.rootNode.playlists.playlists[0].name == "Sunday Service")
		#expect(playlist.rootNode.playlists.playlists[0].items.items.isEmpty)
		#expect(playlist.liveVideoPlaylist.name == "Video Input")
		#expect(playlist.downloadsPlaylist.name == "Downloads")
	}

	@Test
	func rejectsWireCompatiblePayloadsWithTheWrongRootType() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let disguisedTheme = directory.appendingPathComponent("Disguised.pro")
		try DocumentFactory.theme().serializedData().write(to: disguisedTheme)

		#expect(throws: DocumentLoadError.self) {
			_ = try DocumentLoader.load(from: disguisedTheme)
		}
		#expect(throws: DocumentLoadError.self) {
			_ = try DocumentArchive.bundle(
				disguisedTheme,
				to: directory.appendingPathComponent("Disguised.probundle"),
			)
		}

		let disguisedPlaylist = directory.appendingPathComponent("Theme")
		try DocumentFactory.playlist(name: "Disguised").serializedData().write(to: disguisedPlaylist)
		#expect(throws: DocumentLoadError.self) {
			_ = try DocumentLoader.load(from: disguisedPlaylist)
		}
	}

	@Test
	func rawWriterRetainsTheDocumentNamingContract() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let disguisedPlaylist = directory.appendingPathComponent("Playlist.pro")
		let document = ProPresenterDocument(
			payload: .playlist(DocumentFactory.playlist(name: "Playlist")),
			origin: .raw(directory.appendingPathComponent("data")),
		)

		#expect(throws: DocumentLoadError.self) {
			try DocumentWriter.writeRaw(document, to: disguisedPlaylist)
		}
		#expect(!FileManager.default.fileExists(atPath: disguisedPlaylist.path))
	}

	@Test
	func loadsMultiThemeWorkspacesAndArchives() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		for name in ["First", "Second"] {
			var theme = DocumentFactory.theme()
			DocumentEditor.addTemplate(to: &theme, name: "\(name) Template")
			let url = directory.appendingPathComponent("\(name)/Theme")
			try DocumentWriter.writeRaw(
				ProPresenterDocument(payload: .theme(theme), origin: .raw(url)),
				to: url,
			)
		}

		let workspace = try DocumentLoader.load(from: directory)
		expectNoDifference(workspace.themeEntries.map(\.relativePath), ["First/Theme", "Second/Theme"])

		let archiveURL = directory.deletingLastPathComponent().appendingPathComponent("Multi.proTheme")
		defer { try? FileManager.default.removeItem(at: archiveURL) }
		_ = try DocumentArchive.bundle(directory, to: archiveURL)
		let archive = try DocumentLoader.load(from: archiveURL)
		expectNoDifference(archive.themeEntries.map(\.relativePath), ["First/Theme", "Second/Theme"])

		let renderInputs = try PresentationLoader.loadPresentations(from: archiveURL)
		expectNoDifference(renderInputs.map(\.sourceName), ["First", "Second"])
		expectNoDifference(renderInputs.map { $0.document.orderedCues.map(\.name) }, [["First Template"], ["Second Template"]])
		let allUsesOutputSubdirectory = renderInputs.allSatisfy(\.usesOutputSubdirectory)
		#expect(allUsesOutputSubdirectory)
	}

	@Test
	func playlistRenderingInputsFollowTypedItemOrderAndIgnoreUnreferencedFiles() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let presentations = ["First", "Second", "Unreferenced"]
		var presentationURLs: [String: URL] = [:]
		for name in presentations {
			let url = directory.appendingPathComponent("\(name).pro")
			presentationURLs[name] = url
			try DocumentWriter.writeRaw(
				ProPresenterDocument(
					payload: .presentation(DocumentFactory.presentation(name: name)),
					origin: .raw(url),
				),
				to: url,
			)
		}
		var playlist = DocumentFactory.playlist(name: "Order")
		try DocumentEditor.addPlaylistItem(
			to: &playlist,
			at: ComponentPath("/root_node"),
			type: "presentation",
			name: "Second",
			documentURL: presentationURLs["Second"],
		)
		try DocumentEditor.addPlaylistItem(
			to: &playlist,
			at: ComponentPath("/root_node"),
			type: "presentation",
			name: "First",
			documentURL: presentationURLs["First"],
		)
		let playlistURL = directory.appendingPathComponent("data")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .playlist(playlist), origin: .raw(playlistURL)),
			to: playlistURL,
		)

		let loaded = try PresentationLoader.loadPresentations(from: directory)
		expectNoDifference(loaded.map(\.document.presentation.name), ["Second", "First"])
		expectNoDifference(loaded.map(\.sourceName), ["Second", "First"])
		let allUsesOutputSubdirectory = loaded.allSatisfy(\.usesOutputSubdirectory)
		#expect(allUsesOutputSubdirectory)
	}

	@Test
	func playlistRenderingInputsKeepPerItemArrangementSelections() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		var presentation = DocumentFactory.presentation(name: "Shared Song")
		let group = try ComponentPath("/cue_groups[index=0]")
		let shortUUID = try DocumentEditor.addArrangement(
			to: &presentation,
			name: "Short",
			groupPaths: [group],
		)
		let repeatUUID = try DocumentEditor.addArrangement(
			to: &presentation,
			name: "Repeat",
			groupPaths: [group, group],
		)
		let presentationURL = directory.appendingPathComponent("Shared Song.pro")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .presentation(presentation), origin: .raw(presentationURL)),
			to: presentationURL,
		)

		var playlist = DocumentFactory.playlist(name: "Services")
		for name in ["Early", "Late"] {
			try DocumentEditor.addPlaylistItem(
				to: &playlist,
				at: ComponentPath("/root_node"),
				type: "presentation",
				name: name,
				documentURL: presentationURL,
			)
		}
		playlist.rootNode.playlists.playlists[0].items.items[0].presentation.arrangement.string = shortUUID
		playlist.rootNode.playlists.playlists[0].items.items[1].presentation.arrangement.string = repeatUUID
		let playlistURL = directory.appendingPathComponent("data")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .playlist(playlist), origin: .raw(playlistURL)),
			to: playlistURL,
		)

		let loaded = try PresentationLoader.loadPresentations(from: directory)
		expectNoDifference(loaded.map(\.document.arrangementSelection), [.uuid(shortUUID), .uuid(repeatUUID)])
		try expectNoDifference(
			loaded.map { try $0.document.cueOccurrences().map(\.cue.name) },
			[["Slide 1"], ["Slide 1", "Slide 1"]],
		)
		#expect(!loaded[0].document.presentation.hasSelectedArrangement)
		#expect(!loaded[1].document.presentation.hasSelectedArrangement)
	}

	@Test
	func preservesUnknownProtobufFields() throws {
		let presentation = DocumentFactory.presentation(name: "Unknown fields")
		var bytes = try presentation.serializedData()
		bytes.append(contentsOf: [0xA0, 0x06, 0x01]) // field 100, varint value 1

		let decoded = try DocumentLoader.decode(bytes, as: .presentation, location: "memory")
		let encoded = try decoded.serializedData()
		#expect(encoded.contains([0xA0, 0x06, 0x01]))
	}

	@Test
	func resolvesCanonicalPresentationComponentPaths() throws {
		let document = try componentPathFixture()
		let selection = try ComponentResolver.resolve(
			ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text"),
			in: document,
		)

		#expect(selection.canonicalPath.contains("/cues[uuid="))
		#expect(selection.protoMessageName == "rv.data.Graphics.Text")
	}

	@Test
	func resolvesSchemaFieldsAndDirectScalarSelectors() throws {
		let presentation = DocumentFactory.presentation(name: "Paths")
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Paths.pro")),
		)

		let cueGroup = try ComponentResolver.resolve(ComponentPath("/cue_groups[index=0]"), in: document)
		#expect(cueGroup.protoMessageName == "rv.data.Presentation.CueGroup")
		#expect(cueGroup.canonicalPath.contains("/cue_groups[uuid="))

		let cue = try ComponentResolver.resolve(ComponentPath("/cues[isEnabled=true]"), in: document)
		#expect(cue.protoMessageName == "rv.data.Cue")
		#expect(cue.jsonObject["name"] as? String == "Slide 1")
	}

	@Test
	func presentationCueIndicesUseDisplayOrder() throws {
		var presentation = DocumentFactory.presentation(name: "Display order")
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		presentation.cueGroups[0].cueIdentifiers = [
			presentation.cues[2].uuid,
			presentation.cues[0].uuid,
			presentation.cues[1].uuid,
		]
		var document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/DisplayOrder.pro")),
		)

		let selection = try ComponentResolver.resolve(ComponentPath("/cues[index=0]"), in: document)
		#expect(selection.jsonObject["name"] as? String == "Slide 3")

		try DocumentEditor.patch(
			&document,
			at: ComponentPath("/cues[index=1]"),
			jsonData: Data("{\"name\":\"First displayed\"}".utf8),
		)
		guard case var .presentation(edited) = document.payload else {
			Issue.record("Expected presentation payload")
			return
		}
		#expect(edited.cues.map(\.name) == ["First displayed", "Slide 2", "Slide 3"])

		try DocumentEditor.renameCue(in: &edited, at: ComponentPath("/cues[index=0]"), to: "Third stored")
		#expect(edited.cues.map(\.name) == ["First displayed", "Slide 2", "Third stored"])
	}

	@Test
	func canonicalCuePathsUseNativeIndicesForMissingIdentities() throws {
		var presentation = DocumentFactory.presentation(name: "Missing cue identity")
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		presentation.cues[0].uuid.string = ""
		presentation.cueGroups[0].cueIdentifiers = [
			presentation.cues[2].uuid,
			presentation.cues[1].uuid,
		]
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/MissingCueIdentity.pro")),
		)

		let selection = try ComponentResolver.resolve(ComponentPath("/cues[index=2]"), in: document)
		#expect(selection.jsonObject["name"] as? String == "Slide 1")
		#expect(selection.canonicalPath == "/cues[index=2]")
		let roundTrip = try ComponentResolver.resolve(ComponentPath(selection.canonicalPath), in: document)
		#expect(roundTrip.jsonObject["name"] as? String == "Slide 1")
	}

	@Test
	func canonicalCuePathsUseNativeIndicesForDuplicateIdentities() throws {
		var presentation = DocumentFactory.presentation(name: "Duplicate cue identity")
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		presentation.cues[2].uuid = presentation.cues[0].uuid
		presentation.cueGroups[0].cueIdentifiers = [
			presentation.cues[1].uuid,
			presentation.cues[0].uuid,
			presentation.cues[2].uuid,
		]
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/DuplicateCueIdentity.pro")),
		)

		for (nativeIndex, expectedName) in ["Slide 2", "Slide 1", "Slide 3"].enumerated() {
			let selection = try ComponentResolver.resolve(ComponentPath("/cues[index=\(nativeIndex)]"), in: document)
			#expect(selection.jsonObject["name"] as? String == expectedName)
			let expectedPath = try ComponentPath(
				nativeIndex == 0
					? "/cues[uuid=\(presentation.cues[1].uuid.string)]"
					: "/cues[index=\(nativeIndex)]",
			).description
			#expect(selection.canonicalPath == expectedPath)
			let roundTrip = try ComponentResolver.resolve(ComponentPath(selection.canonicalPath), in: document)
			#expect(roundTrip.jsonObject["name"] as? String == expectedName)
		}
	}

	@Test
	func effectiveRenderingPathsFallBackForDuplicateNestedIdentities() throws {
		var presentation = DocumentFactory.presentation(name: "Duplicate nested identities")
		try DocumentEditor.addAction(
			in: &presentation,
			to: ComponentPath("/cues[index=0]"),
			type: "media",
			name: "Media",
		)
		presentation.cues[0].actions[1].uuid = presentation.cues[0].actions[0].uuid
		let slidePath = try ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide")
		try DocumentEditor.addElement(
			to: &presentation,
			at: slidePath,
			name: "First",
			bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
			color: DocumentEditor.color(hex: "#000000"),
		)
		try DocumentEditor.addElement(
			to: &presentation,
			at: slidePath,
			name: "Second",
			bounds: CGRect(x: 100, y: 0, width: 100, height: 100),
			color: DocumentEditor.color(hex: "#FFFFFF"),
		)
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[1].element.uuid =
			presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.uuid
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/DuplicateNestedIdentities.pro")),
		)

		let rendering = try PresentationRenderer(
			document: PresentationDocument(presentation: presentation),
		).effectiveRendering()
		let paths = try #require(rendering.slides.first).layers.map(\.componentPath)
		#expect(paths.contains { $0.contains("/actions[index=1]") })
		#expect(paths.contains { $0.contains("/actions[index=0]") && $0.contains("/elements[index=0]") })
		#expect(paths.contains { $0.contains("/actions[index=0]") && $0.contains("/elements[index=1]") })
		for path in paths {
			let selection = try ComponentResolver.resolve(ComponentPath(path), in: document)
			#expect(selection.canonicalPath == path)
		}
	}

	@Test
	func reportsCandidatesForUnmatchedComponentSelectors() throws {
		let document = try componentPathFixture()
		do {
			_ = try ComponentResolver.resolve(ComponentPath("/cues[index=999]"), in: document)
			Issue.record("Expected the out-of-range selector to fail")
		} catch let error as ComponentPathError {
			#expect(error.description.contains("/cues[uuid="))
		}

		var presentation = DocumentFactory.presentation(name: "Ambiguous")
		var duplicate = presentation.cues[0]
		duplicate.uuid.string = UUID().uuidString
		presentation.cues.append(duplicate)
		let ambiguous = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Ambiguous.pro")),
		)
		do {
			_ = try ComponentResolver.resolve(ComponentPath("/cues[name=\"Slide 1\"]"), in: ambiguous)
			Issue.record("Expected the duplicate name selector to fail")
		} catch let error as ComponentPathError {
			let candidates = error.description.components(separatedBy: "/cues[uuid=").count - 1
			#expect(candidates == 2)
		}
	}

	@Test
	func rootPatchPreservesUnknownFields() throws {
		let presentation = DocumentFactory.presentation(name: "Before")
		var bytes = try presentation.serializedData()
		bytes.append(contentsOf: [0xA0, 0x06, 0x01])
		var document = try ProPresenterDocument(
			payload: DocumentLoader.decode(bytes, as: .presentation, location: "memory"),
			origin: .raw(URL(fileURLWithPath: "/tmp/Test.pro")),
		)

		try DocumentEditor.patch(&document, at: ComponentPath("/"), jsonData: Data("{\"name\":\"After\"}".utf8))
		guard case let .presentation(patched) = document.payload else { Issue.record("Expected presentation payload"); return }
		#expect(patched.name == "After")
		#expect(try document.payload.serializedData().contains([0xA0, 0x06, 0x01]))
	}

	@Test
	func patchClearsFieldsAndReplacesRepeatedFieldsWithoutDroppingUnknownData() throws {
		let presentation = DocumentFactory.presentation(name: "Before")
		var bytes = try presentation.serializedData()
		bytes.append(contentsOf: [0xA0, 0x06, 0x01])
		var document = try ProPresenterDocument(
			payload: DocumentLoader.decode(bytes, as: .presentation, location: "memory"),
			origin: .raw(URL(fileURLWithPath: "/tmp/Test.pro")),
		)

		try DocumentEditor.patch(&document, at: ComponentPath("/"), jsonData: Data("{\"name\":null,\"cues\":[]}".utf8))

		guard case let .presentation(patched) = document.payload else { Issue.record("Expected presentation payload"); return }
		#expect(patched.name.isEmpty)
		#expect(patched.cues.isEmpty)
		#expect(try document.payload.serializedData().contains([0xA0, 0x06, 0x01]))
	}

	@Test
	func componentPatchCanReplaceAnActionOneof() throws {
		let presentation = DocumentFactory.presentation(name: "Action")
		var document = ProPresenterDocument(payload: .presentation(presentation), origin: .raw(URL(fileURLWithPath: "/tmp/Test.pro")))

		try DocumentEditor.patch(
			&document,
			at: ComponentPath("/cues[index=0]/actions[index=0]"),
			jsonData: Data("{\"type\":\"ACTION_TYPE_TIMER\",\"timer\":{}}".utf8),
		)

		guard case let .presentation(patched) = document.payload else { Issue.record("Expected presentation payload"); return }
		let action = patched.cues[0].actions[0]
		#expect(action.type == .timer)
		if case .timer? = action.actionTypeData {
		} else {
			Issue.record("Expected timer action payload")
		}
	}

	@Test
	func setMediaReplacesCompleteIdentityAtEverySupportedTarget() throws {
		var canonical = Rv_Data_Media()
		canonical.uuid.string = "PLAYLIST-MEDIA-UUID"
		canonical.url.absoluteString = "file:///canonical.png"
		canonical.metadata.artist = "Canonical Artist"
		canonical.image.drawing.naturalSize.width = 1920
		canonical.image.drawing.naturalSize.height = 1080
		var canonicalBytes = try canonical.serializedData()
		canonicalBytes.append(contentsOf: [0xA0, 0x06, 0x01])
		canonical = try Rv_Data_Media(serializedBytes: canonicalBytes)

		var presentation = DocumentFactory.presentation(name: "Media targets")
		try DocumentEditor.addElement(
			to: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
			name: "Media fill",
			bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
			color: DocumentEditor.color(hex: "#000000"),
		)
		try DocumentEditor.addAction(in: &presentation, to: ComponentPath("/cues[index=0]"), type: "media", name: "Media")

		try DocumentEditor.setMedia(
			in: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=1]/media/element"),
			to: canonical,
		)
		try DocumentEditor.setMedia(
			in: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/fill/media"),
			to: canonical,
		)

		let actionMedia = presentation.cues[0].actions[1].media.element
		let fillMedia = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media
		for media in [actionMedia, fillMedia] {
			#expect(media.uuid.string == "PLAYLIST-MEDIA-UUID")
			#expect(media.url.absoluteString == "file:///canonical.png")
			#expect(media.metadata.artist == "Canonical Artist")
			#expect(media.image.drawing.naturalSize.width == 1920)
			#expect(try media.serializedData().contains([0xA0, 0x06, 0x01]))
		}

		var relocated = canonical
		relocated.uuid.string = "IGNORED-NEW-UUID"
		relocated.url.absoluteString = "file:///relocated.png"
		try DocumentEditor.setMedia(
			in: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element"),
			to: relocated,
			preserveUUID: true,
		)
		let preserved = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media
		#expect(preserved.uuid.string == "PLAYLIST-MEDIA-UUID")
		#expect(preserved.url.absoluteString == "file:///relocated.png")

		let actionPath = try ComponentPath("/cues[index=0]/actions[index=1]/media/element")
		try DocumentEditor.setMedia(
			in: &presentation,
			at: actionPath,
			sourceURL: packageRootURL.appendingPathComponent("Fixtures/ProPresenter/Media/ImageSample.png"),
		)
		let freshUUID = presentation.cues[0].actions[1].media.element.uuid.string
		#expect(!freshUUID.isEmpty)
		#expect(freshUUID != "PLAYLIST-MEDIA-UUID")
		try DocumentEditor.setMedia(
			in: &presentation,
			at: actionPath,
			sourceURL: packageRootURL.appendingPathComponent("Fixtures/ProPresenter/Media/LogoTransparent.png"),
			preserveUUID: true,
		)
		#expect(presentation.cues[0].actions[1].media.element.uuid.string == freshUUID)
	}

	@Test
	func setMediaRoutesThemeTargetsThroughDocument() throws {
		var theme = DocumentFactory.theme()
		DocumentEditor.addTemplate(to: &theme, name: "Series")
		var existingMedia = Rv_Data_Media()
		existingMedia.uuid.string = "EXISTING-THEME-MEDIA"
		existingMedia.url.absoluteString = "file:///existing.png"
		var element = Rv_Data_Graphics.Element()
		element.uuid.string = "THEME-ELEMENT"
		element.name = "Background"
		element.fill.enable = true
		element.fill.media = existingMedia
		var slideElement = Rv_Data_Slide.Element()
		slideElement.element = element
		theme.slides[0].baseSlide.elements = [slideElement]
		let templateUUID = theme.slides[0].baseSlide.uuid.string
		var document = ProPresenterDocument(
			payload: .theme(theme),
			origin: .raw(URL(fileURLWithPath: "/tmp/Theme")),
		)

		var canonical = Rv_Data_Media()
		canonical.uuid.string = "PLAYLIST-MEDIA"
		canonical.url.absoluteString = "file:///series.png"
		canonical.metadata.artist = "Canonical Artist"
		try DocumentEditor.setMedia(
			&document,
			at: ComponentPath("/slides[name=Series]/base_slide/elements[name=Background]/element/fill/media"),
			to: canonical,
		)

		guard case let .theme(replacedTheme) = document.payload else {
			Issue.record("Expected a theme document")
			return
		}
		let replaced = replacedTheme.slides[0].baseSlide.elements[0].element.fill.media
		expectNoDifference(replaced.uuid.string, "PLAYLIST-MEDIA")
		expectNoDifference(replaced.url.absoluteString, "file:///series.png")
		expectNoDifference(replaced.metadata.artist, "Canonical Artist")
		let selection = try ComponentResolver.resolve(
			ComponentPath("/slides[uuid=\(templateUUID)]/base_slide/elements[uuid=THEME-ELEMENT]/element/fill/media"),
			in: document,
		)
		#expect(selection.protoMessageName == "rv.data.Media")

		var relocated = canonical
		relocated.uuid.string = "IGNORED-MEDIA"
		relocated.url.absoluteString = "file:///relocated.png"
		try DocumentEditor.setMedia(
			&document,
			at: ComponentPath("/slides[uuid=\(templateUUID)]/base_slide/elements[uuid=THEME-ELEMENT]/element"),
			to: relocated,
			preserveUUID: true,
		)

		guard case let .theme(relocatedTheme) = document.payload else {
			Issue.record("Expected a theme document")
			return
		}
		let preserved = relocatedTheme.slides[0].baseSlide.elements[0].element.fill.media
		expectNoDifference(preserved.uuid.string, "PLAYLIST-MEDIA")
		expectNoDifference(preserved.url.absoluteString, "file:///relocated.png")
	}

	@Test
	func selectsCanonicalMediaFromNamedPlaylistItem() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let sourceURL = directory.appendingPathComponent("data")
		var playlist = DocumentFactory.playlist(name: "Media library")
		var media = Rv_Data_Media()
		media.uuid.string = "CANONICAL-ID"
		media.url.absoluteString = "file:///Media/Assets/Welcome.png"
		media.metadata.format = "png"
		media.image.drawing.naturalSize.width = 1280
		var action = Rv_Data_Action()
		action.type = .media
		action.media.element = media
		var cue = Rv_Data_Cue()
		cue.actions = [action]
		var item = Rv_Data_PlaylistItem()
		item.name = "CV_Welcome"
		item.cue = cue
		playlist.rootNode.playlists.playlists[0].name = "2026 Values"
		playlist.rootNode.playlists.playlists[0].items.items = [item]
		try playlist.serializedData().write(to: sourceURL)

		let selection = try PlaylistMediaSource.select(
			from: sourceURL,
			playlist: "2026 Values",
			item: "CV_Welcome",
		)

		#expect(selection.media.uuid.string == "CANONICAL-ID")
		#expect(selection.media.metadata.format == "png")
		#expect(selection.media.image.drawing.naturalSize.width == 1280)

		let workspace = directory.appendingPathComponent("Workspace", isDirectory: true)
		let playlists = workspace.appendingPathComponent("Playlists", isDirectory: true)
		try FileManager.default.createDirectory(at: playlists, withIntermediateDirectories: true)
		try playlist.serializedData().write(to: playlists.appendingPathComponent("Media"))
		let workspaceSelection = try PlaylistMediaSource.select(
			from: workspace,
			playlist: "2026 Values",
			item: "CV_Welcome",
		)
		#expect(workspaceSelection.media.uuid.string == "CANONICAL-ID")
	}

	@Test
	func rejectsPlaylistMediaWithoutCanonicalIdentity() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let sourceURL = directory.appendingPathComponent("Media")
		var playlist = DocumentFactory.playlist(name: "Media library")
		var action = Rv_Data_Action()
		action.type = .media
		action.media.element.url.absoluteString = "file:///Media/Assets/Welcome.png"
		var cue = Rv_Data_Cue()
		cue.actions = [action]
		var item = Rv_Data_PlaylistItem()
		item.name = "CV_Welcome"
		item.cue = cue
		playlist.rootNode.playlists.playlists[0].name = "Values"
		playlist.rootNode.playlists.playlists[0].items.items = [item]
		try playlist.serializedData().write(to: sourceURL)

		#expect(throws: DocumentEditError.self) {
			_ = try PlaylistMediaSource.select(from: sourceURL, playlist: "Values", item: "CV_Welcome")
		}
	}

	@Test
	func identifiesDangerousURLOnlyMediaPatches() throws {
		var presentation = DocumentFactory.presentation(name: "Patch safety")
		try DocumentEditor.addAction(in: &presentation, to: ComponentPath("/cues[index=0]"), type: "media", name: "Media")
		var media = Rv_Data_Media()
		media.uuid.string = "EXISTING-ID"
		media.url.absoluteString = "file:///before.png"
		try DocumentEditor.setMedia(
			in: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=1]/media/element"),
			to: media,
		)
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/PatchSafety.pro")),
		)
		let mediaPath = try ComponentPath("/cues[index=0]/actions[index=1]/media/element")
		let urlPath = try ComponentPath("/cues[index=0]/actions[index=1]/media/element/url")

		#expect(try DocumentEditor.isURLOnlyMediaPatch(document, at: urlPath, jsonData: Data("{\"absoluteString\":\"file:///after.png\"}".utf8)))
		#expect(try DocumentEditor.isURLOnlyMediaPatch(document, at: mediaPath, jsonData: Data("{\"url\":{\"absoluteString\":\"file:///after.png\"}}".utf8)))
		#expect(try DocumentEditor.isURLOnlyMediaPatch(document, at: mediaPath, jsonData: Data("{\"url\":{\"absoluteString\":\"file:///after.png\"},\"metadata\":{\"format\":\"png\"}}".utf8)))
		#expect(try !DocumentEditor.isURLOnlyMediaPatch(document, at: mediaPath, jsonData: Data("{\"uuid\":{\"string\":\"NEW-ID\"},\"url\":{\"absoluteString\":\"file:///after.png\"}}".utf8)))
	}

	@Test
	func componentPatchSupportsThemeAndPlaylistDocuments() throws {
		var theme = DocumentFactory.theme()
		var template = Rv_Data_Template.Slide()
		template.name = "Before"
		theme.slides = [template]
		var themeDocument = ProPresenterDocument(payload: .theme(theme), origin: .raw(URL(fileURLWithPath: "/tmp/Theme")))
		try DocumentEditor.patch(&themeDocument, at: ComponentPath("/slides[index=0]"), jsonData: Data("{\"name\":\"After\"}".utf8))
		guard case let .theme(patchedTheme) = themeDocument.payload else { Issue.record("Expected theme payload"); return }
		#expect(patchedTheme.slides[0].name == "After")

		let playlist = DocumentFactory.playlist(name: "Before")
		var playlistDocument = ProPresenterDocument(payload: .playlist(playlist), origin: .raw(URL(fileURLWithPath: "/tmp/data")))
		try DocumentEditor.patch(&playlistDocument, at: ComponentPath("/root_node"), jsonData: Data("{\"name\":\"After\"}".utf8))
		guard case let .playlist(patchedPlaylist) = playlistDocument.payload else { Issue.record("Expected playlist payload"); return }
		#expect(patchedPlaylist.rootNode.name == "After")
	}

	@Test
	func componentPatchSupportsPlaylistItemsAndPreservesTheirUnknownFields() throws {
		var playlist = DocumentFactory.playlist(name: "Playlist")
		try DocumentEditor.addPlaylistItem(
			to: &playlist,
			at: ComponentPath("/root_node"),
			type: "header",
			name: "Before",
			documentURL: nil,
		)
		var itemData = try playlist.rootNode.playlists.playlists[0].items.items[0].serializedData()
		itemData.append(contentsOf: [0xA0, 0x06, 0x01])
		playlist.rootNode.playlists.playlists[0].items.items[0] = try Rv_Data_PlaylistItem(serializedBytes: itemData)
		var document = ProPresenterDocument(
			payload: .playlist(playlist),
			origin: .raw(URL(fileURLWithPath: "/tmp/data")),
		)

		try DocumentEditor.patch(
			&document,
			at: ComponentPath("/root_node/playlists/playlists[index=0]/items/items[index=0]"),
			jsonData: Data("{\"name\":\"After\"}".utf8),
		)

		guard case let .playlist(patched) = document.payload else { Issue.record("Expected playlist payload"); return }
		#expect(patched.rootNode.playlists.playlists[0].items.items[0].name == "After")
		#expect(try patched.rootNode.playlists.playlists[0].items.items[0].serializedData().contains([0xA0, 0x06, 0x01]))
	}

	@Test
	func componentPatchSupportsPreviouslyUnaddressableMessages() throws {
		let presentation = DocumentFactory.presentation(name: "Groups")
		var document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Groups.pro")),
		)

		try DocumentEditor.patch(
			&document,
			at: ComponentPath("/cue_groups[index=0]"),
			jsonData: Data("{\"group\":{\"name\":\"Edited Group\"}}".utf8),
		)

		guard case let .presentation(patched) = document.payload else { Issue.record("Expected presentation payload"); return }
		#expect(patched.cueGroups[0].group.name == "Edited Group")
	}

	@Test
	func structuralCueEditsKeepCueGroupOrderConsistent() throws {
		var presentation = DocumentFactory.presentation(name: "Structural")
		var arrangement = Rv_Data_Presentation.Arrangement()
		arrangement.uuid.string = UUID().uuidString
		arrangement.name = "Service"
		arrangement.groupIdentifiers = [presentation.cueGroups[0].group.uuid]
		presentation.arrangements = [arrangement]
		presentation.selectedArrangement = arrangement.uuid
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		try DocumentEditor.renameCue(in: &presentation, at: ComponentPath("/cues[index=1]"), to: "Middle")
		try DocumentEditor.duplicateCue(in: &presentation, at: ComponentPath("/cues[name=Middle]"))
		try DocumentEditor.moveCue(in: &presentation, at: ComponentPath("/cues[name=Middle Copy]"), after: ComponentPath("/cues[index=0]"))
		try DocumentEditor.removeCue(in: &presentation, at: ComponentPath("/cues[index=3]"))

		let document = PresentationDocument(presentation: presentation)
		#expect(document.orderedCues.map(\.name) == ["Slide 1", "Middle Copy", "Middle"])
		#expect(presentation.cueGroups[0].cueIdentifiers.count == presentation.cues.count)
		#expect(Set(presentation.cueGroups[0].cueIdentifiers.map(\.string)) == Set(presentation.cues.map(\.uuid.string)))
		#expect(presentation.arrangements[0].groupIdentifiers == [presentation.cueGroups[0].group.uuid])
		#expect(presentation.selectedArrangement == presentation.arrangements[0].uuid)
	}

	@Test
	func movingACueAfterItselfPreservesNativeOrder() throws {
		var presentation = DocumentFactory.presentation(name: "No-op move")
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		let identifiers = presentation.cueGroups[0].cueIdentifiers

		try DocumentEditor.moveCue(
			in: &presentation,
			at: ComponentPath("/cues[index=0]"),
			after: ComponentPath("/cues[index=0]"),
		)

		#expect(presentation.cueGroups[0].cueIdentifiers == identifiers)
		#expect(PresentationDocument(presentation: presentation).orderedCues.map(\.name) == ["Slide 1", "Slide 2"])
	}

	@Test
	func structuralEditsSupportThemeTemplatesAndPlaylistItems() throws {
		var theme = DocumentFactory.theme()
		DocumentEditor.addTemplate(to: &theme, name: "Title")
		DocumentEditor.addTemplate(to: &theme, name: "Body")
		let originalTemplateID = theme.slides[0].baseSlide.uuid
		var themeDocument = ProPresenterDocument(payload: .theme(theme), origin: .raw(URL(fileURLWithPath: "/tmp/Theme")))

		try DocumentEditor.rename(&themeDocument, at: ComponentPath("/slides[index=0]"), to: "Opening")
		try DocumentEditor.duplicate(&themeDocument, at: ComponentPath("/slides[name=Opening]"))
		try DocumentEditor.move(&themeDocument, at: ComponentPath("/slides[name=Opening Copy]"), after: ComponentPath("/slides[name=Body]"))
		guard case let .theme(editedTheme) = themeDocument.payload else { Issue.record("Expected theme payload"); return }
		#expect(editedTheme.slides.map(\.name) == ["Opening", "Body", "Opening Copy"])
		#expect(editedTheme.slides[2].baseSlide.uuid != originalTemplateID)

		var playlist = DocumentFactory.playlist(name: "Service")
		try DocumentEditor.addPlaylistItem(to: &playlist, at: ComponentPath("/root_node"), type: "header", name: "First", documentURL: nil)
		try DocumentEditor.addPlaylistItem(to: &playlist, at: ComponentPath("/root_node"), type: "header", name: "Second", documentURL: nil)
		let firstID = playlist.rootNode.playlists.playlists[0].items.items[0].uuid
		var playlistDocument = ProPresenterDocument(payload: .playlist(playlist), origin: .raw(URL(fileURLWithPath: "/tmp/data")))

		let itemPath = "/root_node/playlists/playlists[index=0]/items/items"
		try DocumentEditor.rename(&playlistDocument, at: ComponentPath("\(itemPath)[name=First]"), to: "Intro")
		try DocumentEditor.duplicate(&playlistDocument, at: ComponentPath("\(itemPath)[name=Intro]"))
		try DocumentEditor.move(&playlistDocument, at: ComponentPath("\(itemPath)[name=Intro Copy]"), after: ComponentPath("\(itemPath)[name=Second]"))
		try DocumentEditor.remove(&playlistDocument, at: ComponentPath("\(itemPath)[name=Intro]"))
		guard case let .playlist(editedPlaylist) = playlistDocument.payload else { Issue.record("Expected playlist payload"); return }
		let editedItems = editedPlaylist.rootNode.playlists.playlists[0].items.items
		#expect(editedItems.map(\.name) == ["Second", "Intro Copy"])
		#expect(editedItems[1].uuid != firstID)
	}

	@Test
	func structuralEditsFollowStoredPlaylistWrapperPaths() throws {
		var playlist = DocumentFactory.playlist(name: "Service")
		var folder = Rv_Data_Playlist()
		folder.uuid.string = UUID().uuidString
		folder.name = "Sunday"
		folder.type = .group
		var folders = Rv_Data_Playlist.PlaylistArray()
		folders.playlists = [folder]
		playlist.rootNode.playlists = folders

		let folderPath = try ComponentPath("/root_node/playlists/playlists[index=0]")
		try DocumentEditor.addPlaylistItem(to: &playlist, at: folderPath, type: "header", name: "First", documentURL: nil)
		try DocumentEditor.addPlaylistItem(to: &playlist, at: folderPath, type: "header", name: "Second", documentURL: nil)
		let firstID = playlist.rootNode.playlists.playlists[0].items.items[0].uuid
		var document = ProPresenterDocument(payload: .playlist(playlist), origin: .raw(URL(fileURLWithPath: "/tmp/data")))

		let itemsPath = "/root_node/playlists/playlists[index=0]/items/items"
		try DocumentEditor.rename(&document, at: ComponentPath("\(itemsPath)[name=First]"), to: "Intro")
		try DocumentEditor.duplicate(&document, at: ComponentPath("\(itemsPath)[name=Intro]"))
		try DocumentEditor.move(
			&document,
			at: ComponentPath("\(itemsPath)[name=Intro Copy]"),
			after: ComponentPath("\(itemsPath)[name=Second]"),
		)
		try DocumentEditor.remove(&document, at: ComponentPath("\(itemsPath)[name=Intro]"))

		guard case let .playlist(edited) = document.payload else { Issue.record("Expected playlist payload"); return }
		let items = edited.rootNode.playlists.playlists[0].items.items
		#expect(items.map(\.name) == ["Second", "Intro Copy"])
		#expect(items[1].uuid != firstID)
	}

	@Test
	func playlistMoveAcceptsEquivalentCanonicalParentPaths() throws {
		var playlist = DocumentFactory.playlist(name: "Service")
		try DocumentEditor.addPlaylistItem(to: &playlist, at: ComponentPath("/root_node"), type: "header", name: "First", documentURL: nil)
		try DocumentEditor.addPlaylistItem(to: &playlist, at: ComponentPath("/root_node"), type: "header", name: "Second", documentURL: nil)
		let playlistID = playlist.rootNode.playlists.playlists[0].uuid.string
		var document = ProPresenterDocument(
			payload: .playlist(playlist),
			origin: .raw(URL(fileURLWithPath: "/tmp/data")),
		)

		try DocumentEditor.move(
			&document,
			at: ComponentPath("/root_node/playlists/playlists[uuid=\(playlistID)]/items[index=0]"),
			after: ComponentPath("/root_node/playlists/playlists[index=0]/items/items[index=1]"),
		)

		guard case let .playlist(edited) = document.payload else {
			Issue.record("Expected playlist payload")
			return
		}
		#expect(edited.rootNode.playlists.playlists[0].items.items.map(\.name) == ["Second", "First"])
	}

	@Test
	func addingDuplicateSlideCopiesContentWithFreshIdentifiers() throws {
		var presentation = DocumentFactory.presentation(name: "Duplicate")
		try DocumentEditor.addElement(
			to: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
			name: "Accent",
			bounds: CGRect(x: 100, y: 100, width: 400, height: 200),
			color: DocumentEditor.color(hex: "#E85D4A"),
		)

		try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath("/cue_groups[index=0]"),
			duplicateCuePath: ComponentPath("/cues[index=0]"),
		)

		let original = presentation.cues[0]
		let copy = presentation.cues[1]
		#expect(copy.name == "Slide 1 Copy")
		#expect(copy.uuid != original.uuid)
		#expect(copy.actions[0].uuid != original.actions[0].uuid)
		#expect(copy.actions[0].slide.presentation.baseSlide.uuid != original.actions[0].slide.presentation.baseSlide.uuid)
		#expect(copy.actions[0].slide.presentation.baseSlide.elements[0].element.uuid != original.actions[0].slide.presentation.baseSlide.elements[0].element.uuid)
		#expect(presentation.cueGroups[0].cueIdentifiers == [original.uuid, copy.uuid])
	}

	@Test
	func addingDuplicateSlideAcceptsASlideComponentPath() throws {
		var presentation = DocumentFactory.presentation(name: "Duplicate Slide")
		try DocumentEditor.addElement(
			to: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
			name: "Accent",
			bounds: CGRect(x: 100, y: 100, width: 400, height: 200),
			color: DocumentEditor.color(hex: "#E85D4A"),
		)

		try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath("/cue_groups[index=0]"),
			duplicateCuePath: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
		)

		let original = presentation.cues[0].actions[0].slide.presentation.baseSlide
		let copy = presentation.cues[1].actions[0].slide.presentation.baseSlide
		#expect(copy.elements[0].element.name == "Accent")
		#expect(copy.uuid != original.uuid)
		#expect(copy.elements[0].element.uuid != original.elements[0].element.uuid)
	}

	@Test
	func themeTemplateSelectionAcceptsAComponentPath() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		var theme = DocumentFactory.theme()
		DocumentEditor.addTemplate(to: &theme, name: "First")
		DocumentEditor.addTemplate(to: &theme, name: "Second")
		let themeURL = directory.appendingPathComponent("Theme")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .theme(theme), origin: .raw(themeURL)),
			to: themeURL,
		)

		let selected = try ThemeTemplateSource.select(
			ThemeTemplateSource.candidates(from: themeURL),
			named: "/slides[index=1]",
		)
		#expect(selected.name == "Second")
	}

	@Test
	func themeTemplateMediaCannotEscapeItsDeclaredResourceRoot() throws {
		let directory = try temporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let themeDirectory = directory.appendingPathComponent("Scoped Theme", isDirectory: true)
		try FileManager.default.createDirectory(at: themeDirectory, withIntermediateDirectories: true)
		let outsideURL = directory.appendingPathComponent("outside.bin")
		try Data([0x01]).write(to: outsideURL)

		var theme = DocumentFactory.theme()
		DocumentEditor.addTemplate(to: &theme, name: "Scoped")
		var element = Rv_Data_Slide.Element()
		element.element.uuid.string = "SCOPED-ELEMENT"
		element.element.fill.enable = true
		element.element.fill.media.uuid.string = "SCOPED-MEDIA"
		element.element.fill.media.url.relativePath = "../outside.bin"
		theme.slides[0].baseSlide.elements = [element]
		let themeURL = themeDirectory.appendingPathComponent("Theme")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .theme(theme), origin: .raw(themeURL)),
			to: themeURL,
		)

		let candidate = try ThemeTemplateSource.select(
			ThemeTemplateSource.candidates(from: themeURL),
			named: "Scoped",
		)
		#expect(candidate.preferredAbsoluteMediaURLs.isEmpty)
		#expect(candidate.mediaWarnings.contains { $0.contains("escapes its declared resource root") })
		#expect(candidate.slide.baseSlide.elements[0].element.fill.media.url.relativePath == "../outside.bin")
	}

	@Test
	func addActionConstructsTheMatchingOneofPayload() throws {
		var presentation = DocumentFactory.presentation(name: "Actions")
		try DocumentEditor.addAction(
			in: &presentation,
			to: ComponentPath("/cues[index=0]"),
			type: "timer",
			name: "Timer",
		)

		let action = presentation.cues[0].actions.last
		#expect(action?.type == .timer)
		if case .timer? = action?.actionTypeData {
		} else {
			Issue.record("Expected a timer ActionTypeData payload")
		}
	}

	@Test
	func addsRectangularElementsWithACompleteNativePath() throws {
		var presentation = DocumentFactory.presentation(name: "Rectangle")
		try DocumentEditor.addElement(
			to: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
			name: "Accent",
			bounds: CGRect(x: 100, y: 100, width: 400, height: 200),
			color: DocumentEditor.color(hex: "#E85D4A"),
		)

		let path = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.path
		#expect(path.closed)
		#expect(path.shape.type == .rectangle)
		#expect(path.points.map(\.point.x) == [0, 1, 1, 0])
		#expect(path.points.map(\.point.y) == [0, 0, 1, 1])
		#expect(path.points.allSatisfy { $0.point == $0.q0 && $0.point == $0.q1 })
	}

	@Test
	func setTextWritesRenderableRTF() throws {
		let themeURL = packageRootURL
			.appendingPathComponent("skills/pro-crud/assets/themes/ProCRUD Design System.proTheme")
		let template = try ThemeTemplateSource.select(ThemeTemplateSource.candidates(from: themeURL), named: "ProCRUD - Streaming/Theme#0")
		var presentation = try DocumentFactory.applying(template: template.slide, to: DocumentFactory.presentation(name: "Text"))
		try DocumentEditor.setText(
			in: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text"),
			to: "Edited",
		)
		let data = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text.rtfData
		let attributed = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
		#expect(attributed.string == "Edited")
	}

	@Test
	func setTextPreservesTheElementsBaseStyle() throws {
		var presentation = DocumentFactory.presentation(name: "Styled plain text")
		try DocumentEditor.addElement(
			to: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
			name: "Title",
			bounds: CGRect(x: 100, y: 100, width: 1600, height: 400),
			color: DocumentEditor.color(hex: "#000000"),
		)
		var text = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text
		text.attributes.font.name = "AvenirNext-Heavy"
		text.attributes.font.family = "Avenir Next"
		text.attributes.font.size = 118
		text.attributes.font.bold = true
		text.attributes.textSolidFill = try DocumentEditor.color(hex: "#57D3C2")
		text.attributes.kerning = 4
		text.attributes.paragraphStyle.alignment = .right
		text.attributes.paragraphStyle.lineHeightMultiple = 1.2
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text = text

		try DocumentEditor.setText(
			in: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text"),
			to: "Practicing Presence",
		)

		let result = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text
		let attributed = try NSAttributedString(
			data: result.rtfData,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		)
		let attributes = attributed.attributes(at: 0, effectiveRange: nil)
		let font = try #require(attributes[.font] as? NSFont)
		#expect(attributed.string == "Practicing Presence")
		#expect(font.fontName == "AvenirNext-Heavy")
		#expect(font.pointSize == 118)
		#expect((attributes[.kern] as? NSNumber)?.doubleValue == 4)
		let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
		#expect(paragraph.alignment == .right)
		#expect(paragraph.lineHeightMultiple == 1.2)
		let color = try #require((attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.deviceRGB))
		#expect(abs(color.redComponent - CGFloat(0x57) / 255) < 0.001)
		#expect(abs(color.greenComponent - CGFloat(0xD3) / 255) < 0.001)
		#expect(abs(color.blueComponent - CGFloat(0xC2) / 255) < 0.001)
		#expect(result.attributes.font.name == "AvenirNext-Heavy")
		#expect(result.attributes.font.size == 118)
	}

	@Test
	func setRTFPreservesMixedInlineStylingAndRejectsInvalidData() throws {
		let themeURL = packageRootURL
			.appendingPathComponent("skills/pro-crud/assets/themes/ProCRUD Design System.proTheme")
		let template = try ThemeTemplateSource.select(
			ThemeTemplateSource.candidates(from: themeURL),
			named: "ProCRUD - Streaming/Theme#0",
		)
		var presentation = try DocumentFactory.applying(
			template: template.slide,
			to: DocumentFactory.presentation(name: "Styled text"),
		)
		let path = try ComponentPath(
			"/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text",
		)
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text.attributes.font.bold = true
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text.attributes.font.italic = true
		let attributed = NSMutableAttributedString(
			string: "Normal ",
			attributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.red],
		)
		attributed.append(NSAttributedString(
			string: "Bold",
			attributes: [.font: NSFont.boldSystemFont(ofSize: 48), .foregroundColor: NSColor.blue],
		))
		let rtf = try attributed.data(
			from: NSRange(location: 0, length: attributed.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)

		try DocumentEditor.setRTF(in: &presentation, at: path, data: rtf)
		let text = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text
		#expect(text.rtfData == rtf)
		#expect(text.attributes.font.size == 24)
		#expect(!text.attributes.font.bold)
		#expect(!text.attributes.font.italic)
		let decoded = try NSAttributedString(
			data: text.rtfData,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		)
		let normalFont = try #require(decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
		let boldFont = try #require(decoded.attribute(.font, at: decoded.length - 1, effectiveRange: nil) as? NSFont)
		#expect(normalFont.pointSize == 24)
		#expect(boldFont.pointSize == 48)
		#expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))

		do {
			try DocumentEditor.setRTF(in: &presentation, at: path, data: Data("{\\rtf1\\ansi".utf8))
			Issue.record("Expected invalid RTF to fail")
		} catch is DocumentEditError {
			#expect(
				presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text.rtfData == rtf,
			)
		}
	}

	@Test
	func setRTFClearsFuzzedRangeMetadataFromReplacedContent() throws {
		let themeURL = packageRootURL
			.appendingPathComponent("skills/pro-crud/assets/themes/ProCRUD Design System.proTheme")
		let template = try ThemeTemplateSource.select(
			ThemeTemplateSource.candidates(from: themeURL),
			named: "ProCRUD - Streaming/Theme#0",
		)
		let path = try ComponentPath(
			"/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text",
		)
		let replacements = [
			NSAttributedString(string: "x", attributes: [.font: NSFont.systemFont(ofSize: 17)]),
			NSAttributedString(string: "short replacement", attributes: [.font: NSFont.boldSystemFont(ofSize: 31)]),
			NSAttributedString(string: "emoji 👨‍👩‍👧‍👦 and accents e\u{301}", attributes: [.font: NSFont.systemFont(ofSize: 24)]),
		]
		let ranges: [(Int32, Int32)] = [
			(Int32.min, Int32.max),
			(-1, 1),
			(0, 0),
			(8, 3),
			(0, 10000),
		]

		for replacement in replacements {
			let rtf = try replacement.data(
				from: NSRange(location: 0, length: replacement.length),
				documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
			)
			for (start, end) in ranges {
				for metadata in fuzzedCustomAttributes(start: start, end: end) {
					var presentation = try DocumentFactory.applying(
						template: template.slide,
						to: DocumentFactory.presentation(name: "Range metadata fuzz"),
					)
					presentation.cues[0].actions[0].slide.presentation.baseSlide
						.elements[0].element.text.attributes.customAttributes = [metadata]

					try DocumentEditor.setRTF(in: &presentation, at: path, data: rtf)

					let edited = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text
					#expect(edited.attributes.customAttributes.isEmpty)
					let decoded = try NSAttributedString(
						data: edited.rtfData,
						options: [.documentType: NSAttributedString.DocumentType.rtf],
						documentAttributes: nil,
					)
					#expect(decoded.string == replacement.string)
				}
			}
		}
	}

	@Test
	func describesEffectiveRenderingInPaintOrderWithFittedRTF() throws {
		var presentation = DocumentFactory.presentation(name: "Effective rendering")
		let slidePath = try ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide")
		try DocumentEditor.addElement(
			to: &presentation,
			at: slidePath,
			name: "Front",
			bounds: CGRect(x: 100, y: 100, width: 200, height: 60),
			color: DocumentEditor.color(hex: "#FF0000"),
		)
		try DocumentEditor.addElement(
			to: &presentation,
			at: slidePath,
			name: "Back",
			bounds: CGRect(x: 0, y: 0, width: 400, height: 200),
			color: DocumentEditor.color(hex: "#0000FF"),
		)

		var front = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element
		let source = NSAttributedString(
			string: "text that must shrink",
			attributes: [.font: NSFont.systemFont(ofSize: 100)],
		)
		front.text.rtfData = try source.data(
			from: NSRange(location: 0, length: source.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)
		front.text.scaleBehavior = .scaleFontDown
		front.text.attributes.capitalization = .allCaps
		var capitalization = Rv_Data_Graphics.Text.Attributes.CustomAttribute()
		capitalization.range.start = 0
		capitalization.range.end = Int32(source.length)
		capitalization.capitalization = .allCaps
		front.text.attributes.customAttributes = [capitalization]
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element = front

		let rendering = try PresentationRenderer.effectiveRendering(
			documents: [PresentationDocument(presentation: presentation)],
		)
		let slide = try #require(rendering.presentations.first?.slides.first)
		#expect(rendering.layerOrder == "back-to-front")
		#expect(slide.layers.compactMap(\.name) == ["Back", "Front"])
		#expect(slide.layers.map(\.sourceIndex) == [1, 0])

		let text = try #require(slide.layers.last?.text)
		#expect(text.plainText == "TEXT THAT MUST SHRINK")
		#expect(try #require(text.fontScale) < 1)
		#expect(try #require(text.runs.first?.font?.pointSize) < 100)
		let effectiveRTF = try #require(text.effectiveRTF.data(using: .utf8))
		let effectiveText = try NSAttributedString(
			data: effectiveRTF,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		)
		#expect(effectiveText.string == text.plainText)
		let jsonData = try JSONEncoder().encode(rendering)
		#expect(jsonData.isEmpty == false)
		let json = try #require(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
		let presentations = try #require(json["presentations"] as? [[String: Any]])
		let slides = try #require(presentations.first?["slides"] as? [[String: Any]])
		let layers = try #require(slides.first?["layers"] as? [[String: Any]])
		let textJSON = try #require(layers.last?["text"] as? [String: Any])
		#expect(textJSON["margins"] == nil)
		#expect(layers.last?["opacity"] == nil)
		#expect(layers.last?["rotation"] == nil)
		#expect(layers.last?["alternateTextOutline"] == nil)
	}

	@Test
	func renderingSelectedSlidesPreservesTheirPresentationIndices() throws {
		var presentation = DocumentFactory.presentation(name: "Selected slides")
		try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath("/cue_groups[index=0]"),
		)
		let renderer = PresentationRenderer(document: PresentationDocument(presentation: presentation))

		let rendering = try renderer.effectiveRendering(slideIndices: [1])

		#expect(rendering.slides.map(\.index) == [1])
		#expect(rendering.slides.map(\.name) == ["Slide 2"])
	}

	@Test
	func renderingDiagnosticsRejectFuzzedCanvasSizesBeforeBitmapAllocation() throws {
		let sizes: [(Double, Double)] = [
			(0, 480),
			(0.5, 480),
			(-854, 480),
			(.nan, 480),
			(.infinity, 480),
			(1e308, 1e-308),
			(1_000_000, 1_000_000),
		]
		for (width, height) in sizes {
			var presentation = DocumentFactory.presentation(name: "Canvas fuzz")
			presentation.cues[0].actions[0].slide.presentation.baseSlide.size.width = width
			presentation.cues[0].actions[0].slide.presentation.baseSlide.size.height = height
			let document = PresentationDocument(presentation: presentation)
			let errors = document.renderingDiagnostics.filter { $0.severity == .error }

			#expect(errors.count == 1)
			#expect(errors[0].componentPath.hasSuffix("/size"))
			#expect(throws: RenderError.self) {
				_ = try PresentationRenderer(document: document).render(cue: presentation.cues[0])
			}
		}
	}

	@Test
	func renderingDiagnosticsRejectFuzzedNonFiniteElementState() throws {
		enum Mutation {
			case x(Double)
			case width(Double)
			case opacity(Double)
			case rotation(Double)
		}
		let mutations: [Mutation] = [
			.x(.nan),
			.x(.infinity),
			.width(.nan),
			.opacity(-0.001),
			.opacity(1.001),
			.opacity(.nan),
			.rotation(.infinity),
		]

		for mutation in mutations {
			var presentation = try presentationWithElement(name: "Numeric fuzz")
			switch mutation {
			case let .x(value):
				presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.bounds.origin.x = value
			case let .width(value):
				presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.bounds.size.width = value
			case let .opacity(value):
				presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.opacity = value
			case let .rotation(value):
				presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.rotation = value
			}
			let document = PresentationDocument(presentation: presentation)

			#expect(document.renderingDiagnostics.contains(where: { $0.severity == .error }))
			#expect(throws: RenderError.self) {
				_ = try PresentationRenderer(document: document).render(cue: presentation.cues[0])
			}
		}
	}

	@Test
	func renderingDiagnosticsExplainInvisibleAndStaleContent() throws {
		var presentation = try presentationWithElement(name: "Warning fuzz")
		var element = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element
		element.opacity = 0
		element.bounds.origin.x = 4000
		let source = NSAttributedString(string: "Short", attributes: [.font: NSFont.systemFont(ofSize: 30)])
		element.text.rtfData = try source.data(
			from: NSRange(location: 0, length: source.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)
		var stale = Rv_Data_Graphics.Text.Attributes.CustomAttribute()
		stale.range.start = -4
		stale.range.end = 999
		stale.originalFontSize = 30
		element.text.attributes.customAttributes = [stale]
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element = element

		let diagnostics = PresentationDocument(presentation: presentation).renderingDiagnostics

		#expect(diagnostics.contains(where: { $0.message.contains("entirely outside") }))
		#expect(diagnostics.contains(where: { $0.message.contains("opacity is zero") }))
		#expect(diagnostics.contains(where: { $0.message.contains("stale metadata") }))
		#expect(diagnostics.allSatisfy { $0.severity == .warning })
	}

	@Test
	func renderingDiagnosticsResolveProPresenterExportedAbsoluteMediaPaths() throws {
		let mediaDirectory = try temporaryDirectory()
		let sourceURL = URL(fileURLWithPath: "/Users/export-host/Documents/ProPresenter/Media/Assets/Background Image.png")
		let embeddedURL = mediaDirectory.appendingPathComponent(String(sourceURL.path.trimmingPrefix("/")))
		try FileManager.default.createDirectory(at: embeddedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data().write(to: embeddedURL)

		var presentation = try presentationWithElement(name: "Exported absolute media")
		var media = Rv_Data_Media()
		media.uuid.string = UUID().uuidString
		media.url.absoluteString = sourceURL.absoluteString
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media = media
		let document = PresentationDocument(
			presentation: presentation,
			mediaDirectory: mediaDirectory,
			embeddedMediaFiles: [sourceURL.path],
		)

		#expect(document.renderingDiagnostics.contains { $0.code == .unresolvedMedia } == false)
	}

	@Test
	func zeroOpacityProducesTransparentPixels() throws {
		var presentation = try presentationWithElement(name: "Zero opacity")
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.opacity = 0
		let document = PresentationDocument(presentation: presentation)

		let bitmap = try PresentationRenderer(document: document).render(cue: presentation.cues[0])

		let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
		#expect(center.alphaComponent == 0)
	}

	@Test
	func zeroOpacityTextStillDrawsGlyphsLikeProPresenter() throws {
		var presentation = try presentationWithElement(name: "Zero-opacity text")
		let source = NSAttributedString(
			string: "INVISIBLE",
			attributes: [.font: NSFont.boldSystemFont(ofSize: 80), .foregroundColor: NSColor.red],
		)
		var element = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element
		element.fill.enable = false
		element.opacity = 0
		element.text.rtfData = try source.data(
			from: NSRange(location: 0, length: source.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)
		presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element = element
		let document = PresentationDocument(presentation: presentation)

		let bitmap = try PresentationRenderer(document: document).render(cue: presentation.cues[0])

		let bytes = try #require(bitmap.bitmapData)
		let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
		#expect(UnsafeBufferPointer(start: bytes, count: byteCount).contains { $0 != 0 })
	}
}

private func temporaryDirectory() throws -> URL {
	let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProCRUDTests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	return directory
}

private let packageRootURL = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()

private func componentPathFixture() throws -> ProPresenterDocument {
	var presentation = DocumentFactory.presentation(name: "Component paths")
	try DocumentEditor.addElement(
		to: &presentation,
		at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
		name: "Text",
		bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
		color: DocumentEditor.color(hex: "#000000"),
	)
	try DocumentEditor.setText(
		in: &presentation,
		at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text"),
		to: "Path fixture",
	)
	return ProPresenterDocument(payload: .presentation(presentation), origin: .raw(URL(fileURLWithPath: "/tmp/ComponentPaths.pro")))
}

private func fuzzedCustomAttributes(
	start: Int32,
	end: Int32,
) -> [Rv_Data_Graphics.Text.Attributes.CustomAttribute] {
	let values: [Rv_Data_Graphics.Text.Attributes.CustomAttribute.OneOf_Attribute] = [
		.capitalization(.allCaps),
		.originalFontSize(200),
		.fontScaleFactor(0.75),
		.shouldPreserveForegroundColor(true),
		.chord("C#m7"),
	]
	return values.map { value in
		var attribute = Rv_Data_Graphics.Text.Attributes.CustomAttribute()
		attribute.range.start = start
		attribute.range.end = end
		attribute.attribute = value
		return attribute
	}
}

private func presentationWithElement(name: String) throws -> Rv_Data_Presentation {
	var presentation = DocumentFactory.presentation(name: name, canvasSize: CGSize(width: 854, height: 480))
	try DocumentEditor.addElement(
		to: &presentation,
		at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
		name: "Visible rectangle",
		bounds: CGRect(x: 327, y: 140, width: 200, height: 200),
		color: DocumentEditor.color(hex: "#E83F35"),
	)
	return presentation
}
