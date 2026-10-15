import CryptoKit
import Darwin
import Foundation

public struct NativeMediaStoreReadLimits: Sendable {
	public var maximumFileBytes = 64 * 1024 * 1024
	public var maximumTotalBytes = 512 * 1024 * 1024
	public var maximumRecordBytes = 16 * 1024 * 1024
	public var maximumRecords = 1_000_000
	public var attempts = 3
	public init() {}
}

struct MediaStoreCapture {
	let records: [String: MediaStoreRecord]
	let tableFiles: [String]
	let logFiles: [String]
	let verifiedTableBlocks: Int
	let sequence: UInt64
	let fingerprint: String

	static func read(at root: URL, limits: NativeMediaStoreReadLimits, beforeValidation: () throws -> Void = {}) throws -> Self {
		guard limits.maximumFileBytes > 0, limits.maximumTotalBytes >= limits.maximumFileBytes,
		      limits.maximumRecordBytes > 0, limits.maximumRecordBytes <= limits.maximumFileBytes,
		      limits.maximumRecords > 0, (1 ... 8).contains(limits.attempts)
		else { throw NativeMediaStoreError.limitExceeded }
		let deadline = ArchiveDeadline(timeout: .seconds(30))
		for _ in 0 ..< limits.attempts {
			var source = try Source(root: root, limits: limits, deadline: deadline)
			do {
				let result = try capture(source: &source)
				try beforeValidation()
				try source.validate()
				return result
			} catch {
				if case NativeMediaStoreError.changedDuringRead = error {
					continue
				}
				do { try source.validate() } catch NativeMediaStoreError.changedDuringRead { continue }
				throw error
			}
		}
		throw NativeMediaStoreError.changedDuringRead
	}

	private static func capture(source: inout Source) throws -> Self {
		guard let current = try String(data: source.read("CURRENT"), encoding: .utf8) else { throw NativeMediaStoreError.invalid("CURRENT is not UTF-8") }
		let manifestName = current.trimmingCharacters(in: .newlines)
		guard manifestName.wholeMatch(of: /MANIFEST-[0-9]+/) != nil else { throw NativeMediaStoreError.invalid("CURRENT manifest name") }
		let limits = source.limits
		let manifest = try MediaStoreManifest(data: source.read(manifestName), maximumRecordBytes: limits.maximumRecordBytes, maximumRecords: limits.maximumRecords)
		var latest: [String: MediaStoreRecord] = [:], totalRecords = 0, blockCount = 0, sequence = manifest.lastSequence
		func apply(_ records: [MediaStoreRecord]) throws {
			guard records.count <= limits.maximumRecords - totalRecords else { throw NativeMediaStoreError.limitExceeded }
			totalRecords += records.count
			for record in records {
				sequence = max(sequence, record.sequence)
				if let previous = latest[record.key] {
					if previous.sequence > record.sequence {
						continue
					}
					if previous.sequence == record.sequence {
						guard previous == record else { throw NativeMediaStoreError.invalid("conflicting values at one model sequence") }
						continue
					}
				}
				latest[record.key] = record
			}
		}
		var tables: [String] = []
		for file in manifest.files.values.sorted(by: { $0.number < $1.number }) {
			try source.deadline.check()
			let name = String(format: "%06llu.sst", file.number), bytes = try source.read(name)
			guard bytes.count == file.size else { throw NativeMediaStoreError.invalid("table size differs from manifest: \(name)") }
			var table = MediaStoreTable(data: bytes)
			try apply(table.records(maximumRecords: limits.maximumRecords - totalRecords))
			blockCount += table.verifiedBlocks; tables.append(name)
		}
		let logs = source.logs.filter { $0.number >= manifest.logNumber || $0.number == manifest.previousLogNumber }
		for file in logs {
			try source.deadline.check()
			for batch in try MediaStoreLog.records(source.read(file.name), maximumRecordBytes: limits.maximumRecordBytes, maximumRecords: limits.maximumRecords) {
				try apply(MediaStoreWriteBatch.records(batch, maximumRecords: limits.maximumRecords - totalRecords))
			}
		}
		try source.deadline.check()
		var hash = SHA256()
		for (name, file) in source.files.sorted(by: { $0.key < $1.key }) {
			hash.update(data: Data(name.utf8) + Data([0]))
			hash.update(data: Data(SHA256.hash(data: file.data)))
		}
		return .init(records: latest.filter { $0.value.value != nil }, tableFiles: tables, logFiles: logs.map(\.name), verifiedTableBlocks: blockCount, sequence: sequence,
		             fingerprint: hash.finalize().map { String(format: "%02x", $0) }.joined())
	}

