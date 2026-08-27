import ArgumentParser
import Foundation

struct SkillCommand: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "skill",
		abstract: "Manage the bundled ProPresenter agent skills.",
		subcommands: [SkillInstall.self],
	)
}

struct SkillInstall: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "install",
		abstract: "Link the bundled ProPresenter skills for local AI agents.",
	)

	@Option(
		name: .customLong("agent"),
		parsing: .upToNextOption,
		help: "Install for a specific agent. Repeat to select multiple agents. By default, all detected agents are selected.",
	)
	var agents: [SkillAgent] = []

	@Flag(help: "Replace differing existing bundled skills.")
	var force = false

	@Flag(help: "Exit successfully if no supported local agents are detected.")
	var skipIfNone = false

	func run() throws {
		let installer = SkillInstaller.live()
		let selectedAgents = try installer.selectedAgents(
			requested: agents,
			skipIfNone: skipIfNone,
		)
		guard !selectedAgents.isEmpty else {
			print("No supported local agents detected; skipped skill installation.")
			return
		}
		if agents.isEmpty {
			print("Detected: \(selectedAgents.map(\.displayName).joined(separator: ", "))")
		}

		for installation in try installer.install(for: selectedAgents, force: force) {
			print(
				"\(installation.outcome.verb) \(installation.skillName) for "
					+ "\(installation.agent.displayName) at \(installation.destination.path)",
			)
		}
		print("Start a new agent session to load the skills.")
	}
}

enum SkillAgent: String, CaseIterable, ExpressibleByArgument, Sendable {
	case claude
	case codex
	case copilot
	case cursor
	case gemini
	case opencode

	var displayName: String {
		switch self {
		case .claude: "Claude Code"
		case .codex: "Codex"
		case .copilot: "GitHub Copilot"
		case .cursor: "Cursor"
		case .gemini: "Gemini CLI"
		case .opencode: "OpenCode"
		}
	}

	var executableNames: [String] {
		switch self {
		case .claude: ["claude"]
		case .codex: ["codex"]
		case .copilot: ["copilot"]
		case .cursor: ["agent", "cursor-agent", "cursor"]
		case .gemini: ["gemini"]
		case .opencode: ["opencode"]
		}
	}

	func configurationDirectory(homeDirectory: URL, environment: [String: String]) -> URL {
		switch self {
		case .claude:
			environment.directory(named: "CLAUDE_CONFIG_DIR")
				?? homeDirectory.appendingPathComponent(".claude", isDirectory: true)
		case .codex:
			environment.directory(named: "CODEX_HOME")
				?? homeDirectory.appendingPathComponent(".codex", isDirectory: true)
		case .copilot:
			environment.directory(named: "COPILOT_HOME")
				?? homeDirectory.appendingPathComponent(".copilot", isDirectory: true)
		case .cursor:
			homeDirectory.appendingPathComponent(".cursor", isDirectory: true)
		case .gemini:
			(environment.directory(named: "GEMINI_CLI_HOME") ?? homeDirectory)
				.appendingPathComponent(".gemini", isDirectory: true)
		case .opencode:
			(environment.directory(named: "XDG_CONFIG_HOME")
				?? homeDirectory.appendingPathComponent(".config", isDirectory: true))
				.appendingPathComponent("opencode", isDirectory: true)
		}
	}

	func skillDirectory(
		named skillName: String,
		homeDirectory: URL,
		environment: [String: String],
	) -> URL {
		let root = switch self {
		case .claude:
			(environment.directory(named: "CLAUDE_CONFIG_DIR")
				?? homeDirectory.appendingPathComponent(".claude", isDirectory: true))
				.appendingPathComponent("skills", isDirectory: true)
		case .codex:
			if let codexHome = environment.directory(named: "CODEX_HOME") {
				codexHome.appendingPathComponent("skills", isDirectory: true)
			} else {
				homeDirectory.appendingPathComponent(".agents/skills", isDirectory: true)
			}
		case .copilot:
			(environment.directory(named: "COPILOT_HOME")
				?? homeDirectory.appendingPathComponent(".copilot", isDirectory: true))
				.appendingPathComponent("skills", isDirectory: true)
		case .cursor:
			homeDirectory.appendingPathComponent(".cursor/skills", isDirectory: true)
		case .gemini:
			(environment.directory(named: "GEMINI_CLI_HOME") ?? homeDirectory)
				.appendingPathComponent(".gemini/skills", isDirectory: true)
		case .opencode:
			configurationDirectory(homeDirectory: homeDirectory, environment: environment)
				.appendingPathComponent("skills", isDirectory: true)
		}
		return root.appendingPathComponent(skillName, isDirectory: true)
	}
}

