import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native HLS interchange")
struct NativeHLSInterchangeTests {
	@Test func nativeVideoHLSActionsHaveAScoped22InterchangeProfile() throws {
		for name in ["NativeBundle", "NativeStandalone", "NativeAfterMetadata"] {
			let presentation = try load(name)
			#expect(try DocumentCompatibility.analyze(document(presentation), target: .v22).issues.isEmpty)
			#expect(try !DocumentCompatibility.analyze(document(presentation), target: .v21).canWrite)
		}
	}

	@Test func otherNativeMediaAndUnknownHLSDependenciesRemainGated() throws {
		let original = try load("NativeBundle"), index = try mediaIndex(original)
		let media = original.cues[0].actions[index].media.element
		let variants = try [
			field(11, Data("2".utf8)), field(9, Data("container".utf8)), field(13, Data()),
			field(10, field(1, Data("invalid UUID".utf8))), field(10, field(99, Data())),
			field(99, Data()), field(12, Data()), field(2, Rv_Data_URL.with { $0.relativePath = "stale.mp4" }.serializedData()),
			field(6, field(6, field(99, Data()))), // Unknown SourceInfo member.
			field(6, field(1, field(12, Data()))), // Drawing effect.
			field(6, field(5, field(1, Rv_Data_URL.with { $0.relativePath = "old.mp4" }.serializedData()))),
			field(6, field(5, field(2, field(1, field(1, Data("provider-id".utf8)))))),
			field(3, Data([48, 127])), // Unknown metadata color-format enum.
		]
		for extra in variants {
			var changed = original
			changed.cues[0].actions[index].media.element = try .init(serializedBytes: media.serializedData() + extra)
			#expect(try !DocumentCompatibility.analyze(document(changed), target: .v22).canWrite)
		}
		for extra in [field(4, Data()), field(12, Data()), field(99, Data())] {
			var changed = original
			changed.cues[0].actions[index].media = try .init(serializedBytes: original.cues[0].actions[index].media.serializedData() + extra)
			#expect(try !DocumentCompatibility.analyze(document(changed), target: .v22).canWrite)
		}
		var fill = original
		fill.cues[0].actions.remove(at: index)
		fill.cues[0].actions[0].slide.presentation.baseSlide.elements = [.with { $0.element.fill.media = media }]
		#expect(try !DocumentCompatibility.analyze(document(fill), target: .v22).canWrite)
	}

	@Test func nativeCLIArtifactsImportWithTheSameAssetSourceAndTransport() throws {
		let probe = try stream("native-probe", id: "cf9668c3-03e2-4c31-b265-c0aa64f4528c").protobufProjection().presentation()
		let imported = try stream("native-cli-import", id: "e3592c20-2828-5688-827d-1242bf558e03").protobufProjection().presentation()
		let input = try portable("ConstructedInput"), edited = try portable("CLIEdited"), exported = try portable("NativeReexport")
		let index = try mediaIndex(input)
		#expect(try input.cues[0].actions[index].media.serializedData() == edited.cues[0].actions[index].media.serializedData())
		#expect(edited.ccli.songTitle == "Portable HLS CLI Interchange" && imported.ccli.songTitle == edited.ccli.songTitle)
		#expect(exported.ccli.songTitle == edited.ccli.songTitle)
		var probeMedia = try probe.cues[0].actions[mediaIndex(probe)].media.element
		var importedMedia = try imported.cues[0].actions[mediaIndex(imported)].media.element
		#expect(probeMedia.uuid != importedMedia.uuid)
		probeMedia.clearUuid(); importedMedia.clearUuid()
		#expect(try probeMedia.serializedData() == importedMedia.serializedData())
		let reference = try MediaReference(media: exported.cues[0].actions[mediaIndex(exported)].media.element)
		#expect(reference.assetID == "5F7CC3BF-2920-489D-ABAE-2E531F18892D")
		#expect(reference.activeLocators.map(\.remote) == ["http://127.0.0.1:49765/stream.m3u8"])
		#expect(try DocumentCompatibility.analyze(document(portable("CLIExport")), target: .v22).issues.isEmpty)
	}

	private func portable(_ name: String) throws -> Rv_Data_Presentation {
		try .init(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("\(name).pro")))
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/HLSInterchange")
	}

	private func stream(_ name: String, id: String) throws -> NativeWorkspaceStream {
		let base = fixtures.appendingPathComponent(name), data = try Data(contentsOf: base.appendingPathExtension("loro"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: id)), scope: .shared, kind: "Presentation", corePath: "Default/HLS", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: base.appendingPathExtension("vector")), lastSharedVersionVector: nil)
	}

	private func load(_ name: String) throws -> Rv_Data_Presentation {
		let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		return try Rv_Data_Presentation(serializedBytes: Data(contentsOf: root.appendingPathComponent("Fixtures/ProPresenter22/Native/HLSStream/\(name).pro")))
	}

	private func mediaIndex(_ presentation: Rv_Data_Presentation) throws -> Int {
		try #require(presentation.cues[0].actions.firstIndex { $0.type == .media })
	}

	private func document(_ presentation: Rv_Data_Presentation) -> ProPresenterDocument {
		.init(payload: .presentation(presentation), origin: .raw(URL(fileURLWithPath: "/Stream.pro")))
	}

	private func field(_ number: Int, _ payload: Data) -> Data {
		ProtobufJSONPatcher.WireField.lengthDelimited(number: number, payload: payload).raw
	}
}
