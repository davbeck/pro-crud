import Foundation
import ProPresenterProto
import SwiftProtobuf

/// A transient protobuf view of shared playlist trees. Only per-node expansion
/// state is read from the matching client stream; shared content remains intact.
public struct NativePlaylistProjection: Sendable {
	public let documentID: UUID
	public let document: Rv_Data_PlaylistDocument
	public let unappliedClientNodeIDs: [UUID]

	public init(shared: NativeWorkspaceStream, client: NativeWorkspaceStream? = nil) throws {
		guard shared.identity.scope == .shared, ["PlaylistLibrary", "PlaylistMedia", "PlaylistAudio"].contains(shared.identity.kind) else {
			throw NativeSemanticError.invalidValue(path: "/playlist", expected: "shared native playlist stream")
		}
		documentID = shared.identity.documentID
		var root = try shared.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root")
		_ = try NativePlaylistLayout(root: .map(root))
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		var expanded: [UUID: Bool] = [:]
		if let client {
			guard client.identity.scope == .client, client.identity.documentID == documentID, client.identity.kind == shared.identity.kind else {
				throw NativeSemanticError.invalidValue(path: "/playlist/client", expected: "matching client playlist identity and kind")
			}
			let local = try client.decodedValue().object(at: "/").required("root", at: "/").object(at: "/client/root")
			_ = try encoder.encode(.map(local), message: "rv.data.PlaylistLocalDocument", path: "/client/root")
			guard local.optional("root_node") == nil, local.optional("live_video_playlist") == nil else {
				throw NativeSemanticError.conflictingOrder(path: "/client/root/node_states")
			}
			if let type = local.optional("type"), type != root.optional("type") {
				throw NativeSemanticError.invalidValue(path: "/client/root/type", expected: "matching shared playlist type")
			}
			for (key, value) in try local.optional("node_states")?.object(at: "/client/root/node_states") ?? [:] {
				let state = try value.object(at: "/client/root/node_states/\(key)")
				guard let id = UUID(uuidString: key), expanded[id] == nil else {
					throw NativeSemanticError.invalidValue(path: "/client/root/node_states/\(key)", expected: "unique key matching its embedded UUID")
				}
				let enabled = state.optional("expanded") ?? .boolean(false)
				guard case let .boolean(value) = enabled else { throw NativeSemanticError.invalidValue(path: key, expected: "boolean expansion state") }
				expanded[id] = value
			}
		}
		var usedClientIDs: Set<UUID> = []
		func convert(_ node: NativePlacementNode, path: String, encoder: inout NativeProtobufEncoder) throws -> NativeWorkspaceValue {
			// Validate every native field before adapting the layouts; no additional
			// native metadata is silently omitted from the transient view.
			_ = try encoder.encode(node.metadata, message: "rv.data.PlaylistNode", path: path)
			let metadata = try node.metadata.object(at: path)
			let id = try metadata.required("uuid", at: path).uuid(at: path)
			let kind = try metadata.required("Kind", at: path).tagged(at: path)
			var result = try kind.value.object(at: path)
			result["uuid"] = metadata["uuid"]
			result["name"] = metadata["name"]
			if kind.tag == "item" {
				guard node.children.isEmpty else { throw NativeSemanticError.unsupportedNode(path: path, kind: "item with children") }
				return .map(result)
			}
			let childKind: String
			switch kind.tag {
			case "group": childKind = "playlists"
			case "playlist": childKind = "items"
			default: throw NativeSemanticError.unsupportedNode(path: path, kind: kind.tag)
			}
			var children: [NativeWorkspaceValue] = []
			for child in node.children {
				let childTag = try child.metadata.object(at: path).required("Kind", at: path).tagged(at: path).tag
				guard (kind.tag == "playlist") == (childTag == "item") else {
					throw NativeSemanticError.unsupportedNode(path: path, kind: "\(childTag) inside \(kind.tag)")
				}
				try children.append(convert(child, path: "\(path)/\(child.nodeID)", encoder: &encoder))
			}
			result["ChildrenType"] = .map(["__tag": .string(childKind), childKind: .map([childKind: .list(children)])])
			if let value = expanded[id] {
				result["expanded"] = .boolean(value)
				usedClientIDs.insert(id)
			}
			return .map(result)
		}
		for (native, legacy) in [("playlists", "root_node"), ("live_video_playlist_nodes", "live_video_playlist")] {
			let nodes = try NativePlacementNode.read(root.required(native, at: "/root"), path: "/root/\(native)")
			root.removeValue(forKey: native)
			guard nodes.count <= 1 else { throw NativeSemanticError.unsupportedNode(path: "/root/\(native)", kind: "multiple roots without one legacy root identity") }
			if let node = nodes.first {
				root[legacy] = try convert(node, path: "/root/\(native)/\(node.nodeID)", encoder: &encoder)
			}
		}
		let bytes = try encoder.encode(.map(root), message: Rv_Data_PlaylistDocument.protoMessageName, path: "/root")
		guard encoder.issues.isEmpty else { throw NativeProjectionError(issues: encoder.issues) }
		document = try Rv_Data_PlaylistDocument(serializedBytes: bytes)
		unappliedClientNodeIDs = expanded.keys.filter { !usedClientIDs.contains($0) }.sorted { $0.uuidString < $1.uuidString }
	}
}
