import ArgumentParser
import Foundation
import ProCRUDCore
import ProPresenterProto

// make sure that any update to edit commands are reflected in the EditApply syntax as well

struct Edit: ParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Edit a raw or bundled ProPresenter document.",
		subcommands: [EditApply.self, EditApplyTemplate.self, EditSetMediaBatch.self, EditPatch.self, EditAddSlide.self, EditAddCueGroup.self, EditSetCueGroupCues.self, EditMoveCueToGroup.self, EditSetCueGroupColor.self, EditSetCueGroupHotKey.self, EditDuplicateCueGroup.self, EditRemoveCueGroup.self, EditAddArrangement.self, EditSetArrangementGroups.self, EditSelectArrangement.self, EditClearSelectedArrangement.self, EditRename.self, EditDuplicate.self, EditRemove.self, EditMove.self, EditSetText.self, EditSetBackground.self, EditSetMedia.self, EditAddElement.self, EditAddAction.self, EditRemoveAction.self, EditAddTemplate.self, EditAddPlaylistItem.self, EditSetPlaylistItemHidden.self, EditLinkPlanningCenterItem.self, EditUnlinkPlanningCenterItem.self],
	)
}

struct EditApplyTemplate: ParsableCommand {
	enum ActionPolicy: String, ExpressibleByArgument {
		case preserve
		case append
		case replace

		var coreValue: TemplateActionPolicy {
			switch self {
			case .preserve: .preserve
			case .append: .append
			case .replace: .replace
			}
		}
	}

	static let configuration = CommandConfiguration(
		commandName: "apply-template",
		abstract: "Resolve a Theme template onto an existing presentation cue.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue component path, such as /cues[index=0].") var path: String
	@Option(help: "Theme file, theme directory, or .proTheme archive.") var theme: String
	@Option(help: "Archive-relative Theme payload path when a theme archive contains multiple documents.") var themeDocument: String?
	@Option(help: "Exact template name, UUID path, or source path.") var template: String?
	@Option(help: "Template action policy: preserve, append, or replace.") var templateActions: ActionPolicy = .preserve
	@Flag(help: "Describe resolution as JSON without writing any document.") var dryRun = false
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		if dryRun, output != nil || replace {
			throw ValidationError("--dry-run cannot be combined with --output or --replace.")
		}
		let candidate = try ThemeTemplateSource.select(
			ThemeTemplateSource.candidates(
				from: URL(fileURLWithPath: theme),
				themeDocument: themeDocument,
			),
			named: template,
		)
		let inputURL = URL(fileURLWithPath: input)
		let session = try DocumentEditSession.open(inputURL)
		guard case var .presentation(presentation) = session.document.payload else {
			throw ValidationError("edit apply-template requires a presentation document.")
		}
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: session.document)
		var report = try DocumentEditor.applyTemplate(
			in: &presentation,
			at: componentPath,
			template: candidate.slide,
			actionPolicy: templateActions.coreValue,
		)
		report.warnings.append(contentsOf: candidate.mediaWarnings)
		report.warnings = Array(Set(report.warnings)).sorted()
		if dryRun {
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
			var data = try encoder.encode(report)
			data.append(0x0A)
			FileHandle.standardOutput.write(data)
			return
		}

		session.document.payload = .presentation(presentation)
		let destination = output.map(URL.init(fileURLWithPath:)) ?? inputURL
		for warning in report.warnings {
			print("Warning [template \(candidate.name)]: \(warning)")
		}
		try withExtendedLifetime(candidate) {
			try session.write(
				to: destination,
				replace: output == nil || replace,
				materializingTemplateMediaURLs: candidate.preferredAbsoluteMediaURLs,
			)
		}
		printEditPathOutputs([.init(kind: .affected, path: affectedPath)])
		print("Wrote: \(destination.path)")
	}
}

private protocol PresentationEditCommand: ParsableCommand {
	var input: String { get }
	var output: String? { get }
	var replace: Bool { get }
	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput]
}

private extension PresentationEditCommand {
	func runPresentationEdit() throws {
		let inputURL = URL(fileURLWithPath: input)
		let session = try DocumentEditSession.open(inputURL)
		guard case var .presentation(presentation) = session.document.payload else {
			throw ValidationError("This edit requires a presentation document.")
		}
		let results = try apply(to: &presentation)
		session.document.payload = .presentation(presentation)
		let destination = output.map(URL.init(fileURLWithPath:)) ?? inputURL
		try session.write(to: destination, replace: output == nil || replace)
		printEditPathOutputs(results)
		print("Wrote: \(destination.path)")
	}
}

