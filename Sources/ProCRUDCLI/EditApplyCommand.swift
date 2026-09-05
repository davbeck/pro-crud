import ArgumentParser
import Foundation
import ProCRUDCore
import ProPresenterProto

struct EditApply: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "apply", abstract: "Atomically apply a JSON array of edit subcommands.")

	@Argument(help: "Path to a raw or bundled ProPresenter document.") var input: String
	@Option(help: "Path to a JSON array of edit subcommands.") var file: String
	@Option(help: "Write to a new document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		let operations = try JSONDecoder().decode(
			[BatchEditOperation].self,
			from: Data(contentsOf: URL(fileURLWithPath: file)),
		)
		let inputURL = URL(fileURLWithPath: input)
		let session = try DocumentEditSession.open(inputURL)
		var templateMediaURLs: Set<String> = []
		var templateWarnings: [String] = []
		var retainedTemplateCandidates: [ThemeTemplateSource.Candidate] = []
		var editPathOutputs: [(operation: Int, output: EditPathOutput)] = []
		for (index, operation) in operations.enumerated() {
			do {
				let outputs = try operation.apply(
					to: &session.document,
					materializingTemplateMediaURLs: &templateMediaURLs,
					templateWarnings: &templateWarnings,
					retainedTemplateCandidates: &retainedTemplateCandidates,
				)
				editPathOutputs.append(contentsOf: outputs.map { (index + 1, $0) })
			} catch {
				throw ValidationError("Batch command \(index + 1) (\(operation.command)) failed: \(error)")
			}
		}

		let destination = output.map(URL.init(fileURLWithPath:)) ?? inputURL
		try withExtendedLifetime(retainedTemplateCandidates) {
			try session.write(
				to: destination,
				replace: output == nil || replace,
				materializingTemplateMediaURLs: templateMediaURLs,
			)
		}
		for warning in Set(templateWarnings).sorted() {
			print("Warning [template]: \(warning)")
		}
		for item in editPathOutputs {
			print("Command \(item.operation) \(item.output.kind.rawValue.lowercased()): \(item.output.path)")
		}
		print("Wrote: \(destination.path)")
	}
}

private struct BatchEditOperation: Decodable {
	let command: String
	let path: String?
	let name: String?
	let after: String?
	let text: String?
	let rtf: String?
	let rtfFile: String?
	let color: String?
	let code: HotKeyCodeArgument?
	let controlIdentifier: String?
	let source: String?
	let fromPlaylist: String?
	let playlist: String?
	let item: String?
	let preserveUUID: Bool?
	let syncLabel: Bool?
	let allowURLOnly: Bool?
	let bounds: String?
	let type: String?
	let documentPath: String?
	let group: [String]?
	let cue: [String]?
	let empty: Bool?
	let select: Bool?
	let transfer: Bool?
	let leaveOmittedUngrouped: Bool?
	let first: Bool?
	let clear: Bool?
	let hidden: Bool?
	let deleteCues: Bool?
	let leaveCuesUngrouped: Bool?
	let moveCuesTo: String?
	let removeFromArrangements: Bool?
	let theme: String?
	let themeDocument: String?
	let template: String?
	let includeTemplateActions: Bool?
	let templateActions: String?
	let duplicate: String?
	let json: String?
	let jsonFile: String?

	private enum CodingKeys: String, CodingKey {
		case command, path, name, after, text, rtf, color, code, source, playlist, item, bounds, type, group, cue, empty, select, transfer, first, clear, hidden, theme, template, duplicate, json
		case rtfFile = "rtf-file"
		case documentPath = "document"
		case jsonFile = "json-file"
		case fromPlaylist = "from-playlist"
		case preserveUUID = "preserve-uuid"
		case syncLabel = "sync-label"
		case allowURLOnly = "allow-url-only"
		case themeDocument = "theme-document"
		case includeTemplateActions = "include-template-actions"
		case templateActions = "template-actions"
		case leaveOmittedUngrouped = "leave-omitted-ungrouped"
		case deleteCues = "delete-cues"
		case leaveCuesUngrouped = "leave-cues-ungrouped"
		case moveCuesTo = "move-cues-to"
		case removeFromArrangements = "remove-from-arrangements"
		case controlIdentifier = "control-identifier"
	}

