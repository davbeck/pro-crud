import Foundation
import ProPresenterProto
import SwiftProtobuf

public enum DocumentKind: String, CaseIterable, Sendable {
	case presentation
	case theme
	case playlist

	public var archiveExtension: String {
		switch self {
		case .presentation: "probundle"
		case .theme: "proTheme"
		case .playlist: "proPlaylist"
		}
	}

	func validate(rawURL: URL) throws {
		let isValid = switch self {
		case .presentation: rawURL.pathExtension.lowercased() == "pro"
		case .theme: rawURL.lastPathComponent == "Theme"
		case .playlist: Self.rawPlaylistNames.contains(rawURL.lastPathComponent)
		}
		guard isValid else {
			throw DocumentLoadError.invalidRawDocumentName(kind: self, url: rawURL)
		}
	}

	private static let rawPlaylistNames: Set<String> = ["data", "Library", "Media", "Audio"]
}

public enum DocumentPayload: Sendable {
	case presentation(Rv_Data_Presentation)
	case theme(Rv_Data_Template.Document)
	case playlist(Rv_Data_PlaylistDocument)

	public var kind: DocumentKind {
		switch self {
		case .presentation: .presentation
		case .theme: .theme
		case .playlist: .playlist
		}
	}

	public func serializedData() throws -> Data {
		switch self {
		case let .presentation(message): try message.serializedData()
		case let .theme(message): try message.serializedData()
		case let .playlist(message): try message.serializedData()
		}
	}

	public func jsonUTF8Data() throws -> Data {
		var options = JSONEncodingOptions()
		options.useDeterministicOrdering = true
		return switch self {
		case let .presentation(message): try message.jsonUTF8Data(options: options)
		case let .theme(message): try message.jsonUTF8Data(options: options)
		case let .playlist(message): try message.jsonUTF8Data(options: options)
		}
	}
}

public enum DocumentOrigin: Sendable, Equatable {
	case raw(URL)
	case archive(URL)
	case workspace(URL)
}

public struct ProPresenterDocument: Sendable {
	public struct ThemeEntry: Sendable {
		public var relativePath: String
		public var document: Rv_Data_Template.Document

		public init(relativePath: String, document: Rv_Data_Template.Document) {
			self.relativePath = relativePath
			self.document = document
		}
	}

	public var payload: DocumentPayload
	public var origin: DocumentOrigin
	public var resourceDirectory: URL?
	public var archiveEntries: [String]
	public var themeEntries: [ThemeEntry]
	var temporaryResourceOwner: TemporaryDirectoryOwner?

	public init(
		payload: DocumentPayload,
		origin: DocumentOrigin,
		resourceDirectory: URL? = nil,
		archiveEntries: [String] = [],
		themeEntries: [ThemeEntry] = [],
	) {
		self.payload = payload
		self.origin = origin
		self.resourceDirectory = resourceDirectory
		self.archiveEntries = archiveEntries
		self.themeEntries = themeEntries
		temporaryResourceOwner = nil
	}

	public var kind: DocumentKind {
		payload.kind
	}

	public var embeddedAssetPaths: [String] {
		switch kind {
		case .presentation:
			archiveEntries.filter { !$0.hasSuffix("/") && URL(fileURLWithPath: $0).pathExtension.lowercased() != "pro" }
		case .theme:
			archiveEntries.filter { !$0.hasSuffix("/") && URL(fileURLWithPath: $0).lastPathComponent != "Theme" }
		case .playlist:
			archiveEntries.filter { !$0.hasSuffix("/") && URL(fileURLWithPath: $0).pathExtension.lowercased() != "pro" && URL(fileURLWithPath: $0).lastPathComponent != "data" }
		}
	}
}

public enum DocumentLoadError: Error, CustomStringConvertible, Sendable {
	case unsupportedInput(URL)
	case expectedRawDocument(URL)
	case missingPayload(kind: DocumentKind, location: URL)
	case invalidPayload(expected: String, location: String, underlying: String)
	case ambiguousPayload(kind: DocumentKind, candidates: [String])
	case invalidRawDocumentName(kind: DocumentKind, url: URL)

