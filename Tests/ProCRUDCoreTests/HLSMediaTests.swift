import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("HLS runtime media")
struct HLSMediaTests {
	@Test func nativeExportsKeepTheirRuntimeLocatorAndIndependentIdentity() throws {
		for name in ["NativeBundle", "NativeStandalone"] {
			let presentation = try load(name)
			let reference = try MediaReference(media: media(in: presentation))
			#expect(reference.dependencyKind == .remoteStream)
			#expect(reference.kind == "video")
			#expect(reference.referenceID == "473204A8-A75F-4D4A-8B7B-7518C1497D26")
			#expect(reference.assetID == "92C2701D-3874-4D50-8F8D-A2A52BEF730F")
			#expect(reference.identitySchemaVersion == "1")
			#expect(reference.activeLocators.map(\.remote) == ["http://127.0.0.1:61541/stream.m3u8"])
			#expect(try !DocumentCompatibility.analyze(document(presentation)).canWrite)
		}
	}

	@Test func nativeReimportAndMetadataContinuationPreserveTheCompleteMediaAction() throws {
		let before = try stream("cli-before"), after = try stream("cli-after"), opened = try stream("native-open")
		#expect(after.snapshot == opened.snapshot && after.versionVector == opened.versionVector)
		let original = try before.protobufProjection().presentation(), edited = try after.protobufProjection().presentation()
		let index = try mediaIndex(in: original)
		#expect(try original.cues[0].actions[index].serializedData() == edited.cues[0].actions[index].serializedData())
		#expect(edited.ccli.songTitle == "HLS CLI Metadata")
		#expect(try NativeLocalPatch.prepare(stream: after, edit: .copyrightTitle("HLS CLI Metadata")) == nil)
		let exported = try load("NativeAfterMetadata")
		#expect(exported.ccli.songTitle == edited.ccli.songTitle)
		let exportedMedia = try media(in: exported), editedMedia = try media(in: edited)
		let exportedReference = try MediaReference(media: exportedMedia), editedReference = try MediaReference(media: editedMedia)
		#expect(exportedReference.referenceID == editedReference.referenceID && exportedReference.assetID == editedReference.assetID)
		#expect(exportedReference.identitySchemaVersion == editedReference.identitySchemaVersion)
		#expect(exportedReference.activeLocators == editedReference.activeLocators)
		// Standalone export sets zero-duration fade flags; compare against the
		// independent pre-edit export of the same native action.
		#expect(try exportedMedia.video.transport == media(in: load("NativeStandalone")).video.transport)
		let reimported = try stream("native-reimported", id: "c8698b23-8ed5-54bf-92c1-178ae239d389").protobufProjection().presentation()
		let reference = try MediaReference(media: media(in: reimported)), source = try MediaReference(media: media(in: original))
		#expect(reference.referenceID.caseInsensitiveCompare(source.referenceID) != .orderedSame)
		#expect(reference.assetID?.lowercased() == source.assetID?.lowercased())
		#expect(reference.activeLocators == source.activeLocators)
		#expect(try reimported.cues[0].actions[mediaIndex(in: reimported)].uuid == original.cues[0].actions[index].uuid)
	}

