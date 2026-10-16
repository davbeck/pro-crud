import AppKit
import Foundation
import Loro
import ProPresenterProto
import SnapshotTesting
import Testing
@testable import ProCRUDCore

@Suite("Native slide text operations")
struct NativeTextEditingTests {
	private var actionID: UUID {
		get throws { try #require(UUID(uuidString: "586CB32A-4D87-4524-A07D-B6F571B5B9D0")) }
	}

	private var elementID: UUID {
		get throws { try #require(UUID(uuidString: "B9DEC841-620E-4A6B-876C-DF8BDF02A56C")) }
	}

	private let text = "CLI text acceptance — café 🎵\nSecond line"

	@Test func independentNativeTextChangesOnlyRTFAndMatchesCLITextSemantics() throws {
		let before = try stream().protobufProjection().presentation()
		var native = try stream(name: "native-after").protobufProjection().presentation()
		let nativeRTF = native.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text.rtfData
		#expect(try NSAttributedString(data: nativeRTF, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string == "Native text acceptance — café 🎵\nSecond line")
		native.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text.rtfData = before.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text.rtfData
		#expect(native == before)
		let source = try stream()
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .slideText(actionID: actionID, elementID: elementID, content: .rtf(nativeRTF))))
		#expect(try stream(patch: patch).decodedValue() == stream(name: "native-after").decodedValue())
	}

	@Test func productionTextIsAcceptedWithoutNativeRepairAndSupportsContinuedEditing() throws {
		let cli = try stream(name: "cli-after")
		let opened = try stream(name: "native-open")
		let continued = try stream(name: "native-continued")
		#expect(cli.snapshot == opened.snapshot)
		#expect(cli.versionVector == opened.versionVector)
		let presentation = try cli.protobufProjection().presentation()
		let rtf = presentation.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text.rtfData
		#expect(try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string == text)
		let history = LoroDoc()
		_ = try history.import(bytes: #require(cli.snapshot))
		let native = LoroDoc()
		_ = try native.import(bytes: #require(continued.snapshot))
		_ = try history.import(bytes: native.exportUpdates(vv: history.oplogVv()))
		#expect(try NativeWorkspaceValue(history.getDeepValue()) == continued.decodedValue())
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeReexport.pro")))
		let nativeText = try continued.protobufProjection().presentation().cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text
		let exportedText = try selectedText(in: exported)
		#expect(try attributed(exportedText.rtfData).string == attributed(nativeText.rtfData).string)
		#expect(exportedText.attributes.font == nativeText.attributes.font)
	}

	@Test func productionRTFIsAcceptedWithoutRepairAndPreservedByNativeExport() throws {
		let cli = try stream(name: "cli-rich-after")
		let native = try stream(name: "native-rich-open")
		#expect(cli.snapshot == native.snapshot)
		#expect(cli.versionVector == native.versionVector)
		let text = try cli.protobufProjection().presentation().cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text
		#expect(try text.rtfData == Data(contentsOf: fixtures.appendingPathComponent("Replacement.rtf")))
		#expect(text.attributes.customAttributes.isEmpty)
		#expect(text.attributes.font.name == "HelveticaNeue-BoldItalic")
		let exported = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("RichNativeReexport.pro")))
		let exportedText = try selectedText(in: exported)
		#expect(try attributed(exportedText.rtfData).string == attributed(text.rtfData).string)
		#expect(exportedText.attributes.font == text.attributes.font)
		#expect(exportedText.attributes.customAttributes.isEmpty)
		let exportedRTF = try attributed(exportedText.rtfData)
		let originalRTF = try attributed(text.rtfData)
		#expect(exportedRTF.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == originalRTF.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
		#expect(exportedRTF.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == originalRTF.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
	}

	@Test func richTextRenderingRetainsTheNative22LayoutDifference() throws {
		let document = try PresentationLoader.load(from: fixtures.appendingPathComponent("RichNativeReexport.pro"))
		let bitmap = try PresentationRenderer(document: document).render(cue: document.orderedCues[3])
		let image = NSImage(size: bitmap.size)
		image.addRepresentation(bitmap)
		let reference = try #require(NSImage(contentsOf: fixtures.appendingPathComponent("RichNativeSlide.png")))
		withKnownIssue("Native 22 text has a five-point horizontal inset and vertical-centering difference from the existing renderer; preserve the independent native PNG until qualified.") {
			if let failure = Snapshotting<NSImage, NSImage>.proCRUDImage().diffing.diffV2(reference, image) {
				Issue.record(Comment(rawValue: failure.0))
			}
		}
	}

