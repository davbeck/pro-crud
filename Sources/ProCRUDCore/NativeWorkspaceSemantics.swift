import Foundation

public enum NativeSemanticError: Error, CustomStringConvertible, Sendable, Equatable {
	case invalidValue(path: String, expected: String)
	case duplicateIdentity(path: String, identity: String)
	case missingReference(path: String, identity: String)
	case conflictingOrder(path: String)
	case unsupportedNode(path: String, kind: String)

	public var description: String {
		switch self {
		case let .invalidValue(path, expected): "Invalid native content at \(path): expected \(expected)."
		case let .duplicateIdentity(path, identity): "Duplicate native identity \(identity) at \(path)."
		case let .missingReference(path, identity): "Native reference at \(path) points to missing identity \(identity)."
		case let .conflictingOrder(path): "Native and legacy ordering disagree at \(path); no ordering was guessed."
		case let .unsupportedNode(path, kind): "Unsupported native content \(kind) at \(path)."
		}
	}
}

/// Tree order is supplied by Loro's resolved tree, including its concurrent
/// sibling tie breaking. Fractional positions and node IDs are preserved; they
/// are not UUIDs and must not be sorted as document identities.
public struct NativePlacementNode: Codable, Sendable, Equatable {
	public let nodeID: String
	public let parentID: String?
	public let index: Int
	public let fractionalIndex: String
	public let metadata: NativeWorkspaceValue
	public let children: [NativePlacementNode]

	public static func read(_ value: NativeWorkspaceValue, path: String) throws -> [Self] {
		var seen: Set<String> = []
		return try read(value, parent: nil, path: path, seen: &seen)
	}

	private static func read(_ value: NativeWorkspaceValue, parent: String?, path: String, seen: inout Set<String>) throws -> [Self] {
		try value.array(at: path).enumerated().map { offset, value in
			let path = "\(path)[\(offset)]"
			let node = try value.object(at: path)
			let id = try node.required("id", at: path).text(at: "\(path)/id")
			guard seen.insert(id).inserted else { throw NativeSemanticError.duplicateIdentity(path: path, identity: id) }
			let parentID = try node.optional("parent")?.text(at: "\(path)/parent")
			let index = try node.required("index", at: path).int(at: "\(path)/index")
			guard parentID == parent, index == offset else {
				throw NativeSemanticError.invalidValue(path: path, expected: "resolved sibling index \(offset) and parent \(parent ?? "root")")
			}
			return try Self(nodeID: id, parentID: parentID, index: index,
			                fractionalIndex: node.required("fractional_index", at: path).text(at: "\(path)/fractional_index"),
			                metadata: node.required("meta", at: path),
			                children: read(node.required("children", at: path), parent: id, path: "\(path)/children", seen: &seen))
		}
	}
}

public struct NativePresentationLayout: Codable, Sendable, Equatable {
	public struct CueGroup: Codable, Sendable, Equatable {
		public let id: UUID
		public let nodeID: String
		public let name: String
		public let cueIDs: [UUID]
		public let attributes: NativeWorkspaceValue
	}

	public struct Arrangement: Codable, Sendable, Equatable {
		public let id: UUID
		public let name: String
		public let groupIDs: [UUID]
	}

	public struct MasterEntry: Codable, Sendable, Equatable {
		public enum Kind: String, Codable, Sendable { case group, cue }
		public let kind: Kind
		public let id: UUID
	}

	public let id: UUID
	public let name: String
	public let groups: [CueGroup]
	public let arrangements: [Arrangement]
	public let selectedArrangementID: UUID?
	public let master: [MasterEntry]
	public let unplacedCueIDs: [UUID]
	public let placements: [NativePlacementNode]
	/// Original values remain the preservation source, including unknown fields.
	public let cues: [UUID: NativeWorkspaceValue]

