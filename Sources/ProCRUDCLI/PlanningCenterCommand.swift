import ArgumentParser
import Darwin
import Foundation
import PlanningCenterKit
import ProCRUDCore

struct PlanningCenterCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "planning-center",
		abstract: "Sign into Planning Center Services and transfer presentation attachments.",
		subcommands: [PlanningCenterLogin.self, PlanningCenterLogout.self, PlanningCenterStatus.self, PlanningCenterList.self, PlanningCenterAttachments.self],
	)

	static var clientID: String? {
		#if PLANNING_CENTER_OAUTH_CONFIGURED
			let value = Secrets.planningCenterClientId
			return value.isEmpty ? nil : value
		#else
			return nil
		#endif
	}
}

struct PlanningCenterLogin: AsyncParsableCommand {
	static let configuration = CommandConfiguration(commandName: "login", abstract: "Sign in through your browser, or save a personal access token in Keychain.")
	@Flag(help: "Use a personal access token's application ID and secret instead of OAuth.") var personalAccessToken = false
	@Flag(help: "Print the browser sign-in URL without opening it automatically.") var noBrowser = false

	func run() async throws {
		let client = PlanningCenterClient()
		if personalAccessToken {
			guard !noBrowser else { throw ValidationError("--no-browser applies only to OAuth sign-in.") }
			let environment = ProcessInfo.processInfo.environment
			let id = try credential(environment["PLANNING_CENTER_PAT_ID"], prompt: "Personal access token application ID: ", hidden: false)
			let secret = try credential(environment["PLANNING_CENTER_PAT_SECRET"], prompt: "Personal access token secret: ", hidden: true)
			try await client.signIn(personalClientID: id, secret: secret)
		} else {
			guard let id = PlanningCenterCommand.clientID else { throw PlanningCenterError.oauthUnavailable }
			let oauth = try PlanningCenterOAuth(clientID: id)
			let callback = try PlanningCenterCallback()
			let url = try oauth.authorizationURL()
			if noBrowser {
				FileHandle.standardError.write(Data("Open this URL in a browser on this Mac:\n\(url.absoluteString)\n".utf8))
			} else {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
				process.arguments = [url.absoluteString]
				try process.run()
				process.waitUntilExit()
				guard process.terminationStatus == 0 else { throw ValidationError("Could not open your browser. Run login --no-browser.") }
			}
			FileHandle.standardError.write(Data("Waiting for Planning Center authorization (up to 3 minutes)…\n".utf8))
			let code = try await callback.wait(for: oauth)
			try await client.signIn(oauth: oauth, code: code)
		}
		print("Signed into Planning Center. Credentials saved in Keychain.")
	}

	private func credential(_ supplied: String?, prompt: String, hidden: Bool) throws -> String {
		if let supplied, !supplied.isEmpty {
			return supplied
		}
		guard isatty(STDIN_FILENO) != 0 else {
			throw ValidationError("PAT login requires a terminal, or PLANNING_CENTER_PAT_ID and PLANNING_CENTER_PAT_SECRET environment variables.")
		}
		let value: String?
		if hidden {
			value = getpass(prompt).map { String(cString: $0) }
		} else {
			FileHandle.standardError.write(Data(prompt.utf8))
			value = readLine()
		}
		guard let value, !value.isEmpty else { throw ValidationError("A personal access token application ID and secret are required.") }
		return value
	}
}

struct PlanningCenterLogout: AsyncParsableCommand {
	static let configuration = CommandConfiguration(commandName: "logout", abstract: "Remove locally saved Planning Center credentials from Keychain.")
	func run() async throws {
		try await PlanningCenterClient().signOut()
		print("Removed Planning Center credentials from Keychain.")
	}
}

struct PlanningCenterStatus: AsyncParsableCommand {
	static let configuration = CommandConfiguration(commandName: "status", abstract: "Report sign-in state and verify the current Services user.")
	func run() async throws {
		let client = PlanningCenterClient()
		let method = try await client.authenticationMethod()
		var result: [String: JSONValue] = [
			"oauth_available": .bool(PlanningCenterCommand.clientID != nil),
			"signed_in": .bool(method != nil),
		]
		if let method {
			result["method"] = .string(method.rawValue)
			let identity = try await client.identity()
			result["person_id"] = .string(identity.id)
			result["name"] = identity.attributes?["full_name"] ?? .null
		}
		try print(prettyJSON(result))
	}
}

struct PlanningCenterList: AsyncParsableCommand {
	enum Resource: String, ExpressibleByArgument, CaseIterable {
		case serviceTypes = "service-types", plans, items, songs, arrangements, keys, media
	}

	static let configuration = CommandConfiguration(commandName: "list", abstract: "Find Services IDs. Returns JSON resources including associations and follows pagination.")
	@Argument var resource: Resource
	@Option var serviceType: String?
	@Option var plan: String?
	@Option var song: String?
	@Option var arrangement: String?
	@Option(help: "Filter songs by title.") var title: String?

