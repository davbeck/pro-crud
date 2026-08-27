import Foundation
import SwiftProtobuf

enum ProtobufJSONPatcher {
	static func patch<M: Message>(_ message: M, at selection: ComponentSelection, with jsonData: Data) throws -> M {
		let object = try JSONSerialization.jsonObject(with: jsonData)
		guard let patchObject = object as? [String: Any] else {
			throw DocumentEditError.unsupportedPatchValue("Patch JSON must be an object.")
		}
		let candidateRoot = try selection.rootJSON(applying: patchObject)
		let candidateData = try JSONSerialization.data(withJSONObject: candidateRoot, options: [.sortedKeys])
		let candidate = try M(jsonUTF8Data: candidateData)
		let data = try patch(
			original: message.serializedData(),
			candidate: candidate.serializedData(),
			steps: selection.traversal[...],
			messageType: selection.protoMessageName,
			patchFields: patchObject,
		)
		return try M(serializedBytes: data)
	}

	static func patch<M: Message>(_ message: M, with jsonData: Data) throws -> M {
		let object = try JSONSerialization.jsonObject(with: jsonData)
		guard let patchObject = object as? [String: Any] else {
			throw DocumentEditError.unsupportedPatchValue("Patch JSON must be an object.")
		}
		let candidateData = try JSONSerialization.data(withJSONObject: removingNulls(from: patchObject), options: [.sortedKeys])
		let candidate = try M(jsonUTF8Data: candidateData)
		let data = try patch(
			original: message.serializedData(),
			candidate: candidate.serializedData(),
			messageType: M.protoMessageName,
			patchFields: patchObject,
		)
		return try M(serializedBytes: data)
	}

	private static func patch(original: Data, candidate: Data, messageType: String, patchFields: [String: Any]) throws -> Data {
		let descriptor = try ProtobufSchema.bundled().message(named: messageType)
		let fieldsByName = descriptor.fieldsByName
		let originalFields = try WireField.parse(original)
		let candidateFields = try WireField.parse(candidate)
		var fieldsToReplace = Set<Int>()
		var replacements: [Int: [WireField]] = [:]

		for (key, value) in patchFields {
			guard let field = fieldsByName[key] else {
				throw DocumentEditError.unsupportedPatchValue("\(key) is not a field of \(messageType).")
			}
			fieldsToReplace.insert(field.number)
			if let oneof = field.oneof {
				fieldsToReplace.formUnion(descriptor.fields.filter { $0.oneof == oneof }.map(\.number))
			}
			guard !(value is NSNull) else { continue }

			let candidateValues = candidateFields.filter { $0.number == field.number }
			if let nestedPatch = value as? [String: Any], field.isMessage, !field.isRepeated {
				guard let nestedType = field.typeName else {
					throw DocumentEditError.unsupportedPatchValue("Missing protobuf type for \(field.protoName).")
				}
				let originalPayload = originalFields
					.filter { $0.number == field.number }
					.reduce(into: Data()) { $0.append($1.payload ?? Data()) }
				let candidatePayload = candidateValues.last?.payload ?? Data()
				let nestedData = try patch(
					original: originalPayload,
					candidate: candidatePayload,
					messageType: nestedType,
					patchFields: nestedPatch,
				)
				replacements[field.number] = [WireField.lengthDelimited(number: field.number, payload: nestedData)]
			} else {
				replacements[field.number] = candidateValues
			}
		}

		var output = Data()
		for field in originalFields where !fieldsToReplace.contains(field.number) {
			output.append(field.raw)
		}
		for number in replacements.keys.sorted() {
			for field in replacements[number, default: []] {
				output.append(field.raw)
			}
		}
		return output
	}

