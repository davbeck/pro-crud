import AppKit
import CryptoKit
import Foundation
import Loro
import ProPresenterProto

public enum NativePresentationEdit: Codable, Sendable, Equatable {
	case presentationName(String)
	case notes(String)
	case copyrightTitle(String)
	case slideNotes(actionID: UUID, content: NativeSlideNotesContent)
	case moveCue(UUID, after: UUID)
	case cueGroupName(UUID, String)
	case arrangementGroups(UUID, [UUID])
}

public enum NativeSlideNotesContent: Codable, Sendable, Equatable {
	case text(String)
	case rtf(Data)

	func encoded(replacing original: Data) throws -> Data? {
		switch self {
		case let .rtf(data):
			_ = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
			return data == original ? nil : data
		case let .text(text):
			let existing = original.isEmpty ? NSAttributedString(string: "") : try NSAttributedString(data: original, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
			guard existing.string != text else { return nil }
			let attributes = existing.length > 0 ? existing.attributes(at: 0, effectiveRange: nil) : [.font: NSFont(name: "HelveticaNeue", size: 24) ?? NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.white]
			let replacement = NSAttributedString(string: text, attributes: attributes)
			return try replacement.data(from: NSRange(location: 0, length: replacement.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
		}
	}
}

/// Prepared operations on an imported native history, not a rebuilt JSON map.
/// Preparing a patch never writes SQLite or requires a running application.
public struct NativeLocalPatch: Sendable {
	public let operationID: UUID
	public let identity: NativeWorkspaceStream.Identity
	public let originalSnapshot: Data
	public let originalVersionVector: Data
	public let snapshot: Data
	public let versionVector: Data
	public let update: Data
	public let payloadFingerprint: Data
	public let sha256: Data
	public let timestampMilliseconds: Int64

	public static func prepare(stream: NativeWorkspaceStream, edit: NativePresentationEdit, operationID: UUID = UUID(), date: Date = Date()) throws -> Self? {
		guard stream.identity.kind == "Presentation", stream.identity.scope == .shared else {
			throw NativeSemanticError.invalidValue(path: stream.identity.documentID.uuidString, expected: "shared Presentation stream")
		}
		let layout = try stream.presentationLayout()
		guard let original = stream.snapshot, let vector = stream.versionVector else { throw NativeWorkspaceError.unavailableStream(stream.identity.documentID.uuidString) }
		let document = LoroDoc()
		_ = try document.import(bytes: original)
		let originalVersion = try VersionVector.decode(bytes: vector)
		let root = document.getMap(id: "root")
		switch edit {
		case let .presentationName(name):
			guard !name.isEmpty else { throw NativeSemanticError.invalidValue(path: "/root/name", expected: "nonempty presentation name") }
			try root.insert(key: "name", v: name)
		case let .notes(notes): try root.insert(key: "notes", v: notes)
		case let .copyrightTitle(title):
			guard let ccli = root.get(key: "ccli")?.asLoroMap() else { throw NativeSemanticError.invalidValue(path: "/root/ccli", expected: "existing native CCLI map") }
			try ccli.insert(key: "song_title", v: title)
		case let .slideNotes(actionID, content):
			let presentation = try stream.protobufProjection().presentation()
			let matches = presentation.cues.flatMap { cue in cue.actions.enumerated().compactMap { index, action in UUID(uuidString: action.uuid.string) == actionID ? (cue.uuid.string, index, action) : nil } }
			guard matches.count == 1, let (cueID, index, action) = matches.first, action.type == .presentationSlide, case .presentation? = action.slide.slide else {
				throw NativeSemanticError.invalidValue(path: "/actions/\(actionID)", expected: "one Presentation slide action")
			}
			guard let rtf = try content.encoded(replacing: action.slide.presentation.notes.rtfData) else { return nil }
			guard let cues = root.get(key: "cues")?.asLoroMap(), let cue = cues.get(key: cueID)?.asLoroMap(),
			      let actions = cue.get(key: "actions")?.asLoroMovableList(), let storedAction = actions.get(index: UInt32(index))?.asLoroMap()
			else { throw NativeSemanticError.invalidValue(path: "/actions/\(actionID)", expected: "native cue map and movable action list") }
			var slide = storedAction
			for key in ["ActionTypeData", "slide", "Slide", "presentation"] {
				guard let child = slide.get(key: key)?.asLoroMap() else { throw NativeSemanticError.invalidValue(path: "/actions/\(actionID)/\(key)", expected: "native map") }
				slide = child
			}
			let notes: LoroMap
			if let existing = slide.get(key: "notes") {
				guard let map = existing.asLoroMap() else { throw NativeSemanticError.invalidValue(path: "/actions/\(actionID)/notes", expected: "native notes map") }
				notes = map
			} else {
				notes = try slide.insertContainer(key: "notes", child: LoroMap())
			}
			try notes.insert(key: "rtf_data", v: LoroValue.binary(value: rtf))
		case let .cueGroupName(groupID, name):
			guard !name.isEmpty else { throw NativeSemanticError.invalidValue(path: "/cue_group_placements/\(groupID)/name", expected: "nonempty group name") }
			guard let group = layout.groups.first(where: { $0.id == groupID }) else { throw NativeSemanticError.missingReference(path: "/cue_group_placements", identity: groupID.uuidString) }
			guard group.name != name else { return nil }
			try NativeStructuralEditing.rename(group: group, to: name, root: root)
		case let .arrangementGroups(arrangementID, groups):
			guard let index = layout.arrangements.firstIndex(where: { $0.id == arrangementID }) else { throw NativeSemanticError.missingReference(path: "/arrangements", identity: arrangementID.uuidString) }
			for id in groups where !layout.groups.contains(where: { $0.id == id }) {
				throw NativeSemanticError.missingReference(path: "/arrangements/\(arrangementID)", identity: id.uuidString)
			}
			let original = layout.arrangements[index].groupIDs
			guard original != groups else { return nil }
			try NativeStructuralEditing.setGroups(groups, replacing: original, at: index, root: root)
		case let .moveCue(cueID, after: anchorID):
			try NativeStructuralEditing.requireNativePlacements(root)
			let nodes = layout.placements.flatMap(\.children)
			func node(_ id: UUID) throws -> NativePlacementNode {
				guard let node = try nodes.first(where: { try $0.metadata.object(at: "/placement").required("uuid", at: "/placement").uuid(at: "/placement/uuid") == id }) else {
					throw NativeSemanticError.missingReference(path: "/cue_group_placements", identity: id.uuidString)
				}
				return node
			}
			let source = try node(cueID)
			let anchor = try node(anchorID)
			guard source.parentID == anchor.parentID else { throw NativeSemanticError.invalidValue(path: "/cue_group_placements", expected: "cue and anchor in the same group") }
			if cueID == anchorID || source.index == anchor.index + 1 {
				return nil
			}
			guard let tree = root.get(key: "cue_group_placements")?.asLoroTree() else { throw NativeSemanticError.invalidValue(path: "/cue_group_placements", expected: "native Loro tree") }
			tree.enableFractionalIndex(jitter: 0)
			try tree.movAfter(target: NativeStructuralEditing.treeID(source.nodeID), after: NativeStructuralEditing.treeID(anchor.nodeID))
		}
		let timestamp = Int64(date.timeIntervalSince1970 * 1000)
		guard timestamp >= 0 else { throw NativeSemanticError.invalidValue(path: "/commit/timestamp", expected: "nonnegative timestamp") }
		document.commitWith(options: .init(origin: "pro-crud", immediateRenew: true, timestamp: timestamp / 1000, commitMsg: nil))
		guard !document.oplogVv().eq(other: originalVersion) else { return nil }
		let update = try document.exportUpdates(vv: originalVersion)
		let snapshot = try document.exportSnapshot()
		// ProPresenter validates the encoded state vector of a freshly imported
		// snapshot byte for byte. The equivalent oplog vector can use a different
		// map iteration order, so it is not a substitute for this stored value.
		let stored = LoroDoc()
		_ = try stored.import(bytes: snapshot)
		let version = stored.stateVv().encode()
		return .init(operationID: operationID, identity: stream.identity, originalSnapshot: original, originalVersionVector: vector,
		             snapshot: snapshot, versionVector: version, update: update, payloadFingerprint: Data(SHA256.hash(data: update)),
		             sha256: Data(SHA256.hash(data: snapshot)), timestampMilliseconds: timestamp)
	}
}
