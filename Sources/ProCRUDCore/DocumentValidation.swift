import Foundation
import ProPresenterProto

public struct DocumentValidationDiagnostic: Codable, Equatable, Sendable, CustomStringConvertible {
	public enum Severity: String, Codable, Sendable {
		case warning
		case error
	}

	public var code: String
	public var severity: Severity
	public var documentPath: String?
	public var componentPath: String
	public var message: String

	public init(
		code: String,
		severity: Severity,
		documentPath: String? = nil,
		componentPath: String,
		message: String,
	) {
		self.code = code
		self.severity = severity
		self.documentPath = documentPath
		self.componentPath = componentPath
		self.message = message
	}

	public init(rendering diagnostic: RenderingDiagnostic) {
		code = diagnostic.code.rawValue
		severity = switch diagnostic.severity {
		case .warning: .warning
		case .error: .error
		}
		documentPath = nil
		componentPath = diagnostic.componentPath
		message = diagnostic.message
	}

	public init(strictMedia diagnostic: StrictMediaDiagnostic) {
		code = "media.\(diagnostic.kind.rawValue)"
		severity = .error
		documentPath = diagnostic.documentPath
		componentPath = diagnostic.componentPath
		message = diagnostic.message
	}

	public var description: String {
		let document = documentPath.map { " in \($0)" } ?? ""
		return "\(severity.rawValue.capitalized) [\(code)]\(document) at \(componentPath): \(message)"
	}
}

public struct DocumentValidationReport: Codable, Equatable, Sendable {
	public var valid: Bool
	public var diagnostics: [DocumentValidationDiagnostic]

	public init(diagnostics: [DocumentValidationDiagnostic]) {
		self.diagnostics = diagnostics.sorted(by: Self.diagnosticOrder)
		valid = !diagnostics.contains { $0.severity == .error }
	}

	private static func diagnosticOrder(
		_ lhs: DocumentValidationDiagnostic,
		_ rhs: DocumentValidationDiagnostic,
	) -> Bool {
		let lhsSeverity = lhs.severity == .error ? 0 : 1
		let rhsSeverity = rhs.severity == .error ? 0 : 1
		if lhsSeverity != rhsSeverity {
			return lhsSeverity < rhsSeverity
		}
		if lhs.documentPath != rhs.documentPath {
			return (lhs.documentPath ?? "") < (rhs.documentPath ?? "")
		}
		if lhs.componentPath != rhs.componentPath {
			return lhs.componentPath < rhs.componentPath
		}
		if lhs.code != rhs.code {
			return lhs.code < rhs.code
		}
		return lhs.message < rhs.message
	}
}

public enum DocumentValidator {
	/// Validates stored document references and, for presentations, includes the
	/// existing rendering diagnostics. Arrangement validation is deliberately
	/// limited to identity references; native cue order remains cue-group based.
	public static func validate(_ document: ProPresenterDocument) -> DocumentValidationReport {
		var diagnostics: [DocumentValidationDiagnostic]
		if case .theme = document.payload, !document.themeEntries.isEmpty {
			diagnostics = document.themeEntries.flatMap { entry in
				themeDiagnostics(entry.document).map { diagnostic in
					var diagnostic = diagnostic
					diagnostic.documentPath = entry.relativePath
					return diagnostic
				}
			}
		} else {
			diagnostics = structuralDiagnostics(in: document)
		}
		switch document.payload {
		case let .presentation(presentation):
			let renderingDocument = PresentationDocument(
				presentation: presentation,
				mediaDirectory: document.resourceDirectory,
				embeddedMediaFiles: document.archiveEntries.isEmpty ? nil : document.embeddedAssetPaths,
			)
			diagnostics.append(contentsOf: renderingDocument.renderingDiagnostics.map(DocumentValidationDiagnostic.init(rendering:)))
		case .theme:
			break
		case .playlist:
			break
		}
		return DocumentValidationReport(diagnostics: diagnostics)
	}

