import Foundation

public struct NativePlaylistLayout: Codable, Sendable, Equatable {
	public struct Node: Codable, Sendable, Equatable {
		public enum Kind: String, Codable, Sendable { case group, playlist, item }
		public let id: UUID
		public let nodeID: String
		public let name: String
		public let kind: Kind
		public let attributes: NativeWorkspaceValue
		public let children: [Node]
	}

	public let type: Int
	public let playlists: [Node]
	public let liveVideoPlaylists: [Node]

	public init(root value: NativeWorkspaceValue) throws {
		let root = try value.object(at: "/root")
		type = try root.required("type", at: "/root").int(at: "/root/type")
		var seen: Set<UUID> = []
		playlists = try Self.nodes(NativePlacementNode.read(root.required("playlists", at: "/root"), path: "/root/playlists"), seen: &seen)
		liveVideoPlaylists = try Self.nodes(NativePlacementNode.read(root.required("live_video_playlist_nodes", at: "/root"), path: "/root/live_video_playlist_nodes"), seen: &seen)
		if root.optional("root_node") != nil || root.optional("live_video_playlist") != nil {
			throw NativeSemanticError.conflictingOrder(path: "/root/playlists")
		}
	}

	private static func nodes(_ placements: [NativePlacementNode], seen: inout Set<UUID>) throws -> [Node] {
		try placements.map { node in
			let path = "/tree/\(node.nodeID)"
			let meta = try node.metadata.object(at: path)
			let id = try meta.required("uuid", at: path).uuid(at: "\(path)/uuid")
			guard seen.insert(id).inserted else { throw NativeSemanticError.duplicateIdentity(path: path, identity: id.uuidString) }
			let tag = try meta.required("Kind", at: path).tagged(at: "\(path)/Kind")
			guard let kind = Node.Kind(rawValue: tag.tag), kind != .item || node.children.isEmpty else {
				throw NativeSemanticError.unsupportedNode(path: path, kind: tag.tag)
			}
			return try Node(id: id, nodeID: node.nodeID, name: meta.required("name", at: path).text(at: "\(path)/name"),
			                kind: kind, attributes: tag.value, children: nodes(node.children, seen: &seen))
		}
	}
}

public struct NativeWorkspaceContents: Encodable, Sendable {
	public struct Presentation: Encodable, Sendable {
		public let identity: NativeWorkspaceStream.Identity
		public let name: String
		public let groups: [NativePresentationLayout.CueGroup]
		public let arrangements: [NativePresentationLayout.Arrangement]
		public let selectedArrangementID: UUID?
		public let masterCueIDs: [UUID]
		public let unplacedCueIDs: [UUID]
	}

	public struct Playlist: Encodable, Sendable {
		public let identity: NativeWorkspaceStream.Identity
		public let layout: NativePlaylistLayout
	}

	public struct Reference: Codable, Sendable, Equatable {
		public let source: NativeWorkspaceValue
		public let logicalPath: String?
		public let documentID: UUID?
		public let availability: NativeWorkspaceStream.Availability?
	}

	public struct Library: Codable, Sendable, Equatable {
		public let sourceURL: NativeWorkspaceValue
		public let children: [Library]
		public let presentations: [Reference]
	}

	public struct Diagnostic: Codable, Sendable, Equatable {
		public let documentID: UUID
		public let scope: NativeWorkspaceStream.Scope
		public let kind: String
		public let message: String
	}

	public let workspaceID: UUID
	public let presentations: [Presentation]
	public let playlists: [Playlist]
	public let libraries: [Library]
	public let diagnostics: [Diagnostic]
	public let unmaterializedStreams: [NativeWorkspaceStream.Identity]

