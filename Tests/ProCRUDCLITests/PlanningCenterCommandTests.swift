import ArgumentParser
import CustomDump
import Foundation
import PlanningCenterKit
import ProCRUDCore
import Testing
@testable import ProCRUDCLI

struct PlanningCenterCommandTests {
	@Test func parsesUploadAndExactDestination() throws {
		let command = try ProCRUD.parseAsRoot(["planning-center", "attachments", "upload", "Song.pro", "--song", "12", "--arrangement", "34", "--dry-run"])
		let upload = try #require(command as? PlanningCenterAttachmentUpload)
		expectNoDifference(upload.destination.song, "12")
		expectNoDifference(upload.destination.arrangement, "34")
		#expect(upload.dryRun)
	}

	@Test func parsesDirectPlanItemUpload() throws {
		let command = try ProCRUD.parseAsRoot(["planning-center", "attachments", "upload", "Sermon.pro", "--service-type", "12", "--plan", "34", "--item", "56", "--dry-run"])
		let upload = try #require(command as? PlanningCenterAttachmentUpload)
		let target = try upload.destination.target()
		expectNoDifference(target.path, "service_types/12/plans/34/items/56")
		try target.validateUpload()
		#expect(upload.dryRun)
	}

	@Test(arguments: [
		["--song", "12", "--arrangement", "34"],
		["--service-type", "12", "--plan", "34", "--item", "56"],
	])
	func dryRunValidatesPresentationWithoutAuthentication(options: [String]) async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let input = directory.appendingPathComponent("Presentation.pro")
		let bytes = try DocumentFactory.presentation(name: "Upload dry run").serializedData()
		try bytes.write(to: input)
		let command = try ProCRUD.parseAsRoot(["planning-center", "attachments", "upload", input.path, "--dry-run"] + options)
		let upload = try #require(command as? PlanningCenterAttachmentUpload)
		try await upload.run()
		#expect(try Data(contentsOf: input) == bytes)
	}

	@Test(arguments: [
		[], ["--service-type", "12"], ["--item", "56"],
		["--service-type", "12", "--plan", "34"],
		["--song", "12", "--arrangement", "34", "--item", "56"],
		["--media", "12"], ["--song", "12", "--arrangement", "34", "--key", "56"],
		["--service-type", "12", "--plan", "34", "--item", "../56"],
	])
	func uploadRejectsUnsupportedDestinationsBeforeLoadingFile(options: [String]) async throws {
		let command = try ProCRUD.parseAsRoot(["planning-center", "attachments", "upload", "Missing.pro", "--dry-run"] + options)
		let upload = try #require(command as? PlanningCenterAttachmentUpload)
		await #expect(throws: PlanningCenterError.self) { try await upload.run() }
	}

	@Test func parsesPATLoginRegardlessOfCompiledOAuthConfiguration() throws {
		let command = try ProCRUD.parseAsRoot(["planning-center", "login", "--personal-access-token"])
		let login = try #require(command as? PlanningCenterLogin)
		#expect(login.personalAccessToken)
	}

	@Test func discoveryRequiresParentIDs() throws {
		let command = try ProCRUD.parseAsRoot(["planning-center", "list", "items"])
		let list = try #require(command as? PlanningCenterList)
		#expect(throws: (any Error).self) { try list.path() }
	}

	@Test func downloadRejectsAmbiguousTargets() throws {
		let command = try ProCRUD.parseAsRoot(["planning-center", "attachments", "download", "1", "--song", "2", "--arrangement", "3", "--media", "4", "--output", "Song.pro"])
		let download = try #require(command as? PlanningCenterAttachmentDownload)
		#expect(throws: (any Error).self) { try download.source.target() }
	}
}
