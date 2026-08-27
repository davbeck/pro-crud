import CoreFoundation
import Foundation

public struct ComponentPath: Sendable, Equatable, CustomStringConvertible {
	public struct Segment: Sendable, Equatable {
		public var field: String
		public var selector: Selector?
	}

	public enum Selector: Sendable, Equatable {
		case index(Int)
		case field(name: String, value: String)
	}

	public var segments: [Segment]

	public init(segments: [Segment]) {
		self.segments = segments
	}

	public init(_ text: String) throws {
		guard text == "/" || text.hasPrefix("/") else { throw ComponentPathError.invalidPath(text) }
		if text == "/" {
			segments = []; return
		}
		segments = try text.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map { raw in
			let text = String(raw)
			guard !text.isEmpty else { throw ComponentPathError.invalidPath(text) }
			if let opening = text.firstIndex(of: "[") {
				guard text.hasSuffix("]"), text[text.index(after: opening) ..< text.index(before: text.endIndex)].contains("=") else {
					throw ComponentPathError.invalidSelector(text)
				}
				let field = String(text[..<opening])
				let contents = String(text[text.index(after: opening) ..< text.index(before: text.endIndex)])
				let parts = contents.split(separator: "=", maxSplits: 1).map(String.init)
				if parts[0] == "index", let index = Int(parts[1]), index >= 0 {
					return Segment(field: field, selector: .index(index))
				}
				let value = try ComponentPath.decodeScalar(parts[1])
				return Segment(field: field, selector: .field(name: parts[0], value: value))
			}
			return Segment(field: text, selector: nil)
		}
	}

	public var description: String {
		guard !segments.isEmpty else { return "/" }
		return "/" + segments.map { segment in
			guard let selector = segment.selector else { return segment.field }
			return "\(segment.field)[\(selector.pathDescription)]"
		}.joined(separator: "/")
	}

	private static func decodeScalar(_ source: String) throws -> String {
		if source.hasPrefix("\"") {
			guard let data = source.data(using: .utf8), let decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
				throw ComponentPathError.invalidSelector(source)
			}
			return decoded
		}
		return source
	}

	private static func encodeScalar(_ value: String) -> String {
		guard let data = try? JSONSerialization.data(withJSONObject: [value]), let encoded = String(data: data, encoding: .utf8) else { return value }
		return String(encoded.dropFirst().dropLast())
	}
}

private extension ComponentPath.Selector {
	var pathDescription: String {
		switch self {
		case let .index(value): "index=\(value)"
		case let .field(name, value): "\(name)=\(ComponentPath.encodeScalar(value))"
		}
	}
}

public enum ComponentPathError: Error, CustomStringConvertible, Sendable {
	case invalidPath(String)
	case invalidSelector(String)
	case unsupported(field: String, at: String)
	case selectorRequired(field: String, at: String)
	case selectorNotAllowed(field: String, at: String)
	case noMatch(path: String, candidates: [String])

	public var description: String {
		switch self {
		case let .invalidPath(value): "Invalid component path: \(value)"
		case let .invalidSelector(value): "Invalid component selector: \(value)"
		case let .unsupported(field, at): "Field \(field) is not traversable at \(at)."
		case let .selectorRequired(field, at): "Repeated field \(field) requires a selector at \(at)."
		case let .selectorNotAllowed(field, at): "Singular field \(field) does not accept a selector at \(at)."
		case let .noMatch(path, candidates): "No unique component matched \(path). Candidates: \(candidates.joined(separator: ", "))"
		}
	}
}

struct ProtobufTraversalStep: Sendable {
	var fieldNumber: Int
	var occurrenceIndex: Int
}

struct JSONTraversalStep {
	var fieldName: String
	var index: Int?
}

/// Maps the index used by a component path to the corresponding repeated-field
/// occurrence. Most protobuf collections use stored order, but some document
/// domains (notably presentation cues) persist a separate native order.
struct ComponentIndexOrder: Sendable, Equatable {
	let storageIndices: [Int]