	private struct FileState: Equatable {
		let device: dev_t, inode: ino_t, size: off_t
		let modifiedSeconds: Int, modifiedNanoseconds: Int, changedSeconds: Int, changedNanoseconds: Int

		init(_ info: stat) {
			device = info.st_dev; inode = info.st_ino; size = info.st_size
			modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanoseconds = info.st_mtimespec.tv_nsec
			changedSeconds = info.st_ctimespec.tv_sec; changedNanoseconds = info.st_ctimespec.tv_nsec
		}
	}

	private struct Source {
		struct File { let data: Data; let state: FileState }
		struct Log: Equatable { let name: String; let number: UInt64 }
		let root: URL
		let limits: NativeMediaStoreReadLimits
		let deadline: ArchiveDeadline
		let logs: [Log]
		var files: [String: File] = [:]
		var totalBytes = 0

		init(root: URL, limits: NativeMediaStoreReadLimits, deadline: ArchiveDeadline) throws {
			self.root = root; self.limits = limits; self.deadline = deadline
			logs = try Self.logNames(at: root)
		}

		private static func logNames(at root: URL) throws -> [Log] {
			try FileManager.default.contentsOfDirectory(atPath: root.path).compactMap { name in
				guard name.wholeMatch(of: /[0-9]+\.log/) != nil else { return nil }
				guard let number = UInt64(name.dropLast(4)) else { throw NativeMediaStoreError.invalid("WAL file number") }
				return Log(name: name, number: number)
			}.sorted { $0.number < $1.number }
		}

		mutating func read(_ name: String) throws -> Data {
			if let file = files[name] {
				return file.data
			}
			try deadline.check()
			let url = root.appendingPathComponent(name)
			let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
			guard descriptor >= 0 else { throw NativeMediaStoreError.invalid("cannot open source file \(name)") }
			let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
			defer { try? handle.close() }
			var before = stat()
			guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size >= 0 else { throw NativeMediaStoreError.invalid("source must be a regular file: \(name)") }
			guard before.st_size <= limits.maximumFileBytes, before.st_size <= limits.maximumTotalBytes - totalBytes else { throw NativeMediaStoreError.limitExceeded }
			var data = Data()
			while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
				try deadline.check()
				guard chunk.count <= Int(before.st_size) - data.count else { throw NativeMediaStoreError.changedDuringRead }
				data.append(chunk)
			}
			var after = stat(), current = stat()
			guard data.count == before.st_size, fstat(descriptor, &after) == 0, lstat(url.path, &current) == 0,
			      FileState(before) == FileState(after), FileState(before) == FileState(current)
			else { throw NativeMediaStoreError.changedDuringRead }
			files[name] = .init(data: data, state: .init(before)); totalBytes += data.count
			return data
		}

		func validate() throws {
			try deadline.check()
			guard try Self.logNames(at: root) == logs else { throw NativeMediaStoreError.changedDuringRead }
			for (name, file) in files {
				var current = stat()
				guard lstat(root.appendingPathComponent(name).path, &current) == 0, current.st_mode & S_IFMT == S_IFREG,
				      FileState(current) == file.state else { throw NativeMediaStoreError.changedDuringRead }
			}
		}
	}
}
