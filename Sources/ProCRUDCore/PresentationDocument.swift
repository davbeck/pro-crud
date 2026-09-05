import Foundation
import ProPresenterProto
import SwiftProtobuf

public enum ArrangementSelection: Sendable, Equatable {
	case native
	case selected
	case uuid(String)
}

public struct ResolvedPresentationArrangement: Sendable, Equatable {
	public var index: Int
	public var path: String
	public var uuid: String
	public var name: String
	public var groupStorageIndices: [Int]
	public var cueStorageIndices: [Int]
}

public struct PresentationCueOccurrence: Sendable {
	public var sequenceIndex: Int
	public var cueStorageIndex: Int
	public var arrangementGroupOccurrenceIndex: Int?
	public var groupUUID: String?
	public var cue: Rv_Data_Cue
}

public enum PresentationArrangementError: Error, CustomStringConvertible, Sendable {
	case noSelectedArrangement
	case arrangementNotFound(uuid: String, candidates: [String])
	case ambiguousArrangementUUID(uuid: String, candidates: [String])
	case unknownGroupReference(arrangement: String, occurrence: Int, uuid: String)
	case ambiguousGroupReference(arrangement: String, occurrence: Int, uuid: String)
	case unknownCueReference(group: String, uuid: String)
	case ambiguousCueReference(group: String, uuid: String)

	public var description: String {
		switch self {
		case .noSelectedArrangement:
			"The presentation has no selected arrangement."
		case let .arrangementNotFound(uuid, candidates):
			"No arrangement has UUID \(uuid). Candidates: \(candidates.joined(separator: ", "))"
		case let .ambiguousArrangementUUID(uuid, candidates):
			"Arrangement UUID \(uuid) is not unique. Candidates: \(candidates.joined(separator: ", "))"
		case let .unknownGroupReference(arrangement, occurrence, uuid):
			"Arrangement \(arrangement) references unknown cue-group UUID \(uuid) at sequence position \(occurrence + 1)."
		case let .ambiguousGroupReference(arrangement, occurrence, uuid):
			"Arrangement \(arrangement) references non-unique cue-group UUID \(uuid) at sequence position \(occurrence + 1)."
		case let .unknownCueReference(group, uuid):
			"Cue group \(group) references unknown cue UUID \(uuid)."
		case let .ambiguousCueReference(group, uuid):
			"Cue group \(group) references non-unique cue UUID \(uuid)."
		}
	}
}

public struct PresentationDocument: Sendable {
	public var presentation: Rv_Data_Presentation
	public var mediaDirectory: URL?
	public var embeddedMediaFiles: [String]?
	/// A render-only selection supplied by a playlist item or caller. When nil,
	/// rendering uses the presentation's stored selection, then Master when no
	/// arrangement is selected.
	public var arrangementSelection: ArrangementSelection?
	var temporaryResourceOwners: [TemporaryDirectoryOwner]
	/// Media identities introduced from a separately loaded resource, such as a
	/// Theme. Their exact URLs must win over a same-named asset beside the source
	/// presentation, while ordinary document media retains archive-local precedence.
	public var preferredMediaReferences: Set<ThemeTemplateSource.MediaReference>

	public init(
		presentation: Rv_Data_Presentation,
		mediaDirectory: URL? = nil,
		embeddedMediaFiles: [String]? = nil,
		preferredMediaReferences: Set<ThemeTemplateSource.MediaReference> = [],
		arrangementSelection: ArrangementSelection? = nil,
	) {
		self.presentation = presentation
		self.mediaDirectory = mediaDirectory
		self.embeddedMediaFiles = embeddedMediaFiles
		temporaryResourceOwners = []
		self.preferredMediaReferences = preferredMediaReferences
		self.arrangementSelection = arrangementSelection
	}

	public var orderedCues: [Rv_Data_Cue] {
		presentation.presentationOrderCueIndices.map { presentation.cues[$0] }
	}

