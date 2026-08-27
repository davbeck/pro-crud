import Compression
import Darwin
import Foundation
import zlib

struct ZIPEntry: Sendable {
	enum Kind: Sendable {
		case file
		case directory
	}

	let rawName: String
	let rawNameData: Data
	let destinationPath: String
	let kind: Kind
	let versionMadeBy: UInt16
	let versionNeeded: UInt16
	let flags: UInt16
	let compressionMethod: UInt16
	let modificationTime: UInt16
	let modificationDate: UInt16
	let crc32: UInt32
	let compressedSize: UInt64
	let uncompressedSize: UInt64
	let externalAttributes: UInt32
	let localHeaderOffset: UInt64
	let dataOffset: UInt64
}

final class ZIPReader {
	let archiveURL: URL
	let limits: ArchiveLimits
	let entries: [ZIPEntry]
	let fileSize: UInt64

	private let deadline: ArchiveDeadline

	init(
		archiveURL: URL,
		limits: ArchiveLimits,
		deadline suppliedDeadline: ArchiveDeadline? = nil,
	) throws {
		self.archiveURL = archiveURL
		self.limits = limits
		try limits.validate()
		deadline = suppliedDeadline ?? ArchiveDeadline(timeout: limits.processingTimeout)

		let file = try ZIPFile(url: archiveURL, forWriting: false)
		defer { file.close() }
		fileSize = file.size
		entries = try ZIPReader.parse(file: file, limits: limits, deadline: deadline)
	}

