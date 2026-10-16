import Foundation
import Testing
@testable import ProCRUDCore

@Suite("Legacy workspace preference discovery")
struct WorkspacePreferencesTests {
	@Test func customRetainedAndUnavailableRootsRemainIndependentHints() throws {
		let entries: [[String: Any]] = [
			["url": "file:///Volumes/Shows%20%26%20Media/Custom%20Workspace/", "name": "Sunday", "isActive": true, "minimumRequiredProPresenterVersion": "21.4.0"],
			["url": "file:///Users/owner/UserWorkspaces/Retained/", "name": "Sunday", "isActive": true, "minimumRequiredProPresenterVersion": "22.0.0"],
			["url": "file://localhost/missing/disconnected/", "name": "Unavailable", "isActive": false],
		]
		try withPreferences(["userWorkspaces": JSONSerialization.data(withJSONObject: entries), "unrelated": ["opaque": "not returned"]]) { url in
			let before = try Data(contentsOf: url)
			let report = try WorkspacePreferences.read(from: url)
			#expect(report.map(\.root) == ["/Volumes/Shows & Media/Custom Workspace", "/Users/owner/UserWorkspaces/Retained", "/missing/disconnected"])
			#expect(report.map(\.displayName) == ["Sunday", "Sunday", "Unavailable"])
			#expect(report.map(\.isActiveHint) == [true, true, false])
			#expect(report.map(\.minimumRequiredProPresenterVersionHint) == ["21.4.0", "22.0.0", nil])
			#expect(try Data(contentsOf: url) == before)
			let json = try String(decoding: JSONEncoder().encode(report), as: UTF8.self)
			#expect(!json.contains("unrelated") && !json.contains("opaque"))
		}
		try withPreferences([:]) { url in
			let entries = try WorkspacePreferences.read(from: url)
			#expect(entries.isEmpty)
		}
	}

	@Test func malformedMetadataAndNonlocalURLsFailWithoutPartialResults() throws {
		for value: Any in ["wrong type", Data("not json".utf8), Data("[{\"url\":1}]".utf8)] {
			try withPreferences(["userWorkspaces": value]) { url in
				#expect(throws: WorkspacePreferenceError.self) { try WorkspacePreferences.read(from: url) }
			}
		}
		for path in ["https://example.invalid/workspace", "relative/path", "file://remote-host/Shows/", "file:///Shows/?query=x", "file:///Shows/#fragment"] {
			let entries = [["url": "file:///Valid/", "name": "Valid", "isActive": false], ["url": path, "name": "Invalid", "isActive": true]] as [[String: Any]]
			try withPreferences(["userWorkspaces": JSONSerialization.data(withJSONObject: entries)]) { url in
				#expect(throws: WorkspacePreferenceError.self) { try WorkspacePreferences.read(from: url) }
			}
		}
	}

	private func withPreferences(_ contents: [String: Any], body: (URL) throws -> Void) throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-preferences-\(UUID()).plist")
		try PropertyListSerialization.data(fromPropertyList: contents, format: .binary, options: 0).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }
		try body(url)
	}
}