	public func resolvedArrangement() throws -> ResolvedPresentationArrangement? {
		let selection: ArrangementSelection
		if let arrangementSelection {
			selection = arrangementSelection
		} else if presentation.hasSelectedArrangement, !presentation.selectedArrangement.string.isEmpty {
			selection = .uuid(presentation.selectedArrangement.string)
		} else {
			selection = .native
		}

		let resolvedArrangementIndex: Int
		switch selection {
		case .native:
			return nil
		case .selected:
			guard presentation.hasSelectedArrangement, !presentation.selectedArrangement.string.isEmpty else {
				throw PresentationArrangementError.noSelectedArrangement
			}
			resolvedArrangementIndex = try arrangementIndex(uuid: presentation.selectedArrangement.string)
		case let .uuid(uuid):
			resolvedArrangementIndex = try arrangementIndex(uuid: uuid)
		}

		let arrangement = presentation.arrangements[resolvedArrangementIndex]
		let groupIndicesByUUID = Dictionary(grouping: presentation.cueGroups.indices, by: {
			presentation.cueGroups[$0].group.uuid.string
		})
		let cueIndicesByUUID = Dictionary(grouping: presentation.cues.indices, by: {
			presentation.cues[$0].uuid.string
		})
		var groupStorageIndices: [Int] = []
		var cueStorageIndices: [Int] = []

		for (occurrence, identifier) in arrangement.groupIdentifiers.enumerated() {
			let uuid = identifier.string
			guard let matchingGroups = groupIndicesByUUID[uuid], !matchingGroups.isEmpty else {
				throw PresentationArrangementError.unknownGroupReference(
					arrangement: arrangement.name,
					occurrence: occurrence,
					uuid: uuid,
				)
			}
			guard matchingGroups.count == 1, let groupIndex = matchingGroups.first else {
				throw PresentationArrangementError.ambiguousGroupReference(
					arrangement: arrangement.name,
					occurrence: occurrence,
					uuid: uuid,
				)
			}
			groupStorageIndices.append(groupIndex)

			let group = presentation.cueGroups[groupIndex]
			for cueIdentifier in group.cueIdentifiers {
				let cueUUID = cueIdentifier.string
				guard let matchingCues = cueIndicesByUUID[cueUUID], !matchingCues.isEmpty else {
					throw PresentationArrangementError.unknownCueReference(group: group.group.name, uuid: cueUUID)
				}
				guard matchingCues.count == 1, let cueIndex = matchingCues.first else {
					throw PresentationArrangementError.ambiguousCueReference(group: group.group.name, uuid: cueUUID)
				}
				cueStorageIndices.append(cueIndex)
			}
		}

		return ResolvedPresentationArrangement(
			index: resolvedArrangementIndex,
			path: ComponentPathBuilder.repeatedPath(
				field: "arrangements",
				storageIndex: resolvedArrangementIndex,
				identities: presentation.arrangements.map(\.uuid.string),
			),
			uuid: arrangement.uuid.string,
			name: arrangement.name,
			groupStorageIndices: groupStorageIndices,
			cueStorageIndices: cueStorageIndices,
		)
	}

	public func cueOccurrences() throws -> [PresentationCueOccurrence] {
		guard let arrangement = try resolvedArrangement() else {
			let cueIndicesByUUID = Dictionary(grouping: presentation.cues.indices, by: {
				presentation.cues[$0].uuid.string
			})
			var firstGroupUUIDByCueStorageIndex: [Int: String] = [:]
			for group in presentation.cueGroups {
				for identifier in group.cueIdentifiers {
					guard let indices = cueIndicesByUUID[identifier.string], indices.count == 1, let storageIndex = indices.first else {
						continue
					}
					if firstGroupUUIDByCueStorageIndex[storageIndex] == nil {
						firstGroupUUIDByCueStorageIndex[storageIndex] = group.group.uuid.string
					}
				}
			}
			return presentation.presentationOrderCueIndices.enumerated().map { sequenceIndex, storageIndex in
				PresentationCueOccurrence(
					sequenceIndex: sequenceIndex,
					cueStorageIndex: storageIndex,
					arrangementGroupOccurrenceIndex: nil,
					groupUUID: firstGroupUUIDByCueStorageIndex[storageIndex],
					cue: presentation.cues[storageIndex],
				)
			}
		}

		var result: [PresentationCueOccurrence] = []
		var cueOffset = 0
		for (groupOccurrenceIndex, groupStorageIndex) in arrangement.groupStorageIndices.enumerated() {
			let group = presentation.cueGroups[groupStorageIndex]
			let cueCount = group.cueIdentifiers.count
			for offset in 0 ..< cueCount {
				let cueStorageIndex = arrangement.cueStorageIndices[cueOffset + offset]
				result.append(PresentationCueOccurrence(
					sequenceIndex: result.count,
					cueStorageIndex: cueStorageIndex,
					arrangementGroupOccurrenceIndex: groupOccurrenceIndex,
					groupUUID: group.group.uuid.string,
					cue: presentation.cues[cueStorageIndex],
				))
			}
			cueOffset += cueCount
		}
		return result
	}

