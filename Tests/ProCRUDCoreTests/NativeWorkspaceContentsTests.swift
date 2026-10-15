import Foundation
import Testing
@testable import ProCRUDCore

@Suite("Native workspace contents")
struct NativeWorkspaceContentsTests {
	@Test func nestedPlaylistTreeRetainsWrappersAndVisibility() throws {
		let itemID = UUID()
		let item = placement(id: itemID, node: "3@1", parent: "2@1", kind: "item", name: "Remote wrapper", data: .map(["is_hidden": .boolean(true), "ItemType": .map(["__tag": .string("planning_center"), "planning_center": .map(["linked_data": .map(["uuid": .string(UUID().uuidString)])])])]))
		let playlist = placement(id: UUID(), node: "2@1", parent: "1@1", kind: "playlist", name: "Service", children: [item])
		let group = placement(id: UUID(), node: "1@1", parent: nil, kind: "group", name: "Folder", children: [playlist])
		let layout = try NativePlaylistLayout(root: .map(["type": .integer(1), "playlists": .list([group]), "live_video_playlist_nodes": .list([])]))
		let result = try #require(layout.playlists.first?.children.first?.children.first)
		#expect(result.id == itemID)
		#expect(result.kind == .item)
		#expect(try result.attributes.object(at: "/")["is_hidden"] == .boolean(true))
		#expect(result.nodeID == "3@1")
	}

	@Test func duplicatePlaylistUUIDAndItemChildrenFail() throws {
		let id = UUID()
		let child = placement(id: id, node: "2@1", parent: "1@1", kind: "playlist", name: "Duplicate")
		let duplicate = placement(id: id, node: "1@1", parent: nil, kind: "group", name: "Root", children: [child])
		#expect(throws: NativeSemanticError.self) { try NativePlaylistLayout(root: .map(["type": .integer(1), "playlists": .list([duplicate]), "live_video_playlist_nodes": .list([])])) }
		let item = placement(id: UUID(), node: "1@1", parent: nil, kind: "item", name: "Invalid", children: [child])
		#expect(throws: NativeSemanticError.self) { try NativePlaylistLayout(root: .map(["type": .integer(1), "playlists": .list([item]), "live_video_playlist_nodes": .list([])])) }
	}

	@Test func referencesUseNativeLogicalPathRatherThanStaleAbsoluteURL() throws {
		let id = UUID()
		let resolver = try NativeWorkspaceReferenceResolver(streams: [stream(id: id, path: "Nested/Service", scope: .shared), stream(id: UUID(), path: "Nested/Service", scope: .client)])
		let url = reference(path: "Libraries/Nested/Service.pro")
		let result = try resolver.presentation(url)
		#expect(result.documentID == id)
		#expect(result.logicalPath == "Nested/Service")
		#expect(result.source == url)
		#expect(result.availability == .unavailable)
	}

	@Test(arguments: ["Libraries/../Outside.pro", "Libraries//Service.pro", "/Libraries/Service.pro", "Libraries/Service", "Themes/Service.pro"])
	func nonLibraryOrUnsafePathsRemainUnresolved(path: String) throws {
		let resolver = try NativeWorkspaceReferenceResolver(streams: [])
		#expect(try resolver.presentation(reference(path: path)).documentID == nil)
		#expect(try resolver.presentation(reference(path: path)).logicalPath == nil)
	}

	@Test func missingPresentationIsReportedWithItsLogicalPath() throws {
		let resolver = try NativeWorkspaceReferenceResolver(streams: [])
		let result = try resolver.presentation(reference(path: "Libraries/Missing.pro"))
		#expect(result.documentID == nil)
		#expect(result.logicalPath == "Missing")
	}

	@Test func duplicateSharedCorePathsAreAmbiguous() throws {
		#expect(throws: NativeSemanticError.self) { try NativeWorkspaceReferenceResolver(streams: [stream(id: UUID(), path: "Same", scope: .shared), stream(id: UUID(), path: "Same", scope: .shared)]) }
	}

	private func reference(path: String) -> NativeWorkspaceValue {
		.map(["RelativeFilePath": .map(["__tag": .string("local"), "local": .map(["root": .integer(10), "path": .string(path)])]), "Storage": .map(["__tag": .string("absolute_string"), "absolute_string": .string("file:///stale/old/workspace/Other.pro")])])
	}

	private func stream(id: UUID, path: String, scope: NativeWorkspaceStream.Scope) -> NativeWorkspaceStream {
		.init(identity: .init(documentID: id, scope: scope, kind: "Presentation", corePath: path, availability: .unavailable, byteCount: 0, sha256: nil, updatedAtMilliseconds: 0), snapshot: nil, versionVector: nil, lastSharedVersionVector: nil)
	}

	private func placement(id: UUID, node: String, parent: String?, kind: String, name: String, data: NativeWorkspaceValue = .map([:]), children: [NativeWorkspaceValue] = []) -> NativeWorkspaceValue {
		.map(["id": .string(node), "parent": parent.map(NativeWorkspaceValue.string) ?? .null, "index": .integer(0), "fractional_index": .string("80"), "meta": .map(["uuid": .string(id.uuidString), "name": .string(name), "Kind": .map(["__tag": .string(kind), kind: data])]), "children": .list(children)])
	}
}
