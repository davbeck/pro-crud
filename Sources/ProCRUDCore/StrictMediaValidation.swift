import AppKit
import Foundation
import ProPresenterProto

public enum StrictMediaDiagnosticKind: String, Sendable {
	case missingIdentity = "missing-identity"
	case missingAsset = "missing-asset"
	case invalidImage = "invalid-image"
	case inconsistentURL = "inconsistent-url"
	case imageDimensions = "image-dimensions"
	case conflictingUUID = "conflicting-uuid"
	case workspaceRegistryConflict = "workspace-registry-conflict"
	case labelMismatch = "label-mismatch"
}

public struct StrictMediaDiagnostic: CustomStringConvertible, Sendable {
	public var kind: StrictMediaDiagnosticKind
	public var documentPath: String?
	public var componentPath: String
	public var message: String

	public init(
		kind: StrictMediaDiagnosticKind,
		documentPath: String? = nil,
		componentPath: String,
		message: String,
	) {
		self.kind = kind
		self.documentPath = documentPath
		self.componentPath = componentPath
		self.message = message
	}

	public var description: String {
		let document = documentPath.map { " in \($0)" } ?? ""
		return "[\(kind.rawValue)]\(document) at \(componentPath): \(message)"
	}
}

public struct StrictMediaValidationReport: Sendable {
	public var diagnostics: [StrictMediaDiagnostic]

	public init(diagnostics: [StrictMediaDiagnostic]) {
		self.diagnostics = diagnostics
	}

	public var isValid: Bool {
		diagnostics.isEmpty
	}
}

/// Validates file-backed media identity as ProPresenter resolves it inside a
/// workspace. Unlike rendering diagnostics, strict validation checks both URL
/// representations and compares media UUIDs with the Media playlist registry.
public enum StrictMediaValidator {
	public static func validate(
		_ document: ProPresenterDocument,
		workspaceURL: URL,
		fileManager: FileManager = .default,
	) throws -> StrictMediaValidationReport {
		let documentReferences = references(in: document, scope: .document)
		let registryReferences = try workspaceRegistryReferences(
			workspaceURL: workspaceURL,
			fileManager: fileManager,
		)
		var diagnostics = documentReferences.flatMap {
			validate($0, workspaceURL: workspaceURL, fileManager: fileManager)
		}
		diagnostics.append(contentsOf: uuidDiagnostics(
			documentReferences: documentReferences,
			registryReferences: registryReferences,
			workspaceURL: workspaceURL,
		))
		return StrictMediaValidationReport(diagnostics: diagnostics.sorted(by: diagnosticOrder))
	}

	private enum Scope {
		case document
		case registry
	}

	private struct MediaReference {
		var media: Rv_Data_Media
		var documentPath: String?
		var componentPath: String
		var siblingLabel: String?
		var siblingLabelPath: String?
		var resourceDirectory: URL?
		var scope: Scope
	}

	private static func references(in document: ProPresenterDocument, scope: Scope) -> [MediaReference] {
		var result: [MediaReference] = []
		switch document.payload {
		case let .presentation(presentation):
			append(presentation: presentation, basePath: "", document: document, scope: scope, to: &result)
		case let .theme(theme):
			if document.themeEntries.isEmpty {
				append(theme: theme, basePath: "", document: document, scope: scope, to: &result)
			} else {
				for entry in document.themeEntries {
					append(
						theme: entry.document,
						basePath: "",
						documentPath: entry.relativePath,
						document: document,
						scope: scope,
						to: &result,
					)
				}
			}
		case let .playlist(playlist):
			append(
				playlist: playlist.rootNode,
				basePath: "/root_node",
				document: document,
				scope: scope,
				to: &result,
			)
		}
		return result
	}

