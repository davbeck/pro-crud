import CoreGraphics
import Foundation
import ProPresenterProto
import SwiftProtobuf

public struct LookTemplateSelection: Sendable {
	public var lookName: String
	public var screenName: String
	public var destinationSize: CGSize
	public var template: ThemeTemplateSource.Candidate
	public var warnings: [String]
}

public enum LookResolverError: Error, CustomStringConvertible, Sendable {
	case missingWorkspace(URL)
	case ambiguousLook(selector: String, candidates: [String])
	case ambiguousScreen(selector: String, candidates: [String])
	case missingScreenMapping(look: String, screen: String)
	case missingTemplateReference(look: String, screen: String)
	case invalidTemplateURL(String)
	case invalidScreenSize(String)

	public var description: String {
		switch self {
		case let .missingWorkspace(url):
			"Configuration/Workspace was not found beneath \(url.path)."
		case let .ambiguousLook(selector, candidates):
			"Look \(selector) did not resolve uniquely. Candidates: \(candidates.joined(separator: ", "))"
		case let .ambiguousScreen(selector, candidates):
			"Audience screen \(selector) did not resolve uniquely. Candidates: \(candidates.joined(separator: ", "))"
		case let .missingScreenMapping(look, screen):
			"Look \(look) does not contain exactly one mapping for audience screen \(screen)."
		case let .missingTemplateReference(look, screen):
			"Look \(look) has no alternate template for audience screen \(screen); ordinary screen aspect-fit rendering is not yet emulated."
		case let .invalidTemplateURL(value):
			"Look template path could not be resolved: \(value)"
		case let .invalidScreenSize(screen):
			"Audience screen \(screen) has no finite, positive output canvas."
		}
	}
}

public enum LookResolver {
	public static func resolve(
		workspace input: URL,
		look lookSelector: String,
		screen screenSelector: String,
	) throws -> LookTemplateSelection {
		let paths = try workspacePaths(from: input)
		let workspace = try Rv_Data_ProPresenterWorkspace(
			serializedBytes: Data(contentsOf: paths.file),
		)

		var looks = workspace.audienceLooks
		if workspace.hasLiveAudienceLook,
		   !looks.contains(where: { $0.uuid == workspace.liveAudienceLook.uuid })
		{
			looks.append(workspace.liveAudienceLook)
		}
		let matchingLooks = looks.filter {
			$0.name == lookSelector || $0.uuid.string == lookSelector
		}
		guard matchingLooks.count == 1, let look = matchingLooks.first else {
			throw LookResolverError.ambiguousLook(
				selector: lookSelector,
				candidates: looks.map { "\($0.name) (\($0.uuid.string))" },
			)
		}

		let audienceScreens = workspace.proScreens.filter { $0.screenType == .audience }
		let matchingScreens = audienceScreens.filter {
			$0.name == screenSelector || $0.uuid.string == screenSelector
		}
		guard matchingScreens.count == 1, let screen = matchingScreens.first else {
			throw LookResolverError.ambiguousScreen(
				selector: screenSelector,
				candidates: audienceScreens.map { "\($0.name) (\($0.uuid.string))" },
			)
		}

		let mappings = look.screenLooks.filter { $0.proScreenUuid == screen.uuid }
		guard mappings.count == 1, let mapping = mappings.first else {
			throw LookResolverError.missingScreenMapping(look: look.name, screen: screen.name)
		}
		guard !mapping.templateSlideUuid.string.isEmpty,
		      !mapping.templateDocumentFilePath.renderPath.isEmpty
		else {
			throw LookResolverError.missingTemplateReference(look: look.name, screen: screen.name)
		}

		let themeURL = try resolve(
			mapping.templateDocumentFilePath,
			workspaceRoot: paths.root,
		)
		let candidates = try ThemeTemplateSource.candidates(from: themeURL, showRoot: paths.root)
		let candidate = try ThemeTemplateSource.select(
			candidates,
			named: "/slides[uuid=\(mapping.templateSlideUuid.string)]",
		)
		let size = try screenSize(screen)
		var warnings: [String] = candidate.mediaWarnings
		if mapping.propsEnabled || mapping.liveVideoEnabled || mapping.announcementsEnabled ||
			mapping.propsLayerEnabled || mapping.messagesLayerEnabled || !mapping.maskUuid.string.isEmpty
		{
			warnings.append("Look masks and runtime props, messages, announcements, and live-video layers are not available from a presentation document render.")
		}
		if !mapping.presentationBackgroundEnabled || !mapping.presentationForegroundEnabled {
			warnings.append("Presentation background/foreground layer switches are recorded by the Look but cannot yet be separated from cue actions during file rendering.")
		}
		return LookTemplateSelection(
			lookName: look.name,
			screenName: screen.name,
			destinationSize: size,
			template: candidate,
			warnings: Array(Set(warnings)).sorted(),
		)
	}

