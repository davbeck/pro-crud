import Foundation
import ProPresenterProto

/// The native-tested video-source HLS action has no local file dependency.
/// This profile preserves its bytes; it does not construct a media-store row.
enum NativeHLSInterchange {
	static func qualifiesAction(_ data: Data) throws -> Bool {
		let action = try MediaWireMessage(data)
		guard let media = try action.message(5), try qualifiesMedia(media.data) else { return false }
		// Effects, transitions and playback markers can introduce dependencies
		// outside this action's HLS element and have separate acceptance gates.
		if action.fields.contains(where: { [3, 4, 12].contains($0.number) }) {
			return false
		}
		if let preset = try action.message(2), try !Rv_Data_UUID(serializedBytes: preset.data).string.isEmpty {
			return false
		}
		return true
	}

	static func qualifiesMedia(_ data: Data) throws -> Bool {
		let reference = try MediaReference(media: Rv_Data_Media(serializedBytes: data))
		guard reference.kind == "video", reference.dependencyKind == .remoteStream,
		      reference.identitySchemaVersion == "1", UUID(uuidString: reference.referenceID) != nil,
		      reference.assetID.flatMap(UUID.init(uuidString:)) != nil,
		      reference.containerID == nil, !reference.hasProvider,
		      reference.activeLocators.count == 1,
		      let remote = reference.activeLocators[0].remote, let url = URL(string: remote),
		      ["http", "https"].contains(url.scheme?.lowercased()), url.host?.isEmpty == false
		else { return false }
		return try hasNoOtherDependencies(data, message: Rv_Data_Media.protoMessageName)
	}

	private static func hasNoOtherDependencies(_ data: Data, message: String) throws -> Bool {
		let descriptor = try ProtobufSchema.bundled(version: .v22).message(named: message)
		for wire in try MediaWireMessage(data).fields {
			guard let field = descriptor.fields.first(where: { $0.number == wire.number }) else { continue }
			switch (message, field.protoName) {
			case ("rv.data.Media.DrawingProperties", "effects"): return false
			case ("rv.data.Media.DrawingProperties", "selected_effect_preset_uuid"):
				if let payload = wire.payload, try !Rv_Data_UUID(serializedBytes: payload).string.isEmpty {
					return false
				}
			case ("rv.data.SourceInfo", "file"): return false
			case ("rv.data.URL", _):
				if field.protoName != "platform", wire.payload?.isEmpty == false {
					return false
				}
			case ("rv.data.FileProperties.RemoteProperties.ProContent", _):
				if wire.payload?.isEmpty == false {
					return false
				}
			default: break
			}
			if let nested = field.typeName, field.isMessage, let payload = wire.payload,
			   try !hasNoOtherDependencies(payload, message: nested)
			{
				return false
			}
		}
		return true
	}
}
