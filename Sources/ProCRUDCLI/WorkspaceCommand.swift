import ArgumentParser
import Foundation
import ProCRUDCore

struct WorkspaceCommand: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "workspace", abstract: "Inspect, export, and apply supported local edits to an explicitly selected ProPresenter workspace.",
		subcommands: [WorkspaceInspect.self, WorkspaceInventory.self, WorkspaceContents.self, WorkspaceConfiguration.self, WorkspaceMedia.self, WorkspaceExport.self, WorkspaceExportPlaylist.self, WorkspaceSetCopyrightTitle.self, WorkspaceSetSlideNotes.self, WorkspaceDump.self, WorkspaceDiscover.self],
	)
}

struct WorkspaceSetSlideNotes: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "set-slide-notes", abstract: "Set native local Slide Notes by exact slide-action UUID. Quit ProPresenter and stop workspace helpers first.")
	@Argument(help: "Exact registered local native workspace root.") var input: String
	@Option(help: "Shared Presentation stream UUID.") var stream: String
	@Option(help: "Exact Presentation slide-action UUID from workspace export/dump.") var action: String
	@Option(help: "Exact local registry-v1.sqlite3 path.") var registry: String
	@Option(help: "Replacement plain text; retains the first existing character's formatting. Empty text clears notes.") var text: String?
	@Option(help: "RTF file containing the complete replacement notes, including formatting.") var rtf: String?

	func validate() throws {
		guard UUID(uuidString: stream) != nil, UUID(uuidString: action) != nil else { throw ValidationError("--stream and --action require UUIDs.") }
		guard (text != nil) != (rtf != nil) else { throw ValidationError("Provide exactly one of --text or --rtf.") }
	}

	func run() throws {
		guard let streamID = UUID(uuidString: stream), let actionID = UUID(uuidString: action) else { throw ValidationError("--stream and --action require UUIDs.") }
		let content: NativeSlideNotesContent
		if let text {
			content = .text(text)
		} else if let rtf {
			content = try .rtf(Data(contentsOf: URL(fileURLWithPath: rtf)))
		} else {
			throw ValidationError("Provide --text or --rtf.")
		}
		let receipts = try NativeLocalWorkspaceWriter.edit(.slideNotes(actionID: actionID, content: content), documentID: streamID, in: URL(fileURLWithPath: input), registry: URL(fileURLWithPath: registry))
		try print(prettyJSON(Result(documentID: streamID, actionID: actionID, changed: !receipts.isEmpty, receipts: receipts)))
	}

	private struct Result: Encodable {
		let documentID: UUID
		let actionID: UUID
		let changed: Bool
		let receipts: [NativeLocalCommitReceipt]
	}
}

struct WorkspaceExportPlaylist: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "export-playlist", abstract: "Export one standard native playlist with its media-free Presentation dependencies to a separate .proPlaylist archive.")
	@Argument(help: "Exact native workspace root.") var input: String
	@Option(help: "Exact standard playlist UUID from workspace contents; this is a tree node, not the PlaylistLibrary stream UUID.") var playlist: String
	@Option(help: "Separate .proPlaylist output path.") var output: String
	@OptionGroup var target: TargetVersionOptions
	@Flag(help: "Replace an existing archive atomically.") var replace = false

	func run() throws {
		guard let id = UUID(uuidString: playlist) else { throw ValidationError("--playlist requires a UUID.") }
		let snapshot = try NativeWorkspaceSnapshot.read(from: URL(fileURLWithPath: input))
		let result = try NativePlaylistExporter.bundle(from: snapshot, playlistID: id, to: URL(fileURLWithPath: output), replace: replace, targetVersion: target.targetVersion)
		try print(prettyJSON(result))
	}
}

struct WorkspaceSetCopyrightTitle: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-copyright-title",
		abstract: "Set a native local Presentation's CCLI song title atomically. Quit ProPresenter and stop its workspace helpers first.",
	)
	@Argument(help: "Exact registered local native workspace root.") var input: String
	@Option(help: "Exact shared Presentation stream UUID from workspace inventory.") var stream: String
	@Option(help: "Exact registry-v1.sqlite3 path containing this local workspace registration.") var registry: String
	@Option(help: "CCLI song title; an empty string clears the title.") var title: String

	func validate() throws {
		guard UUID(uuidString: stream) != nil else { throw ValidationError("--stream requires a UUID.") }
	}

	func run() throws {
		guard let id = UUID(uuidString: stream) else { throw ValidationError("--stream requires a UUID.") }
		let root = URL(fileURLWithPath: input).resolvingSymlinksInPath()
		let receipts = try NativeLocalWorkspaceWriter.edit(.copyrightTitle(title), documentID: id, in: root, registry: URL(fileURLWithPath: registry))
		try print(prettyJSON(Result(root: root.path, documentID: id, changed: receipts.contains { !$0.alreadyApplied }, receipts: receipts)))
	}

	private struct Result: Encodable {
		let root: String
		let documentID: UUID
		let changed: Bool
		let receipts: [NativeLocalCommitReceipt]
	}
}

