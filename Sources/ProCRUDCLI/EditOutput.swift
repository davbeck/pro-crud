import Foundation
import ProCRUDCore
import ProPresenterProto

struct EditPathOutput: Sendable, Equatable {
	enum Kind: String, Sendable {
		case affected = "Affected"
		case created = "Created"
		case removed = "Removed"
	}

	var kind: Kind
	var path: String
}

func printEditPathOutputs(_ outputs: [EditPathOutput]) {
	for output in outputs {
		print("\(output.kind.rawValue): \(output.path)")
	}
}

func canonicalPath(_ path: ComponentPath, in document: ProPresenterDocument) throws -> String {
	try ComponentResolver.resolve(path, in: document).canonicalPath
}

func canonicalPath(_ path: ComponentPath, in presentation: Rv_Data_Presentation) throws -> String {
	try canonicalPath(path, in: transientDocument(for: presentation))
}

func canonicalCreatedSiblingPath(
	sourcePath: String,
	uuid: String,
	in document: ProPresenterDocument,
) throws -> String {
	var path = try ComponentPath(sourcePath)
	guard !path.segments.isEmpty else {
		throw ComponentPathError.unsupported(field: sourcePath, at: "/")
	}
	path.segments[path.segments.count - 1].selector = .field(name: "uuid", value: uuid)
	return try canonicalPath(path, in: document)
}

/// Captures a component by its protobuf storage traversal so an edit may
/// change its identity or effective order without changing which component is
/// reported afterward.
struct EditStablePathContext {
	private var location: ComponentLocation

	init(path: ComponentPath, in document: ProPresenterDocument) throws {
		location = try ComponentResolver.resolve(path, in: document).location
	}

	func resolvedPath(in document: ProPresenterDocument) throws -> String {
		try ComponentResolver.resolve(location, in: document).canonicalPath
	}
}

/// Tracks a media edit through an existing ancestor because callers may target
/// `/fill/media` or `/media/element` before that singular message exists.
struct EditMediaPathContext {
	private var ancestor: ComponentLocation
	private var suffix: [ComponentPath.Segment]

	init(path: ComponentPath, in document: ProPresenterDocument) throws {
		let fields = path.segments.suffix(2).map(\.field)
		let suffixCount = fields == ["fill", "media"] || fields == ["media", "element"] ? 2 : 0
		let ancestorPath = ComponentPath(segments: Array(path.segments.dropLast(suffixCount)))
		ancestor = try ComponentResolver.resolve(ancestorPath, in: document).location
		suffix = Array(path.segments.suffix(suffixCount))
	}

	func resolvedPath(in document: ProPresenterDocument) throws -> String {
		var path = try ComponentPath(ComponentResolver.resolve(ancestor, in: document).canonicalPath)
		path.segments.append(contentsOf: suffix)
		return try canonicalPath(path, in: document)
	}
}

/// Rewrites a component path to collection indexes while preserving the
/// collection's effective path order.
func indexAddressedPath(
	_ path: ComponentPath,
	in document: ProPresenterDocument,
) throws -> ComponentPath {
	var sourcePrefix: [ComponentPath.Segment] = []
	var indexedPrefix: [ComponentPath.Segment] = []
	for sourceSegment in path.segments {
		sourcePrefix.append(sourceSegment)
		guard let selector = sourceSegment.selector else {
			indexedPrefix.append(sourceSegment)
			continue
		}
		if case .index = selector {
			indexedPrefix.append(sourceSegment)
			continue
		}

		let sourceCanonical = try canonicalPath(ComponentPath(segments: sourcePrefix), in: document)
		var index = 0
		var matchedSegment: ComponentPath.Segment?
		while matchedSegment == nil {
			var candidateSegment = sourceSegment
			candidateSegment.selector = .index(index)
			let candidatePath = ComponentPath(segments: indexedPrefix + [candidateSegment])
			do {
				if try canonicalPath(candidatePath, in: document) == sourceCanonical {
					matchedSegment = candidateSegment
				}
			} catch ComponentPathError.noMatch(_, _) {
				throw ComponentPathError.noMatch(path: path.description, candidates: [])
			}
			index += 1
		}
		guard let matchedSegment else { preconditionFailure("Index search exited without a match.") }
		indexedPrefix.append(matchedSegment)
	}
	return ComponentPath(segments: indexedPrefix)
}

struct EditMovePathContext {
	private var sourcePath: ComponentPath
	private var sourceIndex: Int
	private var afterIndex: Int

	init(
		source: ComponentPath,
		after: ComponentPath,
		in document: ProPresenterDocument,
	) throws {
		let canonicalSource = try ComponentPath(canonicalPath(source, in: document))
		let canonicalAfter = try ComponentPath(canonicalPath(after, in: document))
		sourcePath = try indexAddressedPath(canonicalSource, in: document)
		let afterPath = try indexAddressedPath(canonicalAfter, in: document)
		guard sourcePath.segments.dropLast() == afterPath.segments.dropLast(),
		      case let .index(sourceIndex)? = sourcePath.segments.last?.selector,
		      case let .index(afterIndex)? = afterPath.segments.last?.selector
		else {
			throw ComponentPathError.unsupported(
				field: after.description,
				at: "Components must be moved relative to a sibling.",
			)
		}
		self.sourceIndex = sourceIndex
		self.afterIndex = afterIndex
	}

	func resolvedPath(in document: ProPresenterDocument) throws -> String {
		let destinationIndex = if sourceIndex == afterIndex {
			sourceIndex
		} else if sourceIndex < afterIndex {
			afterIndex
		} else {
			afterIndex + 1
		}
		var destinationPath = sourcePath
		destinationPath.segments[destinationPath.segments.count - 1].selector = .index(destinationIndex)
		return try canonicalPath(destinationPath, in: document)
	}
}

func transientDocument(for presentation: Rv_Data_Presentation) -> ProPresenterDocument {
	ProPresenterDocument(
		payload: .presentation(presentation),
		origin: .raw(URL(fileURLWithPath: "/tmp/pro-crud-edit-output.pro")),
	)
}
