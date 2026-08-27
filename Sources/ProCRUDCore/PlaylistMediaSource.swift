import Foundation
import ProPresenterProto

public struct PlaylistMediaSelection: Sendable {
	public var media: Rv_Data_Media
	public var playlistName: String
	public var itemName: String

	public init(media: Rv_Data_Media, playlistName: String, itemName: String) {
		self.media = media
		self.playlistName = playlistName
		self.itemName = itemName
	}
}

public enum PlaylistMediaSource {
	/// Loads one canonical media identity from a media playlist document or
	/// archive. Both current playlist wrapper fields and legacy `children` are
	/// traversed because real ProPresenter libraries contain both shapes.
	public static func select(from sourceURL: URL, playlist playlistName: String, item itemName: String) throws -> PlaylistMediaSelection {
		let document = try DocumentLoader.load(from: playlistDocumentURL(for: sourceURL))
		guard case let .playlist(playlistDocument) = document.payload else {
			throw DocumentEditError.unsupportedPatchValue("--from-playlist requires a playlist document, workspace, or .proPlaylist archive.")
		}
		let playlists = flattenedPlaylists(playlistDocument.rootNode).filter { $0.name == playlistName }
		guard playlists.count == 1, let playlist = playlists.first else {
			throw DocumentEditError.unsupportedPatchValue(
				playlists.isEmpty
					? "No playlist named \(playlistName) was found."
					: "More than one playlist is named \(playlistName); select a unique playlist name.",
			)
		}
		let items = playlistItems(in: playlist).filter { $0.name == itemName }
		guard items.count == 1, let item = items.first else {
			throw DocumentEditError.unsupportedPatchValue(
				items.isEmpty
					? "No item named \(itemName) was found in playlist \(playlistName)."
					: "More than one item is named \(itemName) in playlist \(playlistName); select a unique item name.",
			)
		}
		guard case let .cue(cue)? = item.itemType else {
			throw DocumentEditError.unsupportedPatchValue("Playlist item \(itemName) is not a media cue.")
		}
		let media = cue.actions.compactMap { action -> Rv_Data_Media? in
			guard case let .media(mediaType)? = action.actionTypeData else { return nil }
			return mediaType.element
		}
		guard media.count == 1, let selected = media.first else {
			throw DocumentEditError.unsupportedPatchValue(
				"Playlist item \(itemName) must contain exactly one media action; found \(media.count).",
			)
		}
		guard !selected.uuid.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw DocumentEditError.unsupportedPatchValue(
				"Playlist item \(itemName) has no media UUID and cannot provide a canonical media identity.",
			)
		}
		let hasUsableURL = switch selected.url.storage {
		case let .absoluteString(value)?: !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		case let .relativePath(value)?: !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		case nil: false
		}
		guard hasUsableURL else {
			throw DocumentEditError.unsupportedPatchValue(
				"Playlist item \(itemName) has no usable media URL.",
			)
		}
		return PlaylistMediaSelection(media: selected, playlistName: playlist.name, itemName: item.name)
	}

	/// Resolves the media-playlist database when a caller passes either that
	/// database directly, its containing `Playlists` directory, or a complete
	/// live ProPresenter workspace.
	private static func playlistDocumentURL(for sourceURL: URL) throws -> URL {
		let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
		guard values.isDirectory == true else { return sourceURL }

		let candidates = [
			sourceURL.appendingPathComponent("Playlists/Media"),
			sourceURL.appendingPathComponent("Media"),
		]
		for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
			return candidate
		}
		return sourceURL
	}

	private static func flattenedPlaylists(_ root: Rv_Data_Playlist) -> [Rv_Data_Playlist] {
		[root] + childPlaylists(in: root).flatMap(flattenedPlaylists)
	}

	private static func childPlaylists(in playlist: Rv_Data_Playlist) -> [Rv_Data_Playlist] {
		var children = playlist.children
		if case let .playlists(wrapper)? = playlist.childrenType {
			children.append(contentsOf: wrapper.playlists)
		}
		return children
	}

	private static func playlistItems(in playlist: Rv_Data_Playlist) -> [Rv_Data_PlaylistItem] {
		guard case let .items(wrapper)? = playlist.childrenType else { return [] }
		return wrapper.items
	}
}