	init(from decoder: any Decoder) throws {
		let raw = try decoder.container(keyedBy: BatchEditCodingKey.self)
		let commandKey = BatchEditCodingKey("command")
		command = try raw.decode(String.self, forKey: commandKey)
		guard let allowedOptions = Self.allowedOptions[command] else {
			throw DecodingError.dataCorruptedError(
				forKey: commandKey,
				in: raw,
				debugDescription: "Unsupported edit subcommand \(command).",
			)
		}
		let allowedKeys = allowedOptions.union(["command"])
		if let unknown = raw.allKeys.first(where: { !allowedKeys.contains($0.stringValue) }) {
			throw DecodingError.dataCorruptedError(
				forKey: unknown,
				in: raw,
				debugDescription: "Option \(unknown.stringValue) is not supported by edit \(command).",
			)
		}

		let values = try decoder.container(keyedBy: CodingKeys.self)
		path = try values.decodeIfPresent(String.self, forKey: .path)
		name = try values.decodeIfPresent(String.self, forKey: .name)
		after = try values.decodeIfPresent(String.self, forKey: .after)
		text = try values.decodeIfPresent(String.self, forKey: .text)
		rtf = try values.decodeIfPresent(String.self, forKey: .rtf)
		rtfFile = try values.decodeIfPresent(String.self, forKey: .rtfFile)
		color = try values.decodeIfPresent(String.self, forKey: .color)
		code = try values.decodeIfPresent(HotKeyCodeArgument.self, forKey: .code)
		controlIdentifier = try values.decodeIfPresent(String.self, forKey: .controlIdentifier)
		source = try values.decodeIfPresent(String.self, forKey: .source)
		fromPlaylist = try values.decodeIfPresent(String.self, forKey: .fromPlaylist)
		playlist = try values.decodeIfPresent(String.self, forKey: .playlist)
		item = try values.decodeIfPresent(String.self, forKey: .item)
		preserveUUID = try values.decodeIfPresent(Bool.self, forKey: .preserveUUID)
		syncLabel = try values.decodeIfPresent(Bool.self, forKey: .syncLabel)
		allowURLOnly = try values.decodeIfPresent(Bool.self, forKey: .allowURLOnly)
		bounds = try values.decodeIfPresent(String.self, forKey: .bounds)
		type = try values.decodeIfPresent(String.self, forKey: .type)
		documentPath = try values.decodeIfPresent(String.self, forKey: .documentPath)
		if let singleGroup = try? values.decode(String.self, forKey: .group) {
			group = [singleGroup]
		} else {
			group = try values.decodeIfPresent([String].self, forKey: .group)
		}
		if let singleCue = try? values.decode(String.self, forKey: .cue) {
			cue = [singleCue]
		} else {
			cue = try values.decodeIfPresent([String].self, forKey: .cue)
		}
		empty = try values.decodeIfPresent(Bool.self, forKey: .empty)
		select = try values.decodeIfPresent(Bool.self, forKey: .select)
		transfer = try values.decodeIfPresent(Bool.self, forKey: .transfer)
		leaveOmittedUngrouped = try values.decodeIfPresent(Bool.self, forKey: .leaveOmittedUngrouped)
		first = try values.decodeIfPresent(Bool.self, forKey: .first)
		clear = try values.decodeIfPresent(Bool.self, forKey: .clear)
		hidden = try values.decodeIfPresent(Bool.self, forKey: .hidden)
		deleteCues = try values.decodeIfPresent(Bool.self, forKey: .deleteCues)
		leaveCuesUngrouped = try values.decodeIfPresent(Bool.self, forKey: .leaveCuesUngrouped)
		moveCuesTo = try values.decodeIfPresent(String.self, forKey: .moveCuesTo)
		removeFromArrangements = try values.decodeIfPresent(Bool.self, forKey: .removeFromArrangements)
		theme = try values.decodeIfPresent(String.self, forKey: .theme)
		themeDocument = try values.decodeIfPresent(String.self, forKey: .themeDocument)
		template = try values.decodeIfPresent(String.self, forKey: .template)
		includeTemplateActions = try values.decodeIfPresent(Bool.self, forKey: .includeTemplateActions)
		templateActions = try values.decodeIfPresent(String.self, forKey: .templateActions)
		duplicate = try values.decodeIfPresent(String.self, forKey: .duplicate)
		json = try values.decodeIfPresent(String.self, forKey: .json)
		jsonFile = try values.decodeIfPresent(String.self, forKey: .jsonFile)
	}

