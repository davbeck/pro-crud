import CoreGraphics
import Foundation
import ProPresenterProto

public enum DocumentCreationError: Error, CustomStringConvertible, Sendable {
	case invalidCanvasSize(String)
	case missingPresentationSlideAction

	public var description: String {
		switch self {
		case let .invalidCanvasSize(value): "Invalid canvas size \(value). Use WIDTHxHEIGHT."
		case .missingPresentationSlideAction: "The first cue does not contain a presentation-slide action."
		}
	}
}

public enum DocumentFactory {
	public static func presentation(name: String, canvasSize: CGSize = CGSize(width: 1920, height: 1080)) -> Rv_Data_Presentation {
		let presentationID = uuid()
		let cueID = uuid()
		var slide = Rv_Data_Slide()
		slide.uuid = uuid()
		slide.size = size(canvasSize)

		var presentationSlide = Rv_Data_PresentationSlide()
		presentationSlide.baseSlide = slide
		var action = Rv_Data_Action()
		action.uuid = uuid()
		action.label.text = "Slide 1"
		action.type = .presentationSlide
		action.isEnabled = true
		action.slide.presentation = presentationSlide

		var cue = Rv_Data_Cue()
		cue.uuid = cueID
		cue.name = "Slide 1"
		cue.isEnabled = true
		cue.completionActionType = .last
		cue.actions = [action]

		var group = Rv_Data_Group()
		group.uuid = uuid()
		group.name = "Slides"
		group.color = color(red: 0.2, green: 0.48, blue: 0.9, alpha: 1)
		group.hotKey = Rv_Data_HotKey()
		var cueGroup = Rv_Data_Presentation.CueGroup()
		cueGroup.group = group
		cueGroup.cueIdentifiers = [cueID]

		var result = Rv_Data_Presentation()
		result.applicationInfo = applicationInfo()
		result.uuid = presentationID
		result.name = name
		result.cues = [cue]
		result.cueGroups = [cueGroup]
		return result
	}

	public static func theme() -> Rv_Data_Template.Document {
		var result = Rv_Data_Template.Document()
		result.applicationInfo = applicationInfo()
		return result
	}

	public static func playlist(name: String) -> Rv_Data_PlaylistDocument {
		var child = Rv_Data_Playlist()
		child.uuid = uuid()
		child.name = name
		child.items = Rv_Data_Playlist.PlaylistItems()

		var root = Rv_Data_Playlist()
		root.uuid = uuid()
		root.name = "PLAYLIST"
		root.expanded = true
		var playlists = Rv_Data_Playlist.PlaylistArray()
		playlists.playlists = [child]
		root.playlists = playlists

		var liveVideo = Rv_Data_Playlist()
		liveVideo.uuid = uuid()
		liveVideo.name = "Video Input"
		liveVideo.items = Rv_Data_Playlist.PlaylistItems()

		var downloads = Rv_Data_Playlist()
		downloads.uuid = uuid()
		downloads.name = "Downloads"
		downloads.items = Rv_Data_Playlist.PlaylistItems()

		var result = Rv_Data_PlaylistDocument()
		result.applicationInfo = applicationInfo()
		result.type = .presentation
		result.rootNode = root
		result.liveVideoPlaylist = liveVideo
		result.downloadsPlaylist = downloads
		return result
	}

	public static func applying(
		template: Rv_Data_Template.Slide,
		to presentation: Rv_Data_Presentation,
		includeTemplateActions: Bool = false,
	) throws -> Rv_Data_Presentation {
		try applyingWithReport(
			template: template,
			to: presentation,
			includeTemplateActions: includeTemplateActions,
		).presentation
	}

	public static func applyingWithReport(
		template: Rv_Data_Template.Slide,
		to presentation: Rv_Data_Presentation,
		includeTemplateActions: Bool = false,
	) throws -> (presentation: Rv_Data_Presentation, report: TemplateResolutionReport?) {
		var result = presentation
		guard !result.cues.isEmpty else { return (result, nil) }
		guard let actionIndex = result.cues[0].actions.indices.first(where: { index in
			guard result.cues[0].actions[index].type == .presentationSlide else { return false }
			if case .presentation? = result.cues[0].actions[index].slide.slide {
				return true
			}
			return false
		}) else {
			throw DocumentCreationError.missingPresentationSlideAction
		}
		let destination = result.cues[0].actions[actionIndex].slide.presentation.baseSlide.size
		let resolution = try TemplateResolver.resolve(
			template: template,
			source: nil,
			destinationSize: CGSize(width: destination.width, height: destination.height),
			mode: .instantiateNew,
		)
		result.cues[0].actions[actionIndex].slide.presentation.baseSlide = resolution.slide
		if includeTemplateActions {
			result.cues[0].actions.append(contentsOf: resolution.actions)
		}
		result.cues[0].name = template.name.isEmpty ? result.cues[0].name : template.name
		result.cues[0].actions[actionIndex].label.text = result.cues[0].name
		return (result, resolution.report)
	}

