import ArgumentParser
import Foundation
import ProCRUDCore
import SwiftProtobuf

struct Docs: ParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Print bundled ProPresenter documentation and schema references.",
		subcommands: [DocsFormat.self, DocsProtobuf.self],
		defaultSubcommand: DocsFormat.self,
	)
}

struct DocsFormat: ParsableCommand {
	enum Format: String, CaseIterable, ExpressibleByArgument { case markdown, json }

	static let configuration = CommandConfiguration(commandName: "format", abstract: "Print bundled ProPresenter format documentation.")

	@Option(help: "Output format.") var format: Format = .markdown
	@Option(help: "Write documentation to a file instead of standard output.") var output: String?
	@Flag(help: "Replace an existing output file.") var replace = false

	func run() throws {
		let index = try PublicDocumentation.index()
		let contents: String
		switch format {
		case .markdown: contents = PublicDocumentation.markdownIndex(index)
		case .json: contents = try PublicDocumentation.jsonIndex(index)
		}
		if let output {
			try writeDocumentation(contents, to: URL(fileURLWithPath: output), replace: replace)
		} else {
			print(contents, terminator: "")
		}
	}
}

struct DocsProtobuf: ParsableCommand {
	enum Format: String, CaseIterable, ExpressibleByArgument { case markdown, json, proto, descriptorSet = "descriptor-set" }

	static let configuration = CommandConfiguration(commandName: "protobuf", abstract: "Inspect or export the bundled protobuf schema.")
	@Argument(help: "Use export to write a portable schema artifact.") var mode: String?
	@Option(help: "Output format.") var format: Format = .markdown
	@Option(help: "Write output to this file or directory.") var output: String?
	@Flag(help: "Replace an existing output file or directory.") var replace = false

	func run() throws {
		if let mode {
			guard mode == "export" else { throw ValidationError("Unknown protobuf mode \(mode). Use export.") }
			guard let output else { throw ValidationError("docs protobuf export requires --output.") }
			try ProtobufDocumentation.export(format: format, to: URL(fileURLWithPath: output), replace: replace)
			let metadata = try ProtobufDocumentation.metadata()
			print("Schema revision: \(metadata.revision)")
			print("Schema content hash: \(metadata.contentHash)")
			print("Exported protobuf \(format.rawValue) to \(output)")
			return
		}
		guard format == .markdown || format == .json else {
			throw ValidationError("Use docs protobuf export for \(format.rawValue) output.")
		}
		let contents = try format == .markdown ? ProtobufDocumentation.markdown() : ProtobufDocumentation.json()
		if let output {
			try writeDocumentation(contents, to: URL(fileURLWithPath: output), replace: replace)
		} else {
			print(contents, terminator: "")
		}
	}
}

private func writeDocumentation(_ contents: String, to outputURL: URL, replace: Bool) throws {
	guard replace || !FileManager.default.fileExists(atPath: outputURL.path) else {
		throw ValidationError("Output already exists: \(outputURL.path). Use --replace.")
	}
	try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
	try contents.write(to: outputURL, atomically: true, encoding: .utf8)
}

private enum PublicDocumentation {
	struct Document: Codable {
		var identifier: String
		var title: String
		var summary: String
		var markdown: String
		var headings: [String]
		var relatedDocuments: [String]
		var source: Source
	}

	struct Source: Codable {
		var path: String
		var provenance: String
	}

	static func index() throws -> [Document] {
		try definitions.map { definition in
			guard let markdown = CLIResources.formatDocumentation[definition.filename] else {
				throw CocoaError(.fileNoSuchFile)
			}
			return Document(
				identifier: definition.identifier,
				title: firstHeading(in: markdown),
				summary: firstParagraph(in: markdown),
				markdown: markdown,
				headings: markdown.split(separator: "\n").compactMap { line in
					let text = line.drop(while: { $0 == "#" || $0 == " " })
					return line.hasPrefix("#") ? String(text) : nil
				},
				relatedDocuments: definition.related,
				source: Source(path: "Docs/Format/\(definition.filename)", provenance: "Bundled from the ProCRUD format documentation"),
			)
		}
	}