	public static func structuralDiagnostics(in document: ProPresenterDocument) -> [DocumentValidationDiagnostic] {
		switch document.payload {
		case let .presentation(presentation):
			presentationDiagnostics(presentation)
		case let .theme(theme):
			themeDiagnostics(theme)
		case let .playlist(playlist):
			playlistDiagnostics(playlist)
		}
	}

	private static func presentationDiagnostics(
		_ presentation: Rv_Data_Presentation,
	) -> [DocumentValidationDiagnostic] {
		var diagnostics: [DocumentValidationDiagnostic] = []
		if !presentation.hasApplicationInfo {
			diagnostics.append(error(
				code: "structure.missing-application-info",
				path: "/",
				message: "Presentation is missing application info.",
			))
		}
		if !presentation.hasUuid || presentation.uuid.string.isEmpty {
			diagnostics.append(error(
				code: "structure.missing-presentation-uuid",
				path: presentation.hasUuid ? "/uuid" : "/",
				message: "Presentation UUID is missing.",
			))
		}
		if presentation.name.isEmpty {
			diagnostics.append(error(
				code: "structure.missing-presentation-name",
				path: "/",
				message: "Presentation name is missing.",
			))
		}
		if presentation.cues.isEmpty {
			diagnostics.append(error(
				code: "structure.missing-presentation-cues",
				path: "/",
				message: "Presentation contains no cues.",
			))
		}
		if presentation.cueGroups.isEmpty {
			diagnostics.append(error(
				code: "structure.missing-presentation-cue-groups",
				path: "/",
				message: "Presentation contains no cue groups.",
			))
		}

		let cueIDs = presentation.cues.map(\.uuid.string)
		let knownCueIDs = Set(cueIDs.filter { !$0.isEmpty })
		var seenCueIDs = Set<String>()
		for storageIndex in presentation.presentationOrderCueIndices {
			let cue = presentation.cues[storageIndex]
			let path = presentation.componentPath(forCueAtStorageIndex: storageIndex)
			if cue.uuid.string.isEmpty {
				diagnostics.append(error(
					code: "structure.missing-cue-uuid",
					path: path,
					message: "Cue UUID is missing.",
				))
			} else if !seenCueIDs.insert(cue.uuid.string).inserted {
				diagnostics.append(error(
					code: "structure.duplicate-cue-uuid",
					path: path,
					message: "Cue UUID \(cue.uuid.string) is duplicated.",
				))
			}

			var seenActionIDs = Set<String>()
			let actionIDs = cue.actions.map(\.uuid.string)
			for (actionIndex, action) in cue.actions.enumerated() {
				let actionPath = ComponentPathBuilder.repeatedPath(
					parent: path,
					field: "actions",
					storageIndex: actionIndex,
					identities: actionIDs,
				)
				if action.uuid.string.isEmpty {
					diagnostics.append(warning(
						code: "structure.missing-action-uuid",
						path: actionPath,
						message: "Action UUID is missing, so the action cannot be addressed reliably.",
					))
				} else if !seenActionIDs.insert(action.uuid.string).inserted {
					diagnostics.append(warning(
						code: "structure.duplicate-action-uuid",
						path: actionPath,
						message: "Action UUID \(action.uuid.string) is duplicated within the cue.",
					))
				}
			}
		}

		var referencedCueIDs = Set<String>()
		var firstGroupPathByCueID: [String: String] = [:]
		var knownGroupIDs = Set<String>()
		let groupIDs = presentation.cueGroups.map(\.group.uuid.string)
		for (index, cueGroup) in presentation.cueGroups.enumerated() {
			let identifier = cueGroup.group.uuid.string
			let path = ComponentPathBuilder.repeatedPath(
				field: "cue_groups",
				storageIndex: index,
				identities: groupIDs,
			)
			if identifier.isEmpty {
				diagnostics.append(error(
					code: "structure.missing-cue-group-uuid",
					path: path,
					message: "Cue-group UUID is missing.",
				))
			} else if !knownGroupIDs.insert(identifier).inserted {
				diagnostics.append(error(
					code: "structure.duplicate-cue-group-uuid",
					path: path,
					message: "Cue-group UUID \(identifier) is duplicated.",
				))
			}

			var seenReferences = Set<String>()
			for (referenceIndex, cueIdentifier) in cueGroup.cueIdentifiers.enumerated() {
				let cueID = cueIdentifier.string
				let referencePath = "\(path)/cue_identifiers[index=\(referenceIndex)]"
				if cueID.isEmpty || !knownCueIDs.contains(cueID) {
					diagnostics.append(error(
						code: "structure.unknown-cue-reference",
						path: referencePath,
						message: cueID.isEmpty
							? "Cue group contains an empty cue reference."
							: "Cue group references unknown cue UUID \(cueID).",
					))
					continue
				}
				referencedCueIDs.insert(cueID)
				if let firstGroupPath = firstGroupPathByCueID[cueID], firstGroupPath != path {
					diagnostics.append(warning(
						code: "structure.multiple-cue-group-membership",
						path: referencePath,
						message: "Cue UUID \(cueID) is also referenced by \(firstGroupPath); authored presentations normally assign each cue to exactly one group.",
					))
				} else {
					firstGroupPathByCueID[cueID] = path
				}
				if !seenReferences.insert(cueID).inserted {
					diagnostics.append(warning(
						code: "structure.duplicate-cue-reference",
						path: referencePath,
						message: "Cue UUID \(cueID) appears more than once in this cue group.",
					))
				}
			}
		}

		for storageIndex in presentation.presentationOrderCueIndices
			where !presentation.cues[storageIndex].uuid.string.isEmpty &&
			!referencedCueIDs.contains(presentation.cues[storageIndex].uuid.string)
		{
			diagnostics.append(warning(
				code: "structure.unreferenced-cue",
				path: presentation.componentPath(forCueAtStorageIndex: storageIndex),
				message: "Cue is not referenced by any cue group and is appended after grouped cues by native document order.",
			))
		}

		var knownArrangementIDs = Set<String>()
		let arrangementIDs = presentation.arrangements.map(\.uuid.string)
		for (index, arrangement) in presentation.arrangements.enumerated() {
			let identifier = arrangement.uuid.string
			let path = ComponentPathBuilder.repeatedPath(
				field: "arrangements",
				storageIndex: index,
				identities: arrangementIDs,
			)
			if identifier.isEmpty {
				diagnostics.append(error(
					code: "structure.missing-arrangement-uuid",
					path: path,
					message: "Arrangement UUID is missing.",
				))
			} else if !knownArrangementIDs.insert(identifier).inserted {
				diagnostics.append(error(
					code: "structure.duplicate-arrangement-uuid",
					path: path,
					message: "Arrangement UUID \(identifier) is duplicated.",
				))
			}

			for (referenceIndex, groupIdentifier) in arrangement.groupIdentifiers.enumerated() {
				let groupID = groupIdentifier.string
				let referencePath = "\(path)/group_identifiers[index=\(referenceIndex)]"
				if groupID.isEmpty || !knownGroupIDs.contains(groupID) {
					diagnostics.append(error(
						code: "structure.unknown-arrangement-group-reference",
						path: referencePath,
						message: groupID.isEmpty
							? "Arrangement contains an empty cue-group reference."
							: "Arrangement references unknown cue-group UUID \(groupID).",
					))
					continue
				}
			}
		}

		if presentation.hasSelectedArrangement {
			let selectedID = presentation.selectedArrangement.string
			if selectedID.isEmpty || !knownArrangementIDs.contains(selectedID) {
				diagnostics.append(error(
					code: "structure.unknown-selected-arrangement",
					path: "/selected_arrangement",
					message: selectedID.isEmpty
						? "Selected arrangement reference is empty."
						: "Selected arrangement references unknown arrangement UUID \(selectedID).",
				))
			}
		}

		return diagnostics
	}

