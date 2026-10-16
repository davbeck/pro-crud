import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite("Explicit ProPresenter output targets")
struct DocumentCompatibilityTests {
	@Test(arguments: ProPresenterTargetVersion.allCases, DocumentKind.allCases)
	func commonConstructionUsesRequestedProfile(target: ProPresenterTargetVersion, kind: DocumentKind) throws {
		let payload: DocumentPayload = switch kind {
		case .presentation: .presentation(DocumentFactory.presentation(name: "Profile", targetVersion: target))
		case .theme: .theme(DocumentFactory.theme(targetVersion: target))
		case .playlist: .playlist(DocumentFactory.playlist(name: "Profile", targetVersion: target))
		}
		let document = ProPresenterDocument(payload: payload, origin: .raw(URL(fileURLWithPath: "/Profile")))
		let report = try DocumentCompatibility.analyze(document, target: target)
		#expect(report.profile.targetVersion == target)
		#expect(report.canWrite)
		#expect(report.issues.isEmpty)
		#expect(DocumentCompatibility.sourceApplicationMajorVersion(payload) == (target == .v21 ? 7 : 22))
	}

	@Test
	func defaultConstructionAndExportSelect22() throws {
		let presentation = DocumentFactory.presentation(name: "Default")
		#expect(presentation.applicationInfo.applicationVersion.majorVersion == 22)
		#expect(DocumentFactory.theme().applicationInfo.applicationVersion.majorVersion == 22)
		#expect(DocumentFactory.playlist(name: "Default").applicationInfo.applicationVersion.majorVersion == 22)
		try withDirectory { root in
			let url = root.appendingPathComponent("Default.pro")
			let document = ProPresenterDocument(payload: .presentation(presentation), origin: .raw(url))
			try DocumentWriter.writeRaw(document, to: url)
			let bundle = try DocumentArchive.bundleWithReport(url)
			#expect(bundle.compatibility.profile.targetVersion == .v22)
		}
	}

	@Test
	func downgradeReportsEveryOpaqueFieldAndUnknownEnumWithoutPublishing() throws {
		try withDirectory { root in
			let source = root.appendingPathComponent("Source.pro")
			var presentation = DocumentFactory.presentation(name: "Future")
			var cueBytes = try presentation.cues[0].serializedData()
			cueBytes.append(contentsOf: [0xA0, 0x3E, 0x7B])
			presentation.cues[0] = try Rv_Data_Cue(serializedBytes: cueBytes)
			presentation.cues[0].actions[0].type = .UNRECOGNIZED(987)
			var bytes = try presentation.serializedData()
			bytes.append(contentsOf: [0xA0, 0x3E, 0x7B])
			try bytes.write(to: source)
			let document = try DocumentLoader.load(from: source)
			let report = try DocumentCompatibility.analyze(document, target: .v21)
			#expect(!report.canWrite)
			#expect(report.issues.count(where: { $0.feature == "unknown-field" }) == 2)
			#expect(report.issues.contains { $0.feature == "unknown-enum-value" && $0.componentPath.contains("/actions[index=0]/type") })
			#expect(report.issues.allSatisfy { $0.targetVersion == .v21 && $0.availableConversion == "unsupported" })
			let output = root.appendingPathComponent("Existing.probundle")
			let sentinel = Data("existing output".utf8)
			try sentinel.write(to: output)
			#expect(throws: DocumentCompatibilityError.self) {
				try DocumentArchive.bundleWithReport(source, to: output, replace: true, targetVersion: .v21)
			}
			#expect(try Data(contentsOf: output) == sentinel)
			#expect(try Data(contentsOf: source) == bytes)
			let preserved = try DocumentCompatibility.analyze(document, target: .v22)
			#expect(preserved.canWrite)
			#expect(preserved.issues.allSatisfy { $0.severity == .warning })
		}
	}

	@Test
	func activeV2GraphCannotBeEditedPackagedOrRenderedThroughOldArrays() throws {
		try withDirectory { root in
			let url = root.appendingPathComponent("Mixed.pro")
			var bytes = try DocumentFactory.presentation(name: "Mixed old and v2").serializedData()
			bytes.append(contentsOf: [0xC2, 0x01, 0x00]) // Presentation.cue_group_placements = 24
			try bytes.write(to: url)
			let document = try DocumentLoader.load(from: url)
			let report = try DocumentCompatibility.analyze(document)
			#expect(report.issues.contains { $0.feature == "cue-group-placement-tree" && $0.severity == .error })
			#expect(!DocumentValidator.validate(document).valid)
			#expect(throws: DocumentCompatibilityError.self) { try DocumentEditSession.open(url) }
			#expect(throws: DocumentCompatibilityError.self) { try DocumentArchive.bundle(url) }
			let presentation = try PresentationLoader.load(from: url)
			#expect(throws: DocumentCompatibilityError.self) { try PresentationRenderer(document: presentation).effectiveRendering() }
			#expect(try Data(contentsOf: url) == bytes)
		}
	}

	@Test
	func exportAnalysisIncludesAllEmbeddedPresentations() throws {
		try withDirectory { root in
			for name in ["First", "Second"] {
				var bytes = try DocumentFactory.presentation(name: name).serializedData()
				bytes.append(contentsOf: [0xA0, 0x3E, 0x7B])
				try bytes.write(to: root.appendingPathComponent("\(name).pro"))
			}
			let report = try DocumentCompatibility.analyzeExportContents(in: root, target: .v21)
			#expect(report.issues.count == 2)
			#expect(report.issues.map(\.componentPath) == ["First.pro/field[996][index=0]", "Second.pro/field[996][index=0]"])
		}
	}

	@Test
	func plainEditsRetainAbsentMetadataAndSource21Semantics() throws {
		try withDirectory { root in
			let url = root.appendingPathComponent("Source.pro")
			var presentation = DocumentFactory.presentation(name: "Source", targetVersion: .v21)
			presentation.clearApplicationInfo()
			try presentation.serializedData().write(to: url)
			let session = try DocumentEditSession.open(url)
			try DocumentEditor.rename(&session.document, at: ComponentPath("/cues[index=0]"), to: "Edited")
			try session.write(to: url, replace: true)
			let reloaded = try DocumentLoader.load(from: url)
			#expect(DocumentCompatibility.sourceApplicationMajorVersion(reloaded.payload) == nil)
		}
	}

	private func withDirectory(_ body: (URL) throws -> Void) throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		try body(directory)
	}
}