	func path() throws -> String {
		func id(_ value: String?, option: String) throws -> String {
			guard let value else { throw ValidationError("--\(option) is required.") }
			return try PlanningCenterTarget.validatedID(value)
		}
		switch resource {
		case .serviceTypes: return "service_types"
		case .plans: return try "service_types/\(id(serviceType, option: "service-type"))/plans"
		case .items: return try "service_types/\(id(serviceType, option: "service-type"))/plans/\(id(plan, option: "plan"))/items"
		case .songs: return "songs"
		case .arrangements: return try "songs/\(id(song, option: "song"))/arrangements"
		case .keys: return try "songs/\(id(song, option: "song"))/arrangements/\(id(arrangement, option: "arrangement"))/keys"
		case .media: return "media"
		}
	}

	func run() async throws {
		guard title == nil || resource == .songs else { throw ValidationError("--title applies only to songs.") }
		let query = title.map { [URLQueryItem(name: "where[title]", value: $0)] } ?? []
		try await print(prettyJSON(PlanningCenterClient().list(path: path(), query: query)))
	}
}

struct PlanningCenterAttachmentTargetOptions: ParsableArguments {
	@Option(help: "Services song ID.") var song: String?
	@Option(help: "Services arrangement ID within the song.") var arrangement: String?
	@Option(help: "Services key ID within the arrangement (list/download only).") var key: String?
	@Option(help: "Services media ID (list/download only).") var media: String?
	@Option(help: "Services service type ID (list/download only).") var serviceType: String?
	@Option(help: "Services plan ID (list/download only).") var plan: String?
	@Option(help: "Services plan item ID (list/download only).") var item: String?

	func target() throws -> PlanningCenterTarget {
		try PlanningCenterTarget(song: song, arrangement: arrangement, key: key, media: media, serviceType: serviceType, plan: plan, item: item)
	}
}

struct PlanningCenterAttachments: AsyncParsableCommand {
	static let configuration = CommandConfiguration(commandName: "attachments", abstract: "List, upload, or download Services attachments.",
	                                                subcommands: [PlanningCenterAttachmentList.self, PlanningCenterAttachmentUpload.self, PlanningCenterAttachmentDownload.self])
}

struct PlanningCenterAttachmentList: AsyncParsableCommand {
	static let configuration = CommandConfiguration(commandName: "list", abstract: "List attachments at the exact song arrangement, key, media, plan, or item.")
	@OptionGroup var destination: PlanningCenterAttachmentTargetOptions
	func run() async throws {
		try await print(prettyJSON(PlanningCenterClient().attachments(at: destination.target())))
	}
}

struct PlanningCenterAttachmentUpload: AsyncParsableCommand {
	static let configuration = CommandConfiguration(commandName: "upload", abstract: "Validate and add a .pro attachment to a song arrangement, available in every key. Existing attachments remain.")
	@Argument(help: "Path to the individual .pro presentation.") var input: String
	@Option(help: "Destination Services song ID.") var song: String
	@Option(help: "Destination Services arrangement ID.") var arrangement: String
	@Flag(help: "Validate the presentation and report the destination without uploading.") var dryRun = false

	func run() async throws {
		let url = URL(fileURLWithPath: input)
		guard url.pathExtension.lowercased() == "pro" else { throw ValidationError("Upload requires an individual .pro presentation.") }
		let target = try PlanningCenterTarget(song: song, arrangement: arrangement)
		let document = try DocumentLoader.load(from: url)
		guard case .presentation = document.payload else { throw ValidationError("Upload requires a presentation document.") }
		let report = DocumentValidator.validate(document)
		guard report.valid else { throw ValidationError("Presentation validation failed. Run pro-crud validate for details.") }
		if dryRun {
			try print(prettyJSON(["file": url.path, "destination": target.path, "operation": "create-attachment"]))
			return
		}
		let receipt = try await PlanningCenterClient().upload(presentation: url, to: target)
		try print(prettyJSON(receipt))
	}
}

struct PlanningCenterAttachmentDownload: AsyncParsableCommand {
	static let configuration = CommandConfiguration(commandName: "download", abstract: "Download an attachment to a new local file. Does not import it into ProPresenter.")
	@Argument(help: "Attachment ID from attachments list.") var id: String
	@OptionGroup var source: PlanningCenterAttachmentTargetOptions
	@Option(help: "New local output file path; existing files are rejected.") var output: String
	func run() async throws {
		let target = try source.target()
		try await PlanningCenterClient().download(attachmentID: id, at: target, to: URL(fileURLWithPath: output))
		try print(prettyJSON(["attachment_id": id, "output": URL(fileURLWithPath: output).path]))
	}
}
