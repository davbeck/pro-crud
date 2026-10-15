import AppKit
import CryptoKit
import Foundation
import ProPresenterProto
import SnapshotTesting
import Testing
@testable import ProCRUDCore

@Suite("Native file-media static rendering")
struct NativeMediaRenderingTests {
	@Test func nativeAndExportedMediaRenderIdenticallyWithoutChangingSourceHistoryOrWriteGates() throws {
		for name in ["08 - Media Elements", "09 - Media Backgrounds"] {
			let source = try stream(name)
			let original = try #require(source.snapshot)
			let presentation = try source.protobufProjection().presentation()
			let native = PresentationDocument(presentation: presentation, mediaDirectory: corpus.appendingPathComponent("Documents"))
			let exported = try PresentationLoader.load(from: corpus.appendingPathComponent("Documents/\(name).pro"))
			#expect(native.renderingDiagnostics.filter { $0.code == .missingMediaURL || $0.code == .unsupportedNativeMedia }.isEmpty)
			#expect(try !DocumentCompatibility.analyze(ProPresenterDocument(payload: .presentation(presentation), origin: .raw(corpus))).canWrite)
			let nativeRenderer = PresentationRenderer(document: native)
			let exportedRenderer = PresentationRenderer(document: exported)
			for (nativeCue, exportedCue) in zip(native.orderedCues, exported.orderedCues) {
				let actual = try image(nativeRenderer.render(cue: nativeCue))
				let reference = try image(exportedRenderer.render(cue: exportedCue))
				if let failure = Snapshotting<NSImage, NSImage>.proCRUDImage().diffing.diffV2(reference, actual) {
					Issue.record(Comment(rawValue: failure.0))
				}
			}
			#expect(source.snapshot == original)
			#expect(try source.protobufProjection().presentation() == presentation)
			#expect(try !nativeRenderer.effectiveRendering().slides.isEmpty)
		}
	}

	@Test func olderFilePropertiesDoNotImplyNative22Identity() throws {
		let playlist = corpus.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ProPresenter/ReferenceSlides.proPlaylist")
		let documents = try PresentationLoader.loadPresentations(from: playlist)
		var legacyMediaCount = 0
		for document in documents {
			let references = try MediaReference.collect(protobuf: document.document.presentation.serializedData(), messageType: Rv_Data_Presentation.protoMessageName)
			legacyMediaCount += references.count
			#expect(references.allSatisfy { $0.assetID == nil && $0.identitySchemaVersion == nil })
			let view = try NativeMediaRendering.compatibilityView(document.document.presentation, contextRoot: document.document.mediaDirectory)
			#expect(view == document.document.presentation)
		}
		#expect(legacyMediaCount == 8)
	}

