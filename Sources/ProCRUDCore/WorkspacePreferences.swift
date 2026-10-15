import Foundation

/// Legacy macOS registrations are preference hints. They can point to retained
/// copies after upgrade and must never select the active native workspace.
public struct WorkspacePreferenceEntry: Codable, Sendable, Equatable {
	public let root: String
	public let displayName: String
	public let isActiveHint: Bool
	public let minimumRequiredProPresenterVersionHint: String?
}

public enum WorkspacePreferenceError: Error, CustomStringConvertible, Sendable {
	case propertyList(URL, underlying: any Error)
	case registrations(URL, underlying: any Error)
	case invalidFileURL(index: Int)

	public var description: String {
		switch self {
		case let .propertyList(url, error): "Cannot read workspace preference metadata at \(url.path): \(error)"
		case let .registrations(url, error): "Cannot decode userWorkspaces registrations at \(url.path): \(error)"
		case let .invalidFileURL(index): "Workspace preference entry \(index) requires an absolute local file URL."
		}
	}
}

public enum WorkspacePreferences {
	/// Reads only the documented-by-native-observation userWorkspaces property.
	/// Does not read account data, inspect roots, select a registration or mutate
	/// preferences. A missing property means no legacy registrations are present.
	public static func read(from url: URL) throws -> [WorkspacePreferenceEntry] {
		struct Preferences: Decodable { let userWorkspaces: Data? }
		struct Registration: Decodable {
			let url: String
			let name: String
			let isActive: Bool
			let minimumRequiredProPresenterVersion: String?
		}
		let data: Data?
		do {
			data = try PropertyListDecoder().decode(Preferences.self, from: Data(contentsOf: url)).userWorkspaces
		} catch {
			throw WorkspacePreferenceError.propertyList(url, underlying: error)
		}
		guard let data else { return [] }
		let registrations: [Registration]
		do {
			registrations = try JSONDecoder().decode([Registration].self, from: data)
		} catch {
			throw WorkspacePreferenceError.registrations(url, underlying: error)
		}
		return try registrations.enumerated().map { index, entry in
			guard let root = URL(string: entry.url), root.isFileURL, root.path.hasPrefix("/"),
			      root.host == nil || root.host == "" || root.host?.lowercased() == "localhost",
			      root.query == nil, root.fragment == nil
			else { throw WorkspacePreferenceError.invalidFileURL(index: index) }
			return .init(root: root.path, displayName: entry.name, isActiveHint: entry.isActive, minimumRequiredProPresenterVersionHint: entry.minimumRequiredProPresenterVersion)
		}
	}
}
