import Foundation
import Testing
@testable import ProCRUDCore

struct BundledProtobufSchemaTests {
	@Test
	func bundlesTheCanonicalDescriptorSet() throws {
		let packageRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let canonicalSchema = packageRoot
			.appendingPathComponent("Sources/ProCRUDCore/Resources/Protobuf/schema.pb")

		#expect(try BundledProtobufSchema.data() == Data(contentsOf: canonicalSchema))
	}

	@Test
	func coreBundleContainsOnlyTheDescriptorSet() throws {
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

		#expect(resourceRoot.lastPathComponent == "ProCRUD_ProCRUDCore.bundle")
		#expect(regularFilePaths.sorted() == ["Protobuf/schema.pb"])
	}
}
