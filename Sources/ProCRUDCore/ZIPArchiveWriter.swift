import Darwin
import Foundation

enum ZIPWriter {
	private enum Source {
		case file(URL)
		case compressed(archiveURL: URL, offset: UInt64)
		case empty
	}

	private struct PendingEntry {
		let rawName: String
		let rawNameData: Data
		let destinationPath: String
		let kind: ZIPEntry.Kind
		let versionMadeBy: UInt16
		let flags: UInt16
		let compressionMethod: UInt16
		let modificationTime: UInt16
		let modificationDate: UInt16
		let checksum: UInt32
		let compressedSize: UInt64
		let uncompressedSize: UInt64
		let externalAttributes: UInt32
		let source: Source
	}

	private struct WrittenEntry {
		let entry: PendingEntry
		let localHeaderOffset: UInt64
	}

	static func create(
		from directory: URL,
		entries: [String],
		to archiveURL: URL,
		replaceExisting: Bool,
		limits: ArchiveLimits,
		deadline suppliedDeadline: ArchiveDeadline? = nil,
	) throws {
		try limits.validate()
		let deadline = suppliedDeadline ?? ArchiveDeadline(timeout: limits.processingTimeout)
		let pending = try pendingFiles(
			from: directory,
			entries: entries,
			limits: limits,
			deadline: deadline,
		)
		try writeTransactionally(
			pending,
			to: archiveURL,
			replaceExisting: replaceExisting,
			limits: limits,
			deadline: deadline,
		)
	}

	static func update(
		from directory: URL,
		entries updatedPaths: [String],
		in archiveURL: URL,
		limits: ArchiveLimits,
		deadline suppliedDeadline: ArchiveDeadline? = nil,
	) throws {
		try limits.validate()
		let deadline = suppliedDeadline ?? ArchiveDeadline(timeout: limits.processingTimeout)
		let reader = try ZIPReader(archiveURL: archiveURL, limits: limits, deadline: deadline)
		let validatedUpdates = try validatedEntryNames(updatedPaths, limits: limits)
		var updatesByPath = Dictionary(uniqueKeysWithValues: validatedUpdates.map { ($0, $0) })
		let existingPaths = Set(reader.entries.map(\.destinationPath))
		let resultingEntryCount = reader.entries.count + validatedUpdates.lazy.filter { !existingPaths.contains($0) }.count
		guard resultingEntryCount <= limits.maximumEntryCount else {
			throw ArchiveError.entryCountLimitExceeded(
				count: UInt64(resultingEntryCount),
				limit: limits.maximumEntryCount,
			)
		}
		var pending: [PendingEntry] = []
		pending.reserveCapacity(resultingEntryCount)
		var totalSize: UInt64 = 0

		for original in reader.entries {
			try deadline.check()
			if let updatePath = updatesByPath.removeValue(forKey: original.destinationPath) {
				let sourceURL = directory.appendingPathComponent(updatePath)
				let file = try pendingFile(
					root: directory,
					sourceURL: sourceURL,
					rawName: original.rawName,
					rawNameData: Data(original.rawName.utf8),
					destinationPath: original.destinationPath,
					limits: limits,
					deadline: deadline,
				)
				totalSize = try add(totalSize, file.uncompressedSize)
				guard totalSize <= limits.maximumExpandedSize else {
					throw ArchiveError.expandedSizeLimitExceeded(
						size: totalSize,
						limit: limits.maximumExpandedSize,
					)
				}
				pending.append(file)
			} else {
				let compressionMethod: UInt16 = original.kind == .directory
					? 0
					: original.compressionMethod
				let file = PendingEntry(
					rawName: original.rawName,
					rawNameData: Data(original.rawName.utf8),
					destinationPath: original.destinationPath,
					kind: original.kind,
					versionMadeBy: original.versionMadeBy,
					flags: (original.flags | 0x0800) & ~0x0008,
					compressionMethod: compressionMethod,
					modificationTime: original.modificationTime,
					modificationDate: original.modificationDate,
					checksum: original.crc32,
					compressedSize: original.compressedSize,
					uncompressedSize: original.uncompressedSize,
					externalAttributes: original.externalAttributes,
					source: original.kind == .file
						? .compressed(archiveURL: archiveURL, offset: original.dataOffset)
						: .empty,
				)
				totalSize = try add(totalSize, file.uncompressedSize)
				guard totalSize <= limits.maximumExpandedSize else {
					throw ArchiveError.expandedSizeLimitExceeded(
						size: totalSize,
						limit: limits.maximumExpandedSize,
					)
				}
				pending.append(file)
			}
		}
		for updatePath in validatedUpdates where updatesByPath[updatePath] != nil {
			let sourceURL = directory.appendingPathComponent(updatePath)
			let file = try pendingFile(
				root: directory,
				sourceURL: sourceURL,
				rawName: updatePath,
				rawNameData: Data(updatePath.utf8),
				destinationPath: updatePath,
				limits: limits,
				deadline: deadline,
			)
			totalSize = try add(totalSize, file.uncompressedSize)
			guard totalSize <= limits.maximumExpandedSize else {
				throw ArchiveError.expandedSizeLimitExceeded(
					size: totalSize,
					limit: limits.maximumExpandedSize,
				)
			}
			pending.append(file)
		}
		try validatePendingEntries(pending, limits: limits)
		try writeTransactionally(
			pending,
			to: archiveURL,
			replaceExisting: true,
			limits: limits,
			deadline: deadline,
		)
	}