struct WorkspaceConfiguration: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "configuration", abstract: "Inspect native saved/live Looks and shared/client screen definitions without merging unrelated settings.")
	@Argument(help: "Exact native workspace root.") var input: String

	func run() throws {
		let snapshot = try NativeWorkspaceSnapshot.read(from: URL(fileURLWithPath: input))
		try print(prettyJSON(NativeWorkspaceConfiguration(snapshot: snapshot)))
	}
}

struct WorkspaceMedia: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "media", abstract: "Inspect native Presentation/Theme and playlist-tree media identities and local file availability; report uninspected streams explicitly.")
	@Argument(help: "Exact native workspace root.") var input: String
	@Flag(help: "Hash regular files to check locator and shared-asset content agreement (30-second total hashing budget).") var hashFiles = false

	func run() throws {
		let snapshot = try NativeWorkspaceSnapshot.read(from: URL(fileURLWithPath: input))
		try print(prettyJSON(NativeMediaInventory(snapshot: snapshot, hashFiles: hashFiles)))
	}
}

struct WorkspaceExport: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "export", abstract: "Export a supported native Presentation or Theme stream as protobuf interchange to a separate destination.")
	@Argument(help: "Exact native workspace root.") var input: String
	@Option(help: "Exact shared native document UUID.") var stream: String
	@Option(help: "Separate raw .pro or Theme output path. Native workspaces cannot be output destinations.") var output: String
	@OptionGroup var target: TargetVersionOptions
	@Flag(help: "Replace an existing output file atomically.") var replace = false

	func run() throws {
		guard let id = UUID(uuidString: stream) else { throw ValidationError("--stream requires a UUID.") }
		let snapshot = try NativeWorkspaceSnapshot.read(from: URL(fileURLWithPath: input))
		guard let source = snapshot.streams.first(where: { $0.identity.documentID == id && $0.identity.scope == .shared }) else { throw ValidationError("No shared native stream matches \(stream).") }
		let projection = try source.protobufProjection()
		let url = URL(fileURLWithPath: output)
		let document = try ProPresenterDocument(payload: projection.payload(), origin: .raw(url))
		let compatibility = try DocumentCompatibility.analyze(document, target: target.targetVersion)
		try DocumentWriter.writeRaw(document, to: url, replace: replace, targetVersion: target.targetVersion)
		try print(prettyJSON(Result(path: url.path, sourceDocumentID: id, compatibility: compatibility, retainedNativeMetadata: projection.retainedMetadataPaths)))
	}

	private struct Result: Encodable {
		let path: String
		let sourceDocumentID: UUID
		let compatibility: DocumentCompatibilityReport
		let retainedNativeMetadata: [String]
	}
}

struct WorkspaceContents: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "contents", abstract: "Resolve native libraries, presentation/group/arrangement order, and playlist trees from one consistent snapshot.")
	@Argument(help: "Exact native workspace root.") var input: String

	func run() throws {
		let snapshot = try NativeWorkspaceSnapshot.read(from: URL(fileURLWithPath: input))
		try print(prettyJSON(NativeWorkspaceContents(snapshot: snapshot)))
	}
}

struct WorkspaceInventory: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "inventory", abstract: "Read a consistent native SQLite inventory and verify snapshot checksums.")
	@Argument(help: "Exact native workspace root.") var input: String
	@Flag(help: "Also check native Presentation, Theme and playlist protobuf views and list unmapped fields. Playlist views do not export dependencies.") var projections = false

	func run() throws {
		let snapshot = try NativeWorkspaceSnapshot.read(from: URL(fileURLWithPath: input))
		try print(prettyJSON(NativeInventory(snapshot, includeProjections: projections)))
	}
}