	private static func append(
		presentation: Rv_Data_Presentation,
		basePath: String,
		documentPath: String? = nil,
		document: ProPresenterDocument,
		scope: Scope,
		to result: inout [MediaReference],
	) {
		let cueIdentities = presentation.cues.map(\.uuid.string)
		let cueOrder = presentation.presentationCueIndexOrder
		for cueIndex in cueOrder.storageIndices {
			let cue = presentation.cues[cueIndex]
			let cuePath = ComponentPathBuilder.repeatedPath(
				parent: basePath,
				field: "cues",
				storageIndex: cueIndex,
				identities: cueIdentities,
				order: cueOrder,
			)
			append(
				actions: cue.actions,
				parentPath: cuePath,
				documentPath: documentPath,
				document: document,
				scope: scope,
				to: &result,
			)
		}
	}

	private static func append(
		theme: Rv_Data_Template.Document,
		basePath: String,
		documentPath: String? = nil,
		document: ProPresenterDocument,
		scope: Scope,
		to result: inout [MediaReference],
	) {
		let slideIdentities = theme.slides.map(\.baseSlide.uuid.string)
		for (slideIndex, template) in theme.slides.enumerated() {
			let slidePath = ComponentPathBuilder.repeatedPath(
				parent: basePath,
				field: "slides",
				storageIndex: slideIndex,
				identities: slideIdentities,
			)
			append(
				slide: template.baseSlide,
				basePath: "\(slidePath)/base_slide",
				documentPath: documentPath,
				document: document,
				scope: scope,
				to: &result,
			)
			append(
				actions: template.actions,
				parentPath: slidePath,
				documentPath: documentPath,
				document: document,
				scope: scope,
				to: &result,
			)
		}
	}

	private static func append(
		playlist: Rv_Data_Playlist,
		basePath: String,
		documentPath: String? = nil,
		document: ProPresenterDocument,
		scope: Scope,
		to result: inout [MediaReference],
	) {
		let cueIdentities = playlist.cues.map(\.uuid.string)
		for (cueIndex, cue) in playlist.cues.enumerated() {
			let cuePath = ComponentPathBuilder.repeatedPath(
				parent: basePath,
				field: "cues",
				storageIndex: cueIndex,
				identities: cueIdentities,
			)
			append(
				actions: cue.actions,
				parentPath: cuePath,
				documentPath: documentPath,
				document: document,
				scope: scope,
				to: &result,
			)
		}
		let childIdentities = playlist.children.map(\.uuid.string)
		for (childIndex, child) in playlist.children.enumerated() {
			let childPath = ComponentPathBuilder.repeatedPath(
				parent: basePath,
				field: "children",
				storageIndex: childIndex,
				identities: childIdentities,
			)
			append(
				playlist: child,
				basePath: childPath,
				documentPath: documentPath,
				document: document,
				scope: scope,
				to: &result,
			)
		}
		switch playlist.childrenType {
		case let .items(items):
			let itemIdentities = items.items.map(\.uuid.string)
			for (itemIndex, item) in items.items.enumerated() {
				guard case .cue? = item.itemType else { continue }
				let itemPath = ComponentPathBuilder.repeatedPath(
					parent: "\(basePath)/items",
					field: "items",
					storageIndex: itemIndex,
					identities: itemIdentities,
				)
				append(
					actions: item.cue.actions,
					parentPath: "\(itemPath)/cue",
					documentPath: documentPath,
					document: document,
					scope: scope,
					to: &result,
				)
			}
		case let .playlists(playlists):
			let childIdentities = playlists.playlists.map(\.uuid.string)
			for (childIndex, child) in playlists.playlists.enumerated() {
				let childPath = ComponentPathBuilder.repeatedPath(
					parent: "\(basePath)/playlists",
					field: "playlists",
					storageIndex: childIndex,
					identities: childIdentities,
				)
				append(
					playlist: child,
					basePath: childPath,
					documentPath: documentPath,
					document: document,
					scope: scope,
					to: &result,
				)
			}
		case nil:
			break
		}
	}

