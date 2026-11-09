import Darwin
import Foundation

/// A single-use HTTP listener bound only to the registered IPv4 loopback address.
public final class PlanningCenterCallback: Sendable {
	private let descriptor: Int32

	public init(port: UInt16 = 49173) throws {
		let descriptor = socket(AF_INET, SOCK_STREAM, 0)
		guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
		// A completed callback leaves its connection in TIME_WAIT. Permit the next
		// login to bind the registered port immediately after this listener closes.
		var reuse: Int32 = 1
		guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
			let error = POSIXError(.init(rawValue: errno) ?? .EIO)
			close(descriptor)
			throw error
		}
		var address = sockaddr_in()
		address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		address.sin_family = sa_family_t(AF_INET)
		address.sin_port = port.bigEndian
		address.sin_addr.s_addr = inet_addr("127.0.0.1")
		let result = withUnsafePointer(to: &address) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard result == 0, listen(descriptor, 4) == 0 else {
			let error = POSIXError(.init(rawValue: errno) ?? .EIO)
			close(descriptor)
			throw error
		}
		self.descriptor = descriptor
	}

	deinit { close(descriptor) }

	var localPort: UInt16 {
		get throws {
			var address = sockaddr_in()
			var length = socklen_t(MemoryLayout<sockaddr_in>.size)
			let result = withUnsafeMutablePointer(to: &address) {
				$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
			}
			guard result == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
			return UInt16(bigEndian: address.sin_port)
		}
	}

	public func wait(for oauth: PlanningCenterOAuth, timeout: Duration = .seconds(180)) async throws -> String {
		let task = Task.detached { try self.receive(oauth: oauth, timeout: timeout) }
		return try await withTaskCancellationHandler {
			try await task.value
		} onCancel: {
			task.cancel()
		}
	}

	private func receive(oauth: PlanningCenterOAuth, timeout: Duration) throws -> String {
		let deadline = ContinuousClock.now.advanced(by: timeout)
		while ContinuousClock.now < deadline {
			try Task.checkCancellation()
			guard try readable(descriptor, milliseconds: 200) else { continue }
			let client = accept(descriptor, nil, nil)
			guard client >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
			defer { close(client) }
			var noSignal: Int32 = 1
			setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
			var data = Data()
			let requestDeadline = min(deadline, ContinuousClock.now.advanced(by: .seconds(2)))
			while data.count < 8192, ContinuousClock.now < requestDeadline {
				try Task.checkCancellation()
				guard try readable(client, milliseconds: 200) else { continue }
				var buffer = [UInt8](repeating: 0, count: 1024)
				let count = recv(client, &buffer, buffer.count, 0)
				if count <= 0 {
					break
				}
				data.append(contentsOf: buffer.prefix(count))
				if data.range(of: Data("\r\n\r\n".utf8)) != nil {
					break
				}
			}
			let line = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
			let parts = line.split(separator: " ")
			guard parts.count == 3, parts[0] == "GET" else {
				reply(client, status: "400 Bad Request", text: "Invalid sign-in request.")
				continue
			}
			do {
				let code = try oauth.code(from: String(parts[1]))
				reply(client, status: "200 OK", text: "Authorization received. Return to pro-crud to finish signing in.")
				return code
			} catch PlanningCenterError.invalidCallback {
				reply(client, status: "400 Bad Request", text: "This callback does not match the pending sign-in.")
			} catch {
				reply(client, status: "400 Bad Request", text: "Authorization was not completed. Return to pro-crud.")
				throw error
			}
		}
		throw PlanningCenterError.callbackTimeout
	}

	private func readable(_ descriptor: Int32, milliseconds: Int32) throws -> Bool {
		var item = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
		let result = poll(&item, 1, milliseconds)
		if result < 0 {
			if errno == EINTR {
				return false
			}
			throw POSIXError(.init(rawValue: errno) ?? .EIO)
		}
		return result > 0
	}

	private func reply(_ client: Int32, status: String, text: String) {
		let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(text.utf8.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n\(text)"
		response.withCString { pointer in
			_ = send(client, pointer, response.utf8.count, 0)
		}
	}
}
