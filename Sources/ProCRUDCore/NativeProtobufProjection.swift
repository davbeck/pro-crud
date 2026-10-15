import Foundation
import ProPresenterProto
import SwiftProtobuf

public struct NativeProjectionIssue: Codable, Sendable, Equatable {
	public let path: String
	public let message: String

	public init(path: String, message: String) {
		self.path = path
		self.message = message
	}
}

/// A read-only interchange view. It is never a replacement for the native
/// document or its Loro history. Unknown native fields remain in `source` and
/// block an export until their representation has been mapped.
public struct NativeProtobufProjection: Sendable {
	public let identity: NativeWorkspaceStream.Identity
	public let source: NativeWorkspaceValue
	public let messageType: String
	public let protobuf: Data
	public let issues: [NativeProjectionIssue]
	public let retainedMetadataPaths: [String]

	public func requireComplete() throws {
		guard issues.isEmpty else { throw NativeProjectionError(issues: issues) }
	}

	public func presentation() throws -> Rv_Data_Presentation {
		try requireComplete()
		guard messageType == Rv_Data_Presentation.protoMessageName else { throw NativeSemanticError.invalidValue(path: identity.documentID.uuidString, expected: "Presentation projection") }
		return try Rv_Data_Presentation(serializedBytes: protobuf)
	}

	public func payload() throws -> DocumentPayload {
		try requireComplete()
		switch messageType {
		case Rv_Data_Presentation.protoMessageName: return try .presentation(Rv_Data_Presentation(serializedBytes: protobuf))
		case Rv_Data_Template.Document.protoMessageName: return try .theme(Rv_Data_Template.Document(serializedBytes: protobuf))
		default: throw NativeSemanticError.invalidValue(path: identity.documentID.uuidString, expected: "supported document projection")
		}
	}
}

public struct NativeProjectionError: Error, CustomStringConvertible, Sendable {
	public let issues: [NativeProjectionIssue]
	public var description: String {
		(["Native content has unmapped interchange fields:"] + issues.map { "\($0.path): \($0.message)" }).joined(separator: "\n")
	}
}

public extension NativeWorkspaceStream {
	func protobufProjection() throws -> NativeProtobufProjection {
		try NativeProtobufProjection.read(identity: identity, source: decodedValue())
	}
}

extension NativeProtobufProjection {
	static func read(identity: NativeWorkspaceStream.Identity, source: NativeWorkspaceValue) throws -> Self {
		guard identity.scope == .shared else { throw NativeSemanticError.invalidValue(path: identity.documentID.uuidString, expected: "shared content stream; client state is not an interchange document") }
		let root = try source.object(at: "/").required("root", at: "/")
		let message: String
		let adapted: NativeWorkspaceValue
		switch identity.kind {
		case "Presentation":
			message = Rv_Data_Presentation.protoMessageName
			guard try root.object(at: "/root").required("uuid", at: "/root").uuid(at: "/root/uuid") == identity.documentID else {
				throw NativeSemanticError.invalidValue(path: "/root/uuid", expected: "native stream identity \(identity.documentID)")
			}
			adapted = try NativeInterchangeAdapter.presentation(root)
		case "Theme":
			message = Rv_Data_Template.Document.protoMessageName
			adapted = root
		default: throw NativeSemanticError.invalidValue(path: identity.documentID.uuidString, expected: "Presentation or Theme stream")
		}
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let data = try encoder.encode(adapted, message: message, path: "/root")
		return .init(identity: identity, source: source, messageType: message, protobuf: data, issues: encoder.issues, retainedMetadataPaths: encoder.metadata)
	}
}

private enum NativeInterchangeAdapter {
	static func presentation(_ value: NativeWorkspaceValue) throws -> NativeWorkspaceValue {
		let layout = try NativePresentationLayout(root: value)
		var root = try value.object(at: "/root")
		root.removeValue(forKey: "cue_group_placements")
		root["cue_groups"] = try .list(layout.groups.map { group in
			var attributes = try group.attributes.object(at: "/root/cue_groups")
			attributes["uuid"] = .string(group.id.uuidString)
			attributes["hotKey"] = attributes.removeValue(forKey: "hot_key")
			return .map(["group": .map(attributes), "cue_identifiers": .list(group.cueIDs.map { .string($0.uuidString) })])
		})
		// Ungrouped placement markers are not expressible as a legacy group.
		// Refuse this projection instead of inventing a new group identity.
		guard layout.master.allSatisfy({ $0.kind == .group }) else { throw NativeSemanticError.unsupportedNode(path: "/root/cue_group_placements", kind: "ungrouped cue interchange") }
		let ids = try layout.orderedCueIDs() + layout.unplacedCueIDs
		root["cues"] = .list(ids.compactMap { layout.cues[$0] })
		root["arrangements"] = try .list(root.required("arrangements", at: "/root").array(at: "/root/arrangements").enumerated().map { offset, value in
			var arrangement = try value.object(at: "/root/arrangements[\(offset)]")
			let ids = try NativePresentationLayout.orderedIDs(arrangement, legacy: "group_identifiers", native: "group_identifiers_v2", path: "/root/arrangements[\(offset)]")
			arrangement.removeValue(forKey: "group_identifiers_v2")
			arrangement["group_identifiers"] = .list(ids.map { .string($0.uuidString) })
			return .map(arrangement)
		})
		return .map(root)
	}
}