private protocol StructuralEditCommand: ParsableCommand {
	var input: String { get }
	var output: String? { get }
	var replace: Bool { get }
	func apply(to document: inout ProPresenterDocument) throws -> [EditPathOutput]
}

private extension StructuralEditCommand {
	func runStructuralEdit() throws {
		let inputURL = URL(fileURLWithPath: input)
		let session = try DocumentEditSession.open(inputURL)
		let results = try apply(to: &session.document)
		let destination = output.map(URL.init(fileURLWithPath:)) ?? inputURL
		try session.write(to: destination, replace: output == nil || replace)
		printEditPathOutputs(results)
		print("Wrote: \(destination.path)")
	}
}

struct EditRename: StructuralEditCommand {
	static let configuration = CommandConfiguration(commandName: "rename", abstract: "Rename a presentation cue, cue group, or arrangement, theme template, or playlist component.")
	@Argument(help: "Path to a raw or bundled ProPresenter document.") var input: String
	@Option(help: "Component path.") var path: String
	@Option(help: "New component name.") var name: String
	@Option(help: "Write to a new document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runStructuralEdit()
	}

	func apply(to document: inout ProPresenterDocument) throws -> [EditPathOutput] {
		let path = try ComponentPath(path)
		let canonical = try canonicalPath(path, in: document)
		try DocumentEditor.rename(&document, at: path, to: name)
		return [.init(kind: .affected, path: canonical)]
	}
}

struct EditDuplicate: StructuralEditCommand {
	static let configuration = CommandConfiguration(commandName: "duplicate", abstract: "Duplicate a presentation cue, cue group, or arrangement, theme template, or playlist component.")
	@Argument(help: "Path to a raw or bundled ProPresenter document.") var input: String
	@Option(help: "Component path.") var path: String
	@Option(help: "Write to a new document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runStructuralEdit()
	}

	func apply(to document: inout ProPresenterDocument) throws -> [EditPathOutput] {
		let path = try ComponentPath(path)
		let sourcePath = try canonicalPath(path, in: document)
		let createdUUID = try DocumentEditor.duplicate(&document, at: path)
		let createdPath = try canonicalCreatedSiblingPath(sourcePath: sourcePath, uuid: createdUUID, in: document)
		return [
			.init(kind: .affected, path: sourcePath),
			.init(kind: .created, path: createdPath),
		]
	}
}

struct EditRemove: StructuralEditCommand {
	static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a presentation cue, empty cue group, or arrangement, theme template, or playlist component.")
	@Argument(help: "Path to a raw or bundled ProPresenter document.") var input: String
	@Option(help: "Component path.") var path: String
	@Option(help: "Write to a new document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runStructuralEdit()
	}

	func apply(to document: inout ProPresenterDocument) throws -> [EditPathOutput] {
		let path = try ComponentPath(path)
		let canonical = try canonicalPath(path, in: document)
		try DocumentEditor.remove(&document, at: path)
		return [.init(kind: .removed, path: canonical)]
	}
}

struct EditMove: StructuralEditCommand {
	static let configuration = CommandConfiguration(commandName: "move", abstract: "Move a presentation cue, cue group, or arrangement, theme template, or playlist component after a sibling.")
	@Argument(help: "Path to a raw or bundled ProPresenter document.") var input: String
	@Option(help: "Component path.") var path: String
	@Option(help: "Sibling component path after which to place the selected component.") var after: String
	@Option(help: "Write to a new document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runStructuralEdit()
	}

