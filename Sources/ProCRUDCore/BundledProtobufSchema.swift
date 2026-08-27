import Foundation

package enum BundledProtobufSchema {
	package static func data() throws -> Data {
		guard let url = Bundle.module.url(
			forResource: "schema",
			withExtension: "pb",
			subdirectory: "Protobuf",
		) else {
			throw CocoaError(.fileNoSuchFile)
		}
		return try Data(contentsOf: url)
	}
}
