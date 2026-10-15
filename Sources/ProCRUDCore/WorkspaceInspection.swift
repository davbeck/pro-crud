import Foundation

public enum WorkspaceStorage: String, Codable, Sendable {
	case legacyProtobuf = "legacy-protobuf"
	case legacyExport = "legacy-export"
	case expandedExport = "expanded-export"
	case nativeLoro = "native-loro-sqlite"
	case unrecognized
}

/// Storage evidence is independent of the installed app and of the originating
/// application version. A compatibility export does not identify its producer.
public struct WorkspaceInspection: Codable, Sendable {
	public var root: String
	public var storage: WorkspaceStorage
	public var workspaceID: String?
	public var storageMarker: String?
	public var evidence: [String]
	public var supportedOperations: [String]
	public var unresolvedCapabilities: [String]
	public var legacyExportManifest: LegacyExportManifest?
}

public struct LegacyExportManifest: Codable, Sendable {
	public var version: Int
	public var targetContract: String?
	public var mediaPolicy: String?
	public var compatibilityWarningCount: Int
	public var compatibilityWarnings: [String]
	public var documentCount: Int
	public var reopenedDocumentCount: Int
	public var copiedMediaReferenceCount: Int
	public var preservedMediaCount: Int

	init(url: URL) throws {
		let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
		guard let json = object as? [String: Any] else {
			throw WorkspaceInspectionError.invalidManifest(url)
		}
		guard let version = json["version"] as? Int, version == 1,
		      let warnings = json["compatibility_warnings"] as? [String]
		else { throw WorkspaceInspectionError.invalidManifest(url) }
		self.version = version
		targetContract = json["target_contract"] as? String
		mediaPolicy = json["missing_media_policy"] as? String
		compatibilityWarnings = warnings
		compatibilityWarningCount = warnings.count
		let documents = json["documents"] as? [[String: Any]] ?? []
		documentCount = documents.count
		reopenedDocumentCount = documents.count { $0["reopened"] as? Bool == true }
		copiedMediaReferenceCount = (json["media_references"] as? [Any])?.count ?? 0
		preservedMediaCount = (json["preserved_media"] as? [Any])?.count ?? 0
	}
}

public enum WorkspaceInspectionError: Error, CustomStringConvertible, Sendable {
	case nativeWorkspace(URL)
	case wholeWorkspace(URL)
	case invalidManifest(URL)

	public var description: String {
		switch self {
		case let .nativeWorkspace(root):
			"\(root.path) uses native ProPresenter workspace storage (SQLite/Loro). Direct document editing, rendering, and media validation are not qualified for this storage. In ProPresenter use File → Export → Legacy Workspace, or export a Presentation Bundle, Playlist, or Theme, then operate on that separate export. The preserved UserWorkspaces copy does not update this workspace."
		case let .wholeWorkspace(root):
			"\(root.path) is a whole legacy workspace, not an expanded single-document archive. Use workspace inspect for storage evidence, or select a document under Libraries, Playlists, or Themes."
		case let .invalidManifest(url):
			"Invalid Legacy Workspace export manifest at \(url.path)."
		}
	}
}

public enum WorkspaceInspector {
	public static func inspect(_ directory: URL) throws -> WorkspaceInspection {
		let root = directory.resolvingSymlinksInPath().standardizedFileURL
		let values = try root.resourceValues(forKeys: [.isDirectoryKey])
		guard values.isDirectory == true else { throw DocumentLoadError.unsupportedInput(root) }
		let manager = FileManager.default
		let markers = ["DocumentStore/workspace-v1.sqlite3", "DocumentStore/workspace-storage-v1", "DocumentStore/workspace-id"]
		let evidence = markers.filter { manager.fileExists(atPath: root.appendingPathComponent($0).path) }
		if !evidence.isEmpty {
			return try WorkspaceInspection(
				root: root.path,
				storage: .nativeLoro,
				workspaceID: marker("DocumentStore/workspace-id", in: root),
				storageMarker: marker("DocumentStore/workspace-storage-v1", in: root),
				evidence: evidence,
				supportedOperations: ["inspect-storage"],
				unresolvedCapabilities: ["native-document-read", "native-document-write", "native-media-registry", "cloud-availability"],
			)
		}
		let folders = ["Libraries", "Playlists", "Configuration", "Themes"].filter {
			(try? root.appendingPathComponent($0).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
		}
		let legacy = folders.contains("Libraries") || folders.contains("Configuration") || folders.contains("Playlists")
		let manifestURL = root.appendingPathComponent(".procore/legacy-export-manifest.json")
		if manager.fileExists(atPath: manifestURL.path) {
			return try WorkspaceInspection(
				root: root.path, storage: legacy ? .legacyExport : .expandedExport,
				evidence: [".procore/legacy-export-manifest.json"],
				supportedOperations: ["inspect-storage", "protobuf-document-read", "protobuf-document-write"],
				unresolvedCapabilities: ["source-application-version", "native-only-features"],
				legacyExportManifest: LegacyExportManifest(url: manifestURL),
			)
		}
		return WorkspaceInspection(
			root: root.path, storage: legacy ? .legacyProtobuf : .unrecognized,
			evidence: folders,
			supportedOperations: legacy ? ["inspect-storage", "protobuf-document-read", "protobuf-document-write"] : ["inspect-storage"],
			unresolvedCapabilities: legacy ? ["source-application-version"] : ["workspace-storage"],
		)
	}

	/// Reject native roots and raw leftovers inside them before legacy paths can
	/// be consulted. Explicitly selected retained legacy workspaces stay usable.
	public static func requireLegacyAccess(at input: URL) throws {
		var directory = input.resolvingSymlinksInPath().standardizedFileURL
		if (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
			directory.deleteLastPathComponent()
		}
		while directory.path != "/" {
			if FileManager.default.fileExists(atPath: directory.appendingPathComponent("DocumentStore").path),
			   try inspect(directory).storage == .nativeLoro
			{
				throw WorkspaceInspectionError.nativeWorkspace(directory)
			}
			directory.deleteLastPathComponent()
		}
	}

	static func requireSingleDocumentDirectory(_ directory: URL) throws {
		try requireLegacyAccess(at: directory)
		let inspection = try inspect(directory)
		if inspection.storage == .legacyProtobuf || inspection.storage == .legacyExport {
			throw WorkspaceInspectionError.wholeWorkspace(directory)
		}
	}

	private static func marker(_ path: String, in root: URL) throws -> String? {
		let url = root.appendingPathComponent(path)
		guard FileManager.default.fileExists(atPath: url.path) else { return nil }
		return try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