	func extract(to destinationURL: URL) throws {
		try deadline.check()
		let fileManager = FileManager.default
		guard !fileManager.fileExists(atPath: destinationURL.path) else {
			throw ArchiveError.invalidArchive("Extraction destination already exists: \(destinationURL.path)")
		}

		let parentURL = destinationURL.deletingLastPathComponent()
		try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
		let stagingURL = parentURL.appendingPathComponent(
			".\(destinationURL.lastPathComponent)-extract-\(UUID().uuidString)",
			isDirectory: true,
		)
		var ownsStagingDirectory = false
		do {
			try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
			ownsStagingDirectory = true
			try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stagingURL.path)
			let file = try ZIPFile(url: archiveURL, forWriting: false)
			defer { file.close() }
			for entry in entries {
				try deadline.check()
				let outputURL = stagingURL.appendingPathComponent(entry.destinationPath)
				try ensureContained(outputURL, by: stagingURL)
				switch entry.kind {
				case .directory:
					try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
					try setDirectoryPermissions(from: outputURL, through: stagingURL)
					try ensureContained(outputURL, by: stagingURL)
				case .file:
					try extract(entry, from: file, to: outputURL, root: stagingURL)
				}
			}
			try deadline.check()
			try ArchiveFileIO.installTemporaryFile(
				stagingURL,
				at: destinationURL,
				replaceExisting: false,
			)
			ownsStagingDirectory = false
		} catch {
			if ownsStagingDirectory {
				try? fileManager.removeItem(at: stagingURL)
			}
			throw error
		}
	}

	private func extract(
		_ entry: ZIPEntry,
		from archive: ZIPFile,
		to outputURL: URL,
		root: URL,
	) throws {
		let fileManager = FileManager.default
		let parentURL = outputURL.deletingLastPathComponent()
		try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
		try setDirectoryPermissions(from: parentURL, through: root)
		try ensureContained(parentURL, by: root)

		let descriptor = outputURL.path.withCString { path in
			Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
		}
		guard descriptor >= 0 else {
			throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
		}
		let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
		do {
			try archive.seek(to: entry.dataOffset)
			let result: (size: UInt64, checksum: UInt32)
			switch entry.compressionMethod {
			case 0:
				result = try copyStored(entry, from: archive, to: output)
			case 8:
				result = try inflate(entry, from: archive, to: output)
			default:
				throw ArchiveError.unsupportedCompressionMethod(
					entry: entry.rawName,
					method: entry.compressionMethod,
				)
			}
			try output.close()
			guard result.size == entry.uncompressedSize, result.checksum == entry.crc32 else {
				throw ArchiveError.integrityCheckFailed(entry.rawName)
			}
			try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
		} catch {
			try? output.close()
			try? fileManager.removeItem(at: outputURL)
			throw error
		}
	}

	private func copyStored(
		_ entry: ZIPEntry,
		from archive: ZIPFile,
		to output: FileHandle,
	) throws -> (size: UInt64, checksum: UInt32) {
		guard entry.compressedSize == entry.uncompressedSize else {
			throw ArchiveError.invalidArchive("Stored entry has unequal sizes: \(entry.rawName)")
		}
		var remaining = entry.compressedSize
		var checksum: UInt32 = 0
		var size: UInt64 = 0
		while remaining > 0 {
			try deadline.check()
			let count = Int(min(remaining, 64 * 1024))
			let data = try archive.readExactly(count: count)
			try output.write(contentsOf: data)
			checksum = zipCRC32(checksum, data)
			size = try ZIPReader.addingWithoutOverflow(size, UInt64(data.count))
			remaining -= UInt64(data.count)
		}
		return (size, checksum)
	}

	private func inflate(
		_ entry: ZIPEntry,
		from archive: ZIPFile,
		to output: FileHandle,
	) throws -> (size: UInt64, checksum: UInt32) {
		let inputCapacity = 64 * 1024
		let outputCapacity = 64 * 1024
		let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: inputCapacity)
		let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputCapacity)
		defer {
			inputBuffer.deallocate()
			outputBuffer.deallocate()
		}
		var stream = compression_stream(
			dst_ptr: outputBuffer,
			dst_size: 0,
			src_ptr: UnsafePointer(inputBuffer),
			src_size: 0,
			state: nil,
		)
		guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
			throw ArchiveError.invalidArchive("Could not initialize DEFLATE decoding.")
		}
		defer { compression_stream_destroy(&stream) }

		var compressedRemaining = entry.compressedSize
		var expandedSize: UInt64 = 0
		var checksum: UInt32 = 0
		while true {
			try deadline.check()
			if stream.src_size == 0, compressedRemaining > 0 {
				let count = Int(min(compressedRemaining, UInt64(inputCapacity)))
				let data = try archive.readExactly(count: count)
				data.copyBytes(to: inputBuffer, count: data.count)
				stream.src_ptr = UnsafePointer(inputBuffer)
				stream.src_size = data.count
				compressedRemaining -= UInt64(data.count)
			}

			stream.dst_ptr = outputBuffer
			stream.dst_size = outputCapacity
			let flags: Int32 = compressedRemaining == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
			let status = compression_stream_process(&stream, flags)
			let producedCount = outputCapacity - stream.dst_size
			if producedCount > 0 {
				let data = Data(bytes: outputBuffer, count: producedCount)
				expandedSize = try ZIPReader.addingWithoutOverflow(
					expandedSize,
					UInt64(producedCount),
				)
				guard expandedSize <= entry.uncompressedSize, expandedSize <= limits.maximumEntrySize else {
					throw ArchiveError.entrySizeLimitExceeded(
						entry: entry.rawName,
						size: expandedSize,
						limit: limits.maximumEntrySize,
					)
				}
				try output.write(contentsOf: data)
				checksum = zipCRC32(checksum, data)
			}

			switch status {
			case COMPRESSION_STATUS_END:
				guard compressedRemaining == 0, stream.src_size == 0 else {
					throw ArchiveError.invalidArchive("Compressed stream ends early: \(entry.rawName)")
				}
				return (expandedSize, checksum)
			case COMPRESSION_STATUS_OK:
				if producedCount == 0, stream.src_size == 0, compressedRemaining == 0 {
					throw ArchiveError.invalidArchive("Truncated DEFLATE stream: \(entry.rawName)")
				}
			case COMPRESSION_STATUS_ERROR:
				throw ArchiveError.integrityCheckFailed(entry.rawName)
			default:
				throw ArchiveError.integrityCheckFailed(entry.rawName)
			}
		}
	}

	private func ensureContained(_ candidateURL: URL, by rootURL: URL) throws {
		let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
		let candidatePath = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
		guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
			throw ArchiveError.invalidEntry(candidateURL.path)
		}
	}

	private func setDirectoryPermissions(from directoryURL: URL, through rootURL: URL) throws {
		var currentURL = directoryURL
		while currentURL.path.count >= rootURL.path.count {
			try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: currentURL.path)
			if currentURL.standardizedFileURL == rootURL.standardizedFileURL {
				break
			}
			currentURL.deleteLastPathComponent()
		}
	}
}

private extension ZIPReader {
	struct EndRecords {
		let entryCount: UInt64
		let centralDirectorySize: UInt64
		let centralDirectoryOffset: UInt64
		let classicOffset: UInt64
		let zip64Offset: UInt64?
		let zip64LocatorOffset: UInt64?
	}

