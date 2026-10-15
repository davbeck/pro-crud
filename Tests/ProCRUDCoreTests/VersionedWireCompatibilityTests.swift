import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Versioned timeline and mapping compatibility")
struct VersionedWireCompatibilityTests {
	@Test(arguments: ProPresenterTargetVersion.allCases)
	func commonKeyMappingKeepsUUIDAndNameWithoutConversion(target: ProPresenterTargetVersion) throws {
		let id = UUID().uuidString
		let value: NativeWorkspaceValue = .map(["TargetIdentifier": .map(["__tag": .string("cue_identifier"), "cue_identifier": .map(["parameter_uuid": .string(id), "parameter_name": .string("Opening")])])])
		var old = try NativeProtobufEncoder(schema: .baseline21())
		var new = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let bytes = try old.encode(value, message: "rv.data.KeyMapping", path: "/mapping")
		#expect(try new.encode(value, message: "rv.data.KeyMapping", path: "/mapping") == bytes)
		let report = try DocumentCompatibility.analyze(protobuf: bytes, messageType: "rv.data.KeyMapping", target: target)
		#expect(report.canWrite)
		#expect(report.issues.isEmpty)
		let decoded = try Rv_Data_KeyMapping(serializedBytes: bytes)
		#expect(decoded.cueIdentifier.parameterUuid.string == id)
		#expect(decoded.cueIdentifier.parameterName == "Opening")
	}

	@Test func scoped21MappingIsPreservableIn21AndRejectedFor22() throws {
		var encoder = try NativeProtobufEncoder(schema: .baseline21())
		let value: NativeWorkspaceValue = .map(["TargetIdentifier": .map(["__tag": .string("cue_identifier"), "cue_identifier": .map(["parameter_name": .string("Opening"), "parent_collection": .map(["parameter_name": .string("Service")])])])])
		let bytes = try encoder.encode(value, message: "rv.data.KeyMapping", path: "/mapping")
		let old = try DocumentCompatibility.analyze(protobuf: bytes, messageType: "rv.data.KeyMapping", target: .v21, sourceApplicationMajorVersion: 21)
		#expect(old.canWrite)
		#expect(old.issues.isEmpty)
		let new = try DocumentCompatibility.analyze(protobuf: bytes, messageType: "rv.data.KeyMapping", target: .v22, sourceApplicationMajorVersion: 21)
		#expect(!new.canWrite)
		#expect(new.issues.map(\.feature) == ["key-mapping-parent-scope"])
		#expect(new.issues[0].componentPath == "/cue_identifier/parent_collection")
		#expect(new.issues[0].sourceApplicationMajorVersion == 21)
		// The retained historical type keeps the parent scope opaque without
		// deleting it; the compatibility layer supplies the versioned meaning.
		#expect(try Rv_Data_KeyMapping(serializedBytes: bytes).serializedData() == bytes)
	}

	@Test(arguments: ProPresenterTargetVersion.allCases)
	func singleTimelinePresentationHasTheSameWireRepresentation(target: ProPresenterTargetVersion) throws {
		var old = try NativeProtobufEncoder(schema: .baseline21())
		var new = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let presentation: NativeWorkspaceValue = .map(["name": .string("One Presentation")])
		let bytes = try old.encode(.map(["presentation": presentation]), message: "rv.data.TimedPlayback.Sequence", path: "/timeline")
		#expect(try new.encode(.map(["presentations": .list([presentation])]), message: "rv.data.TimedPlayback.Sequence", path: "/timeline") == bytes)
		let report = try DocumentCompatibility.analyze(protobuf: bytes, messageType: "rv.data.TimedPlayback.Sequence", target: target)
		#expect(report.canWrite)
		#expect(report.issues.isEmpty)
	}

	@Test func multiPresentationTimelineReportsCardinalityAndItemReferenceLosses() throws {
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let first = UUID().uuidString
		let second = UUID().uuidString
		let value: NativeWorkspaceValue = .map([
			"presentations": .list([.map(["uuid": .string(first), "name": .string("First")]), .map(["uuid": .string(second), "name": .string("Second")])]),
			"sequence": .list([.map(["presentation_uuid": .string(second)])]),
		])
		let bytes = try encoder.encode(value, message: "rv.data.TimedPlayback.Sequence", path: "/timeline")
		let modern = try DocumentCompatibility.analyze(protobuf: bytes, messageType: "rv.data.TimedPlayback.Sequence", target: .v22, sourceApplicationMajorVersion: 22)
		#expect(modern.canWrite)
		#expect(modern.issues.isEmpty)
		let old = try DocumentCompatibility.analyze(protobuf: bytes, messageType: "rv.data.TimedPlayback.Sequence", target: .v21, sourceApplicationMajorVersion: 22)
		#expect(!old.canWrite)
		#expect(Set(old.issues.map(\.feature)) == ["multi-presentation-timeline", "timeline-presentation-reference"])
		#expect(old.issues.allSatisfy { $0.availableConversion == "unsupported" && $0.sourceApplicationMajorVersion == 22 })
		#expect(try Rv_Data_TimedPlayback.Sequence(serializedBytes: bytes).serializedData() == bytes)
	}

	@Test func nestedTimelineDependenciesAreStillAnalyzed() throws {
		// Sequence.presentations=3 contains a Presentation with the active
		// cue_group_placements=24 field. Use its wire representation directly;
		// native materialization deliberately adapts that tree to old arrays.
		let bytes = Data([0x1A, 0x03, 0xC2, 0x01, 0x00])
		let report = try DocumentCompatibility.analyze(protobuf: bytes, messageType: "rv.data.TimedPlayback.Sequence", target: .v22)
		#expect(report.issues.map(\.feature) == ["cue-group-placement-tree"])
		#expect(!report.canWrite)
	}
}
