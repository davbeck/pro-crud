import AppKit
import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native Theme template editing")
struct NativeTemplateEditingTests {
	@Test func productionReorderRetainsNativeTemplateContainersAndReopensExactly() throws {
		let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/TemplateEditing")
		func read(_ name: String) throws -> NativeWorkspaceStream {
			let data = try Data(contentsOf: directory.appendingPathComponent("order-\(name).loro"))
			return try .init(identity: .init(documentID: #require(UUID(uuidString: "add2ee1f-c3f7-52f8-8239-805f0836168f")), scope: .shared, kind: "Theme", corePath: "CLI Template Ordering/Theme", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: directory.appendingPathComponent("order-\(name).vector")), lastSharedVersionVector: nil)
		}
		let source = try read("before"), after = try read("after"), opened = try read("open")
		#expect(after.snapshot == opened.snapshot && after.versionVector == opened.versionVector)
		var expected = try projected(source)
		let id = try #require(UUID(uuidString: expected.slides[1].baseSlide.uuid.string))
		expected.slides.swapAt(0, 1); expected.slides[0].name = "CLI First Template"
		#expect(try projected(after) == expected)
		let edits: [NativePresentationEdit] = [.template(.move(id, after: nil)), .template(.rename(id, "CLI First Template"))]
		#expect(try NativeLocalPatch.prepare(stream: after, edits: edits) == nil)
		func containers(_ stream: NativeWorkspaceStream) throws -> [ContainerId] {
			let document = LoroDoc(); _ = try document.import(bytes: #require(stream.snapshot))
			let list = try #require(document.getMap(id: "root").get(key: "slides")?.asLoroMovableList())
			return try (0 ..< list.len()).map { try #require(list.get(index: $0)?.asLoroMap()).id() }
		}
		#expect(try containers(after) == Array(containers(source).reversed()))
		let resnapshot = try read("exported")
		#expect(resnapshot.versionVector == after.versionVector)
		#expect(try resnapshot.decodedValue() == after.decodedValue())
		#expect(try containers(resnapshot) == containers(after))
		let exported = try DocumentLoader.load(from: directory.appendingPathComponent("NativeOrderReexport.proTheme"))
		guard case let .theme(theme) = exported.payload else { Issue.record("Expected native Theme export"); return }
		#expect(theme.slides.map(\.name) == ["CLI First Template", "CLI Template Editing"])
		#expect(theme.slides.map(\.baseSlide.uuid) == expected.slides.map(\.baseSlide.uuid))
		var normalized = theme.slides
		for slide in normalized.indices {
			for element in normalized[slide].baseSlide.elements.indices {
				let source = expected.slides[slide].baseSlide.elements[element]
				#expect(normalized[slide].baseSlide.elements[element].textScroller.repeatDistance == source.textScroller.repeatDistance / source.element.bounds.size.width)
				normalized[slide].baseSlide.elements[element].textScroller.repeatDistance = source.textScroller.repeatDistance
			}
		}
		#expect(normalized == expected.slides)
	}

	@Test func productionThemeReopensExactlyAndNativeExportRetainsItsNamesAndText() throws {
		let source = try fixture(), directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/TemplateEditing")
		let bytes = try Data(contentsOf: directory.appendingPathComponent("cli-after.loro"))
		#expect(try bytes == Data(contentsOf: directory.appendingPathComponent("native-exported.loro")))
		let stream = try NativeWorkspaceStream(identity: source.identity, snapshot: bytes, versionVector: Data(contentsOf: directory.appendingPathComponent("cli-after.vector")), lastSharedVersionVector: nil)
		let native = try DocumentLoader.load(from: directory.appendingPathComponent("NativeReexport.proTheme"))
		guard case let .theme(exported) = native.payload else { Issue.record("Expected native Theme export"); return }
		let expected = try projected(stream)
		var normalized = exported.slides
		for index in normalized[0].baseSlide.elements.indices {
			let source = expected.slides[0].baseSlide.elements[index]
			// Native export divides this inactive legacy distance by element
			// width. It does not rewrite the native Theme on reopen/export.
			#expect(normalized[0].baseSlide.elements[index].textScroller.repeatDistance == source.textScroller.repeatDistance / source.element.bounds.size.width)
			normalized[0].baseSlide.elements[index].textScroller.repeatDistance = source.textScroller.repeatDistance
		}
		#expect(normalized == expected.slides)
		#expect(exported.slides[0].name == "CLI Template Editing")
	}

	@Test func namingAndRichTextPreserveTheRestOfTheNativeThemeAndReplayWithoutChanges() throws {
		let source = try fixture(), theme = try projected(source), slide = try #require(theme.slides.first)
		let slideID = try #require(UUID(uuidString: slide.baseSlide.uuid.string)), element = try #require(slide.baseSlide.elements.first)
		let elementID = try #require(UUID(uuidString: element.element.uuid.string))
		let edits: [NativePresentationEdit] = [.template(.rename(slideID, "CLI Theme Template")), .template(.text(slide: slideID, element: elementID, content: .text("Native Theme text")))]
		let patch = try #require(try NativeLocalPatch.prepare(stream: source, edits: edits)), after = replacing(source, patch)
		let result = try projected(after)
		#expect(result.slides[0].name == "CLI Theme Template")
		#expect(try NSAttributedString(data: result.slides[0].baseSlide.elements[0].element.text.rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string == "Native Theme text")
		var normalized = result
		normalized.slides[0].name = slide.name
		normalized.slides[0].baseSlide.elements[0].element.text = element.element.text
		#expect(normalized == theme)
		#expect(try NativeLocalPatch.prepare(stream: after, edits: edits) == nil)
		let history = LoroDoc(); _ = try history.import(bytes: #require(source.snapshot)); _ = try history.import(bytes: patch.update)
		#expect(try NativeWorkspaceValue(history.getDeepValue()) == after.decodedValue())
	}

	@Test func unknownTemplateTargetsAndMalformedTextNeverChangeTheSource() throws {
		let source = try fixture(), slide = try #require(projected(source).slides.first), id = try #require(UUID(uuidString: slide.baseSlide.uuid.string)), element = try #require(UUID(uuidString: slide.baseSlide.elements[0].element.uuid.string))
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .template(.rename(UUID(), "Missing"))) }
		#expect(throws: NativeSemanticError.self) { try NativeLocalPatch.prepare(stream: source, edit: .template(.text(slide: id, element: UUID(), content: .text("Missing")))) }
		#expect(throws: (any Error).self) { try NativeLocalPatch.prepare(stream: source, edit: .template(.text(slide: id, element: element, content: .rtf(Data("invalid".utf8))))) }
		#expect(try NativeLocalPatch.prepare(stream: source, edit: .template(.move(id, after: nil))) == nil)
		#expect(try source.snapshot == fixture().snapshot)
	}

	private func projected(_ stream: NativeWorkspaceStream) throws -> Rv_Data_Template.Document {
		guard case let .theme(theme) = try stream.protobufProjection().payload() else { throw NativeSemanticError.invalidValue(path: "/theme", expected: "Theme") }
		return theme
	}

	private func replacing(_ source: NativeWorkspaceStream, _ patch: NativeLocalPatch) -> NativeWorkspaceStream {
		.init(identity: source.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
	}

	private func fixture() throws -> NativeWorkspaceStream {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/TemplateEditing/native-before")
		let data = try Data(contentsOf: root.appendingPathExtension("loro"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: "3bd14ee4-bdd4-541a-ae01-f9e4ed9e35be")), scope: .shared, kind: "Theme", corePath: "Deep Look Theme/Theme", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: root.appendingPathExtension("vector")), lastSharedVersionVector: nil)
	}
}
