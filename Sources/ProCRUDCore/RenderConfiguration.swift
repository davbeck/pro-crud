import CoreGraphics
import Foundation
import ProPresenterProto

public enum RenderConfigurationError: Error, CustomStringConvertible, Sendable {
	case selector(kind: String, value: String, candidates: [String])
	case macroCycle([String])
	case screenCycle([String])
	case macroHasNoLook(String)
	case missingLook(slide: Int)
	case timedAction(String)
	case conflictingSelectors

	public var description: String {
		switch self {
		case let .selector(kind, value, candidates):
			"\(kind) \(value) did not resolve uniquely. Candidates: \(candidates.joined(separator: ", "))"
		case let .screenCycle(path):
			"Recursive output-screen link cycle: \(path.joined(separator: " → "))"
		case let .macroCycle(path):
			"Recursive Macro cycle: \(path.joined(separator: " → "))"
		case let .macroHasNoLook(name):
			"Macro \(name) does not trigger an enabled audience Look."
		case let .missingLook(slide):
			"Slide \(slide) has no resolved Look. Select --look or --macro, or provide a workspace with a saved live Look."
		case .conflictingSelectors:
			"Select either a fixed Look or a fixed Macro variation."
		case let .timedAction(name):
			"Timed Look/Macro action \(name) cannot be resolved as a static variation."
		}
	}
}

/// Read-only configuration dependencies for exported documents and bundles.
/// Native configuration and Themes share one captured workspace snapshot.
public struct RenderConfiguration: Sendable {
	public struct Screen: Sendable {
		public let uuid: String
		public let name: String
		let logicalSize: CGSize?
		let document: Rv_Data_ProPresenterScreen?

		var size: CGSize {
			get throws {
				if let size = logicalSize, size.width.isFinite, size.height.isFinite,
				   size.width >= 1, size.height >= 1, size.width * size.height <= PresentationRenderer.maximumCanvasPixelCount
				{
					return size
				}
				if let document {
					return try LookResolver.screenSize(document)
				}
				throw LookResolverError.invalidScreenSize(name)
			}
		}
	}

	public let screens: [Screen]
	let looks: [Rv_Data_ProAudienceLook]
	let liveLook: Rv_Data_ProAudienceLook?
	private let root: URL
	private let snapshot: NativeWorkspaceSnapshot?

	public init(workspace: URL) throws {
		let inspection = try WorkspaceInspector.inspect(workspace)
		if inspection.storage == .nativeLoro, inspection.storageMarker == "sqlite-v1" {
			try self.init(snapshot: NativeWorkspaceSnapshot.read(from: workspace))
		} else {
			let paths = try LookResolver.workspacePaths(from: workspace)
			let document = try Rv_Data_ProPresenterWorkspace(serializedBytes: Data(contentsOf: paths.file))
			self.init(document: document, root: paths.root)
		}
	}

	private init(document: Rv_Data_ProPresenterWorkspace, root: URL) {
		self.root = root
		snapshot = nil
		liveLook = document.hasLiveAudienceLook ? document.liveAudienceLook : nil
		looks = document.audienceLooks
		screens = document.proScreens.filter { $0.screenType == .audience }.map {
			Screen(uuid: $0.uuid.string, name: $0.name, logicalSize: nil, document: $0)
		}
	}

	public init(snapshot: NativeWorkspaceSnapshot) throws {
		let configuration = try NativeWorkspaceConfiguration(snapshot: snapshot)
		root = snapshot.root
		self.snapshot = snapshot
		looks = configuration.savedLooks.map(\.document)
		liveLook = configuration.liveLook?.document
		screens = configuration.screens.filter { $0.screenType == 1 }.map { screen in
			Screen(uuid: screen.id.uuidString, name: screen.name,
			       logicalSize: screen.logicalWidth.flatMap { width in screen.logicalHeight.map { CGSize(width: width, height: $0) } }, document: screen.document)
		}
	}

	/// The first configured audience screen is the main screen. `all` retains
	/// configuration order; explicit selectors retain caller order.
	public func selectScreens(_ selectors: [String] = []) throws -> [Screen] {
		if selectors == ["all"], !screens.isEmpty {
			return screens
		}
		if selectors.isEmpty {
			guard let first = screens.first else { throw RenderConfigurationError.selector(kind: "Audience screen", value: "main", candidates: []) }
			return [first]
		}
		var selected: [Screen] = []
		for selector in selectors {
			let matches = screens.filter { Self.matches(selector, uuid: $0.uuid, name: $0.name) }
			guard matches.count == 1, let screen = matches.first else {
				throw RenderConfigurationError.selector(kind: "Audience screen", value: selector, candidates: screens.map { "\($0.name) (\($0.uuid))" })
			}
			if !selected.contains(where: { $0.uuid == screen.uuid }) {
				selected.append(screen)
			}
		}
		return selected
	}