	init(storageCount: Int, effectiveStorageIndices: [Int]? = nil) {
		var seen = Set<Int>()
		var normalized: [Int] = []
		for index in effectiveStorageIndices ?? Array(0 ..< storageCount)
			where (0 ..< storageCount).contains(index) && seen.insert(index).inserted
		{
			normalized.append(index)
		}
		normalized.append(contentsOf: (0 ..< storageCount).filter { seen.insert($0).inserted })
		storageIndices = normalized
	}

	func storageIndex(atPathIndex index: Int) -> Int? {
		storageIndices.indices.contains(index) ? storageIndices[index] : nil
	}

	func pathIndex(forStorageIndex index: Int) -> Int? {
		storageIndices.firstIndex(of: index)
	}
}

/// Constructs paths whose selectors are guaranteed to remain resolvable for
/// the current document: a UUID is used only when it is nonempty and unique in
/// its collection, otherwise the collection's path-order index is used.
enum ComponentPathBuilder {
	static func repeatedPath(
		parent: String = "",
		field: String,
		storageIndex: Int,
		identities: [String],
		order: ComponentIndexOrder? = nil,
	) -> String {
		let selector = selector(
			storageIndex: storageIndex,
			identities: identities,
			order: order,
		)
		let segment = ComponentPath(segments: [.init(field: field, selector: selector)]).description.dropFirst()
		let prefix = parent == "/" ? "" : parent
		return "\(prefix)/\(segment)"
	}

	static func selector(
		storageIndex: Int,
		identities: [String],
		order: ComponentIndexOrder? = nil,
	) -> ComponentPath.Selector {
		if identities.indices.contains(storageIndex) {
			let identity = identities[storageIndex]
			if !identity.isEmpty, identities.count(where: { $0 == identity }) == 1 {
				return .field(name: "uuid", value: identity)
			}
		}
		let resolvedOrder = order ?? ComponentIndexOrder(storageCount: identities.count)
		return .index(resolvedOrder.pathIndex(forStorageIndex: storageIndex) ?? storageIndex)
	}

	static func selectorDescription(_ selector: ComponentPath.Selector) -> String {
		selector.pathDescription
	}
}

/// An opaque location for a component in a document's protobuf storage.
///
/// Unlike a component path, a location continues to identify the same stored
/// message when an edit changes its UUID or its effective collection order.
public struct ComponentLocation: Sendable {
	fileprivate var rootMessageName: String
	fileprivate var traversal: [ProtobufTraversalStep]
}

public struct ComponentSelection {
	public var canonicalPath: String
	public var protoMessageName: String
	public var jsonObject: [String: Any]
	public var location: ComponentLocation {
		ComponentLocation(rootMessageName: rootMessageName, traversal: traversal)
	}

	var rootMessageName: String
	var traversal: [ProtobufTraversalStep]
	var rootJSON: [String: Any]
	var jsonTraversal: [JSONTraversalStep]

	public func jsonUTF8Data() throws -> Data {
		try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
	}

	func rootJSON(applying patch: [String: Any]) throws -> [String: Any] {
		let replacement = try replacingSelection(
			in: rootJSON,
			steps: jsonTraversal[...],
			targetType: protoMessageName,
			patch: patch,
		)
		guard let root = replacement as? [String: Any] else {
			throw DocumentEditError.unsupportedPatchValue("Patched protobuf root is not a message.")
		}
		return root
	}

	private func replacingSelection(
		in value: Any,
		steps: ArraySlice<JSONTraversalStep>,
		targetType: String,
		patch: [String: Any],
	) throws -> Any {
		guard let step = steps.first else {
			guard let object = value as? [String: Any] else {
				throw DocumentEditError.unsupportedPatchValue("Selected protobuf value is not a message.")
			}
			return try ProtobufSchema.bundled().mergedJSON(original: object, patch: patch, messageType: targetType)
		}
		guard var object = value as? [String: Any] else {
			throw DocumentEditError.unsupportedPatchValue("Component path no longer matches the protobuf JSON document.")
		}
		if let index = step.index {
			guard var values = object[step.fieldName] as? [Any], values.indices.contains(index) else {
				throw DocumentEditError.unsupportedPatchValue("Component path no longer matches the repeated protobuf field \(step.fieldName).")
			}
			values[index] = try replacingSelection(in: values[index], steps: steps.dropFirst(), targetType: targetType, patch: patch)
			object[step.fieldName] = values
		} else {
			guard let child = object[step.fieldName] else {
				throw DocumentEditError.unsupportedPatchValue("Component path no longer matches the protobuf field \(step.fieldName).")
			}
			object[step.fieldName] = try replacingSelection(in: child, steps: steps.dropFirst(), targetType: targetType, patch: patch)
		}
		return object
	}
}

