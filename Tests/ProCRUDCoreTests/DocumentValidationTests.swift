import CustomDump
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite("Document validation")
struct DocumentValidationTests {
	@Test
	func combinesStoredReferenceAndRenderingDiagnostics() {
		var presentation = DocumentFactory.presentation(name: "Invalid")
		presentation.selectedArrangement.string = "UNKNOWN-ARRANGEMENT"
		presentation.cues[0].actions[0].slide.presentation.baseSlide.size.width = 0
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Invalid.pro")),
		)

		let report = DocumentValidator.validate(document)

		#expect(!report.valid)
		#expect(report.diagnostics.contains {
			$0.code == "structure.unknown-selected-arrangement" && $0.severity == .error
		})
		#expect(report.diagnostics.contains {
			$0.code == RenderingDiagnostic.Code.invalidCanvasSize.rawValue && $0.severity == .error
		})
	}

	@Test
	func validatesArrangementReferencesWithoutInterpretingOrder() {
		var presentation = DocumentFactory.presentation(name: "Arrangement")
		var arrangement = Rv_Data_Presentation.Arrangement()
		arrangement.uuid.string = "ARRANGEMENT-ID"
		arrangement.name = "Service"
		arrangement.groupIdentifiers = [presentation.cueGroups[0].group.uuid]
		presentation.arrangements = [arrangement]
		presentation.selectedArrangement = arrangement.uuid
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Arrangement.pro")),
		)

		let report = DocumentValidator.validate(document)

		#expect(report.valid)
		#expect(!report.diagnostics.contains { $0.code.hasPrefix("structure.") })
	}

	@Test
	func warningsDoNotInvalidateDocument() {
		var presentation = DocumentFactory.presentation(name: "Warning")
		var unreferenced = presentation.cues[0]
		unreferenced.uuid.string = "UNREFERENCED-CUE"
		presentation.cues.append(unreferenced)
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/Warning.pro")),
		)

		let report = DocumentValidator.validate(document)

		#expect(report.valid)
		#expect(report.diagnostics.contains {
			$0.code == "structure.unreferenced-cue" && $0.severity == .warning
		})
	}

	@Test
	func duplicateGroupNamesAreValidButCrossGroupCueOwnershipIsReported() {
		var presentation = DocumentFactory.presentation(name: "Group ownership")
		presentation.cueGroups[0].group.name = "Chorus"
		var secondGroup = presentation.cueGroups[0]
		secondGroup.group.uuid.string = "SECOND-CHORUS"
		presentation.cueGroups.append(secondGroup)
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/GroupOwnership.pro")),
		)

		let report = DocumentValidator.validate(document)
		let structuralCodes = report.diagnostics
			.filter { $0.code.hasPrefix("structure.") }
			.map(\.code)

		#expect(report.valid)
		expectNoDifference(structuralCodes, ["structure.multiple-cue-group-membership"])
		#expect(report.diagnostics.contains {
			$0.code == "structure.multiple-cue-group-membership" && $0.severity == .warning
		})
	}

	@Test
	func diagnosticCueIndexUsesNativeOrderAndRoundTrips() throws {
		var presentation = DocumentFactory.presentation(name: "Native order")
		try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath("/cue_groups[index=0]"),
		)
		try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath("/cue_groups[index=0]"),
		)
		presentation.cues[0].uuid.string = ""
		presentation.cueGroups[0].cueIdentifiers = [
			presentation.cues[2].uuid,
			presentation.cues[1].uuid,
		]
		let document = ProPresenterDocument(
			payload: .presentation(presentation),
			origin: .raw(URL(fileURLWithPath: "/tmp/NativeOrder.pro")),
		)

		let diagnostics = DocumentValidator.structuralDiagnostics(in: document)
		let missingUUID = try #require(diagnostics.first { $0.code == "structure.missing-cue-uuid" })
		#expect(missingUUID.componentPath == "/cues[index=2]")
		let selection = try ComponentResolver.resolve(ComponentPath(missingUUID.componentPath), in: document)
		#expect(selection.jsonObject["name"] as? String == "Slide 1")
		#expect(selection.canonicalPath == missingUUID.componentPath)
	}

	@Test
	func coversPresentationAndPlaylistLoaderGates() {
		let presentationReport = DocumentValidator.validate(ProPresenterDocument(
			payload: .presentation(Rv_Data_Presentation()),
			origin: .raw(URL(fileURLWithPath: "/tmp/Empty.pro")),
		))
		let presentationCodes = Set(presentationReport.diagnostics.map(\.code))
		#expect(presentationCodes.isSuperset(of: [
			"structure.missing-application-info",
			"structure.missing-presentation-uuid",
			"structure.missing-presentation-name",
			"structure.missing-presentation-cues",
			"structure.missing-presentation-cue-groups",
		]))

		let playlistReport = DocumentValidator.validate(ProPresenterDocument(
			payload: .playlist(Rv_Data_PlaylistDocument()),
			origin: .raw(URL(fileURLWithPath: "/tmp/data")),
		))
		let playlistCodes = Set(playlistReport.diagnostics.map(\.code))
		#expect(playlistCodes.isSuperset(of: [
			"structure.missing-application-info",
			"structure.missing-playlist-type",
			"structure.missing-playlist-root",
		]))
	}

	@Test
	func validatesEveryThemeDocumentWithStructuredDocumentPath() {
		let source = DocumentFactory.presentation(name: "Template source")
		var validTheme = DocumentFactory.theme()
		var template = Rv_Data_Template.Slide()
		template.name = "Valid"
		template.baseSlide = source.cues[0].actions[0].slide.presentation.baseSlide
		validTheme.slides = [template]

		var invalidTheme = validTheme
		invalidTheme.clearApplicationInfo()
		invalidTheme.slides[0].baseSlide.clearUuid()
		invalidTheme.slides[0].baseSlide.clearSize()
		let document = ProPresenterDocument(
			payload: .theme(validTheme),
			origin: .archive(URL(fileURLWithPath: "/tmp/Themes.proTheme")),
			themeEntries: [
				.init(relativePath: "Valid/Theme", document: validTheme),
				.init(relativePath: "Invalid/Theme", document: invalidTheme),
			],
		)

		let report = DocumentValidator.validate(document)

		#expect(!report.valid)
		#expect(report.diagnostics.contains {
			$0.code == "structure.missing-application-info" &&
				$0.documentPath == "Invalid/Theme" &&
				$0.componentPath == "/"
		})
		#expect(report.diagnostics.contains {
			$0.code == "structure.missing-template-slide-uuid" &&
				$0.documentPath == "Invalid/Theme" &&
				$0.componentPath.hasPrefix("/slides[")
		})
		#expect(report.diagnostics.contains {
			$0.code == "structure.invalid-template-canvas-size" &&
				$0.documentPath == "Invalid/Theme"
		})
	}

	@Test
	func validationLoadingPreservesUnknownFieldsInStructurallyInvalidDocuments() throws {
		var presentation = DocumentFactory.presentation(name: "Unknown fields")
		presentation.cues.append(presentation.cues[0])
		var bytes = try presentation.serializedData()
		let unknownField: [UInt8] = [0xA0, 0x06, 0x01]
		bytes.append(contentsOf: unknownField)
		let input = FileManager.default.temporaryDirectory
			.appendingPathComponent("pro-crud-validation-unknown-\(UUID().uuidString).pro")
		try bytes.write(to: input)
		defer { try? FileManager.default.removeItem(at: input) }

		let document = try DocumentLoader.loadForValidation(from: input)
		let encoded = try document.payload.serializedData()
		#expect(encoded.contains(unknownField))
		#expect(DocumentValidator.validate(document).diagnostics.contains {
			$0.code == "structure.duplicate-cue-uuid"
		})
	}
}
