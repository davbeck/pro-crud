import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite("Edit command paths")
struct EditCommandOutputTests {
	@Test
	func duplicateReportsSourceAndCreatedCanonicalPaths() throws {
		let presentation = DocumentFactory.presentation(name: "Edit paths")
		var document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Edit paths.pro")),
		)
		let command = try EditDuplicate.parse([
			"/tmp/Edit paths.pro",
			"--path", "/cues[index=0]",
		])

		let outputs = try command.apply(to: &document)

		#expect(outputs.count == 2)
		#expect(outputs[0].kind == .affected)
		#expect(outputs[0].path.hasPrefix("/cues[uuid="))
		#expect(outputs[1].kind == .created)
		#expect(outputs[1].path.hasPrefix("/cues[uuid="))
		#expect(outputs[0].path != outputs[1].path)
		_ = try ComponentResolver.resolve(ComponentPath(outputs[1].path), in: document)
	}

	@Test
	func addActionReportsCueAndCreatedActionPaths() throws {
		var presentation = DocumentFactory.presentation(name: "Edit paths")
		let command = try EditAddAction.parse([
			"/tmp/Edit paths.pro",
			"--path", "/cues[index=0]",
			"--type", "timer",
			"--name", "Countdown",
		])

		let outputs = try command.apply(to: &presentation)

		#expect(outputs.count == 2)
		#expect(outputs[0].kind == .affected)
		#expect(outputs[0].path.hasPrefix("/cues[uuid="))
		#expect(outputs[1].kind == .created)
		#expect(outputs[1].path.contains("/actions[uuid="))
		_ = try ComponentResolver.resolve(
			ComponentPath(outputs[1].path),
			in: transientDocument(for: presentation),
		)
	}

	@Test
	func moveReportsTheResultingIndexWhenUUIDsAreAmbiguous() throws {
		var theme = DocumentFactory.theme()
		DocumentEditor.addTemplate(to: &theme, name: "First")
		DocumentEditor.addTemplate(to: &theme, name: "Moved")
		DocumentEditor.addTemplate(to: &theme, name: "Last")
		theme.slides[1].baseSlide.uuid = theme.slides[0].baseSlide.uuid
		var document = ProPresenterDocument(
			payload: .theme(theme),
			origin: .raw(URL(fileURLWithPath: "/tmp/Theme")),
		)
		let command = try EditMove.parse([
			"/tmp/Theme",
			"--path", "/slides[index=1]",
			"--after", "/slides[index=2]",
		])

		let outputs = try command.apply(to: &document)

		#expect(outputs == [.init(kind: .affected, path: "/slides[index=2]")])
		let selection = try ComponentResolver.resolve(ComponentPath(outputs[0].path), in: document)
		#expect(selection.jsonObject["name"] as? String == "Moved")
	}

	@Test
	func moveReportsAPlaylistItemWhenSiblingPathsUseEquivalentForms() throws {
		var playlist = DocumentFactory.playlist(name: "Service")
		try DocumentEditor.addPlaylistItem(
			to: &playlist,
			at: ComponentPath("/root_node"),
			type: "header",
			name: "First",
			documentURL: nil,
		)
		try DocumentEditor.addPlaylistItem(
			to: &playlist,
			at: ComponentPath("/root_node"),
			type: "header",
			name: "Second",
			documentURL: nil,
		)
		let playlistID = playlist.rootNode.playlists.playlists[0].uuid.string
		var document = ProPresenterDocument(
			payload: .playlist(playlist),
			origin: .raw(URL(fileURLWithPath: "/tmp/Playlist data")),
		)
		let command = try EditMove.parse([
			"/tmp/Playlist data",
			"--path", "/root_node/playlists/playlists[uuid=\(playlistID)]/items[index=0]",
			"--after", "/root_node/playlists/playlists[index=0]/items/items[index=1]",
		])

		let outputs = try command.apply(to: &document)

		let output = try #require(outputs.first)
		#expect(output.kind == .affected)
		let selection = try ComponentResolver.resolve(ComponentPath(output.path), in: document)
		#expect(selection.jsonObject["name"] as? String == "First")
		#expect(selection.canonicalPath == output.path)
	}

	@Test
	func setPlaylistItemHiddenUpdatesOnlyLocalVisibility() throws {
		var playlist = DocumentFactory.playlist(name: "Core Values")
		playlist.rootNode.playlists.playlists[0].pcoPlan.planIDStr = "plan-123"
		var remote = Rv_Data_PlanningCenterPlan.PlanItem()
		remote.pcoIDStr = "item-789"
		remote.name = "Announcement Reminder"
		var connected = Rv_Data_PlaylistItem.PlanningCenter()
		connected.item = remote
		var item = Rv_Data_PlaylistItem()
		item.uuid.string = "CONNECTED-ITEM"
		item.name = remote.name
		item.planningCenter = connected
		playlist.rootNode.playlists.playlists[0].items.items = [item]
		var document = ProPresenterDocument(
			payload: .playlist(playlist),
			origin: .raw(URL(fileURLWithPath: "/tmp/Playlist data")),
		)
		let command = try EditSetPlaylistItemHidden.parse([
			"/tmp/Playlist data",
			"--path", "/root_node/playlists/playlists[index=0]/items/items[index=0]",
			"--hidden",
		])

		let outputs = try command.apply(to: &document)

		#expect(outputs.count == 1)
		guard case let .playlist(edited) = document.payload else {
			Issue.record("Expected playlist payload")
			return
		}
		let editedItem = edited.rootNode.playlists.playlists[0].items.items[0]
		#expect(editedItem.isHidden)
		#expect(editedItem.planningCenter.item.pcoIDStr == "item-789")
	}

	@Test
	func planningCenterLinkCommandsReportTheWrapperAndPreserveRemoteIdentity() throws {
		let presentationURL = FileManager.default.temporaryDirectory
			.appendingPathComponent("pro-crud-link-command-\(UUID().uuidString).pro")
		defer { try? FileManager.default.removeItem(at: presentationURL) }
		try DocumentWriter.writeRaw(
			ProPresenterDocument(
				payload: .presentation(DocumentFactory.presentation(name: "Abide")),
				origin: .raw(presentationURL),
			),
			to: presentationURL,
		)

		var playlist = DocumentFactory.playlist(name: "Core Values")
		playlist.rootNode.playlists.playlists[0].pcoPlan.planIDStr = "plan-123"
		var remote = Rv_Data_PlanningCenterPlan.PlanItem()
		remote.pcoIDStr = "item-789"
		remote.name = "Abide"
		var connected = Rv_Data_PlaylistItem.PlanningCenter()
		connected.item = remote
		var item = Rv_Data_PlaylistItem()
		item.uuid.string = "CONNECTED-ITEM"
		item.name = remote.name
		item.planningCenter = connected
		playlist.rootNode.playlists.playlists[0].items.items = [item]
		var document = ProPresenterDocument(
			payload: .playlist(playlist),
			origin: .raw(URL(fileURLWithPath: "/tmp/Library")),
		)
		let itemPath = "/root_node/playlists/playlists[index=0]/items/items[index=0]"
		let link = try EditLinkPlanningCenterItem.parse([
			"/tmp/Library",
			"--path", itemPath,
			"--document", presentationURL.path,
		])

		let linkOutputs = try link.apply(to: &document)
		#expect(linkOutputs.count == 1)
		guard case let .playlist(linkedPlaylist) = document.payload else {
			Issue.record("Expected playlist payload")
			return
		}
		let linked = linkedPlaylist.rootNode.playlists.playlists[0].items.items[0]
		#expect(linked.planningCenter.hasLinkedData)
		#expect(linked.planningCenter.item.pcoIDStr == "item-789")

		let unlink = try EditUnlinkPlanningCenterItem.parse([
			"/tmp/Library",
			"--path", itemPath,
		])
		let unlinkOutputs = try unlink.apply(to: &document)
		#expect(unlinkOutputs == linkOutputs)
		guard case let .playlist(unlinkedPlaylist) = document.payload else {
			Issue.record("Expected playlist payload")
			return
		}
		let unlinked = unlinkedPlaylist.rootNode.playlists.playlists[0].items.items[0]
		#expect(!unlinked.planningCenter.hasLinkedData)
		#expect(unlinked.planningCenter.item.pcoIDStr == "item-789")
	}

	@Test
	func mediaPathContextHandlesAFillCreatedByTheEdit() throws {
		var theme = DocumentFactory.theme()
		DocumentEditor.addTemplate(to: &theme, name: "Series")
		var element = Rv_Data_Graphics.Element()
		element.uuid.string = "BACKGROUND-ELEMENT"
		element.name = "Background"
		element.fill.enable = true
		element.fill.color = try DocumentEditor.color(hex: "#000000")
		var slideElement = Rv_Data_Slide.Element()
		slideElement.element = element
		theme.slides[0].baseSlide.elements = [slideElement]
		var document = ProPresenterDocument(
			payload: .theme(theme),
			origin: .raw(URL(fileURLWithPath: "/tmp/Theme")),
		)
		let target = try ComponentPath(
			"/slides[index=0]/base_slide/elements[index=0]/element/fill/media",
		)
		let outputContext = try EditMediaPathContext(path: target, in: document)
		var media = Rv_Data_Media()
		media.uuid.string = "REPLACEMENT-MEDIA"

		try DocumentEditor.setMedia(&document, at: target, to: media)

		let outputPath = try outputContext.resolvedPath(in: document)
		#expect(outputPath.hasSuffix("/element/fill/media"))
		_ = try ComponentResolver.resolve(ComponentPath(outputPath), in: document)
	}

	@Test
	func patchReportsTheSameGroupedCueWhenItsUUIDChangesNativeOrder() throws {
		var presentation = DocumentFactory.presentation(name: "Patch paths")
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		presentation.cueGroups[0].cueIdentifiers = [
			presentation.cues[2].uuid,
			presentation.cues[0].uuid,
			presentation.cues[1].uuid,
		]
		var document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Patch paths.pro")),
		)
		let originalPath = try ComponentPath("/cues[index=0]")
		let outputContext = try EditStablePathContext(path: originalPath, in: document)

		try DocumentEditor.patch(
			&document,
			at: originalPath,
			jsonData: Data("{\"uuid\":{\"string\":\"PATCHED-ID\"}}".utf8),
		)

		let outputPath = try outputContext.resolvedPath(in: document)
		#expect(outputPath == "/cues[uuid=\"PATCHED-ID\"]")
		let selection = try ComponentResolver.resolve(ComponentPath(outputPath), in: document)
		#expect(selection.jsonObject["name"] as? String == "Slide 3")
		let nowFirst = try ComponentResolver.resolve(ComponentPath("/cues[index=0]"), in: document)
		#expect(nowFirst.jsonObject["name"] as? String == "Slide 1")
	}
}
