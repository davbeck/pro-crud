import Foundation
import ProPresenterProto
import SwiftProtobuf

public enum ProPresenterTargetVersion: String, CaseIterable, Codable, Sendable {
	case v21 = "21"
	case v22 = "22"
}

public struct DocumentCompatibilityProfile: Codable, Equatable, Sendable {
	public var targetVersion: ProPresenterTargetVersion
	public var representation = "legacy-protobuf-interchange"

	public init(targetVersion: ProPresenterTargetVersion = .v22) {
		self.targetVersion = targetVersion
	}
}

public struct DocumentCompatibilityIssue: Codable, Equatable, Sendable {
	public enum Severity: String, Codable, Sendable { case warning, error }
	public var feature: String
	public var componentPath: String
	public var sourceApplicationMajorVersion: UInt32?
	public var targetVersion: ProPresenterTargetVersion
	public var severity: Severity
	public var availableConversion: String
	public var message: String
}

public struct DocumentCompatibilityReport: Codable, Sendable {
	public var profile: DocumentCompatibilityProfile
	public var sourceApplicationMajorVersion: UInt32?
	public var issues: [DocumentCompatibilityIssue]
	public var canWrite: Bool

	init(profile: DocumentCompatibilityProfile, sourceApplicationMajorVersion: UInt32?, issues: [DocumentCompatibilityIssue]) {
		self.profile = profile
		self.sourceApplicationMajorVersion = sourceApplicationMajorVersion
		self.issues = issues
		canWrite = !issues.contains { $0.severity == .error }
	}

	public func requireSupported() throws {
		if !canWrite {
			throw DocumentCompatibilityError(report: self)
		}
	}
}

public struct DocumentCompatibilityError: Error, CustomStringConvertible, Sendable {
	public let report: DocumentCompatibilityReport
	public var description: String {
		(["Cannot write a ProPresenter \(report.profile.targetVersion.rawValue) target without unqualified conversion:"] +
			report.issues.filter { $0.severity == .error }.map { "[\($0.feature)] \($0.componentPath): \($0.message)" }).joined(separator: "\n")
	}
}

public enum DocumentCompatibility {
	/// Checks versioned wire semantics for configuration/runtime roots as well
	/// as document payloads. The input bytes are never decoded through a
	/// singular timeline type or rebuilt by the compatibility analyzer.
	public static func analyze(protobuf: Data, messageType: String, target: ProPresenterTargetVersion, sourceApplicationMajorVersion: UInt32? = nil) throws -> DocumentCompatibilityReport {
		var analyzer = try Analyzer(schema: .bundled(), target: target, source: sourceApplicationMajorVersion)
		try analyzer.inspect(protobuf, message: messageType, path: "")
		return .init(profile: .init(targetVersion: target), sourceApplicationMajorVersion: sourceApplicationMajorVersion, issues: analyzer.issues)
	}

	public static func analyzeExportContents(in directory: URL, target: ProPresenterTargetVersion) throws -> DocumentCompatibilityReport {
		var issues: [DocumentCompatibilityIssue] = []
		for file in try DocumentLoader.recursiveFiles(in: directory).sorted(by: { $0.path < $1.path })
			where file.pathExtension.lowercased() == "pro" || file.lastPathComponent == "Theme" || (file.lastPathComponent == "data" && file.deletingLastPathComponent() == directory)
		{
			let document = try DocumentLoader.load(from: file)
			let report = try analyze(document, target: target)
			let relative = try DocumentLoader.relativePath(of: file, in: directory)
			issues.append(contentsOf: report.issues.map { issue in
				var issue = issue
				issue.componentPath = "\(relative)\(issue.componentPath)"
				return issue
			})
		}
		return .init(profile: .init(targetVersion: target), sourceApplicationMajorVersion: nil, issues: issues)
	}

