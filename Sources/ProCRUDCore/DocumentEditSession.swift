import Foundation
import ProPresenterProto

public final class DocumentEditSession {
	public var document: ProPresenterDocument

	private let archiveWorkspace: URL?
	private let archiveWorkspaceOwner: TemporaryDirectoryOwner?
	private let archiveSourceURL: URL?
	private let payloadRelativePath: String?
	private let originalMediaIdentifiers: Set<String>
	private let originalDocumentKind: DocumentKind
	private let archiveLimits: ArchiveLimits

	public static func open(
		_ inputURL: URL,
		archiveLimits: ArchiveLimits = .default,
	) throws -> DocumentEditSession {
		let archiveExtensions = Set(["probundle", "proplaylist", "protheme"])
		if archiveExtensions.contains(inputURL.pathExtension.lowercased()) {
			let document = try DocumentLoader.load(from: inputURL, archiveLimits: archiveLimits)
			guard case .archive = document.origin, let workspace = document.resourceDirectory else {
				throw DocumentLoadError.unsupportedInput(inputURL)
			}
			let payloadRelativePath = try payloadPath(for: document, in: workspace)
			return DocumentEditSession(
				document: document,
				archiveWorkspace: workspace,
				archiveSourceURL: inputURL,
				payloadRelativePath: payloadRelativePath,
				archiveLimits: archiveLimits,
			)
		}
		return try DocumentEditSession(
			document: DocumentLoader.loadRaw(inputURL),
			archiveLimits: archiveLimits,
		)
	}

	private init(
		document: ProPresenterDocument,
		archiveWorkspace: URL? = nil,
		archiveSourceURL: URL? = nil,
		payloadRelativePath: String? = nil,
		archiveLimits: ArchiveLimits,
	) {
		self.document = document
		self.archiveWorkspace = archiveWorkspace
		archiveWorkspaceOwner = document.temporaryResourceOwner
		self.archiveSourceURL = archiveSourceURL
		self.payloadRelativePath = payloadRelativePath
		self.archiveLimits = archiveLimits
		originalDocumentKind = document.kind
		originalMediaIdentifiers = Self.mediaIdentifiers(in: document.payload)
	}

	public func write(
		to outputURL: URL,
		replace: Bool = false,
		materializingTemplateMediaURLs: Set<String> = [],
	) throws {
		guard let archiveWorkspace, let archiveSourceURL, let payloadRelativePath else {
			try document.kind.validate(rawURL: outputURL)
			guard replace || !FileManager.default.fileExists(atPath: outputURL.path) else {
				throw CocoaError(.fileWriteFileExists)
			}
			try materializeTemplateMedia(
				materializingTemplateMediaURLs,
				in: outputURL.deletingLastPathComponent(),
			)
			try DocumentWriter.writeRaw(document, to: outputURL, replace: replace)
			return
		}

		try archiveLimits.validate()
		let deadline = ArchiveDeadline(timeout: archiveLimits.processingTimeout)
		guard document.kind == originalDocumentKind else {
			throw ArchiveError.invalidArchive(
				"An archive edit cannot change its document kind from \(originalDocumentKind.rawValue) to \(document.kind.rawValue).",
			)
		}
		let expectedExtension = document.kind.archiveExtension
		guard outputURL.pathExtension.lowercased() == expectedExtension.lowercased() else {
			throw DocumentArchiveError.outputExtension(expected: expectedExtension, actual: outputURL.pathExtension)
		}
		let fileManager = FileManager.default
		guard replace || !fileManager.fileExists(atPath: outputURL.path) else {
			throw DocumentArchiveError.outputExists(outputURL)
		}

		let budget = ArchiveCopyBudget(limits: archiveLimits, deadline: deadline)
		for file in try Self.workspaceFiles(in: archiveWorkspace, deadline: deadline) {
			let relativePath = try DocumentLoader.relativePath(of: file, in: archiveWorkspace)
			if relativePath != payloadRelativePath {
				try budget.accountExisting(file, entry: relativePath)
			}
		}
		try materializeTemplateMedia(
			materializingTemplateMediaURLs,
			in: archiveWorkspace,
			budget: budget,
		)
		try includeNewMedia(in: archiveWorkspace, budget: budget)
		let payloadData = try document.payload.serializedData()
		try deadline.check()
		_ = try DocumentLoader.decode(payloadData, as: document.kind, location: outputURL.path)
		try budget.account(size: UInt64(payloadData.count), entry: payloadRelativePath)
		let payloadURL = archiveWorkspace.appendingPathComponent(payloadRelativePath)
		try payloadData.write(to: payloadURL, options: .atomic)
		try deadline.check()

		let fileEntries = try DocumentLoader.recursiveFiles(in: archiveWorkspace)
			.map { try DocumentLoader.relativePath(of: $0, in: archiveWorkspace) }
		let originalExtractedEntries = Set(document.archiveEntries.map(Self.extractedPath(for:)))
		let newFileEntries = fileEntries.filter { !originalExtractedEntries.contains($0) }
		let updatedEntries = Array(Set(newFileEntries + [payloadRelativePath])).sorted()
		try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		let temporaryURL = outputURL.deletingLastPathComponent()
			.appendingPathComponent(".\(UUID().uuidString)-\(outputURL.lastPathComponent)")
		var ownsTemporaryFile = false
		do {
			let sourceSnapshot = try ArchiveFileIO.snapshot(of: archiveSourceURL)
			try ArchiveFileIO.copyRegularFile(
				from: archiveSourceURL,
				to: temporaryURL,
				expectedSize: sourceSnapshot.size,
				deadline: deadline,
			)
			ownsTemporaryFile = true
			try ZIPArchive.update(
				from: archiveWorkspace,
				entries: updatedEntries,
				in: temporaryURL,
				limits: archiveLimits,
				deadline: deadline,
			)
			let archivedEntries = try ZIPReader(
				archiveURL: temporaryURL,
				limits: archiveLimits,
				deadline: deadline,
			).entries.map(\.rawName)
			let expectedEntries = Set(document.archiveEntries + newFileEntries)
			guard archivedEntries.count == expectedEntries.count, Set(archivedEntries) == expectedEntries else {
				throw ArchiveError.invalidArchive("Archive entries did not match the editing workspace.")
			}
			try deadline.check()
			do {
				try ArchiveFileIO.installTemporaryFile(
					temporaryURL,
					at: outputURL,
					replaceExisting: replace,
				)
				ownsTemporaryFile = false
			} catch let error as POSIXError where !replace && error.code == .EEXIST {
				throw DocumentArchiveError.outputExists(outputURL)
			}
		} catch {
			if ownsTemporaryFile {
				try? fileManager.removeItem(at: temporaryURL)
			}
			throw error
		}
	}

