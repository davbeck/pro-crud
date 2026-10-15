import ArgumentParser
import Foundation
import ProCRUDCore

struct WorkspaceSetText: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "set-text", abstract: "Replace a native slide element's plain text or RTF. Quit ProPresenter and stop workspace helpers first.")
	@Argument(help: "Exact registered local native workspace root.") var input: String
	@Option(help: "Shared Presentation stream UUID.") var stream: String
	@Option(help: "Exact Presentation slide-action UUID.") var action: String
	@Option(help: "Exact element UUID within the slide action.") var element: String
	@Option(help: "Exact local registry-v1.sqlite3 path.") var registry: String
	@Option(help: "Complete replacement plain text, using the element's existing default formatting.") var text: String?
	@Option(help: "RTF file containing the complete replacement text and formatting.") var rtf: String?

	func validate() throws {
		guard [stream, action, element].allSatisfy({ UUID(uuidString: $0) != nil }) else { throw ValidationError("--stream, --action and --element require UUIDs.") }
		guard (text != nil) != (rtf != nil) else { throw ValidationError("Provide exactly one of --text or --rtf.") }
	}

	func run() throws {
		guard let streamID = UUID(uuidString: stream), let actionID = UUID(uuidString: action), let elementID = UUID(uuidString: element) else { throw ValidationError("--stream, --action and --element require UUIDs.") }
		let content: NativeSlideTextContent
		if let text {
			content = .text(text)
		} else if let rtf {
			content = try .rtf(Data(contentsOf: URL(fileURLWithPath: rtf)))
		} else {
			throw ValidationError("Provide --text or --rtf.")
		}
		let receipts = try NativeLocalWorkspaceWriter.edit(.slideText(actionID: actionID, elementID: elementID, content: content), documentID: streamID, in: URL(fileURLWithPath: input), registry: URL(fileURLWithPath: registry))
		try print(prettyJSON(Result(documentID: streamID, actionID: actionID, elementID: elementID, changed: !receipts.isEmpty, receipts: receipts)))
	}

	private struct Result: Encodable {
		let documentID: UUID
		let actionID: UUID
		let elementID: UUID
		let changed: Bool
		let receipts: [NativeLocalCommitReceipt]
	}
}
