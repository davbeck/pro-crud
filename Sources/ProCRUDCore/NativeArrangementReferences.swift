import Foundation
import ProPresenterProto

/// Explicit arrangement links in playlist items and document-trigger actions.
/// Local Presentation selection belongs to its own definition and is handled
/// by the edit itself. This inventory does not infer links from arbitrary text.
public struct NativeArrangementReferenceInventory: Encodable, Sendable {
	public struct Reference: Codable, Sendable, Equatable {
		public enum Role: String, Codable, Sendable { case playlist, documentAction = "document-action" }
		public let documentID: UUID
		public let scope: NativeWorkspaceStream.Scope
		public let componentPath: String
		public let role: Role
		public let targetDocumentID: UUID?
		public let arrangementID: UUID?
		public let arrangementName: String?
	}

	public struct Uninspected: Encodable, Sendable {
		public let identity: NativeWorkspaceStream.Identity
		public let reason: String
	}

	public let workspaceID: UUID
	public let references: [Reference]
	public let uninspected: [Uninspected]

	public init(snapshot: NativeWorkspaceSnapshot) throws {
		workspaceID = snapshot.workspaceID
		let resolver = try NativeWorkspaceReferenceResolver(streams: snapshot.streams)
		var references: [Reference] = [], uninspected: [Uninspected] = []
		for stream in snapshot.streams {
			guard stream.supportsProtobufProjection, stream.identity.availability == .available else {
				uninspected.append(.init(identity: stream.identity, reason: "Document kind/scope is unmapped or content is unavailable locally."))
				continue
			}
			do {
				let projection = try stream.protobufProjection()
				try projection.requireComplete()
				try references.append(contentsOf: Self.collect(projection.protobuf, messageType: projection.messageType, identity: stream.identity, resolver: resolver))
			} catch {
				uninspected.append(.init(identity: stream.identity, reason: String(describing: error)))
			}
		}
		self.references = references
		self.uninspected = uninspected
	}

	private static func collect(_ data: Data, messageType: String, identity: NativeWorkspaceStream.Identity, resolver: NativeWorkspaceReferenceResolver) throws -> [Reference] {
		let schema = try ProtobufSchema.bundled(version: .v22)
		func uuid(_ wire: MediaWireMessage?, field: Int) throws -> UUID? {
			guard let message = try wire?.message(field), let string = try message.string(1), !string.isEmpty else { return nil }
			guard let id = UUID(uuidString: string) else { throw NativeSemanticError.invalidValue(path: "field[\(field)]", expected: "arrangement/reference UUID") }
			return id
		}
		func visit(_ data: Data, message: String, path: String) throws -> [Reference] {
			let wire = try MediaWireMessage(data)
			if message == "rv.data.Action.DocumentType" {
				guard let arrangement = try uuid(wire, field: 2) else { return [] }
				// identification is marked obsolete in the native descriptor and is
				// omitted by native import. It cannot establish the current target.
				let target: UUID? = nil
				return [.init(documentID: identity.documentID, scope: identity.scope, componentPath: path + "/selected_arrangement", role: .documentAction, targetDocumentID: target, arrangementID: arrangement, arrangementName: nil)]
			}
			if message == "rv.data.PlaylistItem.Presentation" {
				let arrangement = try uuid(wire, field: 2)
				let name = try wire.string(5).flatMap { $0.isEmpty ? nil : $0 }
				guard arrangement != nil || name != nil else { return [] }
				let url = try wire.message(1).map { try Rv_Data_URL(serializedBytes: $0.data) }
				let target: UUID?
				if case let .local(local)? = url?.relativeFilePath {
					let native: NativeWorkspaceValue = .map(["RelativeFilePath": .map(["__tag": .string("local"), "local": .map(["root": .integer(Int64(local.root.rawValue)), "path": .string(local.path)])])])
					target = try resolver.presentation(native).documentID
				} else {
					target = nil
				}
				return [.init(documentID: identity.documentID, scope: identity.scope, componentPath: path + "/arrangement", role: .playlist, targetDocumentID: target, arrangementID: arrangement, arrangementName: name)]
			}
			let descriptor = try schema.message(named: message)
			var result: [Reference] = []
			for field in descriptor.fields where field.isMessage {
				guard let nested = field.typeName else { continue }
				let siblings = Set(descriptor.fields.filter { field.oneof != nil && $0.oneof == field.oneof }.map(\.number))
				let payloads = wire.payloads(field.number, oneofFields: siblings)
				if field.isRepeated {
					for (index, payload) in payloads.enumerated() {
						try result.append(contentsOf: visit(payload, message: nested, path: "\(path)/\(field.protoName)[index=\(index)]"))
					}
				} else if !payloads.isEmpty {
					try result.append(contentsOf: visit(payloads.reduce(into: Data()) { $0.append($1) }, message: nested, path: "\(path)/\(field.protoName)"))
				}
			}
			return result
		}
		return try visit(data, message: messageType, path: "")
	}
}

enum NativeArrangementDeletion {
	static func validate(_ patches: [NativeLocalPatch], in snapshot: NativeWorkspaceSnapshot) throws -> [NativeWorkspaceStream]? {
		guard Set(patches.map(\.identity.documentID)).count == patches.count else { throw NativeWriteError.invalidBatch }
		var removed: [(documentID: UUID, arrangement: NativePresentationLayout.Arrangement)] = []
		let replacements = try Dictionary(uniqueKeysWithValues: patches.map { patch in
			let before = NativeWorkspaceStream(identity: patch.identity, snapshot: patch.originalSnapshot, versionVector: patch.originalVersionVector, lastSharedVersionVector: nil)
			let after = NativeWorkspaceStream(identity: patch.identity, snapshot: patch.snapshot, versionVector: patch.versionVector, lastSharedVersionVector: nil)
			let retained = try Set(after.presentationLayout().arrangements.map(\.id))
			for arrangement in try before.presentationLayout().arrangements where !retained.contains(arrangement.id) {
				removed.append((patch.identity.documentID, arrangement))
			}
			return (patch.identity.documentID, after)
		})
		guard !removed.isEmpty else { return nil }
		let effective = NativeWorkspaceSnapshot(root: snapshot.root, workspaceID: snapshot.workspaceID, metadata: snapshot.metadata, streams: snapshot.streams.map { stream in
			stream.identity.scope == .shared ? replacements[stream.identity.documentID] ?? stream : stream
		})
		let inventory = try NativeArrangementReferenceInventory(snapshot: effective)
		if let unknown = inventory.uninspected.first {
			throw NativeSemanticError.unsupportedNode(path: "/streams/\(unknown.identity.documentID)/\(unknown.identity.scope)", kind: "arrangement-reference inspection: \(unknown.reason)")
		}
		for removal in removed {
			for reference in inventory.references where reference.targetDocumentID == nil || reference.targetDocumentID == removal.documentID {
				guard reference.arrangementID == removal.arrangement.id || (reference.arrangementID == nil && reference.arrangementName == removal.arrangement.name) else { continue }
				throw NativeSemanticError.unsupportedNode(path: "/streams/\(reference.documentID)/\(reference.scope)\(reference.componentPath)", kind: "arrangement \(removal.arrangement.id) is still referenced; remove the link before deleting its definition")
			}
		}
		return snapshot.streams
	}
}
