import ArgumentParser
import Foundation
import ProCRUDCore

struct WorkspaceCommand: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "workspace", abstract: "Inspect explicitly selected ProPresenter workspace storage.",
		subcommands: [WorkspaceInspect.self, WorkspaceInventory.self, WorkspaceContents.self, WorkspaceExport.self, WorkspaceDump.self, WorkspaceDiscover.self],
	)
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
	@Flag(help: "Also check native Presentation/Theme interchange materialization and list unmapped fields.") var projections = false

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
			projections = try snapshot.streams.filter { $0.identity.scope == .shared && ["Presentation", "Theme"].contains($0.identity.kind) }.map { stream in
				guard stream.identity.availability == .available else { return .init(documentID: stream.identity.documentID, issues: [], failure: "unavailable-local-content") }
				do {
					let projection = try stream.protobufProjection()
					return .init(documentID: stream.identity.documentID, issues: projection.issues, failure: nil)
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
