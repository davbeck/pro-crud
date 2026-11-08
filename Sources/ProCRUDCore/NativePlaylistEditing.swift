import Foundation
import Loro

public enum NativePlaylistEdit: Codable, Sendable, Equatable {
	case rename(UUID, String)
	case hidden(UUID, Bool)
	case move(UUID, parent: UUID, after: UUID?)
	case remove(UUID)
	case create(id: UUID, parent: UUID, name: String, kind: NewNode, after: UUID?)
	case link(item: UUID, presentation: UUID, linkedID: UUID, arrangement: UUID?)
	case unlink(UUID)
	case arrangement(item: UUID, arrangement: UUID?)

	public enum NewNode: Codable, Sendable, Equatable {
		case group, playlist, header
		case presentation(UUID, arrangement: UUID?)
	}
}

enum NativePlaylistEditing {
	static func apply(_ edit: NativePlaylistEdit, document: LoroDoc, identity: NativeWorkspaceStream.Identity, context: NativeWorkspaceSnapshot?) throws {
		guard ["PlaylistLibrary", "PlaylistMedia", "PlaylistAudio"].contains(identity.kind) else { throw NativeSemanticError.invalidValue(path: "/playlist", expected: "native playlist stream") }
		let stream = try NativeWorkspaceStream(identity: identity, snapshot: document.exportSnapshot(), versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
		_ = try NativePlaylistProjection(shared: stream)
		let root = document.getMap(id: "root")
		let layout = try NativePlaylistLayout(root: NativeWorkspaceValue(root.getDeepValue()))
		guard let tree = root.get(key: "playlists")?.asLoroTree() else { throw NativeSemanticError.invalidValue(path: "/playlists", expected: "native playlist tree") }
		func flatten(_ nodes: [NativePlaylistLayout.Node]) -> [NativePlaylistLayout.Node] {
			nodes.flatMap { [$0] + flatten($0.children) }
		}
		let nodes = flatten(layout.playlists)
		func identities(_ value: NativeWorkspaceValue) -> Set<UUID> {
			switch value {
			case let .map(values):
				var ids = values.values.reduce(into: Set<UUID>()) { $0.formUnion(identities($1)) }
				if let value = values["uuid"], let id = try? value.uuid(at: "/uuid") {
					ids.insert(id)
				}
				return ids
			case let .list(values): return values.reduce(into: []) { $0.formUnion(identities($1)) }
			default: return []
			}
		}
		let existingIDs = try identities(NativeWorkspaceValue(root.getDeepValue()))
		func node(_ id: UUID) throws -> NativePlaylistLayout.Node {
			guard let result = nodes.first(where: { $0.id == id }) else { throw NativeSemanticError.missingReference(path: "/playlists", identity: id.uuidString) }
			return result
		}
		func parent(_ id: UUID) -> NativePlaylistLayout.Node? {
			nodes.first { $0.children.contains { $0.id == id } }
		}
		func metadata(_ node: NativePlaylistLayout.Node) throws -> LoroMap {
			try tree.getMeta(target: NativeStructuralEditing.treeID(node.nodeID))
		}
		func attributes(_ node: NativePlaylistLayout.Node) throws -> LoroMap {
			try NativeContainerAccess.map(metadata(node), keys: ["Kind", node.kind.rawValue])
		}
		func requireLocal(_ node: NativePlaylistLayout.Node) throws {
			var current: NativePlaylistLayout.Node? = node
			while let selected = current {
				let fields = try selected.attributes.object(at: "/playlists/\(selected.id)")
				let link = try fields.optional("LinkData")?.object(at: "/LinkData")
				if link?.optional("__tag") != nil || fields.optional("provider") != nil || fields.optional("provider_info") != nil {
					throw NativeSemanticError.unsupportedNode(path: "/playlists/\(selected.id)", kind: "connected/provider-owned structure; use local link, arrangement or visibility operations")
				}
				if selected.kind == .item, let type = fields.optional("ItemType"), try type.tagged(at: "/ItemType").tag == "planning_center" {
					throw NativeSemanticError.unsupportedNode(path: "/playlists/\(selected.id)", kind: "Planning Center-owned item")
				}
				current = parent(selected.id)
			}
		}
		func item(_ id: UUID) throws -> LoroMap {
			let selected = try node(id)
			guard selected.kind == .item else { throw NativeSemanticError.invalidValue(path: "/playlists/\(id)", expected: "playlist item") }
			return try attributes(selected)
		}
		func localPresentation(_ id: UUID) throws -> LoroMap {
			let stored = try item(id)
			var type = try NativeContainerAccess.map(stored, keys: ["ItemType"])
			if type.get(key: "__tag")?.asValue() == .string(value: "planning_center") {
				type = try NativeContainerAccess.map(type, keys: ["planning_center", "linked_data", "ItemType"])
			}
			guard type.get(key: "__tag")?.asValue() == .string(value: "presentation") else { throw NativeSemanticError.invalidValue(path: "/playlists/\(id)", expected: "linked local Presentation") }
			return try NativeContainerAccess.map(type, keys: ["presentation"])
		}
		func position(parent destination: NativePlaylistLayout.Node, after: UUID?, excluding: UUID? = nil) throws -> UInt32 {
			let children = destination.children.filter { $0.id != excluding }
			guard let after else { return 0 }
			guard let index = children.firstIndex(where: { $0.id == after }) else { throw NativeSemanticError.missingReference(path: "/playlists/\(destination.id)/children", identity: after.uuidString) }
			return UInt32(index + 1)
		}
		switch edit {
		case let .rename(id, name):
			let selected = try node(id)
			try requireLocal(selected)
			guard !name.isEmpty, parent(id) != nil else { throw NativeSemanticError.invalidValue(path: "/playlists/\(id)", expected: "non-root node and nonempty name") }
			if selected.name != name {
				try metadata(selected).insert(key: "name", v: name)
			}
		case let .hidden(id, hidden):
			let stored = try item(id)
			let current = stored.get(key: "is_hidden")?.asValue() ?? .bool(value: false)
			if current != .bool(value: hidden) {
				try stored.insert(key: "is_hidden", v: hidden)
			}
		case let .move(id, parentID, after):
			let selected = try node(id), destination = try node(parentID)
			try requireLocal(selected); try requireLocal(destination)
			guard parent(id) != nil, !flatten([selected]).contains(where: { $0.id == parentID }),
			      selected.kind == .item ? destination.kind == .playlist : destination.kind == .group
			else { throw NativeSemanticError.invalidValue(path: "/playlists/\(id)", expected: "acyclic compatible parent, retaining the root") }
			if after == id {
				return
			}
			let index = try position(parent: destination, after: after, excluding: id)
			if parent(id)?.id == parentID, destination.children.firstIndex(where: { $0.id == id }) == Int(index) {
				return
			}
			tree.enableFractionalIndex(jitter: 0)
			try tree.movTo(target: NativeStructuralEditing.treeID(selected.nodeID), parent: .node(id: NativeStructuralEditing.treeID(destination.nodeID)), to: index)
		case let .remove(id):
			let selected = try node(id)
			try requireLocal(selected)
			guard parent(id) != nil, selected.children.isEmpty else { throw NativeSemanticError.invalidValue(path: "/playlists/\(id)", expected: "non-root item or empty playlist/group") }
			try tree.delete(target: NativeStructuralEditing.treeID(selected.nodeID))
		case let .create(id, parentID, name, kind, after):
			let destination = try node(parentID)
			try requireLocal(destination)
			let tag: String
			switch kind { case .group: tag = "group"; case .playlist: tag = "playlist"; default: tag = "item" }
			guard !name.isEmpty, tag == "item" ? destination.kind == .playlist : destination.kind == .group else { throw NativeSemanticError.invalidValue(path: "/playlists/\(parentID)", expected: "compatible parent and nonempty node name") }
			let value = try newAttributes(kind, context: context)
			if let existing = nodes.first(where: { $0.id == id }) {
				var actual = try existing.attributes.object(at: "/playlists/\(id)")
				var expected = try value.object(at: "/new")
				// Visibility is a separate local overlay, including when set later
				// in the same batch. Creation initializes it only for new nodes.
				actual.removeValue(forKey: "is_hidden"); expected.removeValue(forKey: "is_hidden")
				guard parent(id)?.id == parentID, existing.name == name, existing.kind.rawValue == tag, actual == expected else { throw NativeSemanticError.duplicateIdentity(path: "/playlists", identity: id.uuidString) }
				return
			}
			guard !existingIDs.contains(id) else { throw NativeSemanticError.duplicateIdentity(path: "/playlists", identity: id.uuidString) }
			let index = try position(parent: destination, after: after)
			tree.enableFractionalIndex(jitter: 0)
			let created = try tree.createAt(parent: .node(id: NativeStructuralEditing.treeID(destination.nodeID)), index: index)
			let meta = try tree.getMeta(target: created)
			try meta.insert(key: "uuid", v: id.uuidString); try meta.insert(key: "name", v: name)
			let wrapper = try meta.insertContainer(key: "Kind", child: LoroMap())
			try wrapper.insert(key: "__tag", v: tag)
			try NativeContainerAccess.write(value, to: wrapper.insertContainer(key: tag, child: LoroMap()), message: tag == "item" ? "rv.data.PlaylistNode.Item" : tag == "group" ? "rv.data.PlaylistNode.Group" : "rv.data.PlaylistNode.Playlist")
		case let .link(id, presentationID, linkedID, arrangement):
			guard !nodes.contains(where: { $0.id == linkedID }) else { throw NativeSemanticError.duplicateIdentity(path: "/linked_data", identity: linkedID.uuidString) }
			let stored = try item(id)
			let type = try NativeContainerAccess.map(stored, keys: ["ItemType"])
			guard type.get(key: "__tag")?.asValue() == .string(value: "planning_center") else { throw NativeSemanticError.invalidValue(path: "/playlists/\(id)", expected: "Planning Center wrapper") }
			let planning = try NativeContainerAccess.map(type, keys: ["planning_center"])
			let link = try presentation(presentationID, arrangement: arrangement, context: context)
			let linked: NativeWorkspaceValue = .map(["uuid": .string(linkedID.uuidString), "name": .string(link.name), "ItemType": .map(["__tag": .string("presentation"), "presentation": link.value]), "is_hidden": .boolean(false)])
			if let existing = planning.get(key: "linked_data"), existing.asValue() != .null {
				guard try NativeWorkspaceValue(existing.asLoroMap()?.getDeepValue() ?? existing.asValue() ?? .null) == linked else { throw NativeSemanticError.invalidValue(path: "/playlists/\(id)/linked_data", expected: "unlinked item; unlink before assigning different content") }
				return
			}
			guard !existingIDs.contains(linkedID) else { throw NativeSemanticError.duplicateIdentity(path: "/linked_data", identity: linkedID.uuidString) }
			try NativeContainerAccess.write(linked, to: planning.insertContainer(key: "linked_data", child: LoroMap()), message: "rv.data.PlaylistItem")
		case let .unlink(id):
			let type = try NativeContainerAccess.map(item(id), keys: ["ItemType"])
			guard type.get(key: "__tag")?.asValue() == .string(value: "planning_center") else { throw NativeSemanticError.invalidValue(path: "/playlists/\(id)", expected: "Planning Center wrapper") }
			let planning = try NativeContainerAccess.map(type, keys: ["planning_center"])
			if let existing = planning.get(key: "linked_data"), existing.asValue() != .null {
				try planning.delete(key: "linked_data")
			}
		case let .arrangement(id, arrangement):
			let stored = try localPresentation(id)
			let value = try NativeWorkspaceValue(stored.getDeepValue()).object(at: "/presentation")
			guard let context else { throw NativeSemanticError.invalidValue(path: "/context", expected: "workspace snapshot for Presentation selection") }
			let reference = try NativeWorkspaceReferenceResolver(streams: context.streams).presentation(value.required("document_path", at: "/presentation"))
			guard let target = reference.documentID else { throw NativeSemanticError.missingReference(path: "/presentation", identity: reference.logicalPath ?? "unresolved Presentation") }
			let selected = try presentation(target, arrangement: arrangement, context: context)
			let fields = try selected.value.object(at: "/presentation")
			for key in ["arrangement", "arrangement_name"] {
				let replacement = try NativeContainerAccess.atomic(fields[key] ?? .null)
				if stored.get(key: key)?.asValue() != replacement {
					try stored.insert(key: key, v: replacement)
				}
			}
		}
	}

	private static func newAttributes(_ kind: NativePlaylistEdit.NewNode, context: NativeWorkspaceSnapshot?) throws -> NativeWorkspaceValue {
		switch kind {
		case .group: return .map([:])
		case .playlist: return .map(["LinkData": .map(["__tag": .null])])
		case .header: return .map(["is_hidden": .boolean(false), "ItemType": .map(["__tag": .string("header"), "header": .map(["actions": .list([]), "color": .map(["red": .number(0), "green": .number(0), "blue": .number(0), "alpha": .number(1)])])])])
		case let .presentation(id, arrangement): return try .map(["is_hidden": .boolean(false), "ItemType": .map(["__tag": .string("presentation"), "presentation": presentation(id, arrangement: arrangement, context: context).value])])
		}
	}

	private static func presentation(_ id: UUID, arrangement: UUID?, context: NativeWorkspaceSnapshot?) throws -> (name: String, value: NativeWorkspaceValue) {
		guard let stream = context?.streams.first(where: { $0.identity.documentID == id && $0.identity.scope == .shared && $0.identity.kind == "Presentation" }), let path = stream.identity.corePath else { throw NativeSemanticError.missingReference(path: "/Presentation", identity: id.uuidString) }
		let layout = try stream.presentationLayout()
		var selected: NativeWorkspaceValue = .null
		if let arrangement {
			guard let index = layout.arrangements.firstIndex(where: { $0.id == arrangement }) else { throw NativeSemanticError.missingReference(path: "/Presentation/\(id)/arrangements", identity: arrangement.uuidString) }
			let root = try stream.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root")
			selected = try root.required("arrangements", at: "/root").array(at: "/arrangements")[index].object(at: "/arrangement").required("uuid", at: "/arrangement")
		}
		return (layout.name, .map(["document_path": .map(["platform": .integer(1), "Storage": .null, "RelativeFilePath": .map(["__tag": .string("local"), "local": .map(["root": .integer(10), "path": .string("Libraries/\(path).pro")])])]), "arrangement": selected, "arrangement_name": .string(layout.arrangements.first { $0.id == arrangement }?.name ?? ""), "content_destination": .integer(0)]))
	}
}
