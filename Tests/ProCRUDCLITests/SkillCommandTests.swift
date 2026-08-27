import CustomDump
import Foundation
import Testing
@testable import ProCRUDCLI

@Suite("Skill command")
struct SkillCommandTests {
	@Test func parsesRepeatedExplicitAgents() throws {
		let command = try SkillInstall.parse([
			"--agent", "codex",
			"--agent", "claude",
			"--force",
			"--skip-if-none",
		])

		expectNoDifference(command.agents, [.codex, .claude])
		#expect(command.force)
		#expect(command.skipIfNone)
	}

	@Test func detectsAgentsFromConfigurationAndPath() throws {
		try withTemporaryDirectory { directory in
			let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
			let fileManager = FileManager.default
			try fileManager.createDirectory(
				at: homeDirectory.appendingPathComponent(".claude", isDirectory: true),
				withIntermediateDirectories: true,
			)
			let binDirectory = homeDirectory.appendingPathComponent("bin", isDirectory: true)
			try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
			let codexExecutable = binDirectory.appendingPathComponent("codex")
			try "".write(to: codexExecutable, atomically: true, encoding: .utf8)
			try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codexExecutable.path)
			let cursorExecutable = binDirectory.appendingPathComponent("cursor-agent")
			try "".write(to: cursorExecutable, atomically: true, encoding: .utf8)
			try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cursorExecutable.path)

			let installer = try SkillInstaller(
				homeDirectory: homeDirectory,
				environment: ["PATH": binDirectory.path],
				fileManager: fileManager,
				skillDirectoriesByName: makeSkillDirectories(in: directory),
			)

