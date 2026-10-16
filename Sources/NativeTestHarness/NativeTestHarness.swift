import ArgumentParser
import CryptoKit
import Darwin
import Foundation
import ProCRUDCore

/// Contributor-only preflight. Does not launch applications, stop processes,
/// replace helpers, migrate workspaces, or claim native acceptance.
@main
struct NativeTestHarness: AsyncParsableCommand {
	@Option(help: "JSON profile for the authorized local test account, workspace and pinned application.") var profile: String
	@Option(help: "Run manifest path, written even when a preflight check fails.") var output: String
	@Option(help: "Disposable native Presentation UUID for an offline metadata experiment.") var documentID: String?
	@Option(help: "Experimental: commit this copyright title only after the pinned local/offline preflight passes. Requires --document-id.") var setCopyrightTitle: String?

	func run() async throws {
		let configuration = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: URL(fileURLWithPath: profile)))
		guard (documentID == nil) == (setCopyrightTitle == nil), documentID == nil || documentID.flatMap(UUID.init(uuidString:)) != nil else {
			throw ValidationError("Provide both --document-id UUID and --set-copyright-title for an offline metadata experiment, or omit both for preflight only.")
		}
		var checks: [Check] = []
		var notApplicableChecks: [String] = []
		func check(_ name: String, _ passed: Bool, _ detail: String) {
			checks.append(Check(name: name, passed: passed, detail: detail))
		}
		let applicationURL = URL(fileURLWithPath: configuration.applicationPath).resolvingSymlinksInPath()
		let root = URL(fileURLWithPath: configuration.workspaceRoot).resolvingSymlinksInPath()
		check("workspace-profile-storage", configuration.storage == .nativeLoro || configuration.storage == .legacyProtobuf, "Select a legacy or native workspace, not an interchange export.")
		check("workspace-profile-identity", configuration.storage != .nativeLoro || configuration.workspaceID.flatMap(UUID.init(uuidString:)) != nil, "Native profiles must pin a workspace UUID.")
		check("isolated-account", NSUserName() == configuration.accountName, "Expected account \(configuration.accountName); current account \(NSUserName()).")
		let bundle = Bundle(url: applicationURL)
		let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		let build = bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
		check("application-version", version == configuration.applicationVersion, "Expected \(configuration.applicationVersion); found \(version ?? "unavailable").")
		check("application-build", build == configuration.applicationBuild, "Expected \(configuration.applicationBuild); found \(build ?? "unavailable").")
		let signature = try process("/usr/bin/codesign", ["--verify", "--deep", "--strict", applicationURL.path])
		check("application-signature", signature.status == 0, signature.status == 0 ? "Signature verified." : signature.text)
		let identity = try process("/usr/bin/codesign", ["-dv", "--verbose=2", applicationURL.path])
		check("application-team", identity.status == 0 && identity.text.split(separator: "\n").contains(Substring("TeamIdentifier=\(configuration.teamIdentifier)")), "Expected signing team \(configuration.teamIdentifier).")

		let helperRoot = URL(fileURLWithPath: configuration.helperRoot).resolvingSymlinksInPath()
		let expectedHelperRoot = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent("Library/Application Support/RenewedVision/ProPresenter/Helpers/Workspaces").resolvingSymlinksInPath()
		check("helper-location", helperRoot == expectedHelperRoot, "Helper installation must belong to the selected test account.")
		let helperOwner = try? FileManager.default.attributesOfItem(atPath: helperRoot.path)[.ownerAccountID] as? NSNumber
		check("helper-owner", helperOwner?.uint32Value == getuid(), "Helper root must exist and be owned by user ID \(getuid()).")
		let helperExecutable = URL(fileURLWithPath: configuration.helperExecutable).resolvingSymlinksInPath()
		let containedHelper = helperRoot == expectedHelperRoot && helperExecutable.path.hasPrefix(helperRoot.path + "/")
		check("helper-executable-location", containedHelper, "Pin an executable within this account's helper installation.")
		if containedHelper {
			do {
				let attributes = try FileManager.default.attributesOfItem(atPath: helperExecutable.path)
				let owner = attributes[.ownerAccountID] as? NSNumber
				let hash = try SHA256.hash(data: Data(contentsOf: helperExecutable, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
				check("helper-executable-owner", owner?.uint32Value == getuid(), "Pinned helper must belong to this account.")
				check("helper-executable-hash", hash == configuration.helperSHA256.lowercased(), "Pinned helper SHA-256 must match the qualified version; no helper replacement was attempted.")
			} catch { check("helper-executable", false, String(describing: error)) }
		}
		let processes = try process("/bin/ps", ["-axo", "uid=,pid=,comm="])
		let writers = processes.text.split(separator: "\n").compactMap { line -> String? in
			let columns = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
			guard columns.count == 3 else { return nil }
			let path = String(columns[2])
			let name = URL(fileURLWithPath: path).lastPathComponent
			guard path.contains("/Helpers/Workspaces/") || path == helperExecutable.path || name == "ProPresenter" || name.hasPrefix("ProPresenter Helper (") else { return nil }
			return "uid \(columns[0]), pid \(columns[1]): \(path)"
		}
		check("offline-writers-stopped", processes.status == 0 && writers.isEmpty, writers.isEmpty ? "No ProPresenter UI/helper writers; other test sessions must also be stopped." : writers.joined(separator: "; "))

		let api: URL?
		if let configuredAPI = configuration.apiBaseURL {
			guard let url = URL(string: configuredAPI), url.scheme == "http", url.host == "127.0.0.1", url.port != nil else {
				throw ValidationError("apiBaseURL must explicitly identify an http://127.0.0.1:PORT test endpoint.")
			}
			api = url
		} else {
			api = nil; notApplicableChecks.append("offline-api-stopped: no API endpoint configured")
		}
		guard (configuration.syphonSourceUUID == nil) == (configuration.snapSyphonExecutable == nil) else {
			throw ValidationError("Provide both snapSyphonExecutable and syphonSourceUUID, or omit both when no Syphon output is configured.")
		}
		if let source = configuration.syphonSourceUUID, UUID(uuidString: source) == nil {
			throw ValidationError("syphonSourceUUID must be a source UUID discovered with snap-syphon list --json.")
		}
		if checks.allSatisfy(\.passed) {
			if let api {
				var request = URLRequest(url: api.appendingPathComponent("version"))
				request.timeoutInterval = 2
				do {
					_ = try await URLSession.shared.data(for: request)
					check("offline-api-stopped", false, "The configured API endpoint is still serving requests.")
				} catch let error as URLError where error.code == .cannotConnectToHost {
					check("offline-api-stopped", true, "Configured API endpoint is not listening.")
				} catch { check("offline-api-stopped", false, "Cannot prove the API is stopped: \(String(describing: error))") }
			}
			if let executable = configuration.snapSyphonExecutable, let source = configuration.syphonSourceUUID {
				do {
					let sources = try process(executable, ["list", "--json"])
					let array = try JSONSerialization.jsonObject(with: Data(sources.text.utf8)) as? [Any]
					check("offline-output-stopped", sources.status == 0 && array != nil && !sources.text.lowercased().contains(source.lowercased()), "Configured Syphon source must not be active during offline experiments.")
				} catch { check("offline-output-stopped", false, String(describing: error)) }
			} else {
				notApplicableChecks.append("offline-output-stopped: no Syphon output configured")
			}
		}

		// Resolve storage only after process/account/build checks, before any
		// experiment can be authorized by this preflight result.
		var storage: WorkspaceInspection?
		if checks.allSatisfy(\.passed) {
			do {
				let inspection = try WorkspaceInspector.inspect(root)
				storage = inspection
				check("workspace-storage", inspection.storage == configuration.storage, "Expected \(configuration.storage.rawValue); found \(inspection.storage.rawValue).")
				if let expectedID = configuration.workspaceID {
					check("workspace-identity", inspection.workspaceID?.lowercased() == expectedID.lowercased(), "Expected workspace \(expectedID).")
				}
				if configuration.storage == .nativeLoro, checks.allSatisfy(\.passed) {
					guard let registry = configuration.registryPath else { throw ValidationError("Native profiles require registryPath.") }
					if setCopyrightTitle != nil {
						try NativeLocalWorkspaceWriter.withOfflineWriteAccess(to: root, registry: URL(fileURLWithPath: registry)) { _ in
							check("registered-local-workspace", true, "Offline writer setup verified one matching local registration; Cloud writes are rejected.")
						}
					} else {
						let entries = try WorkspaceRegistry.read(from: URL(fileURLWithPath: registry))
						let matching = entries.filter { URL(fileURLWithPath: $0.root).resolvingSymlinksInPath() == root }
						check("registered-local-workspace", matching.count == 1 && matching.first?.cloudID == nil && matching.first?.localID.lowercased() == inspection.workspaceID?.lowercased(), "Expected one matching local workspace registration. Cloud writes are rejected.")
					}
				}
			} catch { check("workspace-inspection", false, String(describing: error)) }
		}
		var committedOperations: [NativeLocalCommitReceipt] = []
		if let documentID, let id = UUID(uuidString: documentID), let title = setCopyrightTitle, checks.allSatisfy(\.passed) {
			do {
				guard configuration.storage == .nativeLoro, let registry = configuration.registryPath else { throw ValidationError("The metadata experiment requires a registered native local workspace.") }
				committedOperations = try NativeLocalWorkspaceWriter.edit(.copyrightTitle(title), documentID: id, in: root, registry: URL(fileURLWithPath: registry))
				if !committedOperations.isEmpty {
					check("native-metadata-commit", true, "Committed targeted Loro operations and a durable receipt; native reopen/edit acceptance remains a separate check.")
				} else {
					check("native-metadata-no-op", true, "Value already matches; no history, database rows, or receipt were changed.")
				}
			} catch { check("native-metadata-commit", false, String(describing: error)) }
		}
		let manifest = Manifest(date: Date(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
		                        profile: configuration, checks: checks, notApplicableChecks: notApplicableChecks, committedOperations: committedOperations, workspace: storage, passed: checks.allSatisfy(\.passed))
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		encoder.dateEncodingStrategy = .iso8601
		let outputURL = URL(fileURLWithPath: output)
		try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		try encoder.encode(manifest).write(to: outputURL, options: .atomic)
		print("\(manifest.passed ? "Preflight passed" : "Preflight failed"): \(outputURL.path)")
		if !manifest.passed {
			throw ExitCode.failure
		}
	}

	private func process(_ executable: String, _ arguments: [String]) throws -> (status: Int32, text: String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		try process.run()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, String(decoding: data, as: UTF8.self))
	}
}

private struct Profile: Codable {
	var accountName: String
	var applicationPath: String
	var applicationVersion: String
	var applicationBuild: String
	var teamIdentifier: String
	var workspaceRoot: String
	var workspaceID: String?
	var storage: WorkspaceStorage
	var registryPath: String?
	var helperRoot: String
	var helperExecutable: String
	var helperSHA256: String
	var apiBaseURL: String?
	var snapSyphonExecutable: String?
	var syphonSourceUUID: String?
}

private struct Check: Codable {
	var name: String
	var passed: Bool
	var detail: String
}

private struct Manifest: Encodable {
	var date: Date
	var operatingSystem: String
	var profile: Profile
	var checks: [Check]
	var notApplicableChecks: [String]
	var committedOperations: [NativeLocalCommitReceipt]
	var workspace: WorkspaceInspection?
	var passed: Bool
}