	static func markdownIndex(_ documents: [Document]) -> String {
		var output = "# ProCRUD Format Documentation\n\n"
		for document in documents {
			output += document.markdown + (document.markdown.hasSuffix("\n") ? "" : "\n")
		}
		return output
	}

	static func jsonIndex(_ documents: [Document]) throws -> String {
		struct Index: Codable { var version: Int; var documents: [Document] }
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try String(decoding: encoder.encode(Index(version: 1, documents: documents)), as: UTF8.self) + "\n"
	}

	private static let definitions: [(identifier: String, filename: String, related: [String])] = [
		("top-level-file-formats", "TopLevelFileFormats.md", ["presentation-documents", "theme-documents", "rendering-behavior"]),
		("presentation-documents", "PresentationDocuments.md", ["top-level-file-formats", "theme-documents", "rendering-behavior"]),
		("theme-documents", "ThemeDocuments.md", ["top-level-file-formats", "presentation-documents", "rendering-behavior"]),
		("rendering-behavior", "RenderingBehavior.md", ["presentation-documents", "theme-documents"]),
	]

	private static func firstHeading(in markdown: String) -> String {
		markdown.split(separator: "\n").first(where: { $0.hasPrefix("# ") }).map { String($0.dropFirst(2)) } ?? "ProCRUD Documentation"
	}

	private static func firstParagraph(in markdown: String) -> String {
		let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
		guard let heading = lines.firstIndex(where: { $0.hasPrefix("# ") }) else { return "" }
		return lines.dropFirst(heading + 1).drop(while: { $0.isEmpty }).prefix(while: { !$0.isEmpty }).joined(separator: " ")
	}
}

private enum ProtobufDocumentation {
	static func markdown() throws -> String {
		let descriptor = try descriptorSet()
		let metadata = try metadata()
		let mapEntries = mapEntryTypes(in: descriptor)
		var output = "# ProPresenter Protobuf Reference\n\n"
		output += "- Schema revision: `\(metadata.revision)`\n"
		output += "- Schema content hash: `\(metadata.contentHash)`\n"
		output += "- Schema source: `Vendor/ProPresenter7Proto/proto/`\n\n"
		output += "## Root Message Lookup\n\n| Path | Root message |\n| --- | --- |\n"
		for entry in rootMessageLookup {
			output += "| `\(entry.path)` | `\(entry.rootMessage)` |\n"
		}
		output += "\n## Import Graph\n\n"
		for file in descriptor.file.sorted(by: { $0.name < $1.name }) {
			output += "- `\(file.name)` → \(file.dependency.isEmpty ? "(none)" : file.dependency.map { "`\($0)`" }.joined(separator: ", "))\n"
		}
		output += "\n## Files\n"
		for file in descriptor.file.sorted(by: { $0.name < $1.name }) {
			output += "\n### `\(file.name)`\n\n"
			output += "Package: `\(file.package)`\n\n"
			if !file.dependency.isEmpty {
				output += "Imports: \(file.dependency.map { "`\($0)`" }.joined(separator: ", "))\n\n"
			}
			output += "Generated Swift: `Sources/ProPresenterProto/Generated/\(generatedSwiftName(for: file.name))`\n\n"
			append(enums: file.enumType, prefix: file.package, to: &output)
			append(messages: file.messageType, prefix: file.package, syntax: file.syntax, mapEntries: mapEntries, to: &output)
		}
		return output
	}

	static func json() throws -> String {
		let descriptor = try descriptorSet()
		var encoding = JSONEncodingOptions()
		encoding.useDeterministicOrdering = true
		let descriptorObject = try JSONSerialization.jsonObject(with: descriptor.jsonUTF8Data(options: encoding))
		let envelope: [String: Any] = try [
			"version": 1,
			"metadata": [
				"schemaSource": "Vendor/ProPresenter7Proto/proto/",
				"revision": metadata(named: "revision.txt"),
				"contentHash": metadata(named: "content-sha256.txt"),
			],
			"rootMessageLookup": rootMessageLookup.map { ["path": $0.path, "rootMessage": $0.rootMessage] },
			"importGraph": descriptor.file.map { ["proto": $0.name, "imports": $0.dependency] }.sorted { ($0["proto"] as? String ?? "") < ($1["proto"] as? String ?? "") },
			"generatedSwiftMapping": descriptorSet().file.map { ["proto": $0.name, "swift": "Sources/ProPresenterProto/Generated/\(generatedSwiftName(for: $0.name))"] }.sorted { ($0["proto"] ?? "") < ($1["proto"] ?? "") },
			"fileDescriptorSet": descriptorObject,
		]
		let data = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
		return String(decoding: data, as: UTF8.self) + "\n"
	}

