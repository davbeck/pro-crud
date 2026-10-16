import Foundation
import SwiftProtobuf

struct ProtobufSchema: Sendable {
	struct MessageDescriptor: Sendable {
		var name: String
		var fields: [FieldDescriptor]
		var oneofNames: [String] = []
		var isMapEntry = false
		var isNativeAtomic = false

		var fieldsByName: [String: FieldDescriptor] {
			var result: [String: FieldDescriptor] = [:]
			for field in fields {
				result[field.protoName] = field
				result[field.jsonName] = field
			}
			return result
		}
	}

	struct FieldDescriptor: Equatable, Sendable {
		var protoName: String
		var jsonName: String
		var number: Int
		var type: Google_Protobuf_FieldDescriptorProto.TypeEnum
		var typeName: String?
		var isRepeated: Bool
		var oneof: Int?
		var nativeMapKey: String?
		var isNativeTree = false
		var isNativeContainer = false

		var isMessage: Bool {
			type == .message
		}
	}

	static func bundled(version: ProPresenterTargetVersion = .v21) throws -> ProtobufSchema {
		try (version == .v21 ? legacy : native).get()
	}

	private static let legacy = Result { try load(.v21) }
	private static let native = Result { try load(.v22) }
	/// Exact upstream 21.4 evidence, independent of the retained generated model.
	/// Do not substitute this for the patcher's descriptor: its Swift view still
	/// deliberately leaves newer fields opaque, including timeline field 3.
	static func baseline21() throws -> Self {
		try baseline.get()
	}

	private static let baseline = Result {
		try Self(descriptorSet: Google_Protobuf_FileDescriptorSet(serializedBytes: BundledProtobufSchema.baseline21()))
	}

	private static func load(_ version: ProPresenterTargetVersion) throws -> Self {
		try Self(descriptorSet: Google_Protobuf_FileDescriptorSet(serializedBytes: BundledProtobufSchema.data(version: version)))
	}

	var descriptorSet: Google_Protobuf_FileDescriptorSet
	var messages: [String: MessageDescriptor]

	init(descriptorSet: Google_Protobuf_FileDescriptorSet) throws {
		self.descriptorSet = descriptorSet
		var messages: [String: MessageDescriptor] = [:]
		for file in descriptorSet.file {
			try Self.add(messages: file.messageType, prefix: file.package, into: &messages)
		}
		self.messages = messages
	}

	func message(named name: String) throws -> MessageDescriptor {
		guard let message = messages[name] else {
			throw DocumentEditError.unsupportedPatchValue("No protobuf descriptor is bundled for \(name).")
		}
		return message
	}

	func mergedJSON(
		original: [String: Any],
		patch: [String: Any],
		messageType: String,
	) throws -> [String: Any] {
		let descriptor = try message(named: messageType)
		let fieldsByName = descriptor.fieldsByName
		var result = original
		for (key, value) in patch {
			guard let field = fieldsByName[key] else {
				throw DocumentEditError.unsupportedPatchValue("\(key) is not a field of \(messageType).")
			}
			result.removeValue(forKey: field.protoName)
			result.removeValue(forKey: field.jsonName)
			if let oneof = field.oneof {
				for sibling in descriptor.fields where sibling.oneof == oneof {
					result.removeValue(forKey: sibling.protoName)
					result.removeValue(forKey: sibling.jsonName)
				}
			}
			guard !(value is NSNull) else { continue }
			if let nestedPatch = value as? [String: Any],
			   field.isMessage,
			   !field.isRepeated,
			   let nestedType = field.typeName
			{
				let existing = (original[field.jsonName] ?? original[field.protoName]) as? [String: Any] ?? [:]
				result[field.jsonName] = try mergedJSON(
					original: existing,
					patch: nestedPatch,
					messageType: nestedType,
				)
			} else {
				result[field.jsonName] = removingNulls(from: value)
			}
		}
		return result
	}

	private static func add(
		messages source: [Google_Protobuf_DescriptorProto],
		prefix: String,
		into result: inout [String: MessageDescriptor],
	) throws {
		for message in source {
			let typeName = prefix.isEmpty ? message.name : "\(prefix).\(message.name)"
			let fields = try message.field.map { field in
				let options = try ProtobufJSONPatcher.WireField.parse(field.options.serializedData())
				return FieldDescriptor(
					protoName: field.name,
					jsonName: field.jsonName.isEmpty ? jsonName(for: field.name) : field.jsonName,
					number: Int(field.number),
					type: field.type,
					typeName: field.typeName.isEmpty ? nil : String(field.typeName.drop(while: { $0 == "." })),
					isRepeated: field.label == .repeated,
					oneof: field.hasOneofIndex ? Int(field.oneofIndex) : nil,
					nativeMapKey: options.first(where: { $0.number == 51302 })?.payload.flatMap { String(data: $0, encoding: .utf8) },
					isNativeTree: options.first(where: { $0.number == 51304 })?.varint == 1,
					isNativeContainer: options.first(where: { $0.number == 51303 })?.varint == 1,
				)
			}
			let options = try ProtobufJSONPatcher.WireField.parse(message.options.serializedData())
			result[typeName] = MessageDescriptor(name: typeName, fields: fields, oneofNames: message.oneofDecl.map(\.name), isMapEntry: message.options.mapEntry,
			                                     isNativeAtomic: options.first(where: { $0.number == 51200 })?.varint == 1)
			try add(messages: message.nestedType, prefix: typeName, into: &result)
		}
	}

	private static func jsonName(for protoName: String) -> String {
		let parts = protoName.split(separator: "_")
		guard let first = parts.first else { return protoName }
		return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
	}

	private func removingNulls(from value: Any) -> Any {
		if let object = value as? [String: Any] {
			return object.reduce(into: [String: Any]()) { result, entry in
				guard !(entry.value is NSNull) else { return }
				result[entry.key] = removingNulls(from: entry.value)
			}
		}
		if let values = value as? [Any] {
			return values.map(removingNulls(from:))
		}
		return value
	}
}
