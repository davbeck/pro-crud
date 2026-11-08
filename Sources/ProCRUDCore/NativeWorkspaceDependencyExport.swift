import Foundation
import ProPresenterProto

public struct NativeWorkspaceDependencyExportResult: Encodable, Sendable {
	public struct Document: Encodable, Sendable {
		public let path: String
		public let messageType: String
	}

	public let path: String
	public let workspaceID: UUID
	public let playlistID: UUID
	public let targetVersion: ProPresenterTargetVersion = .v22
	public let documents: [Document]
}

/// A separate legacy-workspace directory, imported as a new workspace. It is
/// never overlaid onto an existing native workspace or disguised as a playlist.
public enum NativeWorkspaceDependencyExporter {
	public static func export(from snapshot: NativeWorkspaceSnapshot, playlistID: UUID, to output: URL) throws -> NativeWorkspaceDependencyExportResult {
		let destination = output.resolvingSymlinksInPath().standardizedFileURL
		let root = snapshot.root.resolvingSymlinksInPath().standardizedFileURL.path
		guard destination.path != root, !destination.path.hasPrefix(root + "/"), !root.hasPrefix(destination.path + "/") else { throw DocumentArchiveError.unsafeWorkspaceEntry(output.path) }
		try WorkspaceInspector.requireLegacyAccess(at: destination)
		guard !FileManager.default.fileExists(atPath: destination.path) else { throw DocumentArchiveError.outputExists(destination) }
		let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).procrud-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
		defer { try? FileManager.default.removeItem(at: staging) }
		let closure = NativeWorkspaceDependencyClosure(snapshot: snapshot, directory: staging)
		try closure.addPlaylist(kind: "PlaylistLibrary", id: playlistID, name: nil)
		try closure.publish()
		let documents = closure.documents.map { NativeWorkspaceDependencyExportResult.Document(path: $0.key, messageType: $0.value.message) } + closure.exporter.dependencies.map { .init(path: $0.archivePath, messageType: Rv_Data_Presentation.protoMessageName) }
		let result = NativeWorkspaceDependencyExportResult(path: destination.path, workspaceID: snapshot.workspaceID, playlistID: playlistID, documents: documents.sorted { $0.path < $1.path })
		let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		try encoder.encode(result).write(to: staging.appendingPathComponent("pro-crud-dependencies.json"))
		try ArchiveFileIO.installTemporaryFile(staging, at: destination, replaceExisting: false)
		return result
	}
}

final class NativeWorkspaceDependencyClosure {
	struct Document { let message: String; var data: Data }
	let snapshot: NativeWorkspaceSnapshot
	let exporter: NativeDependencyExport
	private(set) var documents: [String: Document] = [:]
	private var selectedPlaylists: [String: Set<UUID>] = [:]
	private var playlists: [String: Rv_Data_PlaylistDocument] = [:]
	private var selectedNodes: [String: [Rv_Data_Playlist]] = [:]
	private var projections: [String: NativeProtobufProjection] = [:]

	init(snapshot: NativeWorkspaceSnapshot, directory: URL) {
		self.snapshot = snapshot
		exporter = .init(snapshot: snapshot, target: .v22, directory: directory, workspaceLayout: true)
		exporter.workspace = self
	}

