import CryptoKit
import Foundation
import ProPresenterProto
import SwiftProtobuf
import Testing
@testable import ProCRUDCore

@Suite("Native media identities and file locators")
struct NativeMediaTests {
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
