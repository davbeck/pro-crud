import ArgumentParser
import Foundation
import ProCRUDCore
import ProPresenterProto

/// Applies media replacements across several raw workspace documents as one
/// validated, rollback-capable transaction.
struct EditSetMediaBatch: ParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "set-media-batch",
		abstract: "Atomically replace media across raw presentation and Theme documents in a workspace.",
	)

	@Argument(help: "ProPresenter workspace containing every document and media source in the manifest.") var workspace: String
	@Option(help: "Path to a JSON array of media replacement operations.") var file: String

	func run() throws {
		let manifestURL = URL(fileURLWithPath: file)
		let entries = try JSONDecoder().decode(
			[SetMediaBatchEntry].self,
			from: Data(contentsOf: manifestURL),
		)
		guard !entries.isEmpty else {
			throw ValidationError("The set-media-batch manifest must contain at least one operation.")
		}
		let transaction = try SetMediaBatchTransaction(
			workspaceURL: URL(fileURLWithPath: workspace),
			entries: entries,
		)
		try transaction.commit()
		print("Applied \(entries.count) media replacements to \(transaction.documentCount) documents.")
	}
}

struct SetMediaBatchEntry: Decodable {
	let document: String
	let path: String
	let source: String?
	let fromPlaylist: String?
	let playlist: String?
	let item: String?
	let preserveUUID: Bool?
	let syncLabel: Bool?

	private enum CodingKeys: String, CodingKey, CaseIterable {
		case document, path, source, playlist, item
		case fromPlaylist = "from-playlist"
		case preserveUUID = "preserve-uuid"
		case syncLabel = "sync-label"
	}

	init(from decoder: any Decoder) throws {
		let unchecked = try decoder.container(keyedBy: SetMediaBatchCodingKey.self)
		let allowed = Set(CodingKeys.allCases.map(\.stringValue))
		if let unknown = unchecked.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
			throw DecodingError.dataCorruptedError(
				forKey: unknown,
				in: unchecked,
				debugDescription: "Unsupported set-media-batch option \(unknown.stringValue).",
			)
		}
		let values = try decoder.container(keyedBy: CodingKeys.self)
		document = try values.decode(String.self, forKey: .document)
		path = try values.decode(String.self, forKey: .path)
		source = try values.decodeIfPresent(String.self, forKey: .source)
		fromPlaylist = try values.decodeIfPresent(String.self, forKey: .fromPlaylist)
		playlist = try values.decodeIfPresent(String.self, forKey: .playlist)
		item = try values.decodeIfPresent(String.self, forKey: .item)
		preserveUUID = try values.decodeIfPresent(Bool.self, forKey: .preserveUUID)
		syncLabel = try values.decodeIfPresent(Bool.self, forKey: .syncLabel)
	}
}

private struct SetMediaBatchCodingKey: CodingKey {
	let stringValue: String
	let intValue: Int? = nil

	init?(stringValue: String) {
		self.stringValue = stringValue
	}

	init?(intValue: Int) {
		nil
	}
}

final class SetMediaBatchTransaction {
	typealias ReplaceDocument = (FileManager, URL, URL) throws -> Void
	private enum MediaReplacement {
		case source(URL, preserveUUID: Bool, syncLabel: Bool)
		case playlist(Rv_Data_Media, syncLabel: Bool)
	}

	private struct Operation {
		let documentURL: URL
		let componentPath: ComponentPath
		let replacement: MediaReplacement
	}

	private struct PreparedDocument {
		let destinationURL: URL
		let originalData: Data
		let updatedData: Data
	}

	private let workspaceURL: URL
	private let preparedDocuments: [PreparedDocument]

	var documentCount: Int {
		preparedDocuments.count
	}

