import CryptoKit
import Foundation
import Loro

public enum NativeMetadataEdit: Codable, Sendable, Equatable {
	case presentationName(String)
	case notes(String)
	case copyrightTitle(String)
}

/// Prepared operations on an imported native history, not a rebuilt JSON map.
/// Preparing a patch never writes SQLite or requires a running application.
public struct NativeLocalPatch: Sendable {
	public let operationID: UUID
	public let identity: NativeWorkspaceStream.Identity
	public let originalSnapshot: Data
	public let originalVersionVector: Data
	public let snapshot: Data
	public let versionVector: Data
	public let update: Data
	public let payloadFingerprint: Data
	public let sha256: Data
	public let timestampMilliseconds: Int64

	public static func prepare(stream: NativeWorkspaceStream, edit: NativeMetadataEdit, operationID: UUID = UUID(), date: Date = Date()) throws -> Self? {
		guard stream.identity.kind == "Presentation", stream.identity.scope == .shared else {
			throw NativeSemanticError.invalidValue(path: stream.identity.documentID.uuidString, expected: "shared Presentation stream")
		}
		_ = try stream.presentationLayout()
		guard let original = stream.snapshot, let vector = stream.versionVector else { throw NativeWorkspaceError.unavailableStream(stream.identity.documentID.uuidString) }
		let document = LoroDoc()
		_ = try document.import(bytes: original)
		let originalVersion = try VersionVector.decode(bytes: vector)
		let root = document.getMap(id: "root")
		switch edit {
		case let .presentationName(name):
			guard !name.isEmpty else { throw NativeSemanticError.invalidValue(path: "/root/name", expected: "nonempty presentation name") }
			try root.insert(key: "name", v: name)
		case let .notes(notes): try root.insert(key: "notes", v: notes)
		case let .copyrightTitle(title):
			guard let ccli = root.get(key: "ccli")?.asLoroMap() else { throw NativeSemanticError.invalidValue(path: "/root/ccli", expected: "existing native CCLI map") }
			try ccli.insert(key: "song_title", v: title)
		}
		let timestamp = Int64(date.timeIntervalSince1970 * 1000)
		guard timestamp >= 0 else { throw NativeSemanticError.invalidValue(path: "/commit/timestamp", expected: "nonnegative timestamp") }
		document.commitWith(options: .init(origin: "pro-crud", immediateRenew: true, timestamp: timestamp / 1000, commitMsg: nil))
		guard !document.oplogVv().eq(other: originalVersion) else { return nil }
		let update = try document.exportUpdates(vv: originalVersion)
		let snapshot = try document.exportSnapshot()
		let version = document.oplogVv().encode()
		return .init(operationID: operationID, identity: stream.identity, originalSnapshot: original, originalVersionVector: vector,
		             snapshot: snapshot, versionVector: version, update: update, payloadFingerprint: Data(SHA256.hash(data: update)),
		             sha256: Data(SHA256.hash(data: snapshot)), timestampMilliseconds: timestamp)
	}
}
