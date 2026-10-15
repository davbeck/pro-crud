import Foundation
import ProPresenterProto

/// A rendering-only adapter. Its compatibility view is never written or used
/// for export: native occurrence/asset identities remain in the source graph.
enum NativeMediaRendering {
	static func requiresAdapter(_ media: Rv_Data_Media) throws -> Bool {
		// FileProperties and SourceInfo predate 22 and occur in the retained 21
		// fixtures. Only explicit native identity/provider/HLS fields select this
		// adapter; older interchange keeps its established resolution behavior.
		try MediaWireMessage(media.serializedData()).fields.contains { (9 ... 13).contains($0.number) }
	}

	static func resolvedFile(_ media: Rv_Data_Media, contextRoot: URL?, path: String = "/media") throws -> URL {
		let reference = try MediaReference(media: media, path: path)
		guard reference.dependencyKind == .file, ["image", "video"].contains(reference.kind) else {
			throw NativeSemanticError.unsupportedNode(path: path, kind: "static preview of \(reference.kind ?? "unknown") / \(reference.dependencyKind.rawValue)")
		}
		guard reference.identitySchemaVersion == "1", UUID(uuidString: reference.referenceID) != nil, reference.assetID.flatMap(UUID.init(uuidString:)) != nil else {
			throw NativeSemanticError.invalidValue(path: path, expected: "media identity schema 1 with occurrence and asset UUIDs")
		}
		guard !reference.hasProvider else { throw NativeSemanticError.unsupportedNode(path: path, kind: "media provider association") }
		guard let locator = reference.activeLocators.first else { throw NativeSemanticError.invalidValue(path: path, expected: "selected file locator") }
		if contextRoot == nil, locator.relative != nil || locator.localPath != nil {
			throw NativeSemanticError.invalidValue(path: path, expected: "explicit resource/workspace root for a relative file source")
		}
		do {
			return try NativeMediaInventory.resolve(locator, workspaceRoot: contextRoot ?? URL(fileURLWithPath: "/"))
		} catch {
			throw RenderError.nativeMediaFile(path: "\(path)/\(locator.field)", source: locator.localPath ?? locator.relative ?? locator.absolute ?? "", underlyingError: error)
		}
	}

	static func compatibilityView(_ presentation: Rv_Data_Presentation, contextRoot: URL?) throws -> Rv_Data_Presentation {
		let schema = try ProtobufSchema.bundled()
		func visit(_ data: Data, message: String, path: String) throws -> Data {
			if message == Rv_Data_Media.protoMessageName {
				let media = try Rv_Data_Media(serializedBytes: data)
				guard try requiresAdapter(media) else { return data }
				return try compatibilityMedia(media, contextRoot: contextRoot, path: path).serializedData()
			}
			let descriptor = try schema.message(named: message)
			let wire = try MediaWireMessage(data)
			var replaced: [Int: Data] = [:]
			for field in descriptor.fields where field.isMessage && !field.isRepeated {
				guard let nested = field.typeName else { continue }
				let siblings = Set(descriptor.fields.filter { field.oneof != nil && $0.oneof == field.oneof }.map(\.number))
				let payloads = wire.payloads(field.number, oneofFields: siblings)
				guard !payloads.isEmpty else { continue }
				let merged = payloads.reduce(into: Data()) { $0.append($1) }
				let result = try visit(merged, message: nested, path: "\(path)/\(field.protoName)")
				if result != merged {
					replaced[field.number] = result
				}
			}
			var output = Data()
			var occurrences: [Int: Int] = [:]
			for field in wire.fields {
				let index = occurrences[field.number, default: 0]
				occurrences[field.number] = index + 1
				if let replacement = replaced[field.number] {
					if index == wire.fields.filter({ $0.number == field.number }).count - 1 {
						output.append(ProtobufJSONPatcher.WireField.lengthDelimited(number: field.number, payload: replacement).raw)
					}
				} else if let descriptor = descriptor.fields.first(where: { $0.number == field.number }), descriptor.isRepeated, descriptor.isMessage, let nested = descriptor.typeName, let payload = field.payload {
					let result = try visit(payload, message: nested, path: "\(path)/\(descriptor.protoName)[index=\(index)]")
					output.append(result == payload ? field.raw : ProtobufJSONPatcher.WireField.lengthDelimited(number: field.number, payload: result).raw)
				} else {
					output.append(field.raw)
				}
			}
			return output
		}
		return try Rv_Data_Presentation(serializedBytes: visit(presentation.serializedData(), message: Rv_Data_Presentation.protoMessageName, path: ""))
	}