	func apply(
		to document: inout ProPresenterDocument,
		materializingTemplateMediaURLs: inout Set<String>,
		templateWarnings: inout [String],
		retainedTemplateCandidates: inout [ThemeTemplateSource.Candidate],
	) throws -> [EditPathOutput] {
		switch command {
		case "patch":
			let sources = [json != nil, jsonFile != nil].count(where: { $0 })
			guard sources == 1 else { throw ValidationError("Specify exactly one of json or json-file.") }
			let data = if let json {
				Data(json.utf8)
			} else {
				try Data(contentsOf: URL(fileURLWithPath: required(jsonFile, option: "json-file")))
			}
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPathContext = try EditStablePathContext(path: componentPath, in: document)
			try DocumentEditor.patch(
				&document,
				at: componentPath,
				jsonData: data,
				allowURLOnly: allowURLOnly == true,
			)
			let affectedPath = try affectedPathContext.resolvedPath(in: document)
			return [.init(kind: .affected, path: affectedPath)]

		case "add-slide":
			let candidate: ThemeTemplateSource.Candidate?
			if let theme {
				candidate = try ThemeTemplateSource.select(
					ThemeTemplateSource.candidates(
						from: URL(fileURLWithPath: theme),
						themeDocument: themeDocument,
					),
					named: template,
				)
				materializingTemplateMediaURLs.formUnion(candidate?.preferredAbsoluteMediaURLs ?? [])
				templateWarnings.append(contentsOf: candidate?.mediaWarnings ?? [])
				if let candidate {
					retainedTemplateCandidates.append(candidate)
				}
			} else {
				guard template == nil, themeDocument == nil, includeTemplateActions != true else {
					throw ValidationError("template, theme-document, and include-template-actions require theme.")
				}
				candidate = nil
			}
			guard theme == nil || duplicate == nil else { throw ValidationError("Use either theme or duplicate, not both.") }
			let createdUUID = try applyToPresentation(&document, command: command) { presentation in
				let existingCueIDs = Set(presentation.cues.map(\.uuid.string))
				let report = try DocumentEditor.addBlankSlide(
					to: &presentation,
					groupPath: ComponentPath(requiredSingle(group, option: "group")),
					after: after.map(ComponentPath.init),
					template: candidate?.slide,
					includeTemplateActions: includeTemplateActions == true,
					duplicateCuePath: duplicate.map(ComponentPath.init),
				)
				templateWarnings.append(contentsOf: report?.warnings ?? [])
				guard let identifier = presentation.cues.lazy.map(\.uuid.string).first(where: { !existingCueIDs.contains($0) }) else {
					throw ValidationError("edit add-slide did not produce a new cue identity.")
				}
				return identifier
			}
			let createdPath = try canonicalPath(ComponentPath("/cues[uuid=\(createdUUID)]"), in: document)
			return [.init(kind: .created, path: createdPath)]

		case "add-cue-group":
			guard empty == true || cue?.isEmpty == false else {
				throw ValidationError("Provide one or more cue values, or set empty to true.")
			}
			guard empty != true || cue?.isEmpty != false else {
				throw ValidationError("empty cannot be combined with cue.")
			}
			let createdUUID = try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.addCueGroup(
					to: &presentation,
					name: required(name, option: "name"),
					color: color.map(DocumentEditor.color(hex:)),
					cuePaths: (cue ?? []).map(ComponentPath.init),
					after: after.map(ComponentPath.init),
				)
			}
			let createdPath = try canonicalPath(ComponentPath("/cue_groups[uuid=\(createdUUID)]"), in: document)
			return [.init(kind: .created, path: createdPath)]

		case "set-cue-group-cues":
			guard empty == true || cue?.isEmpty == false else {
				throw ValidationError("Provide one or more cue values, or set empty to true.")
			}
			guard empty != true || cue?.isEmpty != false else {
				throw ValidationError("empty cannot be combined with cue.")
			}
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.setCueGroupCues(
					in: &presentation,
					at: componentPath,
					cuePaths: (cue ?? []).map(ComponentPath.init),
					ownershipPolicy: transfer == true ? .transferFromOtherGroups : .requireUnassignedOrSameGroup,
					omittedCuePolicy: leaveOmittedUngrouped == true ? .leaveUngrouped : .reject,
				)
			}
			return [.init(kind: .affected, path: affectedPath)]

