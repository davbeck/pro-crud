import Foundation
import ProPresenterProto

public enum DocumentArchiveError: Error, CustomStringConvertible, Sendable {
	case archiveRequired(URL)
	case outputExtension(expected: String, actual: String)
	case outputExists(URL)
	case unsafeWorkspaceEntry(String)
	case assetCollision(String)

	public var description: String {
		switch self {
		case let .archiveRequired(url): "\(url.path) is not a supported ProPresenter archive."
		case let .outputExtension(expected, actual): "Expected output extension .\(expected), got .\(actual)."
		case let .outputExists(url): "Output already exists: \(url.path). Use --replace to overwrite it."
		case let .unsafeWorkspaceEntry(entry): "Unsafe workspace entry: \(entry)"
		case let .assetCollision(path): "Multiple media assets would occupy the archive path \(path)."
		}
	}
}

public struct BundleResult: Sendable {
	public var archiveURL: URL
	public var warnings: [String]
}

public enum DocumentArchive {
	public static func expand(
		_ archiveURL: URL,
		to outputURL: URL? = nil,
		limits: ArchiveLimits = .default,
	) throws -> URL {
		guard archiveURL.pathExtension.lowercased() == "probundle" || archiveURL.pathExtension.lowercased() == "proplaylist" || archiveURL.pathExtension.lowercased() == "protheme" else {
			throw DocumentArchiveError.archiveRequired(archiveURL)
		}
		let destination = outputURL ?? archiveURL.deletingPathExtension()
		guard !FileManager.default.fileExists(atPath: destination.path) else { throw DocumentArchiveError.outputExists(destination) }
		try ZIPArchive.extract(archiveURL, to: destination, limits: limits)
		return destination
	}

	public static func bundle(
		_ inputURL: URL,
		to requestedOutputURL: URL? = nil,
		replace: Bool = false,
		limits: ArchiveLimits = .default,
	) throws -> URL {
		try bundleWithReport(
			inputURL,
			to: requestedOutputURL,
			replace: replace,
			limits: limits,
		).archiveURL
	}

	public static func bundleWithReport(
		_ inputURL: URL,
		to requestedOutputURL: URL? = nil,
		replace: Bool = false,
		limits: ArchiveLimits = .default,
	) throws -> BundleResult {
		try limits.validate()
		let deadline = ArchiveDeadline(timeout: limits.processingTimeout)
		let layout = try detectLayout(
			at: inputURL,
			limits: limits,
			deadline: deadline,
		)
		try deadline.check()
		let outputURL = try outputURL(for: layout.kind, inputURL: inputURL, requested: requestedOutputURL)
		guard replace || !FileManager.default.fileExists(atPath: outputURL.path) else { throw DocumentArchiveError.outputExists(outputURL) }
		try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		let workspace = try archiveWorkspace(
			from: inputURL,
			limits: limits,
			deadline: deadline,
		)
		let workingDirectory = workspace.directory
		defer { try? FileManager.default.removeItem(at: workingDirectory) }
		try deadline.check()
		let entries = try DocumentLoader.recursiveFiles(in: workingDirectory)
			.map { try DocumentLoader.relativePath(of: $0, in: workingDirectory) }
			.sorted()
		try ZIPArchive.create(
			from: workingDirectory,
			entries: entries,
			to: outputURL,
			replaceExisting: replace,
			limits: limits,
			deadline: deadline,
		)
		return BundleResult(archiveURL: outputURL, warnings: workspace.warnings)
	}

	private static func outputURL(for kind: DocumentKind, inputURL: URL, requested: URL?) throws -> URL {
		let expectedExtension = kind.archiveExtension
		let defaultURL: URL
		let values = try inputURL.resourceValues(forKeys: [.isDirectoryKey])
		if values.isDirectory == true {
			defaultURL = inputURL.deletingLastPathComponent().appendingPathComponent(inputURL.lastPathComponent).appendingPathExtension(expectedExtension)
		} else {
			defaultURL = inputURL.deletingPathExtension().appendingPathExtension(expectedExtension)
		}
		let result = requested ?? defaultURL
		guard result.pathExtension.lowercased() == expectedExtension.lowercased() else {
			throw DocumentArchiveError.outputExtension(expected: expectedExtension, actual: result.pathExtension)
		}
		return result
	}

