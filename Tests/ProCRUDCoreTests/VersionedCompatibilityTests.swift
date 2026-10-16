import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite("ProPresenter 21 native-export compatibility")
struct ProPresenter21CompatibilityTests {
	@Test func commonEditsPreserveSourceSemantics() throws {
		try verifyCommonEdits(version: .v21)
	}

	@Test func nativePlaylistExportRetainsItsPayload() throws {
		let source = fixtureRoot.appendingPathComponent("ProPresenter/ReferenceSlides.proPlaylist")
		let loaded = try DocumentLoader.load(from: source)
		#expect(loaded.kind == .playlist)
		#expect(try PresentationLoader.loadPresentations(from: source).count == 9)
		#expect(try loaded.payload.serializedData() == DocumentLoader.decode(loaded.payload.serializedData(), as: .playlist, location: "native-21").serializedData())
	}
}

@Suite("ProPresenter 22 native-export compatibility")
struct ProPresenter22CompatibilityTests {
	@Test func commonEditsPreserveSourceSemantics() throws {
		try verifyCommonEdits(version: .v22)
	}

	@Test func nativeSnapshotAndInterchangeKeepDistinctRootIdentities() throws {
		let exported = try DocumentLoader.load(from: fixtureRoot.appendingPathComponent("ProPresenter22/Interchange/NativePresentation.pro"))
		guard case let .presentation(presentation) = exported.payload else { Issue.record("Expected native presentation export"); return }
		#expect(presentation.uuid.string.uppercased() == "48E32307-7A5A-56CC-8CCA-0BC82D6079C1")
		#expect(presentation.cues[0].uuid.string == "3F5D0BA4-F73A-4F1D-B66B-09B3C42E45FA")
	}
}

private var fixtureRoot: URL {
	URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
}

private func verifyCommonEdits(version: ProPresenterTargetVersion) throws {
	let source: PresentationDocument
	switch version {
	case .v21:
		source = try #require(PresentationLoader.loadPresentations(from: fixtureRoot.appendingPathComponent("ProPresenter/ReferenceSlides.proPlaylist")).first).document
	case .v22:
		source = try PresentationLoader.load(from: fixtureRoot.appendingPathComponent("ProPresenter22/Interchange/NativePresentation.pro"))
	}
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let url = root.appendingPathComponent("Editable.pro")
	let original = source.presentation
	try original.serializedData().write(to: url)
	let session = try DocumentEditSession.open(url)
	guard case var .presentation(presentation) = session.document.payload else { Issue.record("Expected presentation"); return }
	let group = try DocumentEditor.addCueGroup(to: &presentation, name: "Additional")
	try DocumentEditor.addBlankSlide(to: &presentation, groupPath: ComponentPath("/cue_groups[uuid=\"\(group)\"]"))
	let first = try ComponentPath("/cue_groups[uuid=\"\(presentation.cueGroups[0].group.uuid.string)\"]")
	let added = try ComponentPath("/cue_groups[uuid=\"\(group)\"]")
	let arrangementID = try DocumentEditor.addArrangement(to: &presentation, name: "Repeated", groupPaths: [first, added, first], select: true)
	#expect(presentation.arrangements.last?.groupIdentifiers.map(\.string) == [presentation.cueGroups[0].group.uuid.string, group, presentation.cueGroups[0].group.uuid.string])
	let slide = try ComponentPath("/cues[index=0]/actions[index=0]/slide/presentation/base_slide")
	let elementID = try DocumentEditor.addElement(to: &presentation, at: slide, name: "Editable text", bounds: CGRect(x: 20, y: 20, width: 500, height: 200), color: DocumentEditor.color(hex: "#FFFFFF"))
	let text = try ComponentPath("\(slide)/elements[uuid=\"\(elementID)\"]/element/text")
	try DocumentEditor.setText(in: &presentation, at: text, to: "First line\nSecond line")
	try DocumentEditor.setTextDelivery(in: &presentation, at: text, initiallyVisible: 1)
	session.document.payload = .presentation(presentation)
	try session.write(to: url, replace: true)
	let loaded = try DocumentLoader.load(from: url)
	guard case let .presentation(result) = loaded.payload else { Issue.record("Expected edited presentation"); return }
	#expect(result.hasApplicationInfo == original.hasApplicationInfo)
	#expect(result.applicationInfo == original.applicationInfo)
	#expect(result.uuid == original.uuid)
	#expect(result.unknownFields == original.unknownFields)
	#expect(result.cues.count == original.cues.count + 1)
	#expect(result.selectedArrangement.string == arrangementID)
	#expect(!DocumentValidator.structuralDiagnostics(in: loaded).contains { $0.severity == .error })
}