	func apply(to document: inout ProPresenterDocument) throws -> [EditPathOutput] {
		let path = try ComponentPath(path)
		let afterPath = try ComponentPath(after)
		let outputPath = try EditMovePathContext(source: path, after: afterPath, in: document)
		try DocumentEditor.move(&document, at: path, after: afterPath)
		let affectedPath = try outputPath.resolvedPath(in: document)
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditSetText: PresentationEditCommand {
	static let configuration = CommandConfiguration(commandName: "set-text", abstract: "Set a text element from plain text or styled RTF.")
	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Full component path ending in /element/text.") var path: String
	@Option(help: "Plain text to write as uniform RTF using the element's base style.") var text: String?
	@Option(help: "Inline Cocoa RTF, preserving its mixed styling.") var rtf: String?
	@Option(help: "Path to a Cocoa RTF file, preserving its mixed styling.") var rtfFile: String?
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		let sources = [text != nil, rtf != nil, rtfFile != nil].count(where: { $0 })
		guard sources == 1 else {
			throw ValidationError("Provide exactly one of --text, --rtf, or --rtf-file.")
		}
		let path = try ComponentPath(path)
		let canonical = try canonicalPath(path, in: presentation)
		if let text {
			try DocumentEditor.setText(in: &presentation, at: path, to: text)
		} else if let rtf {
			try DocumentEditor.setRTF(in: &presentation, at: path, data: Data(rtf.utf8))
		} else if let rtfFile {
			try DocumentEditor.setRTF(
				in: &presentation,
				at: path,
				data: Data(contentsOf: URL(fileURLWithPath: rtfFile)),
			)
		}
		return [.init(kind: .affected, path: canonical)]
	}
}

struct EditSetBackground: PresentationEditCommand {
	static let configuration = CommandConfiguration(commandName: "set-background", abstract: "Set a presentation slide's background color.")
	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Full component path ending in /base_slide.") var path: String
	@Option(help: "Background RGB color as #RRGGBB.") var color: String
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		let path = try ComponentPath(path)
		let canonical = try canonicalPath(path, in: presentation)
		try DocumentEditor.setBackground(in: &presentation, at: path, color: DocumentEditor.color(hex: color))
		return [.init(kind: .affected, path: canonical)]
	}
}

struct EditSetMedia: StructuralEditCommand {
	static let configuration = CommandConfiguration(commandName: "set-media", abstract: "Replace a presentation or theme media fill with a complete media identity.")
	@Argument(help: "Path to a raw or bundled presentation or Theme document.") var input: String
	@Option(help: "Presentation media action or presentation/theme slide element media path.") var path: String
	@Option(help: "Local image, video, or audio file. Creates a new media UUID by default.") var source: String?
	@Option(help: "Media playlist document, workspace, or .proPlaylist archive from which to copy canonical media.") var fromPlaylist: String?
	@Option(help: "Playlist name used with --from-playlist.") var playlist: String?
	@Option(help: "Media item name used with --from-playlist.") var item: String?
	@Flag(help: "Keep the target's existing media UUID. Use only for path relocation of the same asset.") var preserveUUID = false
	@Flag(help: "Update a media action label only when it exactly matches the old media filename.") var syncLabel = false
	@Option(help: "Write to a new document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runStructuralEdit()
	}

	func apply(to document: inout ProPresenterDocument) throws -> [EditPathOutput] {
		guard (source == nil) != (fromPlaylist == nil) else {
			throw ValidationError("Provide exactly one of --source or --from-playlist.")
		}
		let componentPath = try ComponentPath(path)
		let affectedPathContext = try EditMediaPathContext(path: componentPath, in: document)
		if let source {
			guard playlist == nil, item == nil else {
				throw ValidationError("--playlist and --item require --from-playlist.")
			}
			try DocumentEditor.setMedia(
				&document,
				at: componentPath,
				sourceURL: URL(fileURLWithPath: source),
				preserveUUID: preserveUUID,
				syncLabel: syncLabel,
			)
		} else if let fromPlaylist {
			guard !preserveUUID else {
				throw ValidationError("--preserve-uuid cannot be combined with --from-playlist; playlist media keeps its canonical UUID.")
			}
			guard let playlist, let item else {
				throw ValidationError("--from-playlist requires --playlist and --item.")
			}
			let selection = try PlaylistMediaSource.select(
				from: URL(fileURLWithPath: fromPlaylist),
				playlist: playlist,
				item: item,
			)
			try DocumentEditor.setMedia(&document, at: componentPath, to: selection.media, syncLabel: syncLabel)
		}
		return try [.init(kind: .affected, path: affectedPathContext.resolvedPath(in: document))]
	}
}

