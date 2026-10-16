import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native menu key-mapping projections")
struct NativeKeyMappingProjectionTests {
	@Test func nativeMenuControlRetainsTargetModifiersAndSourceHistory() throws {
		let before = try stream("native-before"), after = try stream("native-menu-key")
		let reopened = try stream("native-reopened")
		#expect(after.snapshot == reopened.snapshot && after.versionVector == reopened.versionVector)
		let empty = try Rv_Data_KeyMappingDocument(serializedBytes: before.protobufProjection().protobuf)
		#expect(empty.keymappings.isEmpty)
		let original = try after.decodedValue(), projection = try after.protobufProjection()
		try projection.requireComplete()
		let document = try Rv_Data_KeyMappingDocument(serializedBytes: projection.protobuf)
		let mapping = try #require(document.keymappings.first)
		#expect(document.keymappings.count == 1)
		#expect(mapping.targetIdentifier == .menuItem(command))
		#expect(mapping.keyboard.keyEquivalent == "k")
		#expect(mapping.keyboard.keyEquivalentModifierFlags.map(\.rawValue) == [3, 1, 0])
		#expect(mapping.hasMidi && mapping.midi.channel == 0 && mapping.midi.pitch == 0 && mapping.midi.velocity == 0)
		#expect(try after.decodedValue() == original && projection.source == original)
		#expect(throws: NativeSemanticError.self) { try projection.payload() }
	}

	@Test func unresolvedCategoriesMismatchedTargetsAndDuplicateLogicalKeysRemainErrors() throws {
		let entries = try mappings(), value = try #require(entries.values.first)
		let invalidKeys = ["not-json", "{}", key(category: "unqualified-category", name: command), key(category: category, name: "DIFFERENT_MENU_COMMAND"), "{\"category\":1,\"name\":\"\(command)\"}"]
		for key in invalidKeys {
			#expect(throws: NativeSemanticError.self) { try NativeKeyMappingProjection.menuEntries([key: value], path: "/root/keymappings") }
		}
		let reordered = "{\"name\":\"\(command)\",\"category\":\"\(category)\"}"
		var duplicate = entries; duplicate[reordered] = value
		#expect(throws: NativeSemanticError.self) { try NativeKeyMappingProjection.menuEntries(duplicate, path: "/root/keymappings") }
		var target = try value.object(at: "/entry")
		target["TargetIdentifier"] = .map(["__tag": .string("group_identifier"), "group_identifier": .map([:])])
		#expect(throws: NativeSemanticError.self) { try NativeKeyMappingProjection.menuEntries([key(category: category, name: command): .map(target)], path: "/root/keymappings") }
	}

	@Test func unknownEntryFieldsRemainVisibleAndPreventCompleteInspection() throws {
		var entries = try mappings()
		let key = try #require(entries.keys.first)
		var entry = try #require(entries[key]).object(at: "/entry")
		entry["future_target_policy"] = .map(["reference": .string("owned unknown reference")])
		var target = try entry.required("TargetIdentifier", at: "/entry").object(at: "/entry/TargetIdentifier")
		target["future_reference"] = .string("owned unknown oneof reference")
		entry["TargetIdentifier"] = .map(target)
		entries[key] = .map(entry)
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		_ = try encoder.encode(.map(["keymappings": .map(entries)]), message: "rv.data.KeyMappingDocument", path: "/root")
		#expect(encoder.issues.contains { $0.path.hasSuffix("/future_target_policy") })
		#expect(encoder.issues.contains { $0.path.hasSuffix("/TargetIdentifier/future_reference") })
	}

	private func mappings() throws -> [String: NativeWorkspaceValue] {
		try stream("native-menu-key").decodedValue().object(at: "/").required("root", at: "/").object(at: "/root").required("keymappings", at: "/root").object(at: "/root/keymappings")
	}

	private func key(category: String, name: String) -> String {
		"{\"category\":\"\(category)\",\"name\":\"\(name)\"}"
	}

	private var category: String {
		"KEYMAPPING_PREFERENCES_SECTION_HEADER_MENU_SUFFIX_title"
	}

	private var command: String {
		"MAIN_MENU_APPLICATION_ABOUT_PROPRESENTER_title"
	}

	private func stream(_ name: String) throws -> NativeWorkspaceStream {
		let base = fixtures.appendingPathComponent(name), data = try Data(contentsOf: base.appendingPathExtension("loro"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "e17451e8-5d76-5dfc-92ed-166f636dac6d")), scope: .shared, kind: "KeyMappings", corePath: nil, availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: base.appendingPathExtension("vector")), lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/KeyMappings")
	}
}
