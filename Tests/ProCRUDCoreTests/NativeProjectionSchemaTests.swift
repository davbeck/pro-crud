import Foundation
import ProPresenterProto
import SwiftProtobuf
import Testing
@testable import ProCRUDCore

@Suite("Versioned native protobuf projection")
struct NativeProjectionSchemaTests {
	@Test func nativeStorageAnnotationsAndChangedTypesRemainVersioned() throws {
		let legacy = try ProtobufSchema.bundled()
		let native = try ProtobufSchema.bundled(version: .v22)
		#expect(try legacy.message(named: "rv.data.Presentation").fieldsByName["cue_group_placements"] == nil)
		#expect(try native.message(named: "rv.data.Presentation").fieldsByName["cue_group_placements"]?.isNativeTree == true)
		#expect(try native.message(named: "rv.data.Presentation").fieldsByName["cues"]?.nativeMapKey == "uuid")
		#expect(try native.message(named: "rv.data.Graphics.Text").fieldsByName["alternate_texts"]?.nativeMapKey == "key")
		#expect(try legacy.message(named: "rv.data.KeyMapping").fieldsByName["cue_identifier"]?.typeName == "rv.data.CollectionElementType")
		#expect(try native.message(named: "rv.data.KeyMapping").fieldsByName["cue_identifier"]?.typeName == "rv.data.KeyMapping.CollectionElementTypeKey")
		#expect(try native.message(named: "rv.data.TimedPlayback.Sequence").fieldsByName["presentations"]?.isRepeated == true)
	}

	@Test func unknownNativeFieldsProducePathsInsteadOfSilentLoss() throws {
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		_ = try encoder.encode(.map(["new_property": .binary(Data([1, 2, 3]))]), message: "rv.data.Color", path: "/color")
		#expect(encoder.issues.map(\.path) == ["/color/new_property"])
	}

	@Test func binaryRTFAndDefaultValuedOneofRemainTyped() throws {
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let rtf = Data([0, 1, 255, 10, 123, 125])
		let data = try encoder.encode(.map(["rtf_data": .binary(rtf)]), message: "rv.data.Graphics.Text", path: "/text")
		#expect(try Rv_Data_Graphics.Text(serializedBytes: data).rtfData == rtf)
		let url = try encoder.encode(.map(["Storage": .map(["__tag": .string("relative_path"), "relative_path": .string("")])]), message: "rv.data.URL", path: "/url")
		#expect(try Rv_Data_URL(serializedBytes: url).storage == .relativePath(""))
		#expect(encoder.issues.isEmpty)
	}

	@Test func signedScalarsAndNativeBuildOrderEncodeWithoutTruncation() throws {
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let range = try encoder.encode(.map(["start": .integer(-7), "end": .integer(12)]), message: "rv.data.IntRange", path: "/range")
		#expect(try Rv_Data_IntRange(serializedBytes: range).start == -7)
		let id = UUID()
		let slide = try encoder.encode(.map(["element_build_order_v2": .list([.string(id.uuidString), .string(id.uuidString)])]), message: "rv.data.Slide", path: "/slide")
		#expect(try Rv_Data_Slide(serializedBytes: slide).elementBuildOrder.map(\.string) == [id.uuidString, id.uuidString])
		#expect(encoder.issues.isEmpty)
	}

	@Test func repeatedTimelinePresentationsDoNotCollapseToOne() throws {
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let data = try encoder.encode(.map(["presentations": .list([.map(["name": .string("First")]), .map(["name": .string("Second")])])]), message: "rv.data.TimedPlayback.Sequence", path: "/timeline")
		let fields = try ProtobufJSONPatcher.WireField.parse(data).filter { $0.number == 3 }
		#expect(fields.count == 2)
		#expect(try fields.compactMap(\.payload).map { try Rv_Data_Presentation(serializedBytes: $0).name } == ["First", "Second"])
	}

	@Test func keyedMapsValidateTheirEmbeddedIdentity() throws {
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let value: NativeWorkspaceValue = .map(["alternate_texts": .map(["screen": .map(["key": .string("other")])])])
		#expect(throws: NativeSemanticError.self) { try encoder.encode(value, message: "rv.data.Graphics.Text", path: "/text") }
	}
}