	init(workspaceURL: URL, entries: [SetMediaBatchEntry]) throws {
		let fileManager = FileManager.default
		let workspaceURL = workspaceURL.standardizedFileURL
		try Self.requireNonSymlink(workspaceURL, description: "workspace")
		var isDirectory: ObjCBool = false
		guard fileManager.fileExists(atPath: workspaceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
			throw ValidationError("Workspace does not exist or is not a directory: \(workspaceURL.path)")
		}
		self.workspaceURL = workspaceURL

		let operations = try entries.enumerated().map { index, entry in
			do {
				return try Self.resolve(entry, in: workspaceURL)
			} catch {
				throw ValidationError("Media batch operation \(index + 1) failed validation: \(error)")
			}
		}

		var documentOrder: [URL] = []
		for operation in operations where !documentOrder.contains(operation.documentURL) {
			documentOrder.append(operation.documentURL)
		}
		var originals: [String: Data] = [:]
		var documents: [String: ProPresenterDocument] = [:]
		for documentURL in documentOrder {
			let data = try Data(contentsOf: documentURL)
			let document = try DocumentLoader.loadRaw(documentURL)
			guard document.kind == .presentation || document.kind == .theme else {
				throw ValidationError("set-media-batch supports only raw presentation and Theme documents: \(documentURL.path)")
			}
			originals[documentURL.path] = data
			documents[documentURL.path] = document
		}

		for (index, operation) in operations.enumerated() {
			do {
				guard var document = documents[operation.documentURL.path] else {
					preconditionFailure("Validated batch document was not loaded.")
				}
				switch operation.replacement {
				case let .source(sourceURL, preserveUUID, syncLabel):
					try DocumentEditor.setMedia(
						&document,
						at: operation.componentPath,
						sourceURL: sourceURL,
						preserveUUID: preserveUUID,
						syncLabel: syncLabel,
					)
				case let .playlist(media, syncLabel):
					try DocumentEditor.setMedia(&document, at: operation.componentPath, to: media, syncLabel: syncLabel)
				}
				documents[operation.documentURL.path] = document
			} catch {
				throw ValidationError("Media batch operation \(index + 1) could not be applied: \(error)")
			}
		}

		preparedDocuments = try documentOrder.map { documentURL in
			guard let document = documents[documentURL.path], let originalData = originals[documentURL.path] else {
				preconditionFailure("Validated batch document was not prepared.")
			}
			let updatedData = try document.payload.serializedData()
			_ = try DocumentLoader.decode(updatedData, as: document.kind, location: documentURL.path)
			return PreparedDocument(
				destinationURL: documentURL,
				originalData: originalData,
				updatedData: updatedData,
			)
		}
	}

	func commit(
		replacing replaceDocument: ReplaceDocument = { fileManager, destinationURL, updatedURL in
			_ = try fileManager.replaceItemAt(destinationURL, withItemAt: updatedURL)
		},
	) throws {
		let fileManager = FileManager.default
		let stagingURL = workspaceURL.appendingPathComponent(".pro-crud-media-batch-\(UUID().uuidString)", isDirectory: true)
		try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
		defer { try? fileManager.removeItem(at: stagingURL) }

		var staged: [(prepared: PreparedDocument, updated: URL, backup: URL)] = []
		for (index, prepared) in preparedDocuments.enumerated() {
			let updatedURL = stagingURL.appendingPathComponent("\(index).updated")
			let backupURL = stagingURL.appendingPathComponent("\(index).original")
			try prepared.updatedData.write(to: updatedURL, options: .atomic)
			try prepared.originalData.write(to: backupURL, options: .atomic)
			staged.append((prepared, updatedURL, backupURL))
		}

		var attempted: [(prepared: PreparedDocument, backup: URL)] = []
		do {
			for item in staged {
				try Self.requireNonSymlink(item.prepared.destinationURL, description: "destination")
				let currentData = try Data(contentsOf: item.prepared.destinationURL)
				guard currentData == item.prepared.originalData else {
					throw ValidationError("Document changed after validation: \(item.prepared.destinationURL.path)")
				}
				attempted.append((item.prepared, item.backup))
				try replaceDocument(fileManager, item.prepared.destinationURL, item.updated)
			}
		} catch {
			var rollbackFailures: [String] = []
			for item in attempted.reversed() {
				do {
					let rollbackURL = item.prepared.destinationURL.deletingLastPathComponent()
						.appendingPathComponent(".\(item.prepared.destinationURL.lastPathComponent).rollback-\(UUID().uuidString)")
					try Data(contentsOf: item.backup).write(to: rollbackURL, options: .atomic)
					if fileManager.fileExists(atPath: item.prepared.destinationURL.path) {
						_ = try fileManager.replaceItemAt(item.prepared.destinationURL, withItemAt: rollbackURL)
					} else {
						try fileManager.moveItem(at: rollbackURL, to: item.prepared.destinationURL)
					}
				} catch {
					rollbackFailures.append("\(item.prepared.destinationURL.path): \(error)")
				}
			}
			if rollbackFailures.isEmpty {
				throw ValidationError("Media batch commit failed; all attempted documents were restored: \(error)")
			}
			throw ValidationError(
				"Media batch commit failed and rollback was incomplete (\(rollbackFailures.joined(separator: "; "))): \(error)",
			)
		}
	}