	public init(root value: NativeWorkspaceValue) throws {
		let root = try value.object(at: "/root")
		id = try root.required("uuid", at: "/root").uuid(at: "/root/uuid")
		name = try root.required("name", at: "/root").text(at: "/root/name")
		let values = try root.required("cues", at: "/root").object(at: "/root/cues")
		var cues: [UUID: NativeWorkspaceValue] = [:]
		for (key, value) in values {
			let path = "/root/cues/\(key)"
			guard let id = UUID(uuidString: key) else { throw NativeSemanticError.invalidValue(path: path, expected: "cue UUID key") }
			let cue = try value.object(at: path)
			guard try cue.required("uuid", at: path).uuid(at: "\(path)/uuid") == id else {
				throw NativeSemanticError.invalidValue(path: path, expected: "cue UUID matching its map key")
			}
			guard cues.updateValue(value, forKey: id) == nil else { throw NativeSemanticError.duplicateIdentity(path: path, identity: key) }
		}
		self.cues = cues
		placements = try NativePlacementNode.read(root.required("cue_group_placements", at: "/root"), path: "/root/cue_group_placements")
		var groups: [CueGroup] = []
		var master: [MasterEntry] = []
		var groupIDs: Set<UUID> = []
		var placedCueIDs: Set<UUID> = []
		for node in placements {
			let path = "/root/cue_group_placements/\(node.nodeID)"
			let meta = try node.metadata.object(at: path)
			let id = try meta.required("uuid", at: path).uuid(at: "\(path)/uuid")
			let kind = try meta.required("Kind", at: path).tagged(at: "\(path)/Kind")
			switch kind.tag {
			case "group":
				guard groupIDs.insert(id).inserted else { throw NativeSemanticError.duplicateIdentity(path: path, identity: id.uuidString) }
				let attributes = try kind.value.object(at: path)
				let cueIDs = try node.children.map { child in
					try Self.cueID(child, cues: cues, placed: &placedCueIDs, path: "\(path)/children/\(child.nodeID)")
				}
				try groups.append(.init(id: id, nodeID: node.nodeID, name: attributes.required("name", at: path).text(at: "\(path)/name"), cueIDs: cueIDs, attributes: kind.value))
				master.append(.init(kind: .group, id: id))
			case "cue":
				let id = try Self.cueID(node, cues: cues, placed: &placedCueIDs, path: path)
				master.append(.init(kind: .cue, id: id))
			default: throw NativeSemanticError.unsupportedNode(path: path, kind: kind.tag)
			}
		}
		self.groups = groups
		self.master = master
		unplacedCueIDs = cues.keys.filter { !placedCueIDs.contains($0) }.sorted { $0.uuidString < $1.uuidString }
		arrangements = try root.required("arrangements", at: "/root").array(at: "/root/arrangements").enumerated().map { offset, value in
			let path = "/root/arrangements[\(offset)]"
			let arrangement = try value.object(at: path)
			let ids = try Self.orderedIDs(arrangement, legacy: "group_identifiers", native: "group_identifiers_v2", path: path)
			for id in ids where !groupIDs.contains(id) {
				throw NativeSemanticError.missingReference(path: path, identity: id.uuidString)
			}
			return try Arrangement(id: arrangement.required("uuid", at: path).uuid(at: "\(path)/uuid"),
			                       name: arrangement.required("name", at: path).text(at: "\(path)/name"), groupIDs: ids)
		}
		guard Set(arrangements.map(\.id)).count == arrangements.count else { throw NativeSemanticError.duplicateIdentity(path: "/root/arrangements", identity: "arrangement UUID") }
		selectedArrangementID = try root.optional("selected_arrangement")?.uuid(at: "/root/selected_arrangement")
		if let selectedArrangementID, !arrangements.contains(where: { $0.id == selectedArrangementID }) {
			throw NativeSemanticError.missingReference(path: "/root/selected_arrangement", identity: selectedArrangementID.uuidString)
		}
		if let legacy = root.optional("cue_groups") {
			try Self.validateLegacyGroups(legacy, groups: groups, master: master)
		}
	}

