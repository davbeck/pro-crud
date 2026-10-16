import ArgumentParser
import Foundation
import Testing
@testable import NativeTestHarness

@Suite("Native environment preflight")
struct NativeTestHarnessTests {
	@Test
	func mismatchedAccountAndApplicationWriteFailureManifestWithoutInspectingWorkspace() async throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let workspace = root.appendingPathComponent("Must Not Inspect")
		let store = workspace.appendingPathComponent("DocumentStore")
		try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
		let sentinel = Data("untouched workspace".utf8)
		let database = store.appendingPathComponent("workspace-v1.sqlite3")
		try sentinel.write(to: database)
		let profile: [String: Any] = [
			"accountName": "pro-crud-negative-control-account",
			"applicationPath": root.appendingPathComponent("Missing.app").path,
			"applicationVersion": "22.0",
			"applicationBuild": "369098875",
			"teamIdentifier": "negative-control",
			"workspaceRoot": workspace.path,
			"workspaceID": UUID().uuidString,
			"storage": "native-loro-sqlite",
			"helperRoot": root.appendingPathComponent("Missing helper").path,
			"helperExecutable": root.appendingPathComponent("Missing helper/executable").path,
			"helperSHA256": String(repeating: "0", count: 64),
			"apiBaseURL": "http://127.0.0.1:1",
			"snapSyphonExecutable": "/usr/bin/false",
			"syphonSourceUUID": UUID().uuidString,
		]
		let profileURL = root.appendingPathComponent("profile.json")
		try JSONSerialization.data(withJSONObject: profile).write(to: profileURL)
		let output = root.appendingPathComponent("manifest.json")
		let command = try NativeTestHarness.parse(["--profile", profileURL.path, "--output", output.path])
		do {
			try await command.run()
			Issue.record("Mismatched environment must fail preflight.")
		} catch let error as ExitCode { #expect(error == .failure) }
		let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
		#expect(manifest["passed"] as? Bool == false)
		#expect(manifest["workspace"] == nil)
		let checks = try #require(manifest["checks"] as? [[String: Any]])
		#expect(checks.contains { $0["name"] as? String == "isolated-account" && $0["passed"] as? Bool == false })
		#expect(!checks.contains { $0["name"] as? String == "workspace-inspection" })
		#expect(!checks.contains { $0["name"] as? String == "offline-api-stopped" })
		#expect(try Data(contentsOf: database) == sentinel)
	}
}
