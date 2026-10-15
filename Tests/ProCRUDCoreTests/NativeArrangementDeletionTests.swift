import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native arrangement deletion acceptance")
struct NativeArrangementDeletionTests {
	@Test func storedNativeReferenceBlocksDeletionUntilExplicitlyClearedInTheSameBatch() throws {
		let arrangementID = try arrangementID, actionID = try actionID
		let target = try stream("cli-before", role: "target"), reference = try stream("cli-before", role: "reference")
		let state = snapshot([target, reference])
		let inventory = try NativeArrangementReferenceInventory(snapshot: state)
		#expect(inventory.uninspected.isEmpty && inventory.references.count == 1)
		let link = try #require(inventory.references.first)
		#expect(link.documentID == reference.identity.documentID && link.arrangementID == arrangementID)
		#expect(link.role == .documentAction && link.targetDocumentID == nil)
		let documentAction = try action(in: reference)
		// The native importer omits obsolete identification. Its selector still
		// blocks deletion without guessing the target from a legacy UUID hint.
		#expect(!documentAction.presentationDocument.hasIdentification)
		let deletion = NativePresentationOperation(documentID: target.identity.documentID, edit: .removeArrangement(arrangementID))
		#expect(throws: NativeSemanticError.self) { try NativeLocalWorkspaceWriter.prepare([deletion], in: state) }
		let unlink = NativePresentationOperation(documentID: reference.identity.documentID, edit: .clearDocumentActionArrangement(actionID))
		let patches = try NativeLocalWorkspaceWriter.prepare([unlink, deletion], in: state)
		#expect(patches.count == 2)
		for (role, source) in [("reference", reference), ("target", target)] {
			let patch = try #require(patches.first { $0.identity.documentID == source.identity.documentID })
			let actual = try stream("cli-after", role: role)
			let replay = LoroDoc(); _ = try replay.import(bytes: #require(source.snapshot)); _ = try replay.import(bytes: patch.update)
			#expect(try NativeWorkspaceValue(replay.getDeepValue()) == actual.decodedValue())
		}
		#expect(throws: NativeSemanticError.self) { try NativeLocalWorkspaceWriter.prepare([unlink, deletion, deletion], in: state) }
	}

	@Test func productionBatchChangesOnlyTheSelectedDefinitionAndActionSelector() throws {
		let arrangementID = try arrangementID, actionID = try actionID
		let before = try stream("cli-before", role: "target"), after = try stream("cli-after", role: "target")
		var expected = try before.protobufProjection().presentation()
		expected.arrangements.removeAll { UUID(uuidString: $0.uuid.string) == arrangementID }
		expected.clearSelectedArrangement()
		#expect(try after.protobufProjection().presentation() == expected)
		#expect(expected.arrangements.count == 6)
		#expect(try after.presentationLayout().selectedArrangementID == nil)
		let referenceBefore = try stream("cli-before", role: "reference"), referenceAfter = try stream("cli-after", role: "reference")
		var expectedReference = try referenceBefore.protobufProjection().presentation()
		for cue in expectedReference.cues.indices {
			for index in expectedReference.cues[cue].actions.indices where UUID(uuidString: expectedReference.cues[cue].actions[index].uuid.string) == actionID {
				expectedReference.cues[cue].actions[index].presentationDocument.clearSelectedArrangement()
			}
		}
		#expect(try referenceAfter.protobufProjection().presentation() == expectedReference)
		#expect(try NativeLocalPatch.prepare(stream: referenceAfter, edit: .clearDocumentActionArrangement(actionID)) == nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: referenceBefore, edit: .clearDocumentActionArrangement(UUID())) }
		let slide = try #require(expectedReference.cues.first?.actions.first)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: referenceBefore, edit: .clearDocumentActionArrangement(#require(UUID(uuidString: slide.uuid.string)))) }
		let inventory = try NativeArrangementReferenceInventory(snapshot: snapshot([after, referenceAfter]))
		#expect(inventory.references.isEmpty && inventory.uninspected.isEmpty)
	}

	@Test func nativeReopenContinuedEditsAndIndependentExportsRetainTheDeletionAndUnlink() throws {
		let arrangementID = try arrangementID, actionID = try actionID
		for (role, export) in [("target", "NativeTargetReexport.pro"), ("reference", "NativeReferenceReexport.pro")] {
			let cli = try stream("cli-after", role: role), opened = try stream("native-open", role: role), continued = try stream("native-continued", role: role)
			#expect(cli.snapshot == opened.snapshot && cli.versionVector == opened.versionVector)
			#expect(cli.versionVector != continued.versionVector)
			let history = LoroDoc(); _ = try history.import(bytes: #require(cli.snapshot))
			let native = LoroDoc(); _ = try native.import(bytes: #require(continued.snapshot))
			_ = try history.import(bytes: native.exportUpdates(vv: history.oplogVv()))
			#expect(try NativeWorkspaceValue(history.getDeepValue()) == continued.decodedValue())
			let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent(export)))
			let projected = try continued.protobufProjection().presentation()
			#expect(exported.arrangements == projected.arrangements && exported.selectedArrangement == projected.selectedArrangement)
			if role == "target" {
				#expect(exported.arrangements.count == 6 && !exported.arrangements.contains { UUID(uuidString: $0.uuid.string) == arrangementID })
				#expect(exported.selectedArrangement.string == "2CE86B4C-F03E-4290-AAD1-C4D9A051E911")
			} else {
				#expect(exported.arrangements.first?.name == "Native After Unlink")
				let action = try #require(exported.cues.flatMap(\.actions).first { UUID(uuidString: $0.uuid.string) == actionID })
				var nativeAction = try self.action(in: continued)
				// Native export omits the stored empty label message.
				#expect(nativeAction.hasLabel && nativeAction.label == Rv_Data_Action.Label())
				nativeAction.clearLabel()
				#expect(action == nativeAction)
				#expect(!action.presentationDocument.hasSelectedArrangement)
			}
		}
	}

	private func action(in stream: NativeWorkspaceStream) throws -> Rv_Data_Action {
		let actionID = try actionID
		return try #require(stream.protobufProjection().presentation().cues.flatMap(\.actions).first { UUID(uuidString: $0.uuid.string) == actionID })
	}

	private func snapshot(_ streams: [NativeWorkspaceStream]) -> NativeWorkspaceSnapshot {
		.init(root: fixtures, workspaceID: UUID(), metadata: [:], streams: streams)
	}

	private func stream(_ step: String, role: String) throws -> NativeWorkspaceStream {
		let base = fixtures.appendingPathComponent("\(step)-\(role)")
		let data = try Data(contentsOf: base.appendingPathExtension("loro"))
		let id = try #require(UUID(uuidString: role == "target" ? "bfa7b647-93ab-5ee6-b397-ec61b08bcfee" : "bf7bda01-2c54-4fcc-bd4e-2551103c383b"))
		return try .init(identity: .init(documentID: id, scope: .shared, kind: "Presentation", corePath: role == "target" ? "Default/ProCRUDTarget22Acceptance" : "Default/ProCRUD Arrangement Reference", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: base.appendingPathExtension("vector")), lastSharedVersionVector: nil)
	}

	private var arrangementID: UUID {
		get throws { try #require(UUID(uuidString: "7017BE68-8867-48CE-9102-60E9C49DF61D")) }
	}

	private var actionID: UUID {
		get throws { try #require(UUID(uuidString: "12F67BC0-D8DE-47F3-91D9-B1692A758620")) }
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/ArrangementDeletion")
	}
}
