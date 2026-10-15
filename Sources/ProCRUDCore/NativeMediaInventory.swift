import Foundation

/// File availability is established from current document locators and regular
/// files, never from the derived MediaStore projection/thumbnail caches. This
/// does not assert membership in the native asset store or Cloud availability.
public struct NativeMediaInventory: Encodable, Sendable {
	public struct File: Codable, Sendable, Equatable {
		public let path: String
		public let byteCount: UInt64
		public let sha256: String?
	}

	public struct Occurrence: Codable, Sendable, Equatable {
		public let documentID: UUID
		public let reference: MediaReference
		public let files: [File]
		public let diagnostics: [String]
		public let localFilesAvailable: Bool

		init(documentID: UUID, reference: MediaReference, files: [File], diagnostics: [String]) {
			self.documentID = documentID
			self.reference = reference
			self.files = files
			self.diagnostics = diagnostics
			localFilesAvailable = !files.isEmpty && diagnostics.isEmpty
		}
	}

	public struct Uninspected: Codable, Sendable, Equatable {
		public let identity: NativeWorkspaceStream.Identity
		public let reason: String
	}

	public let workspaceID: UUID
	public let occurrences: [Occurrence]
	public let uninspected: [Uninspected]
	public let assetStoreMembership = "unverified"

	public init(snapshot: NativeWorkspaceSnapshot, hashFiles: Bool = false) throws {
		workspaceID = snapshot.workspaceID
		let deadline = ArchiveDeadline(timeout: .seconds(30))
		var occurrences: [Occurrence] = []
		var uninspected: [Uninspected] = []
		var fileCache: [URL: File] = [:]
		for stream in snapshot.streams {
			guard stream.identity.scope == .shared, ["Presentation", "Theme"].contains(stream.identity.kind) else {
				uninspected.append(.init(identity: stream.identity, reason: "Media traversal for this stream kind/scope is not implemented."))
				continue
			}
			guard stream.identity.availability == .available else {
				uninspected.append(.init(identity: stream.identity, reason: "Content unavailable locally; dependencies cannot be enumerated."))
				continue
			}
			do {
				let projection = try stream.protobufProjection()
				try projection.requireComplete()
				for reference in try MediaReference.collect(protobuf: projection.protobuf, messageType: projection.messageType) {
					var files: [File] = []
					var diagnostics = Self.identityDiagnostics(reference)
					if reference.locators.isEmpty {
						diagnostics.append("No file locator in the document occurrence.")
					}
					for locator in reference.locators {
						do {
							let url = try Self.resolve(locator, workspaceRoot: snapshot.root)
							let file: File
							if let cached = fileCache[url] {
								file = cached
							} else {
								let count = try ArchiveFileIO.snapshot(of: url).size
								let hash = try hashFiles ? ArchiveFileIO.sha256(of: url, deadline: deadline) : nil
								file = File(path: url.path, byteCount: count, sha256: hash)
								fileCache[url] = file
							}
							if !files.contains(file) {
								files.append(file)
							}
						} catch {
							diagnostics.append("\(locator.field): \(error)")
						}
					}
					if Set(files.compactMap(\.sha256)).count > 1 {
						diagnostics.append("Occurrence locators resolve to different file contents.")
					}
					occurrences.append(.init(documentID: stream.identity.documentID, reference: reference, files: files, diagnostics: diagnostics))
				}
			} catch {
				uninspected.append(.init(identity: stream.identity, reason: String(describing: error)))
			}
		}
		// A shared asset may have several paths, but differing contents cannot
		// establish a coherent asset association. Reference IDs remain per-use.
		let groups = Dictionary(grouping: occurrences.indices, by: { occurrences[$0].reference.assetID?.lowercased() })
		for (id, indices) in groups where id != nil {
			guard Set(indices.flatMap { occurrences[$0].files.compactMap(\.sha256) }).count > 1 else { continue }
			for index in indices {
				let occurrence = occurrences[index]
				occurrences[index] = .init(documentID: occurrence.documentID, reference: occurrence.reference, files: occurrence.files,
				                           diagnostics: occurrence.diagnostics + ["Shared asset ID resolves to different file contents across occurrences."])
			}
		}
		self.occurrences = occurrences
		self.uninspected = uninspected
	}

	private static func identityDiagnostics(_ reference: MediaReference) -> [String] {
		var issues: [String] = []
		if reference.identitySchemaVersion != "1" {
			issues.append("Unqualified native media identity schema: \(reference.identitySchemaVersion ?? "absent").")
		}
		if UUID(uuidString: reference.referenceID) == nil {
			issues.append("Invalid occurrence reference UUID.")
		}
		if reference.assetID.flatMap(UUID.init(uuidString:)) == nil {
			issues.append("Missing or invalid native asset UUID.")
		}
		if reference.hasProvider {
			issues.append("Provider association is preserved; local provider availability is unqualified.")
		}
		return issues
	}

	static func resolve(_ locator: MediaReference.Locator, workspaceRoot: URL) throws -> URL {
		if locator.remote != nil {
			throw NativeSemanticError.unsupportedNode(path: locator.field, kind: "remote/live source; not a missing local file")
		}
		let candidate: URL
		if let path = locator.localPath {
			guard locator.localRoot == 10 else { throw NativeSemanticError.unsupportedNode(path: locator.field, kind: "relative root \(locator.localRoot.map(String.init) ?? "absent") needs its explicit resource/volume context") }
			candidate = try contained(path, root: workspaceRoot)
		} else if let path = locator.relative {
			candidate = try contained(path, root: workspaceRoot)
		} else if let string = locator.absolute {
			if string.hasPrefix("/") {
				candidate = URL(fileURLWithPath: string)
			} else if let url = URL(string: string), url.isFileURL {
				candidate = url
			} else {
				throw NativeSemanticError.unsupportedNode(path: locator.field, kind: "remote/non-file source; not a missing local file")
			}
		} else {
			throw NativeSemanticError.invalidValue(path: locator.field, expected: "materialized file locator")
		}
		_ = try ArchiveFileIO.snapshot(of: candidate)
		return candidate.standardizedFileURL
	}

	private static func contained(_ path: String, root: URL) throws -> URL {
		guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
			throw NativeSemanticError.invalidValue(path: path, expected: "contained relative file path")
		}
		let candidate = root.appendingPathComponent(path)
		let resolvedRoot = root.resolvingSymlinksInPath().path + "/"
		guard candidate.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) else { throw NativeSemanticError.invalidValue(path: path, expected: "file inside selected workspace") }
		return candidate
	}
}