			expectNoDifference(installer.detectedAgents(), [.claude, .codex, .cursor])
		}
	}

	@Test func explicitSelectionDoesNotRequireDetection() throws {
		try withTemporaryDirectory { directory in
			let installer = try SkillInstaller(
				homeDirectory: directory.appendingPathComponent("home", isDirectory: true),
				environment: [:],
				fileManager: .default,
				skillDirectoriesByName: makeSkillDirectories(in: directory),
			)

			try expectNoDifference(
				installer.selectedAgents(requested: [.cursor, .codex, .cursor]),
				[.codex, .cursor],
			)
			do {
				_ = try installer.selectedAgents(requested: [])
				Issue.record("Expected selection to fail when no agents are detected")
			} catch let error as SkillInstallError {
				expectNoDifference(error, .noAgentsDetected)
			}
			try expectNoDifference(
				installer.selectedAgents(requested: [], skipIfNone: true),
				[],
			)
		}
	}

	@Test func resolvesAgentSpecificDestinationsForNamedSkills() throws {
		try withTemporaryDirectory { homeDirectory in
			let environment = [
				"CLAUDE_CONFIG_DIR": homeDirectory.appendingPathComponent("custom-claude").path,
				"CODEX_HOME": homeDirectory.appendingPathComponent("custom-codex").path,
				"COPILOT_HOME": homeDirectory.appendingPathComponent("custom-copilot").path,
				"GEMINI_CLI_HOME": homeDirectory.appendingPathComponent("custom-gemini-home").path,
				"XDG_CONFIG_HOME": homeDirectory.appendingPathComponent("custom-config").path,
			]
			let skillRoots = [
				homeDirectory.appendingPathComponent("custom-claude/skills").path,
				homeDirectory.appendingPathComponent("custom-codex/skills").path,
				homeDirectory.appendingPathComponent("custom-copilot/skills").path,
				homeDirectory.appendingPathComponent(".cursor/skills").path,
				homeDirectory.appendingPathComponent("custom-gemini-home/.gemini/skills").path,
				homeDirectory.appendingPathComponent("custom-config/opencode/skills").path,
			]

			for skillName in ["pro-crud", "propresenter-api"] {
				expectNoDifference(
					SkillAgent.allCases.map {
						$0.skillDirectory(
							named: skillName,
							homeDirectory: homeDirectory,
							environment: environment,
						).path
					},
					skillRoots.map { URL(fileURLWithPath: $0).appendingPathComponent(skillName).path },
				)
			}
		}
	}

	@Test func installsAllBundledSkillsAsSymlinksIdempotently() throws {
		try withTemporaryDirectory { directory in
			let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
			let skillDirectories = try makeSkillDirectories(in: directory)
			let installer = SkillInstaller(
				homeDirectory: homeDirectory,
				environment: [:],
				fileManager: .default,
				skillDirectoriesByName: skillDirectories,
			)
			let agents: [SkillAgent] = [.claude, .codex]
			let skillNames = skillDirectories.keys.sorted()

			let installations = try installer.install(for: agents, force: false)
			expectNoDifference(
				installations.map(\.skillName),
				agents.flatMap { _ in skillNames },
			)
			expectNoDifference(
				installations.map(\.agent),
				agents.flatMap { agent in skillNames.map { _ in agent } },
			)
			expectNoDifference(installations.map(\.outcome), Array(repeating: .installed, count: 4))
			for agent in agents {
				for skillName in skillNames {
					let destination = agent.skillDirectory(
						named: skillName,
						homeDirectory: homeDirectory,
						environment: [:],
					)
					try expectSymbolicLink(destination, pointsTo: #require(skillDirectories[skillName]))
				}
			}

			try expectNoDifference(
				installer.install(for: agents, force: false).map(\.outcome),
				Array(repeating: .unchanged, count: 4),
			)
		}
	}

	@Test func replacesPreviouslyCopiedMatchingSkillWithoutForce() throws {
		try withTemporaryDirectory { directory in
			let fileManager = FileManager.default
			let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
			let skillDirectories = try makeSkillDirectories(in: directory)
			let source = try #require(skillDirectories["pro-crud"])
			let destination = SkillAgent.codex.skillDirectory(
				named: "pro-crud",
				homeDirectory: homeDirectory,
				environment: [:],
			)
			try fileManager.createDirectory(
				at: destination.deletingLastPathComponent(),
				withIntermediateDirectories: true,
			)
			try fileManager.copyItem(at: source, to: destination)
			let installer = SkillInstaller(
				homeDirectory: homeDirectory,
				environment: [:],
				fileManager: fileManager,
				skillDirectoriesByName: ["pro-crud": source],
			)

			let installation = try #require(installer.install(for: [.codex], force: false).first)
			expectNoDifference(installation.outcome, .updated)
			try expectSymbolicLink(destination, pointsTo: source)
		}
	}

	@Test func replacesPreviouslyCopiedBundledSkillWithoutForce() throws {
		try withTemporaryDirectory { directory in
			let fileManager = FileManager.default
			let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
			let source = try #require(CLIResources.agentSkillDirectories["pro-crud"])
			let destination = SkillAgent.codex.skillDirectory(
				named: "pro-crud",
				homeDirectory: homeDirectory,
				environment: [:],
			)
			try fileManager.createDirectory(
				at: destination.deletingLastPathComponent(),
				withIntermediateDirectories: true,
			)
			try fileManager.copyItem(at: source, to: destination)
			let installer = SkillInstaller(
				homeDirectory: homeDirectory,
				environment: [:],
				fileManager: fileManager,
				skillDirectoriesByName: ["pro-crud": source],
			)

			let installation = try #require(installer.install(for: [.codex], force: false).first)
			expectNoDifference(installation.outcome, .updated)
			try expectSymbolicLink(destination, pointsTo: source)
		}
	}

	@Test func protectsModifiedOrExtendedCopiedSkillsWithoutForce() throws {
		try withTemporaryDirectory { directory in
			let fileManager = FileManager.default
			let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
			let skillDirectories = try makeSkillDirectories(in: directory)
			let source = try #require(skillDirectories["pro-crud"])
			let destination = SkillAgent.codex.skillDirectory(
				named: "pro-crud",
				homeDirectory: homeDirectory,
				environment: [:],
			)
			try fileManager.createDirectory(
				at: destination.deletingLastPathComponent(),
				withIntermediateDirectories: true,
			)
			try fileManager.copyItem(at: source, to: destination)
			try "user notes\n".write(
				to: destination.appendingPathComponent("notes.md"),
				atomically: true,
				encoding: .utf8,
			)
			let installer = SkillInstaller(
				homeDirectory: homeDirectory,
				environment: [:],
				fileManager: fileManager,
				skillDirectoriesByName: ["pro-crud": source],
			)

			do {
				_ = try installer.install(for: [.codex], force: false)
				Issue.record("Expected an extended copied skill to require --force")
			} catch let error as SkillInstallError {
				expectNoDifference(
					error,
					.conflict(skillName: "pro-crud", agent: .codex, destination: destination),
				)
			}
			#expect(fileManager.fileExists(atPath: destination.appendingPathComponent("notes.md").path))

			try fileManager.removeItem(at: destination.appendingPathComponent("notes.md"))
			try "modified\n".write(
				to: destination.appendingPathComponent("SKILL.md"),
				atomically: true,
				encoding: .utf8,
			)
			do {
				_ = try installer.install(for: [.codex], force: false)
				Issue.record("Expected a modified copied skill to require --force")
			} catch let error as SkillInstallError {
				expectNoDifference(
					error,
					.conflict(skillName: "pro-crud", agent: .codex, destination: destination),
				)
			}
		}
	}

	@Test func wrongAndBrokenSymlinksRequireForce() throws {
		try withTemporaryDirectory { directory in
			let fileManager = FileManager.default
			let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
			let source = try #require(makeSkillDirectories(in: directory)["pro-crud"])
			let destination = SkillAgent.codex.skillDirectory(
				named: "pro-crud",
				homeDirectory: homeDirectory,
				environment: [:],
			)
			try fileManager.createDirectory(
				at: destination.deletingLastPathComponent(),
				withIntermediateDirectories: true,
			)
			try fileManager.createSymbolicLink(
				at: destination,
				withDestinationURL: directory.appendingPathComponent("missing-skill"),
			)
			let installer = SkillInstaller(
				homeDirectory: homeDirectory,
				environment: [:],
				fileManager: fileManager,
				skillDirectoriesByName: ["pro-crud": source],
			)

			do {
				_ = try installer.install(for: [.codex], force: false)
				Issue.record("Expected a broken symlink to require --force")
			} catch let error as SkillInstallError {
				expectNoDifference(
					error,
					.conflict(skillName: "pro-crud", agent: .codex, destination: destination),
				)
			}

			let installation = try #require(installer.install(for: [.codex], force: true).first)
			expectNoDifference(installation.outcome, .updated)
			try expectSymbolicLink(destination, pointsTo: source)
		}
	}

	@Test func preflightsEveryInstallationBeforeWritingAndForceReplacesWholeSkill() throws {
		try withTemporaryDirectory { directory in
			let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
			let fileManager = FileManager.default
			let skillDirectories = try makeSkillDirectories(in: directory)
			let installer = SkillInstaller(
				homeDirectory: homeDirectory,
				environment: [:],
				fileManager: fileManager,
				skillDirectoriesByName: skillDirectories,
			)
			let conflictingDestination = SkillAgent.codex.skillDirectory(
				named: "propresenter-api",
				homeDirectory: homeDirectory,
				environment: [:],
			)
			try fileManager.createDirectory(at: conflictingDestination, withIntermediateDirectories: true)
			try "custom skill\n".write(
				to: conflictingDestination.appendingPathComponent("SKILL.md"),
				atomically: true,
				encoding: .utf8,
			)
			try "keep me\n".write(
				to: conflictingDestination.appendingPathComponent("notes.md"),
				atomically: true,
				encoding: .utf8,
			)

			do {
				_ = try installer.install(for: [.claude, .codex], force: false)
				Issue.record("Expected a differing skill to require --force")
			} catch let error as SkillInstallError {
				expectNoDifference(
					error,
					.conflict(
						skillName: "propresenter-api",
						agent: .codex,
						destination: conflictingDestination,
					),
				)
			}

			for agent in [SkillAgent.claude, .codex] {
				let proCRUDDestination = agent.skillDirectory(
					named: "pro-crud",
					homeDirectory: homeDirectory,
					environment: [:],
				)
				#expect(!fileManager.fileExists(atPath: proCRUDDestination.path))
			}
			let claudeAPIDestination = SkillAgent.claude.skillDirectory(
				named: "propresenter-api",
				homeDirectory: homeDirectory,
				environment: [:],
			)
			#expect(!fileManager.fileExists(atPath: claudeAPIDestination.path))

			try expectNoDifference(
				installer.install(for: [.claude, .codex], force: true).map(\.outcome),
				[.installed, .installed, .installed, .updated],
			)
			for agent in [SkillAgent.claude, .codex] {
				for skillName in skillDirectories.keys {
					let destination = agent.skillDirectory(
						named: skillName,
						homeDirectory: homeDirectory,
						environment: [:],
					)
					try expectSymbolicLink(destination, pointsTo: #require(skillDirectories[skillName]))
				}
			}
			#expect(!fileManager.fileExists(atPath: conflictingDestination.appendingPathComponent("notes.md").path))
		}
	}

	@Test func missingBundledSkillFailsBeforeWriting() throws {
		try withTemporaryDirectory { directory in
			let homeDirectory = directory.appendingPathComponent("home", isDirectory: true)
			let missingSource = directory.appendingPathComponent("Missing.bundle/skills/pro-crud")
			let installer = SkillInstaller(
				homeDirectory: homeDirectory,
				environment: [:],
				fileManager: .default,
				skillDirectoriesByName: ["pro-crud": missingSource],
			)

			do {
				_ = try installer.install(for: [.codex], force: false)
				Issue.record("Expected a missing bundled skill to fail")
			} catch let error as SkillInstallError {
				expectNoDifference(
					error,
					.invalidSource(skillName: "pro-crud", source: missingSource),
				)
			}
			let destination = SkillAgent.codex.skillDirectory(
				named: "pro-crud",
				homeDirectory: homeDirectory,
				environment: [:],
			)
			#expect(!FileManager.default.fileExists(atPath: destination.path))
		}
	}
}

private func makeSkillDirectories(in directory: URL) throws -> [String: URL] {
	let fileManager = FileManager.default
	let skillsDirectory = directory.appendingPathComponent(
		"ProCRUD_ProCRUDCLI.bundle/skills",
		isDirectory: true,
	)
	let proCRUD = skillsDirectory.appendingPathComponent("pro-crud", isDirectory: true)
	try fileManager.createDirectory(
		at: proCRUD.appendingPathComponent("references", isDirectory: true),
		withIntermediateDirectories: true,
	)
	try fileManager.createDirectory(
		at: proCRUD.appendingPathComponent("assets/themes", isDirectory: true),
		withIntermediateDirectories: true,
	)
	try "---\nname: pro-crud\n---\n".write(
		to: proCRUD.appendingPathComponent("SKILL.md"),
		atomically: true,
		encoding: .utf8,
	)
	try "Reference\n".write(
		to: proCRUD.appendingPathComponent("references/format.md"),
		atomically: true,
		encoding: .utf8,
	)
	try Data([0x00, 0xFF, 0x7F]).write(
		to: proCRUD.appendingPathComponent("assets/themes/Design.proTheme"),
		options: .atomic,
	)

	let api = skillsDirectory.appendingPathComponent("propresenter-api", isDirectory: true)
	try fileManager.createDirectory(
		at: api.appendingPathComponent("references", isDirectory: true),
		withIntermediateDirectories: true,
	)
	try "---\nname: propresenter-api\n---\n".write(
		to: api.appendingPathComponent("SKILL.md"),
		atomically: true,
		encoding: .utf8,
	)
	try "API reference\n".write(
		to: api.appendingPathComponent("references/api.md"),
		atomically: true,
		encoding: .utf8,
	)

	return [
		"pro-crud": proCRUD,
		"propresenter-api": api,
	]
}

private func expectSymbolicLink(_ link: URL, pointsTo expectedDestination: URL) throws {
	let fileManager = FileManager.default
	let attributes = try fileManager.attributesOfItem(atPath: link.path)
	#expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
	let destinationPath = try fileManager.destinationOfSymbolicLink(atPath: link.path)
	let destination = URL(
		fileURLWithPath: destinationPath,
		relativeTo: link.deletingLastPathComponent(),
	).standardizedFileURL
	#expect(destination.path == expectedDestination.standardizedFileURL.path)
}

private func withTemporaryDirectory<Result>(_ operation: (URL) throws -> Result) throws -> Result {
	let fileManager = FileManager.default
	let directory = fileManager.temporaryDirectory
		.appendingPathComponent("pro-crud-skill-tests-\(UUID().uuidString)", isDirectory: true)
	try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? fileManager.removeItem(at: directory) }
	return try operation(directory)
}
