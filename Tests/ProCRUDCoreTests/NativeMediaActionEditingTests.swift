import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native media-action editing")
struct NativeMediaActionEditingTests {
	@Test func removalMatchesNativeUIAndRetainsEveryOtherActionAndContainer() throws {
		let logoAction = try #require(UUID(uuidString: "4F239108-7355-4DDD-A83F-C965313FC1DC"))
		let before = try stream("native-removal-before"), native = try stream("native-removed")
		let patch = try #require(try NativeLocalPatch.prepare(stream: before, edit: .removeMediaAction(logoAction)))
		let after = NativeWorkspaceStream(identity: before.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
		#expect(try after.decodedValue() == native.decodedValue())
		#expect(try after.presentationLayout().groups == before.presentationLayout().groups)
		#expect(try after.presentationLayout().arrangements == before.presentationLayout().arrangements)
		let replay = LoroDoc(); _ = try replay.import(bytes: #require(before.snapshot)); _ = try replay.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(replay.getDeepValue()) == native.decodedValue())
		#expect(try NativeLocalPatch.prepare(stream: after, edit: .removeMediaAction(logoAction)) == nil)
		let reopened = try stream("native-removed-reopened")
		#expect(native.snapshot == reopened.snapshot && native.versionVector == reopened.versionVector)
	}

	@Test func nativeFinderControlAddsAnActionWithFreshOccurrenceAndExistingAsset() throws {
		let logoAction = try #require(UUID(uuidString: "4F239108-7355-4DDD-A83F-C965313FC1DC"))
		let before = try stream("native-before").protobufProjection().presentation(), after = try stream("native-after").protobufProjection().presentation()
		let old = try #require(before.cues.first { $0.uuid.string == cue }), changed = try #require(after.cues.first { $0.uuid.string == cue })
		#expect(Array(changed.actions.dropLast()) == old.actions)
		let action = try #require(changed.actions.last)
		#expect(action.type == .media && UUID(uuidString: action.uuid.string) == logoAction)
		let media = try MediaReference(media: action.media.element)
		#expect(media.referenceID == "BBBFB028-5753-43D8-A264-9392E194692A")
		#expect(media.assetID == "FE240A1B-DE9A-5518-976E-4C72A07A65A4")
		#expect(media.activeLocators.map(\.localPath) == ["Media/Assets/LogoTransparent.png"])
	}

	@Test func backgroundMediaRemovalMatchesItsIndependentNativeControl() throws {
		let before = try stream("native-background-before"), native = try stream("native-background-after")
		let id = try #require(UUID(uuidString: "DDE126BA-14B9-4AAB-B6B9-9BEB04FAD1E3"))
		let patch = try #require(try NativeLocalPatch.prepare(stream: before, edit: .removeMediaAction(id)))
		let actual = NativeWorkspaceStream(identity: before.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
		#expect(try actual.decodedValue() == native.decodedValue())
	}

	@Test func selectedAfterActionCompletionAndNonMediaActionsFailBeforeProducingAnUpdate() throws {
		let logoAction = try #require(UUID(uuidString: "4F239108-7355-4DDD-A83F-C965313FC1DC"))
		let source = try stream("native-removal-before"), document = LoroDoc()
		_ = try document.import(bytes: #require(source.snapshot))
		let root = document.getMap(id: "root")
		let stored = try #require(root.get(key: "cues")?.asLoroMap()?.get(key: cue)?.asLoroMap())
		try stored.insert(key: "completion_action_type", v: 2)
		try stored.insert(key: "completion_action_uuid", v: logoAction.uuidString)
		let dependent = try NativeWorkspaceStream(identity: source.identity, snapshot: document.exportSnapshot(), versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: dependent, edit: .removeMediaAction(logoAction)) }
		let slide = try #require(UUID(uuidString: "88E31F8B-8EEB-464F-8D67-3FF9A6C485CA"))
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .removeMediaAction(slide)) }
		let before = source.snapshot
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edits: [.removeMediaAction(logoAction), .moveCue(UUID(), after: UUID())]) }
		#expect(source.snapshot == before)
	}

	@Test func productionRemovalReopensExactlyAndNativeContinuationRetainsTheDeletion() throws {
		let before = try stream("cli-before"), after = try stream("cli-after"), opened = try stream("native-cli-open"), continued = try stream("native-continued")
		#expect(after.snapshot == opened.snapshot && after.versionVector == opened.versionVector)
		let removed = try #require(UUID(uuidString: "F2421D65-4D95-4434-8DFE-1520C8B3B09D"))
		let patch = try #require(try NativeLocalPatch.prepare(stream: before, edits: [.removeMediaAction(removed), .copyrightTitle("Native Media Removal CLI")]))
		#expect(try NativeWorkspaceStream(identity: before.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil).decodedValue() == after.decodedValue())
		let final = try continued.protobufProjection().presentation()
		#expect(final.cues.flatMap(\.actions).allSatisfy { $0.renderableMedia == nil })
		#expect(final.ccli.songTitle == "Native Media Removal CLI")
		#expect(try continued.presentationLayout().groups.count == 2)
		let exported = try PresentationLoader.load(from: fixtures.appendingPathComponent("NativeReexport.pro"))
		#expect(exported.presentation.ccli.songTitle == final.ccli.songTitle)
		#expect(Set(exported.presentation.cues.map(\.uuid.string)) == Set(final.cues.map(\.uuid.string)))
		#expect(exported.presentation.cues.flatMap(\.actions).allSatisfy { $0.renderableMedia == nil })
		let native = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("ReferenceLifecycle.json"))) as? [String: Any]
		#expect((native?["created"] as? [String: Any])?["projectionOwned"] as? Bool == false)
		#expect((native?["beforeRemoval"] as? [String: Any])?["projectionOwned"] as? Bool == true)
		#expect((native?["immediateRemoval"] as? [String: Any])?["tombstoned"] as? Bool == false)
		#expect((native?["reopenedRemoval"] as? [String: Any])?["tombstoned"] as? Bool == true)
		#expect((native?["cliReopened"] as? [[String: Any]])?.filter { $0["tombstoned"] as? Bool != true }.isEmpty == true)
		#expect((native?["sharedAsset"] as? [String: Any])?["purged"] as? Bool == false)
	}

	private var cue: String {
		"F6E9C408-3E5E-4F91-8A9A-AD8438AFFE71"
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/MediaActionCreation")
	}

	private func stream(_ name: String) throws -> NativeWorkspaceStream {
		let base = fixtures.appendingPathComponent(name), data = try Data(contentsOf: base.appendingPathExtension("loro"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "58884c2c-1eb4-50f8-99ac-c88b29cb0f34")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUD File Replacement Probe", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: base.appendingPathExtension("vector")), lastSharedVersionVector: nil)
	}
}
