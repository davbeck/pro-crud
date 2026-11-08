import Foundation
import ProPresenterProto

/// Walks every active message, including header/cue/template actions and
/// nested connected links. Singular protobuf messages merge before traversal;
/// repeated messages keep their separate identities and order.
enum NativeDependencyWire {
	static func rewrite(_ data: Data, message: String, path: String, visit: (Data, String, String) throws -> Data?) throws -> Data {
		if let replacement = try visit(data, message, path) {
			return replacement
		}
		let descriptor = try ProtobufSchema.bundled(version: .v22).message(named: message)
		let wire = try MediaWireMessage(data)
		var replacements: [Int: Data] = [:]
		for field in descriptor.fields where field.isMessage && !field.isRepeated {
			guard let nested = field.typeName else { continue }
			let siblings = Set(descriptor.fields.filter { field.oneof != nil && $0.oneof == field.oneof }.map(\.number))
			if !siblings.isEmpty, wire.fields.last(where: { siblings.contains($0.number) })?.number != field.number {
				continue
			}
			let payloads = wire.payloads(field.number, oneofFields: siblings)
			guard !payloads.isEmpty else { continue }
			let merged = payloads.reduce(into: Data()) { $0.append($1) }
			let result = try rewrite(merged, message: nested, path: "\(path)/\(field.protoName)", visit: visit)
			if result != merged {
				replacements[field.number] = result
			}
		}
		var result = Data(), indices: [Int: Int] = [:]
		for field in wire.fields {
			let index = indices[field.number, default: 0]; indices[field.number] = index + 1
			if let replacement = replacements[field.number] {
				if index == wire.fields.count(where: { $0.number == field.number }) - 1 {
					result.append(ProtobufJSONPatcher.WireField.lengthDelimited(number: field.number, payload: replacement).raw)
				}
			} else if let descriptor = descriptor.fields.first(where: { $0.number == field.number }), descriptor.isRepeated, descriptor.isMessage, let nested = descriptor.typeName, let payload = field.payload {
				let replacement = try rewrite(payload, message: nested, path: "\(path)/\(descriptor.protoName)[index=\(index)]", visit: visit)
				result.append(replacement == payload ? field.raw : ProtobufJSONPatcher.WireField.lengthDelimited(number: field.number, payload: replacement).raw)
			} else {
				result.append(field.raw)
			}
		}
		return result
	}
}

/// Prepares a complete portable dependency closure before archive publication.
/// Runtime/configuration references that cannot be represented in a playlist
/// archive remain explicit errors, collected alongside missing files/links.
final class NativeDependencyExport {
	let snapshot: NativeWorkspaceSnapshot
	let target: ProPresenterTargetVersion
	let directory: URL
	weak var workspace: NativeWorkspaceDependencyClosure?
	let workspaceLayout: Bool
	private(set) var dependencies: [NativePlaylistExportResult.Dependency] = []
	private(set) var issues: [DocumentCompatibilityIssue] = []
	private var presentations: [UUID: Rv_Data_Presentation] = [:]
	private var assets: [String: (source: URL, path: String)] = [:]
	private var assetStore: Result<NativeMediaStoreSnapshot, any Error>?
	private let budget = ArchiveCopyBudget(limits: .default, deadline: .init(timeout: .seconds(30)))

	init(snapshot: NativeWorkspaceSnapshot, target: ProPresenterTargetVersion, directory: URL, workspaceLayout: Bool = false) {
		self.snapshot = snapshot; self.target = target; self.directory = directory
		self.workspaceLayout = workspaceLayout
	}

