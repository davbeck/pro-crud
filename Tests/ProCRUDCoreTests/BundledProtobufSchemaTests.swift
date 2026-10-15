import Foundation
import Testing
@testable import ProCRUDCore

struct BundledProtobufSchemaTests {
	@Test(arguments: [ProPresenterTargetVersion.v21, .v22])
	func bundlesTheCanonicalDescriptorSet(version: ProPresenterTargetVersion) throws {
		let packageRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let canonicalSchema = packageRoot
			.appendingPathComponent("Sources/ProCRUDCore/Resources/\(version == .v21 ? "Protobuf" : "Protobuf22")/schema.pb")

		#expect(try BundledProtobufSchema.data(version: version) == Data(contentsOf: canonicalSchema))
	}

	@Test
	func coreBundleContainsOnlyVersionedDescriptorSets() throws {
		let resourceRoot = try #require(Bundle.module.resourceURL)
		let fileManager = FileManager.default
		let enumerator = try #require(fileManager.enumerator(
			at: resourceRoot,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles],
		))
		var regularFilePaths: [String] = []
		for case let url as URL in enumerator {
			guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
				continue
			}
			regularFilePaths.append(String(url.path.dropFirst(resourceRoot.path.count + 1)))
		}

		#expect(regularFilePaths.sorted() == ["Protobuf/schema.pb", "Protobuf22/schema.pb"])
	}
}
