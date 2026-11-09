import Foundation
import Loro
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite("Native workspace action dependency export")
struct NativeWorkspaceDependencyExportTests {
	@Test func runtimeAndNonportableThemeSelectorsRemainExplicitDependencyErrors() throws {
		try withSource { source, output in
			let closure = NativeWorkspaceDependencyClosure(snapshot: source, directory: output)
			let theme = try #require(source.streams.first { $0.identity.kind == "Theme" })
			let selector = Rv_Data_TemplateIdentification.with { $0.uuid.string = theme.identity.documentID.uuidString; $0.name = "CLI Template Ordering" }
			_ = try closure.exporter.rewrite(selector.serializedData(), message: Rv_Data_TemplateIdentification.protoMessageName, path: "/message/template")
			let runtime = Rv_Data_Action.with { $0.type = .audioInput; $0.audioInput.index = 0 }
			_ = try closure.exporter.rewrite(runtime.serializedData(), message: Rv_Data_Action.protoMessageName, path: "/actions/0")
			#expect(Set(closure.exporter.issues.map(\.feature)) == ["native-workspace-dependency", "native-action-dependency"])
			#expect(throws: DocumentCompatibilityError.self) { try closure.publish() }
			#expect(!FileManager.default.fileExists(atPath: output.path))
		}
	}