	public func nativeCueIndices(forRenderedSlideIndices slideIndices: Set<Int>?) throws -> Set<Int>? {
		guard try resolvedArrangement() != nil else { return slideIndices }
		let occurrences = try cueOccurrences()
		let selectedIndices = slideIndices ?? Set(occurrences.indices)
		let nativeIndexByStorageIndex = Dictionary(uniqueKeysWithValues:
			presentation.presentationOrderCueIndices.enumerated().map { ($0.element, $0.offset) })
		return Set(selectedIndices.compactMap { index in
			guard occurrences.indices.contains(index) else { return nil }
			return nativeIndexByStorageIndex[occurrences[index].cueStorageIndex]
		})
	}

	private func arrangementIndex(uuid: String) throws -> Int {
		let matches = presentation.arrangements.indices.filter { presentation.arrangements[$0].uuid.string == uuid }
		let candidates = presentation.arrangements.indices.map { index in
			let arrangement = presentation.arrangements[index]
			return "\(arrangement.name) (\(arrangement.uuid.string))"
		}
		guard !matches.isEmpty else {
			throw PresentationArrangementError.arrangementNotFound(uuid: uuid, candidates: candidates)
		}
		guard matches.count == 1, let index = matches.first else {
			throw PresentationArrangementError.ambiguousArrangementUUID(uuid: uuid, candidates: candidates)
		}
		return index
	}

	public var summary: PresentationSummary {
		var actionCounts: [String: Int] = [:]
		var mediaReferences: [String] = []
		var textElementCount = 0

		for cue in presentation.cues {
			for action in cue.actions {
				actionCounts[String(describing: action.type), default: 0] += 1
				if let media = action.renderableMedia {
					mediaReferences.append(media.url.renderPath)
				}
				if let slide = action.presentationBaseSlide {
					textElementCount += slide.elements.count(where: { $0.element.hasText && !$0.element.text.rtfData.isEmpty })
					for element in slide.elements {
						if case let .media(media)? = element.element.fill.fillType {
							mediaReferences.append(media.url.renderPath)
						}
					}
				}
			}
		}

		return PresentationSummary(
			name: presentation.name,
			uuid: presentation.uuid.string,
			cueCount: presentation.cues.count,
			orderedCueCount: orderedCues.count,
			actionCounts: actionCounts,
			mediaReferences: Array(Set(mediaReferences)).sorted(),
			textElementCount: textElementCount,
			cues: orderedCues.map { cue in
				PresentationCueSummary(
					name: cue.name,
					uuid: cue.uuid.string,
					text: cue.actions.compactMap(\.presentationBaseSlide).flatMap { slide in
						slide.elements.compactMap { element in
							guard element.element.hasText, !element.element.text.rtfData.isEmpty else { return nil }
							return NSAttributedString.plainText(fromRTF: element.element.text.rtfData)
						}
					},
				)
			},
		)
	}
}

extension Rv_Data_Presentation {
	/// Raw `cues` indices arranged in the presentation's native document order.
	/// Cue groups own that order; ungrouped cues follow in their stored order so
	/// every persisted cue remains addressable. Playlist arrangements are a
	/// downstream concern and do not change document component-path indices.
	var presentationOrderCueIndices: [Int] {
		presentationCueIndexOrder.storageIndices
	}

	var presentationCueIndexOrder: ComponentIndexOrder {
		var indicesByID: [String: [Int]] = [:]
		for index in cues.indices {
			indicesByID[cues[index].uuid.string, default: []].append(index)
		}
		var nextIndexByID: [String: Int] = [:]
		var seen = Set<Int>()
		var ordered: [Int] = []

		for group in cueGroups {
			for identifier in group.cueIdentifiers {
				let identity = identifier.string
				guard let indices = indicesByID[identity] else { continue }
				var offset = nextIndexByID[identity, default: 0]
				while indices.indices.contains(offset), seen.contains(indices[offset]) {
					offset += 1
				}
				guard indices.indices.contains(offset) else { continue }
				let index = indices[offset]
				nextIndexByID[identity] = offset + 1
				guard seen.insert(index).inserted else { continue }
				ordered.append(index)
			}
		}

		return ComponentIndexOrder(storageCount: cues.count, effectiveStorageIndices: ordered)
	}

	func componentPath(forCueAtStorageIndex storageIndex: Int) -> String {
		ComponentPathBuilder.repeatedPath(
			field: "cues",
			storageIndex: storageIndex,
			identities: cues.map(\.uuid.string),
			order: presentationCueIndexOrder,
		)
	}
}

public struct PresentationSummary: Sendable {
	public var name: String
	public var uuid: String
	public var cueCount: Int
	public var orderedCueCount: Int
	public var actionCounts: [String: Int]
	public var mediaReferences: [String]
	public var textElementCount: Int
	public var cues: [PresentationCueSummary]
}

