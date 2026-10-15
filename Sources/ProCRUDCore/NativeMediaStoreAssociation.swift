import Foundation

public struct NativeMediaStoreAssociation: Encodable, Sendable {
	public enum Status: String, Encodable, Sendable {
		case matched
		case differentAsset = "different-asset-association"
		case noReference = "no-reference-model"
		case noAsset = "no-asset-model"
		case tombstoned
		case invalidIdentity = "invalid-document-identity"
	}

	public let documentID: UUID
	public let scope: NativeWorkspaceStream.Scope
	public let componentPath: String
	public let referenceID: String
	public let declaredAssetID: String?
	public let materializedAssetID: UUID?
	public let transformationID: UUID?
	public let storedAssetPath: String?
	public let nativeAvailability: String?
	public let status: Status

	static func inspect(_ occurrences: [NativeMediaInventory.Occurrence], in store: NativeMediaStoreSnapshot) -> [Self] {
		let references = Dictionary(uniqueKeysWithValues: store.references.map { ($0.id, $0) })
		let assets = Dictionary(uniqueKeysWithValues: store.assets.map { ($0.id, $0) })
		return occurrences.filter { $0.reference.dependencyKind == .file }.map { occurrence in
			let source = occurrence.reference
			let reference = UUID(uuidString: source.referenceID).flatMap { references[$0] }
			let asset = reference?.assetID.flatMap { assets[$0] }
			let status: Status
			if UUID(uuidString: source.referenceID) == nil || source.assetID.flatMap(UUID.init(uuidString:)) == nil {
				status = .invalidIdentity
			} else if reference == nil {
				status = .noReference
			} else if reference?.tombstoned == true {
				status = .tombstoned
			} else if asset == nil {
				status = .noAsset
			} else if reference?.assetID != source.assetID.flatMap(UUID.init(uuidString:)) {
				status = .differentAsset
			} else {
				status = .matched
			}
			return .init(documentID: occurrence.documentID, scope: occurrence.scope, componentPath: source.path, referenceID: source.referenceID, declaredAssetID: source.assetID,
			             materializedAssetID: reference?.assetID, transformationID: reference?.transformationID, storedAssetPath: asset?.storedPath, nativeAvailability: asset?.availability, status: status)
		}
	}
}
