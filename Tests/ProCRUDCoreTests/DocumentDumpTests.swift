import AppKit
import CustomDump
import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Document dump reports")
struct DocumentDumpTests {
	@Test
	func presentsAuthoringStructureInNativeCueOrder() throws {
		var presentation = DocumentFactory.presentation(name: "Authoring report", canvasSize: CGSize(width: 1280, height: 720))
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[index=0]"))
		presentation.cues[0].name = "Stored first"
		presentation.cues[1].name = "Stored second"
		presentation.cues[2].name = "Native first"
		presentation.cueGroups[0].cueIdentifiers = [
			presentation.cues[2].uuid,
			presentation.cues[0].uuid,
			presentation.cues[1].uuid,
		]
		presentation.notes = "Document notes"

		var arrangement = Rv_Data_Presentation.Arrangement()
		arrangement.uuid.string = "ARRANGEMENT"
		arrangement.name = "Short"
		arrangement.groupIdentifiers = [presentation.cueGroups[0].group.uuid]
		presentation.arrangements = [arrangement]
		presentation.selectedArrangement = arrangement.uuid

		try DocumentEditor.addElement(
			to: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"),
			name: "Title",
			bounds: CGRect(x: 20, y: 30, width: 600, height: 100),
			color: DocumentEditor.color(hex: "#FFFFFF"),
		)
		try DocumentEditor.setText(
			in: &presentation,
			at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text"),
			to: "Visible words",
		)
		let nativeStorageIndex = 2
		var presentationSlide = presentation.cues[nativeStorageIndex].actions[0].slide.presentation
		presentationSlide.notes.rtfData = Data("{\\rtf1\\ansi Speaker note}".utf8)
		presentationSlide.baseSlide.elements[0].buildIn.uuid.string = "BUILD-IN"
		presentationSlide.baseSlide.elementBuildOrder = [presentationSlide.baseSlide.elements[0].buildIn.uuid]
		presentation.cues[nativeStorageIndex].actions[0].slide.presentation = presentationSlide

		var mediaAction = Rv_Data_Action()
		mediaAction.uuid.string = "MEDIA-ACTION"
		mediaAction.name = "Walk-in"
		mediaAction.label.text = "Lobby loop"
		mediaAction.type = .backgroundMedia
		mediaAction.isEnabled = true
		mediaAction.media.element.uuid.string = "MEDIA"
		mediaAction.media.element.url.relativePath = "Media/loop.mov"
		mediaAction.media.element.video = Rv_Data_Media.VideoTypeProperties()
		presentation.cues[nativeStorageIndex].actions.append(mediaAction)

		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .archive(URL(fileURLWithPath: "/tmp/Authoring.probundle")),
			archiveEntries: ["Authoring.pro", "Media/loop.mov"],
		)
		let report = try DocumentDumpReport.make(from: document)
		let value = try #require(report.presentation)

		#expect(report.kind == "presentation")
		#expect(value.notes == "Document notes")
		#expect(value.nativeCueOrder.map(\.name) == ["Native first", "Stored first", "Stored second"])
		#expect(value.cues.map(\.name) == ["Native first", "Stored first", "Stored second"])
		#expect(value.cues[0].index == 0)
		#expect(value.cues[0].path.contains("/cues[uuid="))
		#expect(value.groups[0].cues.map(\.path) == value.nativeCueOrder.map { Optional($0.path) })
		#expect(value.arrangements[0].name == "Short")
		#expect(value.arrangements[0].selected)
		#expect(value.arrangements[0].groups[0].path == value.groups[0].path)

		let slideAction = value.cues[0].actions[0]
		#expect(slideAction.label?.text == "Slide 3")
		#expect(slideAction.slide?.notes?.plainText == "Speaker note")
		#expect(slideAction.slide?.elements[0].text?.plainText == "Visible words")
		#expect(slideAction.slide?.elements[0].bounds.x == 20)
		#expect(slideAction.slide?.builds.elementOrderUUIDs == ["BUILD-IN"])
		#expect(slideAction.slide?.builds.buildInCount == 1)
		#expect(slideAction.slide?.elements[0].builds.hasBuildIn == true)

		let dumpedMedia = try #require(value.cues[0].actions[1].media)
		#expect(dumpedMedia.source == "Media/loop.mov")
		#expect(dumpedMedia.type == "video")
		#expect(report.media == [dumpedMedia])
		#expect(report.archive.embeddedMedia == ["Media/loop.mov"])