	private func materializeTemplateMedia(
		_ urls: Set<String>,
		in directory: URL,
		budget: ArchiveCopyBudget? = nil,
	) throws {
		guard !urls.isEmpty else { return }
		guard case var .presentation(presentation) = document.payload else { return }
		try TemplateMediaMaterializer.materialize(
			in: &presentation,
			absoluteURLs: urls,
			destinationDirectory: directory,
			archiveBudget: budget,
		)
		document.payload = .presentation(presentation)
	}

	private static func extractedPath(for archiveEntry: String) -> String {
		var result = archiveEntry
		while result.hasPrefix("/") {
			result.removeFirst()
		}
		while result.hasPrefix("./") {
			result.removeFirst(2)
		}
		return result
	}

	private static func payloadPath(for document: ProPresenterDocument, in workspace: URL) throws -> String {
		switch document.kind {
		case .presentation:
			let presentations = try DocumentLoader.recursiveFiles(in: workspace)
				.filter { $0.pathExtension.lowercased() == "pro" }
			guard presentations.count == 1, let presentation = presentations.first else {
				throw DocumentLoadError.ambiguousPayload(
					kind: .presentation,
					candidates: presentations.map(\.lastPathComponent),
				)
			}
			return try DocumentLoader.relativePath(of: presentation, in: workspace)
		case .theme:
			guard let theme = document.themeEntries.first else {
				throw DocumentLoadError.missingPayload(kind: .theme, location: workspace)
			}
			return theme.relativePath
		case .playlist:
			return "data"
		}
	}

	private static func workspaceFiles(in directory: URL, deadline: ArchiveDeadline) throws -> [URL] {
		let fileManager = FileManager.default
		let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
		guard let enumerator = fileManager.enumerator(
			at: directory,
			includingPropertiesForKeys: Array(keys),
			options: [.skipsPackageDescendants],
		) else {
			return []
		}
		let rootPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
		var result: [URL] = []
		for case let url as URL in enumerator {
			try deadline.check()
			let values = try url.resourceValues(forKeys: keys)
			guard values.isSymbolicLink != true else {
				throw ArchiveError.unsupportedEntryType(entry: url.path)
			}
			if values.isDirectory == true {
				continue
			}
			guard values.isRegularFile == true else {
				throw ArchiveError.unsupportedEntryType(entry: url.path)
			}
			let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
			guard resolvedPath.hasPrefix(rootPath + "/") else {
				throw ArchiveError.invalidEntry(url.path)
			}
			result.append(url)
		}
		return result
	}

	private func includeNewMedia(in workspace: URL, budget: ArchiveCopyBudget) throws {
		switch document.payload {
		case var .presentation(presentation):
			try Self.includeNewMedia(
				in: &presentation,
				originalIdentifiers: originalMediaIdentifiers,
				workspace: workspace,
				budget: budget,
			)
			document.payload = .presentation(presentation)
		case var .theme(theme):
			try Self.includeNewMedia(
				in: &theme,
				originalIdentifiers: originalMediaIdentifiers,
				workspace: workspace,
				budget: budget,
			)
			document.payload = .theme(theme)
		case .playlist:
			break
		}
	}

