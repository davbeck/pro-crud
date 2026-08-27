import ArgumentParser
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing
@testable import ProCRUDCLI

@Suite("Validate command")
struct ValidateCommandTests {
	@Test
	func defaultsToWorkspaceIndependentHumanValidation() throws {
		let command = try Validate.parse(["Document.pro"])

		#expect(command.format == .human)
		#expect(command.workspace == nil)
		#expect(!command.strictMedia)
		#expect(Validate.configuration.abstract.contains("structure"))
	}

	@Test
	func emitsVersionlessJSONWithStableDiagnosticFields() throws {
		try withValidationTemporaryDirectory { directory in
			let input = directory.appendingPathComponent("Invalid.pro")
			var presentation = DocumentFactory.presentation(name: "Invalid")
			presentation.selectedArrangement.string = "UNKNOWN-ARRANGEMENT"
			presentation.cues[0].actions[0].slide.presentation.baseSlide.size.width = 0
			try presentation.serializedData().write(to: input)

			let command = try Validate.parse([input.path, "--format", "json"])
			let report = try command.makeReport()
			let output = try command.formattedOutput(for: report)
			let object = try #require(
				JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
			)
			let diagnostics = try #require(object["diagnostics"] as? [[String: Any]])

			#expect(object["schemaVersion"] == nil)
			#expect(object["valid"] as? Bool == false)
			#expect(diagnostics.contains { diagnostic in
				diagnostic["code"] as? String == "structure.unknown-selected-arrangement" &&
					diagnostic["severity"] as? String == "error" &&
					diagnostic["componentPath"] as? String == "/selected_arrangement" &&
					!(diagnostic["message"] as? String ?? "").isEmpty
			})
		}
	}

	@Test
	func reportsStructuralFailuresThatNormalDocumentLoadingRejects() throws {
		try withValidationTemporaryDirectory { directory in
			let input = directory.appendingPathComponent("DuplicateCue.pro")
			var presentation = DocumentFactory.presentation(name: "Duplicate cue")
			var duplicate = presentation.cues[0]
			duplicate.name = "Duplicate"
			presentation.cues.append(duplicate)
			try presentation.serializedData().write(to: input)

			#expect(throws: DocumentLoadError.self) {
				_ = try DocumentLoader.load(from: input)
			}

			let command = try Validate.parse([input.path, "--format", "json"])
			let report = try command.makeReport()
			#expect(!report.valid)
			#expect(report.diagnostics.contains {
				$0.code == "structure.duplicate-cue-uuid" && $0.severity == .error
			})
		}
	}

	@Test
	func preservesDecodeFailuresAsCommandErrors() throws {
		try withValidationTemporaryDirectory { directory in
			let input = directory.appendingPathComponent("NotProtobuf.pro")
			try Data("not protobuf".utf8).write(to: input)
			let command = try Validate.parse([input.path, "--format", "json"])

			#expect(throws: DocumentLoadError.self) {
				_ = try command.makeReport()
			}
		}
	}

	@Test
	func formatsStrictMediaThemeDocumentPath() throws {
		let report = DocumentValidationReport(diagnostics: [
			DocumentValidationDiagnostic(strictMedia: StrictMediaDiagnostic(
				kind: .missingAsset,
				documentPath: "Teaching/Theme",
				componentPath: "/slides[index=0]/base_slide/elements[index=0]/element/fill/media/url",
				message: "Media asset was not found.",
			)),
		])
		let human = try Validate.parse(["Theme"]).formattedOutput(for: report)
		#expect(human.contains("Error [media.missing-asset] in Teaching/Theme at /slides[index=0]"))

		let json = try Validate.parse(["Theme", "--format", "json"]).formattedOutput(for: report)
		let object = try #require(
			JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
		)
		let diagnostics = try #require(object["diagnostics"] as? [[String: Any]])
		#expect(diagnostics.first?["documentPath"] as? String == "Teaching/Theme")
		#expect((diagnostics.first?["componentPath"] as? String)?.hasPrefix("/slides[index=0]") == true)
	}

	@Test
	func exitsWithFailureWhenReportContainsErrors() throws {
		try withValidationTemporaryDirectory { directory in
			let input = directory.appendingPathComponent("Invalid.pro")
			var presentation = DocumentFactory.presentation(name: "Invalid")
			presentation.cues[0].actions[0].slide.presentation.baseSlide.size.height = 0
			try presentation.serializedData().write(to: input)
			let command = try Validate.parse([input.path, "--format", "json"])

			do {
				try command.run()
				Issue.record("Expected validation failure")
			} catch let exitCode as ExitCode {
				#expect(exitCode == .failure)
			}
		}
	}

	@Test
	func strictMediaRequiresWorkspaceAndWorkspaceRequiresStrictMedia() throws {
		let missingWorkspace = try Validate.parse(["Document.pro", "--strict-media"])
		#expect(throws: ValidationError.self) {
			_ = try missingWorkspace.makeReport()
		}

		let unusedWorkspace = try Validate.parse(["Document.pro", "--workspace", "/tmp/Workspace"])
		#expect(throws: ValidationError.self) {
			_ = try unusedWorkspace.makeReport()
		}
	}
}

private func withValidationTemporaryDirectory<Result>(
	_ operation: (URL) throws -> Result,
) throws -> Result {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("pro-crud-validation-command-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: directory) }
	return try operation(directory)
}