struct EditAddElement: PresentationEditCommand {
	static let configuration = CommandConfiguration(commandName: "add-element", abstract: "Add a colored rectangular element to a presentation slide.")
	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Full component path ending in /base_slide.") var path: String
	@Option(help: "Element name.") var name: String
	@Option(help: "Bounds as x,y,width,height in slide coordinates.") var bounds: String
	@Option(help: "Fill RGB color as #RRGGBB.") var color: String
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		let path = try ComponentPath(path)
		let parentPath = try canonicalPath(path, in: presentation)
		let createdUUID = try DocumentEditor.addElement(
			to: &presentation,
			at: path,
			name: name,
			bounds: DocumentEditor.rect(bounds),
			color: DocumentEditor.color(hex: color),
		)
		let createdPath = try canonicalPath(
			ComponentPath("\(parentPath)/elements[uuid=\(createdUUID)]/element"),
			in: presentation,
		)
		return [
			.init(kind: .affected, path: parentPath),
			.init(kind: .created, path: createdPath),
		]
	}
}

struct EditAddAction: PresentationEditCommand {
	static let configuration = CommandConfiguration(commandName: "add-action", abstract: "Add a typed action to a presentation cue.")
	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue component path.") var path: String
	@Option(help: "Action type: media, background-media, foreground-media, timer, macro, clear, or presentation-slide.") var type: String
	@Option(help: "Optional action name.") var name: String?
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		let path = try ComponentPath(path)
		let cuePath = try canonicalPath(path, in: presentation)
		let createdUUID = try DocumentEditor.addAction(in: &presentation, to: path, type: type, name: name)
		let createdPath = try canonicalPath(
			ComponentPath("\(cuePath)/actions[uuid=\(createdUUID)]"),
			in: presentation,
		)
		return [
			.init(kind: .affected, path: cuePath),
			.init(kind: .created, path: createdPath),
		]
	}
}

struct EditRemoveAction: PresentationEditCommand {
	static let configuration = CommandConfiguration(commandName: "remove-action", abstract: "Remove a selected presentation cue action.")
	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Action component path.") var path: String
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false
	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		let path = try ComponentPath(path)
		let canonical = try canonicalPath(path, in: presentation)
		try DocumentEditor.removeAction(in: &presentation, at: path)
		return [.init(kind: .removed, path: canonical)]
	}
}

struct EditAddTemplate: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "add-template", abstract: "Add a blank template slide to a Theme document.")
	@Argument(help: "Path to a raw Theme or .proTheme document.") var input: String
	@Option(help: "Template name.") var name: String
	@Option(help: "Write to a new theme document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		let inputURL = URL(fileURLWithPath: input)
		let session = try DocumentEditSession.open(inputURL)
		guard case var .theme(theme) = session.document.payload else { throw ValidationError("edit add-template requires a Theme document.") }
		let createdUUID = DocumentEditor.addTemplate(to: &theme, name: name)
		session.document.payload = .theme(theme)
		let createdPath = try canonicalPath(ComponentPath("/slides[uuid=\(createdUUID)]"), in: session.document)
		let destination = output.map(URL.init(fileURLWithPath:)) ?? inputURL
		try session.write(to: destination, replace: output == nil || replace)
		printEditPathOutputs([.init(kind: .created, path: createdPath)])
		print("Wrote: \(destination.path)")
	}
}

struct EditAddPlaylistItem: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "add-playlist-item", abstract: "Add a typed item to a playlist.")
	@Argument(help: "Path to a raw data or .proPlaylist document.") var input: String
	@Option(help: "Playlist parent Component Reference.") var path: String = "/root_node"
	@Option(help: "Item type: header or presentation.") var type: String
	@Option(help: "Playlist item name.") var name: String
	@Option(help: "Raw presentation path for a presentation item.") var document: String?
	@Option(help: "Write to a new playlist document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		let inputURL = URL(fileURLWithPath: input)
		let session = try DocumentEditSession.open(inputURL)
		guard case var .playlist(playlist) = session.document.payload else { throw ValidationError("edit add-playlist-item requires a playlist document.") }
		let createdCandidatePath = try DocumentEditor.addPlaylistItem(
			to: &playlist,
			at: ComponentPath(path),
			type: type,
			name: name,
			documentURL: document.map(URL.init(fileURLWithPath:)),
		)
		session.document.payload = .playlist(playlist)
		let createdPath = try canonicalPath(ComponentPath(createdCandidatePath), in: session.document)
		let destination = output.map(URL.init(fileURLWithPath:)) ?? inputURL
		try session.write(to: destination, replace: output == nil || replace)
		printEditPathOutputs([.init(kind: .created, path: createdPath)])
		print("Wrote: \(destination.path)")
	}
}

