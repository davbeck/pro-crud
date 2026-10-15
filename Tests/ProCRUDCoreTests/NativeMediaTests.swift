import CryptoKit
import Foundation
import Loro
import ProPresenterProto
import SwiftProtobuf
import Testing
@testable import ProCRUDCore

@Suite("Native media identities and file locators")
struct NativeMediaTests {
	@Test func liveDeviceAndRemoteSourcesDoNotRequireFileAssetsOrReportMissingFiles() throws {
		let sources: [(String, NativeWorkspaceValue, NativeMediaInventory.Occurrence.State)] = [
			("live_video", .map([:]), .liveDevice),
			("hls_stream", .map(["url": .string("https://example.invalid/live.m3u8")]), .remoteSource),
			("web_content", .map(["url": .map(["Storage": .map(["__tag": .string("absolute_string"), "absolute_string": .string("https://example.invalid/page")])])]), .webContent),
		]
		for (kind, properties, state) in sources {
			let media: NativeWorkspaceValue = .map(["uuid": .string(UUID().uuidString), "identity_schema_version": .string("1"), "TypeProperties": .map(["__tag": .string(kind), kind: properties])])
			let action: NativeWorkspaceValue = .map(["uuid": .string(UUID().uuidString), "type": .integer(13), "ActionTypeData": .map(["__tag": .string("media"), "media": .map(["element": media])])])
			let document = LoroDoc()
			let root = document.getMap(id: "root")
			try root.insert(key: "type", v: 2)
			let tree = try root.insertContainer(key: "playlists", child: LoroTree())
			let node = try tree.create(parent: .root)
			try metadata(tree.getMeta(target: node), kind: "item", value: itemValue(action: action))
			_ = try root.insertContainer(key: "live_video_playlist_nodes", child: LoroTree())
			let stream = try playlistStream(document, scope: .shared)
			let result = try NativeMediaInventory(snapshot: .init(root: interchange, workspaceID: UUID(), metadata: [:], streams: [stream]), hashFiles: true)
			let occurrence = try #require(result.occurrences.first)
			#expect(occurrence.state == state)
			#expect(occurrence.diagnostics.isEmpty)
			#expect(occurrence.files.isEmpty)
			#expect(occurrence.reference.assetID == nil)
			#expect(!occurrence.localFilesAvailable)
			if kind != "live_video" {
				#expect(occurrence.reference.locators.count == 1)
			}
		}
	}