	private static func workspacePaths(from input: URL) throws -> (root: URL, file: URL) {
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory), !isDirectory.boolValue,
		   input.lastPathComponent == "Workspace"
		{
			let configuration = input.deletingLastPathComponent()
			let root = configuration.lastPathComponent == "Configuration"
				? configuration.deletingLastPathComponent()
				: configuration
			return (root, input)
		}
		let candidate = input.appendingPathComponent("Configuration/Workspace")
		guard FileManager.default.fileExists(atPath: candidate.path) else {
			throw LookResolverError.missingWorkspace(input)
		}
		return (input, candidate)
	}

	private static func resolve(_ value: Rv_Data_URL, workspaceRoot: URL) throws -> URL {
		if case let .absoluteString(string)? = value.storage,
		   let url = URL(string: string), url.isFileURL,
		   FileManager.default.fileExists(atPath: url.path)
		{
			return url
		}
		if case let .absoluteString(string)? = value.storage, string.hasPrefix("/") {
			let url = URL(fileURLWithPath: string)
			if FileManager.default.fileExists(atPath: url.path) {
				return url
			}
		}
		if case let .relativePath(path)? = value.storage {
			let url = workspaceRoot.appendingPathComponent(path)
			if FileManager.default.fileExists(atPath: url.path) {
				return url
			}
		}
		if case let .local(local)? = value.relativeFilePath,
		   local.root == .show || local.root == .currentResource
		{
			let url = workspaceRoot.appendingPathComponent(local.path)
			if FileManager.default.fileExists(atPath: url.path) {
				return url
			}
		}
		throw LookResolverError.invalidTemplateURL(value.renderPath)
	}

	private static func screenSize(_ screen: Rv_Data_ProPresenterScreen) throws -> CGSize {
		let children: [Rv_Data_Screen] = switch screen.arrangement {
		case let .arrangementSingle(value): value.screens
		case let .arrangementCombined(value): value.screens
		case let .arrangementEdgeBlend(value): value.screens
		case nil: []
		}
		let validRects = children.compactMap { child -> CGRect? in
			let rect = CGRect(
				x: child.bounds.origin.x,
				y: child.bounds.origin.y,
				width: child.bounds.size.width,
				height: child.bounds.size.height,
			)
			guard rect.origin.x.isFinite, rect.origin.y.isFinite,
			      rect.width.isFinite, rect.height.isFinite,
			      rect.width > 0, rect.height > 0
			else { return nil }
			return rect.standardized
		}
		if validRects.count == children.count, let first = validRects.first {
			let union = validRects.dropFirst().reduce(first) { $0.union($1) }
			let size = union.size
			if size.width >= 1, size.height >= 1,
			   size.width * size.height <= PresentationRenderer.maximumCanvasPixelCount
			{
				return size
			}
		}
		if children.count == 1, let child = children.first {
			let width = Double(child.outputDisplay.mode.width)
			let height = Double(child.outputDisplay.mode.height)
			if width >= 1, height >= 1,
			   width * height <= PresentationRenderer.maximumCanvasPixelCount
			{
				return CGSize(width: width, height: height)
			}
		}
		throw LookResolverError.invalidScreenSize(screen.name)
	}
}
