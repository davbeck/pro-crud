import AppKit
import Foundation
import ProCRUDCore

private let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let fixturesDirectory = repositoryRoot.appendingPathComponent("Fixtures/ProPresenter", isDirectory: true)
private let referencePlaylistURL = fixturesDirectory.appendingPathComponent("ReferenceSlides.proPlaylist")
private let snapshotDirectory = repositoryRoot.appendingPathComponent("Tests/ProCRUDCoreTests/__Snapshots__/RenderingFixtureTests", isDirectory: true)
private let malformedBundleSnapshotDirectory = repositoryRoot.appendingPathComponent(
	"Tests/ProCRUDCoreTests/__Snapshots__/MalformedGeneratedBundleRenderingTests",
	isDirectory: true,
)
private let typographySnapshotDirectory = repositoryRoot.appendingPathComponent(
	"Tests/ProCRUDCoreTests/__Snapshots__/TypographyRenderingFixtureTests",
	isDirectory: true,
)
private let renderingEdgeCasesSnapshotDirectory = repositoryRoot.appendingPathComponent(
	"Tests/ProCRUDCoreTests/__Snapshots__/RenderingEdgeCasesFixtureTests",
	isDirectory: true,
)
private let fixtureCanvasSize = CGSize(width: 854, height: 480)
private let fullHDCanvasSize = CGSize(width: 1920, height: 1080)

@main
enum FixtureGenerator {
	static func main() throws {
		let arguments = Array(CommandLine.arguments.dropFirst())
		guard let command = arguments.first else { throw UsageError() }

		switch command {
		case "generate-design-system":
			let arguments = Array(arguments.dropFirst())
			guard arguments.isEmpty || arguments == ["--check"] else { throw UsageError() }
			try DesignSystemFixture.generate(
				in: repositoryRoot,
				check: arguments == ["--check"],
			)
		case "generate-malformed-bundle":
			let arguments = Array(arguments.dropFirst())
			guard arguments.isEmpty || arguments == ["--check"] else { throw UsageError() }
			try MalformedGeneratedBundleFixture.generate(
				in: fixturesDirectory,
				check: arguments == ["--check"],
			)
		case "generate-typography":
			let arguments = Array(arguments.dropFirst())
			guard arguments.isEmpty || arguments == ["--check"] else { throw UsageError() }
			try TypographyFixture.generate(
				in: fixturesDirectory,
				check: arguments == ["--check"],
			)
		case "generate-rendering-edge-cases":
			let arguments = Array(arguments.dropFirst())
			guard arguments.isEmpty || arguments == ["--check"] else { throw UsageError() }
			try RenderingEdgeCasesFixture.generate(
				in: fixturesDirectory,
				check: arguments == ["--check"],
			)
		case "install-references":
			try installReferences(arguments: Array(arguments.dropFirst()))
		case "install-malformed-bundle-references":
			try installMalformedBundleReferences(arguments: Array(arguments.dropFirst()))
		case "install-typography-references":
			try installTypographyReferences(arguments: Array(arguments.dropFirst()))
		case "install-rendering-edge-cases-references":
			try installRenderingEdgeCasesReferences(arguments: Array(arguments.dropFirst()))
		default:
			throw UsageError()
		}
	}

	private static func installReferences(arguments: [String]) throws {
		guard arguments.count == 3, arguments[0] == "--from", arguments[2] == "--replace" else { throw UsageError() }
		let exportDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
		let fileManager = FileManager.default
		try fileManager.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

		let presentations = try PresentationLoader.loadPresentations(from: referencePlaylistURL)
		var installations: [(source: URL, destination: URL)] = []
		for presentation in presentations {
			let areaName = areaName(for: presentation.sourceName)
			for (index, _) in presentation.document.orderedCues.enumerated() {
				let source = exportDirectory
					.appendingPathComponent(areaName, isDirectory: true)
					.appendingPathComponent("\(index + 1).png")
				guard fileManager.fileExists(atPath: source.path) else { throw FixtureError.missingExport(source) }
				let image = try requireImage(at: source)
				guard image.pixelSize == fixtureCanvasSize else {
					throw FixtureError.unexpectedImageSize(source, expected: fixtureCanvasSize, actual: image.pixelSize)
				}
				let destination = snapshotDirectory.appendingPathComponent(snapshotFilename(
					presentation: areaName,
					slideNumber: index + 1,
				))
				installations.append((source, destination))
			}
		}

		try removeExistingSnapshots(in: snapshotDirectory, fileManager: fileManager)
		for installation in installations {
			try fileManager.copyItem(at: installation.source, to: installation.destination)
			print("Installed \(installation.destination.path)")
		}
	}

	private static func installMalformedBundleReferences(arguments: [String]) throws {
		guard arguments.count == 3, arguments[0] == "--from", arguments[2] == "--replace" else { throw UsageError() }
		let exportDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
		let fileManager = FileManager.default
		try fileManager.createDirectory(at: malformedBundleSnapshotDirectory, withIntermediateDirectories: true)

		for slideNumber in 1 ... MalformedGeneratedBundleFixture.slideCount {
			let source = exportDirectory.appendingPathComponent("\(slideNumber).png")
			guard fileManager.fileExists(atPath: source.path) else { throw FixtureError.missingExport(source) }
			let image = try requireImage(at: source)
			guard image.pixelSize == fixtureCanvasSize else {
				throw FixtureError.unexpectedImageSize(source, expected: fixtureCanvasSize, actual: image.pixelSize)
			}
		}

		try removeExistingSnapshots(in: malformedBundleSnapshotDirectory, fileManager: fileManager)
		for slideNumber in 1 ... MalformedGeneratedBundleFixture.slideCount {
			let source = exportDirectory.appendingPathComponent("\(slideNumber).png")
			let destination = malformedBundleSnapshotDirectory.appendingPathComponent(
				"rendersMalformedGeneratedBundleSlide.slide-\(slideNumber).png",
			)
			try fileManager.copyItem(at: source, to: destination)
			print("Installed \(destination.path)")
		}
	}

