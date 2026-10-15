import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native playlist materialization")
struct NativePlaylistProjectionTests {
	@Test(arguments: ProPresenterTargetVersion.allCases)
	func portableExportRetainsRepeatedItemsAndEmbedsTheSharedDependencyOnce(target: ProPresenterTargetVersion) throws {
		try withExportSnapshot { snapshot, output in
			let id = try #require(UUID(uuidString: "d0ab014c-0771-4441-9de5-c61098ca8f3c"))
			let result = try NativePlaylistExporter.bundle(from: snapshot, playlistID: id, to: output, targetVersion: target)
			#expect(result.compatibility.canWrite)
			#expect(result.compatibility.profile.targetVersion == target)
			#expect(result.dependencies.count == 1)
			#expect(result.dependencies[0].archivePath == "Presentations/bfa7b647-93ab-5ee6-b397-ec61b08bcfee/ProCRUDTarget22Acceptance.pro")
			let loaded = try DocumentLoader.load(from: output)
			guard case let .playlist(document) = loaded.payload else { Issue.record("Expected playlist archive"); return }
			let items = try #require(document.rootNode.playlists.playlists.first).items.items
			#expect(items.map(\.isHidden) == [false, false, true])
			#expect(items[1].uuid != items[2].uuid)
			#expect(items[1].presentation.documentPath == items[2].presentation.documentPath)
			#expect(items[1].presentation.documentPath.relativePath == result.dependencies[0].archivePath)
			#expect(items[1].presentation.documentPath.local.root == .currentResource)
			#expect(items[1].presentation.documentPath.local.path == result.dependencies[0].archivePath)
			// The hidden occurrence is retained in the file but ordinary playlist
			// rendering continues to select only the visible occurrence.
			#expect(try PresentationLoader.loadPresentations(from: output).count == 1)
			#expect(loaded.archiveEntries.filter { $0.hasSuffix(".pro") }.count == 1)
		}
	}

	@Test func missingNativeDependencyLeavesExistingArchiveUntouched() throws {
		try withExportSnapshot { snapshot, output in
			let incomplete = NativeWorkspaceSnapshot(root: snapshot.root, workspaceID: snapshot.workspaceID, metadata: [:], streams: snapshot.streams.filter { $0.identity.kind != "Presentation" })
			let sentinel = Data("existing archive".utf8)
			try sentinel.write(to: output)
			#expect(throws: NativeSemanticError.self) {
				try NativePlaylistExporter.bundle(from: incomplete, playlistID: #require(UUID(uuidString: "d0ab014c-0771-4441-9de5-c61098ca8f3c")), to: output, replace: true)
			}
			#expect(try Data(contentsOf: output) == sentinel)
		}
	}

	@Test func portableArchiveImportRetainsOccurrencesAndPresentationContentInNativeReexport() throws {
		let result = try DocumentLoader.load(from: fixtures.appendingPathComponent("Interchange/PortablePlaylistNativeReexport.proPlaylist"))
		guard case let .playlist(playlist) = result.payload else { Issue.record("Expected native playlist"); return }
		let items = try #require(playlist.rootNode.playlists.playlists.first).items.items
		#expect(items.map(\.isHidden) == [false, false, true])
		#expect(items[0].name == "Owned section")
		#expect(items[1].presentation.documentPath == items[2].presentation.documentPath)
		#expect(items[1].presentation.documentPath.local.path == "Libraries/Default/ProCRUDTarget22Acceptance-1.pro")
		#expect(result.archiveEntries.filter { $0.hasSuffix(".pro") } == ["ProCRUDTarget22Acceptance-1.pro"])
		let embedded = try PresentationLoader.loadPresentations(from: fixtures.appendingPathComponent("Interchange/PortablePlaylistNativeReexport.proPlaylist"))
		let presentation = try #require(embedded.first).document.presentation
		try withExportSnapshot { snapshot, _ in
			let source = try #require(snapshot.streams.first { $0.identity.kind == "Presentation" }).protobufProjection().presentation()
			#expect(presentation.uuid != source.uuid)
			// Native import initializes default text metadata on this graphic
			// rectangle and an empty macOS chord chart. Compare the entire cue
			// after accounting for those independently observed normalizations.
			var normalized = presentation.cues
			let originalElement = source.cues[0].actions[0].slide.presentation.baseSlide.elements[0]
			#expect(originalElement.element.text.rtfData.isEmpty)
			#expect(!normalized[0].actions[0].slide.presentation.baseSlide.elements[0].element.text.rtfData.isEmpty)
			normalized[0].actions[0].slide.presentation.baseSlide.elements[0].element.text = originalElement.element.text
			normalized[0].actions[0].slide.presentation.baseSlide.elements[0].element.mask = originalElement.element.mask
			normalized[0].actions[0].slide.presentation.clearChordChart()
			#expect(normalized == source.cues)
			#expect(presentation.cueGroups == source.cueGroups)
			#expect(presentation.ccli == source.ccli)
		}
	}

	@Test func nativeMediaDependencyFailsWithStructuredIssueBeforePublishing() throws {
		try withExportSnapshot(media: true) { snapshot, output in
			let sentinel = Data("existing archive".utf8)
			try sentinel.write(to: output)
			do {
				_ = try NativePlaylistExporter.bundle(from: snapshot, playlistID: #require(UUID(uuidString: "d0ab014c-0771-4441-9de5-c61098ca8f3c")), to: output, replace: true)
				Issue.record("Unqualified media was exported.")
			} catch let error as DocumentCompatibilityError {
				#expect(error.report.issues.map(\.feature) == ["native-media-dependency"])
				#expect(!error.report.canWrite)
			}
			#expect(try Data(contentsOf: output) == sentinel)
		}
	}

	@Test func exportCannotReplaceSourceOrPublishInsideIt() throws {
		try withExportSnapshot { snapshot, _ in
			let id = try #require(UUID(uuidString: "d0ab014c-0771-4441-9de5-c61098ca8f3c"))
			for output in [snapshot.root, snapshot.root.deletingLastPathComponent(), snapshot.root.appendingPathComponent("Output.proPlaylist")] {
				#expect(throws: DocumentArchiveError.self) { try NativePlaylistExporter.bundle(from: snapshot, playlistID: id, to: output, replace: true) }
			}
			#expect(try FileManager.default.contentsOfDirectory(atPath: snapshot.root.path).isEmpty)
		}
	}

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

	private func withExportSnapshot(media: Bool = false, _ body: (NativeWorkspaceSnapshot, URL) throws -> Void) throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let root = directory.appendingPathComponent("Source")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let prefix = media ? "MediaIdentity/Presentation" : "Playlist/presentation"
		let data = try Data(contentsOf: fixtures.appendingPathComponent("Native/\(prefix).loro"))
		let vector = try Data(contentsOf: fixtures.appendingPathComponent("Native/\(prefix).vector"))
		let id = try #require(UUID(uuidString: media ? "12080506-ffda-5a60-9e6d-4c99a9a8f82f" : "bfa7b647-93ab-5ee6-b397-ec61b08bcfee"))
		let presentation = NativeWorkspaceStream(identity: .init(documentID: id, scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
		let snapshot = try NativeWorkspaceSnapshot(root: root, workspaceID: UUID(), metadata: [:], streams: [fixture("shared", scope: .shared), fixture("client", scope: .client), presentation])
		try body(snapshot, directory.appendingPathComponent("Export.proPlaylist"))
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
