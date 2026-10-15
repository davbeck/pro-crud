import Foundation
import ProPresenterProto
import SwiftProtobuf

/// A selected configuration view, not a reconstructed Workspace document.
/// Saved Looks/logical screen definitions belong to shared state; physical
/// screens and the live Look remain local to the client scope.
public struct NativeWorkspaceConfiguration: Encodable, Sendable {
	public struct Look: Encodable, Sendable {
		public let id: UUID
		public let name: String
		public let scope: NativeWorkspaceStream.Scope
		public let originalLookID: UUID?
		public let mappings: [Mapping]
		let document: Rv_Data_ProAudienceLook

		private enum CodingKeys: String, CodingKey { case id, name, scope, originalLookID, mappings }
	}

	public struct Mapping: Codable, Sendable, Equatable {
		public let screenID: UUID
		public let templateSlideID: UUID?
		public let theme: NativeWorkspaceContents.Reference?
		public let propsEnabled: Bool
		public let liveVideoEnabled: Bool
		public let presentationBackgroundEnabled: Bool
		public let presentationForegroundEnabled: Bool
		public let announcementsEnabled: Bool
		public let propsLayerEnabled: Bool
		public let messagesLayerEnabled: Bool
		public let maskID: UUID?
	}

	public struct Screen: Encodable, Sendable {
		public let id: UUID
		public let name: String
		public let screenType: Int
		public let logicalWidth: Double?
		public let logicalHeight: Double?
		public let hasLocalOutput: Bool
		public let renderingEnabled: Bool?
		let document: Rv_Data_ProPresenterScreen?

		private enum CodingKeys: String, CodingKey { case id, name, screenType, logicalWidth, logicalHeight, hasLocalOutput, renderingEnabled }
	}

	public struct Uninspected: Codable, Sendable, Equatable {
		public let scope: NativeWorkspaceStream.Scope
		public let fields: [String]
	}

	public let workspaceID: UUID
	public let documentID: UUID
	public let savedLooks: [Look]
	public let liveLook: Look?
	public let screens: [Screen]
	public let uninspected: [Uninspected]

