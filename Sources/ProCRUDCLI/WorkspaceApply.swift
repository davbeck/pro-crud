import ArgumentParser
import Foundation
import ProCRUDCore

struct WorkspaceApply: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "apply", abstract: "Apply a JSON batch of supported native document edits atomically. Quit ProPresenter and stop workspace helpers first.")
	@Argument(help: "Exact registered local native workspace root.") var input: String
	@Option(help: "Version-1 native edit manifest. All operations are prepared before any database write.") var file: String
	@Option(help: "Exact local registry-v1.sqlite3 path.") var registry: String

	func run() throws {
		let manifest = URL(fileURLWithPath: file)
		let operations = try NativeEditManifest.decode(Data(contentsOf: manifest), relativeTo: manifest.deletingLastPathComponent())
		let root = URL(fileURLWithPath: input).resolvingSymlinksInPath()
		let receipts = try NativeLocalWorkspaceWriter.apply(operations, in: root, registry: URL(fileURLWithPath: registry))
		try print(prettyJSON(Result(root: root.path, operationCount: operations.count, changed: !receipts.isEmpty, receipts: receipts)))
	}

	private struct Result: Encodable {
		let root: String
		let operationCount: Int
		let changed: Bool
		let receipts: [NativeLocalCommitReceipt]
	}
}