	public static func canvasSize(_ value: String) throws -> CGSize {
		let parts = value.split(separator: "x", maxSplits: 1).map(String.init)
		guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]), width > 0, height > 0 else {
			throw DocumentCreationError.invalidCanvasSize(value)
		}
		return CGSize(width: width, height: height)
	}

	static func uuid() -> Rv_Data_UUID {
		var value = Rv_Data_UUID()
		value.string = UUID().uuidString.uppercased()
		return value
	}

	private static func applicationInfo() -> Rv_Data_ApplicationInfo {
		var value = Rv_Data_ApplicationInfo()
		value.platform = .macos
		value.platformVersion.majorVersion = 26
		value.application = .propresenter
		value.applicationVersion.majorVersion = 7
		return value
	}

	private static func size(_ value: CGSize) -> Rv_Data_Graphics.Size {
		var size = Rv_Data_Graphics.Size()
		size.width = value.width
		size.height = value.height
		return size
	}

	private static func color(red: Float, green: Float, blue: Float, alpha: Float) -> Rv_Data_Color {
		var color = Rv_Data_Color()
		color.red = red
		color.green = green
		color.blue = blue
		color.alpha = alpha
		return color
	}
}

public enum ThemeTemplateSource {
	public struct MediaReference: Hashable, Sendable {
		public var uuid: String
		public var renderPath: String

		public init(uuid: String, renderPath: String) {
			self.uuid = uuid
			self.renderPath = renderPath
		}
	}

	public struct Candidate: Sendable {
		public var name: String
		public var sourcePath: String
		public var componentPath: String
		public var themeDocumentPath: String
		public var resourceDirectory: URL?
		public var mediaWarnings: [String]
		public var preferredAbsoluteMediaURLs: Set<String>
		public var preferredMediaReferences: Set<MediaReference>
		public var slide: Rv_Data_Template.Slide
		var temporaryResourceOwner: TemporaryDirectoryOwner?
	}

	public static func candidates(
		from url: URL,
		themeDocument: String? = nil,
		showRoot: URL? = nil,
		archiveLimits: ArchiveLimits = .default,
	) throws -> [Candidate] {
		let loaded = try DocumentLoader.load(from: url, archiveLimits: archiveLimits)
		guard case let .theme(fallbackTheme) = loaded.payload else {
			throw DocumentLoadError.invalidPayload(
				expected: DocumentKind.theme.rawValue,
				location: url.path,
				underlying: "input is a \(loaded.kind.rawValue) document",
			)
		}
		let usesFallbackEntry = loaded.themeEntries.isEmpty
		let entries: [ProPresenterDocument.ThemeEntry]
		if usesFallbackEntry {
			entries = [.init(relativePath: "Theme", document: fallbackTheme)]
		} else {
			entries = loaded.themeEntries
		}
		let selectedEntries = if let themeDocument {
			entries.filter { $0.relativePath == themeDocument }
		} else {
			entries
		}
		guard !selectedEntries.isEmpty else {
			throw ThemeTemplateSourceError.noThemeDocument(
				requested: themeDocument ?? "",
				candidates: entries.map(\.relativePath),
			)
		}
		var candidates: [Candidate] = []
		for entry in selectedEntries {
			let fallbackPrefix = url.deletingLastPathComponent().lastPathComponent
			let sourcePrefix = if usesFallbackEntry, !fallbackPrefix.isEmpty {
				"\(fallbackPrefix)/Theme"
			} else {
				entry.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
			}
			candidates += entry.document.slides.enumerated().map { index, originalSlide in
				let rebased = TemplateMediaResolver.rebase(
					template: originalSlide,
					resourceDirectory: loaded.resourceDirectory,
					themeDocumentPath: entry.relativePath,
					showRoot: showRoot,
				)
				return Candidate(
					name: originalSlide.name,
					sourcePath: "\(sourcePrefix)#\(index)",
					componentPath: "/slides[index=\(index)]",
					themeDocumentPath: entry.relativePath,
					resourceDirectory: loaded.resourceDirectory,
					mediaWarnings: rebased.warnings,
					preferredAbsoluteMediaURLs: rebased.preferredAbsoluteMediaURLs,
					preferredMediaReferences: mediaReferences(in: rebased.template),
					slide: rebased.template,
					temporaryResourceOwner: loaded.temporaryResourceOwner,
				)
			}
		}
		return candidates
	}

