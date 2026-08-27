import Foundation
import ProCRUDCore

enum DumpTextFormatter {
	static func format(_ report: DocumentDumpReport) -> String {
		var lines = [
			"Kind: \(report.kind)",
			"Source: \(report.source.type) \(report.source.path)",
		]
		if let presentation = report.presentation {
			append(presentation, to: &lines)
		}
		if let theme = report.theme {
			append(theme, to: &lines)
		}
		if let playlist = report.playlist {
			append(playlist, to: &lines)
		}
		appendMedia(report.media, title: "Referenced media", indentation: "", to: &lines)
		if !report.archive.entries.isEmpty {
			lines.append("Archive entries:")
			lines += report.archive.entries.map { "  \($0)" }
		}
		if !report.archive.embeddedMedia.isEmpty {
			lines.append("Embedded media:")
			lines += report.archive.embeddedMedia.map { "  \($0)" }
		}
		return lines.joined(separator: "\n")
	}

	static func format(_ report: ComponentDumpReport) -> String {
		var lines = [
			"Path: \(report.path)",
			"Protobuf type: \(report.protobufType)",
		]
		if let uuid = report.uuid {
			lines.append("UUID: \(uuid)")
		}
		if let name = report.name {
			lines.append("Name: \(name)")
		}
		for (name, count) in report.children.sorted(by: { $0.key < $1.key }) {
			lines.append("\(humanized(name)): \(count)")
		}
		for value in report.text {
			lines.append("Text: \(escaped(value))")
		}
		return lines.joined(separator: "\n")
	}

	private static func append(_ presentation: DocumentDumpReport.Presentation, to lines: inout [String]) {
		lines += [
			"Name: \(presentation.name)",
			"UUID: \(presentation.uuid)",
		]
		if let category = presentation.category {
			lines.append("Category: \(category)")
		}
		if let notes = presentation.notes {
			lines.append("Notes: \(escaped(notes))")
		}

		lines.append("Native cue order:")
		for (index, cue) in presentation.nativeCueOrder.enumerated() {
			lines.append("  \(index + 1). \(cue.name ?? cue.uuid) [\(cue.path)]")
		}

		lines.append("Cue groups:")
		for group in presentation.groups {
			lines.append("  \(group.index + 1). \(group.name) (\(group.uuid)) [\(group.path)]")
			if let color = group.color {
				lines.append("    Color: rgba(\(color.red), \(color.green), \(color.blue), \(color.alpha))")
			}
			if let hotKey = group.hotKey, hotKey.code != "unknown" || hotKey.controlIdentifier != nil {
				let control = hotKey.controlIdentifier.map { ", control=\($0)" } ?? ""
				lines.append("    Hot key: \(hotKey.code) (raw=\(hotKey.rawValue)\(control))")
			}
			if let applicationGroupUUID = group.applicationGroupUUID {
				let name = group.applicationGroupName.map { " (\($0))" } ?? ""
				lines.append("    Application group: \(applicationGroupUUID)\(name)")
			}
			for cue in group.cues {
				lines.append("    \(cue.uuid)\(cue.path.map { " [\($0)]" } ?? " (unresolved)")")
			}
		}

		if !presentation.arrangements.isEmpty {
			if let selected = presentation.selectedArrangementUUID {
				lines.append("Selected arrangement UUID: \(selected)")
			} else {
				lines.append("Selected arrangement: none (Master/native fallback)")
			}
			lines.append("Stored arrangements:")
			for arrangement in presentation.arrangements {
				let selected = arrangement.selected ? " [selected]" : ""
				lines.append("  \(arrangement.index + 1). \(arrangement.name) (\(arrangement.uuid))\(selected) [\(arrangement.path)]")
				for group in arrangement.groups {
					lines.append("    \(group.uuid)\(group.path.map { " [\($0)]" } ?? " (unresolved)")")
				}
			}
		} else if let selected = presentation.selectedArrangementUUID {
			lines.append("Selected arrangement UUID: \(selected) (unresolved)")
		}

		lines.append("Cues:")
		for cue in presentation.cues {
			lines.append("  \(cue.index + 1). \(cue.name.isEmpty ? cue.uuid : cue.name) [\(cue.path)]")
			lines.append("    UUID: \(cue.uuid)")
			lines.append("    Enabled: \(cue.enabled)")
			if !cue.groupUUIDs.isEmpty {
				lines.append("    Groups: \(cue.groupUUIDs.joined(separator: ", "))")
			}
			appendActions(cue.actions, indentation: "    ", to: &lines)
		}
	}

	private static func append(_ theme: DocumentDumpReport.Theme, to lines: inout [String]) {
		lines.append("Theme documents:")
		for document in theme.documents {
			lines.append("  \(document.archivePath)")
			for template in document.templates {
				lines.append("    \(template.index + 1). \(template.name) [\(template.path)]")
				appendSlide(template.slide, indentation: "      ", to: &lines)
				appendActions(template.actions, indentation: "      ", to: &lines)
			}
		}
	}

	private static func append(_ playlist: DocumentDumpReport.PlaylistDocument, to lines: inout [String]) {
		lines.append("Playlist type: \(playlist.type)")
		lines.append("Playlists:")
		appendPlaylist(playlist.root, indentation: "  ", to: &lines)
		if let liveVideo = playlist.liveVideo {
			lines.append("Live video playlist:")
			appendPlaylist(liveVideo, indentation: "  ", to: &lines)
		}
		if let downloads = playlist.downloads {
			lines.append("Downloads playlist:")
			appendPlaylist(downloads, indentation: "  ", to: &lines)
		}
	}

