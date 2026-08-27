import CustomDump
import Foundation
import Testing
@testable import ProCRUDCLI

struct CLIResourcesTests {
	@Test
	func bundlesIndependentSkills() throws {
		expectNoDifference(
			CLIResources.agentSkills.keys.sorted(),
			["pro-crud", "propresenter-api"],
		)
		let proCRUDSkill = try #require(CLIResources.agentSkills["pro-crud"])
		#expect(proCRUDSkill["references/design-guidance.md"] != nil)
		#expect(proCRUDSkill["references/background-sourcing.md"] != nil)
		#expect(proCRUDSkill["references/presentation-authoring.md"] != nil)
		#expect(proCRUDSkill["assets/themes/ProCRUD Design System.proTheme"] != nil)
		#expect(!proCRUDSkill.keys.contains { URL(fileURLWithPath: $0).pathExtension == "probundle" })
		expectNoDifference(
			proCRUDSkill.keys.filter { $0.hasPrefix("assets/") }.sorted(),
			["assets/themes/ProCRUD Design System.proTheme"],
		)
		let backgroundMediaExtensions: Set = [
			"avi", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "m4v", "mkv",
			"mov", "mp4", "mpeg", "mpg", "png", "svg", "tif", "tiff", "webm", "webp",
		]
		#expect(proCRUDSkill.keys.allSatisfy { path in
			!path.hasPrefix("assets/")
				|| !backgroundMediaExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
		})

		let apiSkill = try #require(CLIResources.agentSkills["propresenter-api"])
		#expect(apiSkill["SKILL.md"] != nil)
		#expect(apiSkill["agents/openai.yaml"] != nil)
		#expect(apiSkill["references/api-reference.md"] != nil)
		for contents in apiSkill.values {
			let text = try #require(String(data: contents, encoding: .utf8))
			#expect(!text.localizedCaseInsensitiveContains("pro-crud"))
		}
	}

	@Test
	func bundlesEveryCanonicalExecutableResource() throws {
		let packageRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let protobufRoot = packageRoot.appendingPathComponent("Sources/ProCRUDCLI/Resources/Protobuf")

		try expectNoDifference(
			CLIResources.agentSkills,
			namedFileBundles(in: packageRoot.appendingPathComponent("skills")),
		)
		try expectNoDifference(
			CLIResources.formatDocumentation,
			textFiles(in: packageRoot.appendingPathComponent("Docs/Format"), withExtension: "md"),
		)
		try expectNoDifference(
			CLIResources.protobufSources,
			textFiles(in: protobufRoot.appendingPathComponent("proto"), withExtension: "proto"),
		)
		try expectNoDifference(
			CLIResources.protobufMetadata,
			Dictionary(uniqueKeysWithValues: ["content-sha256.txt", "revision.txt"].map { filename in
				try (filename, String(contentsOf: protobufRoot.appendingPathComponent(filename), encoding: .utf8))
			}),
		)
		try expectNoDifference(
			CLIResources.protobufNotices,
			Dictionary(uniqueKeysWithValues: ["LICENSE", "README.md"].map { filename in
				try (filename, String(contentsOf: protobufRoot.appendingPathComponent(filename), encoding: .utf8))
			}),
		)
	}

	@Test
	func executableBundleContainsCLIDocumentationButNotCoreSchema() throws {
		let skillDirectory = try #require(CLIResources.agentSkillDirectories["pro-crud"])
		let resourceRoot = skillDirectory
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let fileManager = FileManager.default

		for directory in ["skills", "Format", "Protobuf/proto"] {
			var isDirectory: ObjCBool = false
			#expect(fileManager.fileExists(
				atPath: resourceRoot.appendingPathComponent(directory).path,
				isDirectory: &isDirectory,
			))
			#expect(isDirectory.boolValue)
		}
		#expect(!fileManager.fileExists(
			atPath: resourceRoot.appendingPathComponent("Protobuf/schema.pb").path,
		))
	}

	private func namedFileBundles(in directory: URL) throws -> [String: [String: Data]] {
		let children = try FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles],
		)
		return try Dictionary(uniqueKeysWithValues: children.compactMap { child in
			guard try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
				return nil
			}
			return try (child.lastPathComponent, files(in: child))
		})
	}

	private func files(in directory: URL) throws -> [String: Data] {
		guard let enumerator = FileManager.default.enumerator(
			at: directory,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles],
		) else {
			throw CocoaError(.fileNoSuchFile)
		}
		var files: [String: Data] = [:]
		for case let url as URL in enumerator {
			guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
			let path = String(url.path.dropFirst(directory.path.count + 1))
			files[path] = try Data(contentsOf: url)
		}
		return files
	}

	private func textFiles(in directory: URL, withExtension pathExtension: String? = nil) throws -> [String: String] {
		guard let enumerator = FileManager.default.enumerator(
			at: directory,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles],
		) else {
			throw CocoaError(.fileNoSuchFile)
		}
		var files: [String: String] = [:]
		for case let url as URL in enumerator {
			guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
			guard pathExtension == nil || url.pathExtension == pathExtension else { continue }
			let path = String(url.path.dropFirst(directory.path.count + 1))
			files[path] = try String(contentsOf: url, encoding: .utf8)
		}
		return files
	}
}