	private static func pendingFiles(
		from directory: URL,
		entries: [String],
		limits: ArchiveLimits,
		deadline: ArchiveDeadline,
	) throws -> [PendingEntry] {
		guard entries.count <= limits.maximumEntryCount else {
			throw ArchiveError.entryCountLimitExceeded(
				count: UInt64(entries.count),
				limit: limits.maximumEntryCount,
			)
		}
		let validated = try validatedEntryNames(entries, limits: limits)
		var result: [PendingEntry] = []
		result.reserveCapacity(validated.count)
		var totalSize: UInt64 = 0
		for entry in validated {
			try deadline.check()
			let pending = try pendingFile(
				root: directory,
				sourceURL: directory.appendingPathComponent(entry),
				rawName: entry,
				rawNameData: Data(entry.utf8),
				destinationPath: entry,
				limits: limits,
				deadline: deadline,
			)
			totalSize = try add(totalSize, pending.uncompressedSize)
			guard totalSize <= limits.maximumExpandedSize else {
				throw ArchiveError.expandedSizeLimitExceeded(
					size: totalSize,
					limit: limits.maximumExpandedSize,
				)
			}
			result.append(pending)
		}
		return result
	}

	private static func pendingFile(
		root: URL,
		sourceURL: URL,
		rawName: String,
		rawNameData: Data,
		destinationPath: String,
		limits: ArchiveLimits,
		deadline: ArchiveDeadline,
	) throws -> PendingEntry {
		try validateLexicalContainment(sourceURL, inside: root)
		let opened = try openRegularFile(sourceURL)
		defer { try? opened.handle.close() }
		try validateResolvedContainment(sourceURL, inside: root)
		guard opened.information.st_size >= 0 else {
			throw ArchiveError.invalidEntry(rawName)
		}
		let size = UInt64(opened.information.st_size)
		guard size <= limits.maximumEntrySize else {
			throw ArchiveError.entrySizeLimitExceeded(
				entry: rawName,
				size: size,
				limit: limits.maximumEntrySize,
			)
		}
		let checksum = try checksum(of: opened.handle, deadline: deadline)
		let modificationDate = Date(
			timeIntervalSince1970: TimeInterval(opened.information.st_mtimespec.tv_sec),
		)
		let timestamp = dosTimestamp(modificationDate)
		return PendingEntry(
			rawName: rawName,
			rawNameData: rawNameData,
			destinationPath: destinationPath,
			kind: .file,
			versionMadeBy: 0x031E,
			flags: 0x0800,
			compressionMethod: 0,
			modificationTime: timestamp.time,
			modificationDate: timestamp.date,
			checksum: checksum,
			compressedSize: size,
			uncompressedSize: size,
			externalAttributes: UInt32(0o100600) << 16,
			source: .file(sourceURL),
		)
	}

