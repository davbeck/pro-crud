import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite("Workspace compatibility boundary")
struct WorkspaceCompatibilityTests {
	@Test(arguments: ["workspace-v1.sqlite3", "workspace-storage-v1", "workspace-id"])
	func nativeMarkersTakePrecedenceOverLegacyLeftovers(marker: String) throws {
		let root = try directory()
		defer { try? FileManager.default.removeItem(at: root) }
		let store = root.appendingPathComponent("DocumentStore")
		try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
		try Data("future-or-incomplete".utf8).write(to: store.appendingPathComponent(marker))
		let raw = root.appendingPathComponent("Leftover.pro")
		try DocumentFactory.presentation(name: "Leftover").serializedData().write(to: raw)
		let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
		let report = try WorkspaceInspector.inspect(root)
		#expect(report.storage == .nativeLoro)
		#expect(report.evidence == ["DocumentStore/\(marker)"])
		#expect(throws: WorkspaceInspectionError.self) { try DocumentLoader.load(from: root) }
		#expect(throws: WorkspaceInspectionError.self) { try DocumentLoader.load(from: raw) }
		#expect(throws: WorkspaceInspectionError.self) { try DocumentArchive.bundle(root) }
		#expect(throws: WorkspaceInspectionError.self) { try LookResolver.resolve(workspace: root, look: "Main", screen: "Audience") }
		#expect(throws: WorkspaceInspectionError.self) { try PlaylistMediaSource.select(from: root, playlist: "Media", item: "A") }
		let document = ProPresenterDocument(payload: .presentation(DocumentFactory.presentation(name: "A")), origin: .raw(raw))
		let validation = try StrictMediaValidator.validate(document, workspaceURL: root)
		#expect(!validation.isValid)
		#expect(validation.diagnostics.map(\.kind) == [.unsupportedWorkspace])
		#expect(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted() == before)
		#expect(try Data(contentsOf: store.appendingPathComponent(marker)) == Data("future-or-incomplete".utf8))
	}

	@Test
	func explicitlySelectedLegacySiblingRemainsEditable() throws {
		let parent = try directory()
		defer { try? FileManager.default.removeItem(at: parent) }
		let legacy = parent.appendingPathComponent("Custom Name/Libraries/Songs")
		try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
		let native = parent.appendingPathComponent("New/DocumentStore")
		try FileManager.default.createDirectory(at: native, withIntermediateDirectories: true)
		try Data("sqlite-v1\n".utf8).write(to: native.appendingPathComponent("workspace-storage-v1"))
		let raw = legacy.appendingPathComponent("A.pro")
		try DocumentFactory.presentation(name: "A").serializedData().write(to: raw)
		let root = parent.appendingPathComponent("Custom Name")
		#expect(try WorkspaceInspector.inspect(root).storage == .legacyProtobuf)
		#expect(throws: WorkspaceInspectionError.self) { try DocumentLoader.load(from: root) }
		let document = try DocumentLoader.load(from: raw)
		try DocumentWriter.writeRaw(document, to: raw, replace: true)
		#expect(try DocumentLoader.load(from: raw).kind == .presentation)
	}

	@Test
	func arbitrarySQLiteIsNotAWorkspaceAndMissingRegistryCannotPass() throws {
		let root = try directory()
		defer { try? FileManager.default.removeItem(at: root) }
		try Data().write(to: root.appendingPathComponent("other.sqlite3"))
		#expect(try WorkspaceInspector.inspect(root).storage == .unrecognized)
		let document = ProPresenterDocument(payload: .presentation(DocumentFactory.presentation(name: "A")), origin: .raw(root.appendingPathComponent("A.pro")))
		let report = try StrictMediaValidator.validate(document, workspaceURL: root)
		#expect(!report.isValid)
		#expect(report.diagnostics.map(\.kind) == [.missingRegistry])
	}

	@Test
	func legacyExportReportsOccurrenceAndConsolidatedWarningsSeparately() throws {
		let root = try directory()
		defer { try? FileManager.default.removeItem(at: root) }
		let metadata = root.appendingPathComponent(".procore")
		try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
		try Data(#"{"version":1,"target_contract":"current_pro7","missing_media_policy":"preserve_and_report","documents":[{"reopened":true},{"reopened":false}],"media_references":[{},{}],"compatibility_warnings":["one","two","three"],"preserved_media":[{}]}"#.utf8)
			.write(to: metadata.appendingPathComponent("legacy-export-manifest.json"))
		let report = try WorkspaceInspector.inspect(root)
		#expect(report.storage == .legacyExport)
		let manifest = try #require(report.legacyExportManifest)
		#expect(manifest.targetContract == "current_pro7")
		#expect(manifest.mediaPolicy == "preserve_and_report")
		#expect(manifest.documentCount == 2)
		#expect(manifest.reopenedDocumentCount == 1)
		#expect(manifest.copiedMediaReferenceCount == 2)
		#expect(manifest.compatibilityWarningCount == 3)
		#expect(manifest.preservedMediaCount == 1)
	}

	private func directory() throws -> URL {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}
}

@Suite("Optional interchange application metadata")
struct OptionalApplicationMetadataTests {
	@Test(arguments: DocumentKind.allCases)
	func missingMetadataRoundTripsWithoutInventingAnApplication(kind: DocumentKind) throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let payload: DocumentPayload
		let name: String
		switch kind {
		case .presentation:
			var message = DocumentFactory.presentation(name: "Metadata-free")
			message.clearApplicationInfo()
			payload = .presentation(message)
			name = "A.pro"
		case .theme:
			var message = DocumentFactory.theme()
			DocumentEditor.addTemplate(to: &message, name: "Template")
			message.clearApplicationInfo()
			payload = .theme(message)
			name = "Theme"
		case .playlist:
			var message = DocumentFactory.playlist(name: "Metadata-free")
			message.clearApplicationInfo()
			payload = .playlist(message)
			name = "data"
		}
		// An unknown field must survive alongside absent optional metadata.
		var bytes = try payload.serializedData()
		bytes.append(contentsOf: [0xA0, 0x3E, 0x7B]) // field 996, varint 123
		let url = root.appendingPathComponent(name)
		try bytes.write(to: url)
		let loaded = try DocumentLoader.load(from: url)
		#expect(!DocumentValidator.structuralDiagnostics(in: loaded).contains { $0.severity == .error })
		try DocumentWriter.writeRaw(loaded, to: url, replace: true)
		#expect(try Data(contentsOf: url) == bytes)
		let object = try JSONSerialization.jsonObject(with: loaded.payload.jsonUTF8Data()) as? [String: Any]
		#expect(object?["applicationInfo"] == nil)
	}

	@Test(arguments: DocumentKind.allCases)
	func arbitraryUnknownOnlyBytesAreNotRootIdentity(kind: DocumentKind) {
		#expect(throws: DocumentLoadError.self) {
			try DocumentLoader.decode(Data([0xA0, 0x3E, 0x7B]), as: kind, location: "negative-control")
		}
	}
}