	private static func themeDiagnostics(
		_ theme: Rv_Data_Template.Document,
	) -> [DocumentValidationDiagnostic] {
		var diagnostics: [DocumentValidationDiagnostic] = []
		if !theme.hasApplicationInfo {
			diagnostics.append(error(
				code: "structure.missing-application-info",
				path: "/",
				message: "Theme is missing application info.",
			))
		}
		var seenSlideIDs = Set<String>()
		let slideIDs = theme.slides.map { $0.hasBaseSlide ? $0.baseSlide.uuid.string : "" }
		for (slideIndex, slide) in theme.slides.enumerated() {
			let path = ComponentPathBuilder.repeatedPath(
				field: "slides",
				storageIndex: slideIndex,
				identities: slideIDs,
			)
			guard slide.hasBaseSlide else {
				diagnostics.append(error(
					code: "structure.missing-template-base-slide",
					path: path,
					message: "Template is missing its base slide.",
				))
				continue
			}

			let identifier = slide.baseSlide.uuid.string
			if !slide.baseSlide.hasUuid || identifier.isEmpty {
				diagnostics.append(error(
					code: "structure.missing-template-slide-uuid",
					path: "\(path)/base_slide",
					message: "Template base-slide UUID is missing.",
				))
			}
			if !identifier.isEmpty, !seenSlideIDs.insert(identifier).inserted {
				diagnostics.append(warning(
					code: "structure.duplicate-template-slide-uuid",
					path: path,
					message: "Template base-slide UUID \(identifier) is duplicated within the Theme document.",
				))
			}
			let size = slide.baseSlide.size
			if !slide.baseSlide.hasSize ||
				!size.width.isFinite || !size.height.isFinite ||
				size.width <= 0 || size.height <= 0
			{
				diagnostics.append(error(
					code: "structure.invalid-template-canvas-size",
					path: slide.baseSlide.hasSize ? "\(path)/base_slide/size" : "\(path)/base_slide",
					message: "Template canvas must have finite, positive dimensions.",
				))
			}

			var seenActionIDs = Set<String>()
			let actionIDs = slide.actions.map(\.uuid.string)
			for (actionIndex, action) in slide.actions.enumerated() {
				let actionPath = ComponentPathBuilder.repeatedPath(
					parent: path,
					field: "actions",
					storageIndex: actionIndex,
					identities: actionIDs,
				)
				if action.uuid.string.isEmpty {
					diagnostics.append(warning(
						code: "structure.missing-action-uuid",
						path: actionPath,
						message: "Template action UUID is missing, so the action cannot be addressed reliably.",
					))
				} else if !seenActionIDs.insert(action.uuid.string).inserted {
					diagnostics.append(warning(
						code: "structure.duplicate-action-uuid",
						path: actionPath,
						message: "Action UUID \(action.uuid.string) is duplicated within the template.",
					))
				}
			}
		}
		return diagnostics
	}

