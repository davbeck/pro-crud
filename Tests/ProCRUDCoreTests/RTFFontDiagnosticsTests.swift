import AppKit
import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

struct RTFFontDiagnosticsTests {
	@Test(arguments: ["", #"\fcharset0"#, #"\fcharset0\fprq2"#, "\\fprq2\n\\fcharset0"])
	func readsFontTableWithoutDependingOnCharsetOrder(controls: String) {
		let data = Data(#"{\rtf1\ansi{\fonttbl{\f0\fnil"#.appending(controls).appending(#" Helvetica;}{\f1\fnil\fcharset0 Helvetica-Bold;}}{\f0 Body text;}}"#).utf8)
		#expect(RTFFontTable.referencedNames(in: data) == [
			"Helvetica",
			"Helvetica-Bold",
		])
	}

	@Test(arguments: ["", #"\fcharset0"#])
	func readsCocoaFlatFontTable(controls: String) {
		let data = Data("{\\rtf1\\ansi{\\fonttbl\\f0\\fnil\(controls) Helvetica;\\f1\\fnil\\fcharset0 Helvetica-Bold;}\\f0 Sample}".utf8)
		#expect(RTFFontTable.referencedNames(in: data) == [
			"Helvetica",
			"Helvetica-Bold",
		])
	}

	@Test
	func ignoresTextOutsideFontTableAndUnsupportedEncodedNames() {
		let data = Data(#"{\rtf1\ansi{\fonttbl{\f0\fnil\fcharset0 Helv\'65tica;}}{\f1 This is body text;}}"#.utf8)
		#expect(RTFFontTable.referencedNames(in: data).isEmpty)
		#expect(RTFFontTable.referencedNames(in: Data(#"{\rtf1{\fonttbl{\f0 Helvetica;}"#.utf8)).isEmpty)
	}

	@Test(arguments: [true, false])
	func warnsAboutUnavailableFontAndReportsDecodedFaces(hasCharset: Bool) throws {
		let name = "ProCRUD-Missing-Font-7F4B93"
		#expect(NSFont(name: name, size: 12) == nil)
		let rtf = "{\\rtf1\\ansi{\\fonttbl{\\f0\\fnil\(hasCharset ? "\\fcharset0" : "") \(name);}}\\f0\\fs48 Sample}"
		let presentation = try presentation(rtf: rtf)
		let document = PresentationDocument(presentation: presentation)
		let diagnostics = document.renderingDiagnostics
		let missing = try #require(diagnostics.first { $0.code == .unavailableRTFFont })
		#expect(missing.severity == .warning)
		#expect(missing.componentPath.hasSuffix("/element/text/rtf_data"))
		#expect(missing.message.contains(name))
		#expect(missing.message.contains("Helvetica"))
		#expect(document.presentation == presentation)
		let report = DocumentValidator.validate(ProPresenterDocument(payload: .presentation(presentation), origin: .raw(URL(fileURLWithPath: "/FontDiagnostics.pro"))))
		#expect(report.valid)
		#expect(report.diagnostics.contains { $0.code == "rendering.unavailable-rtf-font" && $0.severity == .warning })
	}

	@Test
	func explicitCharsetMixedStyleExamplePreservesBothFacesAndBytes() throws {
		let rtf = #"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil\fcharset0 Helvetica;}{\f1\fnil\fcharset0 Helvetica-Bold;}}\f0\fs48 Regular {\f1 Bold} regular.}"#
		let presentation = try presentation(rtf: rtf)
		let document = PresentationDocument(presentation: presentation)
		#expect(!document.renderingDiagnostics.contains { $0.code == .unavailableRTFFont })
		let stored = presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text
		#expect(stored.rtfData == Data(rtf.utf8))
		#expect(stored.attributes.font.name == "Helvetica")
		let decoded = try NSAttributedString(data: stored.rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
		#expect(decoded.string == "Regular Bold regular.")
		#expect((decoded.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.fontName == "Helvetica-Bold")
	}

	private func presentation(rtf: String) throws -> Rv_Data_Presentation {
		var presentation = DocumentFactory.presentation(name: "Font diagnostics")
		try DocumentEditor.addElement(to: &presentation, at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide"), name: "Text", bounds: CGRect(x: 0, y: 0, width: 800, height: 200), color: DocumentEditor.color(hex: "#FFFFFF"))
		try DocumentEditor.setRTF(in: &presentation, at: ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text"), data: Data(rtf.utf8))
		return presentation
	}
}
