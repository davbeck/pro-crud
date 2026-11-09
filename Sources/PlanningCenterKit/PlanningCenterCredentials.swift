import Foundation
import Security

public struct PlanningCenterCredentials: Codable, Sendable {
	public enum Method: String, Codable, Sendable { case oauth, personalAccessToken }
	public let method: Method
	public let clientID: String
	public let secret: String
	public let refreshToken: String?
	public let expiresAt: Date?

	public init(method: Method, clientID: String, secret: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
		self.method = method
		self.clientID = clientID
		self.secret = secret
		self.refreshToken = refreshToken
		self.expiresAt = expiresAt
	}
}

public protocol PlanningCenterCredentialStore: Sendable {
	func load() throws -> PlanningCenterCredentials?
	func save(_ credentials: PlanningCenterCredentials) throws
	func delete() throws
}

public struct PlanningCenterKeychain: PlanningCenterCredentialStore {
	private let service: String

	public init(service: String = "com.davbeck.pro-crud.planning-center") {
		self.service = service
	}

	private var query: [String: Any] {
		[kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "credentials"]
	}

	public func load() throws -> PlanningCenterCredentials? {
		var request = query
		request[kSecReturnData as String] = true
		request[kSecMatchLimit as String] = kSecMatchLimitOne
		var result: CFTypeRef?
		let status = SecItemCopyMatching(request as CFDictionary, &result)
		if status == errSecItemNotFound {
			return nil
		}
		guard status == errSecSuccess else { throw PlanningCenterError.keychain(status) }
		guard let data = result as? Data else { throw PlanningCenterError.invalidResponse }
		return try JSONDecoder().decode(PlanningCenterCredentials.self, from: data)
	}

	public func save(_ credentials: PlanningCenterCredentials) throws {
		let data = try JSONEncoder().encode(credentials)
		let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
		if status == errSecItemNotFound {
			var request = query
			request[kSecValueData as String] = data
			request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
			let added = SecItemAdd(request as CFDictionary, nil)
			guard added == errSecSuccess else { throw PlanningCenterError.keychain(added) }
		} else if status != errSecSuccess {
			throw PlanningCenterError.keychain(status)
		}
	}

	public func delete() throws {
		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else { throw PlanningCenterError.keychain(status) }
	}
}