	private static func resolve(_ entry: SetMediaBatchEntry, in workspaceURL: URL) throws -> Operation {
		let documentURL = try resolveWorkspacePath(
			entry.document,
			in: workspaceURL,
			requireRegularFile: true,
			description: "document",
		)
		let componentPath = try ComponentPath(entry.path)
		guard (entry.source == nil) != (entry.fromPlaylist == nil) else {
			throw ValidationError("Provide exactly one of source or from-playlist.")
		}

		let replacement: MediaReplacement
		if let source = entry.source {
			guard entry.playlist == nil, entry.item == nil else {
				throw ValidationError("playlist and item require from-playlist.")
			}
			let sourceURL = try resolveWorkspacePath(
				source,
				in: workspaceURL,
				requireRegularFile: true,
				description: "source",
			)
			replacement = .source(
				sourceURL,
				preserveUUID: entry.preserveUUID == true,
				syncLabel: entry.syncLabel == true,
			)
		} else {
			guard entry.preserveUUID != true else {
				throw ValidationError("preserve-uuid cannot be combined with from-playlist.")
			}
			guard let playlist = entry.playlist, let item = entry.item else {
				throw ValidationError("from-playlist requires playlist and item.")
			}
			let playlistURL = try resolvePlaylistSource(entry.fromPlaylist ?? "", in: workspaceURL)
			let selection = try PlaylistMediaSource.select(from: playlistURL, playlist: playlist, item: item)
			replacement = .playlist(selection.media, syncLabel: entry.syncLabel == true)
		}
		return Operation(documentURL: documentURL, componentPath: componentPath, replacement: replacement)
	}

	private static func resolveWorkspacePath(
		_ relativePath: String,
		in workspaceURL: URL,
		requireRegularFile: Bool,
		description: String,
	) throws -> URL {
		guard !relativePath.isEmpty, !NSString(string: relativePath).isAbsolutePath else {
			throw ValidationError("The \(description) path must be relative to the workspace: \(relativePath)")
		}
		let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
		guard !components.contains(".."), !components.contains("") else {
			throw ValidationError("The \(description) path contains an unsafe component: \(relativePath)")
		}
		let resolvedURL = workspaceURL.appendingPathComponent(relativePath).standardizedFileURL
		guard resolvedURL == workspaceURL || resolvedURL.path.hasPrefix(workspaceURL.path + "/") else {
			throw ValidationError("The \(description) path escapes the workspace: \(relativePath)")
		}

		var currentURL = workspaceURL
		for component in components where component != "." {
			currentURL.appendPathComponent(String(component))
			try requireNonSymlink(currentURL, description: description)
		}
		if requireRegularFile {
			let attributes = try FileManager.default.attributesOfItem(atPath: resolvedURL.path)
			guard attributes[.type] as? FileAttributeType == .typeRegular else {
				throw ValidationError("The \(description) is not a regular file: \(relativePath)")
			}
		}
		return resolvedURL
	}

	private static func resolvePlaylistSource(_ relativePath: String, in workspaceURL: URL) throws -> URL {
		let sourceURL = try resolveWorkspacePath(
			relativePath,
			in: workspaceURL,
			requireRegularFile: false,
			description: "playlist source",
		)
		let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
		if attributes[.type] as? FileAttributeType == .typeRegular {
			return sourceURL
		}
		guard attributes[.type] as? FileAttributeType == .typeDirectory else {
			throw ValidationError("The playlist source is not a regular file or directory: \(relativePath)")
		}
		for candidate in [
			sourceURL.appendingPathComponent("Playlists/Media"),
			sourceURL.appendingPathComponent("Media"),
		] where FileManager.default.fileExists(atPath: candidate.path) {
			let candidatePath = String(candidate.path.dropFirst(workspaceURL.path.count + 1))
			return try resolveWorkspacePath(
				candidatePath,
				in: workspaceURL,
				requireRegularFile: true,
				description: "playlist document",
			)
		}
		throw ValidationError("No Playlists/Media document was found under playlist source \(relativePath).")
	}

	private static func requireNonSymlink(_ url: URL, description: String) throws {
		let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
		guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
			throw ValidationError("The \(description) path contains a symbolic link: \(url.path)")
		}
	}
}