public struct PresentationCueSummary: Sendable {
	public var name: String
	public var uuid: String
	public var text: [String]
}

public struct LoadedPresentationDocument: Sendable {
	public var sourceName: String
	public var document: PresentationDocument
	public var usesOutputSubdirectory: Bool

	public init(sourceName: String, document: PresentationDocument, usesOutputSubdirectory: Bool = false) {
		self.sourceName = sourceName
		self.document = document
		self.usesOutputSubdirectory = usesOutputSubdirectory
	}
}

public enum PresentationLoader {
	public static func load(from url: URL) throws -> PresentationDocument {
		let loaded = try DocumentLoader.load(from: url)
		guard case let .presentation(presentation) = loaded.payload else {
			throw DocumentLoadError.invalidPayload(
				expected: DocumentKind.presentation.rawValue,
				location: url.path,
				underlying: "input is a \(loaded.kind.rawValue) document",
			)
		}
		var result = PresentationDocument(
			presentation: presentation,
			mediaDirectory: loaded.resourceDirectory,
			embeddedMediaFiles: loaded.archiveEntries.isEmpty ? nil : loaded.embeddedAssetPaths,
		)
		result.temporaryResourceOwners = [loaded.temporaryResourceOwner].compactMap(\.self)
		return result
	}

	public static func loadPresentations(from url: URL) throws -> [LoadedPresentationDocument] {
		let loaded = try DocumentLoader.load(from: url)
		if case let .playlist(playlist) = loaded.payload {
			guard let resourceDirectory = loaded.resourceDirectory else {
				throw DocumentLoadError.missingPayload(kind: .playlist, location: url)
			}
			let items = presentationItems(in: playlist.rootNode)
			guard !items.isEmpty else {
				throw DocumentLoadError.missingPayload(kind: .presentation, location: url)
			}
			return try items.map { item in
				let presentationURL = try resolvePresentation(item.presentation.documentPath, in: resourceDirectory)
				let presentation = try DocumentLoader.loadRaw(presentationURL, kind: .presentation)
				guard case let .presentation(message) = presentation.payload else { fatalError("Document kind mismatch") }
				let itemName = item.name.isEmpty ? presentationURL.deletingPathExtension().lastPathComponent : item.name
				var document = PresentationDocument(
					presentation: message,
					mediaDirectory: resourceDirectory,
					arrangementSelection: item.presentation.hasArrangement && !item.presentation.arrangement.string.isEmpty
						? .uuid(item.presentation.arrangement.string)
						: nil,
				)
				document.temporaryResourceOwners = [loaded.temporaryResourceOwner].compactMap(\.self)
				return LoadedPresentationDocument(
					sourceName: safeDirectoryName(itemName),
					document: document,
					usesOutputSubdirectory: true,
				)
			}
		}

		if case let .theme(theme) = loaded.payload {
			let entries: [(name: String, document: Rv_Data_Template.Document)]
			if loaded.themeEntries.isEmpty {
				let fallbackName = url.pathExtension.lowercased() == "protheme"
					? url.deletingPathExtension().lastPathComponent
					: url.deletingLastPathComponent().lastPathComponent
				entries = [(fallbackName.isEmpty ? "Theme" : fallbackName, theme)]
			} else {
				entries = loaded.themeEntries.map { entry in
					let parent = URL(fileURLWithPath: entry.relativePath).deletingLastPathComponent().lastPathComponent
					let fallback = url.deletingPathExtension().lastPathComponent
					return (parent.isEmpty ? fallback : parent, entry.document)
				}
			}
			let usesSubdirectory = entries.count > 1
			return try entries.map { entry in
				try LoadedPresentationDocument(
					sourceName: safeDirectoryName(entry.name),
					document: presentationDocument(from: entry.document, name: entry.name, loaded: loaded, source: url),
					usesOutputSubdirectory: usesSubdirectory,
				)
			}
		}

		return try [
			LoadedPresentationDocument(
				sourceName: url.deletingPathExtension().lastPathComponent,
				document: load(from: url),
			),
		]
	}

