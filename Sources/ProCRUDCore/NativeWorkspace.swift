import CryptoKit
import CSQLite
import Foundation
import Loro

/// A diagnostic projection, deliberately separate from protobuf JSON. Binary
/// values retain their type and encode as base64 instead of numeric-key objects.
public indirect enum NativeWorkspaceValue: Codable, Sendable, Equatable {
	case null
	case boolean(Bool)
	case number(Double)
	case integer(Int64)
	case binary(Data)
	case string(String)
	case list([NativeWorkspaceValue])
	case map([String: NativeWorkspaceValue])

	init(_ value: LoroValue) throws {
		self = switch value {
		case .null: .null
		case let .bool(value): .boolean(value)
		case let .double(value): .number(value)
		case let .i64(value): .integer(value)
		case let .binary(value): .binary(value)
		case let .string(value): .string(value)
		case let .list(value): try .list(value.map(Self.init))
		case let .map(value): try .map(value.mapValues(Self.init))
		case .container: throw NativeWorkspaceError.invalidStream("Unresolved container in deep-value projection.")
		}
	}
}

public struct NativeWorkspaceStream: Sendable {
	public enum Scope: Int, Codable, Sendable { case shared = 0, client = 1 }
	public enum Availability: Int, Codable, Sendable { case available = 0, unavailable = 1 }

	public struct Identity: Codable, Sendable, Equatable {
		public var documentID: UUID
		public var scope: Scope
		public var kind: String
		public var corePath: String?
		public var availability: Availability
		public var byteCount: Int64
		public var sha256: String?
		public var updatedAtMilliseconds: Int64
	}

	public let identity: Identity
	/// Original history, retained independently from any diagnostic projection.
	public let snapshot: Data?
	public let versionVector: Data?
	public let lastSharedVersionVector: Data?

	public func decodedValue() throws -> NativeWorkspaceValue {
		guard let snapshot else { throw NativeWorkspaceError.unavailableStream(identity.documentID.uuidString) }
		let document = LoroDoc()
		let status = try document.import(bytes: snapshot)
		guard status.pending?.isEmpty != false else {
			throw NativeWorkspaceError.incompleteLoroImport(identity.documentID.uuidString)
		}
		guard let versionVector, try document.oplogVv().eq(other: VersionVector.decode(bytes: versionVector)) else {
			throw NativeWorkspaceError.invalidStream("Loro history and stored version vector disagree for \(identity.documentID).")
		}
		return try NativeWorkspaceValue(document.getDeepValue())
	}
}

public struct NativeWorkspaceSnapshot: Sendable {
	public static let schemaVersion: Int64 = 9
	public static let applicationID: Int64 = 1_381_390_163
	public static let loroBindingVersion = "1.13.3"

	public let root: URL
	public let workspaceID: UUID
	public let metadata: [String: String]
	public let streams: [NativeWorkspaceStream]

	public static func read(from root: URL) throws -> Self {
		let inspection = try WorkspaceInspector.inspect(root)
		guard inspection.storage == .nativeLoro, inspection.storageMarker == "sqlite-v1" else {
			throw NativeWorkspaceError.unsupportedStorage(inspection.storageMarker ?? "missing workspace-storage-v1")
		}
		guard let id = inspection.workspaceID.flatMap(UUID.init(uuidString:)) else {
			throw NativeWorkspaceError.database("Missing or invalid DocumentStore/workspace-id.")
		}
		let database = try WorkspaceDatabase(snapshotOf: root.appendingPathComponent("DocumentStore/workspace-v1.sqlite3"))
		let version = try database.integer("PRAGMA user_version")
		let application = try database.integer("PRAGMA application_id")
		guard version == schemaVersion, application == applicationID else {
			throw NativeWorkspaceError.unsupportedSchema(applicationID: application, version: version)
		}
		let metadataRows = try database.query("SELECT key, value FROM workspace_metadata ORDER BY key") { row in
			(WorkspaceDatabase.text(row, 0) ?? "", WorkspaceDatabase.text(row, 1) ?? "")
		}
		let streams = try database.query("""
		SELECT document_id, scope, kind, core_path, availability, snapshot,
		       version_vector, sha256, byte_count, updated_at_ms, last_shared_version_vector, location_type
		FROM workspace_streams ORDER BY kind, core_path, document_id, scope
		""", row: readStream)
		return Self(root: root.resolvingSymlinksInPath(), workspaceID: id, metadata: Dictionary(uniqueKeysWithValues: metadataRows), streams: streams)
	}