	public static func analyze(_ document: ProPresenterDocument, target: ProPresenterTargetVersion = .v22) throws -> DocumentCompatibilityReport {
		let source = sourceApplicationMajorVersion(document.payload)
		var analyzer = try Analyzer(schema: ProtobufSchema.bundled(), target: target, source: source)
		if document.kind == .theme, !document.themeEntries.isEmpty {
			for entry in document.themeEntries {
				try analyzer.inspect(entry.document.serializedData(), message: Rv_Data_Template.Document.protoMessageName, path: entry.relativePath)
			}
		} else {
			let message = switch document.payload {
			case .presentation: Rv_Data_Presentation.protoMessageName
			case .playlist: Rv_Data_PlaylistDocument.protoMessageName
			case .theme: Rv_Data_Template.Document.protoMessageName
			}
			try analyzer.inspect(document.payload.serializedData(), message: message, path: "")
		}
		return DocumentCompatibilityReport(profile: .init(targetVersion: target), sourceApplicationMajorVersion: source, issues: analyzer.issues)
	}

	public static func sourceApplicationMajorVersion(_ payload: DocumentPayload) -> UInt32? {
		switch payload {
		case let .presentation(value): value.hasApplicationInfo ? value.applicationInfo.applicationVersion.majorVersion : nil
		case let .theme(value): value.hasApplicationInfo ? value.applicationInfo.applicationVersion.majorVersion : nil
		case let .playlist(value): value.hasApplicationInfo ? value.applicationInfo.applicationVersion.majorVersion : nil
		}
	}

	private struct Analyzer {
		let schema: ProtobufSchema
		let target: ProPresenterTargetVersion
		let source: UInt32?
		let baseline21: ProtobufSchema
		let native22: ProtobufSchema
		var issues: [DocumentCompatibilityIssue] = []
		private var enumCache: [String: Set<Int32>] = [:]

		init(schema: ProtobufSchema, target: ProPresenterTargetVersion, source: UInt32?) throws {
			self.schema = schema
			self.target = target
			self.source = source
			baseline21 = try .baseline21()
			native22 = try .bundled(version: .v22)
		}

		mutating func inspect(_ data: Data, message: String, path: String, keyMapping: Bool = false, nativeHLS: Bool = false) throws {
			var nativeHLS = nativeHLS
			if message == "rv.data.Action.MediaType", target == .v22 {
				nativeHLS = try NativeHLSInterchange.qualifiesAction(data)
			} else if message == "rv.data.Media" {
				nativeHLS = try nativeHLS && NativeHLSInterchange.qualifiesMedia(data)
			}
			let selectedSchema: ProtobufSchema
			switch (nativeHLS, message) {
			case (true, _): selectedSchema = native22
			case (_, "rv.data.TimedPlayback.Sequence"), (_, "rv.data.TimedPlayback.Sequence.SequenceItem"): selectedSchema = native22
			case (_, "rv.data.CollectionElementType"): selectedSchema = baseline21
			default: selectedSchema = schema
			}
			let descriptor = try selectedSchema.message(named: message)
			let known = Dictionary(uniqueKeysWithValues: descriptor.fields.map { ($0.number, $0) })
			let fields = try ProtobufJSONPatcher.WireField.parse(data)
			if message == "rv.data.TimedPlayback.Sequence", target == .v21, fields.filter({ $0.number == 3 }).count > 1 {
				append("multi-presentation-timeline", path: "\(path)/presentations", unsupported: true, message: "ProPresenter 21.4 has one embedded timeline Presentation. Multiple 22 messages would merge and lose identity/ordering; no flattening conversion is qualified.")
			}
			var occurrences: [Int: Int] = [:]
			for wire in fields {
				let index = occurrences[wire.number, default: 0]
				occurrences[wire.number] = index + 1
				if message == "rv.data.TimedPlayback.Sequence.SequenceItem", wire.number == 8, target == .v21 {
					append("timeline-presentation-reference", path: "\(path)/presentation_uuid", unsupported: true, message: "ProPresenter 21.4 has no per-item Presentation UUID field; this cross-Presentation reference requires a qualified conversion.")
					continue
				}
				if keyMapping, message == "rv.data.CollectionElementType", wire.number == 3, target == .v22 {
					append("key-mapping-parent-scope", path: "\(path)/parent_collection", unsupported: true, message: "The 21.4 mapping's parent scope is absent from the 22 CollectionElementTypeKey layout. Preserving those bytes does not preserve lookup scope.")
					continue
				}
				if let feature = Self.nativeGraphs[message]?[wire.number], !(nativeHLS && message == "rv.data.Media" && [10, 11].contains(wire.number)) {
					append(feature, path: "\(path)/field[\(wire.number)]", unsupported: true,
					       message: "This active 22 representation requires a qualified adapter. Export its compatibility representation from ProPresenter before editing or packaging it.")
					continue
				}
				guard let field = known[wire.number] else {
					append("unknown-field", path: "\(path)/field[\(wire.number)][index=\(index)]", unsupported: target == .v21 || nativeHLS,
					       message: "Wire field \(wire.number) of \(message) is opaque. Its bytes can be preserved, but its behavior and dependencies are unqualified for the requested target.")
					continue
				}
				let fieldPath = "\(path)/\(field.protoName)" + (field.isRepeated ? "[index=\(index)]" : "")
				if field.isMessage, let nested = field.typeName, let payload = wire.payload {
					try inspect(payload, message: nested, path: fieldPath, keyMapping: keyMapping || (message == "rv.data.KeyMapping" && (101 ... 106).contains(wire.number)), nativeHLS: nativeHLS)
				} else if field.type == .enum, let type = field.typeName, let value = wire.varint,
				          let values = enumValues(type, nativeHLS: nativeHLS), !values.contains(Int32(truncatingIfNeeded: value))
				{
					append("unknown-enum-value", path: fieldPath, unsupported: target == .v21 || nativeHLS,
					       message: "Enum \(type) value \(value) has no qualified target behavior.")
				}
			}
		}

