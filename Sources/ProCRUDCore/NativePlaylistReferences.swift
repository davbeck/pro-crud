import Foundation
import ProPresenterProto

enum NativePlaylistDeletion {
	static func validate(_ patches: [NativeLocalPatch], in snapshot: NativeWorkspaceSnapshot) throws -> [NativeWorkspaceStream]? {
		var removed: Set<UUID> = []
		var removedNames: Set<String> = []
		func names(_ nodes: [NativePlaylistLayout.Node], ids: Set<UUID>) -> Set<String> {
			nodes.reduce(into: []) { result, node in
				if ids.contains(node.id) {
					result.insert(node.name)
				}
				result.formUnion(names(node.children, ids: ids))
			}
		}
		func ids(_ nodes: [NativePlaylistLayout.Node]) -> Set<UUID> {
			nodes.reduce(into: []) { $0.formUnion([$1.id]); $0.formUnion(ids($1.children)) }
		}
		for patch in patches where ["PlaylistLibrary", "PlaylistMedia", "PlaylistAudio"].contains(patch.identity.kind) {
			let before = NativeWorkspaceStream(identity: patch.identity, snapshot: patch.originalSnapshot, versionVector: patch.originalVersionVector, lastSharedVersionVector: nil)
			let after = NativeWorkspaceStream(identity: patch.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
			func layout(_ stream: NativeWorkspaceStream) throws -> NativePlaylistLayout {
				try .init(root: stream.decodedValue().object(at: "/").required("root", at: "/"))
			}
			let old = try layout(before), new = try layout(after)
			removed.formUnion(ids(old.playlists + old.liveVideoPlaylists).subtracting(ids(new.playlists + new.liveVideoPlaylists)))
			removedNames.formUnion(names(old.playlists + old.liveVideoPlaylists, ids: removed))
		}
		guard !removed.isEmpty else { return nil }
		for original in snapshot.streams {
			let stream: NativeWorkspaceStream
			if let patch = patches.first(where: { $0.identity.documentID == original.identity.documentID && $0.identity.scope == original.identity.scope }) {
				stream = .init(identity: original.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
			} else {
				stream = original
			}
			guard stream.supportsProtobufProjection, stream.identity.availability == .available else { throw NativeSemanticError.unsupportedNode(path: "/streams/\(stream.identity.documentID)", kind: "playlist-reference inspection requires available mapped content") }
			let projection = try stream.protobufProjection(); try projection.requireComplete()
			_ = try NativeDependencyWire.rewrite(projection.protobuf, message: projection.messageType, path: "/streams/\(stream.identity.documentID)/\(stream.identity.scope)") { data, message, path in
				// Expansion state is not a trigger/reference. It is retained
				// independently in the untouched client stream.
				if message == "rv.data.PlaylistNodeLocal" {
					return data
				}
				if message == "rv.data.UUID", let id = try UUID(uuidString: Rv_Data_UUID(serializedBytes: data).string), removed.contains(id) {
					throw NativeSemanticError.unsupportedNode(path: path, kind: "playlist node \(id) is still referenced; remove the link before deleting its definition")
				}
				if message == "rv.data.Action.PlaylistItemType" {
					let reference = try Rv_Data_Action.PlaylistItemType(serializedBytes: data)
					if reference.playlistUuid.string.isEmpty && removedNames.contains(reference.playlistName) || reference.itemUuid.string.isEmpty && removedNames.contains(reference.itemName) {
						throw NativeSemanticError.unsupportedNode(path: path, kind: "a name-only playlist trigger may still reference a removed node; remove the selector first")
					}
				}
				return nil
			}
		}
		return snapshot.streams
	}
}
