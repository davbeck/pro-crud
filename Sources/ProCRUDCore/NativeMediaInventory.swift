import Foundation

/// File availability is established from current document locators and regular
/// files, never from the derived MediaStore projection/thumbnail caches. This
/// does not assert membership in the native asset store or Cloud availability.
public struct NativeMediaInventory: Encodable, Sendable {
	public struct File: Codable, Sendable, Equatable {
		public let path: String
		public let byteCount: UInt64
		public let sha256: String?
	}

	public struct Occurrence: Codable, Sendable, Equatable {
		public enum State: String, Codable, Sendable { case availableFiles = "available-files", unresolvedFiles = "unresolved-files", liveDevice = "live-device", remoteSource = "remote-source", webContent = "web-content", unqualified }
		public let documentID: UUID
		public let scope: NativeWorkspaceStream.Scope
		public let reference: MediaReference
		public let files: [File]
		public let diagnostics: [String]
		public let localFilesAvailable: Bool
		public let state: State

		init(documentID: UUID, scope: NativeWorkspaceStream.Scope, reference: MediaReference, files: [File], diagnostics: [String]) {
			self.documentID = documentID
			self.scope = scope
			self.reference = reference
			self.files = files
			self.diagnostics = diagnostics
			localFilesAvailable = !files.isEmpty && diagnostics.isEmpty
			switch reference.dependencyKind {
			case .file: state = localFilesAvailable ? .availableFiles : .unresolvedFiles
			case .liveDevice: state = .liveDevice
			case .remoteStream, .remoteResource: state = .remoteSource
			case .webContent: state = .webContent
			case .unknown: state = .unqualified
			}
		}
	}

	public struct Uninspected: Codable, Sendable, Equatable {
		public let identity: NativeWorkspaceStream.Identity
		public let reason: String
	}

	public let workspaceID: UUID
	public let occurrences: [Occurrence]
	public let uninspected: [Uninspected]
	public let assetStoreMembership = "unverified"
	public let runtimeSourceAvailability = "unverified"

	public init(snapshot: NativeWorkspaceSnapshot, hashFiles: Bool = false) throws {
		workspaceID = snapshot.workspaceID
		let deadline = ArchiveDeadline(timeout: .seconds(30))
		var occurrences: [Occurrence] = []
		var uninspected: [Uninspected] = []
		var fileCache: [URL: File] = [:]
		for stream in snapshot.streams {
			guard Self.supports(stream.identity) else {
				uninspected.append(.init(identity: stream.identity, reason: "Media traversal for this stream kind/scope is not implemented."))
				continue
			}
			guard stream.identity.availability == .available else {
				uninspected.append(.init(identity: stream.identity, reason: "Content unavailable locally; dependencies cannot be enumerated."))
				continue
			}
			do {
				for reference in try stream.mediaReferences() {
					var files: [File] = []
					var diagnostics = Self.identityDiagnostics(reference)
					if reference.activeLocators.isEmpty, reference.dependencyKind == .file {
						diagnostics.append("No file locator in the document occurrence.")
					}
					if reference.activeLocators.isEmpty, [.remoteStream, .webContent].contains(reference.dependencyKind) {
						diagnostics.append("No URL in the stored runtime source.")
					}
					for locator in reference.activeLocators where reference.dependencyKind == .file {
						do {
							let url = try Self.resolve(locator, workspaceRoot: snapshot.root)
							let file: File
							if let cached = fileCache[url] {
								file = cached
							} else {
								let count = try ArchiveFileIO.snapshot(of: url).size
								let hash = try hashFiles ? ArchiveFileIO.sha256(of: url, deadline: deadline) : nil
								file = File(path: url.path, byteCount: count, sha256: hash)
								fileCache[url] = file
							}
							if !files.contains(file) {
								files.append(file)
							}
						} catch {
							diagnostics.append("\(locator.field): \(error)")
						}
					}
					if Set(files.compactMap(\.sha256)).count > 1 {
						diagnostics.append("Occurrence locators resolve to different file contents.")
					}
					occurrences.append(.init(documentID: stream.identity.documentID, scope: stream.identity.scope, reference: reference, files: files, diagnostics: diagnostics))
				}
			} catch {
				uninspected.append(.init(identity: stream.identity, reason: String(describing: error)))
			}
		}
		// A shared asset may have several paths, but differing contents cannot
		// establish a coherent asset association. Reference IDs remain per-use.
		let groups = Dictionary(grouping: occurrences.indices, by: { occurrences[$0].reference.assetID?.lowercased() })
		for (id, indices) in groups where id != nil {
			guard Set(indices.flatMap { occurrences[$0].files.compactMap(\.sha256) }).count > 1 else { continue }
			for index in indices {
				let occurrence = occurrences[index]
				occurrences[index] = .init(documentID: occurrence.documentID, scope: occurrence.scope, reference: occurrence.reference, files: occurrence.files,
				                           diagnostics: occurrence.diagnostics + ["Shared asset ID resolves to different file contents across occurrences."])
			}
		}
		self.occurrences = occurrences
		self.uninspected = uninspected
	}