	public init(snapshot: NativeWorkspaceSnapshot) throws {
		workspaceID = snapshot.workspaceID
		let streams = snapshot.streams.filter { $0.identity.kind == "Workspace" }
		let shared = streams.filter { $0.identity.scope == .shared }
		let clients = streams.filter { $0.identity.scope == .client }
		guard shared.count == 1, let source = shared.first, clients.count <= 1 else {
			throw NativeSemanticError.invalidValue(path: "/Workspace", expected: "one shared Workspace and at most one matching client stream")
		}
		documentID = source.identity.documentID
		if let client = clients.first, client.identity.documentID != documentID {
			throw NativeSemanticError.invalidValue(path: "/Workspace/client", expected: "same Workspace identity across scopes")
		}
		let sharedRoot = try source.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root")
		let clientRoot = try clients.first?.decodedValue().object(at: "/").required("root", at: "/").object(at: "/root") ?? [:]
		let resolver = try NativeWorkspaceReferenceResolver(streams: snapshot.streams)
		var encoder = try NativeProtobufEncoder(schema: .bundled(version: .v22))
		func look(_ value: NativeWorkspaceValue, scope: NativeWorkspaceStream.Scope, path: String, encoder: inout NativeProtobufEncoder) throws -> Look {
			let bytes = try encoder.encode(value, message: "rv.data.ProAudienceLook", path: path)
			let document = try Rv_Data_ProAudienceLook(serializedBytes: bytes)
			let object = try value.object(at: path)
			let id = try object.required("uuid", at: path).uuid(at: "\(path)/uuid")
			let mappings = try (object.optional("screen_looks")?.array(at: "\(path)/screen_looks") ?? []).enumerated().map { offset, value in
				let mapping = try value.object(at: "\(path)/screen_looks")
				let materialized = document.screenLooks[offset]
				let theme = try mapping.optional("template_document_file_path").map { try resolver.theme(inWorkspaceDocument: $0) }
				let template = try mapping.optional("template_slide_uuid")?.text(at: "\(path)/template_slide_uuid")
				return try Mapping(screenID: mapping.required("pro_screen_uuid", at: path).uuid(at: "\(path)/pro_screen_uuid"), templateSlideID: template.flatMap(UUID.init(uuidString:)), theme: theme,
				                   propsEnabled: materialized.propsEnabled, liveVideoEnabled: materialized.liveVideoEnabled,
				                   presentationBackgroundEnabled: materialized.presentationBackgroundEnabled, presentationForegroundEnabled: materialized.presentationForegroundEnabled,
				                   announcementsEnabled: materialized.announcementsEnabled, propsLayerEnabled: materialized.propsLayerEnabled,
				                   messagesLayerEnabled: materialized.messagesLayerEnabled, maskID: UUID(uuidString: materialized.maskUuid.string))
			}
			guard Set(mappings.map(\.screenID)).count == mappings.count else { throw NativeSemanticError.duplicateIdentity(path: "\(path)/screen_looks", identity: "screen mapping") }
			return Look(id: id, name: document.name, scope: scope, originalLookID: UUID(uuidString: document.originalLookUuid.string), mappings: mappings, document: document)
		}
		savedLooks = try (sharedRoot.optional("audience_looks")?.array(at: "/root/audience_looks") ?? []).enumerated().map { index, value in
			try look(value, scope: .shared, path: "/shared/audience_looks[\(index)]", encoder: &encoder)
		}
		guard Set(savedLooks.map(\.id)).count == savedLooks.count else { throw NativeSemanticError.duplicateIdentity(path: "/shared/audience_looks", identity: "Look UUID") }
		liveLook = try clientRoot.optional("live_audience_look").map { try look($0, scope: .client, path: "/client/live_audience_look", encoder: &encoder) }
		var localScreens: [UUID: (Rv_Data_ProPresenterScreen, Bool?)] = [:]
		for value in try clientRoot.optional("pro_screens")?.array(at: "/client/pro_screens") ?? [] {
			let bytes = try encoder.encode(value, message: "rv.data.ProPresenterScreen", path: "/client/pro_screens")
			let id = try value.object(at: "/screen").required("uuid", at: "/screen").uuid(at: "/screen/uuid")
			let enabled = try ProtobufJSONPatcher.WireField.parse(bytes).last { $0.number == 9 }?.varint.map { $0 != 0 }
			let document = try Rv_Data_ProPresenterScreen(serializedBytes: bytes)
			guard localScreens.updateValue((document, enabled), forKey: id) == nil else { throw NativeSemanticError.duplicateIdentity(path: "/client/pro_screens", identity: id.uuidString) }
		}
		var screens: [Screen] = []
		var seen: Set<UUID> = []
		for value in try sharedRoot.optional("cloud_output_screens")?.array(at: "/shared/cloud_output_screens") ?? [] {
			let object = try value.object(at: "/screen")
			let id = try object.required("uuid", at: "/screen").uuid(at: "/screen/uuid")
			guard seen.insert(id).inserted else { throw NativeSemanticError.duplicateIdentity(path: "/shared/cloud_output_screens", identity: id.uuidString) }
			let bytes = try encoder.encode(value, message: "rv.data.CloudProPresenterScreen", path: "/shared/cloud_output_screens")
			let size = try MediaWireMessage(bytes).message(7).map { try Rv_Data_Graphics.Size(serializedBytes: $0.data) }
			let local = localScreens.removeValue(forKey: id)
			let name = try object.required("name", at: "/screen").text(at: "/screen/name")
			let type = try object.required("screen_type", at: "/screen").int(at: "/screen/screen_type")
			if let local, local.0.screenType.rawValue != type {
				throw NativeSemanticError.invalidValue(path: "/screen/\(id)", expected: "matching shared/client screen type")
			}
			screens.append(.init(id: id, name: name, screenType: type, logicalWidth: size?.width, logicalHeight: size?.height,
			                     hasLocalOutput: local != nil, renderingEnabled: local?.1, document: local?.0))
		}
		for (id, local) in localScreens.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
			screens.append(.init(id: id, name: local.0.name, screenType: local.0.screenType.rawValue, logicalWidth: nil, logicalHeight: nil,
			                     hasLocalOutput: true, renderingEnabled: local.1, document: local.0))
		}
		guard encoder.issues.isEmpty else { throw NativeProjectionError(issues: encoder.issues) }
		self.screens = screens
		uninspected = [
			.init(scope: .shared, fields: sharedRoot.keys.filter { !["audience_looks", "cloud_output_screens"].contains($0) }.sorted()),
			.init(scope: .client, fields: clientRoot.keys.filter { !["live_audience_look", "pro_screens"].contains($0) }.sorted()),
		]
	}
}