	public static func mediaReferences(in template: Rv_Data_Template.Slide) -> Set<MediaReference> {
		mediaReferences(in: template.baseSlide).union(mediaReferences(in: template.actions))
	}

	public static func mediaReferences(in slide: Rv_Data_Slide) -> Set<MediaReference> {
		slide.elements.reduce(into: Set<MediaReference>()) { result, element in
			collectMediaReferences(in: element.element, into: &result)
		}
	}

	public static func mediaReferences(in actions: [Rv_Data_Action]) -> Set<MediaReference> {
		actions.reduce(into: Set<MediaReference>()) { result, action in
			collectMediaReferences(in: action, into: &result)
		}
	}

	private static func collectMediaReferences(
		in action: Rv_Data_Action,
		into result: inout Set<MediaReference>,
	) {
		switch action.type {
		case .media, .foregroundMedia, .backgroundMedia:
			collectMediaReference(action.media.element, into: &result)
			for marker in action.media.markers {
				for nestedAction in marker.actions {
					collectMediaReferences(in: nestedAction, into: &result)
				}
			}
		case .presentationSlide:
			result.formUnion(mediaReferences(in: action.slide.presentation.baseSlide))
		case .propSlide:
			result.formUnion(mediaReferences(in: action.slide.prop.baseSlide))
		default:
			break
		}
	}

	private static func collectMediaReferences(
		in element: Rv_Data_Graphics.Element,
		into result: inout Set<MediaReference>,
	) {
		if case let .media(media)? = element.fill.fillType {
			collectMediaReference(media, into: &result)
		}
		guard element.hasText else { return }
		if case let .mediaFill(fill)? = element.text.attributes.fill {
			collectMediaReference(fill.media, into: &result)
		}
		for attribute in element.text.attributes.customAttributes {
			if case let .mediaFill(fill)? = attribute.attribute {
				collectMediaReference(fill.media, into: &result)
			}
		}
	}

	private static func collectMediaReference(
		_ media: Rv_Data_Media,
		into result: inout Set<MediaReference>,
	) {
		let path = media.url.renderPath
		guard !path.isEmpty else { return }
		result.insert(MediaReference(uuid: media.uuid.string, renderPath: path))
	}

	public static func select(_ candidates: [Candidate], named name: String?) throws -> Candidate {
		let matches: [Candidate]
		if let name {
			if name.hasPrefix("/") {
				let path = try ComponentPath(name)
				guard path.segments.count == 1,
				      path.segments[0].field == "slides",
				      let selector = path.segments[0].selector
				else {
					throw ComponentPathError.unsupported(field: path.description, at: "/")
				}
				matches = candidates.filter { candidate in
					switch selector {
					case let .index(index): candidate.componentPath == "/slides[index=\(index)]"
					case let .field(field, value):
						(field == "name" && candidate.name == value) ||
							(field == "uuid" && candidate.slide.baseSlide.uuid.string == value)
					}
				}
			} else {
				matches = candidates.filter { $0.name == name || $0.sourcePath == name }
			}
		} else {
			matches = candidates
		}
		guard matches.count == 1, let candidate = matches.first else {
			let descriptions = candidates.map { "\($0.sourcePath) (\($0.name))" }
			throw ThemeTemplateSourceError.ambiguousTemplate(descriptions)
		}
		return candidate
	}
}

public enum ThemeTemplateSourceError: Error, CustomStringConvertible, Sendable {
	case ambiguousTemplate([String])
	case noThemeDocument(requested: String, candidates: [String])

	public var description: String {
		switch self {
		case let .ambiguousTemplate(candidates):
			return "Theme template selection is ambiguous. Specify --template using an exact name or source path. Candidates: \(candidates.joined(separator: ", "))"
		case let .noThemeDocument(requested, candidates):
			return "Theme document \(requested) was not found. Candidates: \(candidates.joined(separator: ", "))"
		}
	}
}

public enum TemplateMediaMaterializationError: Error, CustomStringConvertible, Sendable {
	case conflictingIdentity(String)
	case missingSource(String)

	public var description: String {
		switch self {
		case let .conflictingIdentity(uuid):
			"Template application produced conflicting media values with UUID \(uuid)."
		case let .missingSource(value):
			"Template media source is no longer available: \(value)"
		}
	}
}

/// Copies media introduced from a separately loaded Theme beside a raw
/// presentation (or into an archive editing workspace) and rewrites only those
/// exact absolute URLs to portable relative paths.
public enum TemplateMediaMaterializer {
	public static func materialize(
		in presentation: inout Rv_Data_Presentation,
		absoluteURLs: Set<String>,
		destinationDirectory: URL,
	) throws {
		try materialize(
			in: &presentation,
			absoluteURLs: absoluteURLs,
			destinationDirectory: destinationDirectory,
			archiveBudget: nil,
		)
	}