	private static func append(
		actions: [Rv_Data_Action],
		parentPath: String,
		documentPath: String? = nil,
		document: ProPresenterDocument,
		scope: Scope,
		to result: inout [MediaReference],
	) {
		let actionIdentities = actions.map(\.uuid.string)
		let filenameLabels = actions.enumerated().compactMap { index, action -> (index: Int, text: String, path: String)? in
			guard isFilenameLike(action.label.text) else { return nil }
			let actionPath = ComponentPathBuilder.repeatedPath(
				parent: parentPath,
				field: "actions",
				storageIndex: index,
				identities: actionIdentities,
			)
			return (index, action.label.text, "\(actionPath)/label")
		}
		let mediaActionCount = actions.count(where: { $0.renderableMedia != nil })
		for (actionIndex, action) in actions.enumerated() {
			let actionPath = ComponentPathBuilder.repeatedPath(
				parent: parentPath,
				field: "actions",
				storageIndex: actionIndex,
				identities: actionIdentities,
			)
			if let media = action.renderableMedia {
				let filenameLabel = filenameLabel(
					for: media,
					mediaActionCount: mediaActionCount,
					filenameLabels: filenameLabels,
				)
				result.append(MediaReference(
					media: media,
					documentPath: documentPath,
					componentPath: "\(actionPath)/media/element",
					siblingLabel: filenameLabel?.text,
					siblingLabelPath: filenameLabel?.path,
					resourceDirectory: document.resourceDirectory,
					scope: scope,
				))
			}
			if let slide = action.presentationBaseSlide {
				append(
					slide: slide,
					basePath: "\(actionPath)/slide/presentation/base_slide",
					documentPath: documentPath,
					document: document,
					scope: scope,
					to: &result,
				)
			}
		}
	}

	private static func append(
		slide: Rv_Data_Slide,
		basePath: String,
		documentPath: String? = nil,
		document: ProPresenterDocument,
		scope: Scope,
		to result: inout [MediaReference],
	) {
		let elementIdentities = slide.elements.map(\.element.uuid.string)
		for (elementIndex, slideElement) in slide.elements.enumerated() {
			guard case let .media(media)? = slideElement.element.fill.fillType else { continue }
			let elementPath = ComponentPathBuilder.repeatedPath(
				parent: basePath,
				field: "elements",
				storageIndex: elementIndex,
				identities: elementIdentities,
			) + "/element"
			result.append(MediaReference(
				media: media,
				documentPath: documentPath,
				componentPath: "\(elementPath)/fill/media",
				siblingLabel: nil,
				siblingLabelPath: nil,
				resourceDirectory: document.resourceDirectory,
				scope: scope,
			))
		}
	}

	private static func workspaceRegistryReferences(
		workspaceURL: URL,
		fileManager: FileManager,
	) throws -> [MediaReference] {
		let registryURL = workspaceURL.appendingPathComponent("Playlists/Media")
		guard fileManager.fileExists(atPath: registryURL.path) else { return [] }
		let registry = try DocumentLoader.load(from: registryURL)
		return references(in: registry, scope: .registry)
	}

