import ArgumentParser
import Foundation
import ProCRUDCore
import Testing
@testable import ProCRUDCLI

@Suite("Compatibility command arguments")
struct CompatibilityCommandTests {
	@Test
	func creationAndExportDefaultTo22AndAccept21() throws {
		#expect(try CreatePresentation.parse(["--output", "/tmp/New.pro"]).target.targetVersion == .v22)
		#expect(try CreatePresentation.parse(["--output", "/tmp/New.pro", "--target-version", "21"]).target.targetVersion == .v21)
		#expect(try CreateTheme.parse(["--output", "/tmp/Theme", "--target-version", "21"]).target.targetVersion == .v21)
		#expect(try CreatePlaylist.parse(["--output", "/tmp/data", "--target-version", "21"]).target.targetVersion == .v21)
		#expect(try BundleCommand.parse(["/tmp/New.pro"]).target.targetVersion == .v22)
		#expect(try BundleCommand.parse(["/tmp/New.pro", "--target-version", "21", "--json"]).target.targetVersion == .v21)
	}

	@Test
	func invalidAndImplicitEditConversionsAreRejected() {
		#expect(throws: (any Error).self) { try CreatePresentation.parse(["--output", "/tmp/New.pro", "--target-version", "23"]) }
		#expect(throws: (any Error).self) { try BundleCommand.parse(["/tmp/New.pro", "--target-version", "7"]) }
		#expect(throws: (any Error).self) { try EditApply.parse(["/tmp/New.pro", "--file", "/tmp/edits.json", "--target-version", "21"]) }
	}

	@Test
	func inspectionAndRegistryDiscoveryRequireExplicitRoots() throws {
		#expect(try WorkspaceInspect.parse(["/tmp/Exact"]).input == "/tmp/Exact")
		#expect(throws: (any Error).self) { try WorkspaceDiscover.parse([]) }
		#expect(try WorkspaceDiscover.parse(["--registry", "/tmp/registry-v1.sqlite3"]).registry == "/tmp/registry-v1.sqlite3")
	}

	@Test
	func qualifiedNativeMetadataCommandRequiresExactIdentityAndRegistration() throws {
		let id = UUID().uuidString
		let arguments = ["/tmp/Exact", "--stream", id, "--registry", "/tmp/registry-v1.sqlite3", "--title", "A title with punctuation: ’"]
		let command = try WorkspaceSetCopyrightTitle.parse(arguments)
		#expect(command.input == "/tmp/Exact")
		#expect(command.stream == id)
		#expect(command.registry == "/tmp/registry-v1.sqlite3")
		#expect(command.title == "A title with punctuation: ’")
		#expect(try WorkspaceSetCopyrightTitle.parse(["/tmp/Exact", "--stream", id, "--registry", "/tmp/registry-v1.sqlite3", "--title", ""]).title.isEmpty)
		#expect(throws: (any Error).self) { try WorkspaceSetCopyrightTitle.parse(["/tmp/Exact", "--stream", "not-a-uuid", "--registry", "/tmp/registry-v1.sqlite3", "--title", "X"]) }
		#expect(throws: (any Error).self) { try WorkspaceSetCopyrightTitle.parse(["/tmp/Exact", "--stream", id, "--title", "X"]) }
		#expect(throws: (any Error).self) { try WorkspaceSetCopyrightTitle.parse(arguments + ["--target-version", "21"]) }
		#expect(try ProCRUD.parseAsRoot(["workspace", "set-copyright-title"] + arguments) is WorkspaceSetCopyrightTitle)
	}
}