	static func materialize(
		in presentation: inout Rv_Data_Presentation,
		absoluteURLs: Set<String>,
		destinationDirectory: URL,
		archiveBudget: ArchiveCopyBudget?,
	) throws {
		guard !absoluteURLs.isEmpty else { return }
		try validateMediaIdentities(
			in: presentation,
			introducedAbsoluteURLs: absoluteURLs,
			destinationDirectory: destinationDirectory,
			archiveBudget: archiveBudget,
		)
		try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
		var included: [String: String] = [:]
		for cueIndex in presentation.cues.indices {
			for actionIndex in presentation.cues[cueIndex].actions.indices {
				try materialize(
					action: &presentation.cues[cueIndex].actions[actionIndex],
					absoluteURLs: absoluteURLs,
					destinationDirectory: destinationDirectory,
					archiveBudget: archiveBudget,
					included: &included,
				)
			}
		}
	}

	private static func validateMediaIdentities(
		in presentation: Rv_Data_Presentation,
		introducedAbsoluteURLs: Set<String>,
		destinationDirectory: URL,
		archiveBudget: ArchiveCopyBudget?,
	) throws {
		var mediaValues: [Rv_Data_Media] = []
		for cue in presentation.cues {
			for action in cue.actions {
				collectMedia(in: action, into: &mediaValues)
			}
		}
		let introduced = mediaValues.filter {
			isIntroduced($0.url, absoluteURLs: introducedAbsoluteURLs) && !$0.uuid.string.isEmpty
		}
		for introducedMedia in introduced {
			for existing in mediaValues where existing.uuid == introducedMedia.uuid {
				guard try sameAsset(
					introducedMedia.url,
					existing.url,
					introducedAbsoluteURLs: introducedAbsoluteURLs,
					destinationDirectory: destinationDirectory,
					archiveBudget: archiveBudget,
				) else {
					throw TemplateMediaMaterializationError.conflictingIdentity(introducedMedia.uuid.string)
				}
			}
		}
	}

	private static func isIntroduced(_ value: Rv_Data_URL, absoluteURLs: Set<String>) -> Bool {
		guard case let .absoluteString(string)? = value.storage else { return false }
		return absoluteURLs.contains(string)
	}

	private static func sameAsset(
		_ introduced: Rv_Data_URL,
		_ other: Rv_Data_URL,
		introducedAbsoluteURLs: Set<String>,
		destinationDirectory: URL,
		archiveBudget: ArchiveCopyBudget?,
	) throws -> Bool {
		let left = assetURL(
			introduced,
			preferIntroducedAbsolute: true,
			destinationDirectory: destinationDirectory,
		)
		let right = assetURL(
			other,
			preferIntroducedAbsolute: isIntroduced(other, absoluteURLs: introducedAbsoluteURLs),
			destinationDirectory: destinationDirectory,
		)
		guard let left, let right else { return false }
		if left.standardizedFileURL == right.standardizedFileURL {
			return true
		}
		guard FileManager.default.fileExists(atPath: left.path),
		      FileManager.default.fileExists(atPath: right.path)
		else {
			return false
		}
		if let archiveBudget {
			return try ArchiveFileIO.contentsEqual(left, right, deadline: archiveBudget.deadline)
		}
		return FileManager.default.contentsEqual(atPath: left.path, andPath: right.path)
	}

	private static func assetURL(
		_ value: Rv_Data_URL,
		preferIntroducedAbsolute: Bool,
		destinationDirectory: URL,
	) -> URL? {
		if preferIntroducedAbsolute,
		   case let .absoluteString(string)? = value.storage,
		   let url = fileURL(from: string)
		{
			return url
		}
		if case let .local(local)? = value.relativeFilePath,
		   let root = localRoot(local.root, destinationDirectory: destinationDirectory)
		{
			return root.appendingPathComponent(trimmedPath(local.path)).standardizedFileURL
		}
		if case let .external(external)? = value.relativeFilePath,
		   !external.macos.volumeName.isEmpty
		{
			return URL(fileURLWithPath: "/Volumes/\(external.macos.volumeName)", isDirectory: true)
				.appendingPathComponent(trimmedPath(external.path))
				.standardizedFileURL
		}
		switch value.storage {
		case let .absoluteString(string):
			return fileURL(from: string)
		case let .relativePath(path):
			return destinationDirectory.appendingPathComponent(trimmedPath(path)).standardizedFileURL
		case nil:
			return nil
		}
	}

