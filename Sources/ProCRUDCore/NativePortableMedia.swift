import Foundation
import ProPresenterProto

enum NativePortableMedia {
	static func qualifies(_ data: Data, root: Int = 12) throws -> Bool {
		let reference = try MediaReference(media: Rv_Data_Media(serializedBytes: data))
		guard reference.identitySchemaVersion == "1", reference.dependencyKind == .file, reference.containerID == nil, !reference.hasProvider,
		      UUID(uuidString: reference.referenceID) != nil, reference.assetID.flatMap(UUID.init(uuidString:)) != nil,
		      let selected = reference.activeLocators.first, reference.activeLocators.count == 1, let path = selected.relative,
		      selected.localRoot == root, selected.localPath == path, path.hasPrefix("Media/")
		else { return false }
		try DocumentArchive.validateWorkspacePath(path, limits: .default)
		return reference.locators.allSatisfy { $0.relative == path && $0.localPath == path && $0.localRoot == root }
	}
}