	@Test func renderConfigurationReadsNativeOwnedMacrosAndTheirLookWithoutAnAppConnection() throws {
		let source = try NativeWorkspaceSnapshot(root: fixtures, workspaceID: UUID(), metadata: [:], streams: streams("source"))
		let configuration = try RenderConfiguration(snapshot: source)
		let macros = try configuration.macros()
		let id = try macroID
		let selected = try #require(macros.first { UUID(uuidString: $0.uuid.string) == id })
		#expect(selected.name == "ProCRUD Dependency Macro")
		let resolver = LookActionResolver(configuration: configuration, macros: macros)
		let look = try #require(try resolver.look(actions: selected.actions, startingAt: nil))
		let exported = try Rv_Data_MacrosDocument(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeMacrosReference")))
		let reference = try #require(exported.macros.first?.actions.first { $0.type == .audienceLook }?.audienceLook.identification)
		#expect(UUID(uuidString: look.uuid.string) == UUID(uuidString: reference.parameterUuid.string))
		#expect(look.screenLooks.count == 1)
	}

	@Test func nativeContinuationAndReexportKeepTheMacroIdentityAndActions() throws {
		let reference = try Rv_Data_MacrosDocument(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeMacrosReference")))
		let exported = try Rv_Data_MacrosDocument(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeMacrosContinued")))
		let macro = try #require(exported.macros.first)
		#expect(macro.name == "ProCRUD Dependency Macro Continued")
		#expect(macro.uuid == reference.macros.first?.uuid)
		#expect(macro.actions.map(\.uuid) == reference.macros.first?.actions.map(\.uuid))
		#expect(macro.actions.map(\.type) == [.timer, .audienceLook, .media])
		struct Association: Decodable { let referenceID: UUID; let declaredAssetID: UUID; let materializedAssetID: UUID; let nativeAvailability: String; let status: String }
		let associations = try JSONDecoder().decode([Association].self, from: Data(contentsOf: fixtures.appendingPathComponent("imported-media-associations.json")))
		#expect(associations.count == 1)
		#expect(associations.allSatisfy { $0.status == "matched" && $0.nativeAvailability == "Ready" && $0.declaredAssetID == $0.materializedAssetID })
		#expect(associations.first?.referenceID == UUID(uuidString: macro.actions[2].media.element.uuid.string))
	}

	@Test func legacyCollectionLayoutMatchesNativeExportAndPreventsTheObservedSilentLoss() throws {
		let source = try #require(streams("source").first { $0.identity.kind == "Macros" })
		let projection = try source.protobufProjection()
		let adapted = try Rv_Data_MacrosDocument(serializedBytes: NativeWorkspaceInterchange.document(projection.protobuf, message: projection.messageType))
		let native = try Rv_Data_MacrosDocument(serializedBytes: Data(contentsOf: fixtures.appendingPathComponent("NativeMacrosReference")))
		// Native Legacy Workspace export also adds the obsolete root URL. Native
		// import drops it; the schema-1 SourceInfo locator remains authoritative.
		let normalized = try NativeDependencyWire.rewrite(native.serializedData(), message: projection.messageType, path: "") { bytes, message, _ in
			guard message == Rv_Data_Media.protoMessageName else { return nil }
			var media = try Rv_Data_Media(serializedBytes: bytes)
			let reference = try MediaReference(media: media)
			#expect(media.url.local.path == reference.activeLocators.first?.localPath)
			#expect(media.url.local.root.rawValue == reference.activeLocators.first?.localRoot)
			media.clearURL(); return try media.serializedData()
		}
		#expect(!adapted.macros[0].actions[2].media.element.hasURL)
		#expect(try protobufValues(adapted.serializedData(), message: projection.messageType) == protobufValues(normalized, message: projection.messageType))
		let bad = try NativeWorkspaceStream(identity: source.identity, snapshot: Data(contentsOf: fixtures.appendingPathComponent("unadapted-import-macros.loro")), versionVector: Data(contentsOf: fixtures.appendingPathComponent("unadapted-import-macros.vector")), lastSharedVersionVector: nil)
		var definitions = 0
		let imported = try bad.protobufProjection()
		_ = try NativeDependencyWire.rewrite(imported.protobuf, message: imported.messageType, path: "") { bytes, message, _ in
			if message == "rv.data.MacrosDocument.Macro" {
				definitions += 1; return bytes
			}
			return nil
		}
		#expect(definitions == 0 && adapted.macros.count == 1)
	}

	@Test func nativeWorkspaceReimportRetainsDefinitionsAndTheirResolvedReferences() throws {
		let source = try streams("source"), imported = try streams("imported")
		func projection(_ kind: String, _ streams: [NativeWorkspaceStream]) throws -> NativeProtobufProjection {
			try #require(streams.first { $0.identity.kind == kind }).protobufProjection()
		}
		func normalizeURLs(_ value: NativeProtobufProjection) throws -> Data {
			try NativeDependencyWire.rewrite(value.protobuf, message: value.messageType, path: "") { bytes, message, _ in
				guard message == Rv_Data_URL.protoMessageName else { return nil }
				var url = try Rv_Data_URL(serializedBytes: bytes)
				if url.local.path.hasPrefix("Media/") {
					url.local.path = "Media/SharedRectangle.png"
				}
				url.local.root = .show; url.relativePath = url.local.path
				return try url.serializedData()
			}
		}
		#expect(try normalizeURLs(projection("Macros", source)) == normalizeURLs(projection("Macros", imported)))
		for kind in ["Timers", "Presentation", "Theme"] {
			#expect(try projection(kind, source).protobuf == projection(kind, imported).protobuf)
		}
		let before = try Rv_Data_ProPresenterWorkspace(serializedBytes: normalizeURLs(projection("Workspace", source)))
		let after = try Rv_Data_ProPresenterWorkspace(serializedBytes: normalizeURLs(projection("Workspace", imported)))
		#expect(before.audienceLooks == after.audienceLooks)
		let sourceConfiguration = try NativeWorkspaceConfiguration(snapshot: .init(root: fixtures, workspaceID: UUID(), metadata: [:], streams: source))
		let importedConfiguration = try NativeWorkspaceConfiguration(snapshot: .init(root: fixtures, workspaceID: UUID(), metadata: [:], streams: imported))
		#expect(sourceConfiguration.screens.map(\.id) == importedConfiguration.screens.map(\.id))
		// Native import binds the receiving display. These exact fixtures record
		// that behavior; exporting shared definitions does not clone hardware.
		#expect(sourceConfiguration.screens.first?.logicalWidth == 1440)
		#expect(importedConfiguration.screens.first?.logicalWidth == 1728)
	}

	@Test func transitiveMacroTimerLookThemeAndMediaAreExportedOutsideTheSource() throws {
		try withSource { snapshot, output in
			let originals = snapshot.streams.compactMap(\.snapshot)
			let result = try NativeWorkspaceDependencyExporter.export(from: snapshot, playlistID: playlistID, to: output)
			#expect(Set(result.documents.map(\.path)) == ["Configuration/Macros", "Configuration/Timers", "Configuration/Workspace", "Libraries/Default/Owned Dependencies.pro", "Playlists/Library", "Themes/CLI Template Ordering/Theme"])
			let macros = try Rv_Data_MacrosDocument(serializedBytes: Data(contentsOf: output.appendingPathComponent("Configuration/Macros")))
			#expect(macros.macros.count == 1 && macros.macros[0].actions.count == 3)
			#expect(macros.macros[0].actions.map(\.type) == [.timer, .audienceLook, .media])
			let references = try MediaReference.collect(protobuf: macros.serializedData(), messageType: Rv_Data_MacrosDocument.protoMessageName)
			let media = try #require(references.first), relative = try #require(media.activeLocators.first?.localPath)
			#expect(media.activeLocators.first?.localRoot == 10)
			#expect(try Data(contentsOf: output.appendingPathComponent(relative)) == Data(contentsOf: sourceImage))
			#expect(try DocumentLoader.recursiveFiles(in: output.appendingPathComponent("Media")).count == 1)
			let workspace = try Rv_Data_ProPresenterWorkspace(serializedBytes: Data(contentsOf: output.appendingPathComponent("Configuration/Workspace")))
			#expect(workspace.proScreens.isEmpty && !workspace.hasLiveAudienceLook)
			#expect(workspace.audienceLooks.count == 2)
			let mapping = try #require(workspace.audienceLooks.last?.screenLooks.first)
			#expect(mapping.templateDocumentFilePath.local.root == .show)
			#expect(mapping.templateDocumentFilePath.local.path == "Themes/CLI Template Ordering/Theme")
			#expect(snapshot.streams.compactMap(\.snapshot) == originals)
			#expect(try WorkspaceInspector.inspect(output).storage == .legacyProtobuf)
		}
	}

	@Test func missingDefinitionsThemesAndFilesAreReportedTogetherWithoutPublishing() throws {
		try withSource { source, output in
			try FileManager.default.removeItem(at: source.root.appendingPathComponent("Media/Assets/SharedRectangle.png"))
			let snapshot = NativeWorkspaceSnapshot(root: source.root, workspaceID: source.workspaceID, metadata: [:], streams: source.streams.filter { !["Timers", "Theme"].contains($0.identity.kind) })
			do {
				_ = try NativeWorkspaceDependencyExporter.export(from: snapshot, playlistID: playlistID, to: output)
				Issue.record("An incomplete workspace dependency closure was published.")
			} catch let error as DocumentCompatibilityError {
				#expect(error.report.issues.contains { $0.feature == "native-media-dependency" })
				#expect(error.report.issues.filter { $0.feature == "native-workspace-dependency" }.count >= 2)
			}
			#expect(!FileManager.default.fileExists(atPath: output.path))
			#expect(try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path) == ["Source"])
		}
	}

	@Test func recursiveMacrosTerminateAndKeepTheirReferenceIdentities() throws {
		try withSource { source, output in
			let original = try #require(source.streams.first { $0.identity.kind == "Macros" })
			let doc = LoroDoc(); _ = try doc.import(bytes: #require(original.snapshot))
			let root = doc.getMap(id: "root")
			let collection = try #require(root.get(key: "macro_collections")?.asLoroMovableList()?.get(index: 0)?.asLoroMap())
			let macro = try #require(collection.get(key: "macros")?.asLoroMovableList()?.get(index: 0)?.asLoroMap())
			let actions = try #require(macro.get(key: "actions")?.asLoroMovableList())
			let action: NativeWorkspaceValue = try .map(["uuid": .string(UUID().uuidString), "type": .integer(23), "isEnabled": .boolean(true), "ActionTypeData": .map(["__tag": .string("macro"), "macro": .map(["identification": .map(["parameter_uuid": .string(macroID.uuidString), "parameter_name": .string("ProCRUD Dependency Macro")])])])])
			try NativeContainerAccess.write(action, to: actions.pushContainer(child: LoroMap()), message: Rv_Data_Action.protoMessageName)
			doc.commit()
			let replacement = try NativeWorkspaceStream(identity: original.identity, snapshot: doc.exportSnapshot(), versionVector: doc.oplogVv().encode(), lastSharedVersionVector: nil)
			let snapshot = NativeWorkspaceSnapshot(root: source.root, workspaceID: source.workspaceID, metadata: [:], streams: source.streams.map { $0.identity.kind == "Macros" ? replacement : $0 })
			let result = try NativeWorkspaceDependencyExporter.export(from: snapshot, playlistID: playlistID, to: output)
			#expect(result.documents.count == 6)
			let exported = try Rv_Data_MacrosDocument(serializedBytes: Data(contentsOf: output.appendingPathComponent("Configuration/Macros")))
			#expect(exported.macros.count == 1 && exported.macros[0].actions.count == 4)
			#expect(try UUID(uuidString: exported.macros[0].actions[3].macro.identification.parameterUuid.string) == macroID)
		}
	}

	@Test func existingOutputsAndNativeSourceLocationsAreNeverReplaced() throws {
		try withSource { source, output in
			try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
			let sentinel = output.appendingPathComponent("sentinel")
			try Data("unchanged".utf8).write(to: sentinel)
			for destination in [output, source.root, source.root.appendingPathComponent("Export"), source.root.deletingLastPathComponent()] {
				#expect(throws: DocumentArchiveError.self) { try NativeWorkspaceDependencyExporter.export(from: source, playlistID: playlistID, to: destination) }
			}
			#expect(try String(contentsOf: sentinel, encoding: .utf8) == "unchanged")
		}
	}

	private func withSource(_ body: (NativeWorkspaceSnapshot, URL) throws -> Void) throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), root = directory.appendingPathComponent("Source")
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Media/Assets"), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		try FileManager.default.copyItem(at: sourceImage, to: root.appendingPathComponent("Media/Assets/SharedRectangle.png"))
		try body(.init(root: root, workspaceID: UUID(), metadata: [:], streams: streams("source")), directory.appendingPathComponent("Export"))
	}

	/// Compare pinned 22 values, including fields opaque to the older Swift
	/// model. Only proto3 non-presence scalar defaults are canonicalized.
	private func protobufValues(_ data: Data, message: String) throws -> Data {
		let schema = try ProtobufSchema.bundled(version: .v22).message(named: message)
		var values: [(Int, Int, Data)] = []
		for (index, wire) in try MediaWireMessage(data).fields.enumerated() {
			let field = try #require(schema.fields.first { $0.number == wire.number })
			if !field.isMessage, !field.isRepeated, field.oneof == nil {
				if wire.varint == 0 {
					continue
				}
				if [.string, .bytes].contains(field.type), wire.payload?.isEmpty == true {
					continue
				}
				if field.type == .double, wire.raw.suffix(8) == Data(repeating: 0, count: 8) {
					continue
				}
				if field.type == .float, wire.raw.suffix(4) == Data(repeating: 0, count: 4) {
					continue
				}
			}
			if field.isMessage, let nested = field.typeName, let payload = wire.payload {
				try values.append((wire.number, index, ProtobufJSONPatcher.WireField.lengthDelimited(number: wire.number, payload: protobufValues(payload, message: nested)).raw))
			} else {
				values.append((wire.number, index, wire.raw))
			}
		}
		return values.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.reduce(into: Data()) { $0.append($1.2) }
	}

	private func streams(_ prefix: String) throws -> [NativeWorkspaceStream] {
		struct Record: Decodable { let prefix: String; let documentID: UUID; let kind: String; let corePath: String? }
		let records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: fixtures.appendingPathComponent("\(prefix)-streams.json")))
		return try records.map { record in
			let data = try Data(contentsOf: fixtures.appendingPathComponent(record.prefix + ".loro")), vector = try Data(contentsOf: fixtures.appendingPathComponent(record.prefix + ".vector"))
			return NativeWorkspaceStream(identity: .init(documentID: record.documentID, scope: .shared, kind: record.kind, corePath: record.corePath, availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
		}
	}

	private var playlistID: UUID {
		get throws { try #require(UUID(uuidString: "67CA9682-2249-5331-94CD-2144B2B3557B")) }
	}

	private var macroID: UUID {
		get throws { try #require(UUID(uuidString: "60EBA3D6-B125-4598-9170-E2506FA1353E")) }
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Native/ActionDependencies")
	}

	private var sourceImage: URL {
		fixtures.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Interchange/MediaIdentity/Media/Assets/SharedRectangle.png")
	}
}