	@Test func runtimeDiagnosticsCoverNativeLegacyAndMediaOnlyCues() throws {
		for nativeIdentity in [true, false] {
			for mediaOnly in [true, false] {
				var presentation = try load("NativeBundle")
				if !nativeIdentity {
					try removeNativeIdentity(from: &presentation)
				}
				if mediaOnly {
					presentation.cues[0].actions.removeAll { $0.type == .presentationSlide }
				}
				let original = try presentation.serializedData()
				let view = PresentationDocument(presentation: presentation)
				#expect(view.renderingDiagnostics.contains {
					$0.code.rawValue == "rendering.unsupported-runtime-media" && $0.severity == .error
				})
				let renderer = PresentationRenderer(document: view)
				#expect(throws: (any Error).self) { try renderer.render(cue: presentation.cues[0]) }
				#expect(throws: (any Error).self) { try renderer.effectiveRendering() }
				#expect(try presentation.serializedData() == original)
			}
		}
	}

	@Test func runtimeSourcesNeverFallBackToAFileOrReplaceRenderOutputs() throws {
		try withDirectory { root in
			var presentation = try load("NativeBundle")
			try removeNativeIdentity(from: &presentation)
			let index = try mediaIndex(in: presentation)
			var media = presentation.cues[0].actions[index].media.element
			media.url.relativePath = "Superseded.mp4"
			presentation.cues[0].actions[index].media.element = media
			let renderer = PresentationRenderer(document: .init(presentation: presentation))
			let sentinel = Data("Existing render output".utf8)
			let png = root.appendingPathComponent("1.png"), pdf = root.appendingPathComponent("Stream.pdf")
			try sentinel.write(to: png); try sentinel.write(to: pdf)
			#expect(throws: (any Error).self) { try renderer.render(options: .init(outputDirectory: root)) }
			#expect(throws: (any Error).self) { try renderer.renderPDF(to: pdf) }
			#expect(try Data(contentsOf: png) == sentinel && Data(contentsOf: pdf) == sentinel)
			presentation.cues[0].actions.remove(at: index)
			let slide = try #require(presentation.cues[0].actions.firstIndex { $0.type == .presentationSlide })
			presentation.cues[0].actions[slide].slide.presentation.baseSlide.elements = [.with { $0.element.fill.media = media }]
			#expect(PresentationDocument(presentation: presentation).renderingDiagnostics.contains { $0.code == .unsupportedRuntimeMedia && $0.componentPath.hasSuffix("/fill/media") })
		}
	}

	@Test func strictFileValidationExcludesStreamsInDocumentsAndRegistry() throws {
		try withDirectory { root in
			let registry = root.appendingPathComponent("Playlists/Media")
			try FileManager.default.createDirectory(at: registry.deletingLastPathComponent(), withIntermediateDirectories: true)
			let presentation = try load("NativeStandalone")
			var playlist = DocumentFactory.playlist(name: "Stream registry")
			var item = Rv_Data_PlaylistItem()
			item.cue = presentation.cues[0]
			playlist.rootNode.playlists.playlists[0].items.items = [item]
			try playlist.serializedData().write(to: registry)
			#expect(try StrictMediaValidator.validate(document(presentation), workspaceURL: root).isValid)
			var missingFile = presentation
			let index = try mediaIndex(in: missingFile)
			missingFile.cues[0].actions[index].media.element = .with {
				$0.video = .init()
				$0.url.relativePath = "Missing.mp4"
			}
			#expect(try StrictMediaValidator.validate(document(missingFile), workspaceURL: root).diagnostics.contains { $0.kind == .missingAsset })
		}
	}

	@Test func bundlingNeverCopiesOrRebasesSupersededFileLocators() throws {
		try withDirectory { root in
			var presentation = try load("NativeBundle")
			try removeNativeIdentity(from: &presentation)
			let stale = root.appendingPathComponent("Superseded.mp4")
			try Data("This must never be packaged".utf8).write(to: stale)
			let index = try mediaIndex(in: presentation)
			presentation.cues[0].actions[index].media.element.url.absoluteString = stale.absoluteString
			let originalMedia = try media(in: presentation).serializedData()
			let source = root.appendingPathComponent("Stream.pro")
			try presentation.serializedData().write(to: source)
			let result = try DocumentArchive.bundleWithReport(source)
			#expect(result.warnings.isEmpty)
			let expanded = try DocumentArchive.expand(result.archiveURL, to: root.appendingPathComponent("expanded"))
			#expect(!FileManager.default.fileExists(atPath: expanded.appendingPathComponent(stale.lastPathComponent).path))
			let bundled = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: expanded.appendingPathComponent("Stream.pro")))
			#expect(try media(in: bundled).serializedData() == originalMedia)
		}
	}

	private func load(_ name: String) throws -> Rv_Data_Presentation {
		try Rv_Data_Presentation(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("\(name).pro")))
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/HLSStream")
	}

	private func stream(_ name: String, id: String = "0b8f0934-0c4a-4056-9129-4a097311109e") throws -> NativeWorkspaceStream {
		let base = fixtures.appendingPathComponent(name), data = try Data(contentsOf: base.appendingPathExtension("loro"))
		return try .init(identity: .init(documentID: #require(UUID(uuidString: id)), scope: .shared, kind: "Presentation", corePath: "Default/ProCRUD Local HLS Control", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: Data(contentsOf: base.appendingPathExtension("vector")), lastSharedVersionVector: nil)
	}

	private func mediaIndex(in presentation: Rv_Data_Presentation) throws -> Int {
		try #require(presentation.cues[0].actions.firstIndex { $0.type == .media })
	}

	private func media(in presentation: Rv_Data_Presentation) throws -> Rv_Data_Media {
		try presentation.cues[0].actions[mediaIndex(in: presentation)].media.element
	}

	private func removeNativeIdentity(from presentation: inout Rv_Data_Presentation) throws {
		let index = try mediaIndex(in: presentation)
		let fields = try MediaWireMessage(media(in: presentation).serializedData()).fields
		presentation.cues[0].actions[index].media.element = try .init(serializedBytes: fields.filter { !(9 ... 13).contains($0.number) }.reduce(into: Data()) { $0.append($1.raw) })
	}

	private func document(_ presentation: Rv_Data_Presentation) -> ProPresenterDocument {
		.init(payload: .presentation(presentation), origin: .raw(URL(fileURLWithPath: "/Stream.pro")))
	}

	private func withDirectory(_ operation: (URL) throws -> Void) throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("HLSMedia-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		try operation(root)
	}
}
