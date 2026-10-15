import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native playlist materialization")
struct NativePlaylistProjectionTests {
	@Test func nativeTreeMatchesIndependentExportOrderVisibilityAndReferences() throws {
		let shared = try fixture("shared", scope: .shared)
		let client = try fixture("client", scope: .client)
		let projection = try NativePlaylistProjection(shared: shared, client: client)
		let selected = try #require(projection.document.rootNode.playlists.playlists.first { $0.name == "ProCRUD Native Playlist Acceptance" })
		let exported = try DocumentLoader.load(from: fixtures.appendingPathComponent("Interchange/NonemptyPlaylist.proPlaylist"))
		guard case let .playlist(nativeExport) = exported.payload else { Issue.record("Expected playlist"); return }
		let expected = try #require(nativeExport.rootNode.playlists.playlists.first)
		#expect(projection.document.type == nativeExport.type)
		#expect(projection.document.rootNode.expanded == nativeExport.rootNode.expanded)
		#expect(selected.uuid.string == "D0AB014C-0771-4441-9DE5-C61098CA8F3C")
		#expect(selected.items.items.map(\.uuid.string) == ["04E5FBBD-E2D2-4DBE-BCAD-8C6C5CC1FDD0", "726D1A71-F8B7-4B7A-9B6B-14602BC61C27", "790B82D9-9F5B-4E51-81FB-0F52D74DDA97"])
		// Native export assigns fresh playlist/item identities. Compare their
		// semantics independently while retaining source identities in our view.
		#expect(selected.items.items.map(\.name) == expected.items.items.map(\.name))
		#expect(selected.items.items.map(\.isHidden) == expected.items.items.map(\.isHidden))
		#expect(selected.items.items[0].header.color == expected.items.items[0].header.color)
		for index in [1, 2] {
			#expect(selected.items.items[index].presentation.documentPath.local == expected.items.items[index].presentation.documentPath.local)
			#expect(selected.items.items[index].presentation.arrangement == expected.items.items[index].presentation.arrangement)
		}
		#expect(projection.unappliedClientNodeIDs.isEmpty)
		#expect(try shared.snapshot == Data(contentsOf: fixtures.appendingPathComponent("Native/Playlist/shared.loro")))
	}

	@Test func sharedContentDoesNotRequireClientExpansionState() throws {
		let shared = try fixture("shared", scope: .shared)
		let projection = try NativePlaylistProjection(shared: shared)
		#expect(!projection.document.rootNode.expanded)
		#expect(projection.document.rootNode.playlists.playlists.count == 2)
	}

	@Test func mismatchedClientCannotBeJoinedByNameOrKindAlone() throws {
		let shared = try fixture("shared", scope: .shared)
		let client = try fixture("client", scope: .client)
		var identity = client.identity
		identity.documentID = UUID()
		let other = NativeWorkspaceStream(identity: identity, snapshot: client.snapshot, versionVector: client.versionVector, lastSharedVersionVector: nil)
		#expect(throws: NativeSemanticError.self) { try NativePlaylistProjection(shared: shared, client: other) }
	}

	@Test func keyedClientStateCanOmitItsEmbeddedKeyAndDefaultFalseValue() throws {
		let shared = try fixture("shared", scope: .shared)
		let originalClient = try fixture("client", scope: .client)
		let id = try NativePlaylistProjection(shared: shared).document.rootNode.uuid.string
		let document = LoroDoc()
		try document.getMap(id: "root").insert(key: "node_states", v: LoroValue.map(value: [id: .map(value: [:])]))
		document.commit()
		let client = try NativeWorkspaceStream(identity: originalClient.identity, snapshot: document.exportSnapshot(), versionVector: document.oplogVv().encode(), lastSharedVersionVector: nil)
		let projection = try NativePlaylistProjection(shared: shared, client: client)
		#expect(!projection.document.rootNode.expanded)
		#expect(projection.unappliedClientNodeIDs.isEmpty)
	}

	@Test func unknownRootFieldsBlockMaterializationWithoutChangingHistory() throws {
		let shared = try fixture("shared", scope: .shared)
		let document = LoroDoc()
		_ = try document.import(bytes: #require(shared.snapshot))
		try document.getMap(id: "root").insert(key: "future_field", v: "future value")
		document.commit()
		let bytes = try document.exportSnapshot()
		let future = NativeWorkspaceStream(identity: shared.identity, snapshot: bytes, versionVector: document.oplogVv().encode(), lastSharedVersionVector: nil)
		#expect(throws: NativeProjectionError.self) { try NativePlaylistProjection(shared: future) }
		#expect(try document.exportSnapshot() == bytes)
	}

	@Test func unknownNodeMetadataIsReportedBeforeHierarchyAdaptation() throws {
		let shared = try fixture("shared", scope: .shared)
		var root = try shared.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root")
		var nodes = try root.required("playlists", at: "/root").array(at: "/root/playlists")
		var node = try #require(nodes.first).object(at: "/node")
		var metadata = try node.required("meta", at: "/node").object(at: "/node/meta")
		metadata["future_node_field"] = .string("preserve in source")
		node["meta"] = .map(metadata)
		nodes[0] = .map(node)
		root["playlists"] = .list(nodes)
		let document = LoroDoc()
		for (key, value) in root {
			try document.getMap(id: "root").insert(key: key, v: loro(value))
		}
		document.commit()
		let source = try NativeWorkspaceStream(identity: shared.identity, snapshot: document.exportSnapshot(), versionVector: document.oplogVv().encode(), lastSharedVersionVector: nil)
		do {
			_ = try NativePlaylistProjection(shared: source)
			Issue.record("Unknown native node metadata was omitted.")
		} catch let error as NativeProjectionError {
			#expect(error.issues.contains { $0.path.hasSuffix("/future_node_field") })
		}
	}

	private func loro(_ value: NativeWorkspaceValue) -> LoroValue {
		switch value {
		case .null: .null
		case let .boolean(value): .bool(value: value)
		case let .number(value): .double(value: value)
		case let .integer(value): .i64(value: value)
		case let .binary(value): .binary(value: value)
		case let .string(value): .string(value: value)
		case let .list(value): .list(value: value.map(loro))
		case let .map(value): .map(value: value.mapValues(loro))
		}
	}

	private func fixture(_ name: String, scope: NativeWorkspaceStream.Scope) throws -> NativeWorkspaceStream {
		let data = try Data(contentsOf: fixtures.appendingPathComponent("Native/Playlist/\(name).loro"))
		let vector = try Data(contentsOf: fixtures.appendingPathComponent("Native/Playlist/\(name).vector"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "f1d34fe9-54bc-5cce-aa9b-975968deaeae")), scope: scope, kind: "PlaylistLibrary", corePath: nil, availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22")
	}
}