	static func parse(
		file: ZIPFile,
		limits: ArchiveLimits,
		deadline: ArchiveDeadline,
	) throws -> [ZIPEntry] {
		try deadline.check()
		let endRecords = try findEndRecords(in: file)
		guard endRecords.entryCount <= UInt64(limits.maximumEntryCount) else {
			throw ArchiveError.entryCountLimitExceeded(
				count: endRecords.entryCount,
				limit: limits.maximumEntryCount,
			)
		}
		let (maximumDeclaredDirectorySize, directoryLimitOverflow) = limits.maximumCentralDirectorySize
			.addingReportingOverflow(98)
		guard directoryLimitOverflow || endRecords.centralDirectorySize <= maximumDeclaredDirectorySize else {
			throw ArchiveError.invalidArchive("Central directory exceeds its size limit.")
		}

		try file.seek(to: endRecords.centralDirectoryOffset)
		var parsedEntries: [ZIPEntry] = []
		parsedEntries.reserveCapacity(Int(endRecords.entryCount))
		var seenDestinations = Set<String>()
		var seenFiles = Set<String>()
		var requiredDirectories = Set<String>()
		var expandedSize: UInt64 = 0
		var compressedSize: UInt64 = 0

		for _ in 0 ..< endRecords.entryCount {
			try deadline.check()
			let fixed = try file.readExactly(count: 46)
			guard fixed.uint32(at: 0) == 0x0201_4B50 else {
				throw ArchiveError.invalidArchive("Central directory contains an invalid record.")
			}
			let versionMadeBy = fixed.uint16(at: 4)
			let versionNeeded = fixed.uint16(at: 6)
			let flags = fixed.uint16(at: 8)
			let method = fixed.uint16(at: 10)
			let modificationTime = fixed.uint16(at: 12)
			let modificationDate = fixed.uint16(at: 14)
			let checksum = fixed.uint32(at: 16)
			let compressed32 = fixed.uint32(at: 20)
			let uncompressed32 = fixed.uint32(at: 24)
			let nameLength = Int(fixed.uint16(at: 28))
			let extraLength = Int(fixed.uint16(at: 30))
			let commentLength = Int(fixed.uint16(at: 32))
			let diskStart = fixed.uint16(at: 34)
			let externalAttributes = fixed.uint32(at: 38)
			let localOffset32 = fixed.uint32(at: 42)

			guard diskStart == 0 || diskStart == UInt16.max else {
				throw ArchiveError.invalidArchive("Multi-disk ZIP archives are not supported.")
			}
			let rawNameData = try file.readExactly(count: nameLength)
			let extraData = try file.readExactly(count: extraLength)
			_ = try file.readExactly(count: commentLength)
			let rawName = try decodeName(rawNameData, flags: flags, extraData: extraData)
			guard flags & 0x2061 == 0 else {
				throw ArchiveError.encryptedEntry(rawName)
			}
			guard method == 0 || method == 8 else {
				throw ArchiveError.unsupportedCompressionMethod(entry: rawName, method: method)
			}

			let zip64 = try parseZIP64Extra(
				extraData,
				uncompressed32: uncompressed32,
				compressed32: compressed32,
				localOffset32: localOffset32,
				diskStart: diskStart,
			)
			let entryCompressedSize = zip64.compressedSize ?? UInt64(compressed32)
			let entryUncompressedSize = zip64.uncompressedSize ?? UInt64(uncompressed32)
			let localHeaderOffset = zip64.localHeaderOffset ?? UInt64(localOffset32)
			let entryDisk = zip64.diskStart ?? UInt32(diskStart)
			guard entryDisk == 0 else {
				throw ArchiveError.invalidArchive("Multi-disk ZIP archives are not supported.")
			}
			let kind = try entryKind(
				rawName: rawName,
				versionMadeBy: versionMadeBy,
				externalAttributes: externalAttributes,
			)
			let destinationPath = try safeDestinationPath(rawName, kind: kind, limits: limits)
			if kind == .directory,
			   entryCompressedSize != 0 || entryUncompressedSize != 0 || checksum != 0
			{
				throw ArchiveError.invalidArchive("Directory entry contains file data: \(rawName)")
			}
			if method == 0, entryCompressedSize != entryUncompressedSize {
				throw ArchiveError.invalidArchive("Stored entry has unequal sizes: \(rawName)")
			}
			try validateDestination(
				destinationPath,
				kind: kind,
				seenDestinations: &seenDestinations,
				seenFiles: &seenFiles,
				requiredDirectories: &requiredDirectories,
			)
			guard entryUncompressedSize <= limits.maximumEntrySize else {
				throw ArchiveError.entrySizeLimitExceeded(
					entry: rawName,
					size: entryUncompressedSize,
					limit: limits.maximumEntrySize,
				)
			}
			expandedSize = try addingWithoutOverflow(expandedSize, entryUncompressedSize)
			compressedSize = try addingWithoutOverflow(compressedSize, entryCompressedSize)
			guard expandedSize <= limits.maximumExpandedSize else {
				throw ArchiveError.expandedSizeLimitExceeded(
					size: expandedSize,
					limit: limits.maximumExpandedSize,
				)
			}
			let exceedsEntryRatio = entryUncompressedSize >= 1024 * 1024 && unsafeRatio(
				uncompressed: entryUncompressedSize,
				compressed: entryCompressedSize,
				limit: limits.maximumCompressionRatio,
			)
			if exceedsEntryRatio {
				throw ArchiveError.compressionRatioLimitExceeded(entry: rawName)
			}

			let entry = ZIPEntry(
				rawName: rawName,
				rawNameData: rawNameData,
				destinationPath: destinationPath,
				kind: kind,
				versionMadeBy: versionMadeBy,
				versionNeeded: versionNeeded,
				flags: flags,
				compressionMethod: method,
				modificationTime: modificationTime,
				modificationDate: modificationDate,
				crc32: checksum,
				compressedSize: entryCompressedSize,
				uncompressedSize: entryUncompressedSize,
				externalAttributes: externalAttributes,
				localHeaderOffset: localHeaderOffset,
				dataOffset: 0,
			)
			parsedEntries.append(entry)
			guard file.offset - endRecords.centralDirectoryOffset <= limits.maximumCentralDirectorySize else {
				throw ArchiveError.invalidArchive("Central directory exceeds its size limit.")
			}
		}
		try consumeOptionalCentralRecords(
			file: file,
			trailerOffset: endRecords.zip64Offset ?? endRecords.classicOffset,
			centralDirectoryOffset: endRecords.centralDirectoryOffset,
			limits: limits,
			deadline: deadline,
		)

		let centralDirectoryEnd = file.offset
		let actualCentralDirectorySize = centralDirectoryEnd - endRecords.centralDirectoryOffset
		try validateCentralDirectorySize(
			actual: actualCentralDirectorySize,
			declared: endRecords.centralDirectorySize,
			endRecords: endRecords,
		)
		let exceedsAggregateRatio = expandedSize >= 10 * 1024 * 1024 && unsafeRatio(
			uncompressed: expandedSize,
			compressed: compressedSize,
			limit: limits.maximumAggregateCompressionRatio,
		)
		if exceedsAggregateRatio {
			throw ArchiveError.aggregateCompressionRatioLimitExceeded
		}

		var entriesWithOffsets: [ZIPEntry] = []
		entriesWithOffsets.reserveCapacity(parsedEntries.count)
		for entry in parsedEntries {
			try deadline.check()
			try file.seek(to: entry.localHeaderOffset)
			let localHeader = try file.readExactly(count: 30)
			guard localHeader.uint32(at: 0) == 0x0403_4B50 else {
				throw ArchiveError.invalidArchive("Invalid local header: \(entry.rawName)")
			}
			let localFlags = localHeader.uint16(at: 6)
			let localMethod = localHeader.uint16(at: 8)
			let localNameLength = Int(localHeader.uint16(at: 26))
			let localExtraLength = Int(localHeader.uint16(at: 28))
			guard localFlags & 0x2061 == 0, localMethod == entry.compressionMethod else {
				throw ArchiveError.invalidArchive("Local header disagrees with central directory: \(entry.rawName)")
			}
			let localName = try file.readExactly(count: localNameLength)
			guard localName == entry.rawNameData else {
				throw ArchiveError.invalidArchive("Local and central names differ: \(entry.rawName)")
			}
			_ = try file.readExactly(count: localExtraLength)
			let dataOffset = file.offset
			let dataEnd = try addingWithoutOverflow(dataOffset, entry.compressedSize)
			guard dataEnd <= endRecords.centralDirectoryOffset else {
				throw ArchiveError.invalidArchive("Entry data extends into the central directory: \(entry.rawName)")
			}
			entriesWithOffsets.append(
				ZIPEntry(
					rawName: entry.rawName,
					rawNameData: entry.rawNameData,
					destinationPath: entry.destinationPath,
					kind: entry.kind,
					versionMadeBy: entry.versionMadeBy,
					versionNeeded: entry.versionNeeded,
					flags: entry.flags,
					compressionMethod: entry.compressionMethod,
					modificationTime: entry.modificationTime,
					modificationDate: entry.modificationDate,
					crc32: entry.crc32,
					compressedSize: entry.compressedSize,
					uncompressedSize: entry.uncompressedSize,
					externalAttributes: entry.externalAttributes,
					localHeaderOffset: entry.localHeaderOffset,
					dataOffset: dataOffset,
				),
			)
		}
		try validateLocalRanges(entriesWithOffsets)
		return entriesWithOffsets
	}