	public func orderedCueIDs(arrangement id: UUID? = nil) throws -> [UUID] {
		let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.cueIDs) })
		if let id {
			guard let arrangement = arrangements.first(where: { $0.id == id }) else {
				throw NativeSemanticError.missingReference(path: "/root/arrangements", identity: id.uuidString)
			}
			return arrangement.groupIDs.flatMap { byID[$0] ?? [] }
		}
		return master.flatMap { $0.kind == .cue ? [$0.id] : byID[$0.id] ?? [] }
	}

	static func orderedIDs(_ object: [String: NativeWorkspaceValue], legacy: String, native: String, path: String) throws -> [UUID] {
		func ids(_ value: NativeWorkspaceValue) throws -> [UUID] {
			try value.array(at: path).enumerated().map { try $0.element.uuid(at: "\(path)[\($0.offset)]") }
		}
		if let nativeValue = object.optional(native) {
			let result = try ids(nativeValue)
			if let legacyValue = object.optional(legacy), try ids(legacyValue) != result {
				throw NativeSemanticError.conflictingOrder(path: path)
			}
			return result
		}
		return try ids(object.required(legacy, at: path))
	}

	private static func cueID(_ node: NativePlacementNode, cues: [UUID: NativeWorkspaceValue], placed: inout Set<UUID>, path: String) throws -> UUID {
		let meta = try node.metadata.object(at: path)
		let kind = try meta.required("Kind", at: path).tagged(at: "\(path)/Kind")
		guard kind.tag == "cue", node.children.isEmpty else { throw NativeSemanticError.unsupportedNode(path: path, kind: kind.tag) }
		let id = try meta.required("uuid", at: path).uuid(at: "\(path)/uuid")
		guard cues[id] != nil else { throw NativeSemanticError.missingReference(path: path, identity: id.uuidString) }
		guard placed.insert(id).inserted else { throw NativeSemanticError.duplicateIdentity(path: path, identity: id.uuidString) }
		return id
	}

	private static func validateLegacyGroups(_ value: NativeWorkspaceValue, groups: [CueGroup], master: [MasterEntry]) throws {
		let legacy = try value.array(at: "/root/cue_groups")
		guard legacy.count == groups.count, master.allSatisfy({ $0.kind == .group }) else { throw NativeSemanticError.conflictingOrder(path: "/root/cue_groups") }
		for (value, group) in zip(legacy, groups) {
			let object = try value.object(at: "/root/cue_groups")
			let attributes = try object.required("group", at: "/root/cue_groups").object(at: "/root/cue_groups/group")
			guard try attributes.required("uuid", at: "/root/cue_groups/group").uuid(at: "/root/cue_groups/group/uuid") == group.id,
			      try orderedIDs(object, legacy: "cue_identifiers", native: "cue_identifiers_v2", path: "/root/cue_groups") == group.cueIDs
			else { throw NativeSemanticError.conflictingOrder(path: "/root/cue_groups") }
		}
	}
}

public extension NativeWorkspaceStream {
	func presentationLayout() throws -> NativePresentationLayout {
		guard identity.kind == "Presentation", identity.scope == .shared else {
			throw NativeSemanticError.invalidValue(path: identity.documentID.uuidString, expected: "shared Presentation stream")
		}
		let value = try decodedValue().object(at: "/")
		let layout = try NativePresentationLayout(root: value.required("root", at: "/"))
		guard layout.id == identity.documentID else { throw NativeSemanticError.invalidValue(path: "/root/uuid", expected: "native stream UUID \(identity.documentID)") }
		return layout
	}
}

extension NativeWorkspaceValue {
	func object(at path: String) throws -> [String: Self] {
		guard case let .map(value) = self else { throw NativeSemanticError.invalidValue(path: path, expected: "map") }
		return value
	}

	func array(at path: String) throws -> [Self] {
		guard case let .list(value) = self else { throw NativeSemanticError.invalidValue(path: path, expected: "list") }
		return value
	}

	func text(at path: String) throws -> String {
		guard case let .string(value) = self else { throw NativeSemanticError.invalidValue(path: path, expected: "string") }
		return value
	}

	func int(at path: String) throws -> Int {
		guard case let .integer(value) = self, let result = Int(exactly: value) else { throw NativeSemanticError.invalidValue(path: path, expected: "integer") }
		return result
	}

	func uuid(at path: String) throws -> UUID {
		let string: String
		if case let .map(object) = self {
			string = try object.required("string", at: path).text(at: path)
		} else {
			string = try text(at: path)
		}
		guard let result = UUID(uuidString: string) else { throw NativeSemanticError.invalidValue(path: path, expected: "UUID") }
		return result
	}

	func tagged(at path: String) throws -> (tag: String, value: Self) {
		let object = try object(at: path)
		let tag = try object.required("__tag", at: path).text(at: "\(path)/__tag")
		return try (tag, object.required(tag, at: path))
	}
}

extension [String: NativeWorkspaceValue] {
	func optional(_ key: String) -> Value? {
		guard let value = self[key], value != .null else { return nil }
		return value
	}

	func required(_ key: String, at path: String) throws -> Value {
		guard let value = optional(key) else { throw NativeSemanticError.invalidValue(path: "\(path)/\(key)", expected: "present value") }
		return value
	}
}