	public init(snapshot: NativeWorkspaceSnapshot) throws {
		workspaceID = snapshot.workspaceID
		var presentations: [Presentation] = []
		var playlists: [Playlist] = []
		var libraries: [Library] = []
		var diagnostics: [Diagnostic] = []
		var unmaterialized: [NativeWorkspaceStream.Identity] = []
		let resolver = try NativeWorkspaceReferenceResolver(streams: snapshot.streams)
		for stream in snapshot.streams {
			guard stream.identity.scope == .shared else { unmaterialized.append(stream.identity); continue }
			guard stream.identity.availability == .available else {
				diagnostics.append(.init(documentID: stream.identity.documentID, scope: stream.identity.scope, kind: stream.identity.kind, message: "Content unavailable locally."))
				unmaterialized.append(stream.identity)
				continue
			}
			do {
				switch stream.identity.kind {
				case "Presentation":
					let layout = try stream.presentationLayout()
					try presentations.append(.init(identity: stream.identity, name: layout.name, groups: layout.groups, arrangements: layout.arrangements,
					                               selectedArrangementID: layout.selectedArrangementID, masterCueIDs: layout.orderedCueIDs(), unplacedCueIDs: layout.unplacedCueIDs))
				case "PlaylistLibrary", "PlaylistMedia", "PlaylistAudio":
					try playlists.append(.init(identity: stream.identity, layout: NativePlaylistLayout(root: stream.decodedValue().object(at: "/").required("root", at: "/"))))
				case "LibraryData":
					try libraries.append(Self.library(stream.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root").required("rootLibrary", at: "/root"), resolver: resolver, path: "/root/rootLibrary"))
				default: unmaterialized.append(stream.identity)
				}
			} catch let error as NativeSemanticError {
				diagnostics.append(.init(documentID: stream.identity.documentID, scope: stream.identity.scope, kind: stream.identity.kind, message: error.description))
				unmaterialized.append(stream.identity)
			}
		}
		self.presentations = presentations
		self.playlists = playlists
		self.libraries = libraries
		self.diagnostics = diagnostics
		unmaterializedStreams = unmaterialized
	}

	private static func library(_ value: NativeWorkspaceValue, resolver: NativeWorkspaceReferenceResolver, path: String) throws -> Library {
		let object = try value.object(at: path)
		let url = try object.required("url", at: path)
		let tag = try object.required("ChildType", at: path).tagged(at: "\(path)/ChildType")
		let content = try tag.value.object(at: path)
		switch tag.tag {
		case "libraryChildren":
			return try .init(sourceURL: url, children: content.required("libraries", at: path).array(at: path).enumerated().map {
				try library($0.element, resolver: resolver, path: "\(path)/libraries[\($0.offset)]")
			}, presentations: [])
		case "libraryItems":
			return try .init(sourceURL: url, children: [], presentations: content.required("items", at: path).array(at: path).map {
				try resolver.presentation($0.object(at: path).required("url", at: path))
			})
		default: throw NativeSemanticError.unsupportedNode(path: path, kind: tag.tag)
		}
	}
}

/// Native core paths are logical identities, not filesystem URLs. Resolve the
/// ROOT_SHOW-relative library link rather than a stale pre-migration absolute URL.
public struct NativeWorkspaceReferenceResolver: Sendable {
	private let presentations: [String: NativeWorkspaceStream.Identity]
	private let themes: [String: NativeWorkspaceStream.Identity]

	public init(streams: [NativeWorkspaceStream]) throws {
		func index(_ kind: String) throws -> [String: NativeWorkspaceStream.Identity] {
			var result: [String: NativeWorkspaceStream.Identity] = [:]
			for stream in streams where stream.identity.kind == kind && stream.identity.scope == .shared {
				guard let path = stream.identity.corePath else { continue }
				guard result.updateValue(stream.identity, forKey: path) == nil else { throw NativeSemanticError.duplicateIdentity(path: path, identity: "\(kind) core path") }
			}
			return result
		}
		presentations = try index("Presentation")
		themes = try index("Theme")
	}

	public func presentation(_ url: NativeWorkspaceValue) throws -> NativeWorkspaceContents.Reference {
		try resolve(url, prefix: "Libraries", suffix: ".pro", index: presentations)
	}

	public func theme(_ url: NativeWorkspaceValue) throws -> NativeWorkspaceContents.Reference {
		try resolve(url, prefix: "Themes", suffix: "", index: themes)
	}

	private func resolve(_ url: NativeWorkspaceValue, prefix: String, suffix: String, index: [String: NativeWorkspaceStream.Identity]) throws -> NativeWorkspaceContents.Reference {
		let object = try url.object(at: "/url")
		guard let relative = object.optional("RelativeFilePath"), case let .map(relativeObject) = relative,
		      relativeObject["__tag"] == .string("local"),
		      let local = relativeObject.optional("local"), case let .map(localObject) = local,
		      localObject["root"] == .integer(10), let path = localObject.optional("path")
		else { return .init(source: url, logicalPath: nil, documentID: nil, availability: nil) }
		let raw = try path.text(at: "/url/local/path")
		let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
		guard parts.first == Substring(prefix), parts.count > 1, !parts.contains(".."), !parts.contains("."), !parts.contains(""),
		      raw.hasSuffix(suffix), prefix != "Themes" || parts.last == "Theme"
		else {
			return .init(source: url, logicalPath: nil, documentID: nil, availability: nil)
		}
		let logical = String(raw.dropFirst(prefix.count + 1).dropLast(suffix.count))
		let stream = index[logical]
		return .init(source: url, logicalPath: logical, documentID: stream?.documentID, availability: stream?.availability)
	}
}