	@Test func plainTextMatchesTheExistingEditorAndPreservesTheRestOfTheDocument() throws {
		let source = try stream()
		let before = try source.protobufProjection().presentation()
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .slideText(actionID: actionID, elementID: elementID, content: .text(text))))
		let updated = try stream(patch: patch)
		let after = try updated.protobufProjection().presentation()
		var expected = before
		let path = try ComponentPath("/cues[uuid=\"2FABF989-5E73-4CCE-8139-33F50F483922\"]/actions[uuid=\"\(actionID.uuidString)\"]/slide/presentation/base_slide/elements[uuid=\"\(elementID.uuidString)\"]/element/text")
		try DocumentEditor.setText(in: &expected, at: path, to: text)
		#expect(after == expected)
		let replay = LoroDoc()
		_ = try replay.import(bytes: #require(source.snapshot))
		_ = try replay.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(replay.getDeepValue()) == updated.decodedValue())
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: .slideText(actionID: actionID, elementID: elementID, content: .text(text))) == nil)
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .slideText(actionID: actionID, elementID: elementID, content: .text(""))) == nil)
	}

	@Test func richTextChangesTheAtomicFontAndKeepsUnrelatedState() throws {
		let attributed = try NSAttributedString(string: text, attributes: [.font: #require(NSFont(name: "HelveticaNeue-BoldItalic", size: 36)), .foregroundColor: NSColor.cyan])
		let rtf = try attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
		let source = try stream()
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .slideText(actionID: actionID, elementID: elementID, content: .rtf(rtf))))
		let updated = try stream(patch: patch)
		var before = try source.protobufProjection().presentation()
		let after = try updated.protobufProjection().presentation()
		let result = after.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text
		#expect(result.rtfData == rtf)
		#expect(result.attributes.font.name == "HelveticaNeue-BoldItalic")
		#expect(result.attributes.font.size == 36)
		#expect(result.attributes.font.bold && result.attributes.font.italic)
		#expect(result.attributes.customAttributes.isEmpty)
		before.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text = result
		#expect(after == before)
		#expect(try NativeLocalPatch.prepare(stream: updated, edit: .slideText(actionID: actionID, elementID: elementID, content: .rtf(rtf))) == nil)
	}

	@Test func replacingNativeStyledTextClearsRangesButPlainTextNoOpKeepsThem() throws {
		let source = try stream(name: "native-styled")
		let before = try source.protobufProjection().presentation()
		let original = before.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text
		#expect(original.attributes.customAttributes.count == 3)
		let existing = try NSAttributedString(data: original.rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .slideText(actionID: actionID, elementID: elementID, content: .text(existing))) == nil)
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edit: .slideText(actionID: actionID, elementID: elementID, content: .text(text))))
		let after = try stream(patch: patch).protobufProjection().presentation()
		#expect(after.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text.attributes.customAttributes.isEmpty)
		var expected = before
		expected.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text = after.cues[3].actions[0].slide.presentation.baseSlide.elements[0].element.text
		#expect(after == expected)
	}

	@Test func activeDeliveryIsRejectedBeforeChangingNativeText() throws {
		let source = try stream()
		let document = LoroDoc()
		_ = try document.import(bytes: #require(source.snapshot))
		let root = document.getMap(id: "root")
		let cues = try #require(root.get(key: "cues")?.asLoroMap())
		let cue = try #require(cues.get(key: "2FABF989-5E73-4CCE-8139-33F50F483922")?.asLoroMap())
		let actions = try #require(cue.get(key: "actions")?.asLoroMovableList())
		var map = try #require(actions.get(index: 0)?.asLoroMap())
		for key in ["ActionTypeData", "slide", "Slide", "presentation", "base_slide"] {
			map = try #require(map.get(key: key)?.asLoroMap())
		}
		let elements = try #require(map.get(key: "elements")?.asLoroMovableList())
		let element = try #require(elements.get(index: 0)?.asLoroMap())
		try element.insert(key: "reveal_type", v: Int64(Rv_Data_Slide.Element.TextRevealType.bullet.rawValue))
		let augmented = try NativeWorkspaceStream(identity: source.identity, snapshot: document.exportSnapshot(), versionVector: document.stateVv().encode(), lastSharedVersionVector: nil)
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: augmented, edit: .slideText(actionID: actionID, elementID: elementID, content: .text(text))) }
	}

	@Test func missingTargetsAndInvalidRTFDoNotChangeSource() throws {
		let source = try stream()
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .slideText(actionID: UUID(), elementID: elementID, content: .text(text))) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .slideText(actionID: actionID, elementID: UUID(), content: .text(text))) }
		#expect(throws: (any Error).self) { try NativeLocalPatch.prepare(stream: source, edit: .slideText(actionID: actionID, elementID: elementID, content: .rtf(Data("invalid RTF".utf8)))) }
		#expect(try source.decodedValue() == stream().decodedValue())
	}

	private func stream(name: String = "native-before", patch: NativeLocalPatch? = nil) throws -> NativeWorkspaceStream {
		let base = fixtures.appendingPathComponent(name)
		let bytes = try patch?.snapshot ?? Data(contentsOf: base.appendingPathExtension("loro"))
		let vector = try patch?.versionVector ?? Data(contentsOf: base.appendingPathExtension("vector"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "bfa7b647-93ab-5ee6-b397-ec61b08bcfee")), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUDTarget22Acceptance", availability: .available, byteCount: Int64(bytes.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: bytes, versionVector: vector, lastSharedVersionVector: nil)
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/Text")
	}

	private func attributed(_ data: Data) throws -> NSAttributedString {
		try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
	}

	private func selectedText(in presentation: Rv_Data_Presentation) throws -> Rv_Data_Graphics.Text {
		let action = try actionID, element = try elementID
		let matches = presentation.cues.flatMap(\.actions).filter { UUID(uuidString: $0.uuid.string) == action }.flatMap(\.slide.presentation.baseSlide.elements).filter { UUID(uuidString: $0.element.uuid.string) == element }
		#expect(matches.count == 1)
		return try #require(matches.first).element.text
	}
}
