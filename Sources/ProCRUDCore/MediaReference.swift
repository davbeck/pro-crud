import Foundation
import ProPresenterProto
import SwiftProtobuf

/// A document occurrence and its asset association are separate in 22. This
/// view reads the pinned wire schema without replacing the original message.
public struct MediaReference: Codable, Sendable, Equatable {
	public enum DependencyKind: String, Codable, Sendable {
		case file, liveDevice = "live-device", remoteStream = "remote-stream", remoteResource = "remote-resource", webContent = "web-content", unknown
	}

	public struct Locator: Codable, Sendable, Equatable {
		public let field: String
		public let absolute: String?
		public let relative: String?
		public let localRoot: Int?
		public let localPath: String?
		public let remote: String?

		init(field: String, url: Rv_Data_URL) {
			self.field = field
			if case let .absoluteString(value)? = url.storage {
				absolute = value
			} else {
				absolute = nil
			}
			if case let .relativePath(value)? = url.storage {
				relative = value
			} else {
				relative = nil
			}
			if case let .local(value)? = url.relativeFilePath {
				localRoot = value.root.rawValue
				localPath = value.path
			} else {
				localRoot = nil
				localPath = nil
			}
			remote = nil
		}

		init(field: String, remote: String) {
			self.field = field
			self.remote = remote
			absolute = nil
			relative = nil
			localRoot = nil
			localPath = nil
		}
	}

	public let path: String
	public let referenceID: String
	public let assetID: String?
	public let containerID: String?
	public let identitySchemaVersion: String?
	public let kind: String?
	public let dependencyKind: DependencyKind
	public let locators: [Locator]
	public let hasProvider: Bool

	public init(media: Rv_Data_Media, path: String = "/") throws {
		self.path = path
		referenceID = media.uuid.string
		let root = try MediaWireMessage(media.serializedData())
		assetID = try root.message(10).map { try Rv_Data_UUID(serializedBytes: $0.data).string }
		containerID = try root.string(9)
		identitySchemaVersion = try root.string(11)
		hasProvider = root.fields.contains { $0.number == 13 }
		let schema = try ProtobufSchema.bundled(version: .v22)
		let descriptor = try schema.message(named: "rv.data.Media")
		let types = descriptor.fields.filter { $0.oneof != nil }
		let active = root.fields.last { wire in types.contains { $0.number == wire.number } }
		let type = active.flatMap { wire in types.first { $0.number == wire.number } }
		kind = type?.protoName
		var locators: [Locator] = []
		if media.hasURL {
			locators.append(.init(field: "url", url: media.url))
		}
		if let type, let name = type.typeName, let properties = try root.message(type.number, oneofFields: Set(types.map(\.number))) {
			let fields = try schema.message(named: name).fieldsByName
			if let field = fields["file"], let file = try properties.message(field.number), let url = try file.message(1) {
				try locators.append(.init(field: "\(type.protoName)/file/local_url", url: Rv_Data_URL(serializedBytes: url.data)))
			}
			if let field = fields["source"], let source = try properties.message(field.number) {
				// SourceType is a oneof: a later file/HLS field selects its type.
				switch source.fields.last(where: { $0.number == 1 || $0.number == 2 })?.number {
				case 1:
					if let file = try source.message(1, oneofFields: [1, 2]), let url = try file.message(1) {
						try locators.append(.init(field: "\(type.protoName)/source/file/url", url: Rv_Data_URL(serializedBytes: url.data)))
					}
				case 2:
					if let hls = try source.message(2, oneofFields: [1, 2]), let url = try hls.string(1) {
						locators.append(.init(field: "\(type.protoName)/source/hls/url", remote: url))
					}
				default: break
				}
			}
			if type.protoName == "hls_stream", let url = try properties.string(5) {
				locators.append(.init(field: "hls_stream/url", remote: url))
			}
			if type.protoName == "web_content", let url = try properties.message(2) {
				try locators.append(.init(field: "web_content/url", url: Rv_Data_URL(serializedBytes: url.data)))
			}
		}
		self.locators = locators
		if kind == "live_video" {
			dependencyKind = .liveDevice
		} else if kind == "hls_stream" || locators.contains(where: { $0.remote != nil }) {
			dependencyKind = .remoteStream
		} else if kind == "web_content" {
			dependencyKind = .webContent
		} else if locators.contains(where: { locator in
			guard locator.localPath == nil, locator.relative == nil,
			      let string = locator.absolute, let url = URL(string: string), url.scheme != nil
			else { return false }
			return !url.isFileURL
		}) {
			dependencyKind = .remoteResource
		} else if kind == "image" || kind == "audio" || kind == "video" {
			dependencyKind = .file
		} else {
			dependencyKind = .unknown
		}
	}