	public var description: String {
		switch self {
		case let .unsupportedInput(url):
			return "Cannot identify a ProPresenter document at \(url.path). Expected .pro, Theme, a raw playlist file, .probundle, .proTheme, or .proPlaylist."
		case let .expectedRawDocument(url):
			return "\(url.path) is a bundled document. Run expand, edit the extracted raw document, then bundle it again."
		case let .missingPayload(kind, location):
			return "\(kind.rawValue.capitalized) payload is missing from \(location.path)."
		case let .invalidPayload(expected, location, underlying):
			return "\(location) is not a valid \(expected): \(underlying)"
		case let .ambiguousPayload(kind, candidates):
			return "Expected exactly one \(kind.rawValue) payload, found: \(candidates.joined(separator: ", "))."
		case let .invalidRawDocumentName(kind, url):
			let expected = switch kind {
			case .presentation: "a .pro filename"
			case .theme: "the filename Theme"
			case .playlist: "the filename data, Library, Media, or Audio"
			}
			return "A raw \(kind.rawValue) document requires \(expected), got \(url.lastPathComponent)."
		}
	}
}

public enum DocumentLoader {
	public static func load(
		from url: URL,
		archiveLimits: ArchiveLimits = .default,
	) throws -> ProPresenterDocument {
		try load(from: url, archiveLimits: archiveLimits, validatesPayload: true)
	}

	/// Decodes a document without rejecting structurally invalid protobuf state.
	/// Archive safety checks and document-kind detection still apply so callers
	/// can inspect the decoded payload and report all structural diagnostics.
	public static func loadForValidation(
		from url: URL,
		archiveLimits: ArchiveLimits = .default,
	) throws -> ProPresenterDocument {
		try load(from: url, archiveLimits: archiveLimits, validatesPayload: false)
	}

	private static func load(
		from url: URL,
		archiveLimits: ArchiveLimits,
		validatesPayload: Bool,
	) throws -> ProPresenterDocument {
		let values = try url.resourceValues(forKeys: [.isDirectoryKey])
		if values.isDirectory == true {
			return try loadWorkspace(from: url, validatesPayload: validatesPayload)
		}
		switch url.pathExtension.lowercased() {
		case "pro":
			return try loadRaw(url, kind: .presentation, validatesPayload: validatesPayload)
		case "probundle":
			return try loadArchive(url, kind: .presentation, limits: archiveLimits, validatesPayload: validatesPayload)
		case "protheme":
			return try loadArchive(url, kind: .theme, limits: archiveLimits, validatesPayload: validatesPayload)
		case "proplaylist":
			return try loadArchive(url, kind: .playlist, limits: archiveLimits, validatesPayload: validatesPayload)
		default:
			switch url.lastPathComponent {
			case "Theme": return try loadRaw(url, kind: .theme, validatesPayload: validatesPayload)
			case "data", "Library", "Media", "Audio": return try loadRaw(url, kind: .playlist, validatesPayload: validatesPayload)
			default: throw DocumentLoadError.unsupportedInput(url)
			}
		}
	}

	public static func loadRaw(_ url: URL) throws -> ProPresenterDocument {
		let document = try load(from: url)
		guard case .raw = document.origin else { throw DocumentLoadError.expectedRawDocument(url) }
		return document
	}

	public static func loadRaw(_ url: URL, kind: DocumentKind) throws -> ProPresenterDocument {
		try loadRaw(url, kind: kind, validatesPayload: true)
	}

	private static func loadRaw(
		_ url: URL,
		kind: DocumentKind,
		validatesPayload: Bool,
	) throws -> ProPresenterDocument {
		let data = try Data(contentsOf: url)
		let payload = try decode(data, as: kind, location: url.path, validatesPayload: validatesPayload)
		return ProPresenterDocument(payload: payload, origin: .raw(url), resourceDirectory: url.deletingLastPathComponent())
	}

	public static func loadWorkspace(from directory: URL) throws -> ProPresenterDocument {
		try loadWorkspace(from: directory, validatesPayload: true)
	}

