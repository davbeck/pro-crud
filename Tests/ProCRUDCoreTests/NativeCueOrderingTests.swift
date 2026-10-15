import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native cue placement edits")
struct NativeCueOrderingTests {
	@Test func storedVectorUsesNativeStateEncoding() throws {
		let source = try stream()
		let original = LoroDoc()
		_ = try original.import(bytes: #require(source.snapshot))
		#expect(original.stateVv().encode() == source.versionVector)
		#expect(original.oplogVv().encode() != source.versionVector)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .copyrightTitle("State vector regression")))
		let reloaded = LoroDoc()
		_ = try reloaded.import(bytes: patch.snapshot)
		#expect(patch.versionVector == reloaded.stateVv().encode())
		#expect(try VersionVector.decode(bytes: patch.versionVector).eq(other: reloaded.oplogVv()))
	}

	@Test func moveChangesOnlyTheExistingPlacementPosition() throws {
		let source = try stream()
		let original = try source.presentationLayout()
		let ids = try original.orderedCueIDs()
		#expect(ids.count == 3)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .moveCue(ids[0], after: ids[2])))
		let updated = NativeWorkspaceStream(identity: source.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
		let layout = try updated.presentationLayout()
		#expect(try layout.orderedCueIDs() == [ids[1], ids[2], ids[0]])
		#expect(layout.cues == original.cues)
		#expect(layout.arrangements == original.arrangements)
		#expect(layout.groups.map(\.id) == original.groups.map(\.id))
		#expect(Set(layout.placements[0].children.map(\.nodeID)) == Set(original.placements[0].children.map(\.nodeID)))
		#expect(layout.placements[0].metadata == original.placements[0].metadata)
		let before = try source.protobufProjection().presentation()
		let after = try updated.protobufProjection().presentation()
		#expect(after.cues.map(\.uuid.string) == [ids[1], ids[2], ids[0]].map(\.uuidString))
		#expect(after.cues.allSatisfy { cue in before.cues.contains(cue) })
		#expect(after.cueGroups[0].cueIdentifiers.map(\.string) == [ids[1], ids[2], ids[0]].map(\.uuidString))
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: .moveCue(ids[0], after: ids[2])) == nil)
		let replay = LoroDoc()
		_ = try replay.import(bytes: #require(source.snapshot))
		_ = try replay.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(replay.getDeepValue()) == updated.decodedValue())
	}

	@Test func nativeRestartExportAndContinuationRetainTheMove() throws {
		let before = try stream("native-before")
		let cli = try stream("cli-after")
		let native = try stream("native-continued")
		let ids = try before.presentationLayout().orderedCueIDs()
		let expected = [ids[1], ids[2], ids[0]]
		#expect(try cli.presentationLayout().orderedCueIDs() == expected)
		#expect(try native.presentationLayout().orderedCueIDs() == expected)
		#expect(try before.presentationLayout().cues == cli.presentationLayout().cues)
		#expect(try cli.presentationLayout().cues == native.presentationLayout().cues)
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeReexport.pro")))
		let projection = try cli.protobufProjection().presentation()
		// The native exporter retains its cue storage-array order. Playback order
		// is the group's ordered identifiers, independently exported below.
		#expect(exported.cues.count == projection.cues.count)
		for cue in exported.cues {
			let projected = try #require(projection.cues.first { $0.uuid == cue.uuid })
			#expect(cue.actions.map(\.uuid) == projected.actions.map(\.uuid))
			for (action, expectedAction) in zip(cue.actions, projected.actions) {
				let slide = action.slide.presentation
				let expectedSlide = expectedAction.slide.presentation
				#expect(slide.baseSlide.uuid == expectedSlide.baseSlide.uuid)
				#expect(slide.notes == expectedSlide.notes)
				#expect(slide.baseSlide.elements.map(\.element.uuid) == expectedSlide.baseSlide.elements.map(\.element.uuid))
				for (element, expectedElement) in zip(slide.baseSlide.elements, expectedSlide.baseSlide.elements) {
					#expect(element.element.bounds == expectedElement.element.bounds)
					#expect(element.element.path == expectedElement.element.path)
					#expect(element.element.fill == expectedElement.element.fill)
				}
			}
		}
		#expect(exported.cueGroups[0].cueIdentifiers.map(\.string) == expected.map(\.uuidString))
		#expect(exported.cueGroups == projection.cueGroups)
		#expect(exported.ccli.songTitle == "Native state vector acceptance")
		#expect(try native.protobufProjection().presentation().notes == "Native continuation after CLI cue-tree move")
		for source in [before, cli] {
			let replay = LoroDoc()
			_ = try replay.import(bytes: #require(source.snapshot))
			let continuation = LoroDoc()
			_ = try continuation.import(bytes: #require(native.snapshot))
			_ = try replay.import(bytes: continuation.exportUpdates(vv: replay.oplogVv()))
			#expect(replay.oplogVv().eq(other: continuation.oplogVv()))
			#expect(try NativeWorkspaceValue(replay.getDeepValue()) == native.decodedValue())
		}
	}

	@Test func noOpAndMissingCueDoNotProduceHistoryOrMutateSource() throws {
		let source = try stream()
		let ids = try source.presentationLayout().orderedCueIDs()
		let original = source.snapshot
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .moveCue(ids[1], after: ids[0])) == nil)
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .moveCue(ids[0], after: ids[0])) == nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .moveCue(UUID(), after: ids[0])) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .moveCue(ids[0], after: UUID())) }
		#expect(source.snapshot == original)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/Ordering")
	}

	private func stream(_ name: String = "before") throws -> NativeWorkspaceStream {
		let directory = fixtures
		let bytes = try Data(contentsOf: directory.appendingPathComponent("\(name).loro"))
		let vector = try Data(contentsOf: directory.appendingPathComponent("\(name).vector"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(bytes.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: bytes, versionVector: vector, lastSharedVersionVector: nil)
	}
}