	static func export(format: DocsProtobuf.Format, to outputURL: URL, replace: Bool) throws {
		if FileManager.default.fileExists(atPath: outputURL.path) {
			guard replace else { throw ValidationError("Output already exists: \(outputURL.path). Use --replace.") }
			try FileManager.default.removeItem(at: outputURL)
		}
		switch format {
		case .proto:
			try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
			for (path, contents) in CLIResources.protobufSources.sorted(by: { $0.key < $1.key }) {
				let fileURL = outputURL.appendingPathComponent(path)
				try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
				try contents.write(to: fileURL, atomically: true, encoding: .utf8)
			}
			for (filename, contents) in CLIResources.protobufNotices.sorted(by: { $0.key < $1.key }) {
				try contents.write(
					to: outputURL.appendingPathComponent(filename),
					atomically: true,
					encoding: .utf8,
				)
			}
		case .descriptorSet:
			try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			try BundledProtobufSchema.data().write(to: outputURL)
		case .json:
			try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
			try json().write(to: outputURL, atomically: true, encoding: .utf8)
		case .markdown:
			throw ValidationError("Use --format proto, descriptor-set, or json with docs protobuf export.")
		}
	}

	static func metadata() throws -> (revision: String, contentHash: String) {
		try (
			revision: metadata(named: "revision.txt"),
			contentHash: metadata(named: "content-sha256.txt"),
		)
	}

	private static func descriptorSet() throws -> Google_Protobuf_FileDescriptorSet {
		try Google_Protobuf_FileDescriptorSet(serializedBytes: BundledProtobufSchema.data())
	}

