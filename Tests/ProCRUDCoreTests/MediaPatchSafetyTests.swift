import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite(.timeLimit(.minutes(1)))
struct MediaPatchSafetyTests {
	@Test
	func rejectsURLChangesWithoutADifferentNonemptyUUID() throws {
		let path = try ComponentPath("/cues[index=0]/actions[index=1]/media/element")
		for json in [
			#"{"url":{"absoluteString":"file:///replacement.png"}}"#,
			#"{"url":{"absoluteString":"file:///replacement.png"},"uuid":{"string":"MEDIA-1"}}"#,
			#"{"url":{"absoluteString":"file:///replacement.png"},"uuid":{"string":""}}"#,
		] {
			var document = try mediaDocument()
			#expect(throws: DocumentEditError.self) {
				try DocumentEditor.patch(&document, at: path, jsonData: Data(json.utf8))
			}
			#expect(media(in: document).url.absoluteString == "file:///original.png")
			#expect(media(in: document).uuid.string == "MEDIA-1")
		}
	}

	@Test
	func permitsURLChangesWithANewIdentityOrExplicitRelocation() throws {
		let path = try ComponentPath("/cues[index=0]/actions[index=1]/media/element")
		var replacement = try mediaDocument()
		try DocumentEditor.patch(
			&replacement,
			at: path,
			jsonData: Data(#"{"url":{"absoluteString":"file:///replacement.png"},"uuid":{"string":"MEDIA-2"}}"#.utf8),
		)
		#expect(media(in: replacement).url.absoluteString == "file:///replacement.png")
		#expect(media(in: replacement).uuid.string == "MEDIA-2")

		var relocation = try mediaDocument()
		try DocumentEditor.patch(
			&relocation,
			at: ComponentPath("/cues[index=0]/actions[index=1]/media/element/url"),
			jsonData: Data(#"{"absoluteString":"file:///relocated.png","local":{"path":"Media/relocated.png"}}"#.utf8),
			allowURLOnly: true,
		)
		#expect(media(in: relocation).url.absoluteString == "file:///relocated.png")
		#expect(media(in: relocation).url.local.path == "Media/relocated.png")
		#expect(media(in: relocation).uuid.string == "MEDIA-1")
	}

	@Test
	func catchesURLChangesNestedInsideAContainerPatch() throws {
		var document = try mediaDocument()
		let path = try ComponentPath("/cues[index=0]/actions[index=1]")
		let unsafe = Data(
			#"{"media":{"element":{"url":{"local":{"path":"Media/new.png"}}}}}"#.utf8,
		)
		#expect(throws: DocumentEditError.self) {
			try DocumentEditor.patch(&document, at: path, jsonData: unsafe)
		}

		let safe = Data(
			#"{"media":{"element":{"url":{"local":{"path":"Media/new.png"}},"uuid":{"string":"MEDIA-2"}}}}"#.utf8,
		)
		try DocumentEditor.patch(&document, at: path, jsonData: safe)
		#expect(media(in: document).url.local.path == "Media/new.png")
		#expect(media(in: document).uuid.string == "MEDIA-2")
	}

	@Test
	func ordinaryNonMediaPatchesRemainAllowed() throws {
		var document = try mediaDocument()
		try DocumentEditor.patch(
			&document,
			at: ComponentPath("/cues[index=0]/actions[index=1]"),
			jsonData: Data(#"{"label":{"text":"Semantic label"}}"#.utf8),
		)
		guard case let .presentation(presentation) = document.payload else {
			Issue.record("Expected presentation payload")
			return
		}
		#expect(presentation.cues[0].actions[1].label.text == "Semantic label")
		#expect(presentation.cues[0].actions[1].media.element.uuid.string == "MEDIA-1")
	}

	@Test
	func preserveUUIDRejectsAnEmptyExistingIdentity() throws {
		var document = try mediaDocument(uuid: "")
		var replacement = Rv_Data_Media()
		replacement.uuid.string = "MEDIA-2"
		replacement.url.absoluteString = "file:///replacement.png"
		#expect(throws: DocumentEditError.self) {
			try DocumentEditor.setMedia(
				&document,
				at: ComponentPath("/cues[index=0]/actions[index=1]/media/element"),
				to: replacement,
				preserveUUID: true,
			)
		}
	}

	@Test
	func sourceMediaRejectsDirectoriesAndCorruptImages() throws {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("pro-crud-invalid-media-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let directoryDisguisedAsImage = directory.appendingPathComponent("folder.png", isDirectory: true)
		try FileManager.default.createDirectory(at: directoryDisguisedAsImage, withIntermediateDirectories: true)
		let corruptImage = directory.appendingPathComponent("corrupt.png")
		try Data("not an image".utf8).write(to: corruptImage)

		for source in [directoryDisguisedAsImage, corruptImage] {
			var document = try mediaDocument()
			#expect(throws: DocumentEditError.self) {
				try DocumentEditor.setMedia(
					&document,
					at: ComponentPath("/cues[index=0]/actions[index=1]/media/element"),
					sourceURL: source,
				)
			}
		}
	}

	@Test
	func mediaLabelSyncOnlyReplacesAnOldFilenameLabel() throws {
		var replacement = Rv_Data_Media()
		replacement.uuid.string = "MEDIA-2"
		replacement.url.absoluteString = "file:///Media/Values/CV_Welcome.png"
		let path = try ComponentPath("/cues[index=0]/actions[index=1]/media/element")

		var filenameLabel = try mediaDocument()
		try DocumentEditor.setMedia(&filenameLabel, at: path, to: replacement, syncLabel: true)
		guard case let .presentation(updated) = filenameLabel.payload else {
			Issue.record("Expected presentation payload")
			return
		}
		#expect(updated.cues[0].actions[1].label.text == "CV_Welcome.png")

		var semanticLabel = try mediaDocument()
		guard case var .presentation(presentation) = semanticLabel.payload else { return }
		presentation.cues[0].actions[1].label.text = "Welcome loop"
		semanticLabel.payload = .presentation(presentation)
		try DocumentEditor.setMedia(&semanticLabel, at: path, to: replacement, syncLabel: true)
		guard case let .presentation(semantic) = semanticLabel.payload else { return }
		#expect(semantic.cues[0].actions[1].label.text == "Welcome loop")
	}

	@Test
	func mediaLabelSyncFindsFilenameLabelsOnSiblingActions() throws {
		var document = try mediaDocument()
		guard case var .presentation(presentation) = document.payload else { return }
		presentation.cues[0].actions[1].label.text = ""
		presentation.cues[0].actions[0].label.text = "original.png"
		var semanticSibling = Rv_Data_Action()
		semanticSibling.label.text = "Series welcome"
		presentation.cues[0].actions.append(semanticSibling)
		document.payload = .presentation(presentation)

		var replacement = Rv_Data_Media()
		replacement.uuid.string = "MEDIA-2"
		replacement.url.absoluteString = "file:///Media/Values/CV_Welcome.png"
		try DocumentEditor.setMedia(
			&document,
			at: ComponentPath("/cues[index=0]/actions[index=1]/media/element"),
			to: replacement,
			syncLabel: true,
		)

		guard case let .presentation(updated) = document.payload else { return }
		#expect(updated.cues[0].actions[0].label.text == "CV_Welcome.png")
		#expect(updated.cues[0].actions[1].label.text == "")
		#expect(updated.cues[0].actions[2].label.text == "Series welcome")
	}

	private func mediaDocument(uuid: String = "MEDIA-1") throws -> ProPresenterDocument {
		var presentation = DocumentFactory.presentation(name: "Media patch")
		try DocumentEditor.addAction(
			in: &presentation,
			to: ComponentPath("/cues[index=0]"),
			type: "media",
			name: "original.png",
		)
		presentation.cues[0].actions[1].media.element.uuid.string = uuid
		presentation.cues[0].actions[1].media.element.url.absoluteString = "file:///original.png"
		return ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Media.pro")),
		)
	}

	private func media(in document: ProPresenterDocument) -> Rv_Data_Media {
		guard case let .presentation(presentation) = document.payload else { return Rv_Data_Media() }
		return presentation.cues[0].actions[1].media.element
	}
}