	private static func supports(_ identity: NativeWorkspaceStream.Identity) -> Bool {
		["PlaylistLibrary", "PlaylistMedia", "PlaylistAudio"].contains(identity.kind) ||
			(identity.scope == .shared && ["Presentation", "Theme"].contains(identity.kind)) ||
			NativeConfigurationAdapter.message(for: identity) != nil
	}

	private static func identityDiagnostics(_ reference: MediaReference) -> [String] {
		var issues: [String] = []
		if reference.identitySchemaVersion != "1" {
			issues.append("Unqualified native media identity schema: \(reference.identitySchemaVersion ?? "absent").")
		}
		if UUID(uuidString: reference.referenceID) == nil {
			issues.append("Invalid occurrence reference UUID.")
		}
		if reference.dependencyKind == .file || reference.assetID != nil, reference.assetID.flatMap(UUID.init(uuidString:)) == nil {
			issues.append("Missing or invalid native asset UUID.")
		}
		if reference.hasProvider {
			issues.append("Provider association is preserved; local provider availability is unqualified.")
		}
		return issues
	}

	static func resolve(_ locator: MediaReference.Locator, workspaceRoot: URL) throws -> URL {
		if locator.remote != nil {
			throw NativeSemanticError.unsupportedNode(path: locator.field, kind: "remote/live source; not a missing local file")
		}
		let candidate: URL
		if let path = locator.localPath {
			guard locator.localRoot == 10 else { throw NativeSemanticError.unsupportedNode(path: locator.field, kind: "relative root \(locator.localRoot.map(String.init) ?? "absent") needs its explicit resource/volume context") }
			candidate = try contained(path, root: workspaceRoot)
		} else if let path = locator.relative {
			candidate = try contained(path, root: workspaceRoot)
		} else if let string = locator.absolute {
			if string.hasPrefix("/") {
				candidate = URL(fileURLWithPath: string)
			} else if let url = URL(string: string), url.isFileURL {
				candidate = url
			} else {
				throw NativeSemanticError.unsupportedNode(path: locator.field, kind: "remote/non-file source; not a missing local file")
			}
		} else {
			throw NativeSemanticError.invalidValue(path: locator.field, expected: "materialized file locator")
		}
		_ = try ArchiveFileIO.snapshot(of: candidate)
		return candidate.standardizedFileURL
	}

	private static func contained(_ path: String, root: URL) throws -> URL {
		guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
			throw NativeSemanticError.invalidValue(path: path, expected: "contained relative file path")
		}
		let candidate = root.appendingPathComponent(path)
		let resolvedRoot = root.resolvingSymlinksInPath().path + "/"
		guard candidate.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) else { throw NativeSemanticError.invalidValue(path: path, expected: "file inside selected workspace") }
		return candidate
	}
}

public extension NativeWorkspaceStream {
	/// Enumerates media in supported shared document graphs and playlist trees.
	/// Client playlist state is inspected independently; it is never merged into
	/// a shared tree or treated as an alternate source of content.
	func mediaReferences() throws -> [MediaReference] {
		if supportsProtobufProjection, !(["PlaylistLibrary", "PlaylistMedia", "PlaylistAudio"].contains(identity.kind) && identity.scope == .shared) {
			let projection = try protobufProjection()
			try projection.requireComplete()
			return try MediaReference.collect(protobuf: projection.protobuf, messageType: projection.messageType)
		}
		guard ["PlaylistLibrary", "PlaylistMedia", "PlaylistAudio"].contains(identity.kind) else {
			throw NativeSemanticError.unsupportedNode(path: identity.documentID.uuidString, kind: "media traversal of \(identity.kind)/\(identity.scope)")
		}
		let value = try decodedValue().object(at: "/").required("root", at: "/")
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		if identity.scope == .client {
			let data = try encoder.encode(value, message: "rv.data.PlaylistLocalDocument", path: "/root")
			guard encoder.issues.isEmpty else { throw NativeProjectionError(issues: encoder.issues) }
			return try MediaReference.collect(protobuf: data, messageType: "rv.data.PlaylistLocalDocument")
		}
		_ = try NativePlaylistLayout(root: value)
		var root = try value.object(at: "/root")
		let trees = try ["playlists", "live_video_playlist_nodes"].map { name in
			try (name, NativePlacementNode.read(root.required(name, at: "/root"), path: "/root/\(name)"))
		}
		root.removeValue(forKey: "playlists")
		root.removeValue(forKey: "live_video_playlist_nodes")
		let data = try encoder.encode(.map(root), message: "rv.data.PlaylistDocument", path: "/root")
		var references = try MediaReference.collect(protobuf: data, messageType: "rv.data.PlaylistDocument")
		func collect(_ nodes: [NativePlacementNode], tree: String, encoder: inout NativeProtobufEncoder) throws -> [MediaReference] {
			var result: [MediaReference] = []
			for node in nodes {
				let path = "/root/\(tree)[node_id=\(node.nodeID)]"
				let data = try encoder.encode(node.metadata, message: "rv.data.PlaylistNode", path: path)
				try result.append(contentsOf: MediaReference.collect(protobuf: data, messageType: "rv.data.PlaylistNode", rootPath: path))
				try result.append(contentsOf: collect(node.children, tree: tree, encoder: &encoder))
			}
			return result
		}
		for (name, nodes) in trees {
			try references.append(contentsOf: collect(nodes, tree: name, encoder: &encoder))
		}
		guard encoder.issues.isEmpty else { throw NativeProjectionError(issues: encoder.issues) }
		return references
	}
}