	private static func writeTransactionally(
		_ entries: [PendingEntry],
		to archiveURL: URL,
		replaceExisting: Bool,
		limits: ArchiveLimits,
		deadline: ArchiveDeadline,
	) throws {
		let fileManager = FileManager.default
		let parentURL = archiveURL.deletingLastPathComponent()
		try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
		let temporaryURL = parentURL.appendingPathComponent(
			".\(archiveURL.lastPathComponent)-write-\(UUID().uuidString)",
		)

		var ownsTemporaryFile = false
		do {
			let output = try ZIPOutput(url: temporaryURL)
			ownsTemporaryFile = true
			do {
				try write(entries, to: output, deadline: deadline)
				try output.close()
			} catch {
				try? output.close()
				throw error
			}
			try deadline.check()
			_ = try ZIPReader(archiveURL: temporaryURL, limits: limits, deadline: deadline)
			try deadline.check()
			try ArchiveFileIO.installTemporaryFile(
				temporaryURL,
				at: archiveURL,
				replaceExisting: replaceExisting,
			)
			ownsTemporaryFile = false
		} catch {
			if ownsTemporaryFile {
				try? fileManager.removeItem(at: temporaryURL)
			}
			throw error
		}
	}

	private static func validatePendingEntries(
		_ entries: [PendingEntry],
		limits: ArchiveLimits,
	) throws {
		var destinations = Set<String>()
		var totalSize: UInt64 = 0
		for entry in entries {
			let key = entry.destinationPath.precomposedStringWithCanonicalMapping.lowercased()
			guard destinations.insert(key).inserted else {
				throw ArchiveError.duplicateDestination(entry.destinationPath)
			}
			totalSize = try add(totalSize, entry.uncompressedSize)
			guard totalSize <= limits.maximumExpandedSize else {
				throw ArchiveError.expandedSizeLimitExceeded(
					size: totalSize,
					limit: limits.maximumExpandedSize,
				)
			}
		}
	}

	private static func write(
		_ entries: [PendingEntry],
		to output: ZIPOutput,
		deadline: ArchiveDeadline,
	) throws {
		var written: [WrittenEntry] = []
		written.reserveCapacity(entries.count)
		for entry in entries {
			try deadline.check()
			let localHeaderOffset = output.offset
			try writeLocalHeader(for: entry, to: output)
			try writeData(for: entry, to: output, deadline: deadline)
			written.append(WrittenEntry(entry: entry, localHeaderOffset: localHeaderOffset))
		}

		let centralDirectoryOffset = output.offset
		for entry in written {
			try deadline.check()
			try writeCentralHeader(for: entry, to: output)
		}
		let centralDirectorySize = output.offset - centralDirectoryOffset
		try writeEndRecords(
			entryCount: UInt64(written.count),
			centralDirectorySize: centralDirectorySize,
			centralDirectoryOffset: centralDirectoryOffset,
			to: output,
		)
	}

	private static func writeLocalHeader(for entry: PendingEntry, to output: ZIPOutput) throws {
		// ProPresenter deliberately uses ZIP64 sizes for every member. Preserve that
		// convention, but include only the two fields required by the ZIP specification.
		var extra = Data()
		extra.appendLittleEndian(UInt16(0x0001))
		extra.appendLittleEndian(UInt16(16))
		extra.appendLittleEndian(entry.uncompressedSize)
		extra.appendLittleEndian(entry.compressedSize)
		guard entry.rawNameData.count <= Int(UInt16.max), extra.count <= Int(UInt16.max) else {
			throw ArchiveError.invalidEntry(entry.rawName)
		}

		var header = Data()
		header.appendLittleEndian(UInt32(0x0403_4B50))
		header.appendLittleEndian(UInt16(45))
		header.appendLittleEndian(entry.flags & ~0x0008)
		header.appendLittleEndian(entry.compressionMethod)
		header.appendLittleEndian(entry.modificationTime)
		header.appendLittleEndian(entry.modificationDate)
		header.appendLittleEndian(entry.checksum)
		header.appendLittleEndian(UInt32.max)
		header.appendLittleEndian(UInt32.max)
		header.appendLittleEndian(UInt16(entry.rawNameData.count))
		header.appendLittleEndian(UInt16(extra.count))
		try output.write(header)
		try output.write(entry.rawNameData)
		try output.write(extra)
	}