	static func findEndRecords(in file: ZIPFile) throws -> EndRecords {
		guard file.size >= 22 else {
			throw ArchiveError.invalidArchive("The file is too short to be a ZIP archive.")
		}
		let tailSize = Int(min(file.size, UInt64(65535 + 22)))
		try file.seek(to: file.size - UInt64(tailSize))
		let tail = try file.readExactly(count: tailSize)
		guard let relativeOffset = findClassicEndRecord(in: tail) else {
			throw ArchiveError.invalidArchive("Missing end-of-central-directory record.")
		}
		let classicOffset = file.size - UInt64(tailSize) + UInt64(relativeOffset)
		let classic = Data(tail[relativeOffset ..< relativeOffset + 22])
		guard classic.uint16(at: 4) == 0, classic.uint16(at: 6) == 0 else {
			throw ArchiveError.invalidArchive("Multi-disk ZIP archives are not supported.")
		}

		let classicDiskEntryCount = UInt64(classic.uint16(at: 8))
		let classicEntryCount = UInt64(classic.uint16(at: 10))
		let classicSize = UInt64(classic.uint32(at: 12))
		let classicDirectoryOffset = UInt64(classic.uint32(at: 16))
		guard classicOffset >= 20 else {
			guard classicDiskEntryCount == classicEntryCount,
			      classic.uint16(at: 10) != UInt16.max,
			      classic.uint32(at: 12) != UInt32.max,
			      classic.uint32(at: 16) != UInt32.max
			else {
				throw ArchiveError.invalidArchive("ZIP64 values are present without a ZIP64 locator.")
			}
			return EndRecords(
				entryCount: classicEntryCount,
				centralDirectorySize: classicSize,
				centralDirectoryOffset: classicDirectoryOffset,
				classicOffset: classicOffset,
				zip64Offset: nil,
				zip64LocatorOffset: nil,
			)
		}

		try file.seek(to: classicOffset - 20)
		let locator = try file.readExactly(count: 20)
		guard locator.uint32(at: 0) == 0x0706_4B50 else {
			guard classicDiskEntryCount == classicEntryCount,
			      classic.uint16(at: 10) != UInt16.max,
			      classic.uint32(at: 12) != UInt32.max,
			      classic.uint32(at: 16) != UInt32.max
			else {
				throw ArchiveError.invalidArchive("ZIP64 values are present without a ZIP64 locator.")
			}
			return EndRecords(
				entryCount: classicEntryCount,
				centralDirectorySize: classicSize,
				centralDirectoryOffset: classicDirectoryOffset,
				classicOffset: classicOffset,
				zip64Offset: nil,
				zip64LocatorOffset: nil,
			)
		}
		guard locator.uint32(at: 4) == 0, locator.uint32(at: 16) == 1 else {
			throw ArchiveError.invalidArchive("Multi-disk ZIP64 archives are not supported.")
		}
		let zip64Offset = locator.uint64(at: 8)
		let minimumZIP64End = try addingWithoutOverflow(zip64Offset, 56)
		guard minimumZIP64End <= classicOffset - 20 else {
			throw ArchiveError.invalidArchive("Invalid ZIP64 end record location.")
		}
		try file.seek(to: zip64Offset)
		let fixedZIP64 = try file.readExactly(count: 56)
		guard fixedZIP64.uint32(at: 0) == 0x0606_4B50 else {
			throw ArchiveError.invalidArchive("Missing ZIP64 end-of-central-directory record.")
		}
		let recordBodySize = fixedZIP64.uint64(at: 4)
		let recordSize = try addingWithoutOverflow(12, recordBodySize)
		guard recordBodySize >= 44,
		      try addingWithoutOverflow(zip64Offset, recordSize) == classicOffset - 20
		else {
			throw ArchiveError.invalidArchive("Malformed ZIP64 end-of-central-directory record.")
		}
		guard fixedZIP64.uint32(at: 16) == 0, fixedZIP64.uint32(at: 20) == 0 else {
			throw ArchiveError.invalidArchive("Multi-disk ZIP64 archives are not supported.")
		}
		let diskEntryCount = fixedZIP64.uint64(at: 24)
		let entryCount = fixedZIP64.uint64(at: 32)
		let directorySize = fixedZIP64.uint64(at: 40)
		let directoryOffset = fixedZIP64.uint64(at: 48)
		guard diskEntryCount == entryCount,
		      classic.uint16(at: 8) == UInt16.max || classicDiskEntryCount == diskEntryCount,
		      classic.uint16(at: 10) == UInt16.max || classicEntryCount == entryCount,
		      classic.uint32(at: 12) == UInt32.max || classicSize == directorySize,
		      classic.uint32(at: 16) == UInt32.max || classicDirectoryOffset == directoryOffset
		else {
			throw ArchiveError.invalidArchive("ZIP64 and classic end records disagree.")
		}
		return EndRecords(
			entryCount: entryCount,
			centralDirectorySize: directorySize,
			centralDirectoryOffset: directoryOffset,
			classicOffset: classicOffset,
			zip64Offset: zip64Offset,
			zip64LocatorOffset: classicOffset - 20,
		)
	}