public enum ComponentResolver {
	public static func resolve(_ path: ComponentPath, in document: ProPresenterDocument) throws -> ComponentSelection {
		let rootType = rootMessageName(document.payload)
		let presentationCueOrder: ComponentIndexOrder? = switch document.payload {
		case let .presentation(presentation): presentation.presentationCueIndexOrder
		case .theme, .playlist: nil
		}
		var descriptor = try ProtobufSchema.bundled().message(named: rootType)
		let rootObject = try rootJSONObject(document.payload)
		var object = rootObject
		var canonical = ""
		var traversal: [ProtobufTraversalStep] = []
		var jsonTraversal: [JSONTraversalStep] = []
		for segment in path.segments {
			let parent = canonical.isEmpty ? "/" : canonical
			if descriptor.name == "rv.data.Playlist", segment.field == "items", segment.selector != nil {
				let wrapper = try field(named: "items", in: descriptor, at: parent)
				guard let wrapperType = wrapper.typeName,
				      let wrapperObject = messageValue(for: wrapper, in: object)
				else {
					throw ComponentPathError.noMatch(path: parent + "/items", candidates: [])
				}
				traversal.append(ProtobufTraversalStep(fieldNumber: wrapper.number, occurrenceIndex: 0))
				jsonTraversal.append(JSONTraversalStep(fieldName: wrapper.jsonName, index: nil))
				descriptor = try ProtobufSchema.bundled().message(named: wrapperType)
				object = wrapperObject
				let repeatedItems = try field(named: "items", in: descriptor, at: parent + "/items")
				let selected = try select(repeatedItems, selector: segment.selector, in: object, parent: parent + "/items")
				traversal.append(ProtobufTraversalStep(fieldNumber: repeatedItems.number, occurrenceIndex: selected.index))
				jsonTraversal.append(JSONTraversalStep(fieldName: repeatedItems.jsonName, index: selected.index))
				canonical += "/items/items[\(selected.canonical)]"
				guard let itemsType = repeatedItems.typeName else {
					throw ComponentPathError.unsupported(field: repeatedItems.protoName, at: parent + "/items")
				}
				descriptor = try ProtobufSchema.bundled().message(named: itemsType)
				object = selected.object
				continue
			}

			let selectedField = try field(named: segment.field, in: descriptor, at: parent)
			guard selectedField.isMessage, let typeName = selectedField.typeName else {
				throw ComponentPathError.unsupported(field: selectedField.protoName, at: parent)
			}
			if selectedField.isRepeated {
				let indexOrder = descriptor.name == "rv.data.Presentation" && selectedField.protoName == "cues"
					? presentationCueOrder
					: nil
				let selected = try select(selectedField, selector: segment.selector, in: object, parent: parent, indexOrder: indexOrder)
				traversal.append(ProtobufTraversalStep(fieldNumber: selectedField.number, occurrenceIndex: selected.index))
				jsonTraversal.append(JSONTraversalStep(fieldName: selectedField.jsonName, index: selected.index))
				canonical += "/\(selectedField.protoName)[\(selected.canonical)]"
				object = selected.object
			} else {
				guard segment.selector == nil else {
					throw ComponentPathError.selectorNotAllowed(field: selectedField.protoName, at: parent)
				}
				guard let child = messageValue(for: selectedField, in: object) else {
					throw ComponentPathError.noMatch(path: parent + "/" + selectedField.protoName, candidates: [])
				}
				traversal.append(ProtobufTraversalStep(fieldNumber: selectedField.number, occurrenceIndex: 0))
				jsonTraversal.append(JSONTraversalStep(fieldName: selectedField.jsonName, index: nil))
				canonical += "/\(selectedField.protoName)"
				object = child
			}
			descriptor = try ProtobufSchema.bundled().message(named: typeName)
		}
		return ComponentSelection(
			canonicalPath: canonical.isEmpty ? "/" : canonical,
			protoMessageName: descriptor.name,
			jsonObject: object,
			rootMessageName: rootType,
			traversal: traversal,
			rootJSON: rootObject,
			jsonTraversal: jsonTraversal,
		)
	}

