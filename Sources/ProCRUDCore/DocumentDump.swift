import AppKit
import Foundation
import ProPresenterProto

public struct DocumentDumpReport: Codable, Sendable {
	public var kind: String
	public var source: Source
	public var archive: Archive
	public var media: [Media]
	public var presentation: Presentation?
	public var theme: Theme?
	public var playlist: PlaylistDocument?

	public static func make(from document: ProPresenterDocument) throws -> Self {
		var builder = DocumentDumpBuilder(document: document)
		return try builder.build()
	}

	public struct Source: Codable, Sendable {
		public var type: String
		public var path: String
	}

	public struct Archive: Codable, Sendable {
		public var entries: [String]
		public var embeddedMedia: [String]
	}

	public struct Presentation: Codable, Sendable {
		public var path: String
		public var name: String
		public var uuid: String
		public var category: String?
		public var notes: String?
		public var nativeCueOrder: [ComponentReference]
		public var groups: [CueGroup]
		public var selectedArrangementUUID: String?
		public var arrangements: [Arrangement]
		public var cues: [Cue]
	}

	public struct ComponentReference: Codable, Sendable {
		public var path: String
		public var uuid: String
		public var name: String?
	}

	public struct StoredReference: Codable, Sendable {
		public var uuid: String
		public var path: String?
	}

	public struct CueGroup: Codable, Sendable {
		public var index: Int
		public var path: String
		public var uuid: String
		public var name: String
		public var color: Color?
		public var hotKey: HotKey?
		public var applicationGroupUUID: String?
		public var applicationGroupName: String?
		public var cues: [StoredReference]
	}

	public struct HotKey: Codable, Sendable {
		public var code: String
		public var rawValue: Int
		public var controlIdentifier: String?
	}

	public struct Arrangement: Codable, Sendable {
		public var index: Int
		public var path: String
		public var uuid: String
		public var name: String
		public var selected: Bool
		public var groups: [StoredReference]
	}

	public struct Cue: Codable, Sendable {
		public var index: Int
		public var path: String
		public var uuid: String
		public var name: String
		public var enabled: Bool
		public var groupUUIDs: [String]
		public var actions: [Action]
	}

	public struct Action: Codable, Sendable {
		public var index: Int
		public var path: String
		public var uuid: String
		public var name: String?
		public var label: Label?
		public var type: String
		public var payload: String?
		public var enabled: Bool
		public var delay: Double
		public var slide: Slide?
		public var media: Media?
	}

	public struct Label: Codable, Sendable {
		public var text: String
		public var color: Color?
	}

	public struct Slide: Codable, Sendable {
		public var path: String
		public var uuid: String
		public var canvas: Size
		public var notes: Text?
		public var builds: SlideBuilds
		public var elements: [Element]
	}

	public struct SlideBuilds: Codable, Sendable {
		public var elementOrderUUIDs: [String]
		public var buildInCount: Int
		public var buildOutCount: Int
		public var childBuildCount: Int
	}

	public struct ElementBuilds: Codable, Sendable {
		public var hasBuildIn: Bool
		public var hasBuildOut: Bool
		public var childBuildCount: Int
	}

	public struct Element: Codable, Sendable {
		public var index: Int
		public var path: String
		public var uuid: String
		public var name: String?
		public var kind: String
		public var hidden: Bool
		public var locked: Bool
		public var bounds: Rect
		public var text: Text?
		public var media: Media?
		public var builds: ElementBuilds
	}

	public struct Text: Codable, Sendable {
		public var plainText: String
		public var rtf: String
	}

	public struct Media: Codable, Sendable, Hashable {
		public var path: String
		public var uuid: String
		public var source: String?
		public var type: String?
	}

	public struct Size: Codable, Sendable {
		public var width: Double
		public var height: Double
	}

	public struct Rect: Codable, Sendable {
		public var x: Double
		public var y: Double
		public var width: Double
		public var height: Double
	}

	public struct Color: Codable, Sendable {
		public var red: Float
		public var green: Float
		public var blue: Float
		public var alpha: Float
	}

	public struct Theme: Codable, Sendable {
		public var documents: [ThemeDocument]
	}