	private static func validate(
		_ reference: MediaReference,
		workspaceURL: URL,
		fileManager: FileManager,
	) -> [StrictMediaDiagnostic] {
		var diagnostics: [StrictMediaDiagnostic] = []
		let locations = mediaLocations(reference, workspaceURL: workspaceURL)
		if locations.representsFile,
		   reference.media.uuid.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		{
			diagnostics.append(StrictMediaDiagnostic(
				kind: .missingIdentity,
				documentPath: reference.documentPath,
				componentPath: "\(reference.componentPath)/uuid",
				message: "File-backed media has no UUID and therefore has no stable media identity.",
			))
		}
		if let absolute = locations.absolute, let local = locations.local, absolute != local {
			diagnostics.append(StrictMediaDiagnostic(
				kind: .inconsistentURL,
				documentPath: reference.documentPath,
				componentPath: "\(reference.componentPath)/url",
				message: "Absolute URL resolves to \(absolute.path), but the local URL resolves to \(local.path).",
			))
		}

		let candidates = locations.candidates
		let existing = candidates.filter { fileManager.fileExists(atPath: $0.path) }
		let resolved = existing.first { isRegularFile($0) }
		if resolved == nil, locations.representsFile {
			let declared = candidates.map(\.path).joined(separator: ", ")
			let message = if let nonRegular = existing.first {
				"Media path exists but is not a regular file: \(nonRegular.path)."
			} else if declared.isEmpty {
				"Media has no resolvable file path."
			} else {
				"Media asset was not found at \(declared)."
			}
			diagnostics.append(StrictMediaDiagnostic(
				kind: .missingAsset,
				documentPath: reference.documentPath,
				componentPath: "\(reference.componentPath)/url",
				message: message,
			))
		}

		if case .image? = reference.media.typeProperties, let resolved {
			if let actualSize = imagePixelSize(at: resolved) {
				let stored = reference.media.image.drawing.naturalSize
				if abs(stored.width - actualSize.width) > 0.5 || abs(stored.height - actualSize.height) > 0.5 {
					diagnostics.append(StrictMediaDiagnostic(
						kind: .imageDimensions,
						documentPath: reference.documentPath,
						componentPath: reference.componentPath,
						message: "Stored image dimensions are \(dimension(stored.width))×\(dimension(stored.height)); the asset is \(dimension(actualSize.width))×\(dimension(actualSize.height)).",
					))
				}
			} else {
				diagnostics.append(StrictMediaDiagnostic(
					kind: .invalidImage,
					documentPath: reference.documentPath,
					componentPath: reference.componentPath,
					message: "Image asset is unreadable or does not contain a valid image: \(resolved.path).",
				))
			}
		}

		if let label = reference.siblingLabel,
		   isFilenameLike(label),
		   let mediaFilename = mediaFilename(reference.media.url),
		   label.removingPercentEncoding?.lastPathComponent.caseInsensitiveCompare(mediaFilename) != .orderedSame
		{
			diagnostics.append(StrictMediaDiagnostic(
				kind: .labelMismatch,
				documentPath: reference.documentPath,
				componentPath: reference.siblingLabelPath ?? reference.componentPath,
				message: "Filename label \(label) disagrees with media asset \(mediaFilename).",
			))
		}
		return diagnostics
	}

	private struct MediaLocations {
		var absolute: URL?
		var local: URL?
		var storageRelative: URL?
		var representsFile: Bool

		var candidates: [URL] {
			var seen = Set<String>()
			return [local, storageRelative, absolute].compactMap { value in
				guard let value, seen.insert(value.path).inserted else { return nil }
				return value
			}
		}
	}

	private static func mediaLocations(_ reference: MediaReference, workspaceURL: URL) -> MediaLocations {
		let mediaURL = reference.media.url
		let absolute: URL?
		let storageRelative: URL?
		var representsFile = true
		switch mediaURL.storage {
		case let .absoluteString(value):
			absolute = fileURL(from: value)
			storageRelative = nil
			if let parsed = URL(string: value), parsed.scheme != nil, !parsed.isFileURL {
				representsFile = false
			}
		case let .relativePath(path):
			absolute = nil
			storageRelative = reference.resourceDirectory.map { appending(path, to: $0) }
		case nil:
			absolute = nil
			storageRelative = nil
			representsFile = reference.media.typeProperties.map {
				if case .liveVideo = $0 {
					return false
				}
				if case .webContent = $0 {
					return false
				}
				return true
			} ?? false
		}

		let local: URL? = switch mediaURL.relativeFilePath {
		case let .local(value): localURL(value, workspaceURL: workspaceURL, resourceDirectory: reference.resourceDirectory)
		case let .external(value): externalURL(value)
		case nil: nil
		}
		if local != nil {
			representsFile = true
		}
		return MediaLocations(
			absolute: absolute?.standardizedFileURL,
			local: local?.standardizedFileURL,
			storageRelative: storageRelative?.standardizedFileURL,
			representsFile: representsFile,
		)
	}

