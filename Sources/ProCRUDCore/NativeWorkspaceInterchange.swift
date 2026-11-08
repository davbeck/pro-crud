import Foundation
import ProPresenterProto

/// Native Legacy Workspace export keeps collection membership as ordered ID
/// items and writes the definitions in the older top-level repeated field.
/// Native 22 workspace import ignores definitions stored only inside a collection.
enum NativeWorkspaceInterchange {
	static func document(_ data: Data, message: String) throws -> Data {
		if message == Rv_Data_Template.Document.protoMessageName {
			return try theme(data)
		}
		let fields: (collections: Int, definitions: Int, nested: Int, item: Int)
		switch message {
		case "rv.data.MacrosDocument": fields = (3, 2, 4, 3)
		case "rv.data.PropDocument": fields = (4, 2, 5, 3)
		default: return data
		}
		let root = try MediaWireMessage(data)
		guard root.payloads(fields.definitions).isEmpty else { throw NativeSemanticError.conflictingOrder(path: "/\(message)/legacy-definitions") }
		var result = Data(), seen: Set<UUID> = []
		for field in root.fields {
			guard field.number == fields.collections, let payload = field.payload else { result.append(field.raw); continue }
			let collection = try MediaWireMessage(payload)
			let definitions = collection.payloads(fields.nested)
			var ids: [String] = []
			for definition in definitions {
				guard let uuid = try MediaWireMessage(definition).message(1), let string = try uuid.string(1), let id = UUID(uuidString: string), seen.insert(id).inserted else { throw NativeSemanticError.invalidValue(path: message, expected: "unique definition UUIDs across collections") }
				ids.append(string)
				result.append(ProtobufJSONPatcher.WireField.lengthDelimited(number: fields.definitions, payload: definition).raw)
			}
			guard collection.payloads(fields.item).isEmpty else { throw NativeSemanticError.conflictingOrder(path: "/\(message)/legacy-collection-items") }
			var rewritten = collection.fields.filter { $0.number != fields.nested }.reduce(into: Data()) { $0.append($1.raw) }
			for id in ids {
				let uuid = try Rv_Data_UUID.with { $0.string = id }.serializedData()
				let item = ProtobufJSONPatcher.WireField.lengthDelimited(number: 1, payload: uuid).raw
				rewritten.append(ProtobufJSONPatcher.WireField.lengthDelimited(number: fields.item, payload: item).raw)
			}
			result.append(ProtobufJSONPatcher.WireField.lengthDelimited(number: field.number, payload: rewritten).raw)
		}
		return result
	}

	private static func theme(_ data: Data) throws -> Data {
		var theme = try Rv_Data_Template.Document(serializedBytes: data)
		for slide in theme.slides.indices {
			for index in theme.slides[slide].baseSlide.elements.indices {
				let element = theme.slides[slide].baseSlide.elements[index]
				guard element.hasTextScroller, element.textScroller.repeatDistance != 0 else { continue }
				guard !element.textScroller.shouldScroll, element.textScroller.scrollingDirection == .left,
				      element.textScroller.repeatDistance.isFinite, element.element.bounds.size.width.isFinite, element.element.bounds.size.width > 0
				else { throw NativeSemanticError.unsupportedNode(path: "/slides/\(slide)/elements/\(index)/text_scroller", kind: "Theme scroller interchange beyond the native-qualified inactive left-scrolling form") }
				// Native Theme export stores this distance as a fraction of width;
				// native import multiplies it back into native coordinate units.
				theme.slides[slide].baseSlide.elements[index].textScroller.repeatDistance /= element.element.bounds.size.width
			}
		}
		return try theme.serializedData()
	}
}
