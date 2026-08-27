import Foundation
import SwiftProtobuf

struct ProtobufSchema {
	struct MessageDescriptor {
		var name: String
		var fields: [FieldDescriptor]

		var fieldsByName: [String: FieldDescriptor] {
			var result: [String: FieldDescriptor] = [:]
			for field in fields {
				result[field.protoName] = field
				result[field.jsonName] = field
			}
			return result
		}
	}

	struct FieldDescriptor: Equatable {
		var protoName: String
		var jsonName: String
		var number: Int
		var type: Google_Protobuf_FieldDescriptorProto.TypeEnum
		var typeName: String?
		var isRepeated: Bool
		var oneof: Int?

		var isMessage: Bool {
			type == .message
		}
	}

	static func bundled() throws -> ProtobufSchema {
		let data = try BundledProtobufSchema.data()
		return try ProtobufSchema(descriptorSet: Google_Protobuf_FileDescriptorSet(serializedBytes: data))
	}

	var descriptorSet: Google_Protobuf_FileDescriptorSet
	var messages: [String: MessageDescriptor]

	init(descriptorSet: Google_Protobuf_FileDescriptorSet) throws {
		self.descriptorSet = descriptorSet
		var messages: [String: MessageDescriptor] = [:]
		for file in descriptorSet.file {
			Self.add(messages: file.messageType, prefix: file.package, into: &messages)
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
	) {
		for message in source {
			let typeName = prefix.isEmpty ? message.name : "\(prefix).\(message.name)"
			let fields = message.field.map { field in
				FieldDescriptor(
					protoName: field.name,
					jsonName: field.jsonName.isEmpty ? jsonName(for: field.name) : field.jsonName,
					number: Int(field.number),
					type: field.type,
					typeName: field.typeName.isEmpty ? nil : String(field.typeName.drop(while: { $0 == "." })),
					isRepeated: field.label == .repeated,
					oneof: field.hasOneofIndex ? Int(field.oneofIndex) : nil,
				)
			}
			result[typeName] = MessageDescriptor(name: typeName, fields: fields)
			add(messages: message.nestedType, prefix: typeName, into: &result)
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