	private static func localRoot(
		_ root: Rv_Data_URL.LocalRelativePath.Root,
		destinationDirectory: URL,
	) -> URL? {
		let fileManager = FileManager.default
		return switch root {
		case .bootVolume: URL(fileURLWithPath: "/", isDirectory: true)
		case .userHome: fileManager.homeDirectoryForCurrentUser
		case .userDocuments: fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
		case .userDownloads: fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
		case .userMusic: fileManager.urls(for: .musicDirectory, in: .userDomainMask).first
		case .userPictures: fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
		case .userVideos: fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
		case .userDesktop: fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
		case .userAppSupport: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
		case .shared: URL(fileURLWithPath: "/Users/Shared", isDirectory: true)
		case .show, .currentResource: destinationDirectory
		case .unknown, .UNRECOGNIZED: nil
		}
	}

	private static func fileURL(from value: String) -> URL? {
		if let url = URL(string: value), url.isFileURL {
			return url.standardizedFileURL
		}
		let decoded = value.removingPercentEncoding ?? value
		if decoded.hasPrefix("file://") {
			return URL(fileURLWithPath: String(decoded.dropFirst("file://".count))).standardizedFileURL
		}
		if decoded.hasPrefix("/") {
			return URL(fileURLWithPath: decoded).standardizedFileURL
		}
		return nil
	}

	private static func trimmedPath(_ value: String) -> String {
		value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
	}

	private static func collectMedia(in action: Rv_Data_Action, into result: inout [Rv_Data_Media]) {
		switch action.type {
		case .media, .foregroundMedia, .backgroundMedia:
			result.append(action.media.element)
			for marker in action.media.markers {
				for nestedAction in marker.actions {
					collectMedia(in: nestedAction, into: &result)
				}
			}
		case .presentationSlide:
			collectMedia(in: action.slide.presentation.baseSlide, into: &result)
		case .propSlide:
			collectMedia(in: action.slide.prop.baseSlide, into: &result)
		default:
			break
		}
	}

	private static func collectMedia(in slide: Rv_Data_Slide, into result: inout [Rv_Data_Media]) {
		for element in slide.elements {
			if case let .media(media)? = element.element.fill.fillType {
				result.append(media)
			}
			guard element.element.hasText else { continue }
			if case let .mediaFill(fill)? = element.element.text.attributes.fill {
				result.append(fill.media)
			}
			for attribute in element.element.text.attributes.customAttributes {
				if case let .mediaFill(fill)? = attribute.attribute {
					result.append(fill.media)
				}
			}
		}
	}

	private static func materialize(
		action: inout Rv_Data_Action,
		absoluteURLs: Set<String>,
		destinationDirectory: URL,
		archiveBudget: ArchiveCopyBudget?,
		included: inout [String: String],
	) throws {
		switch action.type {
		case .media, .foregroundMedia, .backgroundMedia:
			var mediaType = action.media
			try materialize(
				media: &mediaType.element,
				absoluteURLs: absoluteURLs,
				destinationDirectory: destinationDirectory,
				archiveBudget: archiveBudget,
				included: &included,
			)
			for markerIndex in mediaType.markers.indices {
				for actionIndex in mediaType.markers[markerIndex].actions.indices {
					try materialize(
						action: &mediaType.markers[markerIndex].actions[actionIndex],
						absoluteURLs: absoluteURLs,
						destinationDirectory: destinationDirectory,
						archiveBudget: archiveBudget,
						included: &included,
					)
				}
			}
			action.media = mediaType
		case .presentationSlide, .propSlide:
			if case var .presentation(presentationSlide)? = action.slide.slide {
				try materialize(
					slide: &presentationSlide.baseSlide,
					absoluteURLs: absoluteURLs,
					destinationDirectory: destinationDirectory,
					archiveBudget: archiveBudget,
					included: &included,
				)
				action.slide.presentation = presentationSlide
			} else if case var .prop(propSlide)? = action.slide.slide {
				try materialize(
					slide: &propSlide.baseSlide,
					absoluteURLs: absoluteURLs,
					destinationDirectory: destinationDirectory,
					archiveBudget: archiveBudget,
					included: &included,
				)
				action.slide.prop = propSlide
			}
		default:
			break
		}
	}