	/// Resolves a previously selected protobuf storage location in the current
	/// document and returns its current canonical component path.
	public static func resolve(_ location: ComponentLocation, in document: ProPresenterDocument) throws -> ComponentSelection {
		let rootType = rootMessageName(document.payload)
		guard rootType == location.rootMessageName else {
			throw ComponentPathError.noMatch(path: "/", candidates: [])
		}
		let schema = try ProtobufSchema.bundled()
		let presentationCueOrder: ComponentIndexOrder? = switch document.payload {
		case let .presentation(presentation): presentation.presentationCueIndexOrder
		case .theme, .playlist: nil
		}
		var descriptor = try schema.message(named: rootType)
		let rootObject = try rootJSONObject(document.payload)
		var object = rootObject
		var canonical = ""
		var traversal: [ProtobufTraversalStep] = []
		var jsonTraversal: [JSONTraversalStep] = []

		for step in location.traversal {
			let parent = canonical.isEmpty ? "/" : canonical
			guard let selectedField = descriptor.fields.first(where: { $0.number == step.fieldNumber }),
			      selectedField.isMessage,
			      let typeName = selectedField.typeName
			else {
				throw ComponentPathError.noMatch(path: parent, candidates: [])
			}
			if selectedField.isRepeated {
				let rawValues = (object[selectedField.jsonName] ?? object[selectedField.protoName]) as? [Any] ?? []
				let values = rawValues.compactMap { $0 as? [String: Any] }
				guard values.indices.contains(step.occurrenceIndex) else {
					throw ComponentPathError.noMatch(path: parent + "/" + selectedField.protoName, candidates: [])
				}
				let indexOrder = descriptor.name == "rv.data.Presentation" && selectedField.protoName == "cues"
					? presentationCueOrder
					: nil
				canonical = ComponentPathBuilder.repeatedPath(
					parent: canonical,
					field: selectedField.protoName,
					storageIndex: step.occurrenceIndex,
					identities: values.map { uuid(in: $0) ?? "" },
					order: indexOrder,
				)
				object = values[step.occurrenceIndex]
				jsonTraversal.append(JSONTraversalStep(fieldName: selectedField.jsonName, index: step.occurrenceIndex))
			} else {
				guard let child = messageValue(for: selectedField, in: object) else {
					throw ComponentPathError.noMatch(path: parent + "/" + selectedField.protoName, candidates: [])
				}
				canonical += "/\(selectedField.protoName)"
				object = child
				jsonTraversal.append(JSONTraversalStep(fieldName: selectedField.jsonName, index: nil))
			}
			traversal.append(step)
			descriptor = try schema.message(named: typeName)
		}

		return ComponentSelection(
			canonicalPath: canonical.isEmpty ? "/" : canonical,
			protoMessageName: descriptor.name,
			jsonObject: object,
			rootMessageName: rootType,
			traversal: traversal,
			rootJSON: rootObject,
			jsonTraversal: jsonTraversal,
		)
	}

	private static func rootMessageName(_ payload: DocumentPayload) -> String {
		switch payload {
		case .presentation: "rv.data.Presentation"
		case .theme: "rv.data.Template.Document"
		case .playlist: "rv.data.PlaylistDocument"
		}
	}

	private static func rootJSONObject(_ payload: DocumentPayload) throws -> [String: Any] {
		let object = try JSONSerialization.jsonObject(with: payload.jsonUTF8Data())
		guard let result = object as? [String: Any] else {
			throw ComponentPathError.invalidPath("/")
		}
		return result
	}

	private static func field(
		named name: String,
		in descriptor: ProtobufSchema.MessageDescriptor,
		at parent: String,
	) throws -> ProtobufSchema.FieldDescriptor {
		guard let field = descriptor.fieldsByName[name] else {
			throw ComponentPathError.unsupported(field: name, at: parent)
		}
		return field
	}

