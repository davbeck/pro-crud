import AppKit
import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native atomic batch acceptance")
struct NativeBatchAcceptanceTests {
	@Test(arguments: ["first", "second"])
	func twoDocumentBatchSurvivesNativeRestartExportAndContinuation(name: String) throws {
		let before = try stream(name, "before")
		let cli = try stream(name, "cli-after")
		let native = try stream(name, "native-continued")
		let projection = try native.protobufProjection().presentation()
		let expectedTitle = name == "first" ? "CLI atomic batch first title" : "CLI atomic batch second title"
		#expect(try cli.protobufProjection().presentation().ccli.songTitle == expectedTitle)
		#expect(projection.ccli.songTitle == expectedTitle)
		let file = name == "first" ? "FirstNativeReexport.pro" : "SecondNativeReexport.pro"
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent(file)))
		#expect(UUID(uuidString: exported.uuid.string) == native.identity.documentID)
		#expect(exported.ccli == projection.ccli)
		#expect(exported.cueGroups == projection.cueGroups)
		#expect(exported.arrangements == projection.arrangements)
		#expect(exported.selectedArrangement == projection.selectedArrangement)
		#expect(exported.notes == projection.notes)
		#expect(Set(exported.cues.map(\.uuid.string)) == Set(projection.cues.map(\.uuid.string)))
		if name == "first" {
			#expect(try cli.protobufProjection().presentation().notes == "CLI atomic batch operator notes")
			#expect(projection.notes == "Native continued editing after atomic batch")
			#expect(projection.cueGroups[0].group.name == "CLI Batch Group")
			#expect(projection.arrangements[0].groupIdentifiers.count == 2)
			let action = try #require(exported.cues.flatMap(\.actions).first { $0.uuid.string == "B6F1DA61-C874-42C1-B4E9-7FE1148715B3" })
			#expect(try NSAttributedString(data: action.slide.presentation.notes.rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string == "CLI atomic batch Slide Notes — café 🎵")
		} else {
			#expect(try before.presentationLayout().cues == native.presentationLayout().cues)
		}
		let initial = LoroDoc(), applied = LoroDoc(), continued = LoroDoc()
		_ = try initial.import(bytes: #require(before.snapshot))
		_ = try applied.import(bytes: #require(cli.snapshot))
		_ = try continued.import(bytes: #require(native.snapshot))
		let json = applied.exportJsonUpdates(startVv: initial.oplogVv(), endVv: applied.oplogVv())
		let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
		#expect((object["changes"] as? [[String: Any]])?.count == 1)
		_ = try initial.import(bytes: applied.exportUpdates(vv: initial.oplogVv()))
		#expect(try NativeWorkspaceValue(initial.getDeepValue()) == cli.decodedValue())
		_ = try initial.import(bytes: continued.exportUpdates(vv: initial.oplogVv()))
		#expect(initial.oplogVv().eq(other: continued.oplogVv()))
		#expect(try NativeWorkspaceValue(initial.getDeepValue()) == native.decodedValue())
		#expect(applied.stateVv().encode() == cli.versionVector)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/Batches")
	}

	private func stream(_ name: String, _ state: String) throws -> NativeWorkspaceStream {
		let data = try Data(contentsOf: fixtures.appendingPathComponent("\(name)-\(state).loro"))
		let vector = try Data(contentsOf: fixtures.appendingPathComponent("\(name)-\(state).vector"))
		let id = try #require(UUID(uuidString: name == "first" ? "bfa7b647-93ab-5ee6-b397-ec61b08bcfee" : "900d3c21-55ae-4446-8f44-1563b0dbbb1c"))
		return .init(identity: .init(documentID: id, scope: .shared, kind: "Presentation", corePath: name == "first" ? "Default/ProCRUDTarget22Acceptance" : "Default/ProCRUDTarget22Acceptance-1", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
	}
}