	private static func localURL(
		_ local: Rv_Data_URL.LocalRelativePath,
		workspaceURL: URL,
		resourceDirectory: URL?,
	) -> URL? {
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
		case .show: workspaceURL
		case .currentResource: resourceDirectory
		case .unknown, .UNRECOGNIZED: nil
		}
		return root.map { appending(local.path, to: $0) }
	}

	private static func externalURL(_ external: Rv_Data_URL.ExternalRelativePath) -> URL? {
		guard !external.macos.volumeName.isEmpty else { return nil }
		return appending(
			external.path,
			to: URL(fileURLWithPath: "/Volumes/\(external.macos.volumeName)", isDirectory: true),
		)
	}

	private static func fileURL(from value: String) -> URL? {
		if let url = URL(string: value), url.isFileURL {
			return url
		}
		let decoded = value.removingPercentEncoding ?? value
		if decoded.hasPrefix("file://") {
			return URL(fileURLWithPath: String(decoded.dropFirst("file://".count)))
		}
		if decoded.hasPrefix("/") {
			return URL(fileURLWithPath: decoded)
		}
		return nil
	}

	private static func appending(_ path: String, to root: URL) -> URL {
		root.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
	}

	private static func imagePixelSize(at url: URL) -> CGSize? {
		guard let image = NSImage(contentsOf: url),
		      let representation = image.representations.max(by: {
		      	$0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
		      }),
		      representation.pixelsWide > 0,
		      representation.pixelsHigh > 0
		else { return nil }
		return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
	}

	private static func isRegularFile(_ url: URL) -> Bool {
		(try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
	}

	private static func filenameLabel(
		for media: Rv_Data_Media,
		mediaActionCount: Int,
		filenameLabels: [(index: Int, text: String, path: String)],
	) -> (index: Int, text: String, path: String)? {
		if let filename = mediaFilename(media.url),
		   let exact = filenameLabels.first(where: {
		   	($0.text.removingPercentEncoding ?? $0.text).lastPathComponent.caseInsensitiveCompare(filename) == .orderedSame
		   })
		{
			return exact
		}
		guard mediaActionCount == 1, filenameLabels.count == 1 else { return nil }
		return filenameLabels[0]
	}

	private static func uuidDiagnostics(
		documentReferences: [MediaReference],
		registryReferences: [MediaReference],
		workspaceURL: URL,
	) -> [StrictMediaDiagnostic] {
		var diagnostics: [StrictMediaDiagnostic] = []
		let documentByUUID = Dictionary(grouping: documentReferences.filter { !$0.media.uuid.string.isEmpty }) {
			$0.media.uuid.string
		}
		let registryByUUID = Dictionary(grouping: registryReferences.filter { !$0.media.uuid.string.isEmpty }) {
			$0.media.uuid.string
		}

		for (uuid, references) in documentByUUID {
			let identities = identityPaths(references, workspaceURL: workspaceURL)
			if identities.count > 1 {
				diagnostics.append(conflictDiagnostic(
					kind: .conflictingUUID,
					uuid: uuid,
					references: references,
					identities: identities,
				))
			}
			guard let registry = registryByUUID[uuid] else { continue }
			let registryIdentities = identityPaths(registry, workspaceURL: workspaceURL)
			for reference in references {
				let referenceIdentities = identityPaths([reference], workspaceURL: workspaceURL)
				if !referenceIdentities.isEmpty,
				   !registryIdentities.isEmpty,
				   referenceIdentities.isDisjoint(with: registryIdentities)
				{
					diagnostics.append(StrictMediaDiagnostic(
						kind: .workspaceRegistryConflict,
						documentPath: reference.documentPath,
						componentPath: reference.componentPath,
						message: "Media UUID \(uuid) identifies \(referenceIdentities.sorted().joined(separator: ", ")) in the document but \(registryIdentities.sorted().joined(separator: ", ")) in Playlists/Media.",
					))
				}
			}
		}

		for (uuid, references) in registryByUUID {
			let identities = identityPaths(references, workspaceURL: workspaceURL)
			if identities.count > 1 {
				diagnostics.append(conflictDiagnostic(
					kind: .conflictingUUID,
					uuid: uuid,
					references: references,
					identities: identities,
				))
			}
		}

		let registryByIdentity = Dictionary(grouping: registryReferences.compactMap { reference -> (String, MediaReference)? in
			guard !reference.media.uuid.string.isEmpty,
			      let identity = identityPaths([reference], workspaceURL: workspaceURL).first
			else { return nil }
			return (identity, reference)
		}, by: \.0)
		for reference in documentReferences where !reference.media.uuid.string.isEmpty {
			guard let identity = identityPaths([reference], workspaceURL: workspaceURL).first,
			      let canonical = registryByIdentity[identity]
			else { continue }
			let canonicalUUIDs = Set(canonical.map(\.1.media.uuid.string))
			guard !canonicalUUIDs.contains(reference.media.uuid.string) else { continue }
			diagnostics.append(StrictMediaDiagnostic(
				kind: .workspaceRegistryConflict,
				documentPath: reference.documentPath,
				componentPath: reference.componentPath,
				message: "Media asset \(identity) is registered in Playlists/Media as UUID \(canonicalUUIDs.sorted().joined(separator: ", ")), but the document uses UUID \(reference.media.uuid.string).",
			))
		}
		return diagnostics
	}

	private static func identityPaths(_ references: [MediaReference], workspaceURL: URL) -> Set<String> {
		Set(references.compactMap { reference in
			let locations = mediaLocations(reference, workspaceURL: workspaceURL)
			return (locations.local ?? locations.storageRelative ?? locations.absolute)?.path
		})
	}

	private static func conflictDiagnostic(
		kind: StrictMediaDiagnosticKind,
		uuid: String,
		references: [MediaReference],
		identities: Set<String>,
	) -> StrictMediaDiagnostic {
		StrictMediaDiagnostic(
			kind: kind,
			documentPath: references[0].documentPath,
			componentPath: references[0].componentPath,
			message: "Media UUID \(uuid) refers to conflicting assets \(identities.sorted().joined(separator: ", ")). References: \(references.map(qualifiedPath).joined(separator: ", ")).",
		)
	}

	private static func qualifiedPath(_ reference: MediaReference) -> String {
		guard let documentPath = reference.documentPath else { return reference.componentPath }
		return "\(documentPath):\(reference.componentPath)"
	}

	private static func mediaFilename(_ url: Rv_Data_URL) -> String? {
		let value: String? = switch url.relativeFilePath {
		case let .local(local): local.path
		case let .external(external): external.path
		case nil:
			switch url.storage {
			case let .absoluteString(absolute): fileURL(from: absolute)?.lastPathComponent
			case let .relativePath(relative): relative
			case nil: nil
			}
		}
		guard let value else { return nil }
		return (value.removingPercentEncoding ?? value).lastPathComponent
	}

	private static func isFilenameLike(_ value: String) -> Bool {
		let mediaExtensions: Set = [
			"aac", "aif", "aiff", "bmp", "gif", "heic", "jpeg", "jpg", "m4a", "m4v", "mov", "mp3", "mp4",
			"png", "tif", "tiff", "wav", "webm", "webp",
		]
		return mediaExtensions.contains(URL(fileURLWithPath: value).pathExtension.lowercased())
	}

	private static func dimension(_ value: Double) -> String {
		value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
	}

	private static func diagnosticOrder(_ lhs: StrictMediaDiagnostic, _ rhs: StrictMediaDiagnostic) -> Bool {
		if lhs.documentPath != rhs.documentPath {
			return (lhs.documentPath ?? "").localizedStandardCompare(rhs.documentPath ?? "") == .orderedAscending
		}
		if lhs.componentPath == rhs.componentPath {
			return lhs.kind.rawValue < rhs.kind.rawValue
		}
		return lhs.componentPath.localizedStandardCompare(rhs.componentPath) == .orderedAscending
	}
}

private extension String {
	var lastPathComponent: String {
		URL(fileURLWithPath: self).lastPathComponent
	}
}