	static func compatibilityMedia(_ media: Rv_Data_Media, contextRoot: URL?, path: String) throws -> Rv_Data_Media {
		let file = try resolvedFile(media, contextRoot: contextRoot, path: path)
		let cleaned = try stripMediaFields(media.serializedData(), message: Rv_Data_Media.protoMessageName, path: path)
		let report = try DocumentCompatibility.analyze(protobuf: cleaned, messageType: Rv_Data_Media.protoMessageName, target: .v21)
		if let issue = report.issues.first(where: { $0.severity == .error }) {
			throw NativeSemanticError.unsupportedNode(path: path + issue.componentPath, kind: issue.feature)
		}
		var view = try Rv_Data_Media(serializedBytes: cleaned)
		view.url = .with { $0.absoluteString = file.absoluteString }
		return view
	}

	private static func stripMediaFields(_ data: Data, message: String, path: String) throws -> Data {
		let descriptor = try ProtobufSchema.bundled(version: .v22).message(named: message)
		var output = Data()
		for wire in try MediaWireMessage(data).fields {
			guard let field = descriptor.fields.first(where: { $0.number == wire.number }) else {
				throw NativeSemanticError.unsupportedNode(path: "\(path)/field[\(wire.number)]", kind: "unknown media rendering field")
			}
			let fieldPath = "\(path)/\(field.protoName)"
			let omit: Bool
			switch (message, field.protoName) {
			case ("rv.data.Media", "container_id"), ("rv.data.Media", "asset_id"), ("rv.data.Media", "identity_schema_version"): omit = true
			case ("rv.data.Media.Metadata", "color_format"):
				try require(wire, values: [0, 1], path: fieldPath); omit = true
			case ("rv.data.Media.DrawingProperties", "alpha_type"):
				try require(wire, values: [0, 1], path: fieldPath); omit = true
			case ("rv.data.Media.DrawingProperties", "is_blurred"):
				try require(wire, values: [0], path: fieldPath); omit = true
			case ("rv.data.Media.TransportProperties", "retrigger"):
				try require(wire, values: [0, 1, 2, 3], path: fieldPath); omit = true
			case ("rv.data.Media.VideoProperties", "hardware_decoding"):
				try require(wire, values: [0, 2], path: fieldPath); omit = true
			case ("rv.data.FileProperties.RemoteProperties.ProContent", "download_identifier"):
				guard wire.payload?.isEmpty == true else { throw NativeSemanticError.unsupportedNode(path: fieldPath, kind: "ProContent provider association") }
				omit = false
			default: omit = ["rv.data.Media.ImageTypeProperties", "rv.data.Media.VideoTypeProperties"].contains(message) && ["file", "source"].contains(field.protoName)
			}
			if field.isMessage, let nested = field.typeName, let payload = wire.payload {
				let result = try stripMediaFields(payload, message: nested, path: fieldPath)
				if !omit {
					output.append(ProtobufJSONPatcher.WireField.lengthDelimited(number: wire.number, payload: result).raw)
				}
			} else if !omit {
				output.append(wire.raw)
			}
		}
		return output
	}

	private static func require(_ field: ProtobufJSONPatcher.WireField, values: Set<UInt64>, path: String) throws {
		guard let value = field.varint, values.contains(value) else { throw NativeSemanticError.unsupportedNode(path: path, kind: "media rendering value \(field.varint.map(String.init) ?? "non-varint")") }
	}
}