	static func findClassicEndRecord(in tail: Data) -> Int? {
		guard tail.count >= 22 else { return nil }
		for offset in stride(from: tail.count - 22, through: 0, by: -1) {
			guard tail.uint32(at: offset) == 0x0605_4B50 else { continue }
			let commentLength = Int(tail.uint16(at: offset + 20))
			if offset + 22 + commentLength == tail.count {
				return offset
			}
		}
		return nil
	}

	static func validateCentralDirectorySize(
		actual: UInt64,
		declared: UInt64,
		endRecords: EndRecords,
	) throws {
		let actualEnd = try addingWithoutOverflow(endRecords.centralDirectoryOffset, actual)
		let expectedTrailerOffset = endRecords.zip64Offset ?? endRecords.classicOffset
		guard actualEnd == expectedTrailerOffset else {
			throw ArchiveError.invalidArchive("Central directory does not end at its trailer.")
		}
		guard declared != actual else { return }
		let overcountedSize = try addingWithoutOverflow(actual, 98)
		let expectedLocatorOffset = try addingWithoutOverflow(actualEnd, 56)
		let expectedClassicOffset = try addingWithoutOverflow(actualEnd, 76)
		let isProPresenterOvercount = declared == overcountedSize
			&& endRecords.zip64Offset == actualEnd
			&& endRecords.zip64LocatorOffset == expectedLocatorOffset
			&& endRecords.classicOffset == expectedClassicOffset
		guard isProPresenterOvercount else {
			throw ArchiveError.invalidArchive(
				"Central directory size is \(declared) bytes, but parsed records occupy \(actual) bytes.",
			)
		}
	}

