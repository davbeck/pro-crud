import Foundation

public struct PlanningCenterTransport: Sendable {
	public var send: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
	public var download: @Sendable (URLRequest) async throws -> (URL, HTTPURLResponse)

	public init(
		send: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse),
		download: @escaping @Sendable (URLRequest) async throws -> (URL, HTTPURLResponse),
	) {
		self.send = send
		self.download = download
	}

	public static let live = Self(send: { request in
		let (data, response) = try await apiSession.data(for: request)
		guard let response = response as? HTTPURLResponse else { throw PlanningCenterError.invalidResponse }
		return (data, response)
	}, download: { request in
		let (url, response) = try await fileSession.download(for: request)
		guard let response = response as? HTTPURLResponse else { throw PlanningCenterError.invalidResponse }
		return (url, response)
	})

	private static let apiSession = URLSession(configuration: .ephemeral, delegate: PlanningCenterRedirectPolicy(allowFileRedirects: false), delegateQueue: nil)
	private static let fileSession = URLSession(configuration: .ephemeral, delegate: PlanningCenterRedirectPolicy(allowFileRedirects: true), delegateQueue: nil)
}

private final class PlanningCenterRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
	let allowFileRedirects: Bool
	init(allowFileRedirects: Bool) {
		self.allowFileRedirects = allowFileRedirects
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
	                newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void)
	{
		// Authenticated API calls must never redirect credentials. File requests may
		// follow HTTPS storage redirects without acquiring API authorization.
		guard allowFileRedirects, request.url?.scheme == "https", request.url?.user == nil, request.url?.password == nil else {
			completionHandler(nil)
			return
		}
		var next = request
		next.setValue(nil, forHTTPHeaderField: "Authorization")
		completionHandler(next)
	}
}