	private static func includeNewMedia(
		in presentation: inout Rv_Data_Presentation,
		originalIdentifiers: Set<String>,
		workspace: URL,
		budget: ArchiveCopyBudget,
	) throws {
		for cueIndex in presentation.cues.indices {
			for actionIndex in presentation.cues[cueIndex].actions.indices {
				var action = presentation.cues[cueIndex].actions[actionIndex]
				try includeNewMedia(
					in: &action,
					originalIdentifiers: originalIdentifiers,
					workspace: workspace,
					budget: budget,
				)
				presentation.cues[cueIndex].actions[actionIndex] = action
			}
		}
	}

	private static func includeNewMedia(
		in theme: inout Rv_Data_Template.Document,
		originalIdentifiers: Set<String>,
		workspace: URL,
		budget: ArchiveCopyBudget,
	) throws {
		for slideIndex in theme.slides.indices {
			var slide = theme.slides[slideIndex]
			try includeNewMedia(
				in: &slide.baseSlide,
				originalIdentifiers: originalIdentifiers,
				workspace: workspace,
				budget: budget,
			)
			for actionIndex in slide.actions.indices {
				var action = slide.actions[actionIndex]
				try includeNewMedia(
					in: &action,
					originalIdentifiers: originalIdentifiers,
					workspace: workspace,
					budget: budget,
				)
				slide.actions[actionIndex] = action
			}
			theme.slides[slideIndex] = slide
		}
	}

	private static func includeNewMedia(
		in action: inout Rv_Data_Action,
		originalIdentifiers: Set<String>,
		workspace: URL,
		budget: ArchiveCopyBudget,
	) throws {
		switch action.type {
		case .media, .foregroundMedia, .backgroundMedia:
			var mediaType = action.media
			var media = mediaType.element
			try includeNewMedia(
				in: &media,
				originalIdentifiers: originalIdentifiers,
				workspace: workspace,
				budget: budget,
			)
			mediaType.element = media
			for markerIndex in mediaType.markers.indices {
				for actionIndex in mediaType.markers[markerIndex].actions.indices {
					try includeNewMedia(
						in: &mediaType.markers[markerIndex].actions[actionIndex],
						originalIdentifiers: originalIdentifiers,
						workspace: workspace,
						budget: budget,
					)
				}
			}
			action.media = mediaType
		case .presentationSlide:
			var slide = action.slide.presentation
			try includeNewMedia(
				in: &slide.baseSlide,
				originalIdentifiers: originalIdentifiers,
				workspace: workspace,
				budget: budget,
			)
			action.slide.presentation = slide
		case .propSlide:
			var slide = action.slide.prop
			try includeNewMedia(
				in: &slide.baseSlide,
				originalIdentifiers: originalIdentifiers,
				workspace: workspace,
				budget: budget,
			)
			action.slide.prop = slide
		default:
			break
		}
	}

	private static func includeNewMedia(
		in slide: inout Rv_Data_Slide,
		originalIdentifiers: Set<String>,
		workspace: URL,
		budget: ArchiveCopyBudget,
	) throws {
		for index in slide.elements.indices {
			var element = slide.elements[index].element
			try includeNewMedia(
				in: &element,
				originalIdentifiers: originalIdentifiers,
				workspace: workspace,
				budget: budget,
			)
			slide.elements[index].element = element
		}
	}

	private static func includeNewMedia(
		in element: inout Rv_Data_Graphics.Element,
		originalIdentifiers: Set<String>,
		workspace: URL,
		budget: ArchiveCopyBudget,
	) throws {
		if case var .media(media)? = element.fill.fillType {
			try includeNewMedia(
				in: &media,
				originalIdentifiers: originalIdentifiers,
				workspace: workspace,
				budget: budget,
			)
			element.fill.media = media
		}
		guard element.hasText else { return }
		var attributes = element.text.attributes
		if case var .mediaFill(fill)? = attributes.fill {
			var media = fill.media
			try includeNewMedia(
				in: &media,
				originalIdentifiers: originalIdentifiers,
				workspace: workspace,
				budget: budget,
			)
			fill.media = media
			attributes.mediaFill = fill
		}
		for index in attributes.customAttributes.indices {
			if case var .mediaFill(fill)? = attributes.customAttributes[index].attribute {
				var media = fill.media
				try includeNewMedia(
					in: &media,
					originalIdentifiers: originalIdentifiers,
					workspace: workspace,
					budget: budget,
				)
				fill.media = media
				attributes.customAttributes[index].mediaFill = fill
			}
		}
		element.text.attributes = attributes
	}