	static func validateLocalRanges(_ entries: [ZIPEntry]) throws {
		let sorted = entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
		for pair in zip(sorted, sorted.dropFirst()) {
			let firstDataEnd = try addingWithoutOverflow(pair.0.dataOffset, pair.0.compressedSize)
			guard firstDataEnd <= pair.1.localHeaderOffset else {
				throw ArchiveError.invalidArchive("Archive entries have overlapping data ranges.")
			}
		}
	}

	static func consumeOptionalCentralRecords(
		file: ZIPFile,
		trailerOffset: UInt64,
		centralDirectoryOffset: UInt64,
		limits: ArchiveLimits,
		deadline: ArchiveDeadline,
	) throws {
		var sawArchiveExtraData = false
		var sawDigitalSignature = false
		while file.offset < trailerOffset {
			try deadline.check()
			let signature = try file.readExactly(count: 4).uint32(at: 0)
			switch signature {
			case 0x0806_4B50:
				guard !sawArchiveExtraData else {
					throw ArchiveError.invalidArchive("Duplicate archive extra-data record.")
				}
				sawArchiveExtraData = true
				let length = try file.readExactly(count: 4).uint32(at: 0)
				let recordEnd = try addingWithoutOverflow(file.offset, UInt64(length))
				guard recordEnd <= trailerOffset,
				      recordEnd - centralDirectoryOffset <= limits.maximumCentralDirectorySize
				else {
					throw ArchiveError.invalidArchive("Central directory exceeds its size limit.")
				}
				_ = try file.readExactly(count: Int(length))
			case 0x0505_4B50:
				guard !sawDigitalSignature else {
					throw ArchiveError.invalidArchive("Duplicate central-directory digital signature.")
				}
				sawDigitalSignature = true
				let length = try file.readExactly(count: 2).uint16(at: 0)
				let recordEnd = try addingWithoutOverflow(file.offset, UInt64(length))
				guard recordEnd <= trailerOffset,
				      recordEnd - centralDirectoryOffset <= limits.maximumCentralDirectorySize
				else {
					throw ArchiveError.invalidArchive("Central directory exceeds its size limit.")
				}
				_ = try file.readExactly(count: Int(length))
			default:
				throw ArchiveError.invalidArchive("Unexpected data after central-directory entries.")
			}
			guard file.offset <= trailerOffset,
			      file.offset - centralDirectoryOffset <= limits.maximumCentralDirectorySize
			else {
				throw ArchiveError.invalidArchive("Central directory exceeds its size limit.")
			}
		}
	}

	static func decodeName(_ data: Data, flags: UInt16, extraData: Data) throws -> String {
		if flags & 0x0800 != 0, let name = String(data: data, encoding: .utf8) {
			return name
		}
		if let unicodeName = unicodePath(from: extraData, originalName: data) {
			return unicodeName
		}
		if let name = String(data: data, encoding: .isoLatin1) {
			return name
		}
		throw ArchiveError.invalidArchive("An archive entry has an invalid filename.")
	}

	static func unicodePath(from extraData: Data, originalName: Data) -> String? {
		var offset = 0
		while offset + 4 <= extraData.count {
			let identifier = extraData.uint16(at: offset)
			let size = Int(extraData.uint16(at: offset + 2))
			offset += 4
			guard offset + size <= extraData.count else { return nil }
			defer { offset += size }
			guard identifier == 0x7075, size >= 5 else { continue }
			let payload = Data(extraData[offset ..< offset + size])
			guard payload[0] == 1, payload.uint32(at: 1) == zipCRC32(0, originalName) else { continue }
			return String(data: payload.dropFirst(5), encoding: .utf8)
		}
		return nil
	}

