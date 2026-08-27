import Foundation
import Testing

func fixtureURL(_ relativePath: String, sourceLocation: SourceLocation = #_sourceLocation) -> URL {
	let url = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent() // filename
		.deletingLastPathComponent() // TestHelpers
		.deletingLastPathComponent() // ProCRUDCoreTests
		.deletingLastPathComponent() // Tests
		.appendingPathComponent("Fixtures")
		.appendingPathComponent(relativePath)

	if !FileManager.default.fileExists(atPath: url.path) {
		Issue.record(
			"Missing \(url.path). Follow Fixtures/ProPresenter/README.md to regenerate the playlist and install ProPresenter-exported reference images.",
			sourceLocation: sourceLocation,
		)
	}

	return url
}

func repositoryURL(_ relativePath: String, sourceLocation: SourceLocation = #_sourceLocation) -> URL {
	let url = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent() // filename
		.deletingLastPathComponent() // TestHelpers
		.deletingLastPathComponent() // ProCRUDCoreTests
		.deletingLastPathComponent() // Tests
		.appendingPathComponent(relativePath)

	if !FileManager.default.fileExists(atPath: url.path) {
		Issue.record("Missing repository file: \(url.path)", sourceLocation: sourceLocation)
	}

	return url
}