struct SkillInstaller {
	let homeDirectory: URL
	let environment: [String: String]
	let fileManager: FileManager
	let skillDirectoriesByName: [String: URL]

	static func live() -> Self {
		Self(
			homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
			environment: ProcessInfo.processInfo.environment,
			fileManager: .default,
			skillDirectoriesByName: CLIResources.agentSkillDirectories,
		)
	}

	func detectedAgents() -> [SkillAgent] {
		SkillAgent.allCases.filter(isInstalled)
	}

	func selectedAgents(requested: [SkillAgent], skipIfNone: Bool = false) throws -> [SkillAgent] {
		let selected = SkillAgent.allCases.filter(Set(requested.isEmpty ? detectedAgents() : requested).contains)
		guard !selected.isEmpty else {
			if skipIfNone {
				return []
			}
			throw SkillInstallError.noAgentsDetected
		}
		return selected
	}

	func install(for agents: [SkillAgent], force: Bool) throws -> [SkillInstallation] {
		var plans: [SkillInstallationPlan] = []
		for agent in agents {
			for skillName in skillDirectoriesByName.keys.sorted() {
				guard let source = skillDirectoriesByName[skillName] else { continue }
				try plans.append(installationPlan(
					for: agent,
					skillName: skillName,
					source: source,
					force: force,
				))
			}
		}
		for plan in plans where plan.outcome != .unchanged {
			try linkSkill(from: plan.source, to: plan.destination)
		}
		return plans.map { plan in
			SkillInstallation(
				skillName: plan.skillName,
				agent: plan.agent,
				destination: plan.destination,
				outcome: plan.outcome,
			)
		}
	}

	private func isInstalled(_ agent: SkillAgent) -> Bool {
		let configurationDirectory = agent.configurationDirectory(
			homeDirectory: homeDirectory,
			environment: environment,
		)
		if fileManager.fileExists(atPath: configurationDirectory.path) {
			return true
		}

		let pathDirectories = environment["PATH", default: ""]
			.split(separator: ":")
			.map { URL(fileURLWithPath: String($0), isDirectory: true) }
		let localBin = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
		return (pathDirectories + [localBin]).contains { directory in
			agent.executableNames.contains { executableName in
				fileManager.isExecutableFile(atPath: directory.appendingPathComponent(executableName).path)
			}
		}
	}

	private func installationPlan(
		for agent: SkillAgent,
		skillName: String,
		source: URL,
		force: Bool,
	) throws -> SkillInstallationPlan {
		guard try itemType(at: source) == .typeDirectory else {
			throw SkillInstallError.invalidSource(skillName: skillName, source: source)
		}
		let destination = agent.skillDirectory(
			named: skillName,
			homeDirectory: homeDirectory,
			environment: environment,
		)
		let outcome = try installationOutcome(
			for: agent,
			skillName: skillName,
			source: source,
			destination: destination,
			force: force,
		)
		return SkillInstallationPlan(
			skillName: skillName,
			source: source,
			agent: agent,
			destination: destination,
			outcome: outcome,
		)
	}

	private func installationOutcome(
		for agent: SkillAgent,
		skillName: String,
		source: URL,
		destination: URL,
		force: Bool,
	) throws -> SkillInstallationOutcome {
		guard let destinationType = try itemType(at: destination) else {
			return .installed
		}

		if destinationType == .typeSymbolicLink {
			let linkedSource = try symbolicLinkDestination(at: destination)
			guard linkedSource.standardizedFileURL.path != source.standardizedFileURL.path else {
				return .unchanged
			}
			return try differingSkillOutcome(
				for: agent,
				skillName: skillName,
				destination: destination,
				force: force,
			)
		}

		guard destinationType == .typeDirectory,
		      try directoryContents(at: destination) == directoryContents(at: source)
		else {
			return try differingSkillOutcome(
				for: agent,
				skillName: skillName,
				destination: destination,
				force: force,
			)
		}
		return .updated
	}