enum NativeEditManifest {
	static func decode(_ data: Data, relativeTo directory: URL) throws -> [NativePresentationOperation] {
		let decoder = JSONDecoder()
		do {
			return try decoder.decode(Manifest.self, from: data).operations.map { try $0.resolve(relativeTo: directory) }
		} catch let error as DecodingError {
			let context: DecodingError.Context
			switch error {
			case let .dataCorrupted(value), let .keyNotFound(_, value), let .typeMismatch(_, value), let .valueNotFound(_, value): context = value
			@unknown default: throw error
			}
			let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: "/")
			throw ValidationError("Invalid native edit manifest at /\(path): \(context.debugDescription)")
		}
	}

	private struct Manifest: Decodable {
		let operations: [Instruction]

		init(from decoder: Decoder) throws {
			try requireKeys(["version", "operations"], decoder: decoder)
			let container = try decoder.container(keyedBy: Key.self)
			guard try container.decode(Int.self, forKey: .version) == 1 else { throw invalid("Expected native edit manifest version 1.", decoder: decoder) }
			operations = try container.decode([Instruction].self, forKey: .operations)
			guard !operations.isEmpty else { throw invalid("Provide at least one native edit operation.", decoder: decoder) }
		}
	}

	private struct Instruction: Decodable {
		let stream: UUID
		private let payload: Payload

		private enum Payload {
			case edit(NativePresentationEdit)
			case rtfFile(action: UUID, path: String)
			case textRTFFile(action: UUID, element: UUID, path: String)
			case templateRTFFile(slide: UUID, element: UUID, path: String)
		}

		func resolve(relativeTo directory: URL) throws -> NativePresentationOperation {
			let edit: NativePresentationEdit
			switch payload {
			case let .edit(value): edit = value
			case let .rtfFile(action, path): edit = try .slideNotes(actionID: action, content: .rtf(Data(contentsOf: URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: directory.path, isDirectory: true)))))
			case let .textRTFFile(action, element, path): edit = try .slideText(actionID: action, elementID: element, content: .rtf(Data(contentsOf: URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: directory.path, isDirectory: true)))))
			case let .templateRTFFile(slide, element, path): edit = try .template(.text(slide: slide, element: element, content: .rtf(Data(contentsOf: URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: directory.path, isDirectory: true))))))
			}
			return .init(documentID: stream, edit: edit)
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: Key.self)
			stream = try container.decode(UUID.self, forKey: .stream)
			let op = try container.decode(Operation.self, forKey: .op)
			let fields: Set<String>
			switch op {
			case .renamePlaylistNode:
				fields = ["node", "name"]
				payload = try .edit(.playlist(.rename(container.decode(UUID.self, forKey: .node), container.decode(String.self, forKey: .name))))
			case .setPlaylistItemHidden:
				fields = ["item", "hidden"]
				payload = try .edit(.playlist(.hidden(container.decode(UUID.self, forKey: .item), container.decode(Bool.self, forKey: .hidden))))
			case .movePlaylistNode:
				fields = ["node", "parent", "after"]
				payload = try .edit(.playlist(.move(container.decode(UUID.self, forKey: .node), parent: container.decode(UUID.self, forKey: .parent), after: container.decodeIfPresent(UUID.self, forKey: .after))))
			case .removePlaylistNode:
				fields = ["node"]
				payload = try .edit(.playlist(.remove(container.decode(UUID.self, forKey: .node))))
			case .addPlaylistGroup, .addPlaylist, .addPlaylistHeader, .addPlaylistPresentation:
				fields = ["node", "parent", "name", "after"]
				var allowed = fields
				let kind: NativePlaylistEdit.NewNode
				switch op {
				case .addPlaylistGroup: kind = .group
				case .addPlaylist: kind = .playlist
				case .addPlaylistHeader: kind = .header
				default:
					allowed.formUnion(["presentation", "arrangement"])
					kind = try .presentation(container.decode(UUID.self, forKey: .presentation), arrangement: container.decodeIfPresent(UUID.self, forKey: .arrangement))
				}
				try requireKeys(allowed.union(["stream", "op"]), decoder: decoder)
				payload = try .edit(.playlist(.create(id: container.decode(UUID.self, forKey: .node), parent: container.decode(UUID.self, forKey: .parent), name: container.decode(String.self, forKey: .name), kind: kind, after: container.decodeIfPresent(UUID.self, forKey: .after))))
				return
			case .linkPlanningCenterItem:
				fields = ["item", "presentation", "linkedItem", "arrangement"]
				payload = try .edit(.playlist(.link(item: container.decode(UUID.self, forKey: .item), presentation: container.decode(UUID.self, forKey: .presentation), linkedID: container.decode(UUID.self, forKey: .linkedItem), arrangement: container.decodeIfPresent(UUID.self, forKey: .arrangement))))
			case .unlinkPlanningCenterItem:
				fields = ["item"]
				payload = try .edit(.playlist(.unlink(container.decode(UUID.self, forKey: .item))))
			case .setPlaylistItemArrangement:
				fields = ["item", "arrangement"]
				guard container.contains(.arrangement) else { throw invalid("Provide an arrangement UUID or explicit null for Master.", decoder: decoder) }
				payload = try .edit(.playlist(.arrangement(item: container.decode(UUID.self, forKey: .item), arrangement: container.decodeIfPresent(UUID.self, forKey: .arrangement))))
			case .renameTemplate:
				fields = ["template", "name"]
				payload = try .edit(.template(.rename(container.decode(UUID.self, forKey: .template), container.decode(String.self, forKey: .name))))
			case .moveTemplate:
				fields = ["template", "after"]
				payload = try .edit(.template(.move(container.decode(UUID.self, forKey: .template), after: container.decodeIfPresent(UUID.self, forKey: .after))))
			case .setTemplateText:
				fields = ["template", "element", "text", "rtfFile"]
				let slide = try container.decode(UUID.self, forKey: .template), element = try container.decode(UUID.self, forKey: .element)
				guard container.contains(.text) != container.contains(.rtfFile) else { throw invalid("set-template-text requires exactly one of text or rtfFile.", decoder: decoder) }
				if container.contains(.text) {
					payload = try .edit(.template(.text(slide: slide, element: element, content: .text(container.decode(String.self, forKey: .text)))))
				} else {
					payload = try .templateRTFFile(slide: slide, element: element, path: container.decode(String.self, forKey: .rtfFile))
				}
			case .setCopyrightTitle:
				fields = ["title"]
				payload = try .edit(.copyrightTitle(container.decode(String.self, forKey: .title)))
			case .setNotes:
				fields = ["text"]
				payload = try .edit(.notes(container.decode(String.self, forKey: .text)))
			case .setSlideNotes:
				fields = ["action", "text", "rtfFile"]
				let action = try container.decode(UUID.self, forKey: .action)
				guard container.contains(.text) != container.contains(.rtfFile) else { throw invalid("set-slide-notes requires exactly one of text or rtfFile.", decoder: decoder) }
				if container.contains(.text) {
					payload = try .edit(.slideNotes(actionID: action, content: .text(container.decode(String.self, forKey: .text))))
				} else {
					let path = try container.decode(String.self, forKey: .rtfFile)
					payload = .rtfFile(action: action, path: path)
				}
			case .setText:
				fields = ["action", "element", "text", "rtfFile"]
				let action = try container.decode(UUID.self, forKey: .action)
				let element = try container.decode(UUID.self, forKey: .element)
				guard container.contains(.text) != container.contains(.rtfFile) else { throw invalid("set-text requires exactly one of text or rtfFile.", decoder: decoder) }
				if container.contains(.text) {
					payload = try .edit(.slideText(actionID: action, elementID: element, content: .text(container.decode(String.self, forKey: .text))))
				} else {
					payload = try .textRTFFile(action: action, element: element, path: container.decode(String.self, forKey: .rtfFile))
				}
			case .moveCue:
				fields = ["cue", "after"]
				payload = try .edit(.moveCue(container.decode(UUID.self, forKey: .cue), after: container.decode(UUID.self, forKey: .after)))
			case .transferCue:
				fields = ["cue", "group", "after"]
				payload = try .edit(.transferCue(container.decode(UUID.self, forKey: .cue), to: container.decode(UUID.self, forKey: .group), after: container.decodeIfPresent(UUID.self, forKey: .after)))
			case .renameCueGroup:
				fields = ["group", "name"]
				payload = try .edit(.cueGroupName(container.decode(UUID.self, forKey: .group), container.decode(String.self, forKey: .name)))
			case .splitCueGroup:
				fields = ["cue", "group", "templateGroup", "name"]
				payload = try .edit(.splitCueGroup(startingAt: container.decode(UUID.self, forKey: .cue), newID: container.decode(UUID.self, forKey: .group), template: container.decode(UUID.self, forKey: .templateGroup), name: container.decode(String.self, forKey: .name)))
			case .setArrangementGroups:
				fields = ["arrangement", "groups"]
				payload = try .edit(.arrangementGroups(container.decode(UUID.self, forKey: .arrangement), container.decode([UUID].self, forKey: .groups)))
			case .renameArrangement:
				fields = ["arrangement", "name"]
				payload = try .edit(.arrangementName(container.decode(UUID.self, forKey: .arrangement), container.decode(String.self, forKey: .name)))
			case .addArrangement:
				fields = ["arrangement", "name", "groups", "select"]
				payload = try .edit(.createArrangement(id: container.decode(UUID.self, forKey: .arrangement), name: container.decode(String.self, forKey: .name), groups: container.decode([UUID].self, forKey: .groups), select: container.decode(Bool.self, forKey: .select)))
			case .duplicateArrangement:
				fields = ["arrangement", "newArrangement", "name", "select"]
				payload = try .edit(.duplicateArrangement(container.decode(UUID.self, forKey: .arrangement), newID: container.decode(UUID.self, forKey: .newArrangement), name: container.decode(String.self, forKey: .name), select: container.decode(Bool.self, forKey: .select)))
			case .clearDocumentActionArrangement:
				fields = ["action"]
				payload = try .edit(.clearDocumentActionArrangement(container.decode(UUID.self, forKey: .action)))
			case .removeMediaAction:
				fields = ["action"]
				payload = try .edit(.removeMediaAction(container.decode(UUID.self, forKey: .action)))
			case .removeArrangement:
				fields = ["arrangement"]
				payload = try .edit(.removeArrangement(container.decode(UUID.self, forKey: .arrangement)))
			case .selectArrangement:
				fields = ["arrangement"]
				guard container.contains(.arrangement) else { throw invalid("select-arrangement requires an arrangement UUID or explicit null for Master.", decoder: decoder) }
				payload = try .edit(.selectedArrangement(container.decodeIfPresent(UUID.self, forKey: .arrangement)))
			}
			try requireKeys(fields.union(["stream", "op"]), decoder: decoder)
		}
	}

	private enum Operation: String, Decodable {
		case renamePlaylistNode = "rename-playlist-node"
		case setPlaylistItemHidden = "set-playlist-item-hidden"
		case movePlaylistNode = "move-playlist-node"
		case removePlaylistNode = "remove-playlist-node"
		case addPlaylistGroup = "add-playlist-group"
		case addPlaylist = "add-playlist"
		case addPlaylistHeader = "add-playlist-header"
		case addPlaylistPresentation = "add-playlist-presentation"
		case linkPlanningCenterItem = "link-planning-center-item"
		case unlinkPlanningCenterItem = "unlink-planning-center-item"
		case setPlaylistItemArrangement = "set-playlist-item-arrangement"
		case renameTemplate = "rename-template"
		case moveTemplate = "move-template"
		case setTemplateText = "set-template-text"
		case setCopyrightTitle = "set-copyright-title"
		case setNotes = "set-notes"
		case setSlideNotes = "set-slide-notes"
		case setText = "set-text"
		case moveCue = "move-cue"
		case transferCue = "transfer-cue"
		case renameCueGroup = "rename-cue-group"
		case splitCueGroup = "split-cue-group"
		case setArrangementGroups = "set-arrangement-groups"
		case renameArrangement = "rename-arrangement"
		case selectArrangement = "select-arrangement"
		case addArrangement = "add-arrangement"
		case duplicateArrangement = "duplicate-arrangement"
		case removeArrangement = "remove-arrangement"
		case clearDocumentActionArrangement = "clear-document-action-arrangement"
		case removeMediaAction = "remove-media-action"
	}

	private enum Key: String, CodingKey {
		case version, operations, stream, op, title, text, action, element, rtfFile, cue, after, group, name, arrangement, groups, newArrangement, select, templateGroup, node, parent, item, hidden, presentation, linkedItem, template
	}

	private struct AnyKey: CodingKey {
		let stringValue: String
		let intValue: Int? = nil
		init?(stringValue: String) {
			self.stringValue = stringValue
		}

		init?(intValue _: Int) {
			nil
		}
	}

	private static func requireKeys(_ allowed: Set<String>, decoder: Decoder) throws {
		let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
		let unknown = Set(keys).subtracting(allowed)
		guard unknown.isEmpty else { throw invalid("Unsupported native edit fields: \(unknown.sorted().joined(separator: ", ")).", decoder: decoder) }
	}

	private static func invalid(_ message: String, decoder: Decoder) -> DecodingError {
		.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
	}
}