	private static func playlistDiagnostics(
		_ document: Rv_Data_PlaylistDocument,
	) -> [DocumentValidationDiagnostic] {
		var diagnostics: [DocumentValidationDiagnostic] = []
		if !document.hasApplicationInfo {
			diagnostics.append(error(
				code: "structure.missing-application-info",
				path: "/",
				message: "Playlist document is missing application info.",
			))
		}
		if document.type == .unknown {
			diagnostics.append(error(
				code: "structure.missing-playlist-type",
				path: "/",
				message: "Playlist document type is missing.",
			))
		}
		guard document.hasRootNode else {
			diagnostics.append(error(
				code: "structure.missing-playlist-root",
				path: "/",
				message: "Playlist document is missing its root node.",
			))
			return diagnostics
		}
		var seenPlaylistIDs = Set<String>()
		var seenItemIDs = Set<String>()
		appendPlaylistDiagnostics(
			document.rootNode,
			path: "/root_node",
			isRoot: true,
			seenPlaylistIDs: &seenPlaylistIDs,
			seenItemIDs: &seenItemIDs,
			to: &diagnostics,
		)
		return diagnostics
	}

	private static func appendPlaylistDiagnostics(
		_ playlist: Rv_Data_Playlist,
		path: String,
		isRoot: Bool,
		seenPlaylistIDs: inout Set<String>,
		seenItemIDs: inout Set<String>,
		to diagnostics: inout [DocumentValidationDiagnostic],
	) {
		let identifier = playlist.uuid.string
		if identifier.isEmpty {
			diagnostics.append(isRoot
				? error(code: "structure.missing-playlist-uuid", path: path, message: "Playlist root UUID is missing.")
				: warning(code: "structure.missing-playlist-uuid", path: path, message: "Playlist UUID is missing, so the playlist cannot be addressed reliably."))
		} else if !seenPlaylistIDs.insert(identifier).inserted {
			diagnostics.append(warning(
				code: "structure.duplicate-playlist-uuid",
				path: path,
				message: "Playlist UUID \(identifier) is duplicated in the playlist tree.",
			))
		}

		let childIDs = playlist.children.map(\.uuid.string)
		for (index, child) in playlist.children.enumerated() {
			let childPath = ComponentPathBuilder.repeatedPath(
				parent: path,
				field: "children",
				storageIndex: index,
				identities: childIDs,
			)
			appendPlaylistDiagnostics(
				child,
				path: childPath,
				isRoot: false,
				seenPlaylistIDs: &seenPlaylistIDs,
				seenItemIDs: &seenItemIDs,
				to: &diagnostics,
			)
		}

		switch playlist.childrenType {
		case let .playlists(wrapper):
			let childIDs = wrapper.playlists.map(\.uuid.string)
			for (index, child) in wrapper.playlists.enumerated() {
				let childPath = ComponentPathBuilder.repeatedPath(
					parent: "\(path)/playlists",
					field: "playlists",
					storageIndex: index,
					identities: childIDs,
				)
				appendPlaylistDiagnostics(
					child,
					path: childPath,
					isRoot: false,
					seenPlaylistIDs: &seenPlaylistIDs,
					seenItemIDs: &seenItemIDs,
					to: &diagnostics,
				)
			}
		case let .items(wrapper):
			let itemIDs = wrapper.items.map(\.uuid.string)
			for (index, item) in wrapper.items.enumerated() {
				let itemPath = ComponentPathBuilder.repeatedPath(
					parent: "\(path)/items",
					field: "items",
					storageIndex: index,
					identities: itemIDs,
				)
				appendPlaylistItemDiagnostics(item, path: itemPath, seenItemIDs: &seenItemIDs, to: &diagnostics)
			}
		case nil:
			break
		}
	}