		private mutating func append(_ feature: String, path: String, unsupported: Bool, message: String) {
			issues.append(.init(feature: feature, componentPath: path, sourceApplicationMajorVersion: source,
			                    targetVersion: target, severity: unsupported ? .error : .warning,
			                    availableConversion: unsupported ? "unsupported" : "preserve-opaque-bytes", message: message))
		}

		private static let nativeGraphs: [String: [Int: String]] = [
			"rv.data.Presentation": [24: "cue-group-placement-tree"],
			"rv.data.Presentation.Arrangement": [4: "arrangement-v2-order"],
			"rv.data.Presentation.CueGroup": [3: "cue-group-v2-order"],
			"rv.data.Slide": [8: "slide-v2-build-order"],
			"rv.data.PlaylistDocument": [7: "playlist-v2-graph", 8: "live-video-v2-graph"],
			"rv.data.Media": [9: "media-container-identity", 10: "media-asset-identity", 11: "media-identity-schema", 12: "hls-source", 13: "media-provider"],
		]

		private mutating func enumValues(_ name: String, nativeHLS: Bool = false) -> Set<Int32>? {
			let cacheKey = "\(nativeHLS):\(name)"
			if let cached = enumCache[cacheKey] {
				return cached
			}
			func find(_ enums: [Google_Protobuf_EnumDescriptorProto], prefix: String) -> Set<Int32>? {
				enums.first { name == "\(prefix).\($0.name)" }.map { Set($0.value.map(\.number)) }
			}
			func nested(_ messages: [Google_Protobuf_DescriptorProto], prefix: String) -> Set<Int32>? {
				for message in messages {
					let child = "\(prefix).\(message.name)"
					if let values = find(message.enumType, prefix: child) ?? nested(message.nestedType, prefix: child) {
						return values
					}
				}
				return nil
			}
			for file in (nativeHLS ? native22 : schema).descriptorSet.file {
				if let values = find(file.enumType, prefix: file.package) ?? nested(file.messageType, prefix: file.package) {
					enumCache[cacheKey] = values
					return values
				}
			}
			return nil
		}
	}
}
