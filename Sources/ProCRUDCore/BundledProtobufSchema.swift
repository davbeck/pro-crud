import Foundation

package enum BundledProtobufSchema {
	package static func baseline21() throws -> Data {
		guard let url = Bundle.module.url(forResource: "schema", withExtension: "pb", subdirectory: "Protobuf21") else {
			throw CocoaError(.fileNoSuchFile)
		}
		return try Data(contentsOf: url)
	}

	package static func data(version: ProPresenterTargetVersion = .v21) throws -> Data {
		guard let url = Bundle.module.url(
			forResource: "schema",
			withExtension: "pb",
			subdirectory: version == .v21 ? "Protobuf" : "Protobuf22",
		) else {
			throw CocoaError(.fileNoSuchFile)
		}
		return try Data(contentsOf: url)
	}
}