	private static func appendPlaylistItemDiagnostics(
		_ item: Rv_Data_PlaylistItem,
		path: String,
		seenItemIDs: inout Set<String>,
		to diagnostics: inout [DocumentValidationDiagnostic],
	) {
		let identifier = item.uuid.string
		if identifier.isEmpty {
			diagnostics.append(warning(
				code: "structure.missing-playlist-item-uuid",
				path: path,
				message: "Playlist-item UUID is missing, so the item cannot be addressed reliably.",
			))
		} else if !seenItemIDs.insert(identifier).inserted {
			diagnostics.append(warning(
				code: "structure.duplicate-playlist-item-uuid",
				path: path,
				message: "Playlist-item UUID \(identifier) is duplicated in the playlist tree.",
			))
		}

		if case let .presentation(presentation)? = item.itemType,
		   !presentation.hasDocumentPath || presentation.documentPath.renderPath.isEmpty
		{
			diagnostics.append(error(
				code: "structure.missing-presentation-document-reference",
				path: "\(path)/presentation/document_path",
				message: "Presentation playlist item has no document path.",
			))
		}
	}

	private static func warning(code: String, path: String, message: String) -> DocumentValidationDiagnostic {
		DocumentValidationDiagnostic(code: code, severity: .warning, componentPath: path, message: message)
	}

	private static func error(code: String, path: String, message: String) -> DocumentValidationDiagnostic {
		DocumentValidationDiagnostic(code: code, severity: .error, componentPath: path, message: message)
	}
}
