import Darwin
import Foundation

enum ArchiveFileIO {
	struct Snapshot {
		let size: UInt64
	}

	static func snapshot(of url: URL) throws -> Snapshot {
		let opened = try openRegularFile(url)
		defer { try? opened.handle.close() }
		guard opened.information.st_size >= 0 else {
			throw ArchiveError.invalidEntry(url.path)
		}
		return Snapshot(size: UInt64(opened.information.st_size))
	}

	static func copyRegularFile(
		from sourceURL: URL,
		to destinationURL: URL,
		expectedSize: UInt64,
		deadline: ArchiveDeadline,
	) throws {
		let opened = try openRegularFile(sourceURL)
		defer { try? opened.handle.close() }
		guard opened.information.st_size >= 0,
		      UInt64(opened.information.st_size) == expectedSize
		else {
			throw ArchiveError.integrityCheckFailed(sourceURL.path)
		}

		let fileManager = FileManager.default
		try fileManager.createDirectory(
			at: destinationURL.deletingLastPathComponent(),
			withIntermediateDirectories: true,
		)
		let descriptor = destinationURL.path.withCString { path in
			Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
		}
		guard descriptor >= 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
		do {
			var copiedSize: UInt64 = 0
			while true {
				try deadline.check()
				let data = try opened.handle.read(upToCount: 64 * 1024) ?? Data()
				guard !data.isEmpty else { break }
				let (newCopiedSize, overflow) = copiedSize.addingReportingOverflow(UInt64(data.count))
				guard !overflow, newCopiedSize <= expectedSize else {
					throw ArchiveError.integrityCheckFailed(sourceURL.path)
				}
				copiedSize = newCopiedSize
				try output.write(contentsOf: data)
			}
			guard copiedSize == expectedSize else {
				throw ArchiveError.integrityCheckFailed(sourceURL.path)
			}
			try output.close()
			try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
		} catch {
			try? output.close()
			try? fileManager.removeItem(at: destinationURL)
			throw error
		}
	}

	static func contentsEqual(
		_ firstURL: URL,
		_ secondURL: URL,
		deadline: ArchiveDeadline,
	) throws -> Bool {
		let first = try openRegularFile(firstURL)
		defer { try? first.handle.close() }
		let second = try openRegularFile(secondURL)
		defer { try? second.handle.close() }

		guard first.information.st_size >= 0, second.information.st_size >= 0 else {
			throw ArchiveError.invalidEntry(firstURL.path)
		}
		guard first.information.st_size == second.information.st_size else { return false }
		if first.information.st_dev == second.information.st_dev,
		   first.information.st_ino == second.information.st_ino
		{
			return true
		}

		while true {
			try deadline.check()
			let firstData = try read(upToCount: 64 * 1024, from: first.handle)
			let secondData = try read(upToCount: 64 * 1024, from: second.handle)
			guard firstData == secondData else { return false }
			if firstData.isEmpty {
				return true
			}
		}
	}

	static func installTemporaryFile(
		_ temporaryURL: URL,
		at destinationURL: URL,
		replaceExisting: Bool,
	) throws {
		let status = temporaryURL.path.withCString { temporaryPath in
			destinationURL.path.withCString { destinationPath in
				if replaceExisting {
					Darwin.rename(temporaryPath, destinationPath)
				} else {
					renamex_np(temporaryPath, destinationPath, UInt32(RENAME_EXCL))
				}
			}
		}
		guard status == 0 else {
			let error = errno
			if !replaceExisting, error == EEXIST {
				throw DocumentArchiveError.outputExists(destinationURL)
			}
			throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
		}
	}

	private static func read(upToCount count: Int, from handle: FileHandle) throws -> Data {
		var result = Data()
		result.reserveCapacity(count)
		while result.count < count {
			let data = try handle.read(upToCount: count - result.count) ?? Data()
			guard !data.isEmpty else { break }
			result.append(data)
		}
		return result
	}

	private static func openRegularFile(_ url: URL) throws -> (handle: FileHandle, information: stat) {
		let descriptor = url.path.withCString { path in
			Darwin.open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
		}
		guard descriptor >= 0 else {
			if errno == ELOOP {
				throw ArchiveError.unsupportedEntryType(entry: url.path)
			}
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		var information = stat()
		guard fstat(descriptor, &information) == 0 else {
			let error = errno
			Darwin.close(descriptor)
			throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
		}
		guard information.st_mode & S_IFMT == S_IFREG else {
			Darwin.close(descriptor)
			throw ArchiveError.unsupportedEntryType(entry: url.path)
		}
		return (FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), information)
	}
}

final class ArchiveCopyBudget {
	let deadline: ArchiveDeadline
	let limits: ArchiveLimits

	private var accountedEntries: [String: UInt64] = [:]
	private var expandedSize: UInt64 = 0

	init(limits: ArchiveLimits, deadline: ArchiveDeadline) {
		self.limits = limits
		self.deadline = deadline
	}

	@discardableResult
	func accountExisting(_ sourceURL: URL, entry: String) throws -> UInt64 {
		try deadline.check()
		let snapshot = try ArchiveFileIO.snapshot(of: sourceURL)
		try account(size: snapshot.size, entry: entry)
		return snapshot.size
	}

	func account(size: UInt64, entry: String) throws {
		try deadline.check()
		if let existingSize = accountedEntries[entry] {
			guard existingSize == size else {
				throw ArchiveError.integrityCheckFailed(entry)
			}
			return
		}
		guard size <= limits.maximumEntrySize else {
			throw ArchiveError.entrySizeLimitExceeded(
				entry: entry,
				size: size,
				limit: limits.maximumEntrySize,
			)
		}
		let (newEntryCount, entryCountOverflow) = UInt64(accountedEntries.count).addingReportingOverflow(1)
		guard !entryCountOverflow, newEntryCount <= UInt64(limits.maximumEntryCount) else {
			throw ArchiveError.entryCountLimitExceeded(
				count: entryCountOverflow ? UInt64.max : newEntryCount,
				limit: limits.maximumEntryCount,
			)
		}
		let (newExpandedSize, expandedSizeOverflow) = expandedSize.addingReportingOverflow(size)
		guard !expandedSizeOverflow, newExpandedSize <= limits.maximumExpandedSize else {
			throw ArchiveError.expandedSizeLimitExceeded(
				size: expandedSizeOverflow ? UInt64.max : newExpandedSize,
				limit: limits.maximumExpandedSize,
			)
		}
		accountedEntries[entry] = size
		expandedSize = newExpandedSize
	}

	@discardableResult
	func copy(from sourceURL: URL, to destinationURL: URL, entry: String) throws -> UInt64 {
		let size = try accountExisting(sourceURL, entry: entry)
		try ArchiveFileIO.copyRegularFile(
			from: sourceURL,
			to: destinationURL,
			expectedSize: size,
			deadline: deadline,
		)
		return size
	}
}
