import Foundation
import Loro
import Testing
@testable import ProCRUDCore

@Suite("Native shared and client workspace configuration")
struct NativeWorkspaceConfigurationTests {
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
		let themeID = UUID()
		let templateID = UUID()
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

	private func stream(id: UUID, scope: NativeWorkspaceStream.Scope, root: [String: NativeWorkspaceValue]) throws -> NativeWorkspaceStream {
		let document = LoroDoc()
		for (key, value) in root {
			try document.getMap(id: "root").insert(key: key, v: loro(value))
		}
		document.commit()
		let data = try document.exportSnapshot()
		return .init(identity: .init(documentID: id, scope: scope, kind: "Workspace", corePath: nil, availability: .available, byteCount: Int64(data.count), sha256: nil, updatedAtMilliseconds: 0), snapshot: data, versionVector: document.oplogVv().encode(), lastSharedVersionVector: nil)
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