	func rewrite(_ data: Data, message: String, path: String) throws -> Data {
		try NativeDependencyWire.rewrite(data, message: message, path: path) { data, message, path in
			if let workspace = self.workspace {
				do {
					if let replacement = try workspace.intercept(data, message: message, path: path) {
						return replacement
					}
				} catch { self.issue("native-workspace-dependency", path: path, message: String(describing: error)); return data }
			}
			switch message {
			case "rv.data.Media":
				do { return try self.media(data, path: path) }
				catch { self.issue("native-media-dependency", path: path, message: String(describing: error)); return data }
			case "rv.data.PlaylistItem.Presentation":
				do { return try self.presentation(data, path: path) }
				catch { self.issue("native-presentation-dependency", path: path, message: String(describing: error)); return data }
			case "rv.data.Action":
				let action = try Rv_Data_Action(serializedBytes: data)
				switch action.type {
				case .presentationSlide, .media, .foregroundMedia, .backgroundMedia, .externalPresentation, .clear, .slideDestination, .propSlide: break
				case .macro, .timer, .audienceLook, .prop, .message, .clearGroup, .stageLayout, .audioBinPlaylist, .mediaBinPlaylist:
					if self.workspace == nil {
						self.issue("native-action-dependency", path: path, message: "Action type \(action.type) requires a separate workspace dependency export.")
					}
				default: self.issue("native-action-dependency", path: path, message: "Action type \(action.type) requires receiving-workspace configuration or a qualified archive adapter.")
				}
				return nil
			case "rv.data.ProviderInfo":
				self.issue("provider-linked-content", path: path, message: "Provider refresh ownership requires native export/import.")
				return data
			case "rv.data.Action.MediaType":
				let media = try Rv_Data_Action.MediaType(serializedBytes: data)
				if !media.selectedEffectPresetUuid.string.isEmpty {
					self.issue("native-effect-preset-dependency", path: path + "/selected_effect_preset_uuid", message: "Selected effect preset requires its receiving-workspace definition.")
				}
				return nil
			case "rv.data.Action.LayerIdentification":
				let layer = try Rv_Data_Action.LayerIdentification(serializedBytes: data)
				if !layer.uuid.string.isEmpty || !layer.name.isEmpty {
					self.issue("native-layer-dependency", path: path, message: "This layer selector has no qualified standalone playlist adapter; use native workspace export.")
				}
				return data
			case "rv.data.Transition":
				let transition = try Rv_Data_Transition(serializedBytes: data)
				if !transition.favoriteUuid.string.isEmpty {
					self.issue("native-transition-preset-dependency", path: path, message: "Transition favorite association requires its receiving-workspace definition.")
				}
				return nil
			case "rv.data.CollectionElementType":
				let value = try Rv_Data_CollectionElementType(serializedBytes: data)
				if !value.parameterUuid.string.isEmpty || !value.parameterName.isEmpty {
					self.issue("native-configuration-dependency", path: path, message: "The referenced configuration object \(value.parameterUuid.string) \(value.parameterName) requires a workspace export; a playlist archive cannot install its definition.")
				}
				return data
			case "rv.data.Action.PlaylistItemType":
				self.issue("native-playlist-action-dependency", path: path, message: "Playlist-trigger actions require the referenced playlist and item in the receiving workspace.")
				return data
			case "rv.data.URL":
				let url = try Rv_Data_URL(serializedBytes: data)
				if url.renderPath.isEmpty {
					return data
				}
				// Remote Planning Center attachment/service URLs stay remote.
				if case let .absoluteString(string)? = url.storage, let remote = URL(string: string), ["https", "http"].contains(remote.scheme?.lowercased()) {
					return data
				}
				do {
					let source = try NativeMediaInventory.resolve(.init(field: path, url: url), workspaceRoot: self.snapshot.root)
					let copied = try self.file(source, asset: nil)
					return try self.portable(copied.relativePath, original: url).serializedData()
				} catch { self.issue("native-file-dependency", path: path, message: String(describing: error)); return data }
			default: return nil
			}
		}
	}

