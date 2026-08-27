import ArgumentParser
import Foundation
import ProCRUDCore

struct Validate: ParsableCommand {
	enum Format: String, CaseIterable, ExpressibleByArgument {
		case human
		case json
	}

	static let configuration = CommandConfiguration(
		abstract: "Validate ProPresenter document structure, rendering state, and optional workspace media integrity.",
	)

	@Argument(help: "Path to a raw document, workspace directory, or bundle.") var input: String
	@Option(help: "Output format: human (default) or json.") var format: Format = .human
	@Option(help: "ProPresenter workspace root used by --strict-media.") var workspace: String?
	@Flag(help: "Also fail on missing, inconsistent, or conflicting workspace media identity. Requires --workspace.") var strictMedia = false

	func run() throws {
		let report = try makeReport()
		try print(formattedOutput(for: report), terminator: "")
		if !report.valid {
			throw ExitCode.failure
		}
	}

	func makeReport() throws -> DocumentValidationReport {
		guard strictMedia || workspace == nil else {
			throw ValidationError("--workspace requires --strict-media.")
		}
		guard !strictMedia || workspace != nil else {
			throw ValidationError("--strict-media requires --workspace.")
		}

		let document = try DocumentLoader.loadForValidation(from: URL(fileURLWithPath: input))
		var diagnostics = DocumentValidator.validate(document).diagnostics
		if let workspace {
			let mediaReport = try StrictMediaValidator.validate(
				document,
				workspaceURL: URL(fileURLWithPath: workspace, isDirectory: true),
			)
			diagnostics.append(contentsOf: mediaReport.diagnostics.map(DocumentValidationDiagnostic.init(strictMedia:)))
		}
		return DocumentValidationReport(diagnostics: diagnostics)
	}

	func formattedOutput(for report: DocumentValidationReport) throws -> String {
		switch format {
		case .json:
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
			return try String(decoding: encoder.encode(report), as: UTF8.self) + "\n"
		case .human:
			var output = report.diagnostics.map(\.description).joined(separator: "\n")
			if !output.isEmpty {
				output += "\n"
			}
			let errorCount = report.diagnostics.count { $0.severity == .error }
			let warningCount = report.diagnostics.count { $0.severity == .warning }
			if report.valid {
				output += warningCount == 0
					? "Validation passed.\n"
					: "Validation passed with \(warningCount) \(pluralized("warning", count: warningCount)).\n"
			} else {
				output += "Validation failed with \(errorCount) \(pluralized("error", count: errorCount))"
				if warningCount > 0 {
					output += " and \(warningCount) \(pluralized("warning", count: warningCount))"
				}
				output += ".\n"
			}
			return output
		}
	}

	private func pluralized(_ word: String, count: Int) -> String {
		count == 1 ? word : "\(word)s"
	}
}