	private func differingSkillOutcome(
		for agent: SkillAgent,
		skillName: String,
		destination: URL,
		force: Bool,
	) throws -> SkillInstallationOutcome {
		guard force else {
			throw SkillInstallError.conflict(skillName: skillName, agent: agent, destination: destination)
		}
		return .updated
	}

	private func linkSkill(from source: URL, to destination: URL) throws {
		try fileManager.createDirectory(
			at: destination.deletingLastPathComponent(),
			withIntermediateDirectories: true,
		)
		if try itemType(at: destination) != nil {
			try fileManager.removeItem(at: destination)
		}
		try fileManager.createSymbolicLink(at: destination, withDestinationURL: source.standardizedFileURL)
	}

	private func itemType(at url: URL) throws -> FileAttributeType? {
		do {
			return try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
		} catch {
			let error = error as NSError
			let missingFileErrorCodes = [
				CocoaError.Code.fileNoSuchFile.rawValue,
				CocoaError.Code.fileReadNoSuchFile.rawValue,
			]
			guard error.domain == NSCocoaErrorDomain,
			      missingFileErrorCodes.contains(error.code)
			else {
				throw error
			}
			return nil
		}
	}

	private func symbolicLinkDestination(at url: URL) throws -> URL {
		let path = try fileManager.destinationOfSymbolicLink(atPath: url.path)
		return URL(
			fileURLWithPath: path,
			relativeTo: url.deletingLastPathComponent(),
		).standardizedFileURL
	}

	private func directoryContents(at directory: URL) throws -> [String: SkillDirectoryEntry] {
		let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
		guard let enumerator = fileManager.enumerator(atPath: directory.path) else {
			throw SkillInstallError.invalidSource(skillName: directory.lastPathComponent, source: directory)
		}

		var contents: [String: SkillDirectoryEntry] = [:]
		for case let relativePath as String in enumerator {
			let item = directory.appendingPathComponent(relativePath)
			let values = try item.resourceValues(forKeys: Set(keys))
			if values.isSymbolicLink == true {
				contents[relativePath] = try .symbolicLink(
					fileManager.destinationOfSymbolicLink(atPath: item.path),
				)
			} else if values.isDirectory == true {
				contents[relativePath] = .directory
			} else if values.isRegularFile == true {
				contents[relativePath] = try .file(Data(contentsOf: item))
			} else {
				contents[relativePath] = .other
			}
		}
		return contents
	}
}

private enum SkillDirectoryEntry: Equatable {
	case directory
	case file(Data)
	case symbolicLink(String)
	case other
}

struct SkillInstallation: Equatable {
	let skillName: String
	let agent: SkillAgent
	let destination: URL
	let outcome: SkillInstallationOutcome
}

enum SkillInstallationOutcome: Equatable {
	case installed
	case unchanged
	case updated

	var verb: String {
		switch self {
		case .installed: "Linked"
		case .unchanged: "Already linked"
		case .updated: "Relinked"
		}
	}
}

private struct SkillInstallationPlan {
	let skillName: String
	let source: URL
	let agent: SkillAgent
	let destination: URL
	let outcome: SkillInstallationOutcome
}

enum SkillInstallError: LocalizedError, Equatable {
	case conflict(skillName: String, agent: SkillAgent?, destination: URL)
	case invalidSource(skillName: String, source: URL)
	case noAgentsDetected

	var errorDescription: String? {
		switch self {
		case let .conflict(skillName, agent, destination):
			let owner = agent.map { " for \($0.displayName)" } ?? ""
			return "A differing \(skillName) skill already exists\(owner) at \(destination.path). Use --force to replace it."
		case let .invalidSource(skillName, source):
			return "The bundled \(skillName) skill is unavailable at \(source.path)."
		case .noAgentsDetected:
			return "No supported local agents were detected. Choose one with --agent: \(SkillAgent.allCases.map(\.rawValue).joined(separator: ", "))."
		}
	}
}

private extension [String: String] {
	func directory(named name: String) -> URL? {
		guard let path = self[name], !path.isEmpty else { return nil }
		return URL(fileURLWithPath: path, isDirectory: true)
	}
}