	private static func materialize(
		slide: inout Rv_Data_Slide,
		absoluteURLs: Set<String>,
		destinationDirectory: URL,
		archiveBudget: ArchiveCopyBudget?,
		included: inout [String: String],
	) throws {
		for index in slide.elements.indices {
			var element = slide.elements[index].element
			if case var .media(media)? = element.fill.fillType {
				try materialize(
					media: &media,
					absoluteURLs: absoluteURLs,
					destinationDirectory: destinationDirectory,
					archiveBudget: archiveBudget,
					included: &included,
				)
				element.fill.media = media
			}
			if element.hasText {
				var attributes = element.text.attributes
				if case var .mediaFill(fill)? = attributes.fill {
					try materialize(
						media: &fill.media,
						absoluteURLs: absoluteURLs,
						destinationDirectory: destinationDirectory,
						archiveBudget: archiveBudget,
						included: &included,
					)
					attributes.mediaFill = fill
				}
				for attributeIndex in attributes.customAttributes.indices {
					if case var .mediaFill(fill)? = attributes.customAttributes[attributeIndex].attribute {
						try materialize(
							media: &fill.media,
							absoluteURLs: absoluteURLs,
							destinationDirectory: destinationDirectory,
							archiveBudget: archiveBudget,
							included: &included,
						)
						attributes.customAttributes[attributeIndex].mediaFill = fill
					}
				}
				element.text.attributes = attributes
			}
			slide.elements[index].element = element
		}
	}

	private static func materialize(
		media: inout Rv_Data_Media,
		absoluteURLs: Set<String>,
		destinationDirectory: URL,
		archiveBudget: ArchiveCopyBudget?,
		included: inout [String: String],
	) throws {
		guard case let .absoluteString(value)? = media.url.storage,
		      absoluteURLs.contains(value)
		else { return }
		if let relative = included[value] {
			media.url.relativePath = relative
			media.url.relativeFilePath = nil
			return
		}
		guard let sourceURL = URL(string: value), sourceURL.isFileURL,
		      FileManager.default.fileExists(atPath: sourceURL.path)
		else {
			throw TemplateMediaMaterializationError.missingSource(value)
		}
		let relative = try include(
			sourceURL,
			in: destinationDirectory,
			archiveBudget: archiveBudget,
		)
		included[value] = relative
		media.url.relativePath = relative
		media.url.relativeFilePath = nil
	}

	private static func include(
		_ sourceURL: URL,
		in destinationDirectory: URL,
		archiveBudget: ArchiveCopyBudget?,
	) throws -> String {
		let standardizedSource = sourceURL.standardizedFileURL
		if let relativePath = try? DocumentLoader.relativePath(of: standardizedSource, in: destinationDirectory) {
			try validateArchivePath(relativePath, limits: archiveBudget?.limits)
			if let archiveBudget {
				try archiveBudget.accountExisting(standardizedSource, entry: relativePath)
			}
			return relativePath
		}

		let fileManager = FileManager.default
		var suffix = 0
		while true {
			try archiveBudget?.deadline.check()
			let filename = ArchiveFileIO.path(sourceURL.lastPathComponent, addingNumericSuffix: suffix)
			try validateArchivePath(filename, limits: archiveBudget?.limits)
			let destination = destinationDirectory.appendingPathComponent(filename)
			if !fileManager.fileExists(atPath: destination.path) {
				if let archiveBudget {
					try archiveBudget.copy(from: standardizedSource, to: destination, entry: filename)
				} else {
					try fileManager.copyItem(at: standardizedSource, to: destination)
				}
				return filename
			}
			let contentsMatch = if let archiveBudget {
				try ArchiveFileIO.contentsEqual(
					standardizedSource,
					destination,
					deadline: archiveBudget.deadline,
				)
			} else {
				fileManager.contentsEqual(atPath: standardizedSource.path, andPath: destination.path)
			}
			if contentsMatch {
				return filename
			}
			suffix += 1
		}
	}

	private static func validateArchivePath(_ path: String, limits: ArchiveLimits?) throws {
		guard let limits else { return }
		guard !path.isEmpty,
		      !path.hasPrefix("/"),
		      !path.contains("\\"),
		      path.utf8.count <= limits.maximumPathLength,
		      !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
		else {
			throw ArchiveError.invalidEntry(path)
		}
		let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		guard components.count <= limits.maximumPathDepth,
		      components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }),
		      components.allSatisfy({ $0.utf8.count <= limits.maximumPathComponentLength }),
		      components.first?.range(of: "^[A-Za-z]:", options: .regularExpression) == nil
		else {
			throw ArchiveError.invalidEntry(path)
		}
	}
}

private enum TemplateMediaResolver {
	private struct ResourceRoots {
		var theme: URL
		var resource: URL
		var show: URL?

		var fallback: [URL] {
			var values = [theme, resource]
			if let show {
				values.append(show)
			}
			return values
		}
	}

	struct Result {
		var template: Rv_Data_Template.Slide
		var warnings: [String]
		var preferredAbsoluteMediaURLs: Set<String>
	}

