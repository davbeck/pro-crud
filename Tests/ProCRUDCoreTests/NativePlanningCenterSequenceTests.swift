import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native Planning Center local sequence acceptance")
struct NativePlanningCenterSequenceTests {
	@Test func missingAndAmbiguousSequenceLabelsCannotPrepareLocalChanges() throws {
		let source = try stream("cli-before"), presentation = try stream("presentation-before", presentation: true)
		let item = try #require(UUID(uuidString: selected(source).items.items[0].uuid.string)), layout = try presentation.presentationLayout()
		for name in [layout.groups[0].name, "No remote label matches this"] {
			let patch = try #require(try NativeLocalPatch.prepare(stream: presentation, edit: .cueGroupName(layout.groups[1].id, name)))
			let changed = NativeWorkspaceStream(identity: presentation.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
			let snapshot = NativeWorkspaceSnapshot(root: fixtures, workspaceID: UUID(), metadata: [:], streams: [source, changed])
			#expect(throws: NativeSemanticError.self) { try NativePlanningCenterSequence(snapshot: snapshot, playlistStreamID: source.identity.documentID, itemID: item, presentationID: presentation.identity.documentID, arrangementID: UUID(), name: "Local sequence", linkedItemID: UUID()) }
		}
	}

	@Test func portableCLIConnectionImportRetainsTheRemoteSnapshotAndResolvesANewLocalPresentation() throws {
		let source = try selected(stream("cli-after")), imported = try stream("portable-import")
		let document = try NativePlaylistProjection(shared: imported).document
		let playlist = try #require(document.rootNode.playlists.playlists.first { $0.uuid.string == "1F3D5C21-1543-4B92-8F93-DBABC80B43D8" })
		#expect(playlist.pcoPlan == source.pcoPlan)
		let item = try #require(playlist.items.items.first), original = try #require(source.items.items.first)
		#expect(item.planningCenter.item == original.planningCenter.item)
		#expect(item.isHidden == original.isHidden)
		#expect(item.planningCenter.linkedData.presentation.arrangement == original.planningCenter.linkedData.presentation.arrangement)
		#expect(item.planningCenter.linkedData.presentation.documentPath.local.path == "Libraries/Default/ProCRUD File Replacement Probe-1.pro")
		#expect(item.uuid != original.uuid && item.planningCenter.linkedData.uuid != original.planningCenter.linkedData.uuid)
	}

	@Test func localSelectionCanReturnToMasterWithoutChangingTheRemoteSongOrItsArrangementDefinition() throws {
		let source = try stream("cli-after"), presentation = try stream("presentation-after", presentation: true)
		let before = try selected(source), item = try #require(UUID(uuidString: before.items.items[0].uuid.string))
		let context = NativeWorkspaceSnapshot(root: fixtures, workspaceID: UUID(), metadata: [:], streams: [source, presentation])
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edits: [.playlist(.arrangement(item: item, arrangement: nil))], context: context))
		let after = NativeWorkspaceStream(identity: source.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
		let local = try selected(after).items.items[0].planningCenter
		#expect(local.item == before.items.items[0].planningCenter.item)
		#expect(local.linkedData.presentation.arrangement.string.isEmpty && local.linkedData.presentation.arrangementName.isEmpty)
		#expect(try NativeLocalPatch.prepare(stream: after, edits: [.playlist(.arrangement(item: item, arrangement: nil))], context: context) == nil)
	}

	@Test func productionSequenceAndLocalLinkReopenExactlyAndRetainRemoteOwnership() throws {
		let before = try stream("cli-before"), after = try stream("cli-after"), opened = try stream("native-open")
		#expect(after.snapshot == opened.snapshot && after.versionVector == opened.versionVector)
		let source = try selected(before), result = try selected(after)
		#expect(result.pcoPlan == source.pcoPlan)
		#expect(result.items.items[0].uuid == source.items.items[0].uuid)
		#expect(result.items.items[0].planningCenter.item == source.items.items[0].planningCenter.item)
		#expect(result.items.items[0].isHidden)
		let local = result.items.items[0].planningCenter.linkedData
		#expect(local.presentation.arrangement.string == "88999999-0000-4000-8000-000000000004")
		#expect(local.presentation.arrangementName == "CLI Service Sequence")
		#expect(local.presentation.documentPath.local.path == "Libraries/Default/ProCRUD File Replacement Probe.pro")
		let presentation = try stream("presentation-after", presentation: true), original = try stream("presentation-before", presentation: true), native = try stream("presentation-open", presentation: true)
		#expect(presentation.snapshot == native.snapshot && presentation.versionVector == native.versionVector)
		let layout = try presentation.presentationLayout(), old = try original.presentationLayout()
		#expect(layout.cues == old.cues && layout.groups == old.groups && layout.selectedArrangementID == old.selectedArrangementID)
		#expect(layout.arrangements.last?.groupIDs == [old.groups[0].id, old.groups[1].id, old.groups[0].id])
		let exported = try DocumentLoader.load(from: fixtures.appendingPathComponent("NativeLinked.proPlaylist"))
		guard case let .playlist(document) = exported.payload else { Issue.record("Expected native playlist export"); return }
		let remote = try #require(document.rootNode.playlists.playlists.first)
		// Native Export > Playlist flattens connected wrappers into standard
		// local items. The live native stream retains all remote metadata.
		#expect(remote.linkData == nil)
		let exportedItem = try #require(remote.items.items.first)
		#expect(exportedItem.presentation.arrangement == local.presentation.arrangement)
		#expect(exportedItem.presentation.arrangementName == local.presentation.arrangementName)
	}

	@Test func unlinkMatchesIndependentNativeDeletionOfOnlyTheLocalKey() throws {
		let before = try stream("native-continued"), native = try stream("native-unlinked")
		let item = try #require(UUID(uuidString: selected(before).items.items[0].uuid.string))
		let patch = try #require(try NativeLocalPatch.prepare(stream: before, edit: .playlist(.unlink(item))))
		let actual = NativeWorkspaceStream(identity: before.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
		#expect(try actual.decodedValue() == native.decodedValue())
		#expect(try NativeLocalPatch.prepare(stream: actual, edit: .playlist(.unlink(item))) == nil)
	}

	private func selected(_ stream: NativeWorkspaceStream) throws -> Rv_Data_Playlist {
		try #require(NativePlaylistProjection(shared: stream).document.rootNode.playlists.playlists.first { $0.name == "Owned Offline Planning Center Control" })
	}

	private func stream(_ name: String, presentation: Bool = false) throws -> NativeWorkspaceStream {
		let data = try Data(contentsOf: fixtures.appendingPathComponent(name + ".loro"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: presentation ? "58884c2c-1eb4-50f8-99ac-c88b29cb0f34" : "f1d34fe9-54bc-5cce-aa9b-975968deaeae")), scope: .shared, kind: presentation ? "Presentation" : "PlaylistLibrary", corePath: presentation ? "Default/ProCRUD File Replacement Probe" : nil, availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: fixtures.appendingPathComponent(name + ".vector")), lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/PlanningCenterEditing")
	}
}
