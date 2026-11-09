import CustomDump
import Foundation
import Synchronization
import Testing
@testable import PlanningCenterKit

private final class MemoryCredentials: PlanningCenterCredentialStore {
	let value: Mutex<PlanningCenterCredentials?>
	init(_ credentials: PlanningCenterCredentials? = nil) {
		value = Mutex(credentials)
	}

	func load() -> PlanningCenterCredentials? {
		value.withLock { $0 }
	}

	func save(_ credentials: PlanningCenterCredentials) {
		value.withLock { $0 = credentials }
	}

	func delete() {
		value.withLock { $0 = nil }
	}
}

private actor HTTPFixture {
	typealias Step = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
	var steps: [Step]
	var requests: [URLRequest] = []
	init(_ steps: [Step]) {
		self.steps = steps
	}

	func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
		requests.append(request)
		let step = try #require(!steps.isEmpty ? steps.removeFirst() : nil)
		return try step(request)
	}

	var transport: PlanningCenterTransport {
		PlanningCenterTransport(send: { try await self.send($0) }, download: { _ in
			Issue.record("Unexpected file download")
			throw PlanningCenterError.invalidResponse
		})
	}
}

private func response(_ request: URLRequest, _ json: String, status: Int = 200, headers: [String: String] = [:]) throws -> (Data, HTTPURLResponse) {
	let url = try #require(request.url)
	return try (Data(json.utf8), #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)))
}

private let person = #"{"data":{"type":"Person","id":"42","attributes":{"name":"Test Person"}}}"#
private let pat = PlanningCenterCredentials(method: .personalAccessToken, clientID: "test-id", secret: "test-secret")

struct PlanningCenterOAuthTests {
	@Test func pkceMatchesRFC7636AndRequestsServicesWithoutSecret() throws {
		let oauth = try PlanningCenterOAuth(clientID: "public-client", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "test-state")
		expectNoDifference(oauth.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
		let url = try oauth.authorizationURL()
		let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
		let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
		expectNoDifference(fields["scope"], "services")
		expectNoDifference(fields["redirect_uri"], PlanningCenterOAuth.callbackURL)
		expectNoDifference(fields["code_challenge_method"], "S256")
		#expect(fields["client_secret"] == nil)
		#expect(fields["code_verifier"] == nil)
	}

	@Test func callbacksRequirePathStateAndOneCode() throws {
		let oauth = try PlanningCenterOAuth(clientID: "client", state: "expected")
		try expectNoDifference(oauth.code(from: "/oauth/callback?state=expected&code=ok"), "ok")
		for target in ["/other?state=expected&code=ok", "/oauth/callback?state=wrong&code=ok", "/oauth/callback?state=expected&state=expected&code=ok", "/oauth/callback?state=expected&code=a&code=b"] {
			#expect(throws: PlanningCenterError.self) { try oauth.code(from: target) }
		}
		#expect(throws: PlanningCenterError.self) { try oauth.code(from: "/oauth/callback?state=expected&error=access_denied") }
	}

	@Test func formEncodingPreservesReservedCharacters() {
		let data = PlanningCenterOAuth.form(["code": "a+b&c=d /?", "client_id": "test"])
		expectNoDifference(String(decoding: data, as: UTF8.self), "client_id=test&code=a%2Bb%26c%3Dd%20%2F%3F")
	}

	@Test func emptyClientIDIsUnavailable() {
		#expect(throws: PlanningCenterError.self) { try PlanningCenterOAuth(clientID: "") }
	}
}

struct PlanningCenterClientTests {
	@Test func patLoginValidatesBeforeSavingAndDoesNotRequireOAuth() async throws {
		let store = MemoryCredentials()
		let fixture = HTTPFixture([{ request in
			expectNoDifference(request.url?.path, "/services/v2/me")
			expectNoDifference(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("test-id:test-secret".utf8).base64EncodedString())
			#expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("pro-crud") == true)
			return try response(request, person)
		}])
		let client = await PlanningCenterClient(store: store, transport: fixture.transport)
		try await client.signIn(personalClientID: "test-id", secret: "test-secret")
		expectNoDifference(store.load()?.method, .personalAccessToken)
		try await client.signOut()
		#expect(store.load() == nil)
	}

	@Test func failedLoginRetainsPriorCredentialsAndRedactsResponseBody() async throws {
		let store = MemoryCredentials(pat)
		let fixture = HTTPFixture([{ request in try response(request, "test-secret must never be printed", status: 401) }])
		let client = await PlanningCenterClient(store: store, transport: fixture.transport)
		do {
			try await client.signIn(personalClientID: "bad", secret: "bad")
			Issue.record("Expected rejection")
		} catch {
			#expect(!error.localizedDescription.contains("test-secret"))
		}
		expectNoDifference(store.load()?.clientID, "test-id")
	}

	@Test func oauthExchangesCodeWithoutSecretAndRefreshesExpiredToken() async throws {
		let now = Date(timeIntervalSince1970: 1000)
		let store = MemoryCredentials()
		let fixture = HTTPFixture([
			{ request in
				let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
				#expect(body.contains("code_verifier=verifier"))
				#expect(body.contains("grant_type=authorization_code"))
				#expect(!body.contains("client_secret"))
				#expect(request.value(forHTTPHeaderField: "Authorization") == nil)
				return try response(request, #"{"access_token":"first","refresh_token":"refresh","expires_in":10,"token_type":"bearer"}"#)
			},
			{ request in
				let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
				#expect(body.contains("grant_type=refresh_token"))
				#expect(body.contains("refresh_token=refresh"))
				#expect(!body.contains("client_secret"))
				return try response(request, #"{"access_token":"second","refresh_token":"rotated","expires_in":7200,"token_type":"bearer"}"#)
			},
			{ request in
				expectNoDifference(request.value(forHTTPHeaderField: "Authorization"), "Bearer second")
				return try response(request, person)
			},
		])
		let client = await PlanningCenterClient(store: store, transport: fixture.transport, now: { now })
		try await client.signIn(oauth: PlanningCenterOAuth(clientID: "public", verifier: "verifier", state: "state"), code: "code")
		let identity = try await client.identity()
		expectNoDifference(identity.id, "42")
		expectNoDifference(store.load()?.refreshToken, "rotated")
		expectNoDifference(store.load()?.expiresAt, now.addingTimeInterval(7200))
	}

	@Test func paginationFollowsCollectionAndRejectsCrossOriginLinks() async throws {
		let fixture = HTTPFixture([
			{ request in try response(request, #"{"data":[{"type":"Song","id":"1","links":{"arrangement":null,"self":"https://api.planningcenteronline.com/services/v2/songs/1"}}],"links":{"next":"https://api.planningcenteronline.com/services/v2/songs?offset=100"}}"#) },
			{ request in
				#expect(request.url?.query?.contains("offset=100") == true)
				return try response(request, #"{"data":[{"type":"Song","id":"2"}],"links":{"next":null}}"#)
			},
		])
		let client = await PlanningCenterClient(store: MemoryCredentials(pat), transport: fixture.transport)
		let songs = try await client.list(path: "songs")
		expectNoDifference(songs.map(\.id), ["1", "2"])
		let hostile = HTTPFixture([{ request in try response(request, #"{"data":[],"links":{"next":"https://example.com/steal"}}"#) }])
		let other = await PlanningCenterClient(store: MemoryCredentials(pat), transport: hostile.transport)
		await #expect(throws: PlanningCenterError.self) { try await other.list(path: "songs") }
		let requests = await hostile.requests
		expectNoDifference(requests.count, 1)
	}

	@Test func rateLimitReportsRetryIntervalWithoutAutomaticReplay() async throws {
		let fixture = HTTPFixture([{ request in try response(request, "{}", status: 429, headers: ["Retry-After": "19"]) }])
		let client = await PlanningCenterClient(store: MemoryCredentials(pat), transport: fixture.transport)
		do {
			_ = try await client.list(path: "songs")
			Issue.record("Expected rate limit")
		} catch {
			#expect(error.localizedDescription.contains("19"))
		}
		let requests = await fixture.requests
		expectNoDifference(requests.count, 1)
	}

	@Test func targetsRejectAmbiguityAndPathInjection() throws {
		try expectNoDifference(PlanningCenterTarget(song: "1", arrangement: "2", key: "3").path, "songs/1/arrangements/2/keys/3")
		#expect(throws: PlanningCenterError.self) { try PlanningCenterTarget(song: "1", arrangement: "2", media: "3") }
		#expect(throws: PlanningCenterError.self) { try PlanningCenterTarget(song: "../1", arrangement: "2") }
		#expect(throws: PlanningCenterError.self) { try PlanningCenterTarget(media: "0") }
	}

	@Test func uploadAssociatesFileUUIDWithExactArrangementAndVerifies() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent("Song.pro")
		try Data("presentation-bytes".utf8).write(to: file)
		let fixture = HTTPFixture([
			{ request in
				expectNoDifference(request.url?.host, "upload.planningcenteronline.com")
				expectNoDifference(request.httpMethod, "POST")
				let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
				#expect(body.contains("filename=\"Song.pro\""))
				#expect(body.contains("presentation-bytes\r\n--pro-crud-"))
				return try response(request, #"{"data":[{"type":"File","id":"file-uuid"}]}"#)
			},
			{ request in
				expectNoDifference(request.url?.path, "/services/v2/songs/1/arrangements/2/attachments")
				let payload = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
				expectNoDifference(payload, .object(["data": .object(["type": .string("Attachment"), "attributes": .object(["filename": .string("Song.pro"), "file_upload_identifier": .string("file-uuid")])])]))
				return try response(request, #"{"data":{"type":"Attachment","id":"3","attributes":{"filename":"Song.pro"}}}"#)
			},
			{ request in
				expectNoDifference(request.httpMethod, "GET")
				expectNoDifference(request.url?.path, "/services/v2/songs/1/arrangements/2/attachments/3")
				return try response(request, #"{"data":{"type":"Attachment","id":"3","attributes":{"filename":"Song.pro"}}}"#)
			},
		])
		let client = await PlanningCenterClient(store: MemoryCredentials(pat), transport: fixture.transport)
		let receipt = try await client.upload(presentation: file, to: PlanningCenterTarget(song: "1", arrangement: "2"))
		expectNoDifference(receipt.id, "3")
		let requests = await fixture.requests
		expectNoDifference(requests.count, 3)
	}

	@Test func downloadOmitsCredentialsAndRefusesToOverwrite() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let downloaded = directory.appendingPathComponent("incoming")
		let output = directory.appendingPathComponent("Song.pro")
		try Data("downloaded-presentation".utf8).write(to: downloaded)
		let fixture = HTTPFixture([{ request in
			expectNoDifference(request.httpMethod, "POST")
			expectNoDifference(request.url?.path, "/services/v2/songs/1/arrangements/2/attachments/3/open")
			return try response(request, #"{"data":{"type":"AttachmentActivity","id":"4","attributes":{"attachment_url":"https://files.example.com/signed"}}}"#)
		}])
		let transport = PlanningCenterTransport(send: { try await fixture.send($0) }, download: { request in
			#expect(request.value(forHTTPHeaderField: "Authorization") == nil)
			let url = try #require(request.url)
			let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
			return (downloaded, response)
		})
		let client = PlanningCenterClient(store: MemoryCredentials(pat), transport: transport)
		let target = try PlanningCenterTarget(song: "1", arrangement: "2")
		try await client.download(attachmentID: "3", at: target, to: output)
		try expectNoDifference(Data(contentsOf: output), Data("downloaded-presentation".utf8))
		await #expect(throws: CocoaError.self) { try await client.download(attachmentID: "3", at: target, to: output) }
		let requests = await fixture.requests
		expectNoDifference(requests.count, 1)
	}
}

struct PlanningCenterCallbackTests {
	@Test func loopbackServerRejectsUnrelatedRequestsThenAcceptsMatchingCode() async throws {
		let callback = try PlanningCenterCallback(port: 0)
		let port = try callback.localPort
		let oauth = try PlanningCenterOAuth(clientID: "client", state: "expected")
		let pending = Task { try await callback.wait(for: oauth, timeout: .seconds(5)) }
		defer { pending.cancel() }
		let invalid = try #require(URL(string: "http://127.0.0.1:\(port)/oauth/callback?state=wrong&code=bad"))
		let (_, invalidResponse) = try await URLSession.shared.data(from: invalid)
		expectNoDifference((invalidResponse as? HTTPURLResponse)?.statusCode, 400)
		let valid = try #require(URL(string: "http://127.0.0.1:\(port)/oauth/callback?state=expected&code=good"))
		let (_, validResponse) = try await URLSession.shared.data(from: valid)
		expectNoDifference((validResponse as? HTTPURLResponse)?.statusCode, 200)
		let code = try await pending.value
		expectNoDifference(code, "good")
	}

	@Test func waitingCanBeCancelled() async throws {
		let callback = try PlanningCenterCallback(port: 0)
		let oauth = try PlanningCenterOAuth(clientID: "client")
		let pending = Task { try await callback.wait(for: oauth) }
		pending.cancel()
		await #expect(throws: CancellationError.self) { try await pending.value }
	}

	@Test func missingCallbackTimesOut() async throws {
		let callback = try PlanningCenterCallback(port: 0)
		let oauth = try PlanningCenterOAuth(clientID: "client")
		await #expect(throws: PlanningCenterError.self) { try await callback.wait(for: oauth, timeout: .milliseconds(1)) }
	}
}

struct PlanningCenterCallbackReuseTests {
	@Test func callbackPortCanBeReusedAfterSuccessfulLogin() async throws {
		func completeLogin() async throws -> UInt16 {
			let callback = try PlanningCenterCallback(port: 0)
			let port = try callback.localPort
			let oauth = try PlanningCenterOAuth(clientID: "client", state: "expected")
			let pending = Task { try await callback.wait(for: oauth, timeout: .seconds(5)) }
			defer { pending.cancel() }
			let url = try #require(URL(string: "http://127.0.0.1:\(port)/oauth/callback?state=expected&code=ok"))
			_ = try await URLSession.shared.data(from: url)
			_ = try await pending.value
			return port
		}
		let port = try await completeLogin()
		let next = try PlanningCenterCallback(port: port)
		try expectNoDifference(next.localPort, port)
	}
}