	private static func patch(
		original: Data,
		candidate: Data,
		steps: ArraySlice<ProtobufTraversalStep>,
		messageType: String,
		patchFields: [String: Any],
	) throws -> Data {
		guard let step = steps.first else {
			return try patch(
				original: original,
				candidate: candidate,
				messageType: messageType,
				patchFields: patchFields,
			)
		}
		let originalFields = try WireField.parse(original)
		let candidateFields = try WireField.parse(candidate)
		let originalMatches = originalFields.indices.filter { originalFields[$0].number == step.fieldNumber }
		let candidateMatches = candidateFields.indices.filter { candidateFields[$0].number == step.fieldNumber }
		guard originalMatches.indices.contains(step.occurrenceIndex),
		      candidateMatches.indices.contains(step.occurrenceIndex),
		      let originalPayload = originalFields[originalMatches[step.occurrenceIndex]].payload,
		      let candidatePayload = candidateFields[candidateMatches[step.occurrenceIndex]].payload
		else {
			throw DocumentEditError.unsupportedPatchValue("Component path no longer matches the serialized protobuf message.")
		}
		let patchedPayload = try patch(
			original: originalPayload,
			candidate: candidatePayload,
			steps: steps.dropFirst(),
			messageType: messageType,
			patchFields: patchFields,
		)
		let replacementIndex = originalMatches[step.occurrenceIndex]
		var output = Data()
		for index in originalFields.indices {
			if index == replacementIndex {
				output.append(WireField.lengthDelimited(number: step.fieldNumber, payload: patchedPayload).raw)
			} else {
				output.append(originalFields[index].raw)
			}
		}
		return output
	}

	private static func removingNulls(from value: Any) -> Any {
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

	private struct WireField {
		var number: Int
		var payload: Data?
		var raw: Data

		static func parse(_ data: Data) throws -> [WireField] {
			var offset = 0
			var fields: [WireField] = []
			while offset < data.count {
				let start = offset
				let key = try readVarint(data, offset: &offset)
				let number = Int(key >> 3)
				let wireType = Int(key & 0x7)
				guard number > 0 else { throw DocumentEditError.unsupportedPatchValue("Invalid protobuf field number 0.") }
				let payload: Data?
				switch wireType {
				case 0:
					_ = try readVarint(data, offset: &offset)
					payload = nil
				case 1:
					try advance(8, in: data, offset: &offset)
					payload = nil
				case 2:
					let length = try readVarint(data, offset: &offset)
					guard length <= UInt64(data.count - offset) else { throw DocumentEditError.unsupportedPatchValue("Truncated protobuf field.") }
					let end = offset + Int(length)
					payload = data.subdata(in: offset ..< end)
					offset = end
				case 5:
					try advance(4, in: data, offset: &offset)
					payload = nil
				default:
					throw DocumentEditError.unsupportedPatchValue("Unsupported protobuf wire type \(wireType).")
				}
				fields.append(WireField(number: number, payload: payload, raw: data.subdata(in: start ..< offset)))
			}
			return fields
		}

		static func lengthDelimited(number: Int, payload: Data) -> WireField {
			var raw = Data()
			appendVarint(UInt64(number << 3 | 2), to: &raw)
			appendVarint(UInt64(payload.count), to: &raw)
			raw.append(payload)
			return WireField(number: number, payload: payload, raw: raw)
		}

		private static func readVarint(_ data: Data, offset: inout Int) throws -> UInt64 {
			var value: UInt64 = 0
			for shift in stride(from: 0, through: 63, by: 7) {
				guard offset < data.count else { throw DocumentEditError.unsupportedPatchValue("Truncated protobuf varint.") }
				let byte = data[offset]
				offset += 1
				value |= UInt64(byte & 0x7F) << UInt64(shift)
				if byte & 0x80 == 0 {
					return value
				}
			}
			throw DocumentEditError.unsupportedPatchValue("Invalid protobuf varint.")
		}

		private static func appendVarint(_ value: UInt64, to data: inout Data) {
			var remaining = value
			while remaining >= 0x80 {
				data.append(UInt8(remaining & 0x7F) | 0x80)
				remaining >>= 7
			}
			data.append(UInt8(remaining))
		}

		private static func advance(_ count: Int, in data: Data, offset: inout Int) throws {
			guard offset + count <= data.count else { throw DocumentEditError.unsupportedPatchValue("Truncated protobuf field.") }
			offset += count
		}
	}
}