	private static func archiveWorkspace(
		from inputURL: URL,
		limits: ArchiveLimits,
		deadline: ArchiveDeadline,
	) throws -> (directory: URL, warnings: [String]) {
		let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("ProCRUD-bundle-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
		do {
			let copyBudget = ArchiveCopyBudget(limits: limits, deadline: deadline)
			let inputValues = try inputURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
			guard inputValues.isSymbolicLink != true else {
				throw ArchiveError.unsupportedEntryType(entry: inputURL.path)
			}
			if inputValues.isDirectory == true {
				for file in try DocumentLoader.recursiveFiles(in: inputURL) {
					let relative = try DocumentLoader.relativePath(of: file, in: inputURL)
					try validateWorkspacePath(relative, limits: limits)
					let destination = workspace.appendingPathComponent(relative)
					try copyBudget.copy(from: file, to: destination, entry: relative)
				}
			} else {
				guard inputValues.isRegularFile == true else {
					throw ArchiveError.unsupportedEntryType(entry: inputURL.path)
				}
				let relative = inputURL.lastPathComponent
				try validateWorkspacePath(relative, limits: limits)
				let destination = workspace.appendingPathComponent(relative)
				try copyBudget.copy(from: inputURL, to: destination, entry: relative)
			}
			let warnings = try makePresentationMediaPortable(
				in: workspace,
				sourceRoot: inputValues.isDirectory == true ? inputURL : inputURL.deletingLastPathComponent(),
				limits: limits,
				copyBudget: copyBudget,
			)
			return (workspace, warnings)
		} catch {
			try? FileManager.default.removeItem(at: workspace)
			throw error
		}
	}

	private static func makePresentationMediaPortable(
		in workspace: URL,
		sourceRoot: URL,
		limits: ArchiveLimits,
		copyBudget: ArchiveCopyBudget,
	) throws -> [String] {
		let rootPros = try FileManager.default.contentsOfDirectory(at: workspace, includingPropertiesForKeys: [.isRegularFileKey])
			.filter { $0.pathExtension.lowercased() == "pro" }
		var warnings: [String] = []
		var copiedAssets: [String: URL] = [:]
		for proURL in rootPros {
			try copyBudget.deadline.check()
			var presentation = try Rv_Data_Presentation(serializedBytes: Data(contentsOf: proURL))
			for cueIndex in presentation.cues.indices {
				for actionIndex in presentation.cues[cueIndex].actions.indices {
					try copyBudget.deadline.check()
					var action = presentation.cues[cueIndex].actions[actionIndex]
					try rewriteMedia(
						in: &action,
						sourceRoot: sourceRoot,
						workspace: workspace,
						limits: limits,
						copyBudget: copyBudget,
						copiedAssets: &copiedAssets,
						warnings: &warnings,
					)
					presentation.cues[cueIndex].actions[actionIndex] = action
				}
			}
			try presentation.serializedData().write(to: proURL, options: .atomic)
		}
		for themeURL in try DocumentLoader.recursiveFiles(in: workspace).filter({ $0.lastPathComponent == "Theme" }) {
			try copyBudget.deadline.check()
			var theme = try Rv_Data_Template.Document(serializedBytes: Data(contentsOf: themeURL))
			for index in theme.slides.indices {
				try copyBudget.deadline.check()
				var template = theme.slides[index]
				try rewriteMedia(
					in: &template.baseSlide,
					sourceRoot: sourceRoot,
					workspace: workspace,
					limits: limits,
					copyBudget: copyBudget,
					copiedAssets: &copiedAssets,
					warnings: &warnings,
				)
				for actionIndex in template.actions.indices {
					var action = template.actions[actionIndex]
					try rewriteMedia(
						in: &action,
						sourceRoot: sourceRoot,
						workspace: workspace,
						limits: limits,
						copyBudget: copyBudget,
						copiedAssets: &copiedAssets,
						warnings: &warnings,
					)
					template.actions[actionIndex] = action
				}
				theme.slides[index] = template
			}
			try theme.serializedData().write(to: themeURL, options: .atomic)
		}
		return warnings
	}

	private static func rewriteMedia(
		in action: inout Rv_Data_Action,
		sourceRoot: URL,
		workspace: URL,
		limits: ArchiveLimits,
		copyBudget: ArchiveCopyBudget,
		copiedAssets: inout [String: URL],
		warnings: inout [String],
	) throws {
		switch action.type {
		case .media, .foregroundMedia, .backgroundMedia:
			var mediaType = action.media
			var media = mediaType.element
			try rewrite(
				mediaURL: &media.url,
				sourceRoot: sourceRoot,
				workspace: workspace,
				limits: limits,
				copyBudget: copyBudget,
				copiedAssets: &copiedAssets,
				warnings: &warnings,
			)
			mediaType.element = media
			action.media = mediaType
		case .presentationSlide:
			var slide = action.slide.presentation
			try rewriteMedia(
				in: &slide.baseSlide,
				sourceRoot: sourceRoot,
				workspace: workspace,
				limits: limits,
				copyBudget: copyBudget,
				copiedAssets: &copiedAssets,
				warnings: &warnings,
			)
			action.slide.presentation = slide
		default:
			break
		}
	}

	private static func rewriteMedia(
		in slide: inout Rv_Data_Slide,
		sourceRoot: URL,
		workspace: URL,
		limits: ArchiveLimits,
		copyBudget: ArchiveCopyBudget,
		copiedAssets: inout [String: URL],
		warnings: inout [String],
	) throws {
		for elementIndex in slide.elements.indices {
			var element = slide.elements[elementIndex].element
			if case var .media(media)? = element.fill.fillType {
				try rewrite(
					mediaURL: &media.url,
					sourceRoot: sourceRoot,
					workspace: workspace,
					limits: limits,
					copyBudget: copyBudget,
					copiedAssets: &copiedAssets,
					warnings: &warnings,
				)
				element.fill.media = media
				slide.elements[elementIndex].element = element
			}
		}
	}

	private static func rewrite(
		mediaURL: inout Rv_Data_URL,
		sourceRoot: URL,
		workspace: URL,
		limits: ArchiveLimits,
		copyBudget: ArchiveCopyBudget,
		copiedAssets: inout [String: URL],
		warnings: inout [String],
	) throws {
		guard let source = try resolve(
			mediaURL: mediaURL,
			in: sourceRoot,
			limits: limits,
		) else {
			warnings.append("Missing media asset: \(mediaURL.renderPath)")
			return
		}
		let containedPath = try? DocumentLoader.relativePath(of: source, in: sourceRoot)
		let proposedRelative = containedPath ?? source.lastPathComponent
		let standardizedSource = source.standardizedFileURL
		let relative: String
		var suffix = 0
		while true {
			try copyBudget.deadline.check()
			let candidate = ArchiveFileIO.path(proposedRelative, addingNumericSuffix: suffix)
			try validateWorkspacePath(candidate, limits: limits)
			let destination = workspace.appendingPathComponent(candidate)
			if let copied = copiedAssets[candidate] {
				if copied.standardizedFileURL == standardizedSource {
					relative = candidate
					break
				}
			} else if !FileManager.default.fileExists(atPath: destination.path) {
				try copyBudget.copy(from: standardizedSource, to: destination, entry: candidate)
				relative = candidate
				break
			} else if candidate == containedPath {
				relative = candidate
				break
			}
			suffix += 1
		}
		copiedAssets[relative] = source
		mediaURL.relativePath = relative
		mediaURL.relativeFilePath = nil
	}

	private static func resolve(
		mediaURL: Rv_Data_URL,
		in directory: URL,
		limits: ArchiveLimits,
	) throws -> URL? {
		if case let .relativePath(path)? = mediaURL.storage {
			try validateWorkspacePath(path, limits: limits)
			let candidate = directory.appendingPathComponent(path)
			if FileManager.default.fileExists(atPath: candidate.path) {
				do {
					_ = try DocumentLoader.relativePath(of: candidate, in: directory)
				} catch {
					throw DocumentArchiveError.unsafeWorkspaceEntry(path)
				}
				_ = try ArchiveFileIO.snapshot(of: candidate)
				return candidate
			}
		}
		if case let .absoluteString(string)? = mediaURL.storage, let candidate = URL(string: string), candidate.isFileURL, FileManager.default.fileExists(atPath: candidate.path) {
			_ = try ArchiveFileIO.snapshot(of: candidate)
			return candidate
		}
		let basename = URL(fileURLWithPath: mediaURL.renderPath).lastPathComponent
		guard !basename.isEmpty else { return nil }
		try validateWorkspacePath(basename, limits: limits)
		let matches = try DocumentLoader.recursiveFiles(in: directory).filter { $0.lastPathComponent == basename }
		guard matches.count <= 1 else { throw DocumentArchiveError.assetCollision(basename) }
		return matches.first
	}

	private struct Layout {
		var kind: DocumentKind
	}

	private static func validateWorkspacePath(
		_ path: String,
		limits: ArchiveLimits,
	) throws {
		guard !path.isEmpty,
		      !path.hasPrefix("/"),
		      !path.contains("\\"),
		      path.utf8.count <= limits.maximumPathLength,
		      !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
		else {
			throw DocumentArchiveError.unsafeWorkspaceEntry(path)
		}
		let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		let componentsAreSafe = components.allSatisfy { component in
			guard !component.isEmpty,
			      component != ".",
			      component != "..",
			      !component.hasPrefix(".")
			else {
				return false
			}
			return component.utf8.count <= limits.maximumPathComponentLength
		}
		guard components.count <= limits.maximumPathDepth,
		      componentsAreSafe,
		      components.first?.range(of: "^[A-Za-z]:", options: .regularExpression) == nil
		else {
			throw DocumentArchiveError.unsafeWorkspaceEntry(path)
		}
	}

	private static func detectLayout(
		at inputURL: URL,
		limits: ArchiveLimits,
		deadline: ArchiveDeadline,
	) throws -> Layout {
		try deadline.check()
		let values = try inputURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
		guard values.isSymbolicLink != true else {
			throw ArchiveError.unsupportedEntryType(entry: inputURL.path)
		}
		if values.isDirectory != true {
			guard inputURL.pathExtension.lowercased() == "pro" else { throw DocumentLoadError.expectedRawDocument(inputURL) }
			try validateWorkspacePath(inputURL.lastPathComponent, limits: limits)
			let validationBudget = ArchiveCopyBudget(limits: limits, deadline: deadline)
			try validationBudget.accountExisting(inputURL, entry: inputURL.lastPathComponent)
			_ = try DocumentLoader.loadRaw(inputURL, kind: .presentation)
			return Layout(kind: .presentation)
		}
		let validationBudget = ArchiveCopyBudget(limits: limits, deadline: deadline)
		let files = try DocumentLoader.recursiveFiles(in: inputURL)
		var paths: [(url: URL, relative: String)] = []
		paths.reserveCapacity(files.count)
		for file in files {
			try deadline.check()
			let relative = try DocumentLoader.relativePath(of: file, in: inputURL)
			try validateWorkspacePath(relative, limits: limits)
			try validationBudget.accountExisting(file, entry: relative)
			paths.append((file, relative))
		}
		let rootFiles = paths.filter { !$0.relative.contains("/") }.map(\.url)
		let rootPresentations = rootFiles.filter { $0.pathExtension.lowercased() == "pro" }
		let playlistURL = rootFiles.first { $0.lastPathComponent == "data" }
		let themes = paths.filter { $0.url.lastPathComponent == "Theme" }.map(\.url)
		let matches = [
			rootPresentations.count == 1 && playlistURL == nil && themes.isEmpty ? DocumentKind.presentation : nil,
			!rootPresentations.isEmpty && playlistURL != nil && themes.isEmpty ? .playlist : nil,
			rootPresentations.isEmpty && playlistURL == nil && !themes.isEmpty ? .theme : nil,
		].compactMap(\.self)
		guard matches.count == 1, let kind = matches.first else {
			throw DocumentLoadError.unsupportedInput(inputURL)
		}
		switch kind {
		case .presentation:
			try deadline.check()
			_ = try DocumentLoader.loadRaw(rootPresentations[0], kind: .presentation)
		case .playlist:
			guard let playlistURL else { throw DocumentLoadError.unsupportedInput(inputURL) }
			try deadline.check()
			_ = try DocumentLoader.loadRaw(playlistURL, kind: .playlist)
			for presentationURL in rootPresentations {
				try deadline.check()
				_ = try DocumentLoader.loadRaw(presentationURL, kind: .presentation)
			}
		case .theme:
			for themeURL in themes {
				try deadline.check()
				_ = try DocumentLoader.loadRaw(themeURL, kind: .theme)
			}
		}
		return Layout(kind: kind)
	}
}
