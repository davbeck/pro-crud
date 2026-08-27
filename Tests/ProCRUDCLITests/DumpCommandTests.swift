import ArgumentParser
import Foundation
import ProCRUDCore
import Testing
@testable import ProCRUDCLI

@Suite("Dump command")
struct DumpCommandTests {
	@Test
	func defaultsToTextAndOffersSemanticJSONAndProtobufJSON() throws {
		let presentation = DocumentFactory.presentation(name: "Dump formats")
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Dump.pro")),
		)

		let textCommand = try Dump.parse(["/tmp/Dump.pro"])
		#expect(textCommand.format == .text)
		let text = try textCommand.output(document: document)
		#expect(text.contains("Native cue order:"))
		#expect(text.contains("Actions:"))

		let jsonCommand = try Dump.parse(["/tmp/Dump.pro", "--format", "json"])
		let report = try JSONDecoder().decode(DocumentDumpReport.self, from: Data(jsonCommand.output(document: document).utf8))
		#expect(report.presentation?.name == "Dump formats")

		let protobufCommand = try Dump.parse(["/tmp/Dump.pro", "--format", "protobuf-json"])
		let protobufJSON = try protobufCommand.output(document: document)
		#expect(protobufJSON.contains("\"applicationInfo\""))
		#expect(!protobufJSON.contains("\"source\""))

		#expect(Dump.Format.allCases.map(\.rawValue) == ["text", "json", "protobuf-json"])
		#expect(Dump.configuration.abstract.contains("semantic authoring details"))
	}

	@Test
	func pathUsesSemanticSelectionForTextAndJSON() throws {
		let presentation = DocumentFactory.presentation(name: "Selection")
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Selection.pro")),
		)
		let arguments = ["/tmp/Selection.pro", "--path", "/cues[index=0]"]

		let text = try Dump.parse(arguments).output(document: document)
		#expect(text.contains("Protobuf type: rv.data.Cue"))
		#expect(text.contains("Actions: 1"))

		let json = try Dump.parse(arguments + ["--format", "json"]).output(document: document)
		let report = try JSONDecoder().decode(ComponentDumpReport.self, from: Data(json.utf8))
		#expect(report.path.contains("/cues[uuid="))
		#expect(report.children["actions"] == 1)
	}
}