	private static func loadWorkspace(
		from directory: URL,
		validatesPayload: Bool,
	) throws -> ProPresenterDocument {
		let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
		let rootPros = contents.filter { $0.pathExtension.lowercased() == "pro" }
		let hasData = contents.contains { $0.lastPathComponent == "data" }
		let themes = try recursiveFiles(in: directory).filter { $0.lastPathComponent == "Theme" }

		let layouts = [
			!rootPros.isEmpty && !hasData && themes.isEmpty ? DocumentKind.presentation : nil,
			hasData && !rootPros.isEmpty && themes.isEmpty ? .playlist : nil,
			!themes.isEmpty && rootPros.isEmpty && !hasData ? .theme : nil,
		].compactMap(\.self)
		guard layouts.count == 1, let kind = layouts.first else {
			throw DocumentLoadError.unsupportedInput(directory)
		}

		switch kind {
		case .presentation:
			guard rootPros.count == 1 else { throw DocumentLoadError.ambiguousPayload(kind: kind, candidates: rootPros.map(\.lastPathComponent)) }
			var result = try loadRaw(rootPros[0], kind: .presentation, validatesPayload: validatesPayload)
			result.origin = .workspace(directory)
			result.resourceDirectory = directory
			return result
		case .playlist:
			var result = try loadRaw(directory.appendingPathComponent("data"), kind: .playlist, validatesPayload: validatesPayload)
			result.origin = .workspace(directory)
			result.resourceDirectory = directory
			return result
		case .theme:
			return try loadThemes(
				themes,
				origin: .workspace(directory),
				resourceDirectory: directory,
				validatesPayload: validatesPayload,
			)
		}
	}

	public static func decode(_ data: Data, as kind: DocumentKind, location: String) throws -> DocumentPayload {
		try decode(data, as: kind, location: location, validatesPayload: true)
	}

	private static func decode(
		_ data: Data,
		as kind: DocumentKind,
		location: String,
		validatesPayload: Bool,
	) throws -> DocumentPayload {
		do {
			let payload: DocumentPayload = switch kind {
			case .presentation: try .presentation(Rv_Data_Presentation(serializedBytes: data))
			case .theme: try .theme(Rv_Data_Template.Document(serializedBytes: data))
			case .playlist: try .playlist(Rv_Data_PlaylistDocument(serializedBytes: data))
			}
			if validatesPayload {
				try validate(payload, location: location)
			}
			return payload
		} catch {
			if let error = error as? DocumentLoadError {
				throw error
			}
			throw DocumentLoadError.invalidPayload(expected: kind.rawValue, location: location, underlying: error.localizedDescription)
		}
	}

	private static func loadArchive(
		_ url: URL,
		kind: DocumentKind,
		limits: ArchiveLimits,
		validatesPayload: Bool,
	) throws -> ProPresenterDocument {
		let reader = try ZIPReader(archiveURL: url, limits: limits)
		let entries = reader.entries.map(\.rawName)
		let temporaryDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("ProCRUD-\(UUID().uuidString)", isDirectory: true)
		try reader.extract(to: temporaryDirectory)
		let owner = TemporaryDirectoryOwner(url: temporaryDirectory)
		var result: ProPresenterDocument
		switch kind {
		case .presentation:
			let presentations = try recursiveFiles(in: temporaryDirectory).filter { $0.pathExtension.lowercased() == "pro" }
			guard presentations.count == 1 else { throw DocumentLoadError.ambiguousPayload(kind: kind, candidates: presentations.map(\.lastPathComponent)) }
			result = try ProPresenterDocument(
				payload: decode(
					Data(contentsOf: presentations[0]),
					as: kind,
					location: presentations[0].path,
					validatesPayload: validatesPayload,
				),
				origin: .archive(url),
				resourceDirectory: temporaryDirectory,
				archiveEntries: entries,
			)
		case .playlist:
			let candidate = temporaryDirectory.appendingPathComponent("data")
			guard FileManager.default.fileExists(atPath: candidate.path) else { throw DocumentLoadError.missingPayload(kind: kind, location: url) }
			result = try ProPresenterDocument(
				payload: decode(
					Data(contentsOf: candidate),
					as: kind,
					location: candidate.path,
					validatesPayload: validatesPayload,
				),
				origin: .archive(url),
				resourceDirectory: temporaryDirectory,
				archiveEntries: entries,
			)
		case .theme:
			let themes = try recursiveFiles(in: temporaryDirectory).filter { $0.lastPathComponent == "Theme" }
			result = try loadThemes(
				themes,
				origin: .archive(url),
				resourceDirectory: temporaryDirectory,
				validatesPayload: validatesPayload,
			)
			result.archiveEntries = entries
		}
		result.temporaryResourceOwner = owner
		return result
	}

	private static func loadThemes(
		_ themeURLs: [URL],
		origin: DocumentOrigin,
		resourceDirectory: URL,
		validatesPayload: Bool,
	) throws -> ProPresenterDocument {
		let sortedThemes = themeURLs.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
		guard !sortedThemes.isEmpty else {
			throw DocumentLoadError.missingPayload(kind: .theme, location: resourceDirectory)
		}
		let entries = try sortedThemes.map { url in
			let payload = try decode(
				Data(contentsOf: url),
				as: .theme,
				location: url.path,
				validatesPayload: validatesPayload,
			)
			guard case let .theme(theme) = payload else { preconditionFailure("Decoded theme payload has the wrong kind") }
			return try ProPresenterDocument.ThemeEntry(
				relativePath: relativePath(of: url, in: resourceDirectory),
				document: theme,
			)
		}
		return ProPresenterDocument(
			payload: .theme(entries[0].document),
			origin: origin,
			resourceDirectory: resourceDirectory,
			themeEntries: entries,
		)
	}