/// Descriptor-driven binary encoding avoids JSON's lossy UUID/oneof/bytes
/// coercions. The 22 descriptor is independent of the retained 21 generated
/// types, including changed nested messages and repeated timeline fields.
struct NativeProtobufEncoder {
	let schema: ProtobufSchema
	var issues: [NativeProjectionIssue] = []
	var metadata: [String] = []

	mutating func encode(_ value: NativeWorkspaceValue, message: String, path: String) throws -> Data {
		if message == "rv.data.UUID", case .string = value {
			return try field(1, payload: Data(value.text(at: path).utf8))
		}
		var object = try value.object(at: path)
		if message == "rv.data.Slide", object.optional("element_build_order_v2") != nil {
			let ids = try NativePresentationLayout.orderedIDs(object, legacy: "element_build_order", native: "element_build_order_v2", path: "\(path)/element_build_order")
			object.removeValue(forKey: "element_build_order_v2")
			object["element_build_order"] = .list(ids.map { .string($0.uuidString) })
		}
		let descriptor = try schema.message(named: message)
		for oneof in descriptor.oneofNames {
			guard let wrapper = object.removeValue(forKey: oneof), wrapper != .null else { continue }
			let choices = try wrapper.object(at: "\(path)/\(oneof)")
			guard choices.optional("__tag") != nil else { continue }
			let selected = try wrapper.tagged(at: "\(path)/\(oneof)")
			guard let field = descriptor.fieldsByName[selected.tag], let index = field.oneof, descriptor.oneofNames[index] == oneof else {
				issues.append(.init(path: "\(path)/\(oneof)", message: "Unknown oneof selection \(selected.tag) in \(message)."))
				continue
			}
			if let existing = object.optional(field.protoName), existing != selected.value {
				throw NativeSemanticError.invalidValue(path: "\(path)/\(oneof)", expected: "one active oneof representation")
			}
			object[field.protoName] = selected.value
		}
		let fields = descriptor.fieldsByName
		for key in object.keys.sorted() where fields[key] == nil {
			if key == "value_array_migration_version" {
				metadata.append("\(path)/\(key)")
			} else {
				issues.append(.init(path: "\(path)/\(key)", message: "Native field is absent from the pinned 22 \(message) descriptor; original value retained."))
			}
		}
		var result = Data()
		for descriptor in descriptor.fields.sorted(by: { $0.number < $1.number }) {
			guard let value = object.optional(descriptor.protoName) ?? object.optional(descriptor.jsonName) else { continue }
			let fieldPath = "\(path)/\(descriptor.protoName)"
			if descriptor.isRepeated {
				let values: [NativeWorkspaceValue]
				if descriptor.isNativeTree {
					issues.append(.init(path: fieldPath, message: "A native tree requires a hierarchy adapter before interchange export."))
					continue
				} else if case let .map(entries) = value, let mapKey = descriptor.nativeMapKey {
					values = try entries.keys.sorted().map { key in
						var entry = try entries.required(key, at: fieldPath).object(at: "\(fieldPath)/\(key)")
						if let stored = entry.optional(mapKey), stored != .string(key) {
							throw NativeSemanticError.invalidValue(path: "\(fieldPath)/\(key)", expected: "map key matching \(mapKey)")
						}
						entry[mapKey] = .string(key)
						return .map(entry)
					}
				} else if case let .map(entries) = value, let nested = descriptor.typeName, try schema.message(named: nested).isMapEntry {
					values = entries.keys.sorted().map { .map(["key": .string($0), "value": entries[$0] ?? .null]) }
				} else {
					values = try value.array(at: fieldPath)
				}
				for (index, value) in values.enumerated() {
					try result.append(encodeField(value, descriptor: descriptor, path: "\(fieldPath)[\(index)]"))
				}
			} else {
				try result.append(encodeField(value, descriptor: descriptor, path: fieldPath))
			}
		}
		return result
	}