	private static func presentationDocument(
		from theme: Rv_Data_Template.Document,
		name: String,
		loaded: ProPresenterDocument,
		source: URL,
	) throws -> PresentationDocument {
		guard !theme.slides.isEmpty else {
			throw DocumentLoadError.missingPayload(kind: .presentation, location: source)
		}

		var presentation = DocumentFactory.presentation(name: name)
		presentation.cues = []
		presentation.cueGroups[0].cueIdentifiers = []
		for template in theme.slides {
			let cueID = DocumentFactory.uuid()
			var slideAction = Rv_Data_Action()
			slideAction.uuid = DocumentFactory.uuid()
			slideAction.label.text = template.name
			slideAction.type = .presentationSlide
			slideAction.isEnabled = true
			var presentationSlide = Rv_Data_PresentationSlide()
			presentationSlide.baseSlide = template.baseSlide
			slideAction.slide.presentation = presentationSlide

			var cue = Rv_Data_Cue()
			cue.uuid = cueID
			cue.name = template.name
			cue.isEnabled = true
			cue.completionActionType = .last
			cue.actions = [slideAction] + template.actions
			presentation.cues.append(cue)
			presentation.cueGroups[0].cueIdentifiers.append(cueID)
		}
		var result = PresentationDocument(
			presentation: presentation,
			mediaDirectory: loaded.resourceDirectory,
			embeddedMediaFiles: loaded.archiveEntries.isEmpty ? nil : loaded.embeddedAssetPaths,
		)
		result.temporaryResourceOwners = [loaded.temporaryResourceOwner].compactMap(\.self)
		return result
	}

	private struct PresentationPlaylistItem {
		var name: String
		var presentation: Rv_Data_PlaylistItem.Presentation
	}

	private static func presentationItems(in playlist: Rv_Data_Playlist) -> [PresentationPlaylistItem] {
		var result: [PresentationPlaylistItem] = []
		switch playlist.childrenType {
		case let .items(items):
			result.append(contentsOf: items.items.compactMap { item in
				let resolved = EffectivePlaylistItem(item)
				guard !resolved.isHidden,
				      let content = resolved.content,
				      case let .presentation(presentation)? = content.itemType
				else { return nil }
				return PresentationPlaylistItem(
					name: item.name.isEmpty ? content.name : item.name,
					presentation: presentation,
				)
			})
		case let .playlists(playlists):
			for child in playlists.playlists {
				result.append(contentsOf: presentationItems(in: child))
			}
		case nil:
			break
		}
		for child in playlist.children {
			result.append(contentsOf: presentationItems(in: child))
		}
		return result
	}

	private static func resolvePresentation(_ documentPath: Rv_Data_URL, in directory: URL) throws -> URL {
		if case let .relativePath(path)? = documentPath.storage {
			let candidate = directory.appendingPathComponent(path)
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}

		let basename: String
		if case let .absoluteString(value)? = documentPath.storage, let url = URL(string: value), url.isFileURL {
			basename = url.lastPathComponent
		} else {
			basename = URL(fileURLWithPath: documentPath.renderPath).lastPathComponent
		}
		let archiveMatches = try DocumentLoader.recursiveFiles(in: directory).filter {
			$0.pathExtension.lowercased() == "pro" && $0.lastPathComponent == basename
		}
		if archiveMatches.count == 1, let match = archiveMatches.first {
			return match
		}
		if archiveMatches.count > 1 {
			throw DocumentLoadError.ambiguousPayload(kind: .presentation, candidates: archiveMatches.map(\.path))
		}

		if case let .absoluteString(value)? = documentPath.storage,
		   let candidate = URL(string: value),
		   candidate.isFileURL,
		   FileManager.default.fileExists(atPath: candidate.path)
		{
			return candidate
		}
		throw DocumentLoadError.missingPayload(kind: .presentation, location: directory.appendingPathComponent(basename))
	}

	private static func safeDirectoryName(_ value: String) -> String {
		value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
	}
}

extension Rv_Data_Action {
	var presentationBaseSlide: Rv_Data_Slide? {
		guard type == .presentationSlide else { return nil }
		guard case let .presentation(slide)? = slide.slide else { return nil }
		return slide.baseSlide
	}

	var renderableMedia: Rv_Data_Media? {
		switch type {
		case .media, .foregroundMedia, .backgroundMedia:
			return media.element
		default:
			return nil
		}
	}
}

extension Rv_Data_URL {
	var renderPath: String {
		if case let .absoluteString(value)? = storage {
			return value
		}
		if case let .relativePath(value)? = storage {
			return value
		}
		if case let .local(value)? = relativeFilePath {
			return value.path
		}
		if case let .external(value)? = relativeFilePath {
			return value.path
		}
		return ""
	}
}

private extension NSAttributedString {
	static func plainText(fromRTF data: Data) -> String? {
		guard let attributedString = try? NSAttributedString(
			data: data,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		) else {
			return nil
		}

		let text = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
		return text.isEmpty ? nil : text
	}
}