	static func parseZIP64Extra(
		_ extraData: Data,
		uncompressed32: UInt32,
		compressed32: UInt32,
		localOffset32: UInt32,
		diskStart: UInt16,
	) throws -> (
		uncompressedSize: UInt64?,
		compressedSize: UInt64?,
		localHeaderOffset: UInt64?,
		diskStart: UInt32?,
	) {
		var field: Data?
		var offset = 0
		while offset + 4 <= extraData.count {
			let identifier = extraData.uint16(at: offset)
			let size = Int(extraData.uint16(at: offset + 2))
			offset += 4
			guard offset + size <= extraData.count else {
				throw ArchiveError.invalidArchive("Malformed ZIP extra field.")
			}
			if identifier == 0x0001 {
				guard field == nil else {
					throw ArchiveError.invalidArchive("Duplicate ZIP64 extra field.")
				}
				field = Data(extraData[offset ..< offset + size])
			}
			offset += size
		}
		guard offset == extraData.count else {
			throw ArchiveError.invalidArchive("Malformed ZIP extra field trailer.")
		}

		if let field, field.count == 24, diskStart != UInt16.max {
			let redundantUncompressed = field.uint64(at: 0)
			let redundantCompressed = field.uint64(at: 8)
			let redundantOffset = field.uint64(at: 16)
			return (
				uncompressed32 == UInt32.max ? redundantUncompressed : UInt64(uncompressed32),
				compressed32 == UInt32.max ? redundantCompressed : UInt64(compressed32),
				localOffset32 == UInt32.max ? redundantOffset : UInt64(localOffset32),
				nil,
			)
		}

		var reader = ZIPDataCursor(data: field ?? Data())
		let uncompressed = try reader.readUInt64(if: uncompressed32 == UInt32.max)
		let compressed = try reader.readUInt64(if: compressed32 == UInt32.max)
		let localOffset = try reader.readUInt64(if: localOffset32 == UInt32.max)
		let zip64DiskStart = try reader.readUInt32(if: diskStart == UInt16.max)

		// ProPresenter intentionally includes a redundant local-header offset after
		// the two required ZIP64 sizes. The ordinary field remains authoritative.
		if localOffset32 != UInt32.max, reader.remaining >= 8 {
			_ = try reader.readUInt64()
		}
		return (uncompressed, compressed, localOffset, zip64DiskStart)
	}

	static func entryKind(
		rawName: String,
		versionMadeBy: UInt16,
		externalAttributes: UInt32,
	) throws -> ZIPEntry.Kind {
		let hostSystem = UInt8(versionMadeBy >> 8)
		let unixMode = UInt16(externalAttributes >> 16)
		let fileType = unixMode & 0o170000
		if fileType != 0 {
			switch fileType {
			case 0o100000:
				if hostSystem == 3 {
					return .file
				}
			case 0o040000:
				if hostSystem == 3 {
					return .directory
				}
			case 0o120000, 0o010000, 0o020000, 0o060000, 0o140000:
				throw ArchiveError.unsupportedEntryType(entry: rawName)
			default:
				if hostSystem == 3 {
					throw ArchiveError.unsupportedEntryType(entry: rawName)
				}
			}
		}
		if rawName.hasSuffix("/") || externalAttributes & 0x10 != 0 {
			return .directory
		}
		return .file
	}

	static func safeDestinationPath(
		_ rawName: String,
		kind: ZIPEntry.Kind,
		limits: ArchiveLimits,
	) throws -> String {
		guard !rawName.isEmpty,
		      rawName.utf8.count <= limits.maximumPathLength,
		      !rawName.hasPrefix("//"),
		      !rawName.contains("\\"),
		      !rawName.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
		else {
			throw ArchiveError.invalidEntry(rawName)
		}
		var path = rawName
		while path.hasPrefix("/") {
			path.removeFirst()
		}
		while path.hasPrefix("./") {
			path.removeFirst(2)
		}
		if case .directory = kind {
			while path.hasSuffix("/") {
				path.removeLast()
			}
		}
		let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		guard !components.isEmpty,
		      components.count <= limits.maximumPathDepth,
		      components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
		      components.allSatisfy({ $0.utf8.count <= limits.maximumPathComponentLength }),
		      components.first?.range(of: "^[A-Za-z]:", options: .regularExpression) == nil
		else {
			throw ArchiveError.invalidEntry(rawName)
		}
		return components.joined(separator: "/")
	}