struct EditSetPlaylistItemHidden: StructuralEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-playlist-item-hidden",
		abstract: "Set a playlist item's local hidden state, including a Planning Center item.",
	)

	@Argument(help: "Path to a raw data or .proPlaylist document.") var input: String
	@Option(help: "Playlist item Component Reference.") var path: String
	@Flag(help: "Hide the selected playlist item.") var hidden = false
	@Flag(help: "Show the selected playlist item.") var visible = false
	@Option(help: "Write to a new playlist document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runStructuralEdit()
	}

	func apply(to document: inout ProPresenterDocument) throws -> [EditPathOutput] {
		guard hidden != visible else {
			throw ValidationError("Provide exactly one of --hidden or --visible.")
		}
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: document)
		try DocumentEditor.setPlaylistItemHidden(&document, at: componentPath, hidden: hidden)
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditLinkPlanningCenterItem: StructuralEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "link-planning-center-item",
		abstract: "Link an unlinked Planning Center item to a local presentation.",
	)

	@Argument(help: "Path to a raw data or .proPlaylist document.") var input: String
	@Option(help: "Planning Center playlist item Component Reference.") var path: String
	@Option(help: "Raw local .pro presentation to link.") var document: String
	@Option(help: "Write to a new playlist document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runStructuralEdit()
	}

	func apply(to documentValue: inout ProPresenterDocument) throws -> [EditPathOutput] {
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: documentValue)
		try DocumentEditor.linkPlanningCenterItem(
			&documentValue,
			at: componentPath,
			to: URL(fileURLWithPath: document),
		)
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditUnlinkPlanningCenterItem: StructuralEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "unlink-planning-center-item",
		abstract: "Unlink local content while retaining its Planning Center item.",
	)

	@Argument(help: "Path to a raw data or .proPlaylist document.") var input: String
	@Option(help: "Planning Center playlist item Component Reference.") var path: String
	@Option(help: "Write to a new playlist document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runStructuralEdit()
	}

	func apply(to document: inout ProPresenterDocument) throws -> [EditPathOutput] {
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: document)
		try DocumentEditor.unlinkPlanningCenterItem(&document, at: componentPath)
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditAddCueGroup: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "add-cue-group",
		abstract: "Add a cue group to a presentation.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue-group name. Duplicate and empty names are valid; UUID paths remain authoritative.") var name: String
	@Option(help: "Cue component path. Repeat to define the group's native cue order; cues are transferred from their current groups.") var cue: [String] = []
	@Flag(help: "Create an empty cue group. Use instead of --cue.") var empty = false
	@Option(help: "Cue-group RGB color as #RRGGBB.") var color: String?
	@Option(help: "Cue-group component path after which to insert the new group. Without it, append.") var after: String?
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		guard empty || !cue.isEmpty else {
			throw ValidationError("Provide one or more --cue values, or use --empty.")
		}
		guard !empty || cue.isEmpty else {
			throw ValidationError("--empty cannot be combined with --cue.")
		}
		let createdUUID = try DocumentEditor.addCueGroup(
			to: &presentation,
			name: name,
			color: color.map(DocumentEditor.color(hex:)),
			cuePaths: cue.map(ComponentPath.init),
			after: after.map(ComponentPath.init),
		)
		let createdPath = try canonicalPath(ComponentPath("/cue_groups[uuid=\(createdUUID)]"), in: presentation)
		return [.init(kind: .created, path: createdPath)]
	}
}

