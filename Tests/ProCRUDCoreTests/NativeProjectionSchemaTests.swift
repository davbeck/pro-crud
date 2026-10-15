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

	@Test func exact21BaselineSeparatesStaleVendorFieldsFrom22Changes() throws {
		let baseline = try ProtobufSchema.baseline21()
		let native = try ProtobufSchema.bundled(version: .v22)
		#expect(try baseline.message(named: "rv.data.ProPresenterScreen").fieldsByName["rendering_enabled"]?.number == 9)
		#expect(try baseline.message(named: "rv.data.TimedPlayback.Sequence").fieldsByName["presentation"]?.isRepeated == false)
		#expect(try native.message(named: "rv.data.TimedPlayback.Sequence").fieldsByName["presentations"]?.isRepeated == true)
		#expect(try baseline.message(named: "rv.data.TimedPlayback.Sequence.SequenceItem").fieldsByName["presentation_uuid"] == nil)
		#expect(try native.message(named: "rv.data.TimedPlayback.Sequence.SequenceItem").fieldsByName["presentation_uuid"]?.number == 8)
		#expect(try baseline.message(named: "rv.data.Presentation").fieldsByName["cue_group_placements"] == nil)
	}

	@Test func typed21TextCatchUpMatchesThePinnedBaselineWireLayouts() throws {
		let baseline = try ProtobufSchema.baseline21()
		var encoder = NativeProtobufEncoder(schema: baseline)
		let style = try encoder.encode(.map(["ligature_style": .integer(1)]), message: "rv.data.Graphics.Text.Attributes", path: "/text")
		let attributes = try Rv_Data_Graphics.Text.Attributes(serializedBytes: style)
		#expect(attributes.ligatureStyle == .none)
		#expect(try attributes.serializedData() == style)
		let mode = try encoder.encode(.map(["Attribute": .map(["__tag": .string("character_size_mode"), "character_size_mode": .integer(2)])]), message: "rv.data.Graphics.Text.Attributes.CustomAttribute", path: "/custom")
		#expect(try Rv_Data_Graphics.Text.Attributes.CustomAttribute(serializedBytes: mode).characterSizeMode == .scaledByDocumentWidth)
		let font = try encoder.encode(.map(["Attribute": .map(["__tag": .string("original_font"), "original_font": .map(["name": .string("AvenirNext-Regular"), "size": .number(28), "family": .string("Avenir Next")])])]), message: "rv.data.Graphics.Text.Attributes.CustomAttribute", path: "/custom")
		let custom = try Rv_Data_Graphics.Text.Attributes.CustomAttribute(serializedBytes: font)
		#expect(custom.originalFont.name == "AvenirNext-Regular")
		#expect(custom.originalFont.size == 28)
		#expect(try custom.serializedData() == font)
		let retained = try ProtobufSchema.bundled().message(named: "rv.data.Graphics.Text.Attributes.Font")
		let moved = try baseline.message(named: "rv.data.Font")
		#expect(retained.fields.map(\.number) == moved.fields.map(\.number))
		#expect(retained.fields.map(\.type) == moved.fields.map(\.type))
		#expect(encoder.issues.isEmpty)
	}

	@Test func typed21ScreenFalsePresenceIsDifferentFromAbsence() throws {
		var encoder = try NativeProtobufEncoder(schema: .baseline21())
		let bytes = try encoder.encode(.map(["RenderingEnabledOptional": .map(["__tag": .string("rendering_enabled"), "rendering_enabled": .boolean(false)])]), message: "rv.data.ProPresenterScreen", path: "/screen")
		let screen = try Rv_Data_ProPresenterScreen(serializedBytes: bytes)
		#expect(screen.renderingEnabledOptional == .renderingEnabled(false))
		#expect(Rv_Data_ProPresenterScreen().renderingEnabledOptional == nil)
		#expect(try screen.serializedData() == bytes)
	}

	@Test func playlistArrangementNameMatchesThe21Baseline() throws {
		var encoder = try NativeProtobufEncoder(schema: .baseline21())
		let bytes = try encoder.encode(.map(["arrangement_name": .string("Verse and Chorus")]), message: "rv.data.PlaylistItem.Presentation", path: "/presentation")
		let link = try Rv_Data_PlaylistItem.Presentation(serializedBytes: bytes)
		#expect(link.arrangementName == "Verse and Chorus")
		#expect(try link.serializedData() == bytes)
		#expect(encoder.issues.isEmpty)
	}

	@Test func keyMappingCommonFieldsRemainWireCompatibleWithoutInventedUUIDConversion() throws {
		let baseline = try ProtobufSchema.baseline21()
		let native = try ProtobufSchema.bundled(version: .v22)
		let old = try baseline.message(named: "rv.data.CollectionElementType")
		let new = try native.message(named: "rv.data.KeyMapping.CollectionElementTypeKey")
		for descriptor in [old, new] {
			#expect(descriptor.fieldsByName["parameter_uuid"]?.number == 1)
			#expect(descriptor.fieldsByName["parameter_uuid"]?.typeName == "rv.data.UUID")
			#expect(descriptor.fieldsByName["parameter_name"]?.number == 2)
			#expect(descriptor.fieldsByName["parameter_name"]?.type == .string)
		}
		#expect(old.fieldsByName["parent_collection"]?.number == 3)
		#expect(new.fieldsByName["parent_collection"] == nil)
		let id = UUID().uuidString
		let key: NativeWorkspaceValue = .map(["parameter_uuid": .string(id), "parameter_name": .string("Opening cue")])
		var legacyEncoder = NativeProtobufEncoder(schema: baseline)
		var nativeEncoder = NativeProtobufEncoder(schema: native)
		let legacy = try legacyEncoder.encode(key, message: old.name, path: "/key")
		let current = try nativeEncoder.encode(key, message: new.name, path: "/key")
		#expect(legacy == current)
		let decoded = try Rv_Data_CollectionElementType(serializedBytes: current)
		#expect(decoded.parameterUuid.string == id)
		#expect(decoded.parameterName == "Opening cue")
	}

	@Test func retainedDecoderPreservesRepeatedTimelineMessagesThroughKnownFieldEdits() throws {
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let bytes = try encoder.encode(.map(["presentations": .list([
			.map(["name": .string("First"), "notes": .string("First notes")]),
			.map(["name": .string("Second")]),
		])]), message: "rv.data.TimedPlayback.Sequence", path: "/timeline")
		let before = try ProtobufJSONPatcher.WireField.parse(bytes).filter { $0.number == 3 }.map(\.raw)
		var sequence = try Rv_Data_TimedPlayback.Sequence(serializedBytes: bytes)
		sequence.contentDestination = .announcements
		let after = try ProtobufJSONPatcher.WireField.parse(sequence.serializedData()).filter { $0.number == 3 }
		#expect(after.map(\.raw) == before)
		#expect(try after.compactMap(\.payload).map { try Rv_Data_Presentation(serializedBytes: $0).name } == ["First", "Second"])
		// A singular-message decoder would merge the payloads and silently retain
		// the last name plus fields from the first presentation.
		let merged = try Rv_Data_Presentation(serializedBytes: after.compactMap(\.payload).reduce(into: Data()) { $0.append($1) })
		#expect(merged.name == "Second")
		#expect(merged.notes == "First notes")
	}

	@Test func keyedMapsValidateTheirEmbeddedIdentity() throws {
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let value: NativeWorkspaceValue = .map(["alternate_texts": .map(["screen": .map(["key": .string("other")])])])
		#expect(throws: NativeSemanticError.self) { try encoder.encode(value, message: "rv.data.Graphics.Text", path: "/text") }
	}
}
