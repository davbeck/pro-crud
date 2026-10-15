import CryptoKit
import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native presentation ordering")
struct NativePresentationLayoutTests {
	@Test func nativeTreeAgreesWithIndependentProtobufExport() throws {
		let stream = try fixtureStream()
		let layout = try stream.presentationLayout()
		let exported = try DocumentLoader.load(from: fixtures.appendingPathComponent("Interchange/NativePresentation.pro"))
		guard case let .presentation(presentation) = exported.payload else { Issue.record("Expected native export"); return }
		#expect(layout.id == UUID(uuidString: presentation.uuid.string))
		#expect(layout.name == presentation.name)
		#expect(layout.groups.map(\.id) == presentation.cueGroups.compactMap { UUID(uuidString: $0.group.uuid.string) })
		#expect(layout.groups.map(\.name) == presentation.cueGroups.map(\.group.name))
		#expect(try layout.orderedCueIDs() == presentation.cueGroups.flatMap { $0.cueIdentifiers.compactMap { UUID(uuidString: $0.string) } })
		#expect(layout.unplacedCueIDs.isEmpty)
		#expect(layout.placements.first?.nodeID == "159@1")
		#expect(layout.placements.first?.children.first?.parentID == "159@1")
	}

	@Test func repeatedArrangementGroupsRetainEveryOccurrence() throws {
		var root = try fixtureRoot()
		let tree = try #require(root["cue_group_placements"])
		let node = try #require(try tree.array(at: "/").first)
		let meta = try node.object(at: "/").required("meta", at: "/").object(at: "/")
		let group = try meta.required("uuid", at: "/").uuid(at: "/")
		let arrangement = UUID()
		root["arrangements"] = .list([.map(["uuid": .string(arrangement.uuidString), "name": .string("Repeated"), "group_identifiers_v2": .list([.string(group.uuidString), .string(group.uuidString)])])])
		root["selected_arrangement"] = .string(arrangement.uuidString)
		let layout = try NativePresentationLayout(root: .map(root))
		#expect(layout.selectedArrangementID == arrangement)
		#expect(try layout.orderedCueIDs(arrangement: arrangement) == layout.orderedCueIDs() + layout.orderedCueIDs())
	}

	@Test func explicitEmptyNativeArrangementDoesNotFallBackToLegacyOrder() throws {
		let id = UUID()
		let object: [String: NativeWorkspaceValue] = ["old": .list([.string(id.uuidString)]), "new": .list([])]
		#expect(throws: NativeSemanticError.conflictingOrder(path: "/arrangement")) {
			try NativePresentationLayout.orderedIDs(object, legacy: "old", native: "new", path: "/arrangement")
		}
	}

	@Test func agreeingDualOrderAndLegacyUUIDWrappersAreAccepted() throws {
		let id = UUID()
		let object: [String: NativeWorkspaceValue] = ["old": .list([.map(["string": .string(id.uuidString)])]), "new": .list([.string(id.uuidString)])]
		#expect(try NativePresentationLayout.orderedIDs(object, legacy: "old", native: "new", path: "/") == [id])
	}

	@Test func unplacedCuesStayVisibleWithoutInventingOrder() throws {
		var root = try fixtureRoot()
		root["cue_group_placements"] = .list([])
		let layout = try NativePresentationLayout(root: .map(root))
		#expect(try layout.orderedCueIDs().isEmpty)
		#expect(layout.unplacedCueIDs.count == 1)
		#expect(layout.cues.count == 1)
	}

	@Test func danglingCueFailsWithItsPlacementPath() throws {
		var root = try fixtureRoot()
		root["cues"] = .map([:])
		#expect(throws: NativeSemanticError.self) { try NativePresentationLayout(root: .map(root)) }
	}

	@Test func danglingArrangementAndSelectionFailExplicitly() throws {
		var root = try fixtureRoot()
		root["arrangements"] = .list([.map(["uuid": .string(UUID().uuidString), "name": .string("Dangling"), "group_identifiers_v2": .list([.string(UUID().uuidString)])])])
		#expect(throws: NativeSemanticError.self) { try NativePresentationLayout(root: .map(root)) }
		root["arrangements"] = .list([])
		root["selected_arrangement"] = .string(UUID().uuidString)
		#expect(throws: NativeSemanticError.self) { try NativePresentationLayout(root: .map(root)) }
	}

	@Test(arguments: ["parent", "index", "id"])
	func malformedTreeTopologyFails(field: String) throws {
		var node = try #require(try fixtureRoot()["cue_group_placements"]?.array(at: "/").first?.object(at: "/"))
		switch field {
		case "parent": node[field] = .string("unknown-parent")
		case "index": node[field] = .integer(1)
		default:
			var child = try #require(try node["children"]?.array(at: "/").first?.object(at: "/"))
			child["id"] = node["id"]
			node["children"] = .list([.map(child)])
		}
		#expect(throws: NativeSemanticError.self) { try NativePlacementNode.read(.list([.map(node)]), path: "/tree") }
	}

	@Test func conflictingLegacyMasterOrderIsRejected() throws {
		var root = try fixtureRoot()
		root["cue_groups"] = .list([])
		#expect(throws: NativeSemanticError.conflictingOrder(path: "/root/cue_groups")) { try NativePresentationLayout(root: .map(root)) }
	}

	private func fixtureRoot() throws -> [String: NativeWorkspaceValue] {
		try fixtureStream().decodedValue().object(at: "/").required("root", at: "/").object(at: "/root")
	}

	private func fixtureStream() throws -> NativeWorkspaceStream {
		let data = try Data(contentsOf: fixtures.appendingPathComponent("Native/Presentation.loro"))
		let vector = try Data(contentsOf: fixtures.appendingPathComponent("Native/Presentation.version-vector"))
		let id = try #require(UUID(uuidString: "48e32307-7a5a-56cc-8cca-0bc82d6079c1"))
		return .init(identity: .init(documentID: id, scope: .shared, kind: "Presentation", corePath: "MISC/ProCRUD22Probe", availability: .available, byteCount: Int64(data.count), sha256: Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined(), updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22")
	}
}