	/// Visits the actual document bytes, including media in nested actions and
	/// fills. The descriptor traversal does not consult projection caches.
	public static func collect(protobuf: Data, messageType: String, rootPath: String = "") throws -> [Self] {
		let schema = try ProtobufSchema.bundled(version: .v22)
		func visit(_ data: Data, message: String, path: String) throws -> [Self] {
			if message == Rv_Data_Media.protoMessageName {
				let reference = try Self(media: Rv_Data_Media(serializedBytes: data), path: path)
				guard reference.kind != nil || !reference.referenceID.isEmpty || reference.assetID != nil || reference.containerID != nil || reference.identitySchemaVersion != nil || !reference.locators.isEmpty || reference.hasProvider else { return [] }
				return [reference]
			}
			let descriptor = try schema.message(named: message)
			let wire = try MediaWireMessage(data)
			var result: [Self] = []
			for field in descriptor.fields where field.isMessage {
				guard let nested = field.typeName else { continue }
				let siblings = Set(descriptor.fields.filter { field.oneof != nil && $0.oneof == field.oneof }.map(\.number))
				if !siblings.isEmpty, wire.fields.last(where: { siblings.contains($0.number) })?.number != field.number {
					continue
				}
				let payloads = wire.payloads(field.number, oneofFields: siblings)
				if field.isRepeated {
					for (index, payload) in payloads.enumerated() {
						try result.append(contentsOf: visit(payload, message: nested, path: "\(path)/\(field.protoName)[index=\(index)]"))
					}
				} else if !payloads.isEmpty {
					// Singular message occurrences merge in protobuf; inspecting only
					// the final occurrence loses fields from earlier wire records.
					try result.append(contentsOf: visit(payloads.reduce(into: Data()) { $0.append($1) }, message: nested, path: "\(path)/\(field.protoName)"))
				}
			}
			return result
		}
		return try visit(protobuf, message: messageType, path: rootPath)
	}
}

struct MediaWireMessage {
	let data: Data
	let fields: [ProtobufJSONPatcher.WireField]

	init(_ data: Data) throws {
		self.data = data
		fields = try ProtobufJSONPatcher.WireField.parse(data)
	}

	func payloads(_ number: Int, oneofFields: Set<Int> = []) -> [Data] {
		let reset = fields.lastIndex { $0.number != number && oneofFields.contains($0.number) }
		return fields.enumerated().filter { $0.element.number == number && $0.offset > (reset ?? -1) }.compactMap(\.element.payload)
	}

	func message(_ number: Int, oneofFields: Set<Int> = []) throws -> Self? {
		let payloads = payloads(number, oneofFields: oneofFields)
		return try payloads.isEmpty ? nil : Self(payloads.reduce(into: Data()) { $0.append($1) })
	}

	func string(_ number: Int) throws -> String? {
		guard let payload = fields.last(where: { $0.number == number })?.payload else { return nil }
		guard let string = String(data: payload, encoding: .utf8) else { throw NativeSemanticError.invalidValue(path: "field[\(number)]", expected: "UTF-8 string") }
		return string
	}
}
