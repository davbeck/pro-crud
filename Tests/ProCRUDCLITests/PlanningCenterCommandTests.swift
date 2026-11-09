import ArgumentParser
import CustomDump
import Testing
@testable import ProCRUDCLI

struct PlanningCenterCommandTests {
	@Test func parsesUploadAndExactDestination() throws {
		let command = try ProCRUD.parseAsRoot(["planning-center", "attachments", "upload", "Song.pro", "--song", "12", "--arrangement", "34", "--dry-run"])
		let upload = try #require(command as? PlanningCenterAttachmentUpload)
		expectNoDifference(upload.song, "12")
		expectNoDifference(upload.arrangement, "34")
		#expect(upload.dryRun)
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