	func intercept(_ data: Data, message: String, path: String) throws -> Data? {
		switch message {
		case "rv.data.Action.MacroType":
			try definition(Rv_Data_Action.MacroType(serializedBytes: data).identification, kind: "Macros", type: "rv.data.MacrosDocument.Macro"); return data
		case "rv.data.Action.TimerType":
			try definition(Rv_Data_Action.TimerType(serializedBytes: data).timerIdentification, kind: "Timers", type: "rv.data.Timer"); return data
		case "rv.data.Action.AudienceLookType":
			try definition(Rv_Data_Action.AudienceLookType(serializedBytes: data).identification, kind: "Workspace", type: "rv.data.ProAudienceLook"); return data
		case "rv.data.Action.PropType":
			try definition(Rv_Data_Action.PropType(serializedBytes: data).identification, kind: "Props", type: "rv.data.Cue"); return data
		case "rv.data.Action.MessageType":
			let value = try Rv_Data_Action.MessageType(serializedBytes: data)
			try definition(value.messageIdentificaton, kind: "Messages", type: "rv.data.Message")
			// Token values can carry additional timer references.
			return try NativeDependencyWire.rewrite(data, message: message, path: path) { bytes, type, nested in
				if type == "rv.data.CollectionElementType" {
					return bytes
				}
				if type == message {
					return nil
				}
				return try self.exporter.rewrite(bytes, message: type, path: nested)
			}
		case "rv.data.Action.ClearGroupType":
			try definition(Rv_Data_Action.ClearGroupType(serializedBytes: data).identification, kind: "ClearGroups", type: "rv.data.ClearGroupsDocument.ClearGroup"); return data
		case "rv.data.Stage.ScreenAssignment":
			let value = try Rv_Data_Stage.ScreenAssignment(serializedBytes: data)
			try definition(value.screen, kind: "Workspace", type: "rv.data.CloudProPresenterScreen")
			try definition(value.layout, kind: "Stage", type: "rv.data.Stage.Layout"); return data
		case "rv.data.Message.Token.TokenTypeTimer":
			let value = try Rv_Data_Message.Token.TokenTypeTimer(serializedBytes: data)
			try definition(.with { $0.parameterUuid = value.timerUuid; $0.parameterName = value.name }, kind: "Timers", type: "rv.data.Timer"); return data
		case "rv.data.TemplateIdentification":
			let value = try Rv_Data_TemplateIdentification(serializedBytes: data)
			guard !value.uuid.string.isEmpty || !value.name.isEmpty else { return data }
			guard value.uuid.string.isEmpty, UUID(uuidString: value.slideUuid.string) != nil else { throw NativeSemanticError.unsupportedNode(path: path, kind: "Theme document-UUID/index-only selector portability; native Theme document IDs change during workspace import") }
			let candidates = snapshot.streams.filter { stream in
				guard stream.identity.kind == "Theme", stream.identity.scope == .shared else { return false }
				return stream.identity.corePath == value.name + "/Theme"
			}
			guard candidates.count == 1, let theme = candidates.first, let corePath = theme.identity.corePath else { throw NativeSemanticError.missingReference(path: path, identity: "unique Theme \(value.uuid.string) \(value.name)") }
			try addTheme(.with { $0.local.root = .show; $0.local.path = "Themes/\(corePath)" }, templateID: value.slideUuid.string); return data
		case "rv.data.Action.PlaylistItemType":
			let value = try Rv_Data_Action.PlaylistItemType(serializedBytes: data)
			// The containing Action determines media versus audio. Resolve by
			// UUID across both roots; a name-only selector must also be unique.
			let candidates = try ["PlaylistMedia", "PlaylistAudio"].flatMap { kind in
				try playlistNodes(kind: kind).filter { node in
					value.playlistUuid.string.isEmpty ? node.name == value.playlistName : UUID(uuidString: node.uuid.string) == UUID(uuidString: value.playlistUuid.string)
				}.map { (kind, $0) }
			}
			guard candidates.count == 1, let (kind, node) = candidates.first else { throw NativeSemanticError.missingReference(path: path, identity: "unique media/audio playlist \(value.playlistUuid.string) \(value.playlistName)") }
			if !value.itemUuid.string.isEmpty || !value.itemName.isEmpty {
				let items = node.items.items.filter { value.itemUuid.string.isEmpty ? $0.name == value.itemName : UUID(uuidString: $0.uuid.string) == UUID(uuidString: value.itemUuid.string) }
				guard items.count == 1 else { throw NativeSemanticError.missingReference(path: path, identity: "unique playlist item \(value.itemUuid.string) \(value.itemName)") }
			}
			try addPlaylist(kind: kind, id: UUID(uuidString: node.uuid.string), name: nil); return data
		case "rv.data.ProAudienceLook.ProScreenLook":
			let value = try Rv_Data_ProAudienceLook.ProScreenLook(serializedBytes: data)
			if value.hasTemplateDocumentFilePath, !value.templateDocumentFilePath.renderPath.isEmpty {
				try addTheme(value.templateDocumentFilePath, templateID: value.templateSlideUuid.string)
			}
			return nil
		case "rv.data.URL":
			let value = try Rv_Data_URL(serializedBytes: data)
			if value.local.path.hasPrefix("Themes/"), path.hasPrefix("/Configuration/Workspace/") {
				try addTheme(value, templateID: nil)
				var url = value; url.local.root = .show; url.relativePath = url.local.path
				return try url.serializedData()
			}
			return nil
		default: return nil
		}
	}