	func look(_ selector: String) throws -> Rv_Data_ProAudienceLook {
		var candidates = looks
		if let liveLook, !candidates.contains(where: { Self.sameID($0.uuid.string, liveLook.uuid.string) }) {
			candidates.append(liveLook)
		}
		let matches = candidates.filter { Self.matches(selector, uuid: $0.uuid.string, name: $0.name) }
		guard matches.count == 1, let match = matches.first else {
			throw RenderConfigurationError.selector(kind: "Look", value: selector, candidates: candidates.map { "\($0.name) (\($0.uuid.string))" })
		}
		return match
	}

	func template(look: Rv_Data_ProAudienceLook, screen: Screen) throws -> LookTemplateSelection? {
		let matches = look.screenLooks.filter { Self.sameID($0.proScreenUuid.string, screen.uuid) }
		guard matches.count == 1, let mapping = matches.first else { throw LookResolverError.missingScreenMapping(look: look.name, screen: screen.name) }
		if mapping.templateSlideUuid.string.isEmpty && mapping.templateDocumentFilePath.renderPath.isEmpty {
			return nil
		}
		if let snapshot {
			return try LookResolver.resolve(snapshot: snapshot, look: look.uuid.string, screen: screen.uuid)
		}
		return try LookResolver.resolve(workspace: root, look: look.uuid.string, screen: screen.uuid)
	}

	func macros() throws -> [Rv_Data_MacrosDocument.Macro] {
		let data: Data
		if let snapshot {
			let streams = snapshot.streams.filter { $0.identity.kind == "Macros" && $0.identity.scope == .shared }
			guard streams.count <= 1 else { throw NativeSemanticError.duplicateIdentity(path: "/Macros", identity: "shared collection") }
			guard let stream = streams.first else { return [] }
			let projection = try stream.protobufProjection()
			try projection.requireComplete()
			data = projection.protobuf
		} else {
			let url = root.appendingPathComponent("Configuration/Macros")
			guard FileManager.default.fileExists(atPath: url.path) else { return [] }
			data = try Data(contentsOf: url)
		}
		let wire = try MediaWireMessage(data)
		// Collections are a newer schema field, preserved as unknown bytes by
		// the generated interchange types. Read their owned Macro definitions.
		let owned = try wire.payloads(3).flatMap { try MediaWireMessage($0).payloads(4) }
		return try (wire.payloads(2) + owned).map { try Rv_Data_MacrosDocument.Macro(serializedBytes: $0) }
	}

	static func sameID(_ lhs: String, _ rhs: String) -> Bool {
		!lhs.isEmpty && lhs.caseInsensitiveCompare(rhs) == .orderedSame
	}

	static func matches(_ selector: String, uuid: String, name: String) -> Bool {
		if UUID(uuidString: selector) != nil {
			return sameID(selector, uuid)
		}
		return selector == name
	}
}

struct LookActionResolver {
	let configuration: RenderConfiguration
	let macros: [Rv_Data_MacrosDocument.Macro]

	func macro(_ selector: String) throws -> Rv_Data_MacrosDocument.Macro {
		let matches = macros.filter { RenderConfiguration.matches(selector, uuid: $0.uuid.string, name: $0.name) }
		guard matches.count == 1, let match = matches.first else {
			throw RenderConfigurationError.selector(kind: "Macro", value: selector, candidates: macros.map { "\($0.name) (\($0.uuid.string))" })
		}
		return match
	}

	func look(actions: [Rv_Data_Action], startingAt initial: Rv_Data_ProAudienceLook?, path: [String] = []) throws -> Rv_Data_ProAudienceLook? {
		var current = initial
		for action in actions where action.isEnabled {
			switch action.type {
			case .audienceLook:
				guard action.delayTime == 0 else { throw RenderConfigurationError.timedAction(action.name) }
				let reference = action.audienceLook.identification
				current = try configuration.look(reference.parameterUuid.string.isEmpty ? reference.parameterName : reference.parameterUuid.string)
			case .macro:
				guard action.delayTime == 0 else { throw RenderConfigurationError.timedAction(action.name) }
				let reference = action.macro.identification
				let selected = try macro(reference.parameterUuid.string.isEmpty ? reference.parameterName : reference.parameterUuid.string)
				let identity = selected.uuid.string.lowercased()
				guard !path.contains(identity) else { throw RenderConfigurationError.macroCycle(path + [identity]) }
				current = try look(actions: selected.actions, startingAt: current, path: path + [identity])
			default: continue
			}
		}
		return current
	}
}
