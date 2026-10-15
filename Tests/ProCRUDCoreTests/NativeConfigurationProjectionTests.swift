import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Scoped native configuration projections")
struct NativeConfigurationProjectionTests {
	@Test func remainingConfigurationRootsHaveIndependentReadOnlyViews() throws {
		let empty: LoroValue = .list(value: [])
		let roots: [(String, NativeWorkspaceStream.Scope, String, [String: LoroValue])] = [
			("Calendar", .shared, "rv.data.Calendar", ["events": empty, "active": .bool(value: false)]),
			("Ccli", .shared, "rv.data.CCLIDocument", ["layout": .map(value: ["tokens_v2": empty]), "value_array_migration_version": .string(value: "1")]),
			("ClearGroups", .shared, "rv.data.ClearGroupsDocument", ["groups": empty]),
			("CommunicationDevices", .shared, "rv.data.ProPresenterCommunications", ["devices": empty]),
			("CommunicationDevices", .client, "rv.data.ProPresenterLocalCommunications", ["devices": empty]),
			("Groups", .shared, "rv.data.ProGroupsDocument", ["groups": empty]),
			("KeyMappings", .shared, "rv.data.KeyMappingDocument", ["keymappings": .map(value: [:])]),
			("Labels", .shared, "rv.data.ProLabelsDocument", ["labels": empty]),
			("LibraryData", .shared, "rv.data.LibraryTreeDocument", ["rootLibrary": .map(value: [:])]),
			("TestPatterns", .shared, "rv.data.TestPatternDocument", ["patterns": empty]),
			("TestPatterns", .client, "rv.data.TestPatternDocument", ["patterns": empty, "state": .map(value: [:])]),
			("Timers", .shared, "rv.data.TimersDocument", ["timers": empty]),
			("Timers", .client, "rv.data.TimersLocalDocument", ["timers": empty]),
		]
		for (kind, scope, message, fields) in roots {
			let document = LoroDoc(), root = document.getMap(id: "root")
			for (key, value) in fields {
				try root.insert(key: key, v: value)
			}
			let stream = try self.stream(document, kind: kind, scope: scope)
			let before = try stream.decodedValue()
			#expect(stream.supportsProtobufProjection)
			let projection = try stream.protobufProjection()
			try projection.requireComplete()
			#expect(projection.messageType == message && projection.identity.scope == scope)
			#expect(projection.source == before)
			#expect(throws: NativeSemanticError.self) { try projection.payload() }
			let inventory = try NativeMediaInventory(snapshot: .init(root: URL(fileURLWithPath: "/"), workspaceID: UUID(), metadata: [:], streams: [stream]))
			#expect(inventory.uninspected.isEmpty && inventory.occurrences.isEmpty)
			try root.insert(key: "future_dependency", v: "owned test reference")
			let unknown = try self.stream(document, kind: kind, scope: scope).protobufProjection()
			#expect(unknown.issues.contains { $0.path == "/root/future_dependency" })
			#expect(throws: NativeProjectionError.self) { try unknown.requireComplete() }
		}
	}

	@Test func timestampMapKeysUseTheirDeclaredIntegerTypeWithoutReplacingStoredValues() throws {
		let values: [Int64] = [-1, 1_730_044_500, Int64.max]
		let dates: [String: NativeWorkspaceValue] = Dictionary(uniqueKeysWithValues: values.map { (String($0), .map(["seconds": .integer($0), "nanos": .integer(42)])) })
		let source: NativeWorkspaceValue = .map(["recurrence_excluded_dates_v2": .map(dates)])
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let data = try encoder.encode(source, message: "rv.data.Calendar.Event", path: "/event")
		#expect(encoder.issues.isEmpty)
		let timestamps = try MediaWireMessage(data).payloads(10).map { try Rv_Data_Timestamp(serializedBytes: $0) }
		#expect(Set(timestamps.map(\.seconds)) == Set(values))
		#expect(timestamps.allSatisfy { $0.nanos == 42 })
		var missing = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let injected = try missing.encode(.map(["recurrence_excluded_dates_v2": .map(["-1": .map(["nanos": .integer(9)])])]), message: "rv.data.Calendar.Event", path: "/event")
		#expect(try Rv_Data_Timestamp(serializedBytes: #require(MediaWireMessage(injected).payloads(10).first)).seconds == -1)
	}

	@Test func inconsistentOrInvalidNumericKeysAndUnsupportedScopesRemainErrors() throws {
		for (key, seconds): (String, NativeWorkspaceValue) in [("1", .integer(2)), ("not-seconds", .integer(1)), ("1", .number(1.5))] {
			var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
			#expect(throws: NativeSemanticError.self) { try encoder.encode(.map(["recurrence_excluded_dates_v2": .map([key: .map(["seconds": seconds])])]), message: "rv.data.Calendar.Event", path: "/event") }
		}
		var keyed = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		#expect(throws: NativeSemanticError.self) {
			try keyed.encode(.map(["keymappings": .map(["unqualified-target-key": .map([:])])]), message: "rv.data.KeyMappingDocument", path: "/root")
		}
		for (kind, scope): (String, NativeWorkspaceStream.Scope) in [("Calendar", .client), ("Presentation", .client), ("FutureRoot", .shared)] {
			let document = LoroDoc(); try document.getMap(id: "root").insert(key: "future_dependency", v: "retained")
			let stream = try self.stream(document, kind: kind, scope: scope)
			#expect(!stream.supportsProtobufProjection)
			#expect(throws: NativeSemanticError.self) { try stream.protobufProjection() }
		}
	}

	private func stream(_ document: LoroDoc, kind: String, scope: NativeWorkspaceStream.Scope) throws -> NativeWorkspaceStream {
		document.commit()
		let data = try document.exportSnapshot()
		return .init(identity: .init(documentID: UUID(), scope: scope, kind: kind, corePath: nil, availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
	}
}