		for path in value.nativeCueOrder.map(\.path) + value.cues.flatMap({ $0.actions.map(\.path) }) {
			#expect(try ComponentResolver.resolve(ComponentPath(path), in: document).canonicalPath == path)
		}

		let encoded = try JSONEncoder().encode(report)
		let json = String(decoding: encoded, as: UTF8.self)
		#expect(json.contains("\"nativeCueOrder\""))
		#expect(json.contains("\"rtf\""))
		#expect(!json.contains("schemaVersion"))
		#expect(!json.contains("effectiveRTF"))
	}

	@Test
	func describesASelectedComponentWithoutReturningProtobufJSON() throws {
		let presentation = DocumentFactory.presentation(name: "Selection")
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Selection.pro")),
		)
		let selection = try ComponentResolver.resolve(ComponentPath("/cues[index=0]"), in: document)
		let report = ComponentDumpReport(selection: selection)

		#expect(report.path.contains(presentation.cues[0].uuid.string))
		#expect(report.protobufType == "rv.data.Cue")
		#expect(report.uuid == presentation.cues[0].uuid.string)
		#expect(report.children["actions"] == 1)
		#expect(!report.text.contains(where: { $0.hasPrefix("ey") }))
	}

	@Test
	func reportsCueGroupMetadataAndNestedComponentIdentity() throws {
		var presentation = DocumentFactory.presentation(name: "Group metadata")
		presentation.cueGroups[0].group.name = "Verse"
		presentation.cueGroups[0].group.color = try DocumentEditor.color(hex: "#336699")
		presentation.cueGroups[0].group.hotKey.code = .ansiV
		presentation.cueGroups[0].group.hotKey.controlIdentifier = "verse-control"
		presentation.cueGroups[0].group.applicationGroupIdentifier.string = "APPLICATION-VERSE"
		presentation.cueGroups[0].group.applicationGroupName = "Verse Label"
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/GroupMetadata.pro")),
		)

		let report = try DocumentDumpReport.make(from: document)
		let group = try #require(report.presentation?.groups.first)
		expectNoDifference(group.name, "Verse")
		expectNoDifference(group.color?.red, Float(0.2))
		expectNoDifference(group.color?.green, Float(0.4))
		expectNoDifference(group.color?.blue, Float(0.6))
		expectNoDifference(group.color?.alpha, Float(1))
		expectNoDifference(group.hotKey?.code, "ansiV")
		expectNoDifference(group.hotKey?.rawValue, Rv_Data_HotKey.KeyCode.ansiV.rawValue)
		expectNoDifference(group.hotKey?.controlIdentifier, "verse-control")
		expectNoDifference(group.applicationGroupUUID, "APPLICATION-VERSE")
		expectNoDifference(group.applicationGroupName, "Verse Label")
		expectNoDifference(group.cues.map(\.uuid), [presentation.cues[0].uuid.string])

		let selection = try ComponentResolver.resolve(ComponentPath("/cue_groups[index=0]"), in: document)
		let component = ComponentDumpReport(selection: selection)
		expectNoDifference(component.name, "Verse")
		expectNoDifference(component.uuid, presentation.cueGroups[0].group.uuid.string)
		expectNoDifference(component.children["cueIdentifiers"], 1)
	}

	@Test
	func supportsThemeAndPlaylistDocuments() throws {
		var theme = DocumentFactory.theme()
		let source = DocumentFactory.presentation(name: "Template source")
		var template = Rv_Data_Template.Slide()
		template.name = "Teaching"
		template.baseSlide = source.cues[0].actions[0].slide.presentation.baseSlide
		theme.slides = [template]
		let themeDocument = ProPresenterDocument(
			payload: .theme(theme),
			origin: .raw(URL(fileURLWithPath: "/tmp/Theme")),
		)
		let themeReport = try DocumentDumpReport.make(from: themeDocument)
		#expect(themeReport.theme?.documents[0].templates[0].name == "Teaching")
		#expect(themeReport.theme?.documents[0].templates[0].path.contains("/slides[uuid=") == true)

		let playlist = DocumentFactory.playlist(name: "Sunday")
		let playlistDocument = ProPresenterDocument(
			payload: .playlist(playlist),
			origin: .raw(URL(fileURLWithPath: "/tmp/data")),
		)
		let playlistReport = try DocumentDumpReport.make(from: playlistDocument)
		#expect(playlistReport.playlist?.type == "presentation")
		#expect(playlistReport.playlist?.root.children.first?.name == "Sunday")
		#expect(playlistReport.playlist?.root.children.first?.path.contains("/playlists/playlists[uuid=") == true)
	}
}