	public struct ThemeDocument: Codable, Sendable {
		public var archivePath: String
		public var templates: [Template]
	}

	public struct Template: Codable, Sendable {
		public var index: Int
		public var path: String
		public var name: String
		public var slide: Slide
		public var actions: [Action]
	}

	public struct PlaylistDocument: Codable, Sendable {
		public var type: String
		public var root: Playlist
		public var liveVideo: Playlist?
		public var downloads: Playlist?
	}

	public struct Playlist: Codable, Sendable {
		public var path: String
		public var uuid: String
		public var name: String
		public var type: String
		public var items: [PlaylistItem]
		public var children: [Playlist]
	}

	public struct PlaylistItem: Codable, Sendable {
		public var index: Int
		public var path: String
		public var uuid: String
		public var name: String
		public var type: String
		public var hidden: Bool
		public var documentPath: String?
		public var arrangementUUID: String?
		public var actions: [Action]
	}
}

public struct ComponentDumpReport: Codable, Sendable {
	public var path: String
	public var protobufType: String
	public var uuid: String?
	public var name: String?
	public var children: [String: Int]
	public var text: [String]

	public init(selection: ComponentSelection) {
		path = selection.canonicalPath
		protobufType = selection.protoMessageName
		uuid = Self.uuid(in: selection.jsonObject)
		name = Self.name(in: selection.jsonObject)
		children = Self.childCounts(in: selection.jsonObject)
		text = Self.visibleText(in: selection.jsonObject)
	}

	private static func uuid(in object: [String: Any]) -> String? {
		if let uuid = object["uuid"] as? [String: Any], let string = uuid["string"] as? String, !string.isEmpty {
			return string
		}
		for key in ["group", "element", "baseSlide", "base_slide"] {
			if let wrapper = object[key] as? [String: Any], let uuid = uuid(in: wrapper) {
				return uuid
			}
		}
		return nil
	}

	private static func name(in object: [String: Any]) -> String? {
		if let name = object["name"] as? String {
			return name
		}
		for key in ["group", "element", "baseSlide", "base_slide"] {
			if let wrapper = object[key] as? [String: Any], let name = name(in: wrapper) {
				return name
			}
		}
		return nil
	}

	private static func childCounts(in object: [String: Any]) -> [String: Int] {
		var result: [String: Int] = [:]
		for key in ["arrangements", "cueGroups", "cueIdentifiers", "groupIdentifiers", "cues", "actions", "slides", "elements", "children", "playlists", "items"] {
			if let values = object[key] as? [Any] {
				result[key] = values.count
			} else if let wrapper = object[key] as? [String: Any], let values = wrapper[key] as? [Any] {
				result[key] = values.count
			}
		}
		return result
	}

	private static func visibleText(in value: Any) -> [String] {
		var values: [String] = []
		if let object = value as? [String: Any] {
			if let encoded = object["rtfData"] as? String,
			   let data = Data(base64Encoded: encoded),
			   let plain = plainText(fromRTF: data),
			   !plain.isEmpty
			{
				values.append(plain)
			}
			if let text = object["text"] as? String, !text.isEmpty {
				values.append(text)
			}
			for child in object.values {
				values.append(contentsOf: visibleText(in: child))
			}
		} else if let array = value as? [Any] {
			for child in array {
				values.append(contentsOf: visibleText(in: child))
			}
		}
		var seen = Set<String>()
		return values.filter { seen.insert($0).inserted }
	}
}

private struct DocumentDumpBuilder {
	var document: ProPresenterDocument
	var media: [DocumentDumpReport.Media] = []

