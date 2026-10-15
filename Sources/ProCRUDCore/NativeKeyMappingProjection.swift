import Foundation

/// The native map key is a serialized UI identity, not a protobuf field.
/// Only the independently observed menu category is qualified here.
enum NativeKeyMappingProjection {
	static func menuEntries(_ entries: [String: NativeWorkspaceValue], path: String) throws -> [NativeWorkspaceValue] {
		var targets: Set<String> = []
		return try entries.keys.sorted().map { key in
			let value = try entries.required(key, at: path)
			let target = try menuTarget(value, key: key, path: path)
			guard targets.insert(target).inserted else { throw NativeSemanticError.duplicateIdentity(path: path, identity: target) }
			return value
		}
	}

	private static func menuTarget(_ value: NativeWorkspaceValue, key: String, path: String) throws -> String {
		let fieldPath = "\(path)/\(key)"
		let identity: [String: String]
		do {
			guard let object = try JSONSerialization.jsonObject(with: Data(key.utf8)) as? [String: String], Set(object.keys) == ["category", "name"] else {
				throw NativeSemanticError.invalidValue(path: fieldPath, expected: "native menu identity with category and name")
			}
			identity = object
		} catch let error as NativeSemanticError {
			throw error
		} catch {
			throw NativeSemanticError.invalidValue(path: fieldPath, expected: "serialized native menu identity")
		}
		guard identity["category"] == "KEYMAPPING_PREFERENCES_SECTION_HEADER_MENU_SUFFIX_title" else {
			throw NativeSemanticError.unsupportedNode(path: fieldPath, kind: "unqualified native key-mapping category")
		}
		let entry = try value.object(at: fieldPath)
		let target = try entry.required("TargetIdentifier", at: fieldPath).tagged(at: "\(fieldPath)/TargetIdentifier")
		guard target.tag == "menu_item" else { throw NativeSemanticError.unsupportedNode(path: fieldPath, kind: "unqualified native key-mapping target \(target.tag)") }
		let name = try target.value.text(at: "\(fieldPath)/TargetIdentifier/menu_item")
		guard !name.isEmpty, identity["name"] == name else { throw NativeSemanticError.invalidValue(path: fieldPath, expected: "menu map key matching its stored TargetIdentifier") }
		return name
	}
}