	func publishDocuments() throws {
		guard issues.isEmpty else { throw DocumentCompatibilityError(report: .init(profile: .init(targetVersion: target), sourceApplicationMajorVersion: nil, issues: issues)) }
		if case let .success(captured)? = assetStore {
			let current = try NativeMediaStoreSnapshot.read(at: snapshot.root.appendingPathComponent("MediaStore"))
			guard current.fingerprint == captured.fingerprint else { throw NativeMediaStoreError.changedDuringRead }
		}
		for dependency in dependencies {
			guard let presentation = presentations[dependency.documentID] else { preconditionFailure("Missing prepared dependency") }
			let destination = directory.appendingPathComponent(dependency.archivePath)
			try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
			if workspaceLayout {
				try DocumentCompatibility.analyzeNativeDependencies(presentation.serializedData(), message: Rv_Data_Presentation.protoMessageName).requireSupported()
				try presentation.serializedData().write(to: destination)
			} else {
				try DocumentWriter.writeRaw(.init(payload: .presentation(presentation), origin: .raw(destination)), to: destination, targetVersion: target)
			}
		}
	}

	private func presentation(_ data: Data, path: String) throws -> Data {
		var link = try Rv_Data_PlaylistItem.Presentation(serializedBytes: data)
		let local = link.documentPath.local
		let url: NativeWorkspaceValue = .map(["RelativeFilePath": .map(["__tag": .string("local"), "local": .map(["root": .integer(Int64(local.root.rawValue)), "path": .string(local.path)])])])
		let reference = try NativeWorkspaceReferenceResolver(streams: snapshot.streams).presentation(url)
		guard let id = reference.documentID, let source = snapshot.streams.first(where: { $0.identity.documentID == id && $0.identity.scope == .shared && $0.identity.kind == "Presentation" }) else { throw NativeSemanticError.missingReference(path: path, identity: reference.logicalPath ?? link.documentPath.renderPath) }
		if presentations[id] == nil {
			let presentation = try source.protobufProjection().presentation()
			// Register before traversing so repeated and cyclic references terminate.
			presentations[id] = presentation
			let name = URL(fileURLWithPath: source.identity.corePath ?? presentation.name).lastPathComponent
			let archivePath = workspaceLayout ? "Libraries/\(source.identity.corePath ?? name).pro" : "Presentations/\(id.uuidString.lowercased())/\(name).pro"
			try DocumentArchive.validateWorkspacePath(archivePath, limits: .default)
			dependencies.append(.init(documentID: id, archivePath: archivePath))
			presentations[id] = try Rv_Data_Presentation(serializedBytes: rewrite(presentation.serializedData(), message: Rv_Data_Presentation.protoMessageName, path: "/dependencies/\(id)"))
		}
		if !link.arrangement.string.isEmpty {
			guard let arrangement = UUID(uuidString: link.arrangement.string), presentations[id]?.arrangements.contains(where: { UUID(uuidString: $0.uuid.string) == arrangement }) == true else { throw NativeSemanticError.missingReference(path: path + "/arrangement", identity: link.arrangement.string) }
		}
		guard let archivePath = dependencies.first(where: { $0.documentID == id })?.archivePath else { preconditionFailure("Missing dependency path") }
		link.documentPath = portable(archivePath, original: link.documentPath)
		return try link.serializedData()
	}