	mutating func build() throws -> DocumentDumpReport {
		var presentation: DocumentDumpReport.Presentation?
		var theme: DocumentDumpReport.Theme?
		var playlist: DocumentDumpReport.PlaylistDocument?
		switch document.payload {
		case let .presentation(value):
			presentation = try makePresentation(value)
		case let .theme(value):
			theme = try makeTheme(value)
		case let .playlist(value):
			playlist = try makePlaylistDocument(value)
		}
		return DocumentDumpReport(
			kind: document.kind.rawValue,
			source: source(),
			archive: .init(
				entries: document.archiveEntries.sorted(),
				embeddedMedia: document.embeddedAssetPaths.sorted(),
			),
			media: Array(Set(media)).sorted { lhs, rhs in
				if lhs.path != rhs.path {
					return lhs.path < rhs.path
				}
				if lhs.uuid != rhs.uuid {
					return lhs.uuid < rhs.uuid
				}
				return (lhs.source ?? "") < (rhs.source ?? "")
			},
			presentation: presentation,
			theme: theme,
			playlist: playlist,
		)
	}

	private func source() -> DocumentDumpReport.Source {
		switch document.origin {
		case let .raw(url): .init(type: "raw", path: url.path)
		case let .archive(url): .init(type: "archive", path: url.path)
		case let .workspace(url): .init(type: "workspace", path: url.path)
		}
	}

	private mutating func makePresentation(_ presentation: Rv_Data_Presentation) throws -> DocumentDumpReport.Presentation {
		let order = presentation.presentationOrderCueIndices
		let nativeReferences = try order.enumerated().map { nativeIndex, storedIndex in
			let cue = presentation.cues[storedIndex]
			return try DocumentDumpReport.ComponentReference(
				path: canonical("/cues[index=\(nativeIndex)]"),
				uuid: cue.uuid.string,
				name: nonEmpty(cue.name),
			)
		}
		let cuePathsByUUID = Dictionary(grouping: nativeReferences, by: \.uuid)
		let groups = try presentation.cueGroups.enumerated().map { index, cueGroup in
			try DocumentDumpReport.CueGroup(
				index: index,
				path: canonical("/cue_groups[index=\(index)]"),
				uuid: cueGroup.group.uuid.string,
				name: cueGroup.group.name,
				color: cueGroup.group.hasColor ? color(cueGroup.group.color) : nil,
				hotKey: hotKey(cueGroup.group),
				applicationGroupUUID: cueGroup.group.hasApplicationGroupIdentifier
					? nonEmpty(cueGroup.group.applicationGroupIdentifier.string)
					: nil,
				applicationGroupName: nonEmpty(cueGroup.group.applicationGroupName),
				cues: cueGroup.cueIdentifiers.map { identifier in
					.init(
						uuid: identifier.string,
						path: cuePathsByUUID[identifier.string]?.count == 1 ? cuePathsByUUID[identifier.string]?.first?.path : nil,
					)
				},
			)
		}
		let groupPathsByUUID = Dictionary(grouping: groups, by: \.uuid)
		let selectedArrangementUUID = presentation.hasSelectedArrangement ? nonEmpty(presentation.selectedArrangement.string) : nil
		let arrangements = try presentation.arrangements.enumerated().map { index, arrangement in
			try DocumentDumpReport.Arrangement(
				index: index,
				path: canonical("/arrangements[index=\(index)]"),
				uuid: arrangement.uuid.string,
				name: arrangement.name,
				selected: selectedArrangementUUID == arrangement.uuid.string,
				groups: arrangement.groupIdentifiers.map { identifier in
					.init(
						uuid: identifier.string,
						path: groupPathsByUUID[identifier.string]?.count == 1 ? groupPathsByUUID[identifier.string]?.first?.path : nil,
					)
				},
			)
		}
		let cues = try order.enumerated().map { nativeIndex, storedIndex in
			let cue = presentation.cues[storedIndex]
			let cuePath = try canonical("/cues[index=\(nativeIndex)]")
			let groupUUIDs = presentation.cueGroups.compactMap { group in
				group.cueIdentifiers.contains(where: { $0.string == cue.uuid.string }) ? group.group.uuid.string : nil
			}
			return try makeCue(cue, index: nativeIndex, path: cuePath, groupUUIDs: groupUUIDs)
		}
		return .init(
			path: "/",
			name: presentation.name,
			uuid: presentation.uuid.string,
			category: nonEmpty(presentation.category),
			notes: nonEmpty(presentation.notes),
			nativeCueOrder: nativeReferences,
			groups: groups,
			selectedArrangementUUID: selectedArrangementUUID,
			arrangements: arrangements,
			cues: cues,
		)
	}

