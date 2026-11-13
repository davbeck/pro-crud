import CryptoKit
import Foundation
import Security

public struct PlanningCenterOAuth: Sendable {
	public static let callbackURL = "http://127.0.0.1:49173/oauth/callback"
	public let clientID: String
	public let verifier: String
	public let state: String

	public init(clientID: String, verifier: String? = nil, state: String? = nil) throws {
		guard !clientID.isEmpty else { throw PlanningCenterError.oauthUnavailable }
		self.clientID = clientID
		self.verifier = try verifier ?? Self.randomToken()
		self.state = try state ?? Self.randomToken()
	}

	public var challenge: String {
		Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
	}

	public func authorizationURL() throws -> URL {
		var components = URLComponents(string: "https://api.planningcenteronline.com/oauth/authorize")
		components?.queryItems = [
			URLQueryItem(name: "client_id", value: clientID),
			URLQueryItem(name: "redirect_uri", value: Self.callbackURL),
			URLQueryItem(name: "response_type", value: "code"),
			URLQueryItem(name: "scope", value: "services"),
			URLQueryItem(name: "state", value: state),
			URLQueryItem(name: "code_challenge", value: challenge),
			URLQueryItem(name: "code_challenge_method", value: "S256"),
		]
		guard let url = components?.url else { throw PlanningCenterError.invalidResponse }
		return url
	}

	public func code(from requestTarget: String) throws -> String {
		guard requestTarget.hasPrefix("/oauth/callback?"),
		      let components = URLComponents(string: "http://127.0.0.1:49173" + requestTarget),
		      components.path == "/oauth/callback"
		else { throw PlanningCenterError.invalidCallback }
		let items = components.queryItems ?? []
		guard items.count(where: { $0.name == "state" }) == 1,
		      items.first(where: { $0.name == "state" })?.value == state
		else { throw PlanningCenterError.invalidCallback }
		if items.contains(where: { $0.name == "error" }) {
			throw PlanningCenterError.authorizationDenied
		}
		guard items.count(where: { $0.name == "code" }) == 1,
		      let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty
		else { throw PlanningCenterError.invalidCallback }
		return code
	}

	public static func form(_ fields: [String: String]) -> Data {
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
		return Data(fields.sorted(by: { $0.key < $1.key }).map { key, value in
			(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "="
				+ (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
		}.joined(separator: "&").utf8)
	}

	private static func randomToken() throws -> String {
		var bytes = [UInt8](repeating: 0, count: 32)
		let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
		return base64URL(Data(bytes))
	}

	private static func base64URL(_ data: Data) -> String {
		data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
	}
}