	@Test func loadedNativeReferencesRetainAllEightOriginalExportHashes() throws {
		struct Provenance: Decodable {
			struct Image: Decodable { let path: String; let sha256: String }
			let build: String; let images: [Image]
		}
		let root = corpus.appendingPathComponent("LoadedMedia")
		let proof = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: root.appendingPathComponent("provenance.json")))
		#expect(proof.build == "369098875" && proof.images.count == 8)
		for entry in proof.images {
			let data = try Data(contentsOf: root.appendingPathComponent(entry.path))
			#expect(Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined() == entry.sha256)
			let image = try #require(NSBitmapImageRep(data: data))
			#expect(image.pixelsWide == 854 && image.pixelsHigh == 480)
		}
	}

	@Test func transparentPNGMatchesLoadedNativeExportAtTheExisting21ComparisonPrecision() throws {
		let document = try PresentationLoader.load(from: corpus.appendingPathComponent("Documents/08 - Media Elements.pro"))
		let actual = try image(PresentationRenderer(document: document).render(cue: document.orderedCues[1]))
		let reference = try #require(NSImage(contentsOf: corpus.appendingPathComponent("LoadedMedia/Images/08 - Media Elements/2.png")))
		// The unchanged 21 reference test uses this same comparison strategy.
		if let failure = Snapshotting<NSImage, NSImage>.proCRUDImage(precision: 0.985, perceptualPrecision: 0.5).diffing.diffV2(reference, actual) {
			Issue.record(Comment(rawValue: failure.0))
		}
	}

	@Test func selectedSourceOverridesStaleRootAndLegacyFileWithoutRewritingTheDocument() throws {
		let document = try nativeImageDocument()
		let original = try selectedMedia(document).serializedData()
		var url = Rv_Data_URL(); url.relativePath = "Media/Assets/LogoTransparent.png"
		let source = try field(3, field(1, field(1, url.serializedData())))
		let current = try Rv_Data_Media(serializedBytes: original + field(5, source))
		let staleFile = try field(2, field(1, Rv_Data_URL.with { $0.relativePath = "Missing/stale.png" }.serializedData()))
		let replaced = try Rv_Data_Media(serializedBytes: current.serializedData() + field(2, Rv_Data_URL.with { $0.absoluteString = "file:///stale.png" }.serializedData()) + field(5, staleFile))
		let changed = replacingMedia(in: document, with: replaced)
		let sourceBytes = try changed.presentation.serializedData()
		let reference = try image(PresentationRenderer(document: document).render(cue: document.orderedCues[0]))
		let actual = try image(PresentationRenderer(document: changed).render(cue: changed.orderedCues[0]))
		#expect(Snapshotting<NSImage, NSImage>.proCRUDImage().diffing.diffV2(reference, actual) == nil)
		#expect(try changed.presentation.serializedData() == sourceBytes)
		#expect(try MediaReference(media: selectedMedia(changed)).locators.count == 3)
	}

	@Test func nativeImageTypeDeterminesDecodingEvenWithAVideoFilenameExtension() throws {
		var document = try nativeImageDocument()
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let renamed = directory.appendingPathComponent("OwnedImage.mp4")
		try FileManager.default.copyItem(at: corpus.appendingPathComponent("Documents/Media/Assets/LogoTransparent.png"), to: renamed)
		let media = try selectedMedia(document)
		let source = try field(5, field(3, field(1, field(1, Rv_Data_URL.with { $0.absoluteString = renamed.absoluteString }.serializedData()))))
		let reference = try image(PresentationRenderer(document: document).render(cue: document.orderedCues[0]))
		document = try replacingMedia(in: document, with: Rv_Data_Media(serializedBytes: media.serializedData() + source))
		let actual = try image(PresentationRenderer(document: document).render(cue: document.orderedCues[0]))
		#expect(Snapshotting<NSImage, NSImage>.proCRUDImage().diffing.diffV2(reference, actual) == nil)
	}

	@Test func missingActiveFileNeverFallsBackToAnExistingRootOrSameBasename() throws {
		let document = try nativeImageDocument()
		var media = try selectedMedia(document)
		media.url = .with { $0.absoluteString = corpus.appendingPathComponent("Documents/Media/Assets/LogoTransparent.png").absoluteString }
		let stale = try field(5, field(3, field(1, field(1, Rv_Data_URL.with { $0.relativePath = "Missing/LogoTransparent.png" }.serializedData()))))
		media = try Rv_Data_Media(serializedBytes: media.serializedData() + stale)
		let missing = replacingMedia(in: document, with: media)
		#expect(missing.renderingDiagnostics.contains { $0.code == .unsupportedNativeMedia && $0.severity == .error })
		#expect(throws: (any Error).self) { try PresentationRenderer(document: missing).render(cue: missing.orderedCues[0]) }
		#expect(throws: NativeSemanticError.self) { try NativeMediaRendering.resolvedFile(selectedMedia(document), contextRoot: nil) }
	}

	@Test func unsupportedSourcesColorAlphaBlurAndUnknownFieldsRemainExplicitErrors() throws {
		let document = try nativeImageDocument()
		let original = try selectedMedia(document).serializedData()
		let variants = try [
			field(11, Data("2".utf8)), field(13, Data()), field(99, Data()),
			field(3, scalar(6, 2)), // HDR metadata.
			field(5, field(1, scalar(15, 2))), // Premultiplied alpha.
			field(5, field(1, scalar(16, 1))), // Scale + blur.
			field(5, field(3, field(2, field(1, Data("https://example.invalid/live.m3u8".utf8))))),
			field(5, field(3, field(1, field(1, Rv_Data_URL.with { $0.relativePath = "Media/Assets/LogoTransparent.png" }.serializedData()) + field(99, Data())))),
		]
		for extra in variants {
			let media = try Rv_Data_Media(serializedBytes: original + extra)
			let unsupported = replacingMedia(in: document, with: media)
			#expect(unsupported.renderingDiagnostics.contains { $0.code == .unsupportedNativeMedia && $0.severity == .error })
			#expect(throws: (any Error).self) { try PresentationRenderer(document: unsupported).render(cue: unsupported.orderedCues[0]) }
			#expect(try selectedMedia(unsupported).serializedData() == media.serializedData())
		}
	}

	private func nativeImageDocument() throws -> PresentationDocument {
		var presentation = try stream("08 - Media Elements").protobufProjection().presentation()
		presentation.cues = [presentation.cues[1]]
		presentation.cueGroups = []
		return .init(presentation: presentation, mediaDirectory: corpus.appendingPathComponent("Documents"))
	}

	private func selectedMedia(_ document: PresentationDocument) throws -> Rv_Data_Media {
		try #require(document.presentation.cues.first?.actions.first?.slide.presentation.baseSlide.elements.first?.element.fill.media)
	}

	private func replacingMedia(in document: PresentationDocument, with media: Rv_Data_Media) -> PresentationDocument {
		var document = document
		document.presentation.cues[0].actions[0].slide.presentation.baseSlide.elements[0].element.fill.media = media
		return document
	}

	private func stream(_ name: String) throws -> NativeWorkspaceStream {
		let data = try Data(contentsOf: corpus.appendingPathComponent("Native/\(name).loro"))
		let vector = try Data(contentsOf: corpus.appendingPathComponent("Native/\(name).vector"))
		let presentation = try PresentationLoader.load(from: corpus.appendingPathComponent("Documents/\(name).pro")).presentation
		return try .init(identity: .init(documentID: #require(UUID(uuidString: presentation.uuid.string)), scope: .shared, kind: "Presentation", corePath: "Default/\(name)", availability: .available, byteCount: Int64(data.count), sha256: Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined(), updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
	}

	private func image(_ bitmap: NSBitmapImageRep) -> NSImage {
		let image = NSImage(size: bitmap.size); image.addRepresentation(bitmap); return image
	}

	private func field(_ number: Int, _ payload: Data) -> Data {
		ProtobufJSONPatcher.WireField.lengthDelimited(number: number, payload: payload).raw
	}

	private func scalar(_ number: Int, _ value: UInt64) -> Data {
		func varint(_ input: UInt64) -> Data {
			var value = input; var data = Data()
			while value > 127 {
				data.append(UInt8(value & 127) | 128); value >>= 7
			}
			data.append(UInt8(value)); return data
		}
		return varint(UInt64(number << 3)) + varint(value)
	}

	private var corpus: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Rendering/ReferenceSlides")
	}
}