	private static func readStream(_ row: OpaquePointer) throws -> NativeWorkspaceStream {
		guard let idBytes = WorkspaceDatabase.data(row, 0), idBytes.count == 16,
		      let scope = NativeWorkspaceStream.Scope(rawValue: Int(sqlite3_column_int(row, 1))),
		      let kind = WorkspaceDatabase.text(row, 2), !kind.isEmpty,
		      let availability = NativeWorkspaceStream.Availability(rawValue: Int(sqlite3_column_int(row, 4)))
		else { throw NativeWorkspaceError.invalidStream("Missing identity, kind, scope, or availability.") }
		let hex = idBytes.map { String(format: "%02x", $0) }.joined()
		let uuidString = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
		guard let id = UUID(uuidString: uuidString) else { throw NativeWorkspaceError.invalidStream("Invalid document ID.") }
		let path = WorkspaceDatabase.text(row, 3)
		let snapshot = WorkspaceDatabase.data(row, 5)
		let vector = WorkspaceDatabase.data(row, 6)
		let hash = WorkspaceDatabase.data(row, 7)
		let count = sqlite3_column_int64(row, 8)
		let updated = sqlite3_column_int64(row, 9)
		let location = sqlite3_column_int(row, 11)
		guard updated >= 0, count >= 0,
		      (location == 0 && path == nil) || (location == 1 && scope == .shared && path?.isEmpty == false)
		else { throw NativeWorkspaceError.invalidStream("Invalid location or timestamp for \(id).") }
		switch availability {
		case .available:
			guard let snapshot, let vector, !vector.isEmpty, let hash,
			      snapshot.count == count, snapshot.starts(with: Data("loro".utf8)),
			      Data(SHA256.hash(data: snapshot)) == hash
			else { throw NativeWorkspaceError.invalidStream("Snapshot, version vector, byte count, or SHA-256 mismatch for \(id).") }
		case .unavailable:
			guard scope == .shared, location == 1, snapshot == nil, vector == nil, hash == nil, count == 0 else {
				throw NativeWorkspaceError.invalidStream("Unavailable stream \(id) has contradictory snapshot data.")
			}
		}
		return NativeWorkspaceStream(
			identity: .init(documentID: id, scope: scope, kind: kind, corePath: path, availability: availability,
			                byteCount: count, sha256: hash?.map { String(format: "%02x", $0) }.joined(), updatedAtMilliseconds: updated),
			snapshot: snapshot, versionVector: vector, lastSharedVersionVector: WorkspaceDatabase.data(row, 10),
		)
	}
}

public struct WorkspaceRegistryEntry: Codable, Sendable {
	public var localID: String
	public var root: String
	public var displayName: String
	public var cloudID: String?
	public var schemaVersion: String
	public var availability: String
	public var exists: Bool
}

public enum WorkspaceRegistry {
	/// Reads only the documented workspace metadata table, never accounts or
	/// credentials. Registry roots are reported verbatim, never auto-selected.
	public static func read(from url: URL) throws -> [WorkspaceRegistryEntry] {
		let database = try WorkspaceDatabase(snapshotOf: url)
		return try database.query("SELECT local_uuid, root_path, display_name, cloud_uuid, schema_version, availability FROM workspaces ORDER BY display_name, local_uuid") { row in
			guard let id = WorkspaceDatabase.text(row, 0), let root = WorkspaceDatabase.text(row, 1),
			      let name = WorkspaceDatabase.text(row, 2), let schema = WorkspaceDatabase.text(row, 4),
			      let availability = WorkspaceDatabase.text(row, 5)
			else { throw NativeWorkspaceError.database("Invalid workspace registry entry.") }
			return WorkspaceRegistryEntry(localID: id, root: root, displayName: name, cloudID: WorkspaceDatabase.text(row, 3),
			                              schemaVersion: schema, availability: availability, exists: FileManager.default.fileExists(atPath: root))
		}
	}
}
