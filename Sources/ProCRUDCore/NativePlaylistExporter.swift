import Foundation
import ProPresenterProto
import SwiftProtobuf

public struct NativePlaylistExportResult: Encodable, Sendable {
	public struct Dependency: Encodable, Sendable {
		public let documentID: UUID
		public let archivePath: String
	}

	public let path: String
	public let workspaceID: UUID
	public let playlistID: UUID
	public let dependencies: [Dependency]
	public let compatibility: DocumentCompatibilityReport
	public let warnings: [String]
}

public enum NativePlaylistExporter {
	/// Exports one standard playlist with its media-free Presentation dependencies.
	/// Resolution uses native logical identities from this snapshot, never raw
	/// leftovers or a filename-only search. Both occurrences of a repeated link
	/// remain in the playlist; the shared document is embedded once.
	public static func bundle(
		from snapshot: NativeWorkspaceSnapshot,
		playlistID: UUID,
		to output: URL,
		replace: Bool = false,
		targetVersion: ProPresenterTargetVersion = .v22,
	) throws -> NativePlaylistExportResult {
		let root = snapshot.root.resolvingSymlinksInPath().standardizedFileURL.path
		let destination = output.resolvingSymlinksInPath().standardizedFileURL
		guard destination.path != root, !destination.path.hasPrefix(root + "/"), !root.hasPrefix(destination.path == "/" ? "/" : destination.path + "/") else {
			throw DocumentArchiveError.unsafeWorkspaceEntry(output.path)
		}
		try WorkspaceInspector.requireLegacyAccess(at: destination)
		let streams = snapshot.streams.filter { $0.identity.kind == "PlaylistLibrary" && $0.identity.scope == .shared }
		guard streams.count == 1, let shared = streams.first else { throw NativeSemanticError.invalidValue(path: "/PlaylistLibrary", expected: "one shared library playlist stream") }
		let client = snapshot.streams.first { $0.identity.documentID == shared.identity.documentID && $0.identity.scope == .client }
		var document = try NativePlaylistProjection(shared: shared, client: client).document
		func find(_ node: Rv_Data_Playlist) -> Rv_Data_Playlist? {
			if UUID(uuidString: node.uuid.string) == playlistID {
				return node
			}
			return node.playlists.playlists.lazy.compactMap(find).first
		}
		guard var selected = find(document.rootNode) else { throw NativeSemanticError.missingReference(path: "/playlists", identity: playlistID.uuidString) }
		let selectedFields = try ProtobufJSONPatcher.WireField.parse(selected.serializedData())
		guard case .items? = selected.childrenType, selected.linkData == nil,
		      !selectedFields.contains(where: { $0.number == 17 })
		else { throw unsupported("connected-playlist", path: "/playlists/\(playlistID)", target: targetVersion, message: "Portable native export currently requires a standard playlist without a smart-directory, Planning Center or provider connection.") }
		let resolver = try NativeWorkspaceReferenceResolver(streams: snapshot.streams)
		var presentations: [UUID: Rv_Data_Presentation] = [:]
		var dependencies: [NativePlaylistExportResult.Dependency] = []
		let schema = try ProtobufSchema.bundled(version: .v22)
		for index in selected.items.items.indices {
			var item = selected.items.items[index]
			let path = "/playlists/\(playlistID)/items[index=\(index)]"
			switch item.itemType {
			case let .header(header):
				guard header.actions.isEmpty else { throw unsupported("header-actions", path: path, target: targetVersion, message: "Header action dependencies require a qualified native export adapter.") }
			case let .presentation(link):
				let url = link.documentPath
				let nativeURL: NativeWorkspaceValue = .map(["RelativeFilePath": .map(["__tag": .string("local"), "local": .map(["root": .integer(Int64(url.local.root.rawValue)), "path": .string(url.local.path)])])])
				let reference = try resolver.presentation(nativeURL)
				guard let id = reference.documentID, let source = snapshot.streams.first(where: { $0.identity.documentID == id && $0.identity.scope == .shared && $0.identity.kind == "Presentation" }) else {
					throw NativeSemanticError.missingReference(path: path, identity: reference.logicalPath ?? url.renderPath)
				}
				if presentations[id] == nil {
					let projection = try source.protobufProjection()
					let presentation = try projection.presentation()
					guard try MediaReference.collect(protobuf: projection.protobuf, messageType: projection.messageType).isEmpty else {
						throw unsupported("native-media-dependency", path: path, target: targetVersion, message: "Native media asset-store resolution and portable locator rebasing remain unqualified.")
					}
					guard try !containsProvider(projection.protobuf, message: projection.messageType, schema: schema) else {
						throw unsupported("provider-linked-content", path: path, target: targetVersion, message: "Provider refresh ownership is not qualified for this portable export.")
					}
					guard presentation.cues.allSatisfy({ $0.actions.allSatisfy { $0.type == .presentationSlide } }) else {
						throw unsupported("native-action-dependencies", path: path, target: targetVersion, message: "Portable native playlist export currently supports Presentation slide actions; other action dependencies require their adapters.")
					}
					presentations[id] = presentation
					let name = URL(fileURLWithPath: source.identity.corePath ?? presentation.name).lastPathComponent
					dependencies.append(.init(documentID: id, archivePath: "Presentations/\(id.uuidString.lowercased())/\(name).pro"))
				}
				if link.hasArrangement, !link.arrangement.string.isEmpty {
					guard let arrangement = UUID(uuidString: link.arrangement.string), presentations[id]?.arrangements.count(where: { UUID(uuidString: $0.uuid.string) == arrangement }) == 1 else {
						throw NativeSemanticError.missingReference(path: "\(path)/arrangement", identity: link.arrangement.string)
					}
				}
				guard let name = dependencies.first(where: { $0.documentID == id })?.archivePath else { preconditionFailure("Prepared dependency is missing") }
				var portable = url
				portable.relativePath = name
				portable.local.root = .currentResource
				portable.local.path = name
				item.presentation.documentPath = portable
			default: throw unsupported("native-playlist-item", path: path, target: targetVersion, message: "Portable native export currently supports headers and direct Presentation items; linked wrappers and cue items require their adapters.")
			}
			selected.items.items[index] = item
		}
		document.rootNode.playlists.playlists = [selected]
		document.clearLiveVideoPlaylist()
		document.clearDownloadsPlaylist()
		let usedTags = Set(selected.items.items.flatMap(\.tags).map { $0.string.lowercased() })
		document.tags = document.tags.filter { usedTags.contains($0.uuid.string.lowercased()) }
		guard Set(document.tags.map { $0.uuid.string.lowercased() }) == usedTags else {
			throw NativeSemanticError.missingReference(path: "/tags", identity: "selected playlist tag definition")
		}
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProCRUD-native-playlist-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
		defer { try? FileManager.default.removeItem(at: directory) }
		let dataURL = directory.appendingPathComponent("data")
		try DocumentWriter.writeRaw(.init(payload: .playlist(document), origin: .raw(dataURL)), to: dataURL, targetVersion: targetVersion)
		for dependency in dependencies {
			guard let presentation = presentations[dependency.documentID] else { preconditionFailure("Prepared dependency is missing") }
			let url = directory.appendingPathComponent(dependency.archivePath)
			try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try DocumentWriter.writeRaw(.init(payload: .presentation(presentation), origin: .raw(url)), to: url, targetVersion: targetVersion)
		}
		let result = try DocumentArchive.bundleWithReport(directory, to: destination, replace: replace, targetVersion: targetVersion)
		return .init(path: result.archiveURL.path, workspaceID: snapshot.workspaceID, playlistID: playlistID, dependencies: dependencies, compatibility: result.compatibility, warnings: result.warnings)
	}

	private static func containsProvider(_ data: Data, message: String, schema: ProtobufSchema) throws -> Bool {
		if message == "rv.data.ProviderInfo" {
			return true
		}
		let descriptor = try schema.message(named: message)
		let wire = try MediaWireMessage(data)
		for field in descriptor.fields where field.isMessage {
			guard let type = field.typeName else { continue }
			let siblings = Set(descriptor.fields.filter { field.oneof != nil && $0.oneof == field.oneof }.map(\.number))
			if !siblings.isEmpty, wire.fields.last(where: { siblings.contains($0.number) })?.number != field.number {
				continue
			}
			for payload in wire.payloads(field.number, oneofFields: siblings) {
				if try containsProvider(payload, message: type, schema: schema) {
					return true
				}
			}
		}
		return false
	}

	private static func unsupported(_ feature: String, path: String, target: ProPresenterTargetVersion, message: String) -> DocumentCompatibilityError {
		.init(report: .init(profile: .init(targetVersion: target), sourceApplicationMajorVersion: nil, issues: [
			.init(feature: feature, componentPath: path, sourceApplicationMajorVersion: nil, targetVersion: target, severity: .error, availableConversion: "unsupported", message: message),
		]))
	}
}