	private static func writeCentralHeader(for written: WrittenEntry, to output: ZIPOutput) throws {
		let entry = written.entry
		var extra = Data()
		extra.appendLittleEndian(UInt16(0x0001))
		let includeOffset = written.localHeaderOffset >= UInt64(UInt32.max)
		extra.appendLittleEndian(UInt16(includeOffset ? 24 : 16))
		extra.appendLittleEndian(entry.uncompressedSize)
		extra.appendLittleEndian(entry.compressedSize)
		if includeOffset {
			extra.appendLittleEndian(written.localHeaderOffset)
		}

		var header = Data()
		header.appendLittleEndian(UInt32(0x0201_4B50))
		header.appendLittleEndian(entry.versionMadeBy)
		header.appendLittleEndian(UInt16(45))
		header.appendLittleEndian(entry.flags & ~0x0008)
		header.appendLittleEndian(entry.compressionMethod)
		header.appendLittleEndian(entry.modificationTime)
		header.appendLittleEndian(entry.modificationDate)
		header.appendLittleEndian(entry.checksum)
		header.appendLittleEndian(UInt32.max)
		header.appendLittleEndian(UInt32.max)
		header.appendLittleEndian(UInt16(entry.rawNameData.count))
		header.appendLittleEndian(UInt16(extra.count))
		header.appendLittleEndian(UInt16(0))
		header.appendLittleEndian(UInt16(0))
		header.appendLittleEndian(UInt16(0))
		header.appendLittleEndian(entry.externalAttributes)
		header.appendLittleEndian(includeOffset ? UInt32.max : UInt32(written.localHeaderOffset))
		try output.write(header)
		try output.write(entry.rawNameData)
		try output.write(extra)
	}

	private static func writeEndRecords(
		entryCount: UInt64,
		centralDirectorySize: UInt64,
		centralDirectoryOffset: UInt64,
		to output: ZIPOutput,
	) throws {
		let zip64Offset = output.offset
		var zip64 = Data()
		zip64.appendLittleEndian(UInt32(0x0606_4B50))
		zip64.appendLittleEndian(UInt64(44))
		zip64.appendLittleEndian(UInt16(0x031E))
		zip64.appendLittleEndian(UInt16(45))
		zip64.appendLittleEndian(UInt32(0))
		zip64.appendLittleEndian(UInt32(0))
		zip64.appendLittleEndian(entryCount)
		zip64.appendLittleEndian(entryCount)
		zip64.appendLittleEndian(centralDirectorySize)
		zip64.appendLittleEndian(centralDirectoryOffset)
		try output.write(zip64)

		var locator = Data()
		locator.appendLittleEndian(UInt32(0x0706_4B50))
		locator.appendLittleEndian(UInt32(0))
		locator.appendLittleEndian(zip64Offset)
		locator.appendLittleEndian(UInt32(1))
		try output.write(locator)

		var classic = Data()
		classic.appendLittleEndian(UInt32(0x0605_4B50))
		classic.appendLittleEndian(UInt16(0))
		classic.appendLittleEndian(UInt16(0))
		classic.appendLittleEndian(UInt16(clamping: entryCount))
		classic.appendLittleEndian(UInt16(clamping: entryCount))
		classic.appendLittleEndian(UInt32(clamping: centralDirectorySize))
		classic.appendLittleEndian(UInt32(clamping: centralDirectoryOffset))
		classic.appendLittleEndian(UInt16(0))
		try output.write(classic)
	}

	private static func writeData(
		for entry: PendingEntry,
		to output: ZIPOutput,
		deadline: ArchiveDeadline,
	) throws {
		switch entry.source {
		case .empty:
			return
		case let .file(url):
			let opened = try openRegularFile(url)
			let input = opened.handle
			defer { try? opened.handle.close() }
			guard opened.information.st_size >= 0,
			      UInt64(opened.information.st_size) == entry.uncompressedSize
			else {
				throw ArchiveError.integrityCheckFailed(entry.rawName)
			}
			var size: UInt64 = 0
			var checksum: UInt32 = 0
			while true {
				try deadline.check()
				let data = try input.read(upToCount: 64 * 1024) ?? Data()
				guard !data.isEmpty else { break }
				let (newSize, overflow) = size.addingReportingOverflow(UInt64(data.count))
				guard !overflow, newSize <= entry.uncompressedSize else {
					throw ArchiveError.integrityCheckFailed(entry.rawName)
				}
				try output.write(data)
				size = newSize
				checksum = zipCRC32(checksum, data)
			}
			guard size == entry.uncompressedSize, checksum == entry.checksum else {
				throw ArchiveError.integrityCheckFailed(entry.rawName)
			}
		case let .compressed(archiveURL, dataOffset):
			let input = try ZIPFile(url: archiveURL, forWriting: false)
			defer { input.close() }
			try input.seek(to: dataOffset)
			var remaining = entry.compressedSize
			while remaining > 0 {
				try deadline.check()
				let data = try input.readExactly(count: Int(min(remaining, 64 * 1024)))
				try output.write(data)
				remaining -= UInt64(data.count)
			}
		}
	}