	static func validateDestination(
		_ path: String,
		kind: ZIPEntry.Kind,
		seenDestinations: inout Set<String>,
		seenFiles: inout Set<String>,
		requiredDirectories: inout Set<String>,
	) throws {
		let components = path.split(separator: "/").map(String.init)
		let key = collisionKey(path)
		guard seenDestinations.insert(key).inserted else {
			throw ArchiveError.duplicateDestination(path)
		}
		var parents: [String] = []
		for component in components.dropLast() {
			parents.append(component)
			let parentKey = collisionKey(parents.joined(separator: "/"))
			guard !seenFiles.contains(parentKey) else {
				throw ArchiveError.duplicateDestination(path)
			}
			requiredDirectories.insert(parentKey)
		}
		switch kind {
		case .file:
			guard !requiredDirectories.contains(key) else {
				throw ArchiveError.duplicateDestination(path)
			}
			seenFiles.insert(key)
		case .directory:
			requiredDirectories.insert(key)
		}
	}

	static func collisionKey(_ path: String) -> String {
		path.precomposedStringWithCanonicalMapping.lowercased()
	}

	static func unsafeRatio(uncompressed: UInt64, compressed: UInt64, limit: UInt64) -> Bool {
		guard uncompressed > 0 else { return false }
		guard compressed > 0 else { return true }
		let (threshold, overflow) = compressed.multipliedReportingOverflow(by: limit)
		return overflow ? false : uncompressed > threshold
	}

	static func addingWithoutOverflow(_ left: UInt64, _ right: UInt64) throws -> UInt64 {
		let (result, overflow) = left.addingReportingOverflow(right)
		guard !overflow else {
			throw ArchiveError.invalidArchive("An archive size overflows 64-bit arithmetic.")
		}
		return result
	}
}

struct ArchiveDeadline: Sendable {
	private let instant: ContinuousClock.Instant

	init(timeout: Duration) {
		instant = .now.advanced(by: timeout)
	}

	func check() throws {
		guard ContinuousClock.now < instant else {
			throw ArchiveError.processingTimedOut
		}
	}
}

final class ZIPFile {
	private let handle: FileHandle
	let size: UInt64
	private(set) var offset: UInt64 = 0

	init(url: URL, forWriting: Bool) throws {
		if forWriting {
			handle = try FileHandle(forWritingTo: url)
			size = try handle.seekToEnd()
			try handle.seek(toOffset: 0)
		} else {
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
			guard information.st_mode & S_IFMT == S_IFREG, information.st_size >= 0 else {
				Darwin.close(descriptor)
				throw ArchiveError.unsupportedEntryType(entry: url.path)
			}
			handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
			size = UInt64(information.st_size)
		}
	}

	func seek(to offset: UInt64) throws {
		try handle.seek(toOffset: offset)
		self.offset = offset
	}

	func readExactly(count: Int) throws -> Data {
		guard count >= 0 else {
			throw ArchiveError.invalidArchive("Invalid negative read length.")
		}
		var data = Data()
		data.reserveCapacity(count)
		while data.count < count {
			let chunk = try handle.read(upToCount: count - data.count) ?? Data()
			guard !chunk.isEmpty else {
				throw ArchiveError.invalidArchive("Unexpected end of ZIP archive.")
			}
			data.append(chunk)
		}
		offset += UInt64(data.count)
		return data
	}

	func close() {
		try? handle.close()
	}
}

private struct ZIPDataCursor {
	let data: Data
	private(set) var offset = 0

	var remaining: Int {
		data.count - offset
	}

	mutating func readUInt64(if condition: Bool) throws -> UInt64? {
		condition ? try readUInt64() : nil
	}

	mutating func readUInt32(if condition: Bool) throws -> UInt32? {
		condition ? try readUInt32() : nil
	}

	mutating func readUInt64() throws -> UInt64 {
		guard remaining >= 8 else {
			throw ArchiveError.invalidArchive("ZIP64 extra field is missing a required value.")
		}
		defer { offset += 8 }
		return data.uint64(at: offset)
	}

	mutating func readUInt32() throws -> UInt32 {
		guard remaining >= 4 else {
			throw ArchiveError.invalidArchive("ZIP64 extra field is missing a required value.")
		}
		defer { offset += 4 }
		return data.uint32(at: offset)
	}
}

func zipCRC32(_ checksum: UInt32, _ data: some DataProtocol) -> UInt32 {
	let contiguous = Data(data)
	return contiguous.withUnsafeBytes { bytes in
		guard let address = bytes.bindMemory(to: Bytef.self).baseAddress else { return checksum }
		return UInt32(zlib.crc32(uLong(checksum), address, uInt(bytes.count)))
	}
}

extension Data {
	func uint16(at offset: Int) -> UInt16 {
		UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
	}

	func uint32(at offset: Int) -> UInt32 {
		UInt32(self[offset])
			| UInt32(self[offset + 1]) << 8
			| UInt32(self[offset + 2]) << 16
			| UInt32(self[offset + 3]) << 24
	}

	func uint64(at offset: Int) -> UInt64 {
		UInt64(uint32(at: offset)) | UInt64(uint32(at: offset + 4)) << 32
	}
}
