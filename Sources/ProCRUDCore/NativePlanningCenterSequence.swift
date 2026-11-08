import Foundation
import ProPresenterProto

/// Converts the stored remote sequence into explicit local arrangement and
/// link operations. It never changes the plan snapshot or contacts a service.
public struct NativePlanningCenterSequence: Sendable {
	public let playlistStreamID: UUID
	public let itemID: UUID
	public let presentationID: UUID
	public let arrangementID: UUID
	public let groupNames: [String]
	public let groupIDs: [UUID]
	public let operations: [NativePresentationOperation]

	public init(snapshot: NativeWorkspaceSnapshot, playlistStreamID: UUID, itemID: UUID, presentationID: UUID, arrangementID: UUID, name: String, linkedItemID: UUID) throws {
		guard !name.isEmpty else { throw NativeSemanticError.invalidValue(path: "/arrangement/name", expected: "nonempty local arrangement name") }
		guard let stream = snapshot.streams.first(where: { $0.identity.documentID == playlistStreamID && $0.identity.scope == .shared }),
		      let presentation = snapshot.streams.first(where: { $0.identity.documentID == presentationID && $0.identity.scope == .shared && $0.identity.kind == "Presentation" })
		else { throw NativeSemanticError.missingReference(path: "/streams", identity: "playlist and local Presentation") }
		let document = try NativePlaylistProjection(shared: stream).document
		func items(_ node: Rv_Data_Playlist) -> [Rv_Data_PlaylistItem] {
			node.items.items + node.playlists.playlists.flatMap(items)
		}
		let matches = items(document.rootNode).filter { UUID(uuidString: $0.uuid.string) == itemID }
		guard matches.count == 1, let item = matches.first, case let .planningCenter(remote)? = item.itemType, remote.item.linkedSong.hasSequence else { throw NativeSemanticError.invalidValue(path: "/items/\(itemID)", expected: "Planning Center song item with a stored sequence") }
		let names = remote.item.linkedSong.sequence.groupNames
		guard !names.isEmpty else { throw NativeSemanticError.invalidValue(path: "/items/\(itemID)/sequence", expected: "nonempty remote song sequence") }
		let layout = try presentation.presentationLayout()
		let groups = try names.map { name in
			let matches = layout.groups.filter { $0.name == name }
			guard matches.count == 1, let group = matches.first else { throw NativeSemanticError.invalidValue(path: "/items/\(itemID)/sequence/\(name)", expected: "exactly one local cue group with this name; resolve missing or ambiguous labels explicitly") }
			return group.id
		}
		var operations: [NativePresentationOperation] = []
		if layout.arrangements.contains(where: { $0.id == arrangementID }) {
			operations.append(.init(documentID: presentationID, edit: .arrangementGroups(arrangementID, groups)))
			operations.append(.init(documentID: presentationID, edit: .arrangementName(arrangementID, name)))
		} else {
			operations.append(.init(documentID: presentationID, edit: .createArrangement(id: arrangementID, name: name, groups: groups, select: false)))
		}
		if remote.hasLinkedData {
			guard case let .presentation(link)? = remote.linkedData.itemType else { throw NativeSemanticError.invalidValue(path: "/items/\(itemID)/linked_data", expected: "local Presentation link") }
			let url: NativeWorkspaceValue = .map(["RelativeFilePath": .map(["__tag": .string("local"), "local": .map(["root": .integer(Int64(link.documentPath.local.root.rawValue)), "path": .string(link.documentPath.local.path)])])])
			guard try NativeWorkspaceReferenceResolver(streams: snapshot.streams).presentation(url).documentID == presentationID else { throw NativeSemanticError.invalidValue(path: "/items/\(itemID)/linked_data", expected: "link to the explicitly selected local Presentation; unlink before reassigning") }
			operations.append(.init(documentID: playlistStreamID, edit: .playlist(.arrangement(item: itemID, arrangement: arrangementID))))
		} else {
			operations.append(.init(documentID: playlistStreamID, edit: .playlist(.link(item: itemID, presentation: presentationID, linkedID: linkedItemID, arrangement: arrangementID))))
		}
		self.playlistStreamID = playlistStreamID; self.itemID = itemID; self.presentationID = presentationID; self.arrangementID = arrangementID
		groupNames = names; groupIDs = groups; self.operations = operations
	}
}
