import AppKit
import Foundation
import Testing
@testable import ProCRUDCore

struct FontCharsetNativeTests {
	@Test(arguments: ["CMGSans", "Montserrat"])
	func nativeExportsPreserveCharsetIndependentOutput(family: String) throws {
		let root = fixtureURL("ProPresenter22/FontCharset/\(family)")
		let document = try PresentationLoader.load(from: root.appendingPathComponent("Input.pro"))
		let first = document.orderedCues[0].actions[0].slide.presentation.baseSlide.elements[0].element.text
		let second = document.orderedCues[1].actions[0].slide.presentation.baseSlide.elements[0].element.text
		#expect(first.attributes == second.attributes)
		let source = try #require(String(data: first.rtfData, encoding: .utf8))
		#expect(Data(source.replacingOccurrences(of: #"\fcharset0"#, with: "").utf8) == second.rtfData)
		#expect(RTFFontTable.referencedNames(in: first.rtfData) == RTFFontTable.referencedNames(in: second.rtfData))
		let reference = try pixels(root.appendingPathComponent("Reference/1.png"))
		#expect(try pixels(root.appendingPathComponent("Reference/2.png")) == reference)
		#expect(try pixels(root.appendingPathComponent("Reference/3.png")) == reference)
		#expect(try pixels(root.appendingPathComponent("Reference/4.png")) != reference)
	}

	@Test(.enabled(if: installed("Montserrat")))
	func montserratMatchesNativeGlyphLayout() throws {
		try matchesNativeGlyphLayout(family: "Montserrat")
	}

	@Test(.enabled(if: installed("CMGSans")))
	func cmgSansMatchesNativeGlyphLayout() throws {
		try matchesNativeGlyphLayout(family: "CMGSans")
	}

	private func matchesNativeGlyphLayout(family: String) throws {
		let root = fixtureURL("ProPresenter22/FontCharset/\(family)")
		let document = try PresentationLoader.load(from: root.appendingPathComponent("Input.pro"))
		// Render the charset-free slide first. Rendering slide 1 first masks the
		// original discovery bug by registering this font family in the process.
		let cue = document.orderedCues[1]
		let bitmap = try PresentationRenderer(document: document).render(cue: cue)
		let actualData = try #require(bitmap.representation(using: .png, properties: [:]))
		let actual = try #require(NSBitmapImageRep(data: actualData))
		let reference = try #require(NSBitmapImageRep(data: Data(contentsOf: root.appendingPathComponent("Reference/2.png"))))
		#expect(actual.pixelsWide == 1920 && actual.pixelsHigh == 1080)
		// Native 22 retains small RGB differences at antialiased glyph edges.
		// Assert the exact glyph footprint independently of those color values.
		#expect(try glyphMask(actual) == glyphMask(reference))
		let data = cue.actions[0].slide.presentation.baseSlide.elements[0].element.text.rtfData
		let decoded = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
		#expect((decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "\(family)-Regular")
		#expect((decoded.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.fontName == "\(family)-Bold")
	}

	private func glyphMask(_ bitmap: NSBitmapImageRep) throws -> [Bool] {
		#expect(bitmap.samplesPerPixel == 4)
		let bytes = try #require(bitmap.bitmapData)
		return (0 ..< bitmap.pixelsHigh).flatMap { y in
			(0 ..< bitmap.pixelsWide).map { x in bytes[y * bitmap.bytesPerRow + x * 4] > 0 }
		}
	}

	private func pixels(_ url: URL) throws -> Data {
		let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
		let bytes = try #require(bitmap.bitmapData)
		return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
	}
}

private func installed(_ family: String) -> Bool {
	["Regular", "Bold"].allSatisfy {
		FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Fonts/\(family)-\($0).ttf")
	}
}