	private static func includeNewMedia(
		in media: inout Rv_Data_Media,
		originalIdentifiers: Set<String>,
		workspace: URL,
		budget: ArchiveCopyBudget,
	) throws {
		let identifier = media.uuid.string
		guard !identifier.isEmpty, !originalIdentifiers.contains(identifier) else { return }
		guard case let .absoluteString(value)? = media.url.storage,
		      let sourceURL = URL(string: value),
		      sourceURL.isFileURL,
		      FileManager.default.fileExists(atPath: sourceURL.path)
		else {
			return
		}
		media.url.relativePath = try include(sourceURL, in: workspace, budget: budget)
		media.url.relativeFilePath = nil
	}

	private static func include(_ sourceURL: URL, in workspace: URL, budget: ArchiveCopyBudget) throws -> String {
		let standardizedSource = sourceURL.standardizedFileURL
		if let relativePath = try? DocumentLoader.relativePath(of: standardizedSource, in: workspace) {
			try validateNewArchivePath(relativePath, limits: budget.limits)
			try budget.accountExisting(standardizedSource, entry: relativePath)
			return relativePath
		}

		let fileManager = FileManager.default
		let extensionValue = sourceURL.pathExtension
		let stem = sourceURL.deletingPathExtension().lastPathComponent
		var suffix = 1
		while true {
			try budget.deadline.check()
			let filename = if suffix == 1 {
				sourceURL.lastPathComponent
			} else if extensionValue.isEmpty {
				"\(stem)-\(suffix)"
			} else {
				"\(stem)-\(suffix).\(extensionValue)"
			}
			try validateNewArchivePath(filename, limits: budget.limits)
			let destination = workspace.appendingPathComponent(filename)
			if !fileManager.fileExists(atPath: destination.path) {
				try budget.copy(from: standardizedSource, to: destination, entry: filename)
				return filename
			}
			if try ArchiveFileIO.contentsEqual(standardizedSource, destination, deadline: budget.deadline) {
				return filename
			}
			let (nextSuffix, overflow) = suffix.addingReportingOverflow(1)
			guard !overflow else {
				throw ArchiveError.invalidEntry(sourceURL.lastPathComponent)
			}
			suffix = nextSuffix
		}
	}

	private static func validateNewArchivePath(_ path: String, limits: ArchiveLimits) throws {
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

	private static func mediaIdentifiers(in payload: DocumentPayload) -> Set<String> {
		var identifiers: Set<String> = []
		switch payload {
		case let .presentation(presentation):
			for cue in presentation.cues {
				for action in cue.actions {
					collectMediaIdentifiers(in: action, into: &identifiers)
				}
			}
		case let .theme(theme):
			for slide in theme.slides {
				collectMediaIdentifiers(in: slide.baseSlide, into: &identifiers)
				for action in slide.actions {
					collectMediaIdentifiers(in: action, into: &identifiers)
				}
			}
		case .playlist:
			break
		}
		return identifiers
	}

	private static func collectMediaIdentifiers(in action: Rv_Data_Action, into identifiers: inout Set<String>) {
		switch action.type {
		case .media, .foregroundMedia, .backgroundMedia:
			collectMediaIdentifier(action.media.element, into: &identifiers)
			for marker in action.media.markers {
				for nestedAction in marker.actions {
					collectMediaIdentifiers(in: nestedAction, into: &identifiers)
				}
			}
		case .presentationSlide:
			collectMediaIdentifiers(in: action.slide.presentation.baseSlide, into: &identifiers)
		case .propSlide:
			collectMediaIdentifiers(in: action.slide.prop.baseSlide, into: &identifiers)
		default:
			break
		}
	}

	private static func collectMediaIdentifiers(in slide: Rv_Data_Slide, into identifiers: inout Set<String>) {
		for element in slide.elements {
			collectMediaIdentifiers(in: element.element, into: &identifiers)
		}
	}

	private static func collectMediaIdentifiers(
		in element: Rv_Data_Graphics.Element,
		into identifiers: inout Set<String>,
	) {
		if case let .media(media)? = element.fill.fillType {
			collectMediaIdentifier(media, into: &identifiers)
		}
		guard element.hasText else { return }
		if case let .mediaFill(fill)? = element.text.attributes.fill {
			collectMediaIdentifier(fill.media, into: &identifiers)
		}
		for attribute in element.text.attributes.customAttributes {
			if case let .mediaFill(fill)? = attribute.attribute {
				collectMediaIdentifier(fill.media, into: &identifiers)
			}
		}
	}

	private static func collectMediaIdentifier(_ media: Rv_Data_Media, into identifiers: inout Set<String>) {
		if !media.uuid.string.isEmpty {
			identifiers.insert(media.uuid.string)
		}
	}
}