	private static func validatedEntryNames(
		_ entries: [String],
		limits: ArchiveLimits,
	) throws -> [String] {
		var seen = Set<String>()
		for entry in entries {
			guard !entry.isEmpty,
			      !entry.hasPrefix("/"),
			      !entry.contains("\\"),
			      entry.utf8.count <= limits.maximumPathLength,
			      !entry.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
			else {
				throw ArchiveError.invalidEntry(entry)
			}
			let components = entry.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
			guard components.count <= limits.maximumPathDepth,
			      components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
			      components.allSatisfy({ $0.utf8.count <= limits.maximumPathComponentLength }),
			      components.first?.range(of: "^[A-Za-z]:", options: .regularExpression) == nil
			else {
				throw ArchiveError.invalidEntry(entry)
			}
			let key = entry.precomposedStringWithCanonicalMapping.lowercased()
			guard seen.insert(key).inserted else {
				throw ArchiveError.duplicateDestination(entry)
			}
		}
		return entries
	}

	private static func validateLexicalContainment(_ fileURL: URL, inside rootURL: URL) throws {
		let lexicalRootPath = rootURL.standardizedFileURL.path
		let lexicalPath = fileURL.standardizedFileURL.path
		guard lexicalPath.hasPrefix(lexicalRootPath + "/") else {
			throw ArchiveError.invalidEntry(fileURL.path)
		}
	}

	private static func validateResolvedContainment(_ fileURL: URL, inside rootURL: URL) throws {
		let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
		let resolvedPath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
		guard resolvedPath.hasPrefix(rootPath + "/") else {
			throw ArchiveError.invalidEntry(fileURL.path)
		}
	}

	private static func openRegularFile(_ fileURL: URL) throws -> (handle: FileHandle, information: stat) {
		let descriptor = fileURL.path.withCString { path in
			Darwin.open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
		}
		guard descriptor >= 0 else {
			if errno == ELOOP {
				throw ArchiveError.unsupportedEntryType(entry: fileURL.path)
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
			throw ArchiveError.unsupportedEntryType(entry: fileURL.path)
		}
		return (FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), information)
	}

	private static func checksum(of input: FileHandle, deadline: ArchiveDeadline) throws -> UInt32 {
		var checksum: UInt32 = 0
		while true {
			try deadline.check()
			let data = try input.read(upToCount: 64 * 1024) ?? Data()
			guard !data.isEmpty else { return checksum }
			checksum = zipCRC32(checksum, data)
		}
	}

	private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = .current
		let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
		let year = min(max(components.year ?? 1980, 1980), 2107)
		let month = min(max(components.month ?? 1, 1), 12)
		let day = min(max(components.day ?? 1, 1), 31)
		let hour = min(max(components.hour ?? 0, 0), 23)
		let minute = min(max(components.minute ?? 0, 0), 59)
		let second = min(max(components.second ?? 0, 0), 59)
		return (
			UInt16(hour << 11 | minute << 5 | second / 2),
			UInt16((year - 1980) << 9 | month << 5 | day),
		)
	}

	private static func add(_ left: UInt64, _ right: UInt64) throws -> UInt64 {
		let (result, overflow) = left.addingReportingOverflow(right)
		guard !overflow else {
			throw ArchiveError.invalidArchive("An archive size overflows 64-bit arithmetic.")
		}
		return result
	}
}

private final class ZIPOutput {
	private let handle: FileHandle
	private(set) var offset: UInt64 = 0

	init(url: URL) throws {
		let descriptor = url.path.withCString { path in
			Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
		}
		guard descriptor >= 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
	}

	func write(_ data: Data) throws {
		try handle.write(contentsOf: data)
		offset += UInt64(data.count)
	}

	func close() throws {
		try handle.synchronize()
		try handle.close()
	}
}

private extension Data {
	mutating func appendLittleEndian(_ value: UInt16) {
		append(UInt8(truncatingIfNeeded: value))
		append(UInt8(truncatingIfNeeded: value >> 8))
	}

	mutating func appendLittleEndian(_ value: UInt32) {
		appendLittleEndian(UInt16(truncatingIfNeeded: value))
		appendLittleEndian(UInt16(truncatingIfNeeded: value >> 16))
	}

	mutating func appendLittleEndian(_ value: UInt64) {
		appendLittleEndian(UInt32(truncatingIfNeeded: value))
		appendLittleEndian(UInt32(truncatingIfNeeded: value >> 32))
	}
}