	private static func metadata(named name: String) throws -> String {
		guard let value = CLIResources.protobufMetadata[name] else {
			throw CocoaError(.fileNoSuchFile)
		}
		return value.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func generatedSwiftName(for proto: String) -> String {
		URL(fileURLWithPath: proto).deletingPathExtension().lastPathComponent + ".pb.swift"
	}

	private static func append(
		messages: [Google_Protobuf_DescriptorProto],
		prefix: String,
		syntax: String,
		mapEntries: Set<String>,
		to output: inout String,
	) {
		for message in messages {
			let name = prefix.isEmpty ? message.name : "\(prefix).\(message.name)"
			output += "#### \(name)\n\n"
			output += "Map entry: \(message.options.mapEntry ? "yes" : "no")\n\n"
			if !message.reservedName.isEmpty {
				output += "Reserved names: \(message.reservedName.map { "`\($0)`" }.joined(separator: ", "))\n\n"
			}
			if !message.reservedRange.isEmpty {
				output += "Reserved ranges (end-exclusive): \(message.reservedRange.map { "`\($0.start)..<\($0.end)`" }.joined(separator: ", "))\n\n"
			}
			if !message.oneofDecl.isEmpty {
				output += "Oneofs: \(message.oneofDecl.enumerated().map { "`\($0.offset): \($0.element.name)`" }.joined(separator: ", "))\n\n"
			}
			if message.field.isEmpty {
				output += "No direct fields.\n\n"
			} else {
				output += "| Field | Tag | Cardinality | Type | Map entry | Oneof | Presence |\n"
				output += "| --- | ---: | --- | --- | --- | --- | --- |\n"
				for field in message.field {
					let typeName = field.typeName.isEmpty ? String(describing: field.type) : field.typeName
					let normalizedType = String(typeName.drop(while: { $0 == "." }))
					let mapEntry = mapEntries.contains(normalizedType)
					let oneof = field.hasOneofIndex && message.oneofDecl.indices.contains(Int(field.oneofIndex))
						? message.oneofDecl[Int(field.oneofIndex)].name
						: ""
					output += "| `\(field.name)` | \(field.number) | \(cardinality(field.label)) | `\(typeName)` | \(mapEntry ? "yes" : "no") | \(oneof.isEmpty ? "" : "`\(oneof)`") | \(hasPresence(field, syntax: syntax) ? "yes" : "no") |\n"
				}
				output += "\n"
			}
			append(enums: message.enumType, prefix: name, to: &output)
			append(messages: message.nestedType, prefix: name, syntax: syntax, mapEntries: mapEntries, to: &output)
		}
	}

	private static func append(enums: [Google_Protobuf_EnumDescriptorProto], prefix: String, to output: inout String) {
		for enumType in enums {
			let name = prefix.isEmpty ? enumType.name : "\(prefix).\(enumType.name)"
			output += "#### \(name) (enum)\n\n"
			if !enumType.reservedName.isEmpty {
				output += "Reserved names: \(enumType.reservedName.map { "`\($0)`" }.joined(separator: ", "))\n\n"
			}
			if !enumType.reservedRange.isEmpty {
				output += "Reserved ranges (inclusive): \(enumType.reservedRange.map { "`\($0.start)...\($0.end)`" }.joined(separator: ", "))\n\n"
			}
			output += "| Value | Number |\n| --- | ---: |\n"
			for value in enumType.value {
				output += "| `\(value.name)` | \(value.number) |\n"
			}
			output += "\n"
		}
	}

	private static func cardinality(_ label: Google_Protobuf_FieldDescriptorProto.Label) -> String {
		switch label {
		case .optional: "optional"
		case .required: "required"
		case .repeated: "repeated"
		}
	}

	private static func hasPresence(_ field: Google_Protobuf_FieldDescriptorProto, syntax: String) -> Bool {
		if field.label == .repeated {
			return false
		}
		if field.type == .message || field.hasOneofIndex || field.proto3Optional {
			return true
		}
		return syntax != "proto3"
	}

	private static func mapEntryTypes(in descriptor: Google_Protobuf_FileDescriptorSet) -> Set<String> {
		var result = Set<String>()
		for file in descriptor.file {
			collectMapEntries(file.messageType, prefix: file.package, into: &result)
		}
		return result
	}

	private static func collectMapEntries(
		_ messages: [Google_Protobuf_DescriptorProto],
		prefix: String,
		into result: inout Set<String>,
	) {
		for message in messages {
			let name = prefix.isEmpty ? message.name : "\(prefix).\(message.name)"
			if message.options.mapEntry {
				result.insert(name)
			}
			collectMapEntries(message.nestedType, prefix: name, into: &result)
		}
	}

	private struct RootMessage {
		let path: String
		let rootMessage: String
	}

	private static let rootMessageLookup: [RootMessage] = [
		RootMessage(path: "*.pro", rootMessage: "rv.data.Presentation"),
		RootMessage(path: "data", rootMessage: "rv.data.PlaylistDocument"),
		RootMessage(path: "Theme", rootMessage: "rv.data.Template.Document"),
		RootMessage(path: "Configuration/Groups", rootMessage: "rv.data.ProGroupsDocument"),
		RootMessage(path: "Configuration/Labels", rootMessage: "rv.data.ProLabelsDocument"),
		RootMessage(path: "Configuration/Timers", rootMessage: "rv.data.TimersDocument"),
		RootMessage(path: "Configuration/Props", rootMessage: "rv.data.PropDocument"),
		RootMessage(path: "Configuration/Workspace", rootMessage: "rv.data.ProPresenterWorkspace"),
		RootMessage(path: "Configuration/Messages", rootMessage: "rv.data.MessageDocument"),
		RootMessage(path: "Configuration/Macros", rootMessage: "rv.data.MacrosDocument"),
		RootMessage(path: "Configuration/ClearGroups", rootMessage: "rv.data.ClearGroupsDocument"),
		RootMessage(path: "Configuration/KeyMappings", rootMessage: "rv.data.KeyMappingDocument"),
		RootMessage(path: "Configuration/Calendar", rootMessage: "rv.data.Calendar"),
		RootMessage(path: "Configuration/Stage", rootMessage: "rv.data.Stage.Document"),
		RootMessage(path: "Configuration/TestPatterns", rootMessage: "rv.data.TestPattern"),
		RootMessage(path: "Configuration/CCLI", rootMessage: "rv.data.CCLIDocument"),
	]
}