private struct NativeInventory: Encodable {
	var root: String
	var workspaceID: UUID
	var storage = WorkspaceStorage.nativeLoro
	var schemaVersion = NativeWorkspaceSnapshot.schemaVersion
	var loroBindingVersion = NativeWorkspaceSnapshot.loroBindingVersion
	var streams: [NativeWorkspaceStream.Identity]
	var projections: [ProjectionStatus]?
	var unresolvedCapabilities = ["remaining-configuration-materialization", "native-document-write", "native-media-registry", "cloud-merge"]

	init(_ snapshot: NativeWorkspaceSnapshot, includeProjections: Bool) throws {
		root = snapshot.root.path
		workspaceID = snapshot.workspaceID
		streams = snapshot.streams.map(\.identity)
		if includeProjections {
			projections = try snapshot.streams.filter { $0.identity.scope == .shared && ["Presentation", "Theme", "PlaylistLibrary", "PlaylistMedia", "PlaylistAudio"].contains($0.identity.kind) }.map { stream in
				guard stream.identity.availability == .available else { return .init(documentID: stream.identity.documentID, issues: [], failure: "unavailable-local-content") }
				do {
					if stream.identity.kind.hasPrefix("Playlist") {
						let client = snapshot.streams.first { $0.identity.documentID == stream.identity.documentID && $0.identity.scope == .client }
						let projection = try NativePlaylistProjection(shared: stream, client: client)
						let issues = projection.unappliedClientNodeIDs.map { id in
							NativeProjectionIssue(path: "/client/root/node_states/\(id.uuidString)", message: "Client expansion state has no matching shared playlist/group; retained in the native source.")
						}
						return .init(documentID: stream.identity.documentID, issues: issues, failure: nil)
					}
					let projection = try stream.protobufProjection()
					return .init(documentID: stream.identity.documentID, issues: projection.issues, failure: nil)
				} catch let error as NativeProjectionError {
					return .init(documentID: stream.identity.documentID, issues: error.issues, failure: nil)
				} catch let error as NativeSemanticError {
					return .init(documentID: stream.identity.documentID, issues: [], failure: error.description)
				}
			}
		}
	}

	struct ProjectionStatus: Encodable {
		let documentID: UUID
		let issues: [NativeProjectionIssue]
		let failure: String?
	}
}

struct WorkspaceDump: ParsableCommand {
	enum Scope: String, ExpressibleByArgument {
		case shared, client
		var value: NativeWorkspaceStream.Scope {
			self == .shared ? .shared : .client
		}
	}

	static let configuration = CommandConfiguration(commandName: "dump", abstract: "Decode native Loro streams as typed diagnostic values; this is not an editable protobuf projection.")
	@Argument(help: "Exact native workspace root.") var input: String
	@Option(help: "One exact native stream UUID. Omit to dump all streams, including client state.") var stream: String?
	@Option(help: "Filter stream scope: shared or client.") var scope: Scope?

	func run() throws {
		let id: UUID?
		if let stream {
			guard let parsed = UUID(uuidString: stream) else { throw ValidationError("--stream requires a UUID.") }
			id = parsed
		} else {
			id = nil
		}
		let snapshot = try NativeWorkspaceSnapshot.read(from: URL(fileURLWithPath: input))
		let selected = snapshot.streams.filter { value in
			(id == nil || value.identity.documentID == id) && (scope == nil || value.identity.scope == scope?.value)
		}
		guard !selected.isEmpty else { throw ValidationError("No native streams match the requested identity and scope.") }
		let content = try selected.map { value in
			try NativeStreamContent(identity: value.identity, value: value.snapshot == nil ? nil : value.decodedValue(),
			                        diagnostic: value.snapshot == nil ? "unavailable-local-content" : nil)
		}
		try print(prettyJSON(content))
	}
}

private struct NativeStreamContent: Encodable {
	var identity: NativeWorkspaceStream.Identity
	var value: NativeWorkspaceValue?
	var diagnostic: String?
}

struct WorkspaceDiscover: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "discover", abstract: "Read registered workspace identities without selecting an active workspace.")
	@Option(help: "Exact registry-v1.sqlite3 path. Only workspace metadata is read.") var registry: String

	func run() throws {
		try print(prettyJSON(WorkspaceRegistry.read(from: URL(fileURLWithPath: registry))))
	}
}

struct WorkspaceInspect: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "inspect", abstract: "Report storage evidence and supported operations without selecting or migrating a workspace.")

	@Argument(help: "Exact workspace root. Retained legacy copies and native workspaces are independent.") var input: String

	func run() throws {
		let report = try WorkspaceInspector.inspect(URL(fileURLWithPath: input))
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		try print(String(decoding: encoder.encode(report), as: UTF8.self))
	}
}