	private func media(_ data: Data, path: String) throws -> Data {
		let media = try Rv_Data_Media(serializedBytes: data), reference = try MediaReference(media: media, path: path)
		if reference.dependencyKind == .remoteStream, target == .v22, try NativeHLSInterchange.qualifiesMedia(data) {
			return data
		}
		guard target == .v22, reference.dependencyKind == .file, reference.identitySchemaVersion == "1", UUID(uuidString: reference.referenceID) != nil,
		      let asset = reference.assetID, UUID(uuidString: asset) != nil, !reference.hasProvider, reference.containerID == nil,
		      reference.activeLocators.count == 1, let locator = reference.activeLocators.first
		else { throw NativeSemanticError.unsupportedNode(path: path, kind: "portable schema-1 file media or qualified HLS; provider/live/unknown identities require native export") }
		let source = try NativeMediaInventory.resolve(locator, workspaceRoot: snapshot.root)
		if FileManager.default.fileExists(atPath: snapshot.root.appendingPathComponent("DocumentStore/workspace-storage-v1").path) {
			if assetStore == nil {
				assetStore = Result { try NativeMediaStoreSnapshot.read(at: snapshot.root.appendingPathComponent("MediaStore")) }
			}
			if let store = try assetStore?.get(), let occurrenceID = UUID(uuidString: reference.referenceID), let assetID = UUID(uuidString: asset) {
				try Self.requireAssociation(occurrence: occurrenceID, asset: assetID, in: store)
			}
		}
		// A selected effect preset is another workspace definition, even when
		// its drawing graph also contains an inline copy of the current effects.
		_ = try NativeDependencyWire.rewrite(data, message: "rv.data.Media", path: path) { bytes, message, path in
			guard message == "rv.data.Media.DrawingProperties" else { return nil }
			let drawing = try MediaWireMessage(bytes)
			let schema = try ProtobufSchema.bundled(version: .v22).message(named: message)
			if let field = schema.fieldsByName["selected_effect_preset_uuid"], let preset = try drawing.message(field.number), try !Rv_Data_UUID(serializedBytes: preset.data).string.isEmpty {
				self.issue("native-effect-preset-dependency", path: path, message: "Selected effect preset requires its receiving-workspace definition.")
			}
			return nil
		}
		let url = try file(source, asset: asset)
		let sourceFields = Set(reference.locators.filter { $0.remote == nil }.map(\.field))
		return try NativeDependencyWire.rewrite(data, message: "rv.data.Media", path: path) { data, message, nestedPath in
			guard message == "rv.data.URL" else { return nil }
			let stored = try Rv_Data_URL(serializedBytes: data)
			if sourceFields.contains(String(nestedPath.dropFirst(path.count + 1))) {
				return try self.portable(url.relativePath, original: stored).serializedData()
			}
			if case let .absoluteString(string)? = stored.storage, let remote = URL(string: string), ["http", "https"].contains(remote.scheme?.lowercased()) {
				return data
			}
			return try self.rewrite(data, message: message, path: nestedPath)
		}
	}

	private func file(_ source: URL, asset: String?) throws -> Rv_Data_URL {
		let key = asset?.lowercased() ?? source.path
		if let existing = assets[key] {
			if existing.source != source {
				guard try ArchiveFileIO.sha256(of: source, deadline: budget.deadline) == ArchiveFileIO.sha256(of: existing.source, deadline: budget.deadline) else { throw DocumentArchiveError.assetCollision(existing.path) }
			}
			return portable(existing.path)
		}
		let relative = "Media/\(asset?.lowercased() ?? UUID().uuidString.lowercased())/\(source.lastPathComponent)"
		try DocumentArchive.validateWorkspacePath(relative, limits: .default)
		try budget.copy(from: source, to: directory.appendingPathComponent(relative), entry: relative)
		assets[key] = (source, relative)
		return portable(relative)
	}

	private func portable(_ path: String, original: Rv_Data_URL = .init()) -> Rv_Data_URL {
		var result = original
		result.relativePath = path; result.local.root = workspaceLayout ? .show : .currentResource; result.local.path = path
		return result
	}

	static func requireAssociation(occurrence: UUID, asset: UUID, in store: NativeMediaStoreSnapshot) throws {
		guard let reference = store.references.first(where: { $0.id == occurrence }), !reference.tombstoned, reference.assetID == asset,
		      let model = store.assets.first(where: { $0.id == asset }), !model.purged
		else { throw NativeSemanticError.unsupportedNode(path: "/MediaStore/references/\(occurrence)", kind: "missing, tombstoned, purged or different materialized asset association; native export is required") }
	}

	func issue(_ feature: String, path: String, message: String) {
		issues.append(.init(feature: feature, componentPath: path, sourceApplicationMajorVersion: nil, targetVersion: target, severity: .error, availableConversion: "unsupported", message: message))
	}
}