	@Test func playlistTreesInspectNestedItemsAndLiveVideoNodesInResolvedOrder() throws {
		let source = try #require(snapshot(root: interchange).streams.first)
		let nativeRoot = try source.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root")
		let cues = try nativeRoot.required("cues", at: "/root").object(at: "/root/cues")
		let actions = try cues.keys.sorted().map { key in
			try #require(cues.required(key, at: "/cues").object(at: "/cue").required("actions", at: "/cue").array(at: "/actions").first { action in
				try action.object(at: "/action")["type"] == .integer(13)
			})
		}
		#expect(actions.count == 2)
		let document = LoroDoc()
		let root = document.getMap(id: "root")
		try root.insert(key: "type", v: 2)
		let tree = try root.insertContainer(key: "playlists", child: LoroTree())
		let group = try tree.create(parent: .root)
		try metadata(tree.getMeta(target: group), kind: "group", value: .map([:]))
		let playlist = try tree.create(parent: .node(id: group))
		try metadata(tree.getMeta(target: playlist), kind: "playlist", value: .map([:]))
		let item = try tree.create(parent: .node(id: playlist))
		try metadata(tree.getMeta(target: item), kind: "item", value: itemValue(action: actions[0]))
		let live = try root.insertContainer(key: "live_video_playlist_nodes", child: LoroTree())
		let liveItem = try live.create(parent: .root)
		try metadata(live.getMeta(target: liveItem), kind: "item", value: itemValue(action: actions[1]))
		let stream = try playlistStream(document, scope: .shared)
		let references = try stream.mediaReferences()
		#expect(references.count == 2)
		#expect(references[0].path.hasPrefix("/root/playlists[node_id="))
		#expect(references[1].path.hasPrefix("/root/live_video_playlist_nodes[node_id="))
		#expect(Set(references.compactMap(\.assetID)) == ["322e4d08-cba2-4b08-bd43-842ae317f6df"])
		#expect(Set(references.map(\.referenceID)).count == 2)
		let inventory = try NativeMediaInventory(snapshot: .init(root: interchange, workspaceID: UUID(), metadata: [:], streams: [stream]))
		#expect(inventory.occurrences.map(\.localFilesAvailable) == [true, true])
		#expect(inventory.uninspected.isEmpty)
		// A future node field can carry a dependency. It must invalidate this
		// stream's complete enumeration rather than silently returning a subset.
		try tree.getMeta(target: item).insert(key: "future_media", v: "unmapped")
		#expect(throws: NativeProjectionError.self) { try playlistStream(document, scope: .shared).mediaReferences() }
	}

	@Test func clientPlaylistStateIsInspectedSeparatelyWithoutSharedTreeFallback() throws {
		let document = LoroDoc()
		let root = document.getMap(id: "root")
		try root.insert(key: "type", v: 2)
		let id = UUID().uuidString
		try root.insert(key: "node_states", v: LoroValue.map(value: [id: .map(value: ["uuid": .string(value: id), "expanded": .bool(value: true)])]))
		let stream = try playlistStream(document, scope: .client)
		#expect(try stream.mediaReferences().isEmpty)
		let inventory = try NativeMediaInventory(snapshot: .init(root: interchange, workspaceID: UUID(), metadata: [:], streams: [stream]))
		#expect(inventory.occurrences.isEmpty)
		#expect(inventory.uninspected.isEmpty)
		try root.insert(key: "future_media", v: "unmapped")
		#expect(throws: NativeProjectionError.self) { try playlistStream(document, scope: .client).mediaReferences() }
	}

	@Test func nativeBundlePreservesSharedAssetAndDistinctOccurrences() throws {
		let payload = try Data(contentsOf: interchange.appendingPathComponent("NativeBundle.pro"))
		let references = try MediaReference.collect(protobuf: payload, messageType: Rv_Data_Presentation.protoMessageName)
		#expect(references.count == 2)
		#expect(Set(references.map(\.referenceID)) == ["80eb4ec7-9507-5bb1-be56-1b42ab4f077a", "a334238d-6c81-5441-85f6-3c61ffaf9004"])
		#expect(Set(references.compactMap(\.assetID)) == ["322e4d08-cba2-4b08-bd43-842ae317f6df"])
		#expect(references.allSatisfy { $0.identitySchemaVersion == "1" && $0.kind == "image" && $0.containerID == nil && !$0.hasProvider })
		#expect(references.allSatisfy { $0.locators.map(\.field) == ["url", "image/file/local_url"] })
		#expect(references.allSatisfy { $0.locators.allSatisfy { $0.localRoot == 10 && $0.localPath == "Media/Assets/SharedRectangle.png" } })
		let decoded = try Rv_Data_Presentation(serializedBytes: payload)
		#expect(try MediaReference.collect(protobuf: decoded.serializedData(), messageType: Rv_Data_Presentation.protoMessageName) == references)
	}

	@Test func standaloneNativeExportActuallyOmitsMediaActions() throws {
		let presentation = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: interchange.appendingPathComponent("NativeStandalone.pro")))
		#expect(presentation.cues.count == 2)
		#expect(presentation.cues.allSatisfy { $0.actions.count == 2 && $0.actions[0].type == .presentationSlide && $0.actions[1].actionTypeData == nil })
		#expect(try MediaReference.collect(protobuf: presentation.serializedData(), messageType: Rv_Data_Presentation.protoMessageName).isEmpty)
	}

	@Test func storedNativeSnapshotMatchesIndependentBundleIdentityAndLocalFiles() throws {
		let snapshot = try snapshot(root: interchange)
		let projection = try #require(snapshot.streams.first).protobufProjection()
		try projection.requireComplete()
		let references = try MediaReference.collect(protobuf: projection.protobuf, messageType: projection.messageType)
		#expect(references.count == 2)
		#expect(references.allSatisfy { $0.locators.map(\.field) == ["image/file/local_url"] })
		let inventory = try NativeMediaInventory(snapshot: snapshot, hashFiles: true)
		#expect(inventory.occurrences.count == 2)
		#expect(inventory.occurrences.map(\.localFilesAvailable) == [true, true])
		#expect(inventory.uninspected.isEmpty)
		let expectedHash = try Data(SHA256.hash(data: Data(contentsOf: interchange.appendingPathComponent("Media/Assets/SharedRectangle.png"))))
		#expect(Set(inventory.occurrences.flatMap(\.files).compactMap(\.sha256)) == [hex(expectedHash)])
		#expect(inventory.assetStoreMembership == "unverified")
	}

	@Test func movedRootUsesExactRelativePathAndNeverBasenameOrStaleCache() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Media/Other"), withIntermediateDirectories: true)
		try Data("wrong file".utf8).write(to: root.appendingPathComponent("Media/Other/SharedRectangle.png"))
		// A stale projection with an old ID/path cannot supply a missing file.
		try Data("stale derived cache".utf8).write(to: root.appendingPathComponent("projection-v6.json"))
		let missing = try NativeMediaInventory(snapshot: snapshot(root: root))
		#expect(missing.occurrences.allSatisfy { !$0.localFilesAvailable && $0.files.isEmpty })
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Media/Assets"), withIntermediateDirectories: true)
		try FileManager.default.copyItem(at: interchange.appendingPathComponent("Media/Assets/SharedRectangle.png"), to: root.appendingPathComponent("Media/Assets/SharedRectangle.png"))
		#expect(try NativeMediaInventory(snapshot: snapshot(root: root)).occurrences.map(\.localFilesAvailable) == [true, true])
	}

	@Test func unknownAndUnavailableStreamsCannotLookLikeCompleteValidation() throws {
		let source = try #require(snapshot(root: interchange).streams.first)
		var missing = source.identity
		missing.documentID = UUID()
		missing.availability = .unavailable
		var client = source.identity
		client.scope = .client
		let streams = [source, NativeWorkspaceStream(identity: missing, snapshot: nil, versionVector: nil, lastSharedVersionVector: nil),
		               NativeWorkspaceStream(identity: client, snapshot: source.snapshot, versionVector: source.versionVector, lastSharedVersionVector: nil)]
		let inventory = try NativeMediaInventory(snapshot: .init(root: interchange, workspaceID: UUID(), metadata: [:], streams: streams))
		#expect(inventory.occurrences.count == 2)
		#expect(inventory.uninspected.count == 2)
		#expect(inventory.uninspected.contains { $0.reason.contains("unavailable locally") })
	}

	@Test func sourceHLSRemainsRemoteAndUnknownSchemaIsNotQualified() throws {
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		let media = try encoder.encode(.map([
			"uuid": .string(UUID().uuidString), "asset_id": .string(UUID().uuidString), "identity_schema_version": .string("2"),
			"TypeProperties": .map(["__tag": .string("video"), "video": .map([
				"source": .map(["SourceType": .map(["__tag": .string("hls"), "hls": .map(["url": .string("https://example.invalid/live.m3u8")])])]),
			])]),
		]), message: "rv.data.Media", path: "/media")
		let reference = try MediaReference(media: Rv_Data_Media(serializedBytes: media))
		#expect(reference.identitySchemaVersion == "2")
		#expect(reference.kind == "video")
		#expect(reference.dependencyKind == .remoteStream)
		let locator = try #require(reference.locators.first)
		#expect(locator.remote == "https://example.invalid/live.m3u8")
		#expect(throws: NativeSemanticError.self) { try NativeMediaInventory.resolve(locator, workspaceRoot: interchange) }
	}

	@Test func splitSingularMediaMessagesMerge() throws {
		let reference = try Data(contentsOf: interchange.appendingPathComponent("NativeBundle.pro"))
		let original = try Rv_Data_Presentation(serializedBytes: reference).cues[0].actions[1].media.element
		let fields = try ProtobufJSONPatcher.WireField.parse(original.serializedData())
		let first = fields.filter { $0.number < 9 }.reduce(into: Data()) { $0.append($1.raw) }
		let second = fields.filter { $0.number >= 9 }.reduce(into: Data()) { $0.append($1.raw) }
		let wire = ProtobufJSONPatcher.WireField.lengthDelimited(number: 5, payload: first).raw + ProtobufJSONPatcher.WireField.lengthDelimited(number: 5, payload: second).raw
		let found = try MediaReference.collect(protobuf: wire, messageType: "rv.data.Action.MediaType")
		#expect(found.count == 1)
		#expect(found.first?.referenceID == original.uuid.string)
		#expect(found.first?.assetID == "322e4d08-cba2-4b08-bd43-842ae317f6df")
	}

	@Test func switchingSourceOneofClearsThePreviousFileLocator() throws {
		func field(_ number: Int, _ data: Data) -> Data {
			ProtobufJSONPatcher.WireField.lengthDelimited(number: number, payload: data).raw
		}
		var url = Rv_Data_URL()
		url.absoluteString = "file:///old.png"
		let source = try field(1, field(1, url.serializedData())) + field(2, field(1, Data("https://example.invalid/live.m3u8".utf8))) + field(1, Data())
		let media = try Rv_Data_Media(serializedBytes: field(5, field(3, source)))
		#expect(try MediaReference(media: media).locators.isEmpty)
	}

	private func snapshot(root: URL) throws -> NativeWorkspaceSnapshot {
		let snapshot = try Data(contentsOf: native.appendingPathComponent("Presentation.loro"))
		let vector = try Data(contentsOf: native.appendingPathComponent("Presentation.vector"))
		return try .init(root: root, workspaceID: UUID(), metadata: [:], streams: [
			.init(identity: .init(documentID: #require(UUID(uuidString: "12080506-ffda-5a60-9e6d-4c99a9a8f82f")), scope: .shared, kind: "Presentation", corePath: "Default/NativeMediaIdentity", availability: .available, byteCount: Int64(snapshot.count), sha256: hex(Data(SHA256.hash(data: snapshot))), updatedAtMilliseconds: 0), snapshot: snapshot, versionVector: vector, lastSharedVersionVector: nil),
		])
	}

	private func playlistStream(_ document: LoroDoc, scope: NativeWorkspaceStream.Scope) throws -> NativeWorkspaceStream {
		document.commit()
		let data = try document.exportSnapshot()
		return .init(identity: .init(documentID: UUID(), scope: scope, kind: "PlaylistMedia", corePath: nil, availability: .available, byteCount: Int64(data.count), sha256: hex(Data(SHA256.hash(data: data))), updatedAtMilliseconds: 0), snapshot: data, versionVector: document.oplogVv().encode(), lastSharedVersionVector: nil)
	}

	private func metadata(_ map: LoroMap, kind: String, value: NativeWorkspaceValue) throws {
		try map.insert(key: "uuid", v: UUID().uuidString)
		try map.insert(key: "name", v: "Owned test node")
		try map.insert(key: "Kind", v: loro(.map(["__tag": .string(kind), kind: value])))
	}

	private func itemValue(action: NativeWorkspaceValue) -> NativeWorkspaceValue {
		.map(["is_hidden": .boolean(false), "ItemType": .map(["__tag": .string("cue"), "cue": .map(["uuid": .string(UUID().uuidString), "name": .string("Owned media cue"), "actions": .list([action])])])])
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

	private func hex(_ data: Data) -> String {
		data.map { String(format: "%02x", $0) }.joined()
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22")
	}

	private var interchange: URL {
		fixtures.appendingPathComponent("Interchange/MediaIdentity")
	}

	private var native: URL {
		fixtures.appendingPathComponent("Native/MediaIdentity")
	}
}