struct EditSetCueGroupCues: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-cue-group-cues",
		abstract: "Replace a cue group's ordered cue references.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue-group component path.") var path: String
	@Option(help: "Cue component path. Repeat to preserve native order.") var cue: [String] = []
	@Flag(help: "Set the cue group to an empty cue sequence.") var empty = false
	@Flag(help: "Transfer selected cues out of their current groups instead of rejecting shared ownership.") var transfer = false
	@Flag(help: "Allow cues omitted from the replacement sequence to remain ungrouped at the end of Master order.") var leaveOmittedUngrouped = false
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		guard empty || !cue.isEmpty else {
			throw ValidationError("Provide one or more --cue values, or use --empty.")
		}
		guard !empty || cue.isEmpty else {
			throw ValidationError("--empty cannot be combined with --cue.")
		}
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: presentation)
		try DocumentEditor.setCueGroupCues(
			in: &presentation,
			at: componentPath,
			cuePaths: cue.map(ComponentPath.init),
			ownershipPolicy: transfer ? .transferFromOtherGroups : .requireUnassignedOrSameGroup,
			omittedCuePolicy: leaveOmittedUngrouped ? .leaveUngrouped : .reject,
		)
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditMoveCueToGroup: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "move-cue-to-group",
		abstract: "Transfer a cue to a cue group.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue component path to transfer.") var path: String
	@Option(help: "Destination cue-group component path.") var group: String
	@Option(help: "Destination-group cue path after which to insert the cue. Without it, append.") var after: String?
	@Flag(help: "Insert the cue first in the destination group.") var first = false
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		guard !first || after == nil else { throw ValidationError("--first cannot be combined with --after.") }
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: presentation)
		let insertion: DocumentEditor.CueGroupCueInsertion = if first {
			.start
		} else if let after {
			try .after(ComponentPath(after))
		} else {
			.end
		}
		try DocumentEditor.moveCueToGroup(
			in: &presentation,
			at: componentPath,
			groupPath: ComponentPath(group),
			insertion: insertion,
		)
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditSetCueGroupColor: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-cue-group-color",
		abstract: "Set or clear a presentation cue-group color.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue-group component path.") var path: String
	@Option(help: "Cue-group RGB color as #RRGGBB.") var color: String?
	@Flag(help: "Clear the cue-group color.") var clear = false
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		guard (color != nil) != clear else { throw ValidationError("Provide exactly one of --color or --clear.") }
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: presentation)
		try DocumentEditor.setCueGroupColor(
			in: &presentation,
			at: componentPath,
			to: color.map(DocumentEditor.color(hex:)),
		)
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditSetCueGroupHotKey: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-cue-group-hotkey",
		abstract: "Set or clear a presentation cue-group hot key.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue-group component path.") var path: String
	@Option(help: "Key code such as ansiV, ansi-v, KEY_CODE_ANSI_V, V, or raw value 22.") var code: HotKeyCodeArgument?
	@Option(help: "Optional ProPresenter control identifier. Use only with --code.") var controlIdentifier: String?
	@Flag(help: "Reset to a present, empty hot key.") var clear = false
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		guard (code != nil) != clear else {
			throw ValidationError("Provide exactly one of --code or --clear.")
		}
		guard code != nil || controlIdentifier == nil else {
			throw ValidationError("--control-identifier requires --code.")
		}
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: presentation)
		if clear {
			try DocumentEditor.clearCueGroupHotKey(in: &presentation, at: componentPath)
		} else if let code {
			try DocumentEditor.setCueGroupHotKey(
				in: &presentation,
				at: componentPath,
				code: code.value,
				controlIdentifier: controlIdentifier ?? "",
			)
		}
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditDuplicateCueGroup: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "duplicate-cue-group",
		abstract: "Deep-copy a cue group and its owned cue graphs without changing arrangements.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue-group component path.") var path: String
	@Option(help: "Optional name for the copied group. Without it, preserve the source group label and application-group link.") var name: String?
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		let componentPath = try ComponentPath(path)
		let sourcePath = try canonicalPath(componentPath, in: presentation)
		let createdUUID = try DocumentEditor.duplicateCueGroup(in: &presentation, at: componentPath, name: name)
		let createdPath = try canonicalPath(ComponentPath("/cue_groups[uuid=\(createdUUID)]"), in: presentation)
		return [
			.init(kind: .affected, path: sourcePath),
			.init(kind: .created, path: createdPath),
		]
	}
}

