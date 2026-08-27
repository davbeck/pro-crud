import Foundation

enum CLIResources {
	static let agentSkillDirectories: [String: URL] = {
		do {
			let children = try FileManager.default.contentsOfDirectory(
				at: requiredDirectory(named: "skills"),
				includingPropertiesForKeys: [.isDirectoryKey],
				options: [.skipsHiddenFiles],
			)
			return try Dictionary(uniqueKeysWithValues: children.compactMap { child in
				guard try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
					return nil
				}
				return (child.lastPathComponent, child)
			})
		} catch {
			fatalError("The bundled agent skills are unavailable: \(error)")
		}
	}()

	static let agentSkills: [String: [String: Data]] = {
		do {
			return try agentSkillDirectories.mapValues { try files(in: $0) }
		} catch {
			fatalError("The bundled agent skills are invalid: \(error)")
		}
	}()

	static let formatDocumentation = textFiles(
		in: requiredDirectory(named: "Format"),
		withExtension: "md",
	)

	static let protobufSources = textFiles(
		in: requiredDirectory(named: "Protobuf/proto"),
		withExtension: "proto",
	)

	static let protobufMetadata: [String: String] = {
		do {
			let directory = requiredDirectory(named: "Protobuf")
			return try Dictionary(uniqueKeysWithValues: ["content-sha256.txt", "revision.txt"].map { filename in
				try (
					filename,
					String(contentsOf: directory.appendingPathComponent(filename), encoding: .utf8),
				)
			})
		} catch {
			fatalError("The bundled protobuf metadata is unavailable: \(error)")
		}
	}()

	static let protobufNotices: [String: String] = {
		do {
			let directory = requiredDirectory(named: "Protobuf")
			return try Dictionary(uniqueKeysWithValues: ["LICENSE", "README.md"].map { filename in
				try (
					filename,
					String(contentsOf: directory.appendingPathComponent(filename), encoding: .utf8),
				)
			})
		} catch {
			preconditionFailure("Missing bundled protobuf notices: \(error)")
		}
	}()

	private static func requiredDirectory(named name: String) -> URL {
		guard let resourceURL = Bundle.module.resourceURL else {
			fatalError("The pro-crud resource bundle is unavailable.")
		}
		let directory = resourceURL.appendingPathComponent(name, isDirectory: true)
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
		      isDirectory.boolValue
		else {
			fatalError("The bundled resource directory \(name) is unavailable.")
		}
		return directory
	}

	private static func files(in directory: URL) throws -> [String: Data] {
		guard let enumerator = FileManager.default.enumerator(
			at: directory,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles],
		) else {
			throw CocoaError(.fileReadUnknown)
		}
		var files: [String: Data] = [:]
		for case let url as URL in enumerator {
			guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
				continue
			}
			let path = String(url.path.dropFirst(directory.path.count + 1))
			files[path] = try Data(contentsOf: url)
		}
		return files
	}

	private static func textFiles(
		in directory: URL,
		withExtension pathExtension: String,
	) -> [String: String] {
		do {
			return try files(in: directory).reduce(into: [:]) { result, entry in
				guard URL(fileURLWithPath: entry.key).pathExtension == pathExtension else { return }
				guard let value = String(data: entry.value, encoding: .utf8) else {
					throw CocoaError(.fileReadInapplicableStringEncoding)
				}
				result[entry.key] = value
			}
		} catch {
			fatalError("The bundled text resources in \(directory.lastPathComponent) are invalid: \(error)")
		}
	}
}