	private mutating func makeCue(
		_ cue: Rv_Data_Cue,
		index: Int,
		path: String,
		groupUUIDs: [String],
	) throws -> DocumentDumpReport.Cue {
		try .init(
			index: index,
			path: path,
			uuid: cue.uuid.string,
			name: cue.name,
			enabled: cue.isEnabled,
			groupUUIDs: groupUUIDs,
			actions: cue.actions.enumerated().map { actionIndex, action in
				try makeAction(action, index: actionIndex, path: canonical("\(path)/actions[index=\(actionIndex)]"))
			},
		)
	}

	private mutating func makeAction(
		_ action: Rv_Data_Action,
		index: Int,
		path: String,
	) throws -> DocumentDumpReport.Action {
		let slide: DocumentDumpReport.Slide?
		switch action.actionTypeData {
		case let .slide(slideType):
			switch slideType.slide {
			case let .presentation(presentationSlide):
				slide = try makeSlide(
					presentationSlide.baseSlide,
					path: canonical("\(path)/slide/presentation/base_slide"),
					notes: text(fromRTF: presentationSlide.notes.rtfData),
				)
			case let .prop(propSlide):
				slide = try makeSlide(propSlide.baseSlide, path: canonical("\(path)/slide/prop/base_slide"), notes: nil)
			case nil:
				slide = nil
			}
		default:
			slide = nil
		}
		let actionMedia: DocumentDumpReport.Media?
		if case let .media(mediaType)? = action.actionTypeData, mediaType.hasElement {
			actionMedia = try makeMedia(mediaType.element, path: canonical("\(path)/media/element"))
		} else {
			actionMedia = nil
		}
		return .init(
			index: index,
			path: path,
			uuid: action.uuid.string,
			name: nonEmpty(action.name),
			label: action.hasLabel ? .init(text: action.label.text, color: color(action.label)) : nil,
			type: String(describing: action.type),
			payload: actionPayloadName(action.actionTypeData),
			enabled: action.isEnabled,
			delay: action.delayTime,
			slide: slide,
			media: actionMedia,
		)
	}

	private mutating func makeSlide(
		_ slide: Rv_Data_Slide,
		path: String,
		notes: DocumentDumpReport.Text?,
	) throws -> DocumentDumpReport.Slide {
		let elements = try slide.elements.enumerated().map { index, element in
			try makeElement(element, index: index, path: canonical("\(path)/elements[index=\(index)]/element"))
		}
		return .init(
			path: path,
			uuid: slide.uuid.string,
			canvas: .init(width: slide.size.width, height: slide.size.height),
			notes: notes,
			builds: .init(
				elementOrderUUIDs: slide.elementBuildOrder.map(\.string),
				buildInCount: slide.elements.count(where: \.hasBuildIn),
				buildOutCount: slide.elements.count(where: \.hasBuildOut),
				childBuildCount: slide.elements.reduce(0) { $0 + $1.childBuilds.count },
			),
			elements: elements,
		)
	}

	private mutating func makeElement(
		_ slideElement: Rv_Data_Slide.Element,
		index: Int,
		path: String,
	) throws -> DocumentDumpReport.Element {
		let element = slideElement.element
		let elementMedia: DocumentDumpReport.Media?
		if case let .media(media)? = element.fill.fillType {
			elementMedia = try makeMedia(media, path: canonical("\(path)/fill/media"))
		} else {
			elementMedia = nil
		}
		return .init(
			index: index,
			path: path,
			uuid: element.uuid.string,
			name: nonEmpty(element.name),
			kind: elementKind(element),
			hidden: element.hidden,
			locked: element.locked,
			bounds: .init(
				x: element.bounds.origin.x,
				y: element.bounds.origin.y,
				width: element.bounds.size.width,
				height: element.bounds.size.height,
			),
			text: element.hasText ? text(fromRTF: element.text.rtfData) : nil,
			media: elementMedia,
			builds: .init(
				hasBuildIn: slideElement.hasBuildIn,
				hasBuildOut: slideElement.hasBuildOut,
				childBuildCount: slideElement.childBuilds.count,
			),
		)
	}