		case "move-cue-to-group":
			guard first != true || after == nil else { throw ValidationError("first cannot be combined with after.") }
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			let insertion: DocumentEditor.CueGroupCueInsertion = if first == true {
				.start
			} else if let after {
				try .after(ComponentPath(after))
			} else {
				.end
			}
			try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.moveCueToGroup(
					in: &presentation,
					at: componentPath,
					groupPath: ComponentPath(requiredSingle(group, option: "group")),
					insertion: insertion,
				)
			}
			return [.init(kind: .affected, path: affectedPath)]

		case "set-cue-group-color":
			guard (color != nil) != (clear == true) else {
				throw ValidationError("Provide exactly one of color or clear.")
			}
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.setCueGroupColor(
					in: &presentation,
					at: componentPath,
					to: color.map(DocumentEditor.color(hex:)),
				)
			}
			return [.init(kind: .affected, path: affectedPath)]

		case "set-cue-group-hotkey":
			guard (code != nil) != (clear == true) else {
				throw ValidationError("Provide exactly one of code or clear.")
			}
			guard code != nil || controlIdentifier == nil else {
				throw ValidationError("control-identifier requires code.")
			}
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try applyToPresentation(&document, command: command) { presentation in
				if clear == true {
					try DocumentEditor.clearCueGroupHotKey(in: &presentation, at: componentPath)
				} else if let code {
					try DocumentEditor.setCueGroupHotKey(
						in: &presentation,
						at: componentPath,
						code: code.value,
						controlIdentifier: controlIdentifier ?? "",
					)
				}
			}
			return [.init(kind: .affected, path: affectedPath)]

		case "duplicate-cue-group":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let sourcePath = try canonicalPath(componentPath, in: document)
			let createdUUID = try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.duplicateCueGroup(in: &presentation, at: componentPath, name: name)
			}
			let createdPath = try canonicalPath(ComponentPath("/cue_groups[uuid=\(createdUUID)]"), in: document)
			return [
				.init(kind: .affected, path: sourcePath),
				.init(kind: .created, path: createdPath),
			]

		case "remove-cue-group":
			let cuePolicyCount = [deleteCues == true, leaveCuesUngrouped == true, moveCuesTo != nil].count(where: { $0 })
			guard cuePolicyCount <= 1 else {
				throw ValidationError("Choose only one of delete-cues, leave-cues-ungrouped, or move-cues-to.")
			}
			let cuePolicy: CueGroupCueRemovalPolicy = if deleteCues == true {
				.deleteOwnedCues
			} else if leaveCuesUngrouped == true {
				.leaveUngrouped
			} else if let moveCuesTo {
				try .moveCues(to: ComponentPath(moveCuesTo))
			} else {
				.rejectNonempty
			}
			let componentPath = try ComponentPath(required(path, option: "path"))
			let removedPath = try canonicalPath(componentPath, in: document)
			_ = try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.removeCueGroup(
					in: &presentation,
					at: componentPath,
					cuePolicy: cuePolicy,
					arrangementPolicy: removeFromArrangements == true ? .removeAllOccurrences : .rejectReferences,
				)
			}
			return [.init(kind: .removed, path: removedPath)]

		case "add-arrangement":
			guard empty != true || group?.isEmpty != false else {
				throw ValidationError("empty cannot be combined with group.")
			}
			let groupPaths: [ComponentPath]? = if empty == true {
				[]
			} else if let group, !group.isEmpty {
				try group.map(ComponentPath.init)
			} else {
				nil
			}
			let createdUUID = try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.addArrangement(
					to: &presentation,
					name: required(name, option: "name"),
					groupPaths: groupPaths,
					select: select == true,
				)
			}
			let createdPath = try canonicalPath(ComponentPath("/arrangements[uuid=\(createdUUID)]"), in: document)
			return [.init(kind: .created, path: createdPath)]

		case "set-arrangement-groups":
			guard empty == true || group?.isEmpty == false else {
				throw ValidationError("Provide one or more group values, or set empty to true.")
			}
			guard empty != true || group?.isEmpty != false else {
				throw ValidationError("empty cannot be combined with group.")
			}
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.setArrangementGroups(
					in: &presentation,
					at: componentPath,
					groupPaths: (group ?? []).map(ComponentPath.init),
				)
			}
			return [.init(kind: .affected, path: affectedPath)]

		case "select-arrangement":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.selectArrangement(in: &presentation, at: componentPath)
			}
			return [.init(kind: .affected, path: affectedPath)]

		case "clear-selected-arrangement":
			try applyToPresentation(&document, command: command) { presentation in
				DocumentEditor.clearSelectedArrangement(in: &presentation)
			}
			return [.init(kind: .affected, path: "/selected_arrangement")]

		case "apply-template":
			let candidate = try ThemeTemplateSource.select(
				ThemeTemplateSource.candidates(
					from: URL(fileURLWithPath: required(theme, option: "theme")),
					themeDocument: themeDocument,
				),
				named: template,
			)
			materializingTemplateMediaURLs.formUnion(candidate.preferredAbsoluteMediaURLs)
			templateWarnings.append(contentsOf: candidate.mediaWarnings)
			retainedTemplateCandidates.append(candidate)
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try applyToPresentation(&document, command: command) { presentation in
				let actionPolicy = try actionPolicy(templateActions)
				let report = try DocumentEditor.applyTemplate(
					in: &presentation,
					at: componentPath,
					template: candidate.slide,
					actionPolicy: actionPolicy,
				)
				templateWarnings.append(contentsOf: report.warnings)
			}
			return [.init(kind: .affected, path: affectedPath)]

		case "rename":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try DocumentEditor.rename(&document, at: componentPath, to: required(name, option: "name"))
			return [.init(kind: .affected, path: affectedPath)]

		case "duplicate":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let sourcePath = try canonicalPath(componentPath, in: document)
			let createdUUID = try DocumentEditor.duplicate(&document, at: componentPath)
			let createdPath = try canonicalCreatedSiblingPath(sourcePath: sourcePath, uuid: createdUUID, in: document)
			return [
				.init(kind: .affected, path: sourcePath),
				.init(kind: .created, path: createdPath),
			]

		case "remove":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let removedPath = try canonicalPath(componentPath, in: document)
			try DocumentEditor.remove(&document, at: componentPath)
			return [.init(kind: .removed, path: removedPath)]

		case "move":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let afterPath = try ComponentPath(required(after, option: "after"))
			let outputPath = try EditMovePathContext(source: componentPath, after: afterPath, in: document)
			try DocumentEditor.move(
				&document,
				at: componentPath,
				after: afterPath,
			)
			let affectedPath = try outputPath.resolvedPath(in: document)
			return [.init(kind: .affected, path: affectedPath)]

		case "set-text":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try applyToPresentation(&document, command: command) { presentation in
				let sources = [text != nil, rtf != nil, rtfFile != nil].count(where: { $0 })
				guard sources == 1 else { throw ValidationError("Provide exactly one of text, rtf, or rtf-file.") }
				if let text {
					try DocumentEditor.setText(in: &presentation, at: componentPath, to: text)
				} else if let rtf {
					try DocumentEditor.setRTF(in: &presentation, at: componentPath, data: Data(rtf.utf8))
				} else {
					let data = try Data(contentsOf: URL(fileURLWithPath: required(rtfFile, option: "rtf-file")))
					try DocumentEditor.setRTF(in: &presentation, at: componentPath, data: data)
				}
			}
			return [.init(kind: .affected, path: affectedPath)]

		case "set-background":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.setBackground(
					in: &presentation,
					at: componentPath,
					color: DocumentEditor.color(hex: required(color, option: "color")),
				)
			}
			return [.init(kind: .affected, path: affectedPath)]

		case "set-media":
			guard (source == nil) != (fromPlaylist == nil) else {
				throw ValidationError("Provide exactly one of source or from-playlist.")
			}
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPathContext = try EditMediaPathContext(path: componentPath, in: document)
			if let source {
				guard playlist == nil, item == nil else { throw ValidationError("playlist and item require from-playlist.") }
				try DocumentEditor.setMedia(
					&document,
					at: componentPath,
					sourceURL: URL(fileURLWithPath: source),
					preserveUUID: preserveUUID == true,
					syncLabel: syncLabel == true,
				)
			} else {
				guard preserveUUID != true else {
					throw ValidationError("preserve-uuid cannot be combined with from-playlist.")
				}
				let selection = try PlaylistMediaSource.select(
					from: URL(fileURLWithPath: required(fromPlaylist, option: "from-playlist")),
					playlist: required(playlist, option: "playlist"),
					item: required(item, option: "item"),
				)
				try DocumentEditor.setMedia(&document, at: componentPath, to: selection.media, syncLabel: syncLabel == true)
			}
			return try [.init(kind: .affected, path: affectedPathContext.resolvedPath(in: document))]

		case "add-element":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let parentPath = try canonicalPath(componentPath, in: document)
			let createdUUID = try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.addElement(
					to: &presentation,
					at: componentPath,
					name: required(name, option: "name"),
					bounds: DocumentEditor.rect(required(bounds, option: "bounds")),
					color: DocumentEditor.color(hex: required(color, option: "color")),
				)
			}
			let createdPath = try canonicalPath(
				ComponentPath("\(parentPath)/elements[uuid=\(createdUUID)]/element"),
				in: document,
			)
			return [
				.init(kind: .affected, path: parentPath),
				.init(kind: .created, path: createdPath),
			]

		case "add-action":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let cuePath = try canonicalPath(componentPath, in: document)
			let createdUUID = try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.addAction(
					in: &presentation,
					to: componentPath,
					type: required(type, option: "type"),
					name: name,
				)
			}
			let createdPath = try canonicalPath(ComponentPath("\(cuePath)/actions[uuid=\(createdUUID)]"), in: document)
			return [
				.init(kind: .affected, path: cuePath),
				.init(kind: .created, path: createdPath),
			]

		case "remove-action":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let removedPath = try canonicalPath(componentPath, in: document)
			try applyToPresentation(&document, command: command) { presentation in
				try DocumentEditor.removeAction(in: &presentation, at: componentPath)
			}
			return [.init(kind: .removed, path: removedPath)]

		case "add-template":
			guard case var .theme(themeDocument) = document.payload else {
				throw ValidationError("edit add-template requires a Theme document.")
			}
			let createdUUID = try DocumentEditor.addTemplate(to: &themeDocument, name: required(name, option: "name"))
			document.payload = .theme(themeDocument)
			let createdPath = try canonicalPath(ComponentPath("/slides[uuid=\(createdUUID)]"), in: document)
			return [.init(kind: .created, path: createdPath)]

		case "add-playlist-item":
			guard case var .playlist(playlist) = document.payload else {
				throw ValidationError("edit add-playlist-item requires a playlist document.")
			}
			let createdCandidatePath = try DocumentEditor.addPlaylistItem(
				to: &playlist,
				at: ComponentPath(path ?? "/root_node"),
				type: required(type, option: "type"),
				name: required(name, option: "name"),
				documentURL: documentPath.map { URL(fileURLWithPath: $0) },
			)
			document.payload = .playlist(playlist)
			let createdPath = try canonicalPath(ComponentPath(createdCandidatePath), in: document)
			return [.init(kind: .created, path: createdPath)]

		case "set-playlist-item-hidden":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			guard let hidden else { throw ValidationError("Missing required option hidden.") }
			try DocumentEditor.setPlaylistItemHidden(&document, at: componentPath, hidden: hidden)
			return [.init(kind: .affected, path: affectedPath)]

		case "link-planning-center-item":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try DocumentEditor.linkPlanningCenterItem(
				&document,
				at: componentPath,
				to: URL(fileURLWithPath: required(documentPath, option: "document")),
			)
			return [.init(kind: .affected, path: affectedPath)]

		case "unlink-planning-center-item":
			let componentPath = try ComponentPath(required(path, option: "path"))
			let affectedPath = try canonicalPath(componentPath, in: document)
			try DocumentEditor.unlinkPlanningCenterItem(&document, at: componentPath)
			return [.init(kind: .affected, path: affectedPath)]

		default:
			preconditionFailure("Unsupported batch command was decoded.")
		}
	}

	private func required(_ value: String?, option: String) throws -> String {
		guard let value else { throw ValidationError("Missing required option \(option).") }
		return value
	}

	private func requiredSingle(_ values: [String]?, option: String) throws -> String {
		guard let values, values.count == 1, let value = values.first else {
			throw ValidationError("Option \(option) must have exactly one value.")
		}
		return value
	}

	private func actionPolicy(_ value: String?) throws -> TemplateActionPolicy {
		guard let value else { return .preserve }
		guard let policy = TemplateActionPolicy(rawValue: value) else {
			throw ValidationError("template-actions must be preserve, append, or replace.")
		}
		return policy
	}

	private func applyToPresentation<Result>(
		_ document: inout ProPresenterDocument,
		command: String,
		operation: (inout Rv_Data_Presentation) throws -> Result,
	) throws -> Result {
		guard case var .presentation(presentation) = document.payload else {
			throw ValidationError("edit \(command) requires a presentation document.")
		}
		let result = try operation(&presentation)
		document.payload = .presentation(presentation)
		return result
	}

	private static let allowedOptions: [String: Set<String>] = [
		"patch": ["path", "json", "json-file", "allow-url-only"],
		"add-slide": ["group", "after", "theme", "theme-document", "template", "include-template-actions", "duplicate"],
		"add-cue-group": ["name", "cue", "empty", "color", "after"],
		"set-cue-group-cues": ["path", "cue", "empty", "transfer", "leave-omitted-ungrouped"],
		"move-cue-to-group": ["path", "group", "after", "first"],
		"set-cue-group-color": ["path", "color", "clear"],
		"set-cue-group-hotkey": ["path", "code", "control-identifier", "clear"],
		"duplicate-cue-group": ["path", "name"],
		"remove-cue-group": ["path", "delete-cues", "leave-cues-ungrouped", "move-cues-to", "remove-from-arrangements"],
		"add-arrangement": ["name", "group", "empty", "select"],
		"set-arrangement-groups": ["path", "group", "empty"],
		"select-arrangement": ["path"],
		"clear-selected-arrangement": [],
		"apply-template": ["path", "theme", "theme-document", "template", "template-actions"],
		"rename": ["path", "name"],
		"duplicate": ["path"],
		"remove": ["path"],
		"move": ["path", "after"],
		"set-text": ["path", "text", "rtf", "rtf-file"],
		"set-background": ["path", "color"],
		"set-media": ["path", "source", "from-playlist", "playlist", "item", "preserve-uuid", "sync-label"],
		"add-element": ["path", "name", "bounds", "color"],
		"add-action": ["path", "type", "name"],
		"remove-action": ["path"],
		"add-template": ["name"],
		"add-playlist-item": ["path", "type", "name", "document"],
		"set-playlist-item-hidden": ["path", "hidden"],
		"link-planning-center-item": ["path", "document"],
		"unlink-planning-center-item": ["path"],
	]
}

private struct BatchEditCodingKey: CodingKey {
	let stringValue: String
	let intValue: Int? = nil

	init(_ stringValue: String) {
		self.stringValue = stringValue
	}

	init?(stringValue: String) {
		self.init(stringValue)
	}

	init?(intValue: Int) {
		nil
	}
}