/// Read-only encoding of independently scoped native configuration roots.
/// This does not export or reconstruct the Workspace/configuration documents.
enum NativeConfigurationAdapter {
	static func message(for identity: NativeWorkspaceStream.Identity) -> String? {
		switch (identity.kind, identity.scope) {
		case ("Workspace", .shared): "rv.data.ProPresenterWorkspace"
		case ("Workspace", .client): "rv.data.ProPresenterLocalWorkspace"
		case ("PlaylistTemplates", .shared): "rv.data.PlaylistTemplate"
		case ("Macros", .shared): "rv.data.MacrosDocument"
		case ("Props", .shared): "rv.data.PropDocument"
		case ("Stage", .shared): "rv.data.Stage.Document"
		case ("Messages", .shared): "rv.data.MessageDocument"
		case ("Messages", .client): "rv.data.MessageLocalDocument"
		case ("Calendar", .shared): "rv.data.Calendar"
		case ("Ccli", .shared): "rv.data.CCLIDocument"
		case ("ClearGroups", .shared): "rv.data.ClearGroupsDocument"
		case ("CommunicationDevices", .shared): "rv.data.ProPresenterCommunications"
		case ("CommunicationDevices", .client): "rv.data.ProPresenterLocalCommunications"
		case ("Groups", .shared): "rv.data.ProGroupsDocument"
		case ("KeyMappings", .shared): "rv.data.KeyMappingDocument"
		case ("Labels", .shared): "rv.data.ProLabelsDocument"
		case ("LibraryData", .shared): "rv.data.LibraryTreeDocument"
		case ("TestPatterns", .shared), ("TestPatterns", .client): "rv.data.TestPatternDocument"
		case ("Timers", .shared): "rv.data.TimersDocument"
		case ("Timers", .client): "rv.data.TimersLocalDocument"
		case ("PlaylistLibrary", .client), ("PlaylistMedia", .client), ("PlaylistAudio", .client): "rv.data.PlaylistLocalDocument"
		default: nil
		}
	}

	static func workspace(_ value: NativeWorkspaceValue) throws -> NativeWorkspaceValue {
		var root = try value.object(at: "/root")
		let field = "bundled_theme_rollout_sequence"
		var maximum = try root.optional(field)?.int(at: "/root/\(field)") ?? 0
		guard UInt32(exactly: maximum) != nil else { throw NativeSemanticError.invalidValue(path: "/root/\(field)", expected: "unsigned 32-bit completed rollout marker") }
		// The pinned native descriptor documents the exported high-water mark:
		// Core retains monotonic versioned markers and projects their maximum.
		for key in root.keys.sorted() where key.hasPrefix(field + "__version_") {
			let suffix = key.dropFirst((field + "__version_").count)
			guard UInt32(suffix) != nil else { continue } // Unknown keys remain visible to the descriptor gate.
			let marker = try root.required(key, at: "/root").int(at: "/root/\(key)")
			guard UInt32(exactly: marker) != nil else { throw NativeSemanticError.invalidValue(path: "/root/\(key)", expected: "unsigned 32-bit completed rollout marker") }
			maximum = max(maximum, marker)
			root.removeValue(forKey: key)
		}
		if root[field] != nil || maximum > 0 {
			root[field] = .integer(Int64(maximum))
		}
		return .map(root)
	}
}