struct EditRemoveCueGroup: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "remove-cue-group",
		abstract: "Remove a cue group with explicit cue and arrangement-reference policies.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue-group component path.") var path: String
	@Flag(help: "Delete cues owned by the group; fails when retained cues or the timeline reference them.") var deleteCues = false
	@Flag(help: "Leave the group's cues ungrouped at the end of Master order.") var leaveCuesUngrouped = false
	@Option(help: "Move the group's cues to this cue-group path before removal.") var moveCuesTo: String?
	@Flag(help: "Remove every occurrence of the group from every arrangement.") var removeFromArrangements = false
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		let cuePolicyCount = [deleteCues, leaveCuesUngrouped, moveCuesTo != nil].count(where: { $0 })
		guard cuePolicyCount <= 1 else {
			throw ValidationError("Choose only one of --delete-cues, --leave-cues-ungrouped, or --move-cues-to.")
		}
		let cuePolicy: CueGroupCueRemovalPolicy = if deleteCues {
			.deleteOwnedCues
		} else if leaveCuesUngrouped {
			.leaveUngrouped
		} else if let moveCuesTo {
			try .moveCues(to: ComponentPath(moveCuesTo))
		} else {
			.rejectNonempty
		}
		let componentPath = try ComponentPath(path)
		let removedPath = try canonicalPath(componentPath, in: presentation)
		try DocumentEditor.removeCueGroup(
			in: &presentation,
			at: componentPath,
			cuePolicy: cuePolicy,
			arrangementPolicy: removeFromArrangements ? .removeAllOccurrences : .rejectReferences,
		)
		return [.init(kind: .removed, path: removedPath)]
	}
}

struct EditAddArrangement: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "add-arrangement",
		abstract: "Add an arrangement to a presentation.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Arrangement name.") var name: String
	@Option(help: "Cue-group component path. Repeat to define the arrangement sequence, including repeated groups.") var group: [String] = []
	@Flag(help: "Create an empty arrangement. Without --group or --empty, all native cue groups are used once.") var empty = false
	@Flag(help: "Select the new arrangement in the presentation.") var select = false
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		guard !empty || group.isEmpty else {
			throw ValidationError("--empty cannot be combined with --group.")
		}
		let groupPaths: [ComponentPath]? = if empty {
			[ComponentPath]()
		} else if group.isEmpty {
			nil
		} else {
			try group.map(ComponentPath.init)
		}
		let createdUUID = try DocumentEditor.addArrangement(
			to: &presentation,
			name: name,
			groupPaths: groupPaths,
			select: select,
		)
		let createdPath = try canonicalPath(ComponentPath("/arrangements[uuid=\(createdUUID)]"), in: presentation)
		return [.init(kind: .created, path: createdPath)]
	}
}

struct EditSetArrangementGroups: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-arrangement-groups",
		abstract: "Replace an arrangement's ordered cue-group sequence.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Arrangement component path.") var path: String
	@Option(help: "Cue-group component path. Repeat to preserve sequence and repetitions.") var group: [String] = []
	@Flag(help: "Set the arrangement to an empty sequence.") var empty = false
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		guard empty || !group.isEmpty else {
			throw ValidationError("Provide one or more --group values, or use --empty.")
		}
		guard !empty || group.isEmpty else {
			throw ValidationError("--empty cannot be combined with --group.")
		}
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: presentation)
		try DocumentEditor.setArrangementGroups(
			in: &presentation,
			at: componentPath,
			groupPaths: group.map(ComponentPath.init),
		)
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditSelectArrangement: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "select-arrangement",
		abstract: "Select an arrangement in a presentation.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Arrangement component path.") var path: String
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		let componentPath = try ComponentPath(path)
		let affectedPath = try canonicalPath(componentPath, in: presentation)
		try DocumentEditor.selectArrangement(in: &presentation, at: componentPath)
		return [.init(kind: .affected, path: affectedPath)]
	}
}

struct EditClearSelectedArrangement: PresentationEditCommand {
	static let configuration = CommandConfiguration(
		commandName: "clear-selected-arrangement",
		abstract: "Clear the stored arrangement selection so the presentation uses Master order.",
	)

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		try runPresentationEdit()
	}

	func apply(to presentation: inout Rv_Data_Presentation) throws -> [EditPathOutput] {
		DocumentEditor.clearSelectedArrangement(in: &presentation)
		return [.init(kind: .affected, path: "/selected_arrangement")]
	}
}