	private mutating func makeTheme(_ fallback: Rv_Data_Template.Document) throws -> DocumentDumpReport.Theme {
		let entries = document.themeEntries.isEmpty
			? [ProPresenterDocument.ThemeEntry(relativePath: "Theme", document: fallback)]
			: document.themeEntries
		let documents = try entries.map { entry in
			let themeDocument = ProPresenterDocument(
				payload: .theme(entry.document),
				origin: document.origin,
				resourceDirectory: document.resourceDirectory,
			)
			let originalDocument = document
			document = themeDocument
			defer { document = originalDocument }
			return try DocumentDumpReport.ThemeDocument(
				archivePath: entry.relativePath,
				templates: entry.document.slides.enumerated().map { index, template in
					let templatePath = try canonical("/slides[index=\(index)]")
					return try DocumentDumpReport.Template(
						index: index,
						path: templatePath,
						name: template.name,
						slide: makeSlide(template.baseSlide, path: canonical("\(templatePath)/base_slide"), notes: nil),
						actions: template.actions.enumerated().map { actionIndex, action in
							try makeAction(action, index: actionIndex, path: canonical("\(templatePath)/actions[index=\(actionIndex)]"))
						},
					)
				},
			)
		}
		return .init(documents: documents)
	}

	private mutating func makePlaylistDocument(_ playlist: Rv_Data_PlaylistDocument) throws -> DocumentDumpReport.PlaylistDocument {
		try .init(
			type: String(describing: playlist.type),
			root: makePlaylist(playlist.rootNode, path: canonical("/root_node")),
			liveVideo: playlist.hasLiveVideoPlaylist
				? makePlaylist(playlist.liveVideoPlaylist, path: canonical("/live_video_playlist"))
				: nil,
			downloads: playlist.hasDownloadsPlaylist
				? makePlaylist(playlist.downloadsPlaylist, path: canonical("/downloads_playlist"))
				: nil,
		)
	}

	private mutating func makePlaylist(_ playlist: Rv_Data_Playlist, path: String) throws -> DocumentDumpReport.Playlist {
		let items: [Rv_Data_PlaylistItem] = switch playlist.childrenType {
		case let .items(wrapper): wrapper.items
		case .playlists, nil: []
		}
		var children = try playlist.children.enumerated().map { index, child in
			try makePlaylist(child, path: canonical("\(path)/children[index=\(index)]"))
		}
		if case let .playlists(wrapper)? = playlist.childrenType {
			children += try wrapper.playlists.enumerated().map { index, child in
				try makePlaylist(child, path: canonical("\(path)/playlists/playlists[index=\(index)]"))
			}
		}
		return try .init(
			path: path,
			uuid: playlist.uuid.string,
			name: playlist.name,
			type: String(describing: playlist.type),
			items: items.enumerated().map { index, item in
				let itemPath = try canonical("\(path)/items[index=\(index)]")
				return try makePlaylistItem(item, index: index, path: itemPath)
			},
			children: children,
		)
	}

	private mutating func makePlaylistItem(
		_ item: Rv_Data_PlaylistItem,
		index: Int,
		path: String,
	) throws -> DocumentDumpReport.PlaylistItem {
		let type: String
		let documentPath: String?
		let arrangementUUID: String?
		let actions: [DocumentDumpReport.Action]
		switch item.itemType {
		case let .header(header):
			type = "header"
			documentPath = nil
			arrangementUUID = nil
			actions = try header.actions.enumerated().map { actionIndex, action in
				try makeAction(action, index: actionIndex, path: canonical("\(path)/header/actions[index=\(actionIndex)]"))
			}
		case let .presentation(presentation):
			type = "presentation"
			documentPath = nonEmpty(presentation.documentPath.renderPath)
			arrangementUUID = presentation.hasArrangement ? nonEmpty(presentation.arrangement.string) : nil
			actions = []
		case let .cue(cue):
			type = "cue"
			documentPath = nil
			arrangementUUID = nil
			actions = try cue.actions.enumerated().map { actionIndex, action in
				try makeAction(action, index: actionIndex, path: canonical("\(path)/cue/actions[index=\(actionIndex)]"))
			}
		case .planningCenter:
			type = "planningCenter"
			documentPath = nil
			arrangementUUID = nil
			actions = []
		case .placeholder:
			type = "placeholder"
			documentPath = nil
			arrangementUUID = nil
			actions = []
		case nil:
			type = "unknown"
			documentPath = nil
			arrangementUUID = nil
			actions = []
		}
		return .init(
			index: index,
			path: path,
			uuid: item.uuid.string,
			name: item.name,
			type: type,
			hidden: item.isHidden,
			documentPath: documentPath,
			arrangementUUID: arrangementUUID,
			actions: actions,
		)
	}

