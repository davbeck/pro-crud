import ArgumentParser
import Foundation
import ProCRUDCore
import SwiftProtobuf

struct Dump: ParsableCommand {
	enum Format: String, CaseIterable, ExpressibleByArgument {
		case text
		case json
		case protobufJSON = "protobuf-json"
	}

	static let configuration = CommandConfiguration(
		abstract: "Print semantic authoring details or known-schema protobuf JSON for a ProPresenter document.",
	)

	@Argument(help: "Path to a raw document, workspace directory, or bundle.") var input: String
	@Option(help: "Output format: text (default), json, or protobuf-json.") var format: Format = .text
	@Option(help: "Component path to inspect.") var path: String?

	func run() throws {
		let document = try DocumentLoader.load(from: URL(fileURLWithPath: input))
		try print(output(document: document))
	}

	func output(document: ProPresenterDocument) throws -> String {
		if let path {
			let selection = try ComponentResolver.resolve(ComponentPath(path), in: document)
			switch format {
			case .text:
				return DumpTextFormatter.format(ComponentDumpReport(selection: selection))
			case .json:
				return try prettyJSON(ComponentDumpReport(selection: selection))
			case .protobufJSON:
				return try String(decoding: selection.jsonUTF8Data(), as: UTF8.self)
			}
		}

		switch format {
		case .text:
			return try DumpTextFormatter.format(DocumentDumpReport.make(from: document))
		case .json:
			return try prettyJSON(DocumentDumpReport.make(from: document))
		case .protobufJSON:
			return try protobufJSON(document)
		}
	}

	private func protobufJSON(_ document: ProPresenterDocument) throws -> String {
		if document.themeEntries.count > 1 {
			let themes = try document.themeEntries.map { entry -> [String: Any] in
				var options = JSONEncodingOptions()
				options.useDeterministicOrdering = true
				return try [
					"path": entry.relativePath,
					"document": JSONSerialization.jsonObject(with: entry.document.jsonUTF8Data(options: options)),
				]
			}
			let data = try JSONSerialization.data(withJSONObject: themes, options: [.prettyPrinted, .sortedKeys])
			return String(decoding: data, as: UTF8.self)
		}
		return try prettyProtobufJSON(document.payload)
	}
}

func prettyJSON(_ value: some Encodable) throws -> String {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
	return try String(decoding: encoder.encode(value), as: UTF8.self)
}

func prettyProtobufJSON(_ payload: DocumentPayload) throws -> String {
	let object = try JSONSerialization.jsonObject(with: payload.jsonUTF8Data())
	let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
	return String(decoding: data, as: UTF8.self)
}