	func addPlaylist(kind: String, id: UUID?, name: String?) throws {
		let candidates = try playlistNodes(kind: kind).filter { node in id.map { UUID(uuidString: node.uuid.string) == $0 } ?? (node.name == name) }
		guard candidates.count == 1, let node = candidates.first, let id = UUID(uuidString: node.uuid.string) else { throw NativeSemanticError.missingReference(path: kind, identity: id?.uuidString ?? name ?? "playlist") }
		guard selectedPlaylists[kind, default: []].insert(id).inserted else { return }
		let rewritten = try Rv_Data_Playlist(serializedBytes: exporter.rewrite(node.serializedData(), message: Rv_Data_Playlist.protoMessageName, path: "/\(kind)/\(id)"))
		selectedNodes[kind, default: []].append(rewritten)
	}

	func publish() throws {
		for (kind, nodes) in selectedNodes {
			guard var document = playlists[kind] else { preconditionFailure("Missing prepared playlist") }
			document.rootNode.playlists.playlists = nodes; document.clearLiveVideoPlaylist(); document.clearDownloadsPlaylist()
			let usedTags = Set(nodes.flatMap { $0.items.items.flatMap(\.tags) }.map { $0.string.lowercased() })
			document.tags = document.tags.filter { usedTags.contains($0.uuid.string.lowercased()) }
			guard Set(document.tags.map { $0.uuid.string.lowercased() }) == usedTags else { throw NativeSemanticError.missingReference(path: kind, identity: "playlist tag definitions") }
			let filename = ["PlaylistLibrary": "Library", "PlaylistMedia": "Media", "PlaylistAudio": "Audio"][kind] ?? kind
			documents["Playlists/\(filename)"] = try .init(message: Rv_Data_PlaylistDocument.protoMessageName, data: document.serializedData())
		}
		// Validate all roots before writing any document or publishing output.
		for (path, document) in documents {
			do { documents[path] = try .init(message: document.message, data: NativeWorkspaceInterchange.document(document.data, message: document.message)) }
			catch { exporter.issue("native-workspace-interchange", path: path, message: String(describing: error)) }
		}
		for (path, document) in documents.sorted(by: { $0.key < $1.key }) {
			let report = try DocumentCompatibility.analyzeNativeDependencies(document.data, message: document.message)
			for issue in report.issues {
				exporter.issue(issue.feature, path: path + issue.componentPath, message: issue.message)
			}
		}
		try exporter.publishDocuments()
		for (path, document) in documents {
			try DocumentArchive.validateWorkspacePath(path, limits: .default)
			let url = exporter.directory.appendingPathComponent(path)
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try document.data.write(to: url)
		}
	}

	private func projection(_ kind: String) throws -> NativeProtobufProjection {
		if let value = projections[kind] {
			return value
		}
		let streams = snapshot.streams.filter { $0.identity.kind == kind && $0.identity.scope == .shared }
		guard streams.count == 1, let stream = streams.first else { throw NativeSemanticError.missingReference(path: "/configuration", identity: "one shared \(kind) stream") }
		let value = try stream.protobufProjection(); try value.requireComplete()
		projections[kind] = value
		return value
	}