	private static func installTypographyReferences(arguments: [String]) throws {
		guard arguments.count == 3, arguments[0] == "--from", arguments[2] == "--replace" else { throw UsageError() }
		let exportDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
		let fileManager = FileManager.default
		try fileManager.createDirectory(at: typographySnapshotDirectory, withIntermediateDirectories: true)

		for slideNumber in 1 ... TypographyFixture.slideCount {
			let source = exportDirectory.appendingPathComponent("\(slideNumber).png")
			guard fileManager.fileExists(atPath: source.path) else { throw FixtureError.missingExport(source) }
			let image = try requireImage(at: source)
			guard image.pixelSize == fixtureCanvasSize else {
				throw FixtureError.unexpectedImageSize(source, expected: fixtureCanvasSize, actual: image.pixelSize)
			}
		}

		try removeExistingSnapshots(in: typographySnapshotDirectory, fileManager: fileManager)
		for slideNumber in 1 ... TypographyFixture.slideCount {
			let source = exportDirectory.appendingPathComponent("\(slideNumber).png")
			let destination = typographySnapshotDirectory.appendingPathComponent(
				"rendersTypographySlide.slide-\(slideNumber).png",
			)
			try fileManager.copyItem(at: source, to: destination)
			print("Installed \(destination.path)")
		}
	}

	private static func installRenderingEdgeCasesReferences(arguments: [String]) throws {
		guard arguments.count == 3, arguments[0] == "--from", arguments[2] == "--replace" else { throw UsageError() }
		let exportDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
		let fileManager = FileManager.default
		try fileManager.createDirectory(at: renderingEdgeCasesSnapshotDirectory, withIntermediateDirectories: true)

		for slideNumber in 1 ... RenderingEdgeCasesFixture.slideCount {
			let source = exportDirectory.appendingPathComponent("\(slideNumber).png")
			guard fileManager.fileExists(atPath: source.path) else { throw FixtureError.missingExport(source) }
			let image = try requireImage(at: source)
			guard image.pixelSize == fullHDCanvasSize else {
				throw FixtureError.unexpectedImageSize(source, expected: fullHDCanvasSize, actual: image.pixelSize)
			}
		}

		try removeExistingSnapshots(in: renderingEdgeCasesSnapshotDirectory, fileManager: fileManager)
		for slideNumber in 1 ... RenderingEdgeCasesFixture.slideCount {
			let source = exportDirectory.appendingPathComponent("\(slideNumber).png")
			let destination = renderingEdgeCasesSnapshotDirectory.appendingPathComponent(
				"rendersRenderingEdgeCasesSlide.slide-\(slideNumber).png",
			)
			try fileManager.copyItem(at: source, to: destination)
			print("Installed \(destination.path)")
		}
	}

	private static func requireImage(at url: URL) throws -> NSImage {
		guard let image = NSImage(contentsOf: url) else { throw FixtureError.invalidImage(url) }
		return image
	}

	private static func removeExistingSnapshots(in directory: URL, fileManager: FileManager) throws {
		let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
		for url in contents where url.pathExtension.lowercased() == "png" {
			try fileManager.removeItem(at: url)
		}
	}

	private static func snapshotFilename(presentation: String, slideNumber: Int) -> String {
		"\(snapshotTestName(for: presentation)).slide-\(slideNumber).png"
	}

	private static func areaName(for presentation: String) -> String {
		presentation.replacing(/^\d+\s*-\s*/, with: "")
	}

	private static func snapshotTestName(for presentation: String) -> String {
		let words = presentation.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
		return "renders\(words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined())Slide"
	}
}

private struct UsageError: Error, CustomStringConvertible {
	var description: String {
		"""
		Usage:
		  swift run FixtureGenerator generate-design-system
		  swift run FixtureGenerator generate-design-system --check
		  swift run FixtureGenerator generate-malformed-bundle
		  swift run FixtureGenerator generate-malformed-bundle --check
		  swift run FixtureGenerator generate-typography
		  swift run FixtureGenerator generate-typography --check
		  swift run FixtureGenerator generate-rendering-edge-cases
		  swift run FixtureGenerator generate-rendering-edge-cases --check
		  swift run FixtureGenerator install-references --from /path/to/exported-pngs --replace
		  swift run FixtureGenerator install-malformed-bundle-references --from /path/to/exported-pngs --replace
		  swift run FixtureGenerator install-typography-references --from /path/to/exported-pngs --replace
		  swift run FixtureGenerator install-rendering-edge-cases-references --from /path/to/exported-pngs --replace
		"""
	}
}

private enum FixtureError: Error, CustomStringConvertible {
	case invalidImage(URL)
	case missingExport(URL)
	case unexpectedImageSize(URL, expected: CGSize, actual: CGSize)

	var description: String {
		switch self {
		case let .invalidImage(url):
			"Cannot read PNG export at \(url.path)."
		case let .missingExport(url):
			"Missing ProPresenter PNG export at \(url.path)."
		case let .unexpectedImageSize(url, expected, actual):
			"Expected a \(Int(expected.width))x\(Int(expected.height)) PNG at \(url.path), got \(Int(actual.width))x\(Int(actual.height))."
		}
	}
}

private extension NSImage {
	var pixelSize: CGSize {
		guard let representation = representations.first else { return size }
		return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
	}
}
