import ArgumentParser
import ProCRUDCore
import ProPresenterProto

struct EditSetTextDelivery: PresentationEditCommand {
	static let configuration = CommandConfiguration(commandName: "set-text-delivery", abstract: "Configure By Bullet reveals or remove a text Build In.")
	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Full component path ending in /element/text.") var path: String
	@Option(help: "Number of nonempty paragraphs visible before the first click. Zero hides all text; one leaves the heading visible.") var initiallyVisible: Int?
	@Flag(help: "Remove the text Build In and Delivery; retain any Build Out.") var clear = false
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		guard (initiallyVisible != nil) != clear else {
			throw ValidationError("Provide exactly one of --initially-visible or --clear.")
		}
		let componentPath = try ComponentPath(path)
		let canonical = try canonicalPath(componentPath, in: presentation)
		try DocumentEditor.setTextDelivery(in: &presentation, at: componentPath, initiallyVisible: initiallyVisible)
		return [.init(kind: .affected, path: canonical)]
	}
}
