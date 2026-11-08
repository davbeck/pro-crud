import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native playlist edits and connected local overlays")
struct NativePlaylistEditingTests {
	@Test func playlistDeletionChecksActionReferencesAndUninspectedScopesBeforePublishing() throws {
		let playlist = try fixture("Playlist/shared"), projection = try NativePlaylistProjection(shared: playlist)
		let item = try #require(UUID(uuidString: projection.document.rootNode.playlists.playlists[1].items.items[0].uuid.string))
		let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/Playlist/presentation")
		let document = LoroDoc(); _ = try document.import(bytes: Data(contentsOf: base.appendingPathExtension("loro")))
		let cues = try #require(document.getMap(id: "root").get(key: "cues")?.asLoroMap()), key = try #require(cues.keys().first)
		let cue = try #require(cues.get(key: key)?.asLoroMap()), actions = try #require(cue.get(key: "actions")?.asLoroMovableList())
		try NativeContainerAccess.write(.map(["uuid": .string(UUID().uuidString), "type": .integer(21), "isEnabled": .boolean(true), "ActionTypeData": .map(["__tag": .string("playlist_item"), "playlist_item": .map(["item_uuid": .string(item.uuidString)])])]), to: actions.pushContainer(child: LoroMap()), message: Rv_Data_Action.protoMessageName)
		let presentation = try NativeWorkspaceStream(identity: .init(documentID: #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: 0, sha256: nil, updatedAtMilliseconds: 0), snapshot: document.exportSnapshot(), versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
		let snapshot = NativeWorkspaceSnapshot(root: base, workspaceID: UUID(), metadata: [:], streams: [playlist, presentation])
		#expect(throws: NativeSemanticError.self) { try NativeLocalWorkspaceWriter.prepare([.init(documentID: playlist.identity.documentID, edit: .playlist(.remove(item)))], in: snapshot) }
		let patch = try #require(try NativeLocalPatch.prepare(stream: playlist, edit: .playlist(.remove(item))))
		#expect(throws: NativeSemanticError.self) { try NativePlaylistDeletion.validate([patch], in: snapshot) }
		var unknown = presentation.identity; unknown.kind = "FutureDocument"
		let future = NativeWorkspaceSnapshot(root: base, workspaceID: snapshot.workspaceID, metadata: [:], streams: [playlist, .init(identity: unknown, snapshot: presentation.snapshot, versionVector: presentation.versionVector, lastSharedVersionVector: nil)])
		#expect(throws: NativeSemanticError.self) { try NativePlaylistDeletion.validate([patch], in: future) }
	}

	@Test func nativeRenameAndConnectedVisibilityMatchIndependentControls() throws {
		let before = try fixture("PlaylistEditing/native-hidden"), renamed = try fixture("PlaylistEditing/native-renamed")
		let id = try #require(UUID(uuidString: "D0AB014C-0771-4441-9DE5-C61098CA8F3C"))
		let patch = try #require(try NativeLocalPatch.prepare(stream: before, edit: .playlist(.rename(id, "ProCRUD Native Playlist Editing"))))
		#expect(try NativePlaylistProjection(shared: replacing(before, patch)).document == NativePlaylistProjection(shared: renamed).document)
		let connected = try fixture("PlaylistEditing/native-connected-before"), hidden = try fixture("PlaylistEditing/native-connected-hidden")
		let item = try #require(UUID(uuidString: "FA1B9B31-37C4-457D-878E-A801D2C4DB13"))
		let overlay = try #require(try NativeLocalPatch.prepare(stream: connected, edit: .playlist(.hidden(item, true))))
		#expect(try NativePlaylistProjection(shared: replacing(connected, overlay)).document == NativePlaylistProjection(shared: hidden).document)
	}

	@Test func productionPlaylistAndThemeTransactionReopensWithoutRepair() throws {
		let before = try fixture("PlaylistEditing/cli-before"), after = try fixture("PlaylistEditing/cli-after"), opened = try fixture("PlaylistEditing/native-open")
		#expect(after.snapshot == opened.snapshot && after.versionVector == opened.versionVector)
		let result = try NativePlaylistProjection(shared: after).document
		let folder = try #require(result.rootNode.playlists.playlists.first)
		#expect(folder.name == "CLI Playlist Folder")
		let playlist = try #require(folder.playlists.playlists.first)
		#expect(playlist.name == "CLI Playlist Editing")
		#expect(playlist.items.items.map(\.isHidden) == [false, true, false])
		#expect(try NativePlaylistProjection(shared: before).document.rootNode.playlists.playlists == result.rootNode.playlists.playlists.dropFirst().map(\.self))
	}

	@Test func portableNativeImportResolvesBothEmbeddedDocumentsWithPlatformMetadata() throws {
		let imported = try fixture("PlaylistEditing/native-platform-import")
		let document = try NativePlaylistProjection(shared: imported).document
		let playlist = try #require(document.rootNode.playlists.playlists.first { $0.uuid.string == "0FC5CB6D-9B03-4343-9C80-B57230AD355E" })
		#expect(playlist.items.items.map(\.isHidden) == [false, true, false])
		#expect(playlist.items.items[0].name == "CLI Section")
		#expect(playlist.items.items[1].presentation.documentPath.local.path == "Libraries/Default/ProCRUDTarget22Acceptance-3.pro")
		#expect(playlist.items.items[2].presentation.documentPath.local.path == "Libraries/Default/NativeMediaIdentity-2.pro")
		#expect(playlist.items.items.dropFirst().allSatisfy { $0.presentation.documentPath.platform.rawValue == 1 && $0.presentation.documentPath.local.root == .show })
	}

	@Test func visibilityMatchesIndependentNativeEditAndPreservesHistory() throws {
		let before = try fixture("PlaylistEditing/native-before"), native = try fixture("PlaylistEditing/native-hidden")
		let item = try #require(UUID(uuidString: "726D1A71-F8B7-4B7A-9B6B-14602BC61C27"))
		let patch = try #require(try NativeLocalPatch.prepare(stream: before, edit: .playlist(.hidden(item, true))))
		let result = replacing(before, patch)
		#expect(try NativePlaylistProjection(shared: result).document == NativePlaylistProjection(shared: native).document)
		let replay = LoroDoc(); _ = try replay.import(bytes: #require(before.snapshot)); _ = try replay.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(replay.getDeepValue()) == result.decodedValue())
		#expect(try NativeLocalPatch.prepare(stream: result, edit: .playlist(.hidden(item, true))) == nil)
	}

	@Test func nodeCreationMovesAndRemovalRetainExistingIdentities() throws {
		let before = try fixture("Playlist/shared")
		let layout = try NativePlaylistLayout(root: before.decodedValue().object(at: "/").required("root", at: "/"))
		let root = try #require(layout.playlists.first), playlist = root.children[1]
		let groupID = UUID(), playlistID = UUID(), headerID = UUID()
		let operations: [NativePresentationEdit] = [
			.playlist(.create(id: groupID, parent: root.id, name: "Folder", kind: .group, after: nil)),
			.playlist(.create(id: playlistID, parent: groupID, name: "New playlist", kind: .playlist, after: nil)),
			.playlist(.create(id: headerID, parent: playlistID, name: "Section", kind: .header, after: nil)),
			.playlist(.move(playlist.children[0].id, parent: playlistID, after: headerID)),
			.playlist(.rename(playlistID, "Renamed")),
		]
		let patch = try #require(try NativeLocalPatch.prepare(stream: before, edits: operations))
		let after = replacing(before, patch)
		let document = try NativePlaylistProjection(shared: after).document
		let created = document.rootNode.playlists.playlists[0].playlists.playlists[0]
		#expect(created.name == "Renamed" && created.items.items.count == 2)
		#expect(UUID(uuidString: created.items.items[1].uuid.string) == playlist.children[0].id)
		let tree = LoroDoc(); _ = try tree.import(bytes: patch.snapshot)
		let list = try NativePlaylistLayout(root: NativeWorkspaceValue(tree.getMap(id: "root").getDeepValue()))
		let moved = try #require(list.playlists.first?.children.first?.children.first?.children.last)
		#expect(moved.nodeID == playlist.children[0].nodeID)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: after, edit: .playlist(.remove(playlistID))) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: after, edit: .playlist(.move(groupID, parent: groupID, after: nil))) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: after, edit: .playlist(.remove(root.id))) }
		let removed = try #require(try NativeLocalPatch.prepare(stream: after, edit: .playlist(.remove(headerID))))
		#expect(try NativePlaylistProjection(shared: replacing(after, removed)).document.rootNode.playlists.playlists[0].playlists.playlists[0].items.items.count == 1)
	}

	@Test func stableCreationReplayAndConflictingReuse() throws {
		let before = try fixture("Playlist/shared")
		let parent = try #require(NativePlaylistProjection(shared: before).document.rootNode.playlists.playlists.first)
		let id = UUID(), parentID = try #require(UUID(uuidString: parent.uuid.string))
		let operation = NativePresentationEdit.playlist(.create(id: id, parent: parentID, name: "Stable", kind: .header, after: nil))
		let patch = try #require(try NativeLocalPatch.prepare(stream: before, edit: operation)), after = replacing(before, patch)
		#expect(try NativeLocalPatch.prepare(stream: after, edit: operation) == nil)
		let hidden = try #require(try NativeLocalPatch.prepare(stream: after, edit: .playlist(.hidden(id, true))))
		#expect(try NativeLocalPatch.prepare(stream: replacing(after, hidden), edits: [operation, .playlist(.hidden(id, true))]) == nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: after, edit: .playlist(.create(id: id, parent: parentID, name: "Conflict", kind: .header, after: nil))) }
		#expect(before.snapshot == patch.originalSnapshot)
	}

	@Test func connectedWrappersRetainRemoteFieldsThroughLocalOverlaysAndBlockStructureEdits() throws {
		let original = try fixture("Playlist/shared"), source = LoroDoc(); _ = try source.import(bytes: #require(original.snapshot))
		let root = source.getMap(id: "root"), tree = try #require(root.get(key: "playlists")?.asLoroTree())
		let layout = try NativePlaylistLayout(root: NativeWorkspaceValue(root.getDeepValue())), selected = try #require(layout.playlists.first?.children.last)
		let attributes = try NativeContainerAccess.map(tree.getMeta(target: NativeStructuralEditing.treeID(selected.nodeID)), keys: ["Kind", "playlist"])
		try NativeContainerAccess.write(.map(["LinkData": .map(["__tag": .string("pco_plan"), "pco_plan": .map(["plan_id_str": .string("123"), "parent_id_str": .string("456")])])]), to: attributes, message: "rv.data.PlaylistNode.Playlist")
		let item = selected.children[1]
		let stored = try NativeContainerAccess.map(tree.getMeta(target: NativeStructuralEditing.treeID(item.nodeID)), keys: ["Kind", "item"])
		let remote: NativeWorkspaceValue = .map(["ItemType": .map(["__tag": .string("planning_center"), "planning_center": .map(["item": .map(["pco_id_str": .string("789"), "name": .string("Remote title")]), "linked_data": .null])])])
		try NativeContainerAccess.write(remote, to: stored, message: "rv.data.PlaylistNode.Item")
		let connected = try NativeWorkspaceStream(identity: original.identity, snapshot: source.exportSnapshot(), versionVector: source.stateVv().encode(), lastSharedVersionVector: nil)
		let patch = try #require(try NativeLocalPatch.prepare(stream: connected, edit: .playlist(.hidden(item.id, true))))
		let after = replacing(connected, patch)
		let projected = try NativePlaylistProjection(shared: after).document.rootNode.playlists.playlists.last
		#expect(projected?.pcoPlan.planIDStr == "123")
		#expect(projected?.items.items[1].planningCenter.item.name == "Remote title")
		#expect(projected?.items.items[1].isHidden == true)
		for edit in [NativePlaylistEdit.rename(selected.id, "Remote rename"), .remove(item.id), .move(item.id, parent: selected.id, after: nil)] {
			#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: connected, edit: .playlist(edit)) }
		}
		#expect(try NativeLocalPatch.prepare(stream: connected, edit: .playlist(.unlink(item.id))) == nil)
		let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/Playlist")
		let presentationID = try #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee"))
		let presentation = try NativeWorkspaceStream(identity: .init(documentID: presentationID, scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: 0, sha256: nil, updatedAtMilliseconds: 0), snapshot: Data(contentsOf: fixtureRoot.appendingPathComponent("presentation.loro")), versionVector: Data(contentsOf: fixtureRoot.appendingPathComponent("presentation.vector")), lastSharedVersionVector: nil)
		let context = NativeWorkspaceSnapshot(root: fixtureRoot, workspaceID: UUID(), metadata: [:], streams: [connected, presentation])
		let nested = UUID()
		let link = NativePresentationEdit.playlist(.link(item: item.id, presentation: presentationID, linkedID: nested, arrangement: nil))
		let linkedPatch = try #require(try NativeLocalPatch.prepare(stream: connected, edits: [link], context: context))
		let linked = replacing(connected, linkedPatch)
		#expect(try NativeLocalPatch.prepare(stream: linked, edits: [link], context: context) == nil)
		let linkedItem = try #require(NativePlaylistProjection(shared: linked).document.rootNode.playlists.playlists.last).items.items[1]
		#expect(UUID(uuidString: linkedItem.planningCenter.linkedData.uuid.string) == nested)
		#expect(linkedItem.planningCenter.item == projected?.items.items[1].planningCenter.item)
		let unlinkedPatch = try #require(try NativeLocalPatch.prepare(stream: linked, edit: .playlist(.unlink(item.id))))
		#expect(try NativePlaylistProjection(shared: replacing(linked, unlinkedPatch)).document == NativePlaylistProjection(shared: connected).document)
		let group = try #require(presentation.presentationLayout().groups.first)
		let remoteItem = try NativeContainerAccess.map(stored, keys: ["ItemType", "planning_center", "item"])
		try NativeContainerAccess.write(.map(["linked_song": .map(["sequence": .map(["group_names": .list([.string(group.name), .string(group.name)])])])]), to: remoteItem, message: "rv.data.PlanningCenterPlan.PlanItem")
		let sequenced = try NativeWorkspaceStream(identity: original.identity, snapshot: source.exportSnapshot(), versionVector: source.stateVv().encode(), lastSharedVersionVector: nil)
		let sequenceContext = NativeWorkspaceSnapshot(root: context.root, workspaceID: context.workspaceID, metadata: [:], streams: [sequenced, presentation])
		let arrangementID = UUID()
		let sequence = try NativePlanningCenterSequence(snapshot: sequenceContext, playlistStreamID: original.identity.documentID, itemID: item.id, presentationID: presentationID, arrangementID: arrangementID, name: "PCO local sequence", linkedItemID: nested)
		#expect(sequence.groupIDs == [group.id, group.id])
		// Input order is deliberately reversed: preparation must still use the
		// final Presentation graph when validating the playlist selection.
		let patches = try NativeLocalWorkspaceWriter.prepare(sequence.operations.reversed(), in: sequenceContext)
		#expect(patches.count == 2)
		let effective = NativeWorkspaceSnapshot(root: context.root, workspaceID: context.workspaceID, metadata: [:], streams: sequenceContext.streams.map { stream in
			guard let patch = patches.first(where: { $0.identity.documentID == stream.identity.documentID }) else { return stream }
			return replacing(stream, patch)
		})
		let repeated = try NativePlanningCenterSequence(snapshot: effective, playlistStreamID: original.identity.documentID, itemID: item.id, presentationID: presentationID, arrangementID: arrangementID, name: "PCO local sequence", linkedItemID: nested)
		#expect(try NativeLocalWorkspaceWriter.prepare(repeated.operations, in: effective).isEmpty)
	}

	private func replacing(_ source: NativeWorkspaceStream, _ patch: NativeLocalPatch) -> NativeWorkspaceStream {
		.init(identity: source.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
	}

	private func fixture(_ name: String) throws -> NativeWorkspaceStream {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native")
		let data = try Data(contentsOf: root.appendingPathComponent(name + ".loro"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "f1d34fe9-54bc-5cce-aa9b-975968deaeae")), scope: .shared, kind: "PlaylistLibrary", corePath: nil, availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: root.appendingPathComponent(name + ".vector")), lastSharedVersionVector: nil)
	}
}