	static func rebase(
		template: Rv_Data_Template.Slide,
		resourceDirectory: URL?,
		themeDocumentPath: String,
		showRoot: URL?,
	) -> Result {
		guard let resourceDirectory else {
			let references = ThemeTemplateSource.mediaReferences(in: template)
			return Result(
				template: template,
				warnings: [],
				preferredAbsoluteMediaURLs: Set(references.compactMap { reference in
					guard let url = URL(string: reference.renderPath), url.isFileURL else { return nil }
					return reference.renderPath
				}),
			)
		}
		var result = template
		var warnings: [String] = []
		var preferredAbsoluteMediaURLs: Set<String> = []
		let themeDirectory = resourceDirectory
			.appendingPathComponent(themeDocumentPath)
			.deletingLastPathComponent()
		let roots = ResourceRoots(theme: themeDirectory, resource: resourceDirectory, show: showRoot)
		for index in result.baseSlide.elements.indices {
			var element = result.baseSlide.elements[index].element
			rebase(
				element: &element,
				roots: roots,
				warnings: &warnings,
				preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
			)
			result.baseSlide.elements[index].element = element
		}
		for index in result.actions.indices {
			rebase(
				action: &result.actions[index],
				roots: roots,
				warnings: &warnings,
				preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
			)
		}
		return Result(
			template: result,
			warnings: warnings,
			preferredAbsoluteMediaURLs: preferredAbsoluteMediaURLs,
		)
	}

	private static func rebase(
		action: inout Rv_Data_Action,
		roots: ResourceRoots,
		warnings: inout [String],
		preferredAbsoluteMediaURLs: inout Set<String>,
	) {
		switch action.type {
		case .media, .foregroundMedia, .backgroundMedia:
			var mediaType = action.media
			var media = mediaType.element
			rebase(
				media: &media,
				roots: roots,
				warnings: &warnings,
				preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
			)
			mediaType.element = media
			for markerIndex in mediaType.markers.indices {
				for actionIndex in mediaType.markers[markerIndex].actions.indices {
					rebase(
						action: &mediaType.markers[markerIndex].actions[actionIndex],
						roots: roots,
						warnings: &warnings,
						preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
					)
				}
			}
			action.media = mediaType
		case .presentationSlide, .propSlide:
			if case var .presentation(presentationSlide)? = action.slide.slide {
				rebase(
					slide: &presentationSlide.baseSlide,
					roots: roots,
					warnings: &warnings,
					preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
				)
				action.slide.presentation = presentationSlide
			} else if case var .prop(propSlide)? = action.slide.slide {
				rebase(
					slide: &propSlide.baseSlide,
					roots: roots,
					warnings: &warnings,
					preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
				)
				action.slide.prop = propSlide
			}
		default:
			break
		}
	}

	private static func rebase(
		slide: inout Rv_Data_Slide,
		roots: ResourceRoots,
		warnings: inout [String],
		preferredAbsoluteMediaURLs: inout Set<String>,
	) {
		for index in slide.elements.indices {
			var element = slide.elements[index].element
			rebase(
				element: &element,
				roots: roots,
				warnings: &warnings,
				preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
			)
			slide.elements[index].element = element
		}
	}

	private static func rebase(
		element: inout Rv_Data_Graphics.Element,
		roots: ResourceRoots,
		warnings: inout [String],
		preferredAbsoluteMediaURLs: inout Set<String>,
	) {
		if case var .media(media)? = element.fill.fillType {
			rebase(
				media: &media,
				roots: roots,
				warnings: &warnings,
				preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
			)
			element.fill.media = media
		}
		guard element.hasText else { return }
		var attributes = element.text.attributes
		if case var .mediaFill(fill)? = attributes.fill {
			var media = fill.media
			rebase(
				media: &media,
				roots: roots,
				warnings: &warnings,
				preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
			)
			fill.media = media
			attributes.mediaFill = fill
		}
		for index in attributes.customAttributes.indices {
			if case var .mediaFill(fill)? = attributes.customAttributes[index].attribute {
				var media = fill.media
				rebase(
					media: &media,
					roots: roots,
					warnings: &warnings,
					preferredAbsoluteMediaURLs: &preferredAbsoluteMediaURLs,
				)
				fill.media = media
				attributes.customAttributes[index].mediaFill = fill
			}
		}
		element.text.attributes = attributes
	}

