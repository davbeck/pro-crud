import Foundation
import ProPresenterProto
import SwiftProtobuf

public struct NativePlaylistExportResult: Encodable, Sendable {
	public struct Dependency: Encodable, Sendable {
		public let documentID: UUID
		public let archivePath: String
	}

	public let path: String
	public let workspaceID: UUID
	public let playlistID: UUID
	public let dependencies: [Dependency]
	public let compatibility: DocumentCompatibilityReport
	public let warnings: [String]
}

public enum NativePlaylistExporter {
	/// Exports a playlist and its portable Presentation/file dependency closure.
	/// Resolution uses native logical identities from this snapshot, never raw
	/// leftovers or a filename-only search. Both occurrences of a repeated link
	/// remain in the playlist; the shared document is embedded once.
	public static func bundle(
		from snapshot: NativeWorkspaceSnapshot,
		playlistID: UUID,
		to output: URL,
		replace: Bool = false,
		targetVersion: ProPresenterTargetVersion = .v22,
	) throws -> NativePlaylistExportResult {
		let root = snapshot.root.resolvingSymlinksInPath().standardizedFileURL.path
		let destination = output.resolvingSymlinksInPath().standardizedFileURL
		guard destination.path != root, !destination.path.hasPrefix(root + "/"), !root.hasPrefix(destination.path == "/" ? "/" : destination.path + "/") else {
			throw DocumentArchiveError.unsafeWorkspaceEntry(output.path)
		}
		try WorkspaceInspector.requireLegacyAccess(at: destination)
		let streams = snapshot.streams.filter { $0.identity.kind == "PlaylistLibrary" && $0.identity.scope == .shared }
		guard streams.count == 1, let shared = streams.first else { throw NativeSemanticError.invalidValue(path: "/PlaylistLibrary", expected: "one shared library playlist stream") }
		let client = snapshot.streams.first { $0.identity.documentID == shared.identity.documentID && $0.identity.scope == .client }
		var document = try NativePlaylistProjection(shared: shared, client: client).document
		func find(_ node: Rv_Data_Playlist) -> Rv_Data_Playlist? {
			if UUID(uuidString: node.uuid.string) == playlistID {
				return node
			}
			return node.playlists.playlists.lazy.compactMap(find).first
		}
		guard var selected = find(document.rootNode) else { throw NativeSemanticError.missingReference(path: "/playlists", identity: playlistID.uuidString) }
		guard case .items? = selected.childrenType else { throw NativeSemanticError.invalidValue(path: "/playlists/\(playlistID)", expected: "playlist containing items") }
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProCRUD-native-playlist-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
		defer { try? FileManager.default.removeItem(at: directory) }
		let exporter = NativeDependencyExport(snapshot: snapshot, target: targetVersion, directory: directory)
		selected = try Rv_Data_Playlist(serializedBytes: exporter.rewrite(selected.serializedData(), message: Rv_Data_Playlist.protoMessageName, path: "/playlists/\(playlistID)"))
		try exporter.publishDocuments()

		document.rootNode.playlists.playlists = [selected]
		document.clearLiveVideoPlaylist()
		document.clearDownloadsPlaylist()
		let usedTags = Set(selected.items.items.flatMap(\.tags).map { $0.string.lowercased() })
		document.tags = document.tags.filter { usedTags.contains($0.uuid.string.lowercased()) }
		guard Set(document.tags.map { $0.uuid.string.lowercased() }) == usedTags else {
			throw NativeSemanticError.missingReference(path: "/tags", identity: "selected playlist tag definition")
		}
		let dataURL = directory.appendingPathComponent("data")
		try DocumentWriter.writeRaw(.init(payload: .playlist(document), origin: .raw(dataURL)), to: dataURL, targetVersion: targetVersion)
		let result = try DocumentArchive.bundleWithReport(directory, to: destination, replace: replace, targetVersion: targetVersion)
		return .init(path: result.archiveURL.path, workspaceID: snapshot.workspaceID, playlistID: playlistID, dependencies: exporter.dependencies, compatibility: result.compatibility, warnings: result.warnings)
	}
}
