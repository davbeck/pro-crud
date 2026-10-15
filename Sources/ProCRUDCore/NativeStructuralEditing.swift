import Foundation
import Loro

enum NativeStructuralEditing {
	static func treeID(_ value: String) throws -> TreeId {
		let parts = value.split(separator: "@", omittingEmptySubsequences: false)
		guard parts.count == 2, let counter = Int32(parts[0]), counter >= 0, let peer = UInt64(parts[1]) else { throw NativeSemanticError.invalidValue(path: "/cue_group_placements/\(value)", expected: "Loro counter@peer node identity") }
		return TreeId(peer: peer, counter: counter)
	}

	static func requireNativePlacements(_ root: LoroMap) throws {
		guard root.get(key: "cue_groups") == nil else { throw NativeSemanticError.unsupportedNode(path: "/cue_groups", kind: "parallel legacy group representation in a native structural edit") }
	}

	static func rename(group: NativePresentationLayout.CueGroup, to name: String, root: LoroMap) throws {
		try requireNativePlacements(root)
		guard let tree = root.get(key: "cue_group_placements")?.asLoroTree(),
		      let attributes = try tree.getMeta(target: treeID(group.nodeID)).get(key: "Kind")?.asLoroMap()?.get(key: "group")?.asLoroMap()
		else { throw NativeSemanticError.invalidValue(path: "/cue_group_placements/\(group.id)/Kind/group", expected: "native group metadata maps") }
		try attributes.insert(key: "name", v: name)
	}

	static func transfer(cue cueID: UUID, to groupID: UUID, after anchorID: UUID?, layout: NativePresentationLayout, root: LoroMap, validateReferences: () throws -> Void) throws {
		try requireNativePlacements(root)
		guard let destination = layout.groups.first(where: { $0.id == groupID }),
		      let placement = layout.placements.first(where: { $0.nodeID == destination.nodeID })
		else { throw NativeSemanticError.missingReference(path: "/cue_group_placements", identity: groupID.uuidString) }
		let nodes = layout.placements.flatMap { [$0] + $0.children }
		guard layout.cues[cueID] != nil, let source = try nodes.first(where: { node in
			let meta = try node.metadata.object(at: "/placement")
			return try meta.required("Kind", at: "/placement").tagged(at: "/placement/Kind").tag == "cue" && meta.required("uuid", at: "/placement").uuid(at: "/placement/uuid") == cueID
		}) else { throw NativeSemanticError.missingReference(path: "/cue_group_placements", identity: cueID.uuidString) }
		if let anchorID, !destination.cueIDs.contains(anchorID) {
			throw NativeSemanticError.missingReference(path: "/cue_group_placements/\(groupID)/children", identity: anchorID.uuidString)
		}
		if anchorID == cueID {
			return
		}
		if anchorID == nil, source.parentID == destination.nodeID, source.index == destination.cueIDs.count - 1 {
			return
		}
		let emptied = layout.groups.first { $0.nodeID == source.parentID && $0.id != groupID && $0.cueIDs.count == 1 }
		if emptied != nil {
			try validateReferences()
		}
		let anchor = anchorID ?? destination.cueIDs.last(where: { $0 != cueID })
		guard let tree = root.get(key: "cue_group_placements")?.asLoroTree() else { throw NativeSemanticError.invalidValue(path: "/cue_group_placements", expected: "native Loro tree") }
		tree.enableFractionalIndex(jitter: 0)
		if let anchor, let index = destination.cueIDs.firstIndex(of: anchor) {
			let target = placement.children[index]
			if source.parentID == destination.nodeID, source.index == target.index + 1 {
				return
			}
			try tree.movAfter(target: treeID(source.nodeID), after: treeID(target.nodeID))
		} else {
			try tree.mov(target: treeID(source.nodeID), parent: .node(id: treeID(destination.nodeID)))
		}
		if let emptied {
			try tree.delete(target: treeID(emptied.nodeID))
			for (index, arrangement) in layout.arrangements.enumerated() where arrangement.groupIDs.contains(emptied.id) {
				let list = try groupList(at: index, root: root)
				for (position, group) in arrangement.groupIDs.enumerated().reversed() where group == emptied.id {
					try list.delete(pos: UInt32(position), len: 1)
				}
			}
		}
	}

	static func setGroups(_ groups: [UUID], replacing original: [UUID], at index: Int, root: LoroMap) throws {
		let list = try groupList(at: index, root: root)
		// Reuse and move existing occurrences, including repeated group IDs.
		// Insert only absent occurrences and remove only those not selected.
		var current = original
		for (index, group) in groups.enumerated() {
			if index < current.count, current[index] == group {
				continue
			}
			if let existing = current.indices.dropFirst(index).first(where: { current[$0] == group }) {
				try list.mov(from: UInt32(existing), to: UInt32(index))
				current.insert(current.remove(at: existing), at: index)
			} else {
				try list.insert(pos: UInt32(index), v: group.uuidString)
				current.insert(group, at: index)
			}
		}
		if current.count > groups.count {
			try list.delete(pos: UInt32(groups.count), len: UInt32(current.count - groups.count))
		}
	}

	private static func groupList(at index: Int, root: LoroMap) throws -> LoroMovableList {
		let path = "/arrangements[\(index)]"
		guard let arrangements = root.get(key: "arrangements")?.asLoroMovableList(),
		      let arrangement = arrangements.get(index: UInt32(index))?.asLoroMap(),
		      let list = arrangement.get(key: "group_identifiers_v2")?.asLoroMovableList()
		else { throw NativeSemanticError.invalidValue(path: path, expected: "native arrangement and v2 movable group list") }
		guard arrangement.get(key: "group_identifiers") == nil else { throw NativeSemanticError.unsupportedNode(path: path, kind: "parallel legacy arrangement sequence in a native structural edit") }
		return list
	}
}