	private func canonical(_ path: String) throws -> String {
		try ComponentResolver.resolve(ComponentPath(path), in: document).canonicalPath
	}

	private mutating func makeMedia(_ mediaValue: Rv_Data_Media, path: String) -> DocumentDumpReport.Media {
		let value = DocumentDumpReport.Media(
			path: path,
			uuid: mediaValue.uuid.string,
			source: nonEmpty(mediaValue.url.renderPath),
			type: mediaType(mediaValue.typeProperties),
		)
		media.append(value)
		return value
	}
}

private func nonEmpty(_ value: String) -> String? {
	value.isEmpty ? nil : value
}

private func text(fromRTF data: Data) -> DocumentDumpReport.Text? {
	guard !data.isEmpty else { return nil }
	return .init(
		plainText: plainText(fromRTF: data) ?? "",
		rtf: String(decoding: data, as: UTF8.self),
	)
}

private func plainText(fromRTF data: Data) -> String? {
	guard let attributed = try? NSAttributedString(
		data: data,
		options: [.documentType: NSAttributedString.DocumentType.rtf],
		documentAttributes: nil,
	) else { return nil }
	return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func color(_ label: Rv_Data_Action.Label) -> DocumentDumpReport.Color? {
	guard label.hasColor else { return nil }
	return color(label.color)
}

private func color(_ value: Rv_Data_Color) -> DocumentDumpReport.Color {
	.init(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
}

private func hotKey(_ group: Rv_Data_Group) -> DocumentDumpReport.HotKey? {
	guard group.hasHotKey else { return nil }
	return .init(
		code: String(describing: group.hotKey.code),
		rawValue: group.hotKey.code.rawValue,
		controlIdentifier: nonEmpty(group.hotKey.controlIdentifier),
	)
}

private func elementKind(_ element: Rv_Data_Graphics.Element) -> String {
	if element.hasText {
		return "text"
	}
	if case .media? = element.fill.fillType {
		return "media"
	}
	if element.hasPath {
		return "shape"
	}
	return "graphic"
}

private func mediaType(_ value: Rv_Data_Media.OneOf_TypeProperties?) -> String? {
	switch value {
	case .audio: "audio"
	case .image: "image"
	case .video: "video"
	case .liveVideo: "liveVideo"
	case .webContent: "webContent"
	case nil: nil
	}
}

private func actionPayloadName(_ value: Rv_Data_Action.OneOf_ActionTypeData?) -> String? {
	switch value {
	case .collectionElement: "collectionElement"
	case .playlistItem: "playlistItem"
	case .blendMode: "blendMode"
	case .transition: "transition"
	case .media: "media"
	case .doubleItem: "double"
	case .effects: "effects"
	case .slide: "slide"
	case .background: "background"
	case .timer: "timer"
	case .clear: "clear"
	case .stage: "stageLayout"
	case .prop: "prop"
	case .mask: "mask"
	case .message: "message"
	case .socialMedia: "socialMedia"
	case .communication: "communication"
	case .multiScreen: "multiScreen"
	case .presentationDocument: "presentationDocument"
	case .externalPresentation: "externalPresentation"
	case .audienceLook: "audienceLook"
	case .audioInput: "audioInput"
	case .slideDestination: "slideDestination"
	case .macro: "macro"
	case .clearGroup_p: "clearGroup"
	case .transportControl: "transportControl"
	case nil: nil
	}
}
