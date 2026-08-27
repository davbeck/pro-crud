import Foundation
import Testing
@testable import ProCRUDCLI

@Suite("Documentation command")
struct DocsCommandTests {
	@Test
	func formatIncludesThemeDocumentationAndRelations() throws {
		try withDocumentationTemporaryDirectory { directory in
			let markdownURL = directory.appendingPathComponent("format.md")
			try DocsFormat.parse([
				"--output", markdownURL.path,
			]).run()

			let output = try String(contentsOf: markdownURL, encoding: .utf8)
			let themeMarkdown = try #require(CLIResources.formatDocumentation["ThemeDocuments.md"])
			#expect(output.contains(themeMarkdown))

			let jsonURL = directory.appendingPathComponent("format.json")
			try DocsFormat.parse([
				"--format", "json",
				"--output", jsonURL.path,
			]).run()
			let index = try JSONDecoder().decode(
				DocumentationIndex.self,
				from: Data(contentsOf: jsonURL),
			)
			let theme = try #require(index.documents.first { $0.identifier == "theme-documents" })
			#expect(theme.source.path == "Docs/Format/ThemeDocuments.md")
			#expect(Set(theme.relatedDocuments) == [
				"top-level-file-formats",
				"presentation-documents",
				"rendering-behavior",
			])
			for identifier in ["top-level-file-formats", "presentation-documents", "rendering-behavior"] {
				let related = try #require(index.documents.first { $0.identifier == identifier })
				#expect(related.relatedDocuments.contains("theme-documents"))
			}
		}
	}

	@Test
	func protobufSourceExportIncludesLicenseNotices() throws {
		try withDocumentationTemporaryDirectory { directory in
			let outputURL = directory.appendingPathComponent("proto", isDirectory: true)
			try DocsProtobuf.parse([
				"export",
				"--format", "proto",
				"--output", outputURL.path,
			]).run()

			for (filename, contents) in CLIResources.protobufNotices {
				#expect(try String(
					contentsOf: outputURL.appendingPathComponent(filename),
					encoding: .utf8,
				) == contents)
			}
		}
	}
}

private struct DocumentationIndex: Decodable {
	var documents: [DocumentationDocument]
}

private struct DocumentationDocument: Decodable {
	struct Source: Decodable {
		var path: String
	}

	var identifier: String
	var relatedDocuments: [String]
	var source: Source
}

private func withDocumentationTemporaryDirectory<Result>(
	_ operation: (URL) throws -> Result,
) throws -> Result {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("pro-crud-documentation-command-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: directory) }
	return try operation(directory)
}
