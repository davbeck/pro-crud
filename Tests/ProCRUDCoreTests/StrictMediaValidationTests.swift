import AppKit
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite("Strict media validation")
struct StrictMediaValidationTests {
	@Test
	func reportsMediaIdentityFailuresWithComponentPaths() throws {
		try withTemporaryWorkspace { workspace in
			let assetA = workspace.appendingPathComponent("Media/Assets/A.png")
			let assetB = workspace.appendingPathComponent("Media/Assets/B.png")
			let assetC = workspace.appendingPathComponent("Media/Assets/C.png")
			let assetWithoutIdentity = workspace.appendingPathComponent("Media/Assets/No Identity.png")
			let canonical = workspace.appendingPathComponent("Media/Assets/Canonical.png")
			try writePNG(to: assetA, width: 2, height: 3)
			try writePNG(to: assetB, width: 4, height: 5)
			try writePNG(to: assetC, width: 2, height: 3)
			try writePNG(to: assetWithoutIdentity, width: 2, height: 3)
			try writePNG(to: canonical, width: 2, height: 3)

			var inconsistent = imageMedia(uuid: "SHARED-ID", url: assetA, width: 9, height: 9)
			inconsistent.url.local.root = .show
			inconsistent.url.local.path = "Media/Assets/B.png"
			let conflicting = imageMedia(uuid: "SHARED-ID", url: assetC, width: 2, height: 3)
			let missing = imageMedia(
				uuid: "MISSING-ID",
				url: workspace.appendingPathComponent("Media/Assets/Missing.png"),
				width: 1,
				height: 1,
			)
			let withoutIdentity = imageMedia(uuid: "", url: assetWithoutIdentity, width: 2, height: 3)
			let document = try presentationDocument(
				workspace: workspace,
				media: [
					(inconsistent, "Wrong.png"),
					(conflicting, "C.png"),
					(missing, "Missing.png"),
					(withoutIdentity, "No Identity.png"),
				],
			)
			try writeRegistry(
				media: imageMedia(uuid: "SHARED-ID", url: canonical, width: 2, height: 3),
				workspace: workspace,
			)

			let report = try StrictMediaValidator.validate(document, workspaceURL: workspace)
			let kinds = Set(report.diagnostics.map(\.kind))
			#expect(kinds.contains(.inconsistentURL))
			#expect(kinds.contains(.imageDimensions))
			#expect(kinds.contains(.missingAsset))
			#expect(kinds.contains(.missingIdentity))
			#expect(kinds.contains(.conflictingUUID))
			#expect(kinds.contains(.workspaceRegistryConflict))
			#expect(report.diagnostics.allSatisfy { $0.componentPath.hasPrefix("/") })
			#expect(report.diagnostics.contains {
				$0.kind == .missingAsset && $0.message.contains("Missing.png")
			})
		}
	}

	@Test
	func acceptsCanonicalWorkspaceMedia() throws {
		try withTemporaryWorkspace { workspace in
			let asset = workspace.appendingPathComponent("Media/Assets/Good.png")
			try writePNG(to: asset, width: 3, height: 2)
			var media = imageMedia(uuid: "CANONICAL-ID", url: asset, width: 3, height: 2)
			media.url.local.root = .show
			media.url.local.path = "Media/Assets/Good.png"
			let document = try presentationDocument(
				workspace: workspace,
				media: [(media, "Good.png")],
			)
			try writeRegistry(media: media, workspace: workspace)

			let report = try StrictMediaValidator.validate(document, workspaceURL: workspace)
			#expect(report.isValid)
			#expect(report.diagnostics.isEmpty)
		}
	}

	@Test
	func reportsSiblingFilenameLabelAndCanonicalAssetWithWrongUUID() throws {
		try withTemporaryWorkspace { workspace in
			let asset = workspace.appendingPathComponent("Media/Assets/Good.png")
			try writePNG(to: asset, width: 3, height: 2)
			let canonical = imageMedia(uuid: "CANONICAL-ID", url: asset, width: 3, height: 2)
			let wrongIdentity = imageMedia(uuid: "WRONG-ID", url: asset, width: 3, height: 2)
			var document = try presentationDocument(
				workspace: workspace,
				media: [(wrongIdentity, "Media cue")],
			)
			guard case var .presentation(presentation) = document.payload else { return }
			presentation.cues[0].actions[0].label.text = "Old.png"
			document.payload = .presentation(presentation)
			try writeRegistry(media: canonical, workspace: workspace)

			let report = try StrictMediaValidator.validate(document, workspaceURL: workspace)
			#expect(report.diagnostics.contains {
				$0.kind == .labelMismatch && $0.componentPath.hasSuffix("/label")
			})
			#expect(report.diagnostics.contains { $0.kind == .workspaceRegistryConflict })
		}
	}

	@Test
	func presentationDiagnosticsUseNativeCueOrderForIndexFallbacks() throws {
		try withTemporaryWorkspace { workspace in
			let missingAsset = workspace.appendingPathComponent("Media/Assets/Missing.png")
			var presentation = DocumentFactory.presentation(name: "Native cue order")
			try DocumentEditor.addBlankSlide(
				to: &presentation,
				groupPath: ComponentPath("/cue_groups[index=0]"),
			)
			try DocumentEditor.addAction(
				in: &presentation,
				to: ComponentPath("/cues[index=0]"),
				type: "media",
				name: "Missing.png",
			)
			presentation.cues[0].actions[1].media.element = imageMedia(
				uuid: "MISSING-ID",
				url: missingAsset,
				width: 1,
				height: 1,
			)
			presentation.cues[0].uuid.string = ""
			presentation.cueGroups[0].cueIdentifiers = [presentation.cues[1].uuid]
			let document = ProPresenterDocument(
				payload: .presentation(presentation),
				origin: .raw(workspace.appendingPathComponent("Libraries/NativeCueOrder.pro")),
				resourceDirectory: workspace.appendingPathComponent("Libraries"),
			)

			let report = try StrictMediaValidator.validate(document, workspaceURL: workspace)
			let diagnostic = try #require(report.diagnostics.first { $0.kind == .missingAsset })
			#expect(diagnostic.componentPath.hasPrefix("/cues[index=1]/"))
			let mediaPath = String(diagnostic.componentPath.dropLast("/url".count))
			let selection = try ComponentResolver.resolve(ComponentPath(mediaPath), in: document)
			#expect(selection.canonicalPath == mediaPath)
		}
	}

	@Test
	func multiThemeDiagnosticsSeparateDocumentAndComponentPaths() throws {
		try withTemporaryWorkspace { workspace in
			var firstTheme = DocumentFactory.theme()
			var firstTemplate = Rv_Data_Template.Slide()
			firstTemplate.name = "First"
			firstTemplate.baseSlide = DocumentFactory.presentation(name: "First").cues[0].actions[0].slide.presentation.baseSlide
			firstTheme.slides = [firstTemplate]

			var secondTheme = DocumentFactory.theme()
			var secondTemplate = Rv_Data_Template.Slide()
			secondTemplate.name = "Second"
			secondTemplate.baseSlide = DocumentFactory.presentation(name: "Second").cues[0].actions[0].slide.presentation.baseSlide
			var mediaAction = Rv_Data_Action()
			mediaAction.uuid.string = "MISSING-MEDIA-ACTION"
			mediaAction.type = .backgroundMedia
			mediaAction.media.element = imageMedia(
				uuid: "MISSING-MEDIA",
				url: workspace.appendingPathComponent("Media/Missing.png"),
				width: 1,
				height: 1,
			)
			secondTemplate.actions = [mediaAction]
			secondTheme.slides = [secondTemplate]

			let document = ProPresenterDocument(
				payload: .theme(firstTheme),
				origin: .archive(workspace.appendingPathComponent("Themes.proTheme")),
				resourceDirectory: workspace,
				themeEntries: [
					.init(relativePath: "First/Theme", document: firstTheme),
					.init(relativePath: "Second/Theme", document: secondTheme),
				],
			)

			let report = try StrictMediaValidator.validate(document, workspaceURL: workspace)
			let diagnostic = try #require(report.diagnostics.first { $0.kind == .missingAsset })
			#expect(diagnostic.documentPath == "Second/Theme")
			#expect(diagnostic.componentPath.hasPrefix("/slides["))
			#expect(!diagnostic.componentPath.contains("/themes["))
			#expect(diagnostic.description.contains("in Second/Theme at /slides["))

			let selectedDocument = ProPresenterDocument(
				payload: .theme(secondTheme),
				origin: .raw(workspace.appendingPathComponent("Second/Theme")),
			)
			let selection = try ComponentResolver.resolve(ComponentPath(diagnostic.componentPath), in: selectedDocument)
			#expect(selection.canonicalPath == diagnostic.componentPath)
		}
	}

	@Test
	func matchesFilenameLabelsAcrossSiblingActionsWithoutAmbiguousInference() throws {
		try withTemporaryWorkspace { workspace in
			let assetA = workspace.appendingPathComponent("Media/Assets/A.png")
			let assetB = workspace.appendingPathComponent("Media/Assets/B.png")
			try writePNG(to: assetA, width: 2, height: 2)
			try writePNG(to: assetB, width: 2, height: 2)

			let crossMatched = try presentationDocument(
				workspace: workspace,
				media: [
					(imageMedia(uuid: "A-ID", url: assetA, width: 2, height: 2), "B.png"),
					(imageMedia(uuid: "B-ID", url: assetB, width: 2, height: 2), "A.png"),
				],
			)
			let crossMatchedReport = try StrictMediaValidator.validate(crossMatched, workspaceURL: workspace)
			#expect(!crossMatchedReport.diagnostics.contains { $0.kind == .labelMismatch })

			let ambiguous = try presentationDocument(
				workspace: workspace,
				media: [
					(imageMedia(uuid: "A-ID", url: assetA, width: 2, height: 2), "First.png"),
					(imageMedia(uuid: "B-ID", url: assetB, width: 2, height: 2), "Second.png"),
				],
			)
			let ambiguousReport = try StrictMediaValidator.validate(ambiguous, workspaceURL: workspace)
			#expect(!ambiguousReport.diagnostics.contains { $0.kind == .labelMismatch })
		}
	}

	@Test
	func rejectsDirectoriesAndCorruptImageFiles() throws {
		try withTemporaryWorkspace { workspace in
			let directoryAsset = workspace.appendingPathComponent("Media/Assets/Folder.png", isDirectory: true)
			try FileManager.default.createDirectory(at: directoryAsset, withIntermediateDirectories: true)
			let corruptAsset = workspace.appendingPathComponent("Media/Assets/Corrupt.png")
			try Data("not a PNG".utf8).write(to: corruptAsset)
			let document = try presentationDocument(
				workspace: workspace,
				media: [
					(imageMedia(uuid: "DIRECTORY-ID", url: directoryAsset, width: 1, height: 1), "Folder.png"),
					(imageMedia(uuid: "CORRUPT-ID", url: corruptAsset, width: 1, height: 1), "Corrupt.png"),
				],
			)

			let report = try StrictMediaValidator.validate(document, workspaceURL: workspace)
			#expect(report.diagnostics.contains {
				$0.kind == .missingAsset && $0.message.contains("not a regular file")
			})
			#expect(report.diagnostics.contains {
				$0.kind == .invalidImage && $0.message.contains("unreadable or does not contain a valid image")
			})
		}
	}

	private func presentationDocument(
		workspace: URL,
		media: [(Rv_Data_Media, String)],
	) throws -> ProPresenterDocument {
		var presentation = DocumentFactory.presentation(name: "Validation")
		for (value, label) in media {
			try DocumentEditor.addAction(
				in: &presentation,
				to: ComponentPath("/cues[index=0]"),
				type: "media",
				name: label,
			)
			presentation.cues[0].actions[presentation.cues[0].actions.count - 1].media.element = value
		}
		return ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(workspace.appendingPathComponent("Libraries/Validation.pro")),
			resourceDirectory: workspace.appendingPathComponent("Libraries"),
		)
	}

	private func imageMedia(uuid: String, url: URL, width: Double, height: Double) -> Rv_Data_Media {
		var media = Rv_Data_Media()
		media.uuid.string = uuid
		media.url.absoluteString = url.absoluteString
		media.image.drawing.naturalSize.width = width
		media.image.drawing.naturalSize.height = height
		return media
	}

	private func writeRegistry(media: Rv_Data_Media, workspace: URL) throws {
		var action = Rv_Data_Action()
		action.type = .media
		action.media.element = media
		var cue = Rv_Data_Cue()
		cue.actions = [action]
		var item = Rv_Data_PlaylistItem()
		item.name = "Canonical"
		item.cue = cue
		var playlist = DocumentFactory.playlist(name: "Values")
		playlist.rootNode.playlists.playlists[0].items.items = [item]
		let output = workspace.appendingPathComponent("Playlists/Media")
		try DocumentWriter.writeRaw(
			ProPresenterDocument(payload: .playlist(playlist), origin: .raw(output)),
			to: output,
		)
	}

	private func writePNG(to url: URL, width: Int, height: Int) throws {
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: width,
			pixelsHigh: height,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0,
		))
		let data = try #require(bitmap.representation(using: .png, properties: [:]))
		try data.write(to: url)
	}

	private func withTemporaryWorkspace(_ operation: (URL) throws -> Void) throws {
		let workspace = FileManager.default.temporaryDirectory
			.appendingPathComponent("StrictMediaValidation-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: workspace) }
		try operation(workspace)
	}
}