	private static func rebase(
		media: inout Rv_Data_Media,
		roots: ResourceRoots,
		warnings: inout [String],
		preferredAbsoluteMediaURLs: inout Set<String>,
	) {
		let value = media.url.renderPath
		guard !value.isEmpty else { return }
		if hasUnsafeScopedPath(media.url) {
			warnings.append("Template media path \(value) escapes its declared resource root and was not resolved.")
			return
		}
		if let rooted = rootedURL(for: media.url, roots: roots),
		   FileManager.default.fileExists(atPath: rooted.path)
		{
			media.url.absoluteString = rooted.standardizedFileURL.absoluteString
			preferredAbsoluteMediaURLs.insert(media.url.absoluteString)
			return
		}
		if let absolute = URL(string: value), absolute.isFileURL,
		   FileManager.default.fileExists(atPath: absolute.path)
		{
			preferredAbsoluteMediaURLs.insert(value)
			return
		}
		let decoded = value.removingPercentEncoding ?? value
		if let normalized = normalizedScopedPath(decoded) {
			for root in roots.fallback {
				guard let candidate = containedURL(for: normalized, in: root) else { continue }
				media.url.absoluteString = candidate.standardizedFileURL.absoluteString
				preferredAbsoluteMediaURLs.insert(media.url.absoluteString)
				return
			}
		}
		let basename = URL(fileURLWithPath: decoded).lastPathComponent
		let matches = roots.fallback.flatMap { root in
			(try? DocumentLoader.recursiveFiles(in: root).filter { $0.lastPathComponent == basename }) ?? []
		}.reduce(into: [String: URL]()) { partial, url in
			partial[url.standardizedFileURL.path] = url
		}.values
		if matches.count == 1, let match = matches.first {
			media.url.absoluteString = match.standardizedFileURL.absoluteString
			preferredAbsoluteMediaURLs.insert(media.url.absoluteString)
		} else if matches.count > 1 {
			warnings.append("Template media path \(value) is ambiguous across the theme resource roots.")
		} else {
			warnings.append("Template media path \(value) could not be resolved relative to its theme document.")
		}
	}

	private static func rootedURL(for url: Rv_Data_URL, roots: ResourceRoots) -> URL? {
		if case let .local(local)? = url.relativeFilePath {
			guard let normalized = normalizedScopedPath(local.path) else { return nil }
			let fileManager = FileManager.default
			let root: URL? = switch local.root {
			case .bootVolume: URL(fileURLWithPath: "/", isDirectory: true)
			case .userHome: fileManager.homeDirectoryForCurrentUser
			case .userDocuments: fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
			case .userDownloads: fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
			case .userMusic: fileManager.urls(for: .musicDirectory, in: .userDomainMask).first
			case .userPictures: fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
			case .userVideos: fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
			case .userDesktop: fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
			case .userAppSupport: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			case .shared: URL(fileURLWithPath: "/Users/Shared", isDirectory: true)
			case .show: roots.show
			case .currentResource: roots.theme
			case .unknown, .UNRECOGNIZED: nil
			}
			guard let root else { return nil }
			return containedURL(for: normalized, in: root, requireExisting: false)
		}
		if case let .external(external)? = url.relativeFilePath,
		   !external.macos.volumeName.isEmpty
		{
			guard let normalized = normalizedScopedPath(external.path) else { return nil }
			let root = URL(fileURLWithPath: "/Volumes/\(external.macos.volumeName)", isDirectory: true)
			return containedURL(for: normalized, in: root, requireExisting: false)
		}
		if case let .relativePath(path)? = url.storage {
			guard let normalized = normalizedScopedPath(path) else { return nil }
			return [roots.theme, roots.resource]
				.compactMap { containedURL(for: normalized, in: $0) }
				.first
		}
		return nil
	}

	private static func hasUnsafeScopedPath(_ url: Rv_Data_URL) -> Bool {
		if case let .local(local)? = url.relativeFilePath {
			return normalizedScopedPath(local.path) == nil
		}
		if case let .external(external)? = url.relativeFilePath {
			return normalizedScopedPath(external.path) == nil
		}
		if case let .relativePath(path)? = url.storage {
			return normalizedScopedPath(path) == nil
		}
		return false
	}

	private static func normalizedScopedPath(_ value: String) -> String? {
		let decoded = value.removingPercentEncoding ?? value
		guard !decoded.contains("\\"),
		      !decoded.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
		else {
			return nil
		}
		let trimmed = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
		guard !components.isEmpty,
		      components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
		else {
			return nil
		}
		return components.joined(separator: "/")
	}

	private static func containedURL(
		for relativePath: String,
		in root: URL,
		requireExisting: Bool = true,
	) -> URL? {
		let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
		let candidate = root.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
		guard resolvedRoot.path == "/" || candidate.path.hasPrefix(resolvedRoot.path + "/") else {
			return nil
		}
		guard !requireExisting || FileManager.default.fileExists(atPath: candidate.path) else {
			return nil
		}
		return candidate
	}
}