public actor PlanningCenterClient {
	private let store: any PlanningCenterCredentialStore
	private let transport: PlanningCenterTransport
	private let now: @Sendable () -> Date
	private let sleep: @Sendable (Duration) async throws -> Void
	private static let root = "https://api.planningcenteronline.com/services/v2/"
	private static let userAgent = "pro-crud (https://github.com/davbeck/pro-crud)"

	public init(store: any PlanningCenterCredentialStore = PlanningCenterKeychain(), transport: PlanningCenterTransport = .live,
	            now: @escaping @Sendable () -> Date = { Date() },
	            sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })
	{
		self.store = store
		self.transport = transport
		self.now = now
		self.sleep = sleep
	}

	public func signIn(personalClientID: String, secret: String) async throws {
		let credentials = PlanningCenterCredentials(method: .personalAccessToken, clientID: personalClientID, secret: secret)
		_ = try await request(url: apiURL("me"), credentials: credentials)
		try store.save(credentials)
	}

	public func signIn(oauth: PlanningCenterOAuth, code: String) async throws {
		let credentials = try await token(fields: [
			"grant_type": "authorization_code", "client_id": oauth.clientID,
			"redirect_uri": PlanningCenterOAuth.callbackURL, "code_verifier": oauth.verifier, "code": code,
		], clientID: oauth.clientID)
		try store.save(credentials)
	}

	public func signOut() throws {
		try store.delete()
	}

	public func identity() async throws -> PlanningCenterResource {
		let data = try await request(url: apiURL("me"))
		return try JSONDecoder().decode(PlanningCenterDocument<PlanningCenterResource>.self, from: data).data
	}

	public func authenticationMethod() throws -> PlanningCenterCredentials.Method? {
		try store.load()?.method
	}

	/// Follows only same-origin Services pagination links; never follows resource actions.
	public func list(path: String, query: [URLQueryItem] = []) async throws -> [PlanningCenterResource] {
		var components = try URLComponents(url: apiURL(path), resolvingAgainstBaseURL: false)
		components?.queryItems = [URLQueryItem(name: "per_page", value: "100")] + query
		guard let first = components?.url else { throw PlanningCenterError.invalidResponse }
		var next: URL? = first
		var visited = Set<URL>()
		var resources: [PlanningCenterResource] = []
		while let url = next {
			try Task.checkCancellation()
			guard Self.isAPIURL(url), url.path == first.path, visited.insert(url).inserted else {
				throw PlanningCenterError.invalidResponse
			}
			let data = try await request(url: url)
			let document = try JSONDecoder().decode(PlanningCenterDocument<[PlanningCenterResource]>.self, from: data)
			resources.append(contentsOf: document.data)
			if let link = document.links?["next"] ?? nil {
				next = URL(string: link, relativeTo: url)?.absoluteURL
				guard next != nil else { throw PlanningCenterError.invalidResponse }
			} else {
				next = nil
			}
		}
		return resources
	}

	public func attachments(at target: PlanningCenterTarget) async throws -> [PlanningCenterResource] {
		try await list(path: target.path + "/attachments")
	}

	/// Creates a song arrangement or direct plan-item attachment. Never replaces or deletes an existing attachment.
	public func upload(presentation: URL, to target: PlanningCenterTarget) async throws -> PlanningCenterResource {
		try target.validateUpload()
		let filename = presentation.lastPathComponent
		guard !filename.contains("\r"), !filename.contains("\n"), !filename.contains("\""), filename.lowercased().hasSuffix(".pro") else {
			throw PlanningCenterError.invalidTarget
		}
		let boundary = "pro-crud-" + UUID().uuidString
		var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
		try body.append(Data(contentsOf: presentation))
		body.append(Data("\r\n--\(boundary)--\r\n".utf8))
		guard let uploadURL = URL(string: "https://upload.planningcenteronline.com/v2/files") else { throw PlanningCenterError.invalidResponse }
		let uploaded = try await request(url: uploadURL, method: "POST", contentType: "multipart/form-data; boundary=\(boundary)", body: body)
		let files = try JSONDecoder().decode(PlanningCenterDocument<[PlanningCenterResource]>.self, from: uploaded)
		guard let fileID = files.data.first?.id else { throw PlanningCenterError.invalidResponse }
		let payload: JSONValue = .object(["data": .object([
			"type": .string("Attachment"), "attributes": .object([
				"file_upload_identifier": .string(fileID), "filename": .string(filename),
			]),
		])])
		let createdData = try await request(url: apiURL(target.path + "/attachments"), method: "POST", body: JSONEncoder().encode(payload))
		let created = try JSONDecoder().decode(PlanningCenterDocument<PlanningCenterResource>.self, from: createdData).data
		do {
			let verified = try await request(url: apiURL(target.path + "/attachments/" + PlanningCenterTarget.validatedID(created.id)))
			let attachment = try JSONDecoder().decode(PlanningCenterDocument<PlanningCenterResource>.self, from: verified).data
			guard attachment.id == created.id, attachment.attributes?["filename"]?.string == filename else {
				throw PlanningCenterError.uploadAssociationFailed(fileID: fileID)
			}
			return attachment
		} catch is CancellationError { throw CancellationError() }
		catch { throw PlanningCenterError.uploadAssociationFailed(fileID: fileID) }
	}

	/// Saves to a new file. The file host receives no Planning Center credentials.
	public func download(attachmentID: String, at target: PlanningCenterTarget, to output: URL) async throws {
		guard !FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
		let id = try PlanningCenterTarget.validatedID(attachmentID)
		let data = try await openAttachment(url: apiURL(target.path + "/attachments/\(id)/open"))
		let activity = try JSONDecoder().decode(PlanningCenterDocument<PlanningCenterResource>.self, from: data).data
		guard let address = activity.attributes?["attachment_url"]?.string, let url = URL(string: address),
		      url.scheme == "https", url.host != nil, url.user == nil, url.password == nil
		else { throw PlanningCenterError.invalidResponse }
		var request = URLRequest(url: url)
		request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
		let (file, response) = try await transport.download(request)
		defer { try? FileManager.default.removeItem(at: file) }
		try Self.check(response)
		// copyItem fails if output appeared while the download was in progress.
		try FileManager.default.copyItem(at: file, to: output)
	}

	private func openAttachment(url: URL) async throws -> Data {
		// Newly created attachments can precede their S3 object by a few seconds.
		// Only replay the explicitly rejected open action, never file/attachment creation.
		let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
		for delay in delays {
			do { return try await request(url: url, method: "POST") }
			catch PlanningCenterError.attachmentNotReady { try await sleep(delay) }
		}
		return try await request(url: url, method: "POST")
	}

	private func apiURL(_ path: String) throws -> URL {
		guard let url = URL(string: Self.root + path), Self.isAPIURL(url),
		      !path.contains(".."), !path.contains("?"), !path.contains("#")
		else { throw PlanningCenterError.invalidTarget }
		return url
	}

	private static func isAPIURL(_ url: URL) -> Bool {
		url.scheme == "https" && url.host == "api.planningcenteronline.com" && (url.port == nil || url.port == 443)
			&& url.user == nil && url.password == nil && url.path.hasPrefix("/services/v2/")
	}

	private func credentials() async throws -> PlanningCenterCredentials {
		guard let saved = try store.load() else { throw PlanningCenterError.notLoggedIn }
		guard saved.method == .oauth, let expires = saved.expiresAt, expires <= now().addingTimeInterval(60) else { return saved }
		guard let refresh = saved.refreshToken else { throw PlanningCenterError.notLoggedIn }
		let updated = try await token(fields: ["grant_type": "refresh_token", "client_id": saved.clientID, "refresh_token": refresh], clientID: saved.clientID)
		try store.save(updated)
		return updated
	}

	private func request(url: URL, method: String = "GET", contentType: String = "application/json", body: Data? = nil,
	                     credentials supplied: PlanningCenterCredentials? = nil) async throws -> Data
	{
		let auth: PlanningCenterCredentials
		if let supplied {
			auth = supplied
		} else {
			auth = try await credentials()
		}
		var request = URLRequest(url: url)
		request.httpMethod = method
		request.httpBody = body
		request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("2018-11-01", forHTTPHeaderField: "X-PCO-API-Version")
		if body != nil {
			request.setValue(contentType, forHTTPHeaderField: "Content-Type")
		}
		switch auth.method {
		case .oauth: request.setValue("Bearer " + auth.secret, forHTTPHeaderField: "Authorization")
		case .personalAccessToken:
			request.setValue("Basic " + Data("\(auth.clientID):\(auth.secret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
		}
		let (data, response) = try await transport.send(request)
		if response.statusCode == 422, url.path.hasSuffix("/open"),
		   let failure = try? JSONDecoder().decode(PlanningCenterAPIFailure.self, from: data),
		   failure.errors.contains(where: { $0.detail == "File does not exist on S3. Please try again later." })
		{
			throw PlanningCenterError.attachmentNotReady
		}
		try Self.check(response)
		return data
	}

	private func token(fields: [String: String], clientID: String) async throws -> PlanningCenterCredentials {
		guard let url = URL(string: "https://api.planningcenteronline.com/oauth/token") else { throw PlanningCenterError.invalidResponse }
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.httpBody = PlanningCenterOAuth.form(fields)
		request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		let (data, response) = try await transport.send(request)
		try Self.check(response)
		let token = try JSONDecoder().decode(OAuthToken.self, from: data)
		guard !token.access_token.isEmpty, !token.refresh_token.isEmpty, token.token_type.lowercased() == "bearer" else {
			throw PlanningCenterError.invalidResponse
		}
		return PlanningCenterCredentials(method: .oauth, clientID: clientID, secret: token.access_token,
		                                 refreshToken: token.refresh_token, expiresAt: now().addingTimeInterval(token.expires_in))
	}

	private static func check(_ response: HTTPURLResponse) throws {
		guard (200 ..< 300).contains(response.statusCode) else {
			throw PlanningCenterError.http(status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
		}
	}
}

private struct PlanningCenterAPIFailure: Decodable {
	struct Entry: Decodable { let detail: String? }
	let errors: [Entry]
}

private struct OAuthToken: Decodable {
	let access_token: String
	let refresh_token: String
	let expires_in: TimeInterval
	let token_type: String
}
