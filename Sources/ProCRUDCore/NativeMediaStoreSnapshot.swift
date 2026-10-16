import Foundation

/// A bounded, checksum-verified read of native schema-1 asset/reference models.
/// The document snapshot and MediaStore are captured independently; this does
/// not assert a transaction spanning both stores or qualify MediaStore writes.
public struct NativeMediaStoreSnapshot: Encodable, Sendable {
	public struct Asset: Codable, Sendable, Equatable {
		public let id: UUID
		public let storedPath: String?
		public let nativeChecksum: [UInt8]?
		public let availability: String
		public let purged: Bool
		public let mediaType: String?
		public let width: Int?
		public let height: Int?
	}

	public struct Reference: Codable, Sendable, Equatable {
		public let id: UUID
		public let assetID: UUID?
		public let transformationID: UUID?
		public let projectionOwned: Bool
		public let tombstoned: Bool
	}

	public let schemaVersion: Int
	public let sequence: UInt64
	public let fingerprint: String
	public let tableFiles: [String]
	public let logFiles: [String]
	public let verifiedTableBlocks: Int
	public let nativeModelCount: Int
	public let assets: [Asset]
	public let references: [Reference]
	public let uninspectedModelKinds: [String: Int]
	let rawModels: [String: Data]

	private enum CodingKeys: String, CodingKey {
		case schemaVersion, sequence, fingerprint, tableFiles, logFiles, verifiedTableBlocks, nativeModelCount, assets, references, uninspectedModelKinds
	}

	public static func read(at root: URL, limits: NativeMediaStoreReadLimits = .init()) throws -> Self {
		try .init(capture: MediaStoreCapture.read(at: root, limits: limits))
	}

	init(capture: MediaStoreCapture) throws {
		let decoder = JSONDecoder()
		guard let marker = capture.records["__rv_media_store_schema"]?.value else { throw NativeMediaStoreError.invalid("schema marker missing") }
		let schema = try decoder.decode(Schema.self, from: marker)
		guard schema.applicationID == "com.renewedvision.media-store", schema.version == 1 else { throw NativeMediaStoreError.unsupported("application/schema marker") }
		var assets: [UUID: Asset] = [:], references: [UUID: Reference] = [:], uninspected: [String: Int] = [:]
		let assetPrefix = "helper_workspaces::db::models::asset::Asset:"
		let referencePrefix = "v3_helper_workspaces::db::models::reference::Reference:"
		for (key, record) in capture.records {
			guard let value = record.value else { continue }
			if key == "__rv_media_store_schema" {
				continue
			}
			if key.hasPrefix(assetPrefix) {
				let row = try decoder.decode(AssetRow.self, from: value)
				let id = try Self.uuid(String(key.dropFirst(assetPrefix.count)))
				guard try id == (Self.uuid(row.key)), assets[id] == nil else { throw NativeMediaStoreError.invalid("asset key/identity mismatch or duplicate") }
				assets[id] = .init(id: id, storedPath: row.url, nativeChecksum: row.checksum, availability: row.availability, purged: row.purged, mediaType: row.mediaType, width: row.width, height: row.height)
			} else if key.hasPrefix(referencePrefix) {
				let row = try decoder.decode(ReferenceRow.self, from: value)
				let id = try Self.uuid(String(key.dropFirst(referencePrefix.count)))
				guard try id == (Self.uuid(row.key.uuid)), references[id] == nil else { throw NativeMediaStoreError.invalid("reference key/identity mismatch or duplicate") }
				references[id] = try .init(id: id, assetID: row.assetID.map(Self.uuid), transformationID: row.transformationID.map(Self.uuid), projectionOwned: row.projectionOwned, tombstoned: row.projectionTombstoned)
			} else {
				guard !key.contains("::asset::Asset:"), !key.contains("::reference::Reference:") else { throw NativeMediaStoreError.unsupported("asset/reference model namespace") }
				let kind = key.lastIndex(of: ":").map { String(key[..<$0]) } ?? key
				uninspected[kind, default: 0] += 1
			}
		}
		schemaVersion = schema.version; sequence = capture.sequence; fingerprint = capture.fingerprint
		tableFiles = capture.tableFiles; logFiles = capture.logFiles; verifiedTableBlocks = capture.verifiedTableBlocks
		nativeModelCount = capture.records.count
		self.assets = assets.values.sorted { $0.id.uuidString < $1.id.uuidString }
		self.references = references.values.sorted { $0.id.uuidString < $1.id.uuidString }
		uninspectedModelKinds = uninspected
		rawModels = capture.records.compactMapValues(\.value)
	}

	private static func uuid(_ value: String) throws -> UUID {
		guard let uuid = UUID(uuidString: value) else { throw NativeMediaStoreError.invalid("asset/reference model UUID") }
		return uuid
	}

	private struct Schema: Decodable {
		let applicationID: String
		let version: Int
		enum CodingKeys: String, CodingKey { case applicationID = "application_id", version }
	}

	private struct AssetRow: Decodable {
		let key: String
		let url: String?
		let checksum: [UInt8]?
		let availability: String
		let purged: Bool
		let mediaType: String?
		let width: Int?
		let height: Int?
		enum CodingKeys: String, CodingKey { case key, url, checksum, availability, purged, mediaType = "media_type", width, height }
	}

	private struct ReferenceRow: Decodable {
		struct Key: Decodable { let uuid: String }
		let key: Key
		let assetID: String?
		let transformationID: String?
		let projectionOwned: Bool
		let projectionTombstoned: Bool
		enum CodingKeys: String, CodingKey { case key, assetID = "asset_uuid", transformationID = "transformation_uuid", projectionOwned = "projection_owned", projectionTombstoned = "projection_tombstoned" }
	}
}
