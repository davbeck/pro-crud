import Foundation
import Loro
import ProPresenterProto
import SwiftProtobuf
import Testing
@testable import ProCRUDCore

@Suite("Native shared and client workspace configuration")
struct NativeWorkspaceConfigurationTests {
	@Test func nativeLookSelectsTheOwnedThemeByLogicalIdentityAndPreservesDisabledState() throws {
		let (fixture, source) = try lookSnapshot()
		let selected = try LookResolver.resolve(snapshot: source, look: fixture.savedID.uuidString.lowercased(), screen: fixture.screenID.uuidString.lowercased())
		#expect(selected.lookName == "Saved Look")
		#expect(selected.screenName == "Shared Audience")
		#expect(selected.destinationSize.width == 854 && selected.destinationSize.height == 480)
		#expect(UUID(uuidString: selected.template.slide.baseSlide.uuid.string) == fixture.templateID)
		#expect(selected.warnings.contains { $0.contains("disabled in ProPresenter") })
		#expect(selected.template.preferredMediaReferences.isEmpty)
		let exported = try DocumentLoader.load(from: fixtures.appendingPathComponent("Interchange/MetadataFreeTheme/Theme"))
		guard case let .theme(theme) = exported.payload else { Issue.record("Expected owned native Theme export"); return }
		let expected = try #require(theme.slides.first { UUID(uuidString: $0.baseSlide.uuid.string) == fixture.templateID })
		#expect(selected.template.slide.name == expected.name)
		#expect(selected.template.slide.baseSlide.size == expected.baseSlide.size)
		#expect(selected.template.slide.baseSlide.elements.map(\.element.uuid) == expected.baseSlide.elements.map(\.element.uuid))
		#expect(selected.template.slide.baseSlide.elements.map(\.element.bounds) == expected.baseSlide.elements.map(\.element.bounds))
		#expect(selected.template.slide.baseSlide.elements.map(\.element.fill) == expected.baseSlide.elements.map(\.element.fill))
		#expect(selected.template.slide.baseSlide.elements.map(\.element.text.rtfData) == expected.baseSlide.elements.map(\.element.text.rtfData))
	}

	@Test func nativeLookCanPreviewSharedDimensionsWithoutLocalHardwareConfiguration() throws {
		let (fixture, source) = try lookSnapshot(includeClient: false)
		let selected = try LookResolver.resolve(snapshot: source, look: "Saved Look", screen: "Shared Audience")
		#expect(UUID(uuidString: selected.template.slide.baseSlide.uuid.string) == fixture.templateID)
		#expect(selected.destinationSize.width == 854)
		#expect(selected.warnings.contains { $0.contains("no local output configuration") })
	}

	@Test func nativeLookRejectsUnavailableThemeWithoutConsultingLegacyLeftovers() throws {
		let (fixture, source) = try lookSnapshot()
		let streams = source.streams.map { stream in
			guard stream.identity.kind == "Theme" else { return stream }
			var identity = stream.identity
			identity.availability = .unavailable
			return NativeWorkspaceStream(identity: identity, snapshot: nil, versionVector: nil, lastSharedVersionVector: nil)
		}
		#expect(throws: NativeWorkspaceError.self) { try LookResolver.resolve(snapshot: .init(root: source.root, workspaceID: source.workspaceID, metadata: [:], streams: streams), look: fixture.savedID.uuidString, screen: fixture.screenID.uuidString) }
	}