	private func playlistNodes(kind: String) throws -> [Rv_Data_Playlist] {
		if playlists[kind] == nil {
			guard snapshot.streams.contains(where: { $0.identity.kind == kind && $0.identity.scope == .shared }) else { return [] }
			playlists[kind] = try Rv_Data_PlaylistDocument(serializedBytes: projection(kind).protobuf)
		}
		func nodes(_ node: Rv_Data_Playlist) -> [Rv_Data_Playlist] {
			if case .items? = node.childrenType {
				return [node]
			}
			return node.playlists.playlists.flatMap(nodes)
		}
		return playlists[kind].map { nodes($0.rootNode) } ?? []
	}

	private func definition(_ selector: Rv_Data_CollectionElementType, kind: String, type: String) throws {
		let source = try projection(kind)
		var matches: [Data] = []
		_ = try NativeDependencyWire.rewrite(source.protobuf, message: source.messageType, path: "") { data, message, _ in
			guard message == type else { return nil }
			let wire = try MediaWireMessage(data)
			let descriptor = try ProtobufSchema.bundled(version: .v22).message(named: type)
			guard let uuidField = descriptor.fieldsByName["uuid"], let nameField = descriptor.fieldsByName["name"] ?? descriptor.fieldsByName["title"] else { throw NativeSemanticError.unsupportedNode(path: kind, kind: "definition identity for \(type)") }
			let uuid = try wire.message(uuidField.number).map { try Rv_Data_UUID(serializedBytes: $0.data).string }
			let name = try wire.string(nameField.number)
			if !selector.parameterUuid.string.isEmpty {
				guard let id = UUID(uuidString: selector.parameterUuid.string) else { throw NativeSemanticError.invalidValue(path: kind, expected: "definition UUID") }
				if uuid.flatMap(UUID.init(uuidString:)) == id {
					matches.append(data)
				}
			} else if !selector.parameterName.isEmpty, name == selector.parameterName {
				matches.append(data)
			}
			return data
		}
		guard matches.count == 1 else { throw NativeSemanticError.missingReference(path: kind, identity: "unique \(type) \(selector.parameterUuid.string) \(selector.parameterName)") }
		let path = "Configuration/\(kind)"
		guard documents[path] == nil else { return }
		// Register before traversal, so recursive Macro graphs terminate. Keep
		// the owning definition collection, including its native order/metadata.
		documents[path] = .init(message: source.messageType, data: source.protobuf)
		let rewritten = try exporter.rewrite(source.protobuf, message: source.messageType, path: "/\(path)")
		documents[path] = .init(message: source.messageType, data: rewritten)
	}

	private func addTheme(_ url: Rv_Data_URL, templateID: String?) throws {
		let value: NativeWorkspaceValue = .map(["RelativeFilePath": .map(["__tag": .string("local"), "local": .map(["root": .integer(Int64(url.local.root.rawValue)), "path": .string(url.local.path)])])])
		let reference = try NativeWorkspaceReferenceResolver(streams: snapshot.streams).theme(inWorkspaceDocument: value)
		guard let id = reference.documentID, let stream = snapshot.streams.first(where: { $0.identity.documentID == id && $0.identity.scope == .shared }), let corePath = stream.identity.corePath else { throw NativeSemanticError.missingReference(path: "/Themes", identity: url.renderPath) }
		let projection = try stream.protobufProjection(); try projection.requireComplete()
		let theme = try Rv_Data_Template.Document(serializedBytes: projection.protobuf)
		if let templateID {
			guard let id = UUID(uuidString: templateID), theme.slides.count(where: { UUID(uuidString: $0.baseSlide.uuid.string) == id }) == 1 else { throw NativeSemanticError.missingReference(path: corePath, identity: templateID) }
		}
		let path = "Themes/\(corePath)"
		guard documents[path] == nil else { return }
		try DocumentArchive.validateWorkspacePath(path, limits: .default)
		documents[path] = .init(message: projection.messageType, data: projection.protobuf)
		let rewritten = try exporter.rewrite(projection.protobuf, message: projection.messageType, path: "/\(path)")
		documents[path] = .init(message: projection.messageType, data: rewritten)
	}
}