	private static func appendPlaylist(
		_ playlist: DocumentDumpReport.Playlist,
		indentation: String,
		to lines: inout [String],
	) {
		lines.append("\(indentation)\(playlist.name) (\(playlist.uuid)) [\(playlist.path)]")
		for item in playlist.items {
			lines.append("\(indentation)  \(item.index + 1). \(item.name) [\(item.path)]")
			lines.append("\(indentation)    Type: \(item.type)\(item.hidden ? ", hidden" : "")")
			if let documentPath = item.documentPath {
				lines.append("\(indentation)    Document: \(documentPath)")
			}
			if let arrangementUUID = item.arrangementUUID {
				lines.append("\(indentation)    Arrangement UUID: \(arrangementUUID)")
			}
			appendActions(item.actions, indentation: indentation + "    ", to: &lines)
		}
		for child in playlist.children {
			appendPlaylist(child, indentation: indentation + "  ", to: &lines)
		}
	}

	private static func appendActions(
		_ actions: [DocumentDumpReport.Action],
		indentation: String,
		to lines: inout [String],
	) {
		guard !actions.isEmpty else { return }
		lines.append("\(indentation)Actions:")
		for action in actions {
			let title = action.name ?? action.label?.text ?? action.uuid
			lines.append("\(indentation)  \(action.index + 1). \(action.type): \(title) [\(action.path)]")
			lines.append("\(indentation)    UUID: \(action.uuid)")
			lines.append("\(indentation)    Enabled: \(action.enabled)")
			if let payload = action.payload {
				lines.append("\(indentation)    Payload: \(payload)")
			}
			if let label = action.label {
				lines.append("\(indentation)    Label: \(escaped(label.text))")
			}
			if action.delay != 0 {
				lines.append("\(indentation)    Delay: \(action.delay)")
			}
			if let media = action.media {
				appendMedia(media, indentation: indentation + "    ", to: &lines)
			}
			if let slide = action.slide {
				appendSlide(slide, indentation: indentation + "    ", to: &lines)
			}
		}
	}

	private static func appendSlide(
		_ slide: DocumentDumpReport.Slide,
		indentation: String,
		to lines: inout [String],
	) {
		lines.append("\(indentation)Slide: \(slide.uuid) [\(slide.path)]")
		lines.append("\(indentation)Canvas: \(number(slide.canvas.width))x\(number(slide.canvas.height))")
		if let notes = slide.notes {
			lines.append("\(indentation)Notes: \(escaped(notes.plainText))")
		}
		if !slide.builds.elementOrderUUIDs.isEmpty || slide.builds.buildInCount > 0 || slide.builds.buildOutCount > 0 || slide.builds.childBuildCount > 0 {
			lines.append(
				"\(indentation)Builds: order \(slide.builds.elementOrderUUIDs.count), in \(slide.builds.buildInCount), out \(slide.builds.buildOutCount), child \(slide.builds.childBuildCount)",
			)
		}
		guard !slide.elements.isEmpty else { return }
		lines.append("\(indentation)Elements:")
		for element in slide.elements {
			let title = element.name ?? element.uuid
			lines.append("\(indentation)  \(element.index + 1). \(element.kind): \(title) [\(element.path)]")
			lines.append(
				"\(indentation)    Bounds: \(number(element.bounds.x)),\(number(element.bounds.y)) \(number(element.bounds.width))x\(number(element.bounds.height))",
			)
			if element.hidden {
				lines.append("\(indentation)    Hidden: true")
			}
			if element.locked {
				lines.append("\(indentation)    Locked: true")
			}
			if let text = element.text {
				lines.append("\(indentation)    Text: \(escaped(text.plainText))")
			}
			if let media = element.media {
				appendMedia(media, indentation: indentation + "    ", to: &lines)
			}
			if element.builds.hasBuildIn || element.builds.hasBuildOut || element.builds.childBuildCount > 0 {
				lines.append(
					"\(indentation)    Builds: in \(element.builds.hasBuildIn), out \(element.builds.hasBuildOut), child \(element.builds.childBuildCount)",
				)
			}
		}
	}

	private static func appendMedia(
		_ media: [DocumentDumpReport.Media],
		title: String,
		indentation: String,
		to lines: inout [String],
	) {
		guard !media.isEmpty else { return }
		lines.append("\(indentation)\(title):")
		for item in media {
			appendMedia(item, indentation: indentation + "  ", to: &lines)
		}
	}

	private static func appendMedia(
		_ media: DocumentDumpReport.Media,
		indentation: String,
		to lines: inout [String],
	) {
		let description = [media.type, media.source].compactMap(\.self).joined(separator: ": ")
		lines.append("\(indentation)Media: \(description.isEmpty ? media.uuid : description) (\(media.uuid)) [\(media.path)]")
	}

	private static func escaped(_ value: String) -> String {
		value.replacingOccurrences(of: "\n", with: "\\n")
	}

	private static func humanized(_ value: String) -> String {
		value.reduce(into: "") { result, character in
			if character.isUppercase {
				result.append(" ")
			}
			result.append(character)
		}.capitalized
	}

	private static func number(_ value: Double) -> String {
		value.rounded() == value ? String(Int(value)) : String(value)
	}
}