	@Test func nativeLookReportsADanglingTemplateUUIDWithoutChoosingAnotherSlide() throws {
		let (fixture, original) = try lookSnapshot()
		let missing = UUID()
		var mapping = try fixture.mapping.object(at: "/mapping")
		mapping["template_slide_uuid"] = .string(missing.uuidString)
		var look = fixture.savedLook
		look["screen_looks"] = .list([.map(mapping)])
		var root = fixture.shared
		root["audience_looks"] = .list([.map(look)])
		let updated = try stream(id: fixture.workspaceID, scope: .shared, root: root)
		let source = NativeWorkspaceSnapshot(root: original.root, workspaceID: original.workspaceID, metadata: [:], streams: [updated] + original.streams.filter { $0.identity.kind != "Workspace" || $0.identity.scope != .shared })
		#expect(throws: NativeSemanticError.missingReference(path: "Owned/Theme", identity: missing.uuidString)) {
			try LookResolver.resolve(snapshot: source, look: fixture.savedID.uuidString, screen: fixture.screenID.uuidString)
		}
	}

	@Test func selectedTemplateMediaBlocksPreviewButUnusedTemplateMediaDoesNot() throws {
		let (fixture, original) = try lookSnapshot()
		let source = try #require(original.streams.first { $0.identity.kind == "Theme" })
		var root = try source.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root")
		let slides = try root.required("slides", at: "/root").array(at: "/root/slides")
		var mediaSlide = try #require(slides.first).object(at: "/slide")
		var base = try mediaSlide.required("base_slide", at: "/slide").object(at: "/base_slide")
		var elements = try base.required("elements", at: "/base_slide").array(at: "/elements")
		var slideElement = try #require(elements.first).object(at: "/element")
		var element = try slideElement.required("element", at: "/element").object(at: "/graphic")
		element["fill"] = .map(["enable": .boolean(true), "FillType": .map(["__tag": .string("media"), "media": .map([
			"uuid": .string(UUID().uuidString), "asset_id": .string(UUID().uuidString), "identity_schema_version": .string("1"),
			"TypeProperties": .map(["__tag": .string("image"), "image": .map([:])]),
		])])])
		slideElement["element"] = .map(element)
		elements[0] = .map(slideElement)
		base["elements"] = .list(elements)
		mediaSlide["base_slide"] = .map(base)
		var replaced = slides
		replaced[0] = .map(mediaSlide)
		root["slides"] = .list(replaced)
		func snapshot(_ root: [String: NativeWorkspaceValue]) throws -> NativeWorkspaceSnapshot {
			let theme = try stream(id: source.identity.documentID, scope: .shared, root: root, kind: "Theme", corePath: "Owned/Theme")
			return .init(root: original.root, workspaceID: original.workspaceID, metadata: [:], streams: original.streams.filter { $0.identity.kind != "Theme" } + [theme])
		}
		#expect(throws: NativeSemanticError.self) { try LookResolver.resolve(snapshot: snapshot(root), look: fixture.savedID.uuidString, screen: fixture.screenID.uuidString) }
		base["uuid"] = .string(UUID().uuidString)
		mediaSlide["base_slide"] = .map(base)
		root["slides"] = .list(slides + [.map(mediaSlide)])
		let selected = try LookResolver.resolve(snapshot: snapshot(root), look: fixture.savedID.uuidString, screen: fixture.screenID.uuidString)
		#expect(UUID(uuidString: selected.template.slide.baseSlide.uuid.string) == fixture.templateID)
		var actionSlide = try #require(slides.first).object(at: "/slide")
		let media = try element.required("fill", at: "/graphic").object(at: "/fill").required("FillType", at: "/fill").tagged(at: "/fill/FillType").value
		actionSlide["actions"] = .list([.map(["uuid": .string(UUID().uuidString), "type": .integer(13), "isEnabled": .boolean(true), "ActionTypeData": .map(["__tag": .string("media"), "media": .map(["element": media])])])])
		var actionSlides = slides
		actionSlides[0] = .map(actionSlide)
		root["slides"] = .list(actionSlides)
		let actionResult = try LookResolver.resolve(snapshot: snapshot(root), look: fixture.savedID.uuidString, screen: fixture.screenID.uuidString)
		#expect(actionResult.template.slide.actions.isEmpty)
	}

	@Test func savedAndLiveLooksAndScreenStateRemainInTheirOwningScopes() throws {
		let fixture = Fixture()
		var shared = fixture.shared
		shared["future_configuration"] = .map(["value": .string("retained outside this selected view")])
		let result = try NativeWorkspaceConfiguration(snapshot: snapshot(fixture, shared: shared))
		#expect(result.documentID == fixture.workspaceID)
		#expect(result.savedLooks.map(\.id) == [fixture.savedID])
		#expect(result.savedLooks.map(\.scope) == [.shared])
		#expect(result.liveLook?.id == fixture.liveID)
		#expect(result.liveLook?.scope == .client)
		#expect(result.liveLook?.originalLookID == fixture.savedID)
		let screen = try #require(result.screens.first)
		#expect(screen.id == fixture.screenID)
		#expect(screen.name == "Shared Audience")
		#expect(screen.hasLocalOutput)
		#expect(screen.renderingEnabled == false)
		#expect(screen.logicalWidth == 854 && screen.logicalHeight == 480)
		#expect(screen.document?.name == "Local Audience")
		#expect(result.savedLooks.first?.mappings.first?.theme?.documentID == fixture.themeID)
		#expect(result.savedLooks.first?.mappings.first?.theme?.logicalPath == "Owned/Theme")
		#expect(result.uninspected.first { $0.scope == .shared }?.fields == ["future_configuration"])
		let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any]
		#expect((json?["screens"] as? [[String: Any]])?.first?["renderingEnabled"] as? Bool == false)
	}

	@Test func absentClientAndMissingOrUnavailableThemesStayExplicit() throws {
		let fixture = Fixture()
		let noClient = try NativeWorkspaceConfiguration(snapshot: snapshot(fixture, includeClient: false))
		#expect(noClient.liveLook == nil)
		#expect(noClient.screens.first?.hasLocalOutput == false)
		#expect(noClient.screens.first?.renderingEnabled == nil)
		#expect(noClient.savedLooks.count == 1)
		let unavailable = try NativeWorkspaceConfiguration(snapshot: snapshot(fixture, themeAvailability: .unavailable))
		#expect(unavailable.savedLooks.first?.mappings.first?.theme?.availability == .unavailable)
		let missing = try NativeWorkspaceConfiguration(snapshot: snapshot(fixture, includeTheme: false))
		let reference = try #require(missing.savedLooks.first?.mappings.first?.theme)
		#expect(reference.logicalPath == "Owned/Theme")
		#expect(reference.documentID == nil)
	}

	@Test func absentRenderingFlagDoesNotBecomeAnExplicitEnabledState() throws {
		let fixture = Fixture()
		var client = fixture.client
		var screen = try fixture.client.required("pro_screens", at: "/").array(at: "/")[0].object(at: "/")
		screen.removeValue(forKey: "RenderingEnabledOptional")
		client["pro_screens"] = .list([.map(screen)])
		let result = try NativeWorkspaceConfiguration(snapshot: snapshot(fixture, client: client))
		#expect(result.screens.first?.renderingEnabled == nil)
	}

	@Test func duplicateMappingsAndLogicalScreensAreRejected() throws {
		let fixture = Fixture()
		var root = fixture.shared
		var look = fixture.savedLook
		look["screen_looks"] = .list([fixture.mapping, fixture.mapping])
		root["audience_looks"] = .list([.map(look)])
		#expect(throws: NativeSemanticError.self) { try NativeWorkspaceConfiguration(snapshot: snapshot(fixture, shared: root)) }
		root = fixture.shared
		root["cloud_output_screens"] = .list([fixture.logicalScreen, fixture.logicalScreen])
		#expect(throws: NativeSemanticError.self) { try NativeWorkspaceConfiguration(snapshot: snapshot(fixture, shared: root)) }
	}

	@Test func mismatchedWorkspaceIdentityAndUnknownSelectedFieldsFail() throws {
		let fixture = Fixture()
		let source = try snapshot(fixture)
		var streams = source.streams
		let client = try #require(streams.first { $0.identity.scope == .client })
		var identity = client.identity
		identity.documentID = UUID()
		streams[1] = .init(identity: identity, snapshot: client.snapshot, versionVector: client.versionVector, lastSharedVersionVector: nil)
		#expect(throws: NativeSemanticError.self) { try NativeWorkspaceConfiguration(snapshot: .init(root: source.root, workspaceID: source.workspaceID, metadata: [:], streams: streams)) }
		var root = fixture.shared
		var look = fixture.savedLook
		look["future_visual_behavior"] = .boolean(true)
		root["audience_looks"] = .list([.map(look)])
		#expect(throws: NativeProjectionError.self) { try NativeWorkspaceConfiguration(snapshot: snapshot(fixture, shared: root)) }
	}

	private struct Fixture {
		let workspaceID = UUID()
		let screenID = UUID()
		let savedID = UUID()
		let liveID = UUID()
		let themeID: UUID
		let templateID: UUID
		init(themeID: UUID = UUID(), templateID: UUID = UUID()) {
			self.themeID = themeID
			self.templateID = templateID
		}

		var mapping: NativeWorkspaceValue {
			.map(["pro_screen_uuid": .string(screenID.uuidString), "template_slide_uuid": .string(templateID.uuidString), "template_document_file_path": .map([
				"RelativeFilePath": .map(["__tag": .string("local"), "local": .map(["root": .integer(10), "path": .string("Themes/Owned/Theme")])]),
				"Storage": .map(["__tag": .string("absolute_string"), "absolute_string": .string("file:///stale/workspace/Themes/Other/Theme")]),
			])])
		}

		var savedLook: [String: NativeWorkspaceValue] {
			["uuid": .string(savedID.uuidString), "name": .string("Saved Look"), "screen_looks": .list([mapping])]
		}

		var logicalScreen: NativeWorkspaceValue {
			.map(["uuid": .string(screenID.uuidString), "name": .string("Shared Audience"), "screen_type": .integer(1), "size": .map(["width": .number(854), "height": .number(480)])])
		}

		var shared: [String: NativeWorkspaceValue] {
			["audience_looks": .list([.map(savedLook)]), "cloud_output_screens": .list([logicalScreen])]
		}

		var client: [String: NativeWorkspaceValue] {
			["live_audience_look": .map(["uuid": .string(liveID.uuidString), "original_look_uuid": .string(savedID.uuidString), "name": .string("Live Look"), "screen_looks": .list([])]),
			 "pro_screens": .list([.map(["uuid": .string(screenID.uuidString), "name": .string("Local Audience"), "screen_type": .integer(1), "RenderingEnabledOptional": .map(["__tag": .string("rendering_enabled"), "rendering_enabled": .boolean(false)])])])]
		}
	}

	private func snapshot(_ fixture: Fixture, shared: [String: NativeWorkspaceValue]? = nil, client: [String: NativeWorkspaceValue]? = nil, includeClient: Bool = true, includeTheme: Bool = true, themeAvailability: NativeWorkspaceStream.Availability = .available) throws -> NativeWorkspaceSnapshot {
		var streams = try [stream(id: fixture.workspaceID, scope: .shared, root: shared ?? fixture.shared)]
		if includeClient {
			try streams.append(stream(id: fixture.workspaceID, scope: .client, root: client ?? fixture.client))
		}
		if includeTheme {
			streams.append(.init(identity: .init(documentID: fixture.themeID, scope: .shared, kind: "Theme", corePath: "Owned/Theme", availability: themeAvailability, byteCount: 0, sha256: nil, updatedAtMilliseconds: 0), snapshot: nil, versionVector: nil, lastSharedVersionVector: nil))
		}
		return .init(root: FileManager.default.temporaryDirectory, workspaceID: fixture.workspaceID, metadata: [:], streams: streams)
	}

	private func lookSnapshot(includeClient: Bool = true) throws -> (Fixture, NativeWorkspaceSnapshot) {
		let directory = fixtures.appendingPathComponent("Native/LookTheme")
		let data = try Data(contentsOf: directory.appendingPathComponent("Theme.loro"))
		let vector = try Data(contentsOf: directory.appendingPathComponent("Theme.vector"))
		let id = try #require(UUID(uuidString: "e90a8c1e-a43f-5688-8d49-70cf33b1a6e7"))
		let themeStream = NativeWorkspaceStream(identity: .init(documentID: id, scope: .shared, kind: "Theme", corePath: "Owned/Theme", availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
		guard case let .theme(theme) = try themeStream.protobufProjection().payload() else { throw NativeSemanticError.invalidValue(path: "/fixture", expected: "Theme") }
		let slideID = try #require(theme.slides.first.flatMap { UUID(uuidString: $0.baseSlide.uuid.string) })
		let fixture = Fixture(themeID: id, templateID: slideID)
		let original = try snapshot(fixture, includeClient: includeClient, includeTheme: false)
		return (fixture, .init(root: original.root, workspaceID: original.workspaceID, metadata: [:], streams: original.streams + [themeStream]))
	}

	private var fixtures: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22")
	}

	private func stream(id: UUID, scope: NativeWorkspaceStream.Scope, root: [String: NativeWorkspaceValue], kind: String = "Workspace", corePath: String? = nil) throws -> NativeWorkspaceStream {
		let document = LoroDoc()
		for (key, value) in root {
			try document.getMap(id: "root").insert(key: key, v: loro(value))
		}
		document.commit()
		let data = try document.exportSnapshot()
		return .init(identity: .init(documentID: id, scope: scope, kind: kind, corePath: corePath, availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: document.oplogVv().encode(), lastSharedVersionVector: nil)
	}

	private func loro(_ value: NativeWorkspaceValue) -> LoroValue {
		switch value {
		case .null: .null
		case let .boolean(value): .bool(value: value)
		case let .number(value): .double(value: value)
		case let .integer(value): .i64(value: value)
		case let .binary(value): .binary(value: value)
		case let .string(value): .string(value: value)
		case let .list(value): .list(value: value.map(loro))
		case let .map(value): .map(value: value.mapValues(loro))
		}
	}
}