struct EditAddSlide: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "add-slide", abstract: "Add a blank presentation slide to a cue group.")

	@Argument(help: "Path to a raw .pro or .probundle presentation.") var input: String
	@Option(help: "Cue-group component path.") var group: String
	@Option(help: "Cue component path after which to insert the new slide.") var after: String?
	@Option(help: "Theme file, theme directory, or .proTheme archive used for the new slide.") var theme: String?
	@Option(help: "Archive-relative Theme payload path when a theme archive contains multiple documents.") var themeDocument: String?
	@Option(help: "Exact template name or source path when the theme contains multiple templates.") var template: String?
	@Flag(help: "Copy the selected template's actions into the new cue.") var includeTemplateActions = false
	@Option(help: "Existing cue component path to duplicate as the new slide.") var duplicate: String?
	@Option(help: "Write to a new presentation of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		let inputURL = URL(fileURLWithPath: input)
		let session = try DocumentEditSession.open(inputURL)
		guard case var .presentation(presentation) = session.document.payload else {
			throw ValidationError("edit add-slide requires a presentation document.")
		}
		let templateCandidate: ThemeTemplateSource.Candidate?
		if let theme {
			templateCandidate = try ThemeTemplateSource.select(
				ThemeTemplateSource.candidates(
					from: URL(fileURLWithPath: theme),
					themeDocument: themeDocument,
				),
				named: template,
			)
		} else {
			guard template == nil, themeDocument == nil, !includeTemplateActions else {
				throw ValidationError("--template, --theme-document, and --include-template-actions require --theme.")
			}
			templateCandidate = nil
		}
		guard theme == nil || duplicate == nil else { throw ValidationError("Use either --theme or --duplicate, not both.") }
		let existingCueIDs = Set(presentation.cues.map(\.uuid.string))
		let report = try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath(group),
			after: after.map(ComponentPath.init),
			template: templateCandidate?.slide,
			includeTemplateActions: includeTemplateActions,
			duplicateCuePath: duplicate.map(ComponentPath.init),
		)
		session.document.payload = .presentation(presentation)
		guard let createdUUID = presentation.cues.lazy.map(\.uuid.string).first(where: { !existingCueIDs.contains($0) }) else {
			throw ValidationError("edit add-slide did not produce a new cue identity.")
		}
		let createdPath = try canonicalPath(ComponentPath("/cues[uuid=\(createdUUID)]"), in: session.document)
		let destination = output.map(URL.init(fileURLWithPath:)) ?? inputURL
		if let templateCandidate {
			let warnings = templateCandidate.mediaWarnings + (report?.warnings ?? [])
			for warning in Set(warnings).sorted() {
				print("Warning [template \(templateCandidate.name)]: \(warning)")
			}
		}
		try withExtendedLifetime(templateCandidate) {
			try session.write(
				to: destination,
				replace: output == nil || replace,
				materializingTemplateMediaURLs: templateCandidate?.preferredAbsoluteMediaURLs ?? [],
			)
		}
		printEditPathOutputs([.init(kind: .created, path: createdPath)])
		print("Wrote: \(destination.path)")
	}
}

struct EditPatch: ParsableCommand {
	static let configuration = CommandConfiguration(commandName: "patch", abstract: "Apply a protobuf JSON fragment to a raw or bundled document.")

	@Argument(help: "Path to a raw or bundled ProPresenter document.") var input: String
	@Option(help: "Component path to patch.") var path: String
	@Option(help: "Protobuf JSON fragment.") var json: String?
	@Option(help: "Path to a protobuf JSON fragment.") var jsonFile: String?
	@Flag(help: "Allow changing a media URL without replacing its UUID and complete media identity.") var allowURLOnly = false
	@Option(help: "Write to a new document of the same kind.") var output: String?
	@Flag(help: "Replace an existing --output file.") var replace = false

	func run() throws {
		guard (json == nil) != (jsonFile == nil) else {
			throw ValidationError("Specify exactly one of --json or --json-file.")
		}
		let inputURL = URL(fileURLWithPath: input)
		let session = try DocumentEditSession.open(inputURL)
		let jsonData: Data
		if let json {
			jsonData = Data(json.utf8)
		} else if let jsonFile {
			jsonData = try Data(contentsOf: URL(fileURLWithPath: jsonFile))
		} else {
			throw ValidationError("Specify exactly one of --json or --json-file.")
		}
		let componentPath = try ComponentPath(path)
		let affectedPathContext = try EditStablePathContext(path: componentPath, in: session.document)
		try DocumentEditor.patch(
			&session.document,
			at: componentPath,
			jsonData: jsonData,
			allowURLOnly: allowURLOnly,
		)

		let destination = output.map(URL.init(fileURLWithPath:)) ?? inputURL
		try session.write(to: destination, replace: output == nil || replace)
		let affectedPath = try affectedPathContext.resolvedPath(in: session.document)
		printEditPathOutputs([.init(kind: .affected, path: affectedPath)])
		print("Wrote: \(destination.path)")
	}
}