	private static func validate(_ payload: DocumentPayload, location: String) throws {
		let failure: String? = switch payload {
		case let .presentation(presentation):
			if !presentation.hasApplicationInfo {
				"missing application_info"
			} else if !presentation.hasUuid || presentation.uuid.string.isEmpty {
				"missing presentation UUID"
			} else if presentation.name.isEmpty {
				"missing presentation name"
			} else if presentation.cues.isEmpty {
				"missing presentation cues"
			} else if presentation.cueGroups.isEmpty {
				"missing presentation cue groups"
			} else {
				validatePresentationReferences(presentation)
			}
		case let .theme(theme):
			if !theme.hasApplicationInfo {
				"missing application_info"
			} else if theme.slides.contains(where: {
				!$0.hasBaseSlide ||
					!$0.baseSlide.hasUuid || $0.baseSlide.uuid.string.isEmpty ||
					!$0.baseSlide.hasSize || $0.baseSlide.size.width <= 0 || $0.baseSlide.size.height <= 0
			}) {
				"a template slide is missing a valid base_slide UUID or canvas size"
			} else {
				nil
			}
		case let .playlist(playlist):
			if !playlist.hasApplicationInfo {
				"missing application_info"
			} else if playlist.type == .unknown {
				"missing playlist document type"
			} else if !playlist.hasRootNode || playlist.rootNode.uuid.string.isEmpty {
				"missing playlist root node UUID"
			} else {
				nil
			}
		}
		if let failure {
			throw DocumentLoadError.invalidPayload(expected: payload.kind.rawValue, location: location, underlying: failure)
		}
	}

	private static func validatePresentationReferences(_ presentation: Rv_Data_Presentation) -> String? {
		let cueIDs = presentation.cues.map(\.uuid.string)
		guard cueIDs.allSatisfy({ !$0.isEmpty }), Set(cueIDs).count == cueIDs.count else {
			return "cue UUIDs are missing or duplicated"
		}
		let knownCueIDs = Set(cueIDs)
		let orderedCueIDs = presentation.cueGroups.flatMap { $0.cueIdentifiers.map(\.string) }
		guard orderedCueIDs.allSatisfy(knownCueIDs.contains) else {
			return "a cue group references an unknown cue UUID"
		}
		return nil
	}

	static func recursiveFiles(in directory: URL) throws -> [URL] {
		let fileManager = FileManager.default
		let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
		guard let enumerator = fileManager.enumerator(
			at: directory,
			includingPropertiesForKeys: Array(keys),
			options: [.skipsHiddenFiles, .skipsPackageDescendants],
		) else {
			return []
		}
		let rootPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
		var result: [URL] = []
		for case let url as URL in enumerator {
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

	static func relativePath(of url: URL, in directory: URL) throws -> String {
		let rootPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
		let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
		guard filePath.hasPrefix(rootPath + "/") else {
			throw ArchiveError.invalidEntry(url.path)
		}
		return String(filePath.dropFirst(rootPath.count + 1))
	}
}

public enum DocumentWriter {
	public static func writeRaw(_ document: ProPresenterDocument, to outputURL: URL, replace: Bool = false) throws {
		try document.kind.validate(rawURL: outputURL)
		_ = try DocumentLoader.decode(document.payload.serializedData(), as: document.kind, location: outputURL.path)
		let fileManager = FileManager.default
		guard replace || !fileManager.fileExists(atPath: outputURL.path) else {
			throw CocoaError(.fileWriteFileExists)
		}
		try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		let temporaryURL = outputURL.deletingLastPathComponent().appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")
		do {
			try document.payload.serializedData().write(to: temporaryURL, options: .atomic)
			if fileManager.fileExists(atPath: outputURL.path) {
				_ = try fileManager.replaceItemAt(outputURL, withItemAt: temporaryURL)
			} else {
				try fileManager.moveItem(at: temporaryURL, to: outputURL)
			}
		} catch {
			try? fileManager.removeItem(at: temporaryURL)
			throw error
		}
	}
}
