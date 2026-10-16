import AppKit
import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native Slide Notes operations")
struct NativeSlideNotesTests {
	private var actionID: UUID {
		get throws { try #require(UUID(uuidString: "B6F1DA61-C874-42C1-B4E9-7FE1148715B3")) }
	}

	private let nativeText = "Native notes acceptance — first line\nSecond line: café 🎵"

	@Test func independentNativeEditStoresRichTextOnTheSlideAction() throws {
		let before = try stream("before").protobufProjection().presentation()
		let native = try stream("native-after").protobufProjection().presentation()
		#expect(before.notes.isEmpty)
		#expect(native.notes.isEmpty)
		#expect(before.cues[0].actions[0].slide.presentation.notes.rtfData.isEmpty)
		#expect(try plainText(native.cues[0].actions[0].slide.presentation.notes.rtfData) == nativeText)
		var normalized = native
		normalized.cues[0].actions[0].slide.presentation.clearNotes()
		#expect(normalized == before)
	}

	@Test func nativeRestartAndContinuationRetainTheCLIUpdate() throws {
		let cli = try stream("cli-after")
		let native = try stream("native-continued")
		let cliPresentation = try cli.protobufProjection().presentation()
		let nativePresentation = try native.protobufProjection().presentation()
		#expect(try plainText(cliPresentation.cues[0].actions[0].slide.presentation.notes.rtfData) == "CLI slide notes acceptance — café 🎵\nSecond line, preserved history.")
		#expect(try plainText(nativePresentation.cues[0].actions[0].slide.presentation.notes.rtfData) == "Native continued notes after CLI — café 🎵\nSecond line survives.")
		let history = LoroDoc()
		_ = try history.import(bytes: #require(cli.snapshot))
		let continuation = LoroDoc()
		_ = try continuation.import(bytes: #require(native.snapshot))
		_ = try history.import(bytes: continuation.exportUpdates(vv: history.oplogVv()))
		#expect(history.oplogVv().eq(other: continuation.oplogVv()))
		#expect(try NativeWorkspaceValue(history.getDeepValue()) == native.decodedValue())
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeReexport.pro")))
		#expect(try plainText(exported.cues[0].actions[0].slide.presentation.notes.rtfData) == "Native continued notes after CLI — café 🎵\nSecond line survives.")
		#expect(exported.cues.map(\.uuid) == nativePresentation.cues.map(\.uuid))
		#expect(exported.ccli == nativePresentation.ccli)
	}

	@Test(arguments: ["before", "native-after"])
	func richTextPatchChangesOnlyNotesBytesAndRetainsHistory(name: String) throws {
		let source = try stream(name)
		let replacement = try NativeSlideNotesContent.text("CLI rich notes — café 🎵\nNext line").encoded(replacing: Data())
		let rtf = try #require(replacement)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .slideNotes(actionID: actionID, content: .rtf(rtf))))
		let updated = try stream(name, patch: patch)
		let before = try source.protobufProjection().presentation()
		var after = try updated.protobufProjection().presentation()
		#expect(after.cues[0].actions[0].slide.presentation.notes.rtfData == rtf)
		after.cues[0].actions[0].slide.presentation.notes = before.cues[0].actions[0].slide.presentation.notes
		if !before.cues[0].actions[0].slide.presentation.hasNotes {
			after.cues[0].actions[0].slide.presentation.clearNotes()
		}
		#expect(after == before)
		let replay = LoroDoc()
		_ = try replay.import(bytes: #require(source.snapshot))
		_ = try replay.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(replay.getDeepValue()) == updated.decodedValue())
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: .slideNotes(actionID: actionID, content: .rtf(rtf))) == nil)
	}

	@Test func plainTextNoOpKeepsFormattingAndHistoryAndEmptyTextClears() throws {
		let source = try stream("native-after")
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .slideNotes(actionID: actionID, content: .text(nativeText))) == nil)
		#expect(try NativeLocalPatch.prepare(stream: stream("before"), edit: .slideNotes(actionID: actionID, content: .text(""))) == nil)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .slideNotes(actionID: actionID, content: .text(""))))
		let updated = try stream("native-after", patch: patch).protobufProjection().presentation()
		#expect(try plainText(updated.cues[0].actions[0].slide.presentation.notes.rtfData).isEmpty)
	}

	@Test func missingActionAndMalformedRTFFailWithoutChangingSource() throws {
		let source = try stream("native-after")
		let original = source.snapshot
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .slideNotes(actionID: UUID(), content: .text("Unresolved"))) }
		#expect(throws: (any Error).self) { try NativeLocalPatch.prepare(stream: source, edit: .slideNotes(actionID: actionID, content: .rtf(Data("invalid RTF".utf8)))) }
		#expect(source.snapshot == original)
	}

	private func stream(_ name: String, patch: NativeLocalPatch? = nil) throws -> NativeWorkspaceStream {
		let bytes = try patch?.snapshot ?? Data(contentsOf: fixtures.appendingPathComponent("\(name).loro"))
		let vector = try patch?.versionVector ?? Data(contentsOf: fixtures.appendingPathComponent("\(name).vector"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(bytes.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: bytes, versionVector: vector, lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/Notes")
	}

	private func plainText(_ data: Data) throws -> String {
		try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
	}
}
