import Foundation
import Loro

/// Creates new native subgraphs from the pinned CRDT annotations. Existing
/// document histories and containers are always edited in place.
enum NativeContainerAccess {
	static func map(_ parent: LoroMap, keys: [String]) throws -> LoroMap {
		var result = parent
		for key in keys {
			guard let child = result.get(key: key)?.asLoroMap() else { throw NativeSemanticError.invalidValue(path: keys.joined(separator: "/"), expected: "native \(key) map") }
			result = child
		}
		return result
	}

	static func atomic(_ value: NativeWorkspaceValue) throws -> LoroValue {
		switch value {
		case .null: return .null
		case let .boolean(value): return .bool(value: value)
		case let .integer(value): return .i64(value: value)
		case let .number(value): return .double(value: value)
		case let .string(value): return .string(value: value)
		case let .binary(value): return .binary(value: value)
		case let .map(value): return try .map(value: value.mapValues(atomic))
		case let .list(value): return try .list(value: value.map(atomic))
		}
	}

	static func write(_ value: NativeWorkspaceValue, to map: LoroMap, message: String) throws {
		let schema = try ProtobufSchema.bundled(version: .v22)
		var encoder = NativeProtobufEncoder(schema: schema)
		_ = try encoder.encode(value, message: message, path: "/new/\(message)")
		guard encoder.issues.isEmpty else { throw NativeProjectionError(issues: encoder.issues) }
		let descriptor = try schema.message(named: message)
		for (key, value) in try value.object(at: "/new/\(message)").sorted(by: { $0.key < $1.key }) {
			if let index = descriptor.oneofNames.firstIndex(of: key) {
				if value == .null {
					try map.insert(key: key, v: LoroValue.null); continue
				}
				let wrapper = try value.object(at: key)
				let child = try map.insertContainer(key: key, child: LoroMap())
				try child.insert(key: "__tag", v: atomic(wrapper["__tag"] ?? .null))
				if let tag = wrapper.optional("__tag") {
					let name = try tag.text(at: key)
					guard let field = descriptor.fields.first(where: { $0.oneof == index && $0.protoName == name }) else { throw NativeSemanticError.unsupportedNode(path: key, kind: "unknown oneof tag") }
					try insert(wrapper.required(name, at: key), key: name, field: field, in: child, schema: schema)
				}
			} else if let field = descriptor.fieldsByName[key] {
				try insert(value, key: key, field: field, in: map, schema: schema)
			} else {
				throw NativeSemanticError.unsupportedNode(path: key, kind: "unmapped native subgraph field")
			}
		}
	}

	private static func insert(_ value: NativeWorkspaceValue, key: String, field: ProtobufSchema.FieldDescriptor, in parent: LoroMap, schema: ProtobufSchema) throws {
		if value == .null {
			try parent.insert(key: key, v: LoroValue.null); return
		}
		guard !field.isNativeTree else { throw NativeSemanticError.unsupportedNode(path: key, kind: "nested tree construction") }
		if field.isRepeated {
			if field.nativeMapKey != nil {
				let map = try parent.insertContainer(key: key, child: LoroMap())
				for (id, child) in try value.object(at: key).sorted(by: { $0.key < $1.key }) {
					if let message = field.typeName, field.isMessage, try !schema.message(named: message).isNativeAtomic {
						try write(child, to: map.insertContainer(key: id, child: LoroMap()), message: message)
					} else {
						try map.insert(key: id, v: atomic(child))
					}
				}
			} else {
				let list = try parent.insertContainer(key: key, child: LoroMovableList())
				for child in try value.array(at: key) {
					if let message = field.typeName, field.isMessage, message != "rv.data.UUID", try !schema.message(named: message).isNativeAtomic {
						try write(child, to: list.pushContainer(child: LoroMap()), message: message)
					} else {
						try list.push(v: atomic(child))
					}
				}
			}
		} else if let message = field.typeName, field.isMessage, message != "rv.data.UUID", try !schema.message(named: message).isNativeAtomic {
			try write(value, to: parent.insertContainer(key: key, child: LoroMap()), message: message)
		} else {
			try parent.insert(key: key, v: atomic(value))
		}
	}
}
