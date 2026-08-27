import Foundation

public struct ArchiveLimits: Equatable, Sendable {
	public static let `default` = ArchiveLimits()

	public var maximumEntryCount: Int
	public var maximumEntrySize: UInt64
	public var maximumExpandedSize: UInt64
	public var maximumCompressionRatio: UInt64
	public var maximumAggregateCompressionRatio: UInt64
	public var maximumPathLength: Int
	public var maximumPathComponentLength: Int
	public var maximumPathDepth: Int
	public var maximumCentralDirectorySize: UInt64
	public var processingTimeout: Duration

	public init(
		maximumEntryCount: Int = 10000,
		maximumEntrySize: UInt64 = 32 * 1024 * 1024 * 1024,
		maximumExpandedSize: UInt64 = 64 * 1024 * 1024 * 1024,
		maximumCompressionRatio: UInt64 = 200,
		maximumAggregateCompressionRatio: UInt64 = 100,
		maximumPathLength: Int = 4096,
		maximumPathComponentLength: Int = 255,
		maximumPathDepth: Int = 64,
		maximumCentralDirectorySize: UInt64 = 64 * 1024 * 1024,
		processingTimeout: Duration = .seconds(300),
	) {
		self.maximumEntryCount = maximumEntryCount
		self.maximumEntrySize = maximumEntrySize
		self.maximumExpandedSize = maximumExpandedSize
		self.maximumCompressionRatio = maximumCompressionRatio
		self.maximumAggregateCompressionRatio = maximumAggregateCompressionRatio
		self.maximumPathLength = maximumPathLength
		self.maximumPathComponentLength = maximumPathComponentLength
		self.maximumPathDepth = maximumPathDepth
		self.maximumCentralDirectorySize = maximumCentralDirectorySize
		self.processingTimeout = processingTimeout
	}
}

public enum ArchiveError: Error, CustomStringConvertible, Equatable, Sendable {
	case unsupportedArchive(URL)
	case invalidEntry(String)
	case invalidArchive(String)
	case entryCountLimitExceeded(count: UInt64, limit: Int)
	case entrySizeLimitExceeded(entry: String, size: UInt64, limit: UInt64)
	case expandedSizeLimitExceeded(size: UInt64, limit: UInt64)
	case compressionRatioLimitExceeded(entry: String)
	case aggregateCompressionRatioLimitExceeded
	case unsupportedCompressionMethod(entry: String, method: UInt16)
	case unsupportedEntryType(entry: String)
	case encryptedEntry(String)
	case duplicateDestination(String)
	case integrityCheckFailed(String)
	case processingTimedOut
	case commandFailed(command: String, status: Int32, output: String)

	public var description: String {
		switch self {
		case let .unsupportedArchive(url):
			return "Unsupported archive: \(url.path)"
		case let .invalidEntry(entry):
			return "Unsafe archive entry: \(entry.debugDescription)"
		case let .invalidArchive(reason):
			return "Invalid ZIP archive: \(reason)"
		case let .entryCountLimitExceeded(count, limit):
			return "Archive has \(count) entries; the limit is \(limit)."
		case let .entrySizeLimitExceeded(entry, size, limit):
			return "Archive entry \(entry.debugDescription) expands to \(size) bytes; the limit is \(limit)."
		case let .expandedSizeLimitExceeded(size, limit):
			return "Archive expands to \(size) bytes; the limit is \(limit)."
		case let .compressionRatioLimitExceeded(entry):
			return "Archive entry has an unsafe compression ratio: \(entry.debugDescription)"
		case .aggregateCompressionRatioLimitExceeded:
			return "Archive has an unsafe aggregate compression ratio."
		case let .unsupportedCompressionMethod(entry, method):
			return "Archive entry \(entry.debugDescription) uses unsupported compression method \(method)."
		case let .unsupportedEntryType(entry):
			return "Archive entry is a symbolic link or special file: \(entry.debugDescription)"
		case let .encryptedEntry(entry):
			return "Encrypted archive entries are not supported: \(entry.debugDescription)"
		case let .duplicateDestination(entry):
			return "Multiple archive entries resolve to the same destination: \(entry.debugDescription)"
		case let .integrityCheckFailed(entry):
			return "Archive entry failed its integrity check: \(entry.debugDescription)"
		case .processingTimedOut:
			return "Archive processing timed out."
		case let .commandFailed(command, status, output):
			return "\(command) failed with status \(status): \(output)"
		}
	}
}

enum ZIPArchive {
	static func entries(
		in archiveURL: URL,
		limits: ArchiveLimits = .default,
	) throws -> [String] {
		try ZIPReader(archiveURL: archiveURL, limits: limits).entries.map(\.rawName)
	}

	static func extract(
		_ archiveURL: URL,
		to directory: URL,
		limits: ArchiveLimits = .default,
	) throws {
		try ZIPReader(archiveURL: archiveURL, limits: limits).extract(to: directory)
	}

	static func create(
		from directory: URL,
		entries: [String],
		to archiveURL: URL,
		replaceExisting: Bool = true,
		limits: ArchiveLimits = .default,
		deadline: ArchiveDeadline? = nil,
	) throws {
		try ZIPWriter.create(
			from: directory,
			entries: entries,
			to: archiveURL,
			replaceExisting: replaceExisting,
			limits: limits,
			deadline: deadline,
		)
	}

	static func update(
		from directory: URL,
		entries: [String],
		in archiveURL: URL,
		limits: ArchiveLimits = .default,
		deadline: ArchiveDeadline? = nil,
	) throws {
		try ZIPWriter.update(
			from: directory,
			entries: entries,
			in: archiveURL,
			limits: limits,
			deadline: deadline,
		)
	}
}

final class TemporaryDirectoryOwner: Sendable {
	let url: URL

	init(url: URL) {
		self.url = url
	}

	deinit {
		try? FileManager.default.removeItem(at: url)
	}
}

extension ArchiveLimits {
	func validate() throws {
		guard maximumEntryCount >= 0,
		      maximumPathLength >= 0,
		      maximumPathComponentLength >= 0,
		      maximumPathDepth >= 0
		else {
			throw ArchiveError.invalidArchive("Archive limits cannot be negative.")
		}
	}
}
