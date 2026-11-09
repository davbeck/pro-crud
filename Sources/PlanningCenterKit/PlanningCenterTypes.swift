import Foundation

public enum PlanningCenterError: Error, LocalizedError {
	case notLoggedIn
	case oauthUnavailable
	case http(status: Int, retryAfter: String?)
	case invalidResponse
	case attachmentNotReady
	case invalidTarget
	case invalidUploadTarget
	case invalidCallback
	case authorizationDenied
	case callbackTimeout
	case keychain(OSStatus)
	case uploadAssociationFailed(fileID: String)

	public var errorDescription: String? {
		switch self {
		case .notLoggedIn: "Sign into Planning Center with planning-center login."
		case .oauthUnavailable: "This build has no Planning Center OAuth client ID. Use planning-center login --personal-access-token."
		case let .http(status, retryAfter):
			switch status {
			case 401: "Planning Center rejected your credentials. Sign in again."
			case 403: "Your Planning Center account does not have permission for this operation."
			case 404: "The Planning Center resource was not found or is unavailable to your account."
			case 429: "Planning Center's request limit was reached. Retry after \(retryAfter ?? "the indicated number of") seconds."
			default: "Planning Center returned HTTP \(status)."
			}
		case .invalidResponse: "Planning Center returned an unexpected response."
		case .attachmentNotReady: "Planning Center is still preparing this attachment. Try downloading it again shortly."
		case .invalidTarget: "Select one attachment destination: song and arrangement (optionally key), media, plan, or plan item. IDs must be positive integers."
		case .invalidUploadTarget: "Upload requires --song and --arrangement, or --service-type, --plan, and --item. Plan-wide, key, and media destinations support list/download only."
		case .invalidCallback: "The Planning Center login callback did not match this sign-in attempt."
		case .authorizationDenied: "Planning Center authorization was declined."
		case .callbackTimeout: "Planning Center sign-in timed out. Run planning-center login again."
		case let .keychain(status): "Could not access Planning Center credentials in Keychain (\(status))."
		case let .uploadAssociationFailed(fileID): "The file was uploaded (file ID \(fileID)), but its attachment could not be verified. Inspect the destination before retrying."
		}
	}
}

public enum JSONValue: Codable, Sendable, Equatable {
	case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

	public init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		if container.decodeNil() {
			self = .null
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		} else if let value = try? container.decode(Double.self) {
			self = .number(value)
		} else if let value = try? container.decode([String: JSONValue].self) {
			self = .object(value)
		} else {
			self = try .array(container.decode([JSONValue].self))
		}
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case let .string(value): try container.encode(value)
		case let .number(value): try container.encode(value)
		case let .bool(value): try container.encode(value)
		case let .object(value): try container.encode(value)
		case let .array(value): try container.encode(value)
		case .null: try container.encodeNil()
		}
	}

	public var string: String? {
		guard case let .string(value) = self else { return nil }
		return value
	}
}

public struct PlanningCenterResource: Codable, Sendable {
	public let type: String
	public let id: String
	public var attributes: [String: JSONValue]?
	public var relationships: [String: JSONValue]?
	public var links: [String: String?]?
}

struct PlanningCenterDocument<Value: Codable & Sendable>: Codable, Sendable {
	let data: Value
	var links: [String: String?]?
}

public struct PlanningCenterTarget: Sendable {
	public let path: String

	public init(song: String? = nil, arrangement: String? = nil, key: String? = nil,
	            media: String? = nil, serviceType: String? = nil, plan: String? = nil, item: String? = nil) throws
	{
		let ids = [song, arrangement, key, media, serviceType, plan, item].compactMap(\.self)
		guard ids.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48 ... 57).contains($0) } && $0.contains(where: { $0 != "0" }) }) else {
			throw PlanningCenterError.invalidTarget
		}
		if let song, let arrangement, media == nil, serviceType == nil, plan == nil, item == nil {
			path = "songs/\(song)/arrangements/\(arrangement)" + (key.map { "/keys/\($0)" } ?? "")
		} else if let media, song == nil, arrangement == nil, key == nil, serviceType == nil, plan == nil, item == nil {
			path = "media/\(media)"
		} else if let serviceType, let plan, song == nil, arrangement == nil, key == nil, media == nil {
			path = "service_types/\(serviceType)/plans/\(plan)" + (item.map { "/items/\($0)" } ?? "")
		} else {
			throw PlanningCenterError.invalidTarget
		}
	}

	/// Uploads require an exact arrangement or plan item, never a plan-wide attachment.
	public func validateUpload() throws {
		let parts = path.split(separator: "/")
		let arrangement = parts.count == 4 && parts[0] == "songs" && parts[2] == "arrangements"
		let item = parts.count == 6 && parts[0] == "service_types" && parts[2] == "plans" && parts[4] == "items"
		guard arrangement || item else { throw PlanningCenterError.invalidUploadTarget }
	}

	public static func validatedID(_ id: String) throws -> String {
		guard !id.isEmpty, id.utf8.allSatisfy({ (48 ... 57).contains($0) }), id.contains(where: { $0 != "0" }) else {
			throw PlanningCenterError.invalidTarget
		}
		return id
	}
}