	private static func messageValue(
		for field: ProtobufSchema.FieldDescriptor,
		in object: [String: Any],
	) -> [String: Any]? {
		(object[field.jsonName] ?? object[field.protoName]) as? [String: Any]
	}

	private static func select(
		_ field: ProtobufSchema.FieldDescriptor,
		selector: ComponentPath.Selector?,
		in object: [String: Any],
		parent: String,
		indexOrder: ComponentIndexOrder? = nil,
	) throws -> (index: Int, object: [String: Any], canonical: String) {
		guard let selector else { throw ComponentPathError.selectorRequired(field: field.protoName, at: parent) }
		let rawValues = (object[field.jsonName] ?? object[field.protoName]) as? [Any] ?? []
		let values = rawValues.compactMap { $0 as? [String: Any] }
		guard let typeName = field.typeName else {
			throw ComponentPathError.unsupported(field: field.protoName, at: parent)
		}
		let elementDescriptor = try ProtobufSchema.bundled().message(named: typeName)
		let matches: [Int]
		switch selector {
		case let .index(index):
			let order = indexOrder ?? ComponentIndexOrder(storageCount: values.count)
			matches = order.storageIndex(atPathIndex: index).map { [$0] } ?? []
		case let .field(key, value):
			matches = values.indices.filter { index in
				if key == "uuid" {
					return uuid(in: values[index]) == value
				}
				if key == "name", let name = name(in: values[index]) {
					return name == value
				}
				guard let selectorField = elementDescriptor.fieldsByName[key],
				      !selectorField.isMessage,
				      !selectorField.isRepeated,
				      let scalar = scalarValue(for: selectorField, in: values[index])
				else {
					return false
				}
				return scalarMatches(scalar, selector: value)
			}
		}
		guard matches.count == 1, let index = matches.first else {
			let order = indexOrder ?? ComponentIndexOrder(storageCount: values.count)
			let identities = values.map { uuid(in: $0) ?? "" }
			let candidates = order.storageIndices.map { index in
				ComponentPathBuilder.repeatedPath(
					parent: parent,
					field: field.protoName,
					storageIndex: index,
					identities: identities,
					order: order,
				)
			}
			throw ComponentPathError.noMatch(path: parent + (parent == "/" ? "" : "/") + field.protoName, candidates: candidates)
		}
		let identities = values.map { uuid(in: $0) ?? "" }
		let canonicalSelector = ComponentPathBuilder.selector(
			storageIndex: index,
			identities: identities,
			order: indexOrder,
		)
		return (index, values[index], ComponentPathBuilder.selectorDescription(canonicalSelector))
	}

	private static func uuid(in object: [String: Any]) -> String? {
		if let value = object["uuid"] as? [String: Any], let string = value["string"] as? String {
			return string
		}
		for wrapper in ["group", "element", "baseSlide", "base_slide"] {
			if let nested = object[wrapper] as? [String: Any], let string = uuid(in: nested) {
				return string
			}
		}
		return nil
	}

	private static func name(in object: [String: Any]) -> String? {
		if let name = object["name"] as? String {
			return name
		}
		for wrapper in ["group", "element"] {
			if let nested = object[wrapper] as? [String: Any], let name = name(in: nested) {
				return name
			}
		}
		return nil
	}

	private static func scalarValue(
		for field: ProtobufSchema.FieldDescriptor,
		in object: [String: Any],
	) -> Any? {
		if let value = object[field.jsonName] ?? object[field.protoName] {
			return value
		}
		return switch field.type {
		case .bool: NSNumber(value: false)
		case .string, .bytes: ""
		case .double, .float,
		     .int64, .uint64, .int32, .fixed64, .fixed32,
		     .uint32, .sfixed32, .sfixed64, .sint32, .sint64: NSNumber(value: 0)
		default: nil
		}
	}

	private static func scalarMatches(_ scalar: Any, selector: String) -> Bool {
		if let string = scalar as? String {
			return string == selector
		}
		if let number = scalar as? NSNumber {
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				return (number.boolValue ? "true" : "false") == selector.lowercased()
			}
			guard let selectorNumber = Decimal(string: selector) else { return false }
			return number.decimalValue == selectorNumber
		}
		return false
	}
}
