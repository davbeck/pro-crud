import AppKit
import Foundation
import ProPresenterProto
import SwiftProtobuf
import UniformTypeIdentifiers

public enum DocumentEditError: Error, CustomStringConvertible, Sendable {
	case unsupportedPatchValue(String)
	case planningCenterManagedContent(path: String)
	case notPlanningCenterItem(path: String)
	case planningCenterItemAlreadyLinked(path: String)
	case planningCenterItemNotLinked(path: String)
	case planningCenterItemOutsideConnectedPlaylist(path: String)

	public var description: String {
		switch self {
		case let .unsupportedPatchValue(reason): reason
		case let .planningCenterManagedContent(path):
			"\(path) is managed by Planning Center. Convert the connected playlist to a regular playlist before changing its structure; use edit set-playlist-item-hidden to change local visibility."
		case let .notPlanningCenterItem(path):
			"\(path) is not a Planning Center item. Link and unlink operations require a Planning Center item wrapper."
		case let .planningCenterItemAlreadyLinked(path):
			"\(path) is already linked. Unlink it before selecting a different presentation."
		case let .planningCenterItemNotLinked(path):
			"\(path) is already unlinked."
		case let .planningCenterItemOutsideConnectedPlaylist(path):
			"\(path) is not inside a playlist connected to a Planning Center plan."
		}
	}
}

public enum CueGroupEditError: Error, CustomStringConvertible, Sendable {
	case cueAlreadyAssigned(cuePath: String, groupPaths: [String])
	case duplicateCueSelection(path: String)
	case omittedCuesRequirePolicy(paths: [String])
	case nonemptyGroupRequiresPolicy(path: String)
	case arrangementReferencesRequirePolicy(paths: [String])
	case cannotRemoveLastGroup
	case cannotRemoveAllCues
	case referencedCueCannotBeDeleted(cuePath: String, referencePath: String)
	case destinationIsSourceGroup

	public var description: String {
		switch self {
		case let .cueAlreadyAssigned(cuePath, groupPaths):
			"Cue \(cuePath) already belongs to \(groupPaths.joined(separator: ", ")). Use the transfer policy to move it."
		case let .duplicateCueSelection(path):
			"Cue \(path) was selected more than once. A cue group owns each cue exactly once."
		case let .omittedCuesRequirePolicy(paths):
			"Replacing the cue group would leave existing cues ungrouped: \(paths.joined(separator: ", ")). Explicitly allow omitted cues to remain ungrouped."
		case let .nonemptyGroupRequiresPolicy(path):
			"Cue group \(path) is not empty. Choose whether to delete, move, or leave its cues ungrouped."
		case let .arrangementReferencesRequirePolicy(paths):
			"The cue group is referenced by arrangements: \(paths.joined(separator: ", ")). Explicitly allow removal of every arrangement occurrence."
		case .cannotRemoveLastGroup:
			"A presentation must retain at least one cue group."
		case .cannotRemoveAllCues:
			"A presentation must retain at least one cue."
		case let .referencedCueCannotBeDeleted(cuePath, referencePath):
			"Cue \(cuePath) cannot be deleted because it is referenced by \(referencePath)."
		case .destinationIsSourceGroup:
			"The destination cue group must differ from the group being removed."
		}
	}
}

public enum CueGroupOwnershipPolicy: Sendable, Equatable {
	case requireUnassignedOrSameGroup
	case transferFromOtherGroups
}

public enum CueGroupOmittedCuePolicy: Sendable, Equatable {
	case reject
	case leaveUngrouped
}

public enum CueGroupCueRemovalPolicy: Sendable, Equatable {
	case rejectNonempty
	case deleteOwnedCues
	case leaveUngrouped
	case moveCues(to: ComponentPath)
}

public enum CueGroupArrangementRemovalPolicy: Sendable, Equatable {
	case rejectReferences
	case removeAllOccurrences
}

public struct CueGroupRemovalReport: Sendable, Equatable {
	public var groupUUID: String
	public var removedCueUUIDs: [String]
	public var movedCueUUIDs: [String]
	public var removedArrangementOccurrences: Int

	public init(
		groupUUID: String,
		removedCueUUIDs: [String],
		movedCueUUIDs: [String],
		removedArrangementOccurrences: Int,
	) {
		self.groupUUID = groupUUID
		self.removedCueUUIDs = removedCueUUIDs
		self.movedCueUUIDs = movedCueUUIDs
		self.removedArrangementOccurrences = removedArrangementOccurrences
	}
}

public enum DocumentEditor {
	/// Applies a protobuf JSON fragment to the selected message. Replaced fields are
	/// rebuilt from the fragment; untouched wire fields, including unknown ones, are
	/// retained verbatim. Media URL changes must also replace the media UUID with a
	/// different, nonempty identity unless `allowURLOnly` is explicitly enabled for
	/// an intentional relocation of the same asset.
	public static func patch(
		_ document: inout ProPresenterDocument,
		at path: ComponentPath,
		jsonData: Data,
		allowURLOnly: Bool = false,
	) throws {
		let patchedPayload = try patchedPayload(document, at: path, jsonData: jsonData)
		if !allowURLOnly, try hasUnsafeMediaURLChange(from: document.payload, to: patchedPayload) {
			throw DocumentEditError.unsupportedPatchValue(
				"Changing rv.data.Media.url without replacing its UUID with a different, nonempty identity can create a media-identity conflict. Use setMedia or explicitly allow a URL-only relocation.",
			)
		}
		document.payload = patchedPayload
	}

	private static func patchedPayload(
		_ document: ProPresenterDocument,
		at path: ComponentPath,
		jsonData: Data,
	) throws -> DocumentPayload {
		let selection = try ComponentResolver.resolve(path, in: document)
		return switch document.payload {
		case let .presentation(message):
			try .presentation(ProtobufJSONPatcher.patch(message, at: selection, with: jsonData))
		case let .theme(message):
			try .theme(ProtobufJSONPatcher.patch(message, at: selection, with: jsonData))
		case let .playlist(message):
			try .playlist(ProtobufJSONPatcher.patch(message, at: selection, with: jsonData))
		}
	}

	/// Returns whether a generic patch changes only the URL of an existing media
	/// identity. Such edits can leave ProPresenter's UUID-to-asset registry in
	/// conflict with the document URL and should normally use `setMedia`.
	public static func isURLOnlyMediaPatch(_ document: ProPresenterDocument, at path: ComponentPath, jsonData: Data) throws -> Bool {
		try hasUnsafeMediaURLChange(
			from: document.payload,
			to: patchedPayload(document, at: path, jsonData: jsonData),
		)
	}

	private struct MediaPatchState {
		var uuid: String
		var url: Data?
	}

	private static func hasUnsafeMediaURLChange(from original: DocumentPayload, to candidate: DocumentPayload) throws -> Bool {
		let before = try mediaPatchStates(in: original)
		let after = try mediaPatchStates(in: candidate)
		for path in Set(before.keys).union(after.keys) {
			let old = before[path] ?? MediaPatchState(uuid: "", url: nil)
			let new = after[path] ?? MediaPatchState(uuid: "", url: nil)
			guard old.url != new.url else { continue }
			if new.uuid.isEmpty || new.uuid == old.uuid {
				return true
			}
		}
		return false
	}

	private static func mediaPatchStates(in payload: DocumentPayload) throws -> [String: MediaPatchState] {
		let root = try JSONSerialization.jsonObject(with: payload.jsonUTF8Data())
		var result: [String: MediaPatchState] = [:]
		collectMediaPatchStates(from: root, path: [], fields: [], into: &result)
		return result
	}

