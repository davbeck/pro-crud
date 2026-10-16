import Foundation
import Loro

enum NativeGroupCreation {
	static func split(startingAt cueID: UUID, newID: UUID, templateID: UUID, name: String, layout: NativePresentationLayout, root: LoroMap) throws {
		try NativeStructuralEditing.requireNativePlacements(root)
		guard !name.isEmpty else { throw NativeSemanticError.invalidValue(path: "/cue_group_placements/\(newID)/name", expected: "nonempty group name") }
		guard newID != templateID else { throw NativeSemanticError.duplicateIdentity(path: "/cue_group_placements", identity: newID.uuidString) }
		guard let template = layout.groups.first(where: { $0.id == templateID }) else { throw NativeSemanticError.missingReference(path: "/cue_group_placements", identity: templateID.uuidString) }
		let path = "/cue_group_placements/\(templateID)/Kind/group"
		var attributes = try template.attributes.object(at: path)
		guard Set(attributes.keys) == ["name", "color", "hot_key", "application_group_identifier"] else { throw NativeSemanticError.unsupportedNode(path: path, kind: "unqualified template group metadata") }
		let color = try attributes.required("color", at: path).object(at: "\(path)/color")
		let hotKey = try attributes.required("hot_key", at: path).object(at: "\(path)/hot_key")
		guard Set(color.keys).isSubset(of: ["red", "green", "blue", "alpha"]), Set(hotKey.keys) == ["code"] else { throw NativeSemanticError.unsupportedNode(path: path, kind: "unqualified group color or hotkey metadata") }
		var typed = attributes
		typed["hotKey"] = typed.removeValue(forKey: "hot_key")
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		_ = try encoder.encode(.map(typed), message: "rv.data.Group", path: path)
		guard encoder.issues.isEmpty else { throw NativeProjectionError(issues: encoder.issues) }
		attributes["name"] = .string(name)
		if let existing = layout.groups.first(where: { $0.id == newID }) {
			guard existing.attributes == .map(attributes), existing.cueIDs.first == cueID else { throw NativeSemanticError.duplicateIdentity(path: "/cue_group_placements", identity: newID.uuidString) }
			return
		}
		guard let source = layout.groups.first(where: { $0.cueIDs.contains(cueID) }), let offset = source.cueIDs.firstIndex(of: cueID) else { throw NativeSemanticError.missingReference(path: "/cue_group_placements", identity: cueID.uuidString) }
		guard offset > 0 else { throw NativeSemanticError.unsupportedNode(path: "/cue_group_placements/\(cueID)", kind: "splitting at the first cue; select a later cue in its group") }
		guard let sourceIndex = layout.placements.firstIndex(where: { $0.nodeID == source.nodeID }),
		      let tree = root.get(key: "cue_group_placements")?.asLoroTree(),
		      let definition = try tree.getMeta(target: NativeStructuralEditing.treeID(template.nodeID)).get(key: "Kind")?.asLoroMap()?.get(key: "group")?.asLoroMap(),
		      let nativeColor = definition.get(key: "color")?.asValue(), let applicationGroup = definition.get(key: "application_group_identifier")?.asValue(),
		      let nativeHotKey = definition.get(key: "hot_key")?.asLoroMap()?.get(key: "code")?.asValue()
		else { throw NativeSemanticError.invalidValue(path: path, expected: "native group maps, atomic color and hotkey map") }
		tree.enableFractionalIndex(jitter: 0)
		let node = try tree.createAt(parent: .root, index: UInt32(sourceIndex + 1))
		let metadata = try tree.getMeta(target: node)
		try metadata.insert(key: "uuid", v: newID.uuidString)
		let kind = try metadata.insertContainer(key: "Kind", child: LoroMap())
		try kind.insert(key: "__tag", v: "group")
		let group = try kind.insertContainer(key: "group", child: LoroMap())
		try group.insert(key: "name", v: name)
		try group.insert(key: "application_group_identifier", v: applicationGroup)
		try group.insert(key: "color", v: nativeColor)
		let hotKeyMap = try group.insertContainer(key: "hot_key", child: LoroMap())
		try hotKeyMap.insert(key: "code", v: nativeHotKey)
		for (index, child) in layout.placements[sourceIndex].children.dropFirst(offset).enumerated() {
			try tree.movTo(target: NativeStructuralEditing.treeID(child.nodeID), parent: .node(id: node), to: UInt32(index))
		}
	}
}