	private mutating func encodeField(_ value: NativeWorkspaceValue, descriptor: ProtobufSchema.FieldDescriptor, path: String) throws -> Data {
		let number = descriptor.number
		switch descriptor.type {
		case .message:
			guard let type = descriptor.typeName else { throw NativeSemanticError.invalidValue(path: path, expected: "message descriptor") }
			return try field(number, payload: encode(value, message: type, path: path))
		case .string: return try field(number, payload: Data(value.text(at: path).utf8))
		case .bytes:
			guard case let .binary(bytes) = value else { throw NativeSemanticError.invalidValue(path: path, expected: "binary bytes") }
			return field(number, payload: bytes)
		case .bool:
			guard case let .boolean(flag) = value else { throw NativeSemanticError.invalidValue(path: path, expected: "boolean") }
			return varint(UInt64(number << 3)) + varint(flag ? 1 : 0)
		case .double: return try fixed(number, wire: 1, value: numberValue(value, path: path).bitPattern)
		case .float: return try fixed(number, wire: 5, value: Float(numberValue(value, path: path)).bitPattern)
		case .int32, .int64, .enum:
			let integer = try integerValue(value, path: path)
			if descriptor.type != .int64, Int32(exactly: integer) == nil {
				throw NativeSemanticError.invalidValue(path: path, expected: "signed 32-bit integer")
			}
			return varint(UInt64(number << 3)) + varint(UInt64(bitPattern: integer))
		case .uint32, .uint64, .fixed32, .fixed64:
			let unsigned = try unsignedValue(value, path: path)
			guard descriptor.type != .uint32 && descriptor.type != .fixed32 || UInt32(exactly: unsigned) != nil else { throw NativeSemanticError.invalidValue(path: path, expected: "unsigned integer of the declared width") }
			switch descriptor.type {
			case .fixed32: return fixed(number, wire: 5, value: UInt32(truncatingIfNeeded: unsigned))
			case .fixed64: return fixed(number, wire: 1, value: unsigned)
			default: return varint(UInt64(number << 3)) + varint(unsigned)
			}
		case .sint32, .sint64:
			let integer = try integerValue(value, path: path)
			guard descriptor.type == .sint64 || Int32(exactly: integer) != nil else { throw NativeSemanticError.invalidValue(path: path, expected: "signed 32-bit integer") }
			return varint(UInt64(number << 3)) + varint(UInt64(bitPattern: (integer &<< 1) ^ (integer >> 63)))
		case .sfixed32:
			guard let integer = try Int32(exactly: integerValue(value, path: path)) else { throw NativeSemanticError.invalidValue(path: path, expected: "signed 32-bit integer") }
			return fixed(number, wire: 5, value: integer)
		case .sfixed64: return try fixed(number, wire: 1, value: integerValue(value, path: path))
		case .group: throw NativeSemanticError.invalidValue(path: path, expected: "supported protobuf wire type")
		}
	}

	private func numberValue(_ value: NativeWorkspaceValue, path: String) throws -> Double {
		switch value {
		case let .number(value): value
		case let .integer(value): Double(value)
		default: throw NativeSemanticError.invalidValue(path: path, expected: "number")
		}
	}

	private func integerValue(_ value: NativeWorkspaceValue, path: String) throws -> Int64 {
		switch value {
		case let .integer(value): return value
		case let .number(value):
			guard let integer = Int64(exactly: value) else { throw NativeSemanticError.invalidValue(path: path, expected: "exact integer") }
			return integer
		case let .string(value):
			guard let integer = Int64(value) else { throw NativeSemanticError.invalidValue(path: path, expected: "integer string") }
			return integer
		default: throw NativeSemanticError.invalidValue(path: path, expected: "integer")
		}
	}

	private func unsignedValue(_ value: NativeWorkspaceValue, path: String) throws -> UInt64 {
		let integer: UInt64?
		switch value {
		case let .integer(value): integer = UInt64(exactly: value)
		case let .number(value): integer = UInt64(exactly: value)
		case let .string(value): integer = UInt64(value)
		default: integer = nil
		}
		guard let integer else { throw NativeSemanticError.invalidValue(path: path, expected: "unsigned 64-bit integer") }
		return integer
	}

	private func varint(_ value: UInt64) -> Data {
		var value = value
		var result = Data()
		while value > 127 {
			result.append(UInt8(value & 127) | 128); value >>= 7
		}
		result.append(UInt8(value))
		return result
	}

	private func field(_ number: Int, payload: Data) -> Data {
		varint(UInt64(number << 3 | 2)) + varint(UInt64(payload.count)) + payload
	}

	private func fixed(_ number: Int, wire: Int, value: some FixedWidthInteger) -> Data {
		var value = value.littleEndian
		return varint(UInt64(number << 3 | wire)) + withUnsafeBytes(of: &value) { Data($0) }
	}
}