	private static func collectMediaPatchStates(
		from value: Any,
		path: [String],
		fields: [String],
		into result: inout [String: MediaPatchState],
	) {
		if let object = value as? [String: Any] {
			let isMedia = fields.suffix(2).elementsEqual(["media", "element"]) ||
				fields.suffix(2).elementsEqual(["fill", "media"])
			if isMedia {
				let uuid = (object["uuid"] as? [String: Any])?["string"] as? String ?? ""
				let url = (object["url"] as? [String: Any]).flatMap {
					try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])
				}
				result[path.joined(separator: "/")] = MediaPatchState(uuid: uuid, url: url)
			}
			for key in object.keys.sorted() {
				collectMediaPatchStates(
					from: object[key] as Any,
					path: path + [key],
					fields: fields + [key],
					into: &result,
				)
			}
		} else if let values = value as? [Any] {
			for (index, child) in values.enumerated() {
				collectMediaPatchStates(
					from: child,
					path: path + ["[\(index)]"],
					fields: fields,
					into: &result,
				)
			}
		}
	}

	public static func rename(_ document: inout ProPresenterDocument, at path: ComponentPath, to name: String) throws {
		switch document.payload {
		case var .presentation(presentation):
			switch path.segments.first?.field {
			case "arrangements":
				try renameArrangement(in: &presentation, at: path, to: name)
			case "cue_groups":
				try renameCueGroup(in: &presentation, at: path, to: name)
			case "cues":
				try renameCue(in: &presentation, at: path, to: name)
			default:
				throw ComponentPathError.unsupported(field: path.description, at: "/")
			}
			document.payload = .presentation(presentation)
		case var .theme(theme):
			let index = try templateIndex(in: theme, path: path)
			theme.slides[index].name = name
			document.payload = .theme(theme)
		case var .playlist(playlist):
			_ = try editPlaylist(&playlist, at: ArraySlice(path.segments), operation: .rename(name))
			document.payload = .playlist(playlist)
		}
	}

	@discardableResult
	public static func duplicate(_ document: inout ProPresenterDocument, at path: ComponentPath) throws -> String {
		switch document.payload {
		case var .presentation(presentation):
			let identifier: String
			switch path.segments.first?.field {
			case "arrangements":
				identifier = try duplicateArrangement(in: &presentation, at: path)
			case "cue_groups":
				identifier = try duplicateCueGroup(in: &presentation, at: path)
			case "cues":
				identifier = try duplicateCue(in: &presentation, at: path)
			default:
				throw ComponentPathError.unsupported(field: path.description, at: "/")
			}
			document.payload = .presentation(presentation)
			return identifier
		case var .theme(theme):
			let index = try templateIndex(in: theme, path: path)
			let copy = freshCopy(of: theme.slides[index])
			theme.slides.insert(copy, at: index + 1)
			document.payload = .theme(theme)
			return copy.baseSlide.uuid.string
		case var .playlist(playlist):
			guard let identifier = try editPlaylist(&playlist, at: ArraySlice(path.segments), operation: .duplicate) else {
				throw ComponentPathError.noMatch(path: path.description, candidates: [])
			}
			document.payload = .playlist(playlist)
			return identifier
		}
	}

	public static func remove(_ document: inout ProPresenterDocument, at path: ComponentPath) throws {
		switch document.payload {
		case var .presentation(presentation):
			switch path.segments.first?.field {
			case "arrangements":
				try removeArrangement(in: &presentation, at: path)
			case "cue_groups":
				try removeCueGroup(in: &presentation, at: path)
			case "cues":
				try removeCue(in: &presentation, at: path)
			default:
				throw ComponentPathError.unsupported(field: path.description, at: "/")
			}
			document.payload = .presentation(presentation)
		case var .theme(theme):
			try theme.slides.remove(at: templateIndex(in: theme, path: path))
			document.payload = .theme(theme)
		case var .playlist(playlist):
			_ = try editPlaylist(&playlist, at: ArraySlice(path.segments), operation: .remove)
			document.payload = .playlist(playlist)
		}
	}

	public static func move(_ document: inout ProPresenterDocument, at path: ComponentPath, after afterPath: ComponentPath) throws {
		switch document.payload {
		case var .presentation(presentation):
			switch path.segments.first?.field {
			case "arrangements":
				try moveArrangement(in: &presentation, at: path, after: afterPath)
			case "cue_groups":
				try moveCueGroup(in: &presentation, at: path, after: afterPath)
			case "cues":
				try moveCue(in: &presentation, at: path, after: afterPath)
			default:
				throw ComponentPathError.unsupported(field: path.description, at: "/")
			}
			document.payload = .presentation(presentation)
		case var .theme(theme):
			let index = try templateIndex(in: theme, path: path)
			let afterIndex = try templateIndex(in: theme, path: afterPath)
			try move(&theme.slides, from: index, after: afterIndex)
			document.payload = .theme(theme)
		case var .playlist(playlist):
			let sourceDocument = ProPresenterDocument(
				payload: .playlist(playlist),
				origin: .raw(URL(fileURLWithPath: "/tmp/pro-crud-playlist-move")),
			)
			let canonicalPath = try ComponentPath(ComponentResolver.resolve(path, in: sourceDocument).canonicalPath)
			let canonicalAfterPath = try ComponentPath(ComponentResolver.resolve(afterPath, in: sourceDocument).canonicalPath)
			guard canonicalPath.segments.dropLast() == canonicalAfterPath.segments.dropLast(),
			      let after = canonicalAfterPath.segments.last?.selector
			else {
				throw ComponentPathError.unsupported(field: afterPath.description, at: "Playlist components must be moved relative to a sibling.")
			}
			_ = try editPlaylist(&playlist, at: ArraySlice(canonicalPath.segments), operation: .move(after))
			document.payload = .playlist(playlist)
		}
	}

	private enum StructuralOperation {
		case rename(String)
		case duplicate
		case remove
		case move(ComponentPath.Selector)
		case setHidden(Bool)
		case linkPlanningCenterItem(Rv_Data_PlaylistItem)
		case unlinkPlanningCenterItem

		var changesConnectedStructure: Bool {
			if case .setHidden = self {
				return false
			}
			if case .linkPlanningCenterItem = self {
				return false
			}
			if case .unlinkPlanningCenterItem = self {
				return false
			}
			return true
		}
	}

	private static func templateIndex(in theme: Rv_Data_Template.Document, path: ComponentPath) throws -> Int {
		guard path.segments.count == 1, path.segments[0].field == "slides", let selector = path.segments[0].selector else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		return try index(
			in: theme.slides,
			selector: selector,
			path: path.description,
			identity: { $0.baseSlide.uuid.string },
			name: { $0.name },
		)
	}

	private static func editPlaylist(_ document: inout Rv_Data_PlaylistDocument, at segments: ArraySlice<ComponentPath.Segment>, operation: StructuralOperation) throws -> String? {
		guard let root = segments.first, root.field == "root_node", root.selector == nil else {
			throw ComponentPathError.unsupported(field: ComponentPath(segments: Array(segments)).description, at: "/")
		}
		var playlist = document.rootNode
		let result = try editPlaylist(&playlist, at: segments.dropFirst(), operation: operation)
		document.rootNode = playlist
		return result
	}

	private static func editPlaylist(_ playlist: inout Rv_Data_Playlist, at segments: ArraySlice<ComponentPath.Segment>, operation: StructuralOperation) throws -> String? {
		guard let segment = segments.first else {
			throw ComponentPathError.unsupported(field: ComponentPath(segments: Array(segments)).description, at: "/root_node")
		}

		if segment.selector == nil {
			guard segments.count >= 2 else {
				throw ComponentPathError.unsupported(field: segment.field, at: "/root_node")
			}
			guard let repeated = segments.dropFirst().first else {
				throw ComponentPathError.unsupported(field: segment.field, at: "/root_node")
			}
			guard repeated.field == segment.field, let selector = repeated.selector else {
				throw ComponentPathError.unsupported(field: repeated.field, at: "/root_node/\(segment.field)")
			}
			switch segment.field {
			case "playlists":
				guard case .playlists? = playlist.childrenType else {
					throw ComponentPathError.noMatch(path: "/root_node/playlists/playlists", candidates: [])
				}
				var wrapper = playlist.playlists
				let index = try index(in: wrapper.playlists, selector: selector, path: "/root_node/playlists/playlists", identity: { $0.uuid.string }, name: { $0.name })
				let result: String?
				if segments.count == 2 {
					result = try editPlaylistChildren(&wrapper.playlists, index: index, operation: operation)
				} else {
					var child = wrapper.playlists[index]
					try rejectManagedStructureChange(child, path: ComponentPath(segments: Array(segments.prefix(2))).description, operation: operation)
					result = try editPlaylist(&child, at: segments.dropFirst(2), operation: operation)
					wrapper.playlists[index] = child
				}
				playlist.playlists = wrapper
				return result
			case "items":
				guard case .items? = playlist.childrenType, segments.count == 2 else {
					throw ComponentPathError.unsupported(field: ComponentPath(segments: Array(segments)).description, at: "/root_node/items")
				}
				try requirePlanningCenterPlaylistIfNeeded(playlist, path: "/root_node", operation: operation)
				try rejectManagedStructureChange(playlist, path: "/root_node", operation: operation)
				var wrapper = playlist.items
				let index = try index(in: wrapper.items, selector: selector, path: "/root_node/items/items", identity: { $0.uuid.string }, name: { $0.name })
				let result = try editPlaylistItems(&wrapper.items, index: index, operation: operation)
				playlist.items = wrapper
				return result
			default:
				throw ComponentPathError.unsupported(field: segment.field, at: "/root_node")
			}
		}

		guard let selector = segment.selector else {
			throw ComponentPathError.selectorRequired(field: segment.field, at: "/root_node")
		}
		switch segment.field {
		case "children":
			let index = try index(in: playlist.children, selector: selector, path: "/root_node/children", identity: { $0.uuid.string }, name: { $0.name })
			if segments.count == 1 {
				return try editPlaylistChildren(&playlist.children, index: index, operation: operation)
			} else {
				var child = playlist.children[index]
				try rejectManagedStructureChange(child, path: ComponentPath(segments: Array(segments.prefix(1))).description, operation: operation)
				let result = try editPlaylist(&child, at: segments.dropFirst(), operation: operation)
				playlist.children[index] = child
				return result
			}
		case "items":
			guard segments.count == 1 else { throw ComponentPathError.unsupported(field: ComponentPath(segments: Array(segments)).description, at: "/root_node/items") }
			try requirePlanningCenterPlaylistIfNeeded(playlist, path: "/root_node", operation: operation)
			try rejectManagedStructureChange(playlist, path: "/root_node", operation: operation)
			var items = playlist.items
			let index = try index(in: items.items, selector: selector, path: "/root_node/items", identity: { $0.uuid.string }, name: { $0.name })
			let result = try editPlaylistItems(&items.items, index: index, operation: operation)
			playlist.items = items
			return result
		default:
			throw ComponentPathError.unsupported(field: segment.field, at: "/root_node")
		}
	}

	private static func editPlaylistChildren(_ children: inout [Rv_Data_Playlist], index selectedIndex: Int, operation: StructuralOperation) throws -> String? {
		try rejectManagedStructureChange(children[selectedIndex], path: "/root_node/playlists", operation: operation)
		switch operation {
		case let .rename(name):
			children[selectedIndex].name = name
			return nil
		case .duplicate:
			let copy = freshCopy(of: children[selectedIndex])
			children.insert(copy, at: selectedIndex + 1)
			return copy.uuid.string
		case .remove:
			children.remove(at: selectedIndex)
			return nil
		case let .move(after):
			try move(&children, from: selectedIndex, after: index(in: children, selector: after, path: "/root_node/children", identity: { $0.uuid.string }, name: { $0.name }))
			return nil
		case .setHidden:
			throw ComponentPathError.unsupported(field: "is_hidden", at: "/root_node/playlists")
		case .linkPlanningCenterItem, .unlinkPlanningCenterItem:
			throw ComponentPathError.unsupported(field: "planning_center", at: "/root_node/playlists")
		}
	}

	private static func editPlaylistItems(_ items: inout [Rv_Data_PlaylistItem], index selectedIndex: Int, operation: StructuralOperation) throws -> String? {
		switch operation {
		case let .rename(name):
			items[selectedIndex].name = name
			return nil
		case .duplicate:
			let copy = freshCopy(of: items[selectedIndex])
			items.insert(copy, at: selectedIndex + 1)
			return copy.uuid.string
		case .remove:
			items.remove(at: selectedIndex)
			return nil
		case let .move(after):
			try move(&items, from: selectedIndex, after: index(in: items, selector: after, path: "/root_node/items", identity: { $0.uuid.string }, name: { $0.name }))
			return nil
		case let .setHidden(hidden):
			items[selectedIndex].isHidden = hidden
			return nil
		case let .linkPlanningCenterItem(linkedItem):
			guard case var .planningCenter(planningCenter)? = items[selectedIndex].itemType else {
				throw DocumentEditError.notPlanningCenterItem(path: "/root_node/items")
			}
			guard !planningCenter.hasLinkedData else {
				throw DocumentEditError.planningCenterItemAlreadyLinked(path: "/root_node/items")
			}
			planningCenter.linkedData = linkedItem
			items[selectedIndex].planningCenter = planningCenter
			return nil
		case .unlinkPlanningCenterItem:
			guard case var .planningCenter(planningCenter)? = items[selectedIndex].itemType else {
				throw DocumentEditError.notPlanningCenterItem(path: "/root_node/items")
			}
			guard planningCenter.hasLinkedData else {
				throw DocumentEditError.planningCenterItemNotLinked(path: "/root_node/items")
			}
			planningCenter.clearLinkedData()
			items[selectedIndex].planningCenter = planningCenter
			return nil
		}
	}

	private static func requirePlanningCenterPlaylistIfNeeded(
		_ playlist: Rv_Data_Playlist,
		path: String,
		operation: StructuralOperation,
	) throws {
		guard case .linkPlanningCenterItem = operation else {
			if case .unlinkPlanningCenterItem = operation, !playlist.isPlanningCenterConnected {
				throw DocumentEditError.planningCenterItemOutsideConnectedPlaylist(path: path)
			}
			return
		}
		guard playlist.isPlanningCenterConnected else {
			throw DocumentEditError.planningCenterItemOutsideConnectedPlaylist(path: path)
		}
	}

	private static func rejectManagedStructureChange(
		_ playlist: Rv_Data_Playlist,
		path: String,
		operation: StructuralOperation,
	) throws {
		guard operation.changesConnectedStructure, playlist.isPlanningCenterConnected else { return }
		throw DocumentEditError.planningCenterManagedContent(path: path)
	}

	public static func setPlaylistItemHidden(
		_ document: inout ProPresenterDocument,
		at path: ComponentPath,
		hidden: Bool,
	) throws {
		guard case var .playlist(playlist) = document.payload else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let sourceDocument = ProPresenterDocument(
			payload: .playlist(playlist),
			origin: .raw(URL(fileURLWithPath: "/tmp/pro-crud-playlist-visibility")),
		)
		let canonicalPath = try ComponentPath(ComponentResolver.resolve(path, in: sourceDocument).canonicalPath)
		_ = try editPlaylist(&playlist, at: ArraySlice(canonicalPath.segments), operation: .setHidden(hidden))
		document.payload = .playlist(playlist)
	}

	public static func linkPlanningCenterItem(
		_ document: inout ProPresenterDocument,
		at path: ComponentPath,
		to presentationURL: URL,
		linkedItemUUID: String? = nil,
	) throws {
		let loaded = try DocumentLoader.loadRaw(presentationURL, kind: .presentation)
		guard case let .presentation(presentation) = loaded.payload else {
			throw DocumentLoadError.invalidPayload(
				expected: DocumentKind.presentation.rawValue,
				location: presentationURL.path,
				underlying: "input is not a presentation",
			)
		}
		if let linkedItemUUID, linkedItemUUID.isEmpty {
			throw DocumentEditError.unsupportedPatchValue("A linked playlist-item UUID cannot be empty.")
		}
		var linkedItem = Rv_Data_PlaylistItem()
		linkedItem.uuid.string = linkedItemUUID ?? DocumentFactory.uuid().string
		linkedItem.name = presentation.name.isEmpty
			? presentationURL.deletingPathExtension().lastPathComponent
			: presentation.name
		linkedItem.presentation.documentPath = planningCenterDocumentPath(
			presentationURL,
			showRoot: planningCenterShowRoot(for: document, presentationURL: presentationURL),
		)
		linkedItem.presentation.userMusicKey.musicKey = .c

		guard case var .playlist(playlist) = document.payload else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let canonicalPath = try canonicalPlaylistPath(path, playlist: playlist)
		try editPlanningCenterItem(
			&playlist,
			at: canonicalPath,
			operation: .linkPlanningCenterItem(linkedItem),
		)
		document.payload = .playlist(playlist)
	}

	public static func unlinkPlanningCenterItem(
		_ document: inout ProPresenterDocument,
		at path: ComponentPath,
	) throws {
		guard case var .playlist(playlist) = document.payload else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let canonicalPath = try canonicalPlaylistPath(path, playlist: playlist)
		try editPlanningCenterItem(&playlist, at: canonicalPath, operation: .unlinkPlanningCenterItem)
		document.payload = .playlist(playlist)
	}

	private static func editPlanningCenterItem(
		_ playlist: inout Rv_Data_PlaylistDocument,
		at path: ComponentPath,
		operation: StructuralOperation,
	) throws {
		do {
			_ = try editPlaylist(&playlist, at: ArraySlice(path.segments), operation: operation)
		} catch let error as DocumentEditError {
			switch error {
			case .notPlanningCenterItem:
				throw DocumentEditError.notPlanningCenterItem(path: path.description)
			case .planningCenterItemAlreadyLinked:
				throw DocumentEditError.planningCenterItemAlreadyLinked(path: path.description)
			case .planningCenterItemNotLinked:
				throw DocumentEditError.planningCenterItemNotLinked(path: path.description)
			case .planningCenterItemOutsideConnectedPlaylist:
				throw DocumentEditError.planningCenterItemOutsideConnectedPlaylist(path: path.description)
			default:
				throw error
			}
		}
	}

	private static func canonicalPlaylistPath(
		_ path: ComponentPath,
		playlist: Rv_Data_PlaylistDocument,
	) throws -> ComponentPath {
		let sourceDocument = ProPresenterDocument(
			payload: .playlist(playlist),
			origin: .raw(URL(fileURLWithPath: "/tmp/pro-crud-playlist-edit")),
		)
		return try ComponentPath(ComponentResolver.resolve(path, in: sourceDocument).canonicalPath)
	}

	private static func planningCenterShowRoot(
		for document: ProPresenterDocument,
		presentationURL: URL,
	) -> URL? {
		guard case let .raw(playlistURL) = document.origin,
		      playlistURL.deletingLastPathComponent().lastPathComponent == "Playlists"
		else { return nil }
		let showRoot = playlistURL.deletingLastPathComponent().deletingLastPathComponent()
		let librariesRoot = showRoot.appendingPathComponent("Libraries", isDirectory: true)
		return (try? DocumentLoader.relativePath(of: presentationURL, in: librariesRoot)) == nil ? nil : showRoot
	}

	private static func planningCenterDocumentPath(
		_ presentationURL: URL,
		showRoot: URL?,
	) -> Rv_Data_URL {
		let standardized = presentationURL.standardizedFileURL
		var path = Rv_Data_URL()
		path.platform = .macos
		path.absoluteString = standardized.absoluteString
		if let showRoot, let relativePath = try? DocumentLoader.relativePath(of: standardized, in: showRoot) {
			path.local.root = .show
			path.local.path = relativePath
		}
		return path
	}

	private static func index<T>(in values: [T], selector: ComponentPath.Selector, path: String, identity: (T) -> String, name: (T) -> String) throws -> Int {
		let matches = values.indices.filter { index in
			switch selector {
			case let .index(value): index == value
			case let .field(field, value):
				switch field {
				case "uuid": identity(values[index]) == value
				case "name": name(values[index]) == value
				default: false
				}
			}
		}
		guard matches.count == 1, let index = matches.first else { throw ComponentPathError.noMatch(path: path, candidates: []) }
		return index
	}

	private static func move(_ values: inout [some Any], from index: Int, after afterIndex: Int) throws {
		guard index != afterIndex else { return }
		let value = values.remove(at: index)
		let insertionIndex = index < afterIndex ? afterIndex : afterIndex + 1
		values.insert(value, at: insertionIndex)
	}

	@discardableResult
	public static func addBlankSlide(
		to presentation: inout Rv_Data_Presentation,
		groupPath: ComponentPath,
		after cuePath: ComponentPath? = nil,
		template: Rv_Data_Template.Slide? = nil,
		includeTemplateActions: Bool = false,
		duplicateCuePath: ComponentPath? = nil,
	) throws -> TemplateResolutionReport? {
		guard groupPath.segments.count == 1, let selector = groupPath.segments[0].selector, groupPath.segments[0].field == "cue_groups" else {
			throw ComponentPathError.unsupported(field: groupPath.description, at: "/")
		}
		let groupIndex = try cueGroupIndex(in: presentation, selector: selector)
		let cueID = DocumentFactory.uuid()
		var templateReport: TemplateResolutionReport?
		let cue: Rv_Data_Cue
		if let duplicateCuePath {
			if duplicateCuePath.segments.count == 1, duplicateCuePath.segments[0].field == "cues" {
				var copy = try freshCopy(of: presentation.cues[cueIndex(in: presentation, path: duplicateCuePath)])
				let generatedIdentifier = copy.uuid
				copy.uuid.string = cueID.string
				if copy.completionTargetType == .cue,
				   copy.completionTargetUuid.string == generatedIdentifier.string
				{
					copy.completionTargetUuid.string = cueID.string
				}
				cue = copy
			} else {
				let slide = try ProPresenterGraphCopier.freshSlide(
					slideForDuplicate(in: presentation, at: duplicateCuePath),
				)
				cue = makeSlideCue(
					identifier: cueID,
					name: "Slide \(presentation.cues.count + 1) Copy",
					slide: slide,
				)
			}
		} else {
			let afterSize: Rv_Data_Graphics.Size?
			if let cuePath {
				let afterIndex = try cueIndex(in: presentation, path: cuePath)
				afterSize = presentation.cues[afterIndex].actions.compactMap(\.presentationBaseSlide).first?.size
			} else {
				afterSize = nil
			}
			let targetGroupSize = presentation.cueGroups[groupIndex].cueIdentifiers.compactMap { identifier in
				presentation.cues.first(where: { $0.uuid.string == identifier.string })?.actions.compactMap(\.presentationBaseSlide).first?.size
			}.first
			let presentationSize = presentation.presentationOrderCueIndices.compactMap { index in
				presentation.cues[index].actions.compactMap(\.presentationBaseSlide).first?.size
			}.first
			let size = afterSize ?? targetGroupSize ?? presentationSize ?? defaultSize()
			let slide: Rv_Data_Slide
			var templateActions: [Rv_Data_Action] = []
			if let template {
				let resolution = try TemplateResolver.resolve(
					template: template,
					source: nil,
					destinationSize: CGSize(width: size.width, height: size.height),
					mode: .instantiateNew,
				)
				slide = resolution.slide
				templateReport = resolution.report
				if includeTemplateActions {
					templateActions = resolution.actions
				}
			} else {
				var blank = Rv_Data_Slide()
				blank.uuid = DocumentFactory.uuid()
				blank.size = size
				slide = blank
			}
			let cueName = if let template, !template.name.isEmpty {
				template.name
			} else {
				"Slide \(presentation.cues.count + 1)"
			}
			var generatedCue = makeSlideCue(
				identifier: cueID,
				name: cueName,
				slide: slide,
			)
			generatedCue.actions.append(contentsOf: templateActions)
			cue = generatedCue
		}

		let cuePosition: Int
		if let cuePath {
			cuePosition = try indexInGroup(for: cuePath, presentation: presentation, groupIndex: groupIndex) + 1
		} else {
			cuePosition = presentation.cueGroups[groupIndex].cueIdentifiers.count
		}
		presentation.cues.append(cue)
		presentation.cueGroups[groupIndex].cueIdentifiers.insert(cueID, at: cuePosition)
		return templateReport
	}

	/// Adds a presentation-local cue group. Cue paths are resolved before any
	/// mutation, and transferring them removes every previous group occurrence so
	/// ordinary authored presentations retain exclusive cue ownership.
	@discardableResult
	public static func addCueGroup(
		to presentation: inout Rv_Data_Presentation,
		name: String,
		color: Rv_Data_Color? = nil,
		cuePaths: [ComponentPath] = [],
		after afterPath: ComponentPath? = nil,
		ownershipPolicy: CueGroupOwnershipPolicy = .transferFromOtherGroups,
	) throws -> String {
		var group = Rv_Data_Group()
		group.name = name
		group.hotKey = Rv_Data_HotKey()
		if let color {
			group.color = color
		}
		return try addCueGroup(
			to: &presentation,
			group: group,
			cuePaths: cuePaths,
			after: afterPath,
			ownershipPolicy: ownershipPolicy,
		)
	}

	/// Adds a cue group from a metadata prototype while always generating a fresh
	/// presentation-local UUID. Known and unknown prototype fields are otherwise
	/// retained.
	@discardableResult
	public static func addCueGroup(
		to presentation: inout Rv_Data_Presentation,
		group prototype: Rv_Data_Group,
		cuePaths: [ComponentPath] = [],
		after afterPath: ComponentPath? = nil,
		ownershipPolicy: CueGroupOwnershipPolicy = .transferFromOtherGroups,
	) throws -> String {
		let cueReferences = try selectedCueReferences(in: presentation, paths: cuePaths)
		let cueIdentifiers = cueReferences.map {
			storedCueIdentifier(in: presentation, matching: $0.uuid, preferredGroupIndex: nil)
		}
		let afterIndex = try afterPath.map { try cueGroupIndex(in: presentation, path: $0) }
		try validateCueOwnership(
			in: presentation,
			cueReferences: cueReferences,
			targetGroupIndex: nil,
			policy: ownershipPolicy,
		)

		var group = prototype
		group.uuid = freshUUID(preserving: group.uuid)
		if ownershipPolicy == .transferFromOtherGroups {
			removeCueReferences(cueIdentifiers, from: &presentation.cueGroups)
		}
		var cueGroup = Rv_Data_Presentation.CueGroup()
		cueGroup.group = group
		cueGroup.cueIdentifiers = cueIdentifiers
		let insertionIndex = afterIndex.map { $0 + 1 } ?? presentation.cueGroups.endIndex
		presentation.cueGroups.insert(cueGroup, at: insertionIndex)
		return group.uuid.string
	}

	/// Replaces a cue group's ordered references. By default, cues selected from
	/// another group and existing cues omitted from the new sequence are rejected;
	/// callers must opt into either structural consequence explicitly.
	public static func setCueGroupCues(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		cuePaths: [ComponentPath],
		ownershipPolicy: CueGroupOwnershipPolicy = .requireUnassignedOrSameGroup,
		omittedCuePolicy: CueGroupOmittedCuePolicy = .reject,
	) throws {
		let groupIndex = try cueGroupIndex(in: presentation, path: path)
		let cueReferences = try selectedCueReferences(in: presentation, paths: cuePaths)
		let cueIdentifiers = cueReferences.map {
			storedCueIdentifier(in: presentation, matching: $0.uuid, preferredGroupIndex: groupIndex)
		}
		let selectedIDs = Set(cueReferences.map(\.uuid.string))
		let omitted = presentation.cueGroups[groupIndex].cueIdentifiers.filter { !selectedIDs.contains($0.string) }
		if omittedCuePolicy == .reject, !omitted.isEmpty {
			throw CueGroupEditError.omittedCuesRequirePolicy(paths: omitted.map {
				cuePath(for: $0, in: presentation)
			})
		}
		try validateCueOwnership(
			in: presentation,
			cueReferences: cueReferences,
			targetGroupIndex: groupIndex,
			policy: ownershipPolicy,
		)
		if ownershipPolicy == .transferFromOtherGroups {
			removeCueReferences(cueIdentifiers, from: &presentation.cueGroups)
		}
		presentation.cueGroups[groupIndex].cueIdentifiers = cueIdentifiers
	}

	public enum CueGroupCueInsertion: Sendable {
		case start
		case end
		case after(ComponentPath)
	}

	/// Transfers one cue to a cue group, removing every old group occurrence and
	/// inserting exactly one destination reference.
	public static func moveCueToGroup(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		groupPath: ComponentPath,
		insertion: CueGroupCueInsertion = .end,
	) throws {
		let groupIndex = try cueGroupIndex(in: presentation, path: groupPath)
		let reference = try selectedCueReferences(in: presentation, paths: [path])[0]
		let storedIdentifier = storedCueIdentifier(in: presentation, matching: reference.uuid, preferredGroupIndex: groupIndex)
		let afterIdentifier: Rv_Data_UUID?
		switch insertion {
		case .start, .end:
			afterIdentifier = nil
		case let .after(afterPath):
			let afterReference = try selectedCueReferences(in: presentation, paths: [afterPath])[0]
			guard afterReference.uuid.string != reference.uuid.string else { return }
			let storedAfterIdentifier = storedCueIdentifier(
				in: presentation,
				matching: afterReference.uuid,
				preferredGroupIndex: groupIndex,
			)
			guard presentation.cueGroups[groupIndex].cueIdentifiers.contains(where: { $0.string == afterReference.uuid.string }) else {
				throw ComponentPathError.noMatch(
					path: afterPath.description,
					candidates: presentation.cueGroups[groupIndex].cueIdentifiers.map {
						cuePath(for: $0, in: presentation)
					},
				)
			}
			afterIdentifier = storedAfterIdentifier
		}

		removeCueReferences([storedIdentifier], from: &presentation.cueGroups)
		let insertionIndex: Int
		switch insertion {
		case .start:
			insertionIndex = 0
		case .end:
			insertionIndex = presentation.cueGroups[groupIndex].cueIdentifiers.endIndex
		case .after:
			guard let afterIdentifier,
			      let index = presentation.cueGroups[groupIndex].cueIdentifiers.firstIndex(where: { $0.string == afterIdentifier.string })
			else { preconditionFailure("The destination cue disappeared during an ownership transfer.") }
			insertionIndex = index + 1
		}
		presentation.cueGroups[groupIndex].cueIdentifiers.insert(storedIdentifier, at: insertionIndex)
	}

	public static func renameCueGroup(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		to name: String,
	) throws {
		let index = try cueGroupIndex(in: presentation, path: path)
		if presentation.cueGroups[index].group.name != name {
			presentation.cueGroups[index].group.name = name
			detachApplicationGroup(in: &presentation.cueGroups[index].group)
		}
	}

	public static func setCueGroupColor(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		to color: Rv_Data_Color?,
	) throws {
		let index = try cueGroupIndex(in: presentation, path: path)
		if let color {
			if presentation.cueGroups[index].group.hasColor {
				presentation.cueGroups[index].group.color.red = color.red
				presentation.cueGroups[index].group.color.green = color.green
				presentation.cueGroups[index].group.color.blue = color.blue
				presentation.cueGroups[index].group.color.alpha = color.alpha
			} else {
				presentation.cueGroups[index].group.color = color
			}
		} else {
			presentation.cueGroups[index].group.clearColor()
		}
		detachApplicationGroup(in: &presentation.cueGroups[index].group)
	}

	public static func setCueGroupHotKey(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		code: Rv_Data_HotKey.KeyCode,
		controlIdentifier: String = "",
	) throws {
		let index = try cueGroupIndex(in: presentation, path: path)
		var hotKey = presentation.cueGroups[index].group.hasHotKey
			? presentation.cueGroups[index].group.hotKey
			: Rv_Data_HotKey()
		hotKey.code = code
		hotKey.controlIdentifier = controlIdentifier
		presentation.cueGroups[index].group.hotKey = hotKey
		detachApplicationGroup(in: &presentation.cueGroups[index].group)
	}

	public static func clearCueGroupHotKey(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
	) throws {
		try setCueGroupHotKey(
			in: &presentation,
			at: path,
			code: .unknown,
			controlIdentifier: "",
		)
	}

	public static func moveCueGroup(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		after afterPath: ComponentPath,
	) throws {
		let index = try cueGroupIndex(in: presentation, path: path)
		let afterIndex = try cueGroupIndex(in: presentation, path: afterPath)
		try move(&presentation.cueGroups, from: index, after: afterIndex)
	}

	/// Deep-copies a cue group. The new group receives a fresh local UUID, and
	/// every owned cue/action/slide graph receives fresh identities. Existing
	/// arrangements are intentionally unchanged.
	@discardableResult
	public static func duplicateCueGroup(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		name: String? = nil,
	) throws -> String {
		let sourceIndex = try cueGroupIndex(in: presentation, path: path)
		let sourceGroup = presentation.cueGroups[sourceIndex]
		let cueIndicesByUUID = Dictionary(grouping: presentation.cues.indices, by: {
			presentation.cues[$0].uuid.string
		})
		var copiedCuesByUUID: [String: Rv_Data_Cue] = [:]
		var sourceCuesByUUID: [String: Rv_Data_Cue] = [:]
		for identifier in sourceGroup.cueIdentifiers where copiedCuesByUUID[identifier.string] == nil {
			guard let indices = cueIndicesByUUID[identifier.string], indices.count == 1, let cueIndex = indices.first else {
				throw ComponentPathError.noMatch(
					path: cuePath(for: identifier, in: presentation),
					candidates: presentation.presentationOrderCueIndices.map {
						presentation.componentPath(forCueAtStorageIndex: $0)
					},
				)
			}
			let sourceCue = presentation.cues[cueIndex]
			sourceCuesByUUID[identifier.string] = sourceCue
			copiedCuesByUUID[identifier.string] = freshCopy(of: sourceCue)
		}
		let cueIDMapping = copiedCuesByUUID.mapValues(\.uuid)
		for (sourceUUID, sourceCue) in sourceCuesByUUID {
			guard var copy = copiedCuesByUUID[sourceUUID] else { continue }
			if sourceCue.completionTargetType == .cue,
			   let replacement = cueIDMapping[sourceCue.completionTargetUuid.string]
			{
				copy.completionTargetUuid.string = replacement.string
			}
			copiedCuesByUUID[sourceUUID] = copy
		}

		var copy = sourceGroup
		copy.group.uuid = freshUUID(preserving: copy.group.uuid)
		if let name, name != copy.group.name {
			copy.group.name = name
			detachApplicationGroup(in: &copy.group)
		}
		copy.cueIdentifiers = sourceGroup.cueIdentifiers.compactMap { identifier in
			guard let replacement = cueIDMapping[identifier.string] else { return nil }
			return replacingUUIDString(in: identifier, with: replacement.string)
		}
		var appendedCueIDs = Set<String>()
		presentation.cues.append(contentsOf: sourceGroup.cueIdentifiers.compactMap { identifier in
			guard appendedCueIDs.insert(identifier.string).inserted else { return nil }
			return copiedCuesByUUID[identifier.string]
		})
		presentation.cueGroups.insert(copy, at: sourceIndex + 1)
		return copy.group.uuid.string
	}

	/// Removes a cue group only under explicit cue and arrangement policies. The
	/// default used by generic structural removal is intentionally limited to an
	/// empty, unreferenced group.
	@discardableResult
	public static func removeCueGroup(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		cuePolicy: CueGroupCueRemovalPolicy = .rejectNonempty,
		arrangementPolicy: CueGroupArrangementRemovalPolicy = .rejectReferences,
	) throws -> CueGroupRemovalReport {
		let groupIndex = try cueGroupIndex(in: presentation, path: path)
		guard presentation.cueGroups.count > 1 else { throw CueGroupEditError.cannotRemoveLastGroup }
		let group = presentation.cueGroups[groupIndex]
		let groupPath = cueGroupPath(at: groupIndex, in: presentation)
		let arrangementReferences = arrangementReferencePaths(to: group.group.uuid, in: presentation)
		if arrangementPolicy == .rejectReferences, !arrangementReferences.isEmpty {
			throw CueGroupEditError.arrangementReferencesRequirePolicy(paths: arrangementReferences)
		}
		if cuePolicy == .rejectNonempty, !group.cueIdentifiers.isEmpty {
			throw CueGroupEditError.nonemptyGroupRequiresPolicy(path: groupPath)
		}

		var destinationIndex: Int?
		if case let .moveCues(destinationPath) = cuePolicy {
			destinationIndex = try cueGroupIndex(in: presentation, path: destinationPath)
			guard destinationIndex != groupIndex else { throw CueGroupEditError.destinationIsSourceGroup }
		}
		let ownedIDs = group.cueIdentifiers
		let ownedIDStrings = Set(ownedIDs.map(\.string))
		var removedCueUUIDs: [String] = []
		var movedCueUUIDs: [String] = []

		switch cuePolicy {
		case .rejectNonempty, .leaveUngrouped:
			break
		case .moveCues:
			removeCueReferences(ownedIDs, from: &presentation.cueGroups)
			guard let destinationIndex else { preconditionFailure("A move policy has no destination group.") }
			var seen = Set<String>()
			let references = ownedIDs.filter { seen.insert($0.string).inserted }
			presentation.cueGroups[destinationIndex].cueIdentifiers.append(contentsOf: references)
			movedCueUUIDs = references.map(\.string)
		case .deleteOwnedCues:
			for otherGroupIndex in presentation.cueGroups.indices where otherGroupIndex != groupIndex {
				for (referenceIndex, identifier) in presentation.cueGroups[otherGroupIndex].cueIdentifiers.enumerated()
					where ownedIDStrings.contains(identifier.string)
				{
					throw CueGroupEditError.referencedCueCannotBeDeleted(
						cuePath: cuePath(for: identifier, in: presentation),
						referencePath: "\(cueGroupPath(at: otherGroupIndex, in: presentation))/cue_identifiers[index=\(referenceIndex)]",
					)
				}
			}
			guard presentation.cues.count > ownedIDStrings.count else { throw CueGroupEditError.cannotRemoveAllCues }
			try validateNoExternalCueReferences(to: ownedIDStrings, in: presentation)
			removedCueUUIDs = presentation.cues.filter { ownedIDStrings.contains($0.uuid.string) }.map(\.uuid.string)
			presentation.cues.removeAll { ownedIDStrings.contains($0.uuid.string) }
		}

		var removedArrangementOccurrences = 0
		if arrangementPolicy == .removeAllOccurrences {
			for arrangementIndex in presentation.arrangements.indices {
				let previousCount = presentation.arrangements[arrangementIndex].groupIdentifiers.count
				presentation.arrangements[arrangementIndex].groupIdentifiers.removeAll { $0.string == group.group.uuid.string }
				removedArrangementOccurrences += previousCount - presentation.arrangements[arrangementIndex].groupIdentifiers.count
			}
		}
		presentation.cueGroups.remove(at: groupIndex)
		return CueGroupRemovalReport(
			groupUUID: group.group.uuid.string,
			removedCueUUIDs: removedCueUUIDs,
			movedCueUUIDs: movedCueUUIDs,
			removedArrangementOccurrences: removedArrangementOccurrences,
		)
	}

	/// Adds an arrangement. Passing nil group paths copies every native cue group
	/// once, matching ProPresenter's New Arrangement behavior. Passing an empty
	/// array creates an empty arrangement.
	@discardableResult
	public static func addArrangement(
		to presentation: inout Rv_Data_Presentation,
		name: String,
		groupPaths: [ComponentPath]? = nil,
		select: Bool = false,
	) throws -> String {
		var arrangement = Rv_Data_Presentation.Arrangement()
		arrangement.uuid = DocumentFactory.uuid()
		arrangement.name = name
		arrangement.groupIdentifiers = try groupPaths.map {
			try groupIdentifiers(in: presentation, for: $0)
		} ?? presentation.cueGroups.map(\.group.uuid)
		presentation.arrangements.append(arrangement)
		if select {
			presentation.selectedArrangement = arrangement.uuid
		}
		return arrangement.uuid.string
	}

	public static func setArrangementGroups(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		groupPaths: [ComponentPath],
	) throws {
		let index = try arrangementIndex(in: presentation, path: path)
		presentation.arrangements[index].groupIdentifiers = try groupIdentifiers(in: presentation, for: groupPaths)
	}

	public static func selectArrangement(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
	) throws {
		presentation.selectedArrangement = try presentation.arrangements[arrangementIndex(in: presentation, path: path)].uuid
	}

	public static func clearSelectedArrangement(in presentation: inout Rv_Data_Presentation) {
		presentation.clearSelectedArrangement()
	}

	public static func renameArrangement(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		to name: String,
	) throws {
		try presentation.arrangements[arrangementIndex(in: presentation, path: path)].name = name
	}

	@discardableResult
	public static func duplicateArrangement(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
	) throws -> String {
		let sourceIndex = try arrangementIndex(in: presentation, path: path)
		var copy = presentation.arrangements[sourceIndex]
		copy.uuid = freshUUID(preserving: copy.uuid)
		copy.name = sourceNameForCopy(presentation.arrangements[sourceIndex].name)
		presentation.arrangements.insert(copy, at: sourceIndex + 1)
		return copy.uuid.string
	}

	public static func removeArrangement(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
	) throws {
		let index = try arrangementIndex(in: presentation, path: path)
		let identifier = presentation.arrangements[index].uuid
		presentation.arrangements.remove(at: index)
		if presentation.hasSelectedArrangement, presentation.selectedArrangement.string == identifier.string {
			presentation.clearSelectedArrangement()
		}
	}

	public static func moveArrangement(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		after afterPath: ComponentPath,
	) throws {
		let index = try arrangementIndex(in: presentation, path: path)
		let afterIndex = try arrangementIndex(in: presentation, path: afterPath)
		try move(&presentation.arrangements, from: index, after: afterIndex)
	}

	@discardableResult
	public static func applyTemplate(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		template: Rv_Data_Template.Slide,
		actionPolicy: TemplateActionPolicy = .preserve,
	) throws -> TemplateResolutionReport {
		let selectedCueIndex = try cueIndex(in: presentation, path: path)
		let presentationActionIndices = presentation.cues[selectedCueIndex].actions.indices.filter {
			presentation.cues[selectedCueIndex].actions[$0].type == .presentationSlide
		}
		guard presentationActionIndices.count == 1, let selectedActionIndex = presentationActionIndices.first,
		      case var .presentation(presentationSlide)? = presentation.cues[selectedCueIndex].actions[selectedActionIndex].slide.slide
		else {
			throw ComponentPathError.noMatch(
				path: path.description,
				candidates: presentation.cues[selectedCueIndex].actions.indices.map { "\(path.description)/actions[index=\($0)]" },
			)
		}

		let source = presentationSlide.baseSlide
		let resolution = try TemplateResolver.resolve(
			template: template,
			source: source,
			destinationSize: CGSize(width: source.size.width, height: source.size.height),
			mode: .applyExisting,
		)
		presentationSlide.baseSlide = resolution.slide
		presentation.cues[selectedCueIndex].actions[selectedActionIndex].slide.presentation = presentationSlide

		switch actionPolicy {
		case .preserve:
			break
		case .append:
			presentation.cues[selectedCueIndex].actions.append(contentsOf: resolution.actions)
		case .replace:
			let presentationAction = presentation.cues[selectedCueIndex].actions[selectedActionIndex]
			var actions = resolution.actions
			actions.insert(presentationAction, at: min(selectedActionIndex, actions.count))
			presentation.cues[selectedCueIndex].actions = actions
		}
		return resolution.report
	}

	public static func renameCue(in presentation: inout Rv_Data_Presentation, at path: ComponentPath, to name: String) throws {
		let index = try cueIndex(in: presentation, path: path)
		presentation.cues[index].name = name
		for actionIndex in presentation.cues[index].actions.indices where presentation.cues[index].actions[actionIndex].label.text == "" {
			presentation.cues[index].actions[actionIndex].label.text = name
		}
	}

	@discardableResult
	public static func duplicateCue(in presentation: inout Rv_Data_Presentation, at path: ComponentPath) throws -> String {
		let sourceIndex = try cueIndex(in: presentation, path: path)
		let source = presentation.cues[sourceIndex]
		let copy = freshCopy(of: source)
		presentation.cues.insert(copy, at: sourceIndex + 1)
		for groupIndex in presentation.cueGroups.indices {
			guard let position = presentation.cueGroups[groupIndex].cueIdentifiers.firstIndex(where: { $0.string == source.uuid.string }) else { continue }
			let copiedReference = replacingUUIDString(
				in: presentation.cueGroups[groupIndex].cueIdentifiers[position],
				with: copy.uuid.string,
			)
			presentation.cueGroups[groupIndex].cueIdentifiers.insert(copiedReference, at: position + 1)
		}
		return copy.uuid.string
	}

	public static func removeCue(in presentation: inout Rv_Data_Presentation, at path: ComponentPath) throws {
		let index = try cueIndex(in: presentation, path: path)
		let identifier = presentation.cues[index].uuid
		presentation.cues.remove(at: index)
		for groupIndex in presentation.cueGroups.indices {
			presentation.cueGroups[groupIndex].cueIdentifiers.removeAll { $0.string == identifier.string }
		}
	}

	public static func moveCue(in presentation: inout Rv_Data_Presentation, at path: ComponentPath, after afterPath: ComponentPath) throws {
		let index = try cueIndex(in: presentation, path: path)
		let afterIndex = try cueIndex(in: presentation, path: afterPath)
		guard index != afterIndex else { return }
		let identifier = presentation.cues[index].uuid
		let afterIdentifier = presentation.cues[afterIndex].uuid
		guard let groupIndex = presentation.cueGroups.indices.first(where: { groupIndex in
			let identifiers = presentation.cueGroups[groupIndex].cueIdentifiers
			return identifiers.contains(where: { $0.string == identifier.string }) &&
				identifiers.contains(where: { $0.string == afterIdentifier.string })
		}) else {
			throw ComponentPathError.noMatch(path: path.description, candidates: [])
		}
		guard let storedIdentifier = presentation.cueGroups[groupIndex].cueIdentifiers.first(where: { $0.string == identifier.string }) else {
			preconditionFailure("The selected cue reference disappeared before the move.")
		}
		presentation.cueGroups[groupIndex].cueIdentifiers.removeAll { $0.string == identifier.string }
		guard let afterPosition = presentation.cueGroups[groupIndex].cueIdentifiers.firstIndex(where: { $0.string == afterIdentifier.string }) else { return }
		presentation.cueGroups[groupIndex].cueIdentifiers.insert(storedIdentifier, at: afterPosition + 1)
	}

	public static func setText(in presentation: inout Rv_Data_Presentation, at path: ComponentPath, to value: String) throws {
		let target = try presentationTextTarget(in: presentation, at: path)
		let metadata = target.slide.baseSlide.elements[target.elementIndex].element.text.attributes
		let attributes = TemplateResolver.appKitAttributes(from: metadata)
		let attributed = NSAttributedString(string: value, attributes: attributes)
		let data = try attributed.data(
			from: NSRange(location: 0, length: attributed.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)
		try setRTF(
			in: &presentation,
			at: path,
			data: data,
			fallbackFont: attributes[.font] as? NSFont,
		)
	}

	public static func setRTF(in presentation: inout Rv_Data_Presentation, at path: ComponentPath, data: Data) throws {
		try setRTF(in: &presentation, at: path, data: data, fallbackFont: nil)
	}

	private static func setRTF(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		data: Data,
		fallbackFont: NSFont?,
	) throws {
		ProcessFontRegistry.registerFonts(referencedByRTF: data)
		let attributed: NSAttributedString
		do {
			attributed = try NSAttributedString(
				data: data,
				options: [.documentType: NSAttributedString.DocumentType.rtf],
				documentAttributes: nil,
			)
		} catch {
			throw DocumentEditError.unsupportedPatchValue("RTF content could not be decoded: \(error.localizedDescription)")
		}
		let target = try presentationTextTarget(in: presentation, at: path)
		var action = presentation.cues[target.cueIndex].actions[target.actionIndex]
		var slide = target.slide
		var element = slide.baseSlide.elements[target.elementIndex].element
		element.text.rtfData = data
		// Every custom attribute is range-based metadata for the previous RTF
		// contents. Keeping any of it after replacing the complete attributed
		// string can make ProPresenter reinterpret otherwise valid font runs,
		// capitalization, fills, chords, or scale information.
		element.text.attributes.customAttributes = []
		let font = attributed.length > 0
			? attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
			: fallbackFont
		if let font {
			element.text.attributes.font.name = font.fontName
			element.text.attributes.font.family = font.familyName ?? "System"
			element.text.attributes.font.size = font.pointSize
			element.text.attributes.font.bold = font.fontDescriptor.symbolicTraits.contains(.bold)
			element.text.attributes.font.italic = font.fontDescriptor.symbolicTraits.contains(.italic)
		}
		slide.baseSlide.elements[target.elementIndex].element = element
		action.slide.presentation = slide
		presentation.cues[target.cueIndex].actions[target.actionIndex] = action
	}

	private static func presentationTextTarget(
		in presentation: Rv_Data_Presentation,
		at path: ComponentPath,
	) throws -> (
		cueIndex: Int,
		actionIndex: Int,
		elementIndex: Int,
		slide: Rv_Data_PresentationSlide,
	) {
		guard path.segments.count == 8,
		      path.segments[0].field == "cues",
		      path.segments[1].field == "actions",
		      path.segments[2].field == "slide",
		      path.segments[3].field == "presentation",
		      path.segments[4].field == "base_slide",
		      path.segments[5].field == "elements",
		      path.segments[6].field == "element",
		      path.segments[7].field == "text",
		      let actionSelector = path.segments[1].selector,
		      let elementSelector = path.segments[5].selector
		else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let cueIndex = try cueIndex(in: presentation, path: ComponentPath(segments: [path.segments[0]]))
		let actionIndex = try actionIndex(in: presentation.cues[cueIndex], selector: actionSelector)
		let action = presentation.cues[cueIndex].actions[actionIndex]
		guard case let .presentation(slide)? = action.slide.slide else {
			throw ComponentPathError.noMatch(path: path.description, candidates: [])
		}
		let elementIndex = try slideElementIndex(in: slide.baseSlide, selector: elementSelector)
		return (cueIndex, actionIndex, elementIndex, slide)
	}

	public static func setBackground(in presentation: inout Rv_Data_Presentation, at path: ComponentPath, color: Rv_Data_Color) throws {
		guard path.segments.count == 5,
		      path.segments[0].field == "cues",
		      path.segments[1].field == "actions",
		      path.segments[2].field == "slide",
		      path.segments[3].field == "presentation",
		      path.segments[4].field == "base_slide",
		      let actionSelector = path.segments[1].selector
		else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let cueIndex = try cueIndex(in: presentation, path: ComponentPath(segments: [path.segments[0]]))
		let actionIndex = try actionIndex(in: presentation.cues[cueIndex], selector: actionSelector)
		var action = presentation.cues[cueIndex].actions[actionIndex]
		guard case var .presentation(slide)? = action.slide.slide else {
			throw ComponentPathError.noMatch(path: path.description, candidates: [])
		}
		slide.baseSlide.drawsBackgroundColor = true
		slide.baseSlide.backgroundColor = color
		action.slide.presentation = slide
		presentation.cues[cueIndex].actions[actionIndex] = action
	}

	public static func setMedia(
		_ document: inout ProPresenterDocument,
		at path: ComponentPath,
		sourceURL: URL,
		preserveUUID: Bool = false,
		syncLabel: Bool = false,
	) throws {
		try setMedia(
			&document,
			at: path,
			to: media(from: sourceURL),
			preserveUUID: preserveUUID,
			syncLabel: syncLabel,
		)
	}

	/// Routes a complete media replacement to either a presentation or theme
	/// document while preserving the payload's document kind.
	public static func setMedia(
		_ document: inout ProPresenterDocument,
		at path: ComponentPath,
		to replacement: Rv_Data_Media,
		preserveUUID: Bool = false,
		syncLabel: Bool = false,
	) throws {
		switch document.payload {
		case var .presentation(presentation):
			try setMedia(in: &presentation, at: path, to: replacement, preserveUUID: preserveUUID, syncLabel: syncLabel)
			document.payload = .presentation(presentation)
		case var .theme(theme):
			try setMedia(in: &theme, at: path, to: replacement, preserveUUID: preserveUUID, syncLabel: syncLabel)
			document.payload = .theme(theme)
		case .playlist:
			throw unsupportedMediaPath(path)
		}
	}

	public static func setMedia(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		sourceURL: URL,
		preserveUUID: Bool = false,
		syncLabel: Bool = false,
	) throws {
		try setMedia(
			in: &presentation,
			at: path,
			to: media(from: sourceURL),
			preserveUUID: preserveUUID,
			syncLabel: syncLabel,
		)
	}

	private static func media(from sourceURL: URL) throws -> Rv_Data_Media {
		guard FileManager.default.fileExists(atPath: sourceURL.path) else {
			throw CocoaError(.fileNoSuchFile)
		}
		guard try sourceURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
			throw DocumentEditError.unsupportedPatchValue("Media source is not a regular file: \(sourceURL.path)")
		}
		var media = Rv_Data_Media()
		media.uuid = DocumentFactory.uuid()
		media.url.absoluteString = sourceURL.absoluteString
		media.metadata.format = sourceURL.pathExtension.lowercased()
		let contentType = sourceURL.pathExtension.isEmpty ? nil : UTType(filenameExtension: sourceURL.pathExtension)
		let image = NSImage(contentsOf: sourceURL)
		let imageExtensions: Set = ["bmp", "gif", "heic", "jpeg", "jpg", "png", "tif", "tiff", "webp"]
		if image != nil || contentType?.conforms(to: .image) == true || imageExtensions.contains(sourceURL.pathExtension.lowercased()) {
			var properties = Rv_Data_Media.ImageTypeProperties()
			guard let representation = image?.representations.max(by: {
				$0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
			}), representation.pixelsWide > 0, representation.pixelsHigh > 0 else {
				throw DocumentEditError.unsupportedPatchValue("Image media could not be decoded: \(sourceURL.lastPathComponent)")
			}
			properties.drawing.naturalSize.width = Double(representation.pixelsWide)
			properties.drawing.naturalSize.height = Double(representation.pixelsHigh)
			media.image = properties
		} else if contentType?.conforms(to: .movie) == true {
			media.video = Rv_Data_Media.VideoTypeProperties()
		} else if contentType?.conforms(to: .audio) == true {
			media.audio = Rv_Data_Media.AudioTypeProperties()
		} else {
			throw DocumentEditError.unsupportedPatchValue("Unsupported media type for \(sourceURL.lastPathComponent).")
		}
		return media
	}

	/// Replaces a complete media identity at an action media element, a slide
	/// element's media fill, or the containing slide element. Copying the whole
	/// message retains playlist metadata and unknown protobuf fields.
	public static func setMedia(
		in presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		to replacement: Rv_Data_Media,
		preserveUUID: Bool = false,
		syncLabel: Bool = false,
	) throws {
		guard path.segments.count >= 2,
		      path.segments[0].field == "cues",
		      path.segments[1].field == "actions",
		      let actionSelector = path.segments[1].selector
		else {
			throw unsupportedMediaPath(path)
		}
		let cueIndex = try cueIndex(in: presentation, path: ComponentPath(segments: [path.segments[0]]))
		let actionIndex = try actionIndex(in: presentation.cues[cueIndex], selector: actionSelector)
		var action = presentation.cues[cueIndex].actions[actionIndex]

		if path.segments.dropFirst(2).map(\.field) == ["media", "element"] {
			guard case var .media(mediaType)? = action.actionTypeData else {
				throw ComponentPathError.noMatch(path: path.description, candidates: [])
			}
			let labelReplacement: (old: String, new: String)? = if syncLabel,
			                                                       let oldBasename = mediaBasename(mediaType.element),
			                                                       let newBasename = mediaBasename(replacement)
			{
				(old: oldBasename, new: newBasename)
			} else {
				nil
			}
			mediaType.element = try replacingMedia(mediaType.element, with: replacement, preserveUUID: preserveUUID)
			action.media = mediaType
			presentation.cues[cueIndex].actions[actionIndex] = action
			if let labelReplacement {
				for index in presentation.cues[cueIndex].actions.indices
					where presentation.cues[cueIndex].actions[index].label.text == labelReplacement.old
				{
					presentation.cues[cueIndex].actions[index].label.text = labelReplacement.new
				}
			}
			return
		}

		let slideElementSuffixes = [
			["slide", "presentation", "base_slide", "elements", "element"],
			["slide", "presentation", "base_slide", "elements", "element", "fill", "media"],
		]
		let suffix = path.segments.dropFirst(2).map(\.field)
		guard slideElementSuffixes.contains(suffix),
		      let elementSelector = path.segments.first(where: { $0.field == "elements" })?.selector,
		      case var .presentation(slide)? = action.slide.slide
		else {
			throw unsupportedMediaPath(path)
		}
		let elementIndex = try slideElementIndex(in: slide.baseSlide, selector: elementSelector)
		var element = slide.baseSlide.elements[elementIndex].element
		element.fill.enable = true
		element.fill.media = try replacingMedia(element.fill.media, with: replacement, preserveUUID: preserveUUID)
		slide.baseSlide.elements[elementIndex].element = element
		action.slide.presentation = slide
		presentation.cues[cueIndex].actions[actionIndex] = action
	}

	public static func setMedia(
		in theme: inout Rv_Data_Template.Document,
		at path: ComponentPath,
		sourceURL: URL,
		preserveUUID: Bool = false,
		syncLabel: Bool = false,
	) throws {
		try setMedia(
			in: &theme,
			at: path,
			to: media(from: sourceURL),
			preserveUUID: preserveUUID,
			syncLabel: syncLabel,
		)
	}

	/// Replaces a complete media identity in a theme template's slide-element
	/// fill. Both the containing element and its `/fill/media` child are accepted.
	public static func setMedia(
		in theme: inout Rv_Data_Template.Document,
		at path: ComponentPath,
		to replacement: Rv_Data_Media,
		preserveUUID: Bool = false,
		syncLabel _: Bool = false,
	) throws {
		let suffix = path.segments.dropFirst().map(\.field)
		let elementSuffixes = [
			["base_slide", "elements", "element"],
			["base_slide", "elements", "element", "fill", "media"],
		]
		guard path.segments.first?.field == "slides",
		      path.segments.first?.selector != nil,
		      elementSuffixes.contains(suffix),
		      let elementSelector = path.segments.first(where: { $0.field == "elements" })?.selector
		else {
			throw unsupportedMediaPath(path)
		}

		let slideIndex = try templateIndex(
			in: theme,
			path: ComponentPath(segments: [path.segments[0]]),
		)
		var slide = theme.slides[slideIndex].baseSlide
		let elementIndex = try slideElementIndex(in: slide, selector: elementSelector)
		var element = slide.elements[elementIndex].element
		element.fill.enable = true
		element.fill.media = try replacingMedia(element.fill.media, with: replacement, preserveUUID: preserveUUID)
		slide.elements[elementIndex].element = element
		theme.slides[slideIndex].baseSlide = slide
	}

	private static func replacingMedia(
		_ existing: Rv_Data_Media,
		with replacement: Rv_Data_Media,
		preserveUUID: Bool,
	) throws -> Rv_Data_Media {
		guard preserveUUID else { return replacement }
		guard !existing.uuid.string.isEmpty else {
			throw DocumentEditError.unsupportedPatchValue(
				"Cannot preserve an empty media UUID. Replace the media identity or omit --preserve-uuid.",
			)
		}
		var replacement = replacement
		replacement.uuid = existing.uuid
		return replacement
	}

	private static func mediaBasename(_ media: Rv_Data_Media) -> String? {
		if let url = URL(string: media.url.absoluteString), !url.lastPathComponent.isEmpty {
			return url.lastPathComponent
		}
		let localPath = media.url.local.path
		guard !localPath.isEmpty else { return nil }
		return URL(fileURLWithPath: localPath).lastPathComponent
	}

	private static func unsupportedMediaPath(_ path: ComponentPath) -> ComponentPathError {
		.unsupported(
			field: path.description,
			at: "Expected an action /media/element or a presentation/theme slide /element/fill/media or /element.",
		)
	}

	@discardableResult
	public static func addElement(
		to presentation: inout Rv_Data_Presentation,
		at path: ComponentPath,
		name: String,
		bounds: CGRect,
		color: Rv_Data_Color,
	) throws -> String {
		guard path.segments.count == 5,
		      path.segments[0].field == "cues",
		      path.segments[1].field == "actions",
		      path.segments[2].field == "slide",
		      path.segments[3].field == "presentation",
		      path.segments[4].field == "base_slide",
		      let actionSelector = path.segments[1].selector
		else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let cueIndex = try cueIndex(in: presentation, path: ComponentPath(segments: [path.segments[0]]))
		let actionIndex = try actionIndex(in: presentation.cues[cueIndex], selector: actionSelector)
		var action = presentation.cues[cueIndex].actions[actionIndex]
		guard case var .presentation(slide)? = action.slide.slide else {
			throw ComponentPathError.noMatch(path: path.description, candidates: [])
		}
		var element = Rv_Data_Graphics.Element()
		element.uuid = DocumentFactory.uuid()
		element.name = name
		element.opacity = 1
		element.bounds.origin.x = bounds.origin.x
		element.bounds.origin.y = bounds.origin.y
		element.bounds.size.width = bounds.width
		element.bounds.size.height = bounds.height
		element.path = rectanglePath()
		element.fill.enable = true
		element.fill.color = color
		var slideElement = Rv_Data_Slide.Element()
		slideElement.element = element
		slideElement.info = (slide.baseSlide.elements.map(\.info).max() ?? 0) + 1
		slide.baseSlide.elements.append(slideElement)
		action.slide.presentation = slide
		presentation.cues[cueIndex].actions[actionIndex] = action
		return element.uuid.string
	}

	private static func rectanglePath() -> Rv_Data_Graphics.Path {
		var path = Rv_Data_Graphics.Path()
		path.closed = true
		path.shape.type = .rectangle
		path.points = [
			bezierPoint(x: 0, y: 0),
			bezierPoint(x: 1, y: 0),
			bezierPoint(x: 1, y: 1),
			bezierPoint(x: 0, y: 1),
		]
		return path
	}

	private static func bezierPoint(x: Double, y: Double) -> Rv_Data_Graphics.Path.BezierPoint {
		var point = Rv_Data_Graphics.Point()
		point.x = x
		point.y = y
		var result = Rv_Data_Graphics.Path.BezierPoint()
		result.point = point
		result.q0 = point
		result.q1 = point
		return result
	}

	@discardableResult
	public static func addAction(in presentation: inout Rv_Data_Presentation, to cuePath: ComponentPath, type: String, name: String?) throws -> String {
		let cueIndex = try cueIndex(in: presentation, path: cuePath)
		var action = Rv_Data_Action()
		action.uuid = DocumentFactory.uuid()
		action.type = try actionType(named: type)
		action.isEnabled = true
		action.name = name ?? ""
		action.label.text = name ?? type
		switch action.type {
		case .media, .backgroundMedia, .foregroundMedia:
			action.media = Rv_Data_Action.MediaType()
		case .timer:
			action.timer = Rv_Data_Action.TimerType()
		case .macro:
			action.macro = Rv_Data_Action.MacroType()
		case .clear:
			action.clear = Rv_Data_Action.ClearType()
		case .presentationSlide:
			var slide = Rv_Data_Slide()
			slide.uuid = DocumentFactory.uuid()
			slide.size = defaultSize()
			var presentationSlide = Rv_Data_PresentationSlide()
			presentationSlide.baseSlide = slide
			action.slide.presentation = presentationSlide
		default:
			break
		}
		presentation.cues[cueIndex].actions.append(action)
		return action.uuid.string
	}

	@discardableResult
	public static func addTemplate(to document: inout Rv_Data_Template.Document, name: String, size: Rv_Data_Graphics.Size? = nil) -> String {
		var slide = Rv_Data_Template.Slide()
		slide.name = name
		slide.baseSlide.uuid = DocumentFactory.uuid()
		slide.baseSlide.size = size ?? defaultSize()
		document.slides.append(slide)
		return slide.baseSlide.uuid.string
	}

	@discardableResult
	public static func addPlaylistItem(
		to document: inout Rv_Data_PlaylistDocument,
		at path: ComponentPath,
		type: String,
		name: String,
		documentURL: URL?,
	) throws -> String {
		guard path.segments.first?.field == "root_node", path.segments.first?.selector == nil else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		var item = Rv_Data_PlaylistItem()
		item.uuid = DocumentFactory.uuid()
		item.name = name
		switch type {
		case "header":
			item.header = Rv_Data_PlaylistItem.Header()
		case "presentation":
			guard let documentURL else {
				throw DocumentEditError.unsupportedPatchValue("A presentation playlist item requires --document.")
			}
			item.presentation.documentPath.absoluteString = documentURL.absoluteString
		default:
			throw DocumentEditError.unsupportedPatchValue("Unsupported playlist item type \(type). Supported types: header, presentation.")
		}
		var root = document.rootNode
		let createdPath = try appendPlaylistItem(
			item,
			to: &root,
			at: ArraySlice(path.segments.dropFirst()),
			basePath: "/root_node",
		)
		document.rootNode = root
		return createdPath
	}

	private static func appendPlaylistItem(
		_ item: Rv_Data_PlaylistItem,
		to playlist: inout Rv_Data_Playlist,
		at segments: ArraySlice<ComponentPath.Segment>,
		basePath: String,
	) throws -> String {
		if segments.isEmpty {
			if case .playlists? = playlist.childrenType,
			   playlist.name == "PLAYLIST",
			   playlist.playlists.playlists.count == 1
			{
				var wrapper = playlist.playlists
				var child = wrapper.playlists[0]
				let childPath = ComponentPathBuilder.repeatedPath(
					parent: "\(basePath)/playlists",
					field: "playlists",
					storageIndex: 0,
					identities: wrapper.playlists.map(\.uuid.string),
				)
				let result = try appendPlaylistItem(
					item,
					to: &child,
					at: [],
					basePath: childPath,
				)
				wrapper.playlists[0] = child
				playlist.playlists = wrapper
				return result
			}
			if playlist.isPlanningCenterConnected {
				throw DocumentEditError.planningCenterManagedContent(path: basePath)
			}
			if case .playlists? = playlist.childrenType, !playlist.playlists.playlists.isEmpty {
				throw ComponentPathError.unsupported(field: "items", at: "Selected playlist contains child playlists rather than items.")
			}
			var items = playlist.items
			items.items.append(item)
			playlist.items = items
			return ComponentPathBuilder.repeatedPath(
				parent: "\(basePath)/items",
				field: "items",
				storageIndex: items.items.count - 1,
				identities: items.items.map(\.uuid.string),
			)
		}

		guard segments.count >= 2,
		      segments.first?.field == "playlists",
		      segments.first?.selector == nil,
		      segments.dropFirst().first?.field == "playlists",
		      let selector = segments.dropFirst().first?.selector,
		      case .playlists? = playlist.childrenType
		else {
			throw ComponentPathError.unsupported(field: ComponentPath(segments: Array(segments)).description, at: "/root_node")
		}

		var wrapper = playlist.playlists
		let index = try index(in: wrapper.playlists, selector: selector, path: "/root_node/playlists/playlists", identity: { $0.uuid.string }, name: { $0.name })
		var child = wrapper.playlists[index]
		let childPath = ComponentPathBuilder.repeatedPath(
			parent: "\(basePath)/playlists",
			field: "playlists",
			storageIndex: index,
			identities: wrapper.playlists.map(\.uuid.string),
		)
		let result = try appendPlaylistItem(
			item,
			to: &child,
			at: segments.dropFirst(2),
			basePath: childPath,
		)
		wrapper.playlists[index] = child
		playlist.playlists = wrapper
		return result
	}

	public static func removeAction(in presentation: inout Rv_Data_Presentation, at path: ComponentPath) throws {
		guard path.segments.count == 2, path.segments[0].field == "cues", path.segments[1].field == "actions", let actionSelector = path.segments[1].selector else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let cueIndex = try cueIndex(in: presentation, path: ComponentPath(segments: [path.segments[0]]))
		let actionIndex = try actionIndex(in: presentation.cues[cueIndex], selector: actionSelector)
		presentation.cues[cueIndex].actions.remove(at: actionIndex)
	}

	public static func color(hex: String) throws -> Rv_Data_Color {
		let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
		guard value.count == 6, let raw = UInt32(value, radix: 16) else {
			throw DocumentEditError.unsupportedPatchValue("Color must be a six-digit RGB value such as #336699.")
		}
		var color = Rv_Data_Color()
		color.red = Float((raw >> 16) & 0xFF) / 255
		color.green = Float((raw >> 8) & 0xFF) / 255
		color.blue = Float(raw & 0xFF) / 255
		color.alpha = 1
		return color
	}

	public static func rect(_ value: String) throws -> CGRect {
		let values = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
		guard values.count == 4, values[2] > 0, values[3] > 0 else {
			throw DocumentEditError.unsupportedPatchValue("Bounds must be x,y,width,height with positive width and height.")
		}
		return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
	}

	private static func actionType(named value: String) throws -> Rv_Data_Action.ActionType {
		switch value {
		case "media": .media
		case "background-media": .backgroundMedia
		case "foreground-media": .foregroundMedia
		case "timer": .timer
		case "macro": .macro
		case "clear": .clear
		case "presentation-slide": .presentationSlide
		default: throw DocumentEditError.unsupportedPatchValue("Unsupported action type \(value). Supported types: media, background-media, foreground-media, timer, macro, clear, presentation-slide.")
		}
	}

	private static func cueGroupIndex(in presentation: Rv_Data_Presentation, path: ComponentPath) throws -> Int {
		guard path.segments.count == 1,
		      path.segments[0].field == "cue_groups",
		      let selector = path.segments[0].selector
		else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		return try cueGroupIndex(in: presentation, selector: selector)
	}

	private static func cueGroupIndex(in presentation: Rv_Data_Presentation, selector: ComponentPath.Selector) throws -> Int {
		let matches: [Int]
		switch selector {
		case let .index(index): matches = presentation.cueGroups.indices.contains(index) ? [index] : []
		case let .field(name, value):
			matches = presentation.cueGroups.indices.filter { index in
				switch name {
				case "uuid": presentation.cueGroups[index].group.uuid.string == value
				case "name": presentation.cueGroups[index].group.name == value
				default: false
				}
			}
		}
		guard matches.count == 1, let index = matches.first else {
			let identities = presentation.cueGroups.map(\.group.uuid.string)
			throw ComponentPathError.noMatch(
				path: "/cue_groups",
				candidates: presentation.cueGroups.indices.map { index in
					ComponentPathBuilder.repeatedPath(
						field: "cue_groups",
						storageIndex: index,
						identities: identities,
					)
				},
			)
		}
		return index
	}

	private struct SelectedCueReference {
		var storageIndex: Int
		var uuid: Rv_Data_UUID
		var path: String
	}

	private static func selectedCueReferences(
		in presentation: Rv_Data_Presentation,
		paths: [ComponentPath],
	) throws -> [SelectedCueReference] {
		var result: [SelectedCueReference] = []
		var seen = Set<String>()
		for path in paths {
			let storageIndex = try cueIndex(in: presentation, path: path)
			let uuid = presentation.cues[storageIndex].uuid
			let canonicalPath = presentation.componentPath(forCueAtStorageIndex: storageIndex)
			guard seen.insert(uuid.string).inserted else {
				throw CueGroupEditError.duplicateCueSelection(path: canonicalPath)
			}
			result.append(.init(storageIndex: storageIndex, uuid: uuid, path: canonicalPath))
		}
		return result
	}

	private static func validateCueOwnership(
		in presentation: Rv_Data_Presentation,
		cueReferences: [SelectedCueReference],
		targetGroupIndex: Int?,
		policy: CueGroupOwnershipPolicy,
	) throws {
		guard policy == .requireUnassignedOrSameGroup else { return }
		for reference in cueReferences {
			let otherGroups = presentation.cueGroups.indices.filter { groupIndex in
				groupIndex != targetGroupIndex && presentation.cueGroups[groupIndex].cueIdentifiers.contains(where: { $0.string == reference.uuid.string })
			}
			if !otherGroups.isEmpty {
				throw CueGroupEditError.cueAlreadyAssigned(
					cuePath: reference.path,
					groupPaths: otherGroups.map { cueGroupPath(at: $0, in: presentation) },
				)
			}
		}
	}

	private static func removeCueReferences(
		_ identifiers: [Rv_Data_UUID],
		from groups: inout [Rv_Data_Presentation.CueGroup],
	) {
		let values = Set(identifiers.map(\.string))
		guard !values.isEmpty else { return }
		for groupIndex in groups.indices {
			groups[groupIndex].cueIdentifiers.removeAll { values.contains($0.string) }
		}
	}

	private static func storedCueIdentifier(
		in presentation: Rv_Data_Presentation,
		matching identifier: Rv_Data_UUID,
		preferredGroupIndex: Int?,
	) -> Rv_Data_UUID {
		if let preferredGroupIndex,
		   let existing = presentation.cueGroups[preferredGroupIndex].cueIdentifiers.first(where: { $0.string == identifier.string })
		{
			return existing
		}
		for group in presentation.cueGroups {
			if let existing = group.cueIdentifiers.first(where: { $0.string == identifier.string }) {
				return existing
			}
		}
		return identifier
	}

	private static func freshUUID(preserving identifier: Rv_Data_UUID) -> Rv_Data_UUID {
		replacingUUIDString(in: identifier, with: DocumentFactory.uuid().string)
	}

	private static func replacingUUIDString(
		in identifier: Rv_Data_UUID,
		with string: String,
	) -> Rv_Data_UUID {
		var result = identifier
		result.string = string
		return result
	}

	private static func detachApplicationGroup(in group: inout Rv_Data_Group) {
		group.clearApplicationGroupIdentifier()
		group.applicationGroupName = ""
	}

	private static func cueGroupPath(at index: Int, in presentation: Rv_Data_Presentation) -> String {
		ComponentPathBuilder.repeatedPath(
			field: "cue_groups",
			storageIndex: index,
			identities: presentation.cueGroups.map(\.group.uuid.string),
		)
	}

	private static func cuePath(for identifier: Rv_Data_UUID, in presentation: Rv_Data_Presentation) -> String {
		let matches = presentation.cues.indices.filter { presentation.cues[$0].uuid.string == identifier.string }
		guard matches.count == 1, let storageIndex = matches.first else {
			return "/cues[uuid=\(identifier.string)]"
		}
		return presentation.componentPath(forCueAtStorageIndex: storageIndex)
	}

	private static func arrangementReferencePaths(
		to identifier: Rv_Data_UUID,
		in presentation: Rv_Data_Presentation,
	) -> [String] {
		let arrangementIDs = presentation.arrangements.map(\.uuid.string)
		return presentation.arrangements.enumerated().flatMap { arrangementIndex, arrangement in
			let arrangementPath = ComponentPathBuilder.repeatedPath(
				field: "arrangements",
				storageIndex: arrangementIndex,
				identities: arrangementIDs,
			)
			return arrangement.groupIdentifiers.enumerated().compactMap { referenceIndex, reference in
				reference.string == identifier.string ? "\(arrangementPath)/group_identifiers[index=\(referenceIndex)]" : nil
			}
		}
	}

	private static func validateNoExternalCueReferences(
		to identifiers: Set<String>,
		in presentation: Rv_Data_Presentation,
	) throws {
		for storageIndex in presentation.cues.indices {
			let cue = presentation.cues[storageIndex]
			guard !identifiers.contains(cue.uuid.string),
			      cue.completionTargetType == .cue,
			      identifiers.contains(cue.completionTargetUuid.string)
			else { continue }
			throw CueGroupEditError.referencedCueCannotBeDeleted(
				cuePath: cuePath(for: cue.completionTargetUuid, in: presentation),
				referencePath: "\(presentation.componentPath(forCueAtStorageIndex: storageIndex))/completion_target_uuid",
			)
		}
		for (index, cue) in presentation.timeline.cues.enumerated() {
			guard case let .cueID(identifier)? = cue.triggerInfo, identifiers.contains(identifier.string) else { continue }
			throw CueGroupEditError.referencedCueCannotBeDeleted(
				cuePath: cuePath(for: identifier, in: presentation),
				referencePath: "/timeline/cues[index=\(index)]/cue_id",
			)
		}
		for (index, cue) in presentation.timeline.cuesV2.enumerated() {
			guard case let .cueID(identifier)? = cue.triggerInfo, identifiers.contains(identifier.string) else { continue }
			throw CueGroupEditError.referencedCueCannotBeDeleted(
				cuePath: cuePath(for: identifier, in: presentation),
				referencePath: "/timeline/cues_v2[index=\(index)]/cue_id",
			)
		}
	}

	private static func groupIdentifiers(
		in presentation: Rv_Data_Presentation,
		for paths: [ComponentPath],
	) throws -> [Rv_Data_UUID] {
		try paths.map { path in
			guard path.segments.count == 1,
			      path.segments[0].field == "cue_groups",
			      let selector = path.segments[0].selector
			else {
				throw ComponentPathError.unsupported(field: path.description, at: "/")
			}
			return try presentation.cueGroups[cueGroupIndex(in: presentation, selector: selector)].group.uuid
		}
	}

	private static func arrangementIndex(
		in presentation: Rv_Data_Presentation,
		path: ComponentPath,
	) throws -> Int {
		guard path.segments.count == 1,
		      path.segments[0].field == "arrangements",
		      let selector = path.segments[0].selector
		else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		return try index(
			in: presentation.arrangements,
			selector: selector,
			path: path.description,
			identity: { $0.uuid.string },
			name: { $0.name },
		)
	}

	private static func sourceNameForCopy(_ name: String) -> String {
		name.isEmpty ? "Arrangement Copy" : "\(name) Copy"
	}

	private static func cueIndex(in presentation: Rv_Data_Presentation, path: ComponentPath) throws -> Int {
		guard path.segments.count == 1, path.segments[0].field == "cues", let selector = path.segments[0].selector else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let presentationOrder = presentation.presentationOrderCueIndices
		let matches: [Int] = switch selector {
		case let .index(value):
			presentationOrder.indices.contains(value) ? [presentationOrder[value]] : []
		case let .field(name, value):
			presentation.cues.indices.filter { index in
				let cue = presentation.cues[index]
				return switch name {
				case "uuid": cue.uuid.string == value
				case "name": cue.name == value
				case "is_enabled": String(cue.isEnabled) == value
				default: false
				}
			}
		}
		guard matches.count == 1, let index = matches.first else {
			let identities = presentation.cues.map(\.uuid.string)
			throw ComponentPathError.noMatch(
				path: path.description,
				candidates: presentationOrder.map { storageIndex in
					ComponentPathBuilder.repeatedPath(
						field: "cues",
						storageIndex: storageIndex,
						identities: identities,
						order: presentation.presentationCueIndexOrder,
					)
				},
			)
		}
		return index
	}

	private static func freshCopy(of source: Rv_Data_Cue) -> Rv_Data_Cue {
		var copy = source
		copy.uuid = freshUUID(preserving: source.uuid)
		if copy.completionTargetType == .cue,
		   copy.completionTargetUuid.string == source.uuid.string
		{
			copy.completionTargetUuid.string = copy.uuid.string
		}
		copy.name = source.name.isEmpty ? "Slide Copy" : "\(source.name) Copy"
		var actionMapping: [String: Rv_Data_UUID] = [:]
		for actionIndex in copy.actions.indices {
			let old = copy.actions[actionIndex].uuid.string
			copy.actions[actionIndex] = ProPresenterGraphCopier.freshAction(copy.actions[actionIndex])
			if !old.isEmpty {
				actionMapping[old] = copy.actions[actionIndex].uuid
			}
		}
		if copy.completionActionType == .afterAction,
		   let replacement = actionMapping[copy.completionActionUuid.string]
		{
			copy.completionActionUuid.string = replacement.string
		}
		return copy
	}

	private static func slideForDuplicate(in presentation: Rv_Data_Presentation, at path: ComponentPath) throws -> Rv_Data_Slide {
		guard path.segments.count == 4 || path.segments.count == 5,
		      path.segments[0].field == "cues",
		      path.segments[1].field == "actions",
		      path.segments[2].field == "slide",
		      path.segments[3].field == "presentation",
		      path.segments.count == 4 || path.segments[4].field == "base_slide",
		      let actionSelector = path.segments[1].selector
		else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let cue = try presentation.cues[cueIndex(in: presentation, path: ComponentPath(segments: [path.segments[0]]))]
		let action = try cue.actions[actionIndex(in: cue, selector: actionSelector)]
		guard case let .presentation(slide)? = action.slide.slide else {
			throw ComponentPathError.noMatch(path: path.description, candidates: [])
		}
		return slide.baseSlide
	}

	private static func makeSlideCue(identifier: Rv_Data_UUID, name: String, slide: Rv_Data_Slide) -> Rv_Data_Cue {
		var presentationSlide = Rv_Data_PresentationSlide()
		presentationSlide.baseSlide = slide
		var action = Rv_Data_Action()
		action.uuid = DocumentFactory.uuid()
		action.label.text = name
		action.type = .presentationSlide
		action.isEnabled = true
		action.slide.presentation = presentationSlide
		var cue = Rv_Data_Cue()
		cue.uuid = identifier
		cue.name = name
		cue.isEnabled = true
		cue.completionActionType = .last
		cue.actions = [action]
		return cue
	}

	private static func freshCopy(of source: Rv_Data_Template.Slide) -> Rv_Data_Template.Slide {
		var copy = source
		copy.name = source.name.isEmpty ? "Template Copy" : "\(source.name) Copy"
		copy.baseSlide = ProPresenterGraphCopier.freshSlide(copy.baseSlide)
		copy.actions = copy.actions.map(ProPresenterGraphCopier.freshAction)
		return copy
	}

	private static func freshCopy(of source: Rv_Data_Action) -> Rv_Data_Action {
		ProPresenterGraphCopier.freshAction(source)
	}

	private static func freshCopy(of source: Rv_Data_PlaylistItem) -> Rv_Data_PlaylistItem {
		var copy = source
		copy.uuid = DocumentFactory.uuid()
		copy.name = source.name.isEmpty ? "Item Copy" : "\(source.name) Copy"
		if case .cue? = copy.itemType {
			copy.cue = freshCopy(of: copy.cue)
		}
		if case .header? = copy.itemType {
			for index in copy.header.actions.indices {
				copy.header.actions[index] = freshCopy(of: copy.header.actions[index])
			}
		}
		return copy
	}

	private static func freshCopy(of source: Rv_Data_Playlist) -> Rv_Data_Playlist {
		var copy = source
		copy.uuid = DocumentFactory.uuid()
		copy.name = source.name.isEmpty ? "Playlist Copy" : "\(source.name) Copy"
		copy.children = source.children.map(freshCopy)
		var items = copy.items
		items.items = source.items.items.map(freshCopy)
		copy.items = items
		return copy
	}

	private static func actionIndex(in cue: Rv_Data_Cue, selector: ComponentPath.Selector) throws -> Int {
		let matches = cue.actions.indices.filter { index in
			let action = cue.actions[index]
			return switch selector {
			case let .index(value): index == value
			case let .field(name, value):
				switch name {
				case "uuid": action.uuid.string == value
				case "name": action.name == value
				default: false
				}
			}
		}
		guard matches.count == 1, let index = matches.first else {
			let identities = cue.actions.map(\.uuid.string)
			throw ComponentPathError.noMatch(
				path: "/actions",
				candidates: cue.actions.indices.map { index in
					ComponentPathBuilder.repeatedPath(
						field: "actions",
						storageIndex: index,
						identities: identities,
					)
				},
			)
		}
		return index
	}

	private static func slideElementIndex(in slide: Rv_Data_Slide, selector: ComponentPath.Selector) throws -> Int {
		let matches = slide.elements.indices.filter { index in
			let element = slide.elements[index].element
			return switch selector {
			case let .index(value): index == value
			case let .field(name, value):
				switch name {
				case "uuid": element.uuid.string == value
				case "name": element.name == value
				default: false
				}
			}
		}
		guard matches.count == 1, let index = matches.first else {
			let identities = slide.elements.map(\.element.uuid.string)
			throw ComponentPathError.noMatch(
				path: "/elements",
				candidates: slide.elements.indices.map { index in
					ComponentPathBuilder.repeatedPath(
						field: "elements",
						storageIndex: index,
						identities: identities,
					)
				},
			)
		}
		return index
	}

	private static func indexInGroup(for path: ComponentPath, presentation: Rv_Data_Presentation, groupIndex: Int) throws -> Int {
		guard path.segments.count == 1, path.segments[0].field == "cues", path.segments[0].selector != nil else {
			throw ComponentPathError.unsupported(field: path.description, at: "/")
		}
		let cueIDs = presentation.cueGroups[groupIndex].cueIdentifiers
		let cueIndex = try cueIndex(in: presentation, path: path)
		let matches = cueIDs.indices.filter { cueIDs[$0].string == presentation.cues[cueIndex].uuid.string }
		guard matches.count == 1, let index = matches.first else {
			let identities = presentation.cues.map(\.uuid.string)
			let order = presentation.presentationCueIndexOrder
			throw ComponentPathError.noMatch(
				path: path.description,
				candidates: order.storageIndices.map { storageIndex in
					ComponentPathBuilder.repeatedPath(
						field: "cues",
						storageIndex: storageIndex,
						identities: identities,
						order: order,
					)
				},
			)
		}
		return index
	}

	private static func defaultSize() -> Rv_Data_Graphics.Size {
		var size = Rv_Data_Graphics.Size()
		size.width = 1920
		size.height = 1080
		return size
	}
}
