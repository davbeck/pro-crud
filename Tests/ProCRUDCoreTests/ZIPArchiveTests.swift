import CustomDump
import Foundation
import ProPresenterProto
import Testing
@testable import ProCRUDCore

@Suite(
	"Native ZIP archive",
	.timeLimit(.minutes(1)),
)
struct ZIPArchiveTests {
	@Test
	func rejectsEntryCountBeforeCreatingDestination() throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: (0 ..< 20000).map { index in
				FixtureEntry(name: "entry-\(index).txt", data: Data())
			})
			let archiveURL = try write(fixture, named: "too-many.zip", in: directory)
			let destination = directory.appendingPathComponent("expanded", isDirectory: true)

			let error = caughtArchiveError {
				try ZIPArchive.extract(archiveURL, to: destination)
			}

			expectNoDifference(
				error,
				Optional(ArchiveError.entryCountLimitExceeded(count: 20000, limit: 10000)),
			)
			#expect(!FileManager.default.fileExists(atPath: destination.path))
		}
	}

	@Test
	func timeoutStopsProcessingBeforeCreatingDestination() throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: [
				FixtureEntry(name: "entry.txt", data: Data("entry".utf8)),
			])
			let archiveURL = try write(fixture, named: "timeout.zip", in: directory)
			let destination = directory.appendingPathComponent("expanded", isDirectory: true)
			var limits = ArchiveLimits.default
			limits.processingTimeout = .zero

			expectNoDifference(
				caughtArchiveError {
					try ZIPArchive.extract(archiveURL, to: destination, limits: limits)
				},
				Optional(ArchiveError.processingTimedOut),
			)
			#expect(!FileManager.default.fileExists(atPath: destination.path))
		}
	}

	@Test
	func rejectsIndividualAndAggregateExpandedSizeLimits() throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: [
				FixtureEntry(name: "one.bin", data: Data(repeating: 1, count: 5)),
				FixtureEntry(name: "two.bin", data: Data(repeating: 2, count: 5)),
			])
			let archiveURL = try write(fixture, named: "sizes.zip", in: directory)

			var entryLimits = ArchiveLimits.default
			entryLimits.maximumEntrySize = 4
			expectNoDifference(
				caughtArchiveError {
					try ZIPArchive.extract(
						archiveURL,
						to: directory.appendingPathComponent("entry-expanded"),
						limits: entryLimits,
					)
				},
				Optional(ArchiveError.entrySizeLimitExceeded(entry: "one.bin", size: 5, limit: 4)),
			)

			var aggregateLimits = ArchiveLimits.default
			aggregateLimits.maximumExpandedSize = 9
			expectNoDifference(
				caughtArchiveError {
					try ZIPArchive.extract(
						archiveURL,
						to: directory.appendingPathComponent("aggregate-expanded"),
						limits: aggregateLimits,
					)
				},
				Optional(ArchiveError.expandedSizeLimitExceeded(size: 10, limit: 9)),
			)
			#expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("entry-expanded").path))
			#expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("aggregate-expanded").path))
		}
	}

	@Test
	func rejectsACompressionRatioBombDuringPreflight() throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: [
				FixtureEntry(
					name: "bomb.bin",
					data: Data([0]),
					compressionMethod: 8,
					uncompressedSize: 1_048_576,
				),
			])
			let archiveURL = try write(fixture, named: "ratio.zip", in: directory)
			let destination = directory.appendingPathComponent("expanded")

			expectNoDifference(
				caughtArchiveError {
					try ZIPArchive.extract(archiveURL, to: destination)
				},
				Optional(ArchiveError.compressionRatioLimitExceeded(entry: "bomb.bin")),
			)
			#expect(!FileManager.default.fileExists(atPath: destination.path))
		}
	}

	@Test
	func rejectsTraversalButNormalizesProPresenterAbsoluteNames() throws {
		try withZIPTemporaryDirectory { directory in
			let traversal = makeStoredZIP(entries: [
				FixtureEntry(name: "../escape.txt", data: Data("escape".utf8)),
			])
			let traversalURL = try write(traversal, named: "traversal.zip", in: directory)
			let rejectedDestination = directory.appendingPathComponent("rejected", isDirectory: true)

			expectNoDifference(
				caughtArchiveError {
					try ZIPArchive.extract(traversalURL, to: rejectedDestination)
				},
				Optional(ArchiveError.invalidEntry("../escape.txt")),
			)
			#expect(!FileManager.default.fileExists(atPath: rejectedDestination.path))
			#expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("escape.txt").path))

			let absoluteName = "/Users/example/Media/asset.txt"
			let contents = Data("portable asset".utf8)
			let absolute = makeStoredZIP(entries: [
				FixtureEntry(name: absoluteName, data: contents),
			])
			let absoluteURL = try write(absolute, named: "absolute.zip", in: directory)
			let expanded = directory.appendingPathComponent("absolute-expanded", isDirectory: true)

			try expectNoDifference(ZIPArchive.entries(in: absoluteURL), [absoluteName])
			try ZIPArchive.extract(absoluteURL, to: expanded)
			#expect(
				try Data(contentsOf: expanded.appendingPathComponent("Users/example/Media/asset.txt")) == contents,
			)
		}
	}

	@Test
	func rejectsEntriesThatNormalizeToTheSameDestination() throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: [
				FixtureEntry(name: "/assets/shared.png", data: Data([1])),
				FixtureEntry(name: "assets/shared.png", data: Data([2])),
			])
			let archiveURL = try write(fixture, named: "collision.zip", in: directory)
			let destination = directory.appendingPathComponent("expanded", isDirectory: true)

			expectNoDifference(
				caughtArchiveError {
					try ZIPArchive.extract(archiveURL, to: destination)
				},
				Optional(ArchiveError.duplicateDestination("assets/shared.png")),
			)
			#expect(!FileManager.default.fileExists(atPath: destination.path))

			let prefixFixture = makeStoredZIP(entries: [
				FixtureEntry(name: "assets", data: Data([1])),
				FixtureEntry(name: "assets/file.png", data: Data([2])),
			])
			let prefixURL = try write(prefixFixture, named: "prefix-collision.zip", in: directory)
			expectNoDifference(
				caughtArchiveError {
					_ = try ZIPArchive.entries(in: prefixURL)
				},
				Optional(ArchiveError.duplicateDestination("assets/file.png")),
			)
		}
	}

	@Test(arguments: [UInt16(0o120777), UInt16(0o010600)])
	func rejectsSymlinksAndSpecialUnixEntries(unixMode: UInt16) throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: [
				FixtureEntry(
					name: "unsafe-entry",
					data: Data("target".utf8),
					unixMode: unixMode,
				),
			])
			let archiveURL = try write(fixture, named: "special-\(unixMode).zip", in: directory)
			let destination = directory.appendingPathComponent("expanded", isDirectory: true)

			expectNoDifference(
				caughtArchiveError {
					try ZIPArchive.extract(archiveURL, to: destination)
				},
				Optional(ArchiveError.unsupportedEntryType(entry: "unsafe-entry")),
			)
			#expect(!FileManager.default.fileExists(atPath: destination.path))
		}
	}

	@Test
	func writerRejectsSourceSymlinksWithoutCreatingAnArchive() throws {
		try withZIPTemporaryDirectory { directory in
			let source = directory.appendingPathComponent("source", isDirectory: true)
			try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
			let external = directory.appendingPathComponent("external.txt")
			try Data("secret".utf8).write(to: external)
			let link = source.appendingPathComponent("linked.txt")
			try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
			let archiveURL = directory.appendingPathComponent("rejected.zip")

			let error = caughtArchiveError {
				try ZIPArchive.create(from: source, entries: ["linked.txt"], to: archiveURL)
			}

			expectNoDifference(
				error,
				Optional(ArchiveError.unsupportedEntryType(entry: link.path)),
			)
			#expect(!FileManager.default.fileExists(atPath: archiveURL.path))
		}
	}

	@Test
	func readerRejectsAnArchiveSymlink() throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: [
				FixtureEntry(name: "payload.txt", data: Data("payload".utf8)),
			])
			let archiveURL = try write(fixture, named: "source.zip", in: directory)
			let symlinkURL = directory.appendingPathComponent("linked.zip")
			try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: archiveURL)

			expectNoDifference(
				caughtArchiveError {
					_ = try ZIPArchive.entries(in: symlinkURL)
				},
				Optional(ArchiveError.unsupportedEntryType(entry: symlinkURL.path)),
			)
		}
	}

	@Test
	func writerDoesNotReplaceAnExistingArchiveWithoutPermission() throws {
		try withZIPTemporaryDirectory { directory in
			let source = directory.appendingPathComponent("source", isDirectory: true)
			try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
			try Data("payload".utf8).write(to: source.appendingPathComponent("payload.txt"))
			let archiveURL = directory.appendingPathComponent("existing.zip")
			let original = Data("existing output".utf8)
			try original.write(to: archiveURL)

			do {
				try ZIPArchive.create(
					from: source,
					entries: ["payload.txt"],
					to: archiveURL,
					replaceExisting: false,
				)
				Issue.record("Expected archive creation to preserve the existing output")
			} catch let DocumentArchiveError.outputExists(url) {
				expectNoDifference(url, archiveURL)
			} catch {
				Issue.record("Expected outputExists, got \(error)")
			}
			#expect(try Data(contentsOf: archiveURL) == original)
			#expect(
				try directoryContents(directory).filter { $0.contains("-write-") }.isEmpty,
			)
		}
	}

	@Test
	func rejectsCRCMismatchAndRemovesTransactionalOutput() throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: [
				FixtureEntry(
					name: "bad.txt",
					data: Data("contents".utf8),
					checksum: 0xDEAD_BEEF,
				),
			])
			let archiveURL = try write(fixture, named: "bad-crc.zip", in: directory)
			let destination = directory.appendingPathComponent("expanded", isDirectory: true)
			let contentsBefore = try directoryContents(directory)

			expectNoDifference(
				caughtArchiveError {
					try ZIPArchive.extract(archiveURL, to: destination)
				},
				Optional(ArchiveError.integrityCheckFailed("bad.txt")),
			)
			#expect(!FileManager.default.fileExists(atPath: destination.path))
			try expectNoDifference(directoryContents(directory), contentsBefore)
		}
	}

	@Test
	func rejectsUnsupportedCompressionBeforeCreatingOutput() throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: [
				FixtureEntry(
					name: "future.bin",
					data: Data([1, 2, 3]),
					compressionMethod: 99,
				),
			])
			let archiveURL = try write(fixture, named: "unsupported.zip", in: directory)
			let destination = directory.appendingPathComponent("expanded", isDirectory: true)
			let contentsBefore = try directoryContents(directory)

			expectNoDifference(
				caughtArchiveError {
					try ZIPArchive.extract(archiveURL, to: destination)
				},
				Optional(ArchiveError.unsupportedCompressionMethod(entry: "future.bin", method: 99)),
			)
			#expect(!FileManager.default.fileExists(atPath: destination.path))
			try expectNoDifference(directoryContents(directory), contentsBefore)
		}
	}

	@Test
	func acceptsOnlyTheExactProPresenterCentralDirectoryOvercount() throws {
		try withZIPTemporaryDirectory { directory in
			let contents = Data("payload".utf8)
			let accepted = makeStoredZIP(
				entries: [FixtureEntry(name: "payload.pro", data: contents)],
				zip64EndRecords: true,
				declaredCentralDirectoryOvercount: 98,
				digitalSignature: Data([1, 2, 3]),
			)
			let acceptedURL = try write(accepted, named: "overcount-98.zip", in: directory)
			let expanded = directory.appendingPathComponent("accepted", isDirectory: true)

			try expectNoDifference(ZIPArchive.entries(in: acceptedURL), ["payload.pro"])
			try ZIPArchive.extract(acceptedURL, to: expanded)
			#expect(try Data(contentsOf: expanded.appendingPathComponent("payload.pro")) == contents)

			for overcount in [97, 99] {
				let rejected = makeStoredZIP(
					entries: [FixtureEntry(name: "payload.pro", data: contents)],
					zip64EndRecords: true,
					declaredCentralDirectoryOvercount: overcount,
				)
				let rejectedURL = try write(rejected, named: "overcount-\(overcount).zip", in: directory)
				let declaredSize = rejected.centralDirectorySize + UInt64(overcount)
				expectNoDifference(
					caughtArchiveError {
						_ = try ZIPArchive.entries(in: rejectedURL)
					},
					Optional(ArchiveError.invalidArchive(
						"Central directory size is \(declaredSize) bytes, but parsed records occupy \(rejected.centralDirectorySize) bytes.",
					)),
				)
			}
		}
	}

	@Test
	func rejectsOverflowingZIP64OffsetsWithoutTrapping() throws {
		try withZIPTemporaryDirectory { directory in
			var fixture = makeStoredZIP(
				entries: [FixtureEntry(name: "payload.pro", data: Data("payload".utf8))],
				zip64EndRecords: true,
			)
			let locatorOffset = fixture.data.count - 22 - 20
			fixture.data.replaceUInt64LE(UInt64.max, at: locatorOffset + 8)
			let archiveURL = try write(fixture, named: "overflow.zip", in: directory)

			expectNoDifference(
				caughtArchiveError {
					_ = try ZIPArchive.entries(in: archiveURL)
				},
				Optional(ArchiveError.invalidArchive(
					"An archive size overflows 64-bit arithmetic.",
				)),
			)
		}
	}

	@Test
	func acceptsAnUnlimitedCentralDirectoryLimit() throws {
		try withZIPTemporaryDirectory { directory in
			let fixture = makeStoredZIP(entries: [
				FixtureEntry(name: "payload.pro", data: Data("payload".utf8)),
			])
			let archiveURL = try write(fixture, named: "unlimited.zip", in: directory)
			var limits = ArchiveLimits.default
			limits.maximumCentralDirectorySize = UInt64.max

			try expectNoDifference(
				ZIPArchive.entries(in: archiveURL, limits: limits),
				["payload.pro"],
			)
		}
	}

	@Test
	func extractsARealProPresenterZIP64Export() throws {
		try withZIPTemporaryDirectory { directory in
			let archiveURL = fixtureURL("ProPresenter/ReferenceSlides.proPlaylist")
			let entries = try ZIPArchive.entries(in: archiveURL)
			expectNoDifference(entries.count, 13)

			let destination = directory.appendingPathComponent("expanded", isDirectory: true)
			try ZIPArchive.extract(archiveURL, to: destination)
			let regularFiles = try DocumentLoader.recursiveFiles(in: destination)
			expectNoDifference(regularFiles.count, 13)
		}
	}

	@Test
	func loadedDocumentOwnsAndRemovesItsExtractionDirectory() throws {
		var document: ProPresenterDocument? = try DocumentLoader.load(
			from: fixtureURL("ProPresenter/ReferenceSlides.proPlaylist"),
		)
		let resourceDirectory = try #require(document?.resourceDirectory)
		#expect(FileManager.default.fileExists(atPath: resourceDirectory.path))

		document = nil

		#expect(!FileManager.default.fileExists(atPath: resourceDirectory.path))
	}

	@Test
	func loadedPresentationsRetainTheirArchiveMediaDirectory() throws {
		var presentations: [LoadedPresentationDocument]? = try PresentationLoader.loadPresentations(
			from: fixtureURL("ProPresenter/ReferenceSlides.proPlaylist"),
		)
		let resourceDirectory = try #require(presentations?.first?.document.mediaDirectory)
		#expect(FileManager.default.fileExists(atPath: resourceDirectory.path))

		presentations = nil

		#expect(!FileManager.default.fileExists(atPath: resourceDirectory.path))
	}

	@Test
	func resolvedTemplateDocumentRetainsSourceAndThemeArchiveDirectories() throws {
		try withZIPTemporaryDirectory { directory in
			let sourceURL = directory.appendingPathComponent("Source.pro")
			try DocumentWriter.writeRaw(
				ProPresenterDocument(
					payload: .presentation(DocumentFactory.presentation(name: "Source")),
					origin: .raw(sourceURL),
				),
				to: sourceURL,
			)
			let sourceArchive = try DocumentArchive.bundle(
				sourceURL,
				to: directory.appendingPathComponent("Source.probundle"),
			)

			let themeDirectory = directory.appendingPathComponent("Archived Theme", isDirectory: true)
			try FileManager.default.createDirectory(at: themeDirectory, withIntermediateDirectories: true)
			try Data([0x01, 0x02, 0x03]).write(to: themeDirectory.appendingPathComponent("theme.bin"))
			var theme = DocumentFactory.theme()
			DocumentEditor.addTemplate(to: &theme, name: "Archived")
			var element = Rv_Data_Slide.Element()
			element.element.uuid.string = "ARCHIVED-THEME-ELEMENT"
			element.element.fill.enable = true
			element.element.fill.media.uuid.string = "ARCHIVED-THEME-MEDIA"
			element.element.fill.media.url.relativePath = "theme.bin"
			theme.slides[0].baseSlide.elements = [element]
			let themeURL = themeDirectory.appendingPathComponent("Theme")
			try DocumentWriter.writeRaw(
				ProPresenterDocument(payload: .theme(theme), origin: .raw(themeURL)),
				to: themeURL,
			)
			let themeArchive = try DocumentArchive.bundle(
				themeDirectory,
				to: directory.appendingPathComponent("Archived Theme.proTheme"),
			)

			var source: PresentationDocument? = try PresentationLoader.load(from: sourceArchive)
			let sourceDirectory = try #require(source?.mediaDirectory)
			var candidate: ThemeTemplateSource.Candidate? = try ThemeTemplateSource.select(
				ThemeTemplateSource.candidates(from: themeArchive),
				named: "Archived",
			)
			let themeResourceDirectory = try #require(candidate?.resourceDirectory)
			var resolved: PresentationDocument? = try PresentationTemplateResolver.resolve(
				document: #require(source),
				template: #require(candidate),
			).document
			#expect(resolved != nil)

			source = nil
			candidate = nil
			#expect(FileManager.default.fileExists(atPath: sourceDirectory.path))
			#expect(FileManager.default.fileExists(atPath: themeResourceDirectory.path))

			resolved = nil
			#expect(!FileManager.default.fileExists(atPath: sourceDirectory.path))
			#expect(!FileManager.default.fileExists(atPath: themeResourceDirectory.path))
		}
	}

	@Test
	func writerUsesRelativeStoredZIP64EntriesWithACorrectDirectorySize() throws {
		try withZIPTemporaryDirectory { directory in
			let source = directory.appendingPathComponent("source", isDirectory: true)
			let nested = source.appendingPathComponent("nested", isDirectory: true)
			try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
			let firstContents = Data("first".utf8)
			let secondContents = Data([0, 1, 2, 3, 4])
			try firstContents.write(to: source.appendingPathComponent("first.txt"))
			try secondContents.write(to: nested.appendingPathComponent("second.bin"))
			let names = ["first.txt", "nested/second.bin"]
			let archiveURL = directory.appendingPathComponent("created.zip")

			try ZIPArchive.create(from: source, entries: names, to: archiveURL)

			try expectNoDifference(ZIPArchive.entries(in: archiveURL), names)
			let archive = try Data(contentsOf: archiveURL)
			let classicOffset = archive.count - 22
			#expect(archive.readUInt32LE(at: classicOffset) == 0x0605_4B50)
			let locatorOffset = classicOffset - 20
			#expect(archive.readUInt32LE(at: locatorOffset) == 0x0706_4B50)
			let zip64Offset = try #require(Int(exactly: archive.readUInt64LE(at: locatorOffset + 8)))
			#expect(archive.readUInt32LE(at: zip64Offset) == 0x0606_4B50)
			let centralDirectorySize = try #require(Int(exactly: archive.readUInt64LE(at: zip64Offset + 40)))
			let centralDirectoryOffset = try #require(Int(exactly: archive.readUInt64LE(at: zip64Offset + 48)))
			#expect(centralDirectoryOffset + centralDirectorySize == zip64Offset)
			#expect(Int(archive.readUInt32LE(at: classicOffset + 12)) == centralDirectorySize)

			#expect(archive.readUInt32LE(at: 0) == 0x0403_4B50)
			#expect(archive.readUInt16LE(at: 4) == 45)
			#expect(archive.readUInt16LE(at: 8) == 0)
			#expect(archive.readUInt32LE(at: 18) == UInt32.max)
			#expect(archive.readUInt32LE(at: 22) == UInt32.max)
			let localNameLength = Int(archive.readUInt16LE(at: 26))
			let localExtraOffset = 30 + localNameLength
			#expect(archive.readUInt16LE(at: localExtraOffset) == 0x0001)
			#expect(archive.readUInt16LE(at: localExtraOffset + 2) == 16)

			#expect(archive.readUInt32LE(at: centralDirectoryOffset) == 0x0201_4B50)
			#expect(archive.readUInt16LE(at: centralDirectoryOffset + 6) == 45)
			#expect(archive.readUInt16LE(at: centralDirectoryOffset + 10) == 0)
			#expect(archive.readUInt32LE(at: centralDirectoryOffset + 20) == UInt32.max)
			#expect(archive.readUInt32LE(at: centralDirectoryOffset + 24) == UInt32.max)
			let centralNameLength = Int(archive.readUInt16LE(at: centralDirectoryOffset + 28))
			let centralExtraOffset = centralDirectoryOffset + 46 + centralNameLength
			#expect(archive.readUInt16LE(at: centralExtraOffset) == 0x0001)
			#expect(archive.readUInt16LE(at: centralExtraOffset + 2) == 16)

			let expanded = directory.appendingPathComponent("round-trip", isDirectory: true)
			try ZIPArchive.extract(archiveURL, to: expanded)
			#expect(try Data(contentsOf: expanded.appendingPathComponent(names[0])) == firstContents)
			#expect(try Data(contentsOf: expanded.appendingPathComponent(names[1])) == secondContents)
			let rootPermissions = try FileManager.default.attributesOfItem(atPath: expanded.path)[.posixPermissions]
			let filePermissions = try FileManager.default.attributesOfItem(
				atPath: expanded.appendingPathComponent(names[1]).path,
			)[.posixPermissions]
			expectNoDifference(rootPermissions as? NSNumber, NSNumber(value: 0o700))
			expectNoDifference(filePermissions as? NSNumber, NSNumber(value: 0o600))
		}
	}

	@Test
	func updaterCopiesUntouchedCompressedStreamsWithoutRecompression() throws {
		try withZIPTemporaryDirectory { directory in
			let sourceURL = fixtureURL("ProPresenter/ReferenceSlides.proPlaylist")
			let archiveURL = directory.appendingPathComponent("edited.proPlaylist")
			try FileManager.default.copyItem(at: sourceURL, to: archiveURL)
			let workspace = directory.appendingPathComponent("workspace", isDirectory: true)
			try ZIPArchive.extract(archiveURL, to: workspace)

			let beforeReader = try ZIPReader(archiveURL: archiveURL, limits: .default)
			let beforeData = try Data(contentsOf: archiveURL)
			let beforeStreams = try Dictionary(uniqueKeysWithValues: beforeReader.entries
				.filter { $0.rawName != "data" }
				.map { entry in
					try (entry.rawName, compressedBytes(for: entry, in: beforeData))
				})
			let replacement = Data("edited playlist payload".utf8)
			try replacement.write(to: workspace.appendingPathComponent("data"))

			try ZIPArchive.update(from: workspace, entries: ["data"], in: archiveURL)

			let afterReader = try ZIPReader(archiveURL: archiveURL, limits: .default)
			let afterData = try Data(contentsOf: archiveURL)
			for entry in afterReader.entries where entry.rawName != "data" {
				let beforeStream = try #require(beforeStreams[entry.rawName])
				try expectNoDifference(
					compressedBytes(for: entry, in: afterData),
					beforeStream,
				)
			}
			let expanded = directory.appendingPathComponent("updated", isDirectory: true)
			try ZIPArchive.extract(archiveURL, to: expanded)
			#expect(try Data(contentsOf: expanded.appendingPathComponent("data")) == replacement)
		}
	}
}

private struct FixtureEntry {
	var name: String
	var data: Data
	var compressionMethod: UInt16
	var versionMadeBy: UInt16
	var externalAttributes: UInt32
	var checksum: UInt32?
	var uncompressedSize: UInt32?

	init(
		name: String,
		data: Data,
		compressionMethod: UInt16 = 0,
		unixMode: UInt16 = 0o100600,
		checksum: UInt32? = nil,
		uncompressedSize: UInt32? = nil,
	) {
		self.name = name
		self.data = data
		self.compressionMethod = compressionMethod
		versionMadeBy = 0x031E
		externalAttributes = UInt32(unixMode) << 16
		self.checksum = checksum
		self.uncompressedSize = uncompressedSize
	}
}

private struct StoredZIPFixture {
	var data: Data
	var centralDirectoryOffset: UInt64
	var centralDirectorySize: UInt64
}

private struct StoredZIPRecord {
	var entry: FixtureEntry
	var name: Data
	var checksum: UInt32
	var localHeaderOffset: UInt32
}

private func makeStoredZIP(
	entries: [FixtureEntry],
	zip64EndRecords: Bool = false,
	declaredCentralDirectoryOvercount: Int = 0,
	digitalSignature: Data? = nil,
) -> StoredZIPFixture {
	precondition(entries.count <= Int(UInt16.max))
	var archive = Data()
	var records: [StoredZIPRecord] = []
	for entry in entries {
		let name = Data(entry.name.utf8)
		precondition(name.count <= Int(UInt16.max))
		precondition(entry.data.count <= Int(UInt32.max))
		let checksum = entry.checksum ?? zipCRC32(0, entry.data)
		let localHeaderOffset = UInt32(archive.count)
		archive.appendUInt32LE(0x0403_4B50)
		archive.appendUInt16LE(20)
		archive.appendUInt16LE(0x0800)
		archive.appendUInt16LE(entry.compressionMethod)
		archive.appendUInt16LE(0)
		archive.appendUInt16LE(0)
		archive.appendUInt32LE(checksum)
		archive.appendUInt32LE(UInt32(entry.data.count))
		archive.appendUInt32LE(entry.uncompressedSize ?? UInt32(entry.data.count))
		archive.appendUInt16LE(UInt16(name.count))
		archive.appendUInt16LE(0)
		archive.append(name)
		archive.append(entry.data)
		records.append(StoredZIPRecord(
			entry: entry,
			name: name,
			checksum: checksum,
			localHeaderOffset: localHeaderOffset,
		))
	}

	let centralDirectoryOffset = UInt64(archive.count)
	for record in records {
		archive.appendUInt32LE(0x0201_4B50)
		archive.appendUInt16LE(record.entry.versionMadeBy)
		archive.appendUInt16LE(20)
		archive.appendUInt16LE(0x0800)
		archive.appendUInt16LE(record.entry.compressionMethod)
		archive.appendUInt16LE(0)
		archive.appendUInt16LE(0)
		archive.appendUInt32LE(record.checksum)
		archive.appendUInt32LE(UInt32(record.entry.data.count))
		archive.appendUInt32LE(record.entry.uncompressedSize ?? UInt32(record.entry.data.count))
		archive.appendUInt16LE(UInt16(record.name.count))
		archive.appendUInt16LE(0)
		archive.appendUInt16LE(0)
		archive.appendUInt16LE(0)
		archive.appendUInt16LE(0)
		archive.appendUInt32LE(record.entry.externalAttributes)
		archive.appendUInt32LE(record.localHeaderOffset)
		archive.append(record.name)
	}
	if let digitalSignature {
		precondition(digitalSignature.count <= Int(UInt16.max))
		archive.appendUInt32LE(0x0505_4B50)
		archive.appendUInt16LE(UInt16(digitalSignature.count))
		archive.append(digitalSignature)
	}
	let centralDirectorySize = UInt64(archive.count) - centralDirectoryOffset
	let declaredSize = centralDirectorySize + UInt64(declaredCentralDirectoryOvercount)

	if zip64EndRecords {
		let zip64Offset = UInt64(archive.count)
		archive.appendUInt32LE(0x0606_4B50)
		archive.appendUInt64LE(44)
		archive.appendUInt16LE(0x032D)
		archive.appendUInt16LE(45)
		archive.appendUInt32LE(0)
		archive.appendUInt32LE(0)
		archive.appendUInt64LE(UInt64(entries.count))
		archive.appendUInt64LE(UInt64(entries.count))
		archive.appendUInt64LE(declaredSize)
		archive.appendUInt64LE(centralDirectoryOffset)
		archive.appendUInt32LE(0x0706_4B50)
		archive.appendUInt32LE(0)
		archive.appendUInt64LE(zip64Offset)
		archive.appendUInt32LE(1)
	}

	archive.appendUInt32LE(0x0605_4B50)
	archive.appendUInt16LE(0)
	archive.appendUInt16LE(0)
	archive.appendUInt16LE(UInt16(entries.count))
	archive.appendUInt16LE(UInt16(entries.count))
	archive.appendUInt32LE(UInt32(declaredSize))
	archive.appendUInt32LE(UInt32(centralDirectoryOffset))
	archive.appendUInt16LE(0)
	return StoredZIPFixture(
		data: archive,
		centralDirectoryOffset: centralDirectoryOffset,
		centralDirectorySize: centralDirectorySize,
	)
}

private func write(
	_ fixture: StoredZIPFixture,
	named name: String,
	in directory: URL,
) throws -> URL {
	let url = directory.appendingPathComponent(name)
	try fixture.data.write(to: url)
	return url
}

private func withZIPTemporaryDirectory(
	_ operation: (URL) throws -> Void,
) throws {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("ProCRUD-ZIPArchiveTests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: directory) }
	try operation(directory)
}

private func caughtArchiveError(
	_ operation: () throws -> Void,
) -> ArchiveError? {
	do {
		try operation()
		Issue.record("Expected archive operation to throw")
		return nil
	} catch let error as ArchiveError {
		return error
	} catch {
		Issue.record("Expected ArchiveError, got \(error)")
		return nil
	}
}

private func directoryContents(_ directory: URL) throws -> [String] {
	try FileManager.default.contentsOfDirectory(
		at: directory,
		includingPropertiesForKeys: nil,
	)
	.map(\.lastPathComponent)
	.sorted()
}

private func compressedBytes(for entry: ZIPEntry, in archive: Data) throws -> Data {
	let lowerBound = try #require(Int(exactly: entry.dataOffset))
	let size = try #require(Int(exactly: entry.compressedSize))
	return Data(archive[lowerBound ..< lowerBound + size])
}

private extension Data {
	mutating func appendUInt16LE(_ value: UInt16) {
		append(UInt8(truncatingIfNeeded: value))
		append(UInt8(truncatingIfNeeded: value >> 8))
	}

	mutating func appendUInt32LE(_ value: UInt32) {
		appendUInt16LE(UInt16(truncatingIfNeeded: value))
		appendUInt16LE(UInt16(truncatingIfNeeded: value >> 16))
	}

	mutating func appendUInt64LE(_ value: UInt64) {
		appendUInt32LE(UInt32(truncatingIfNeeded: value))
		appendUInt32LE(UInt32(truncatingIfNeeded: value >> 32))
	}

	mutating func replaceUInt64LE(_ value: UInt64, at offset: Int) {
		var replacement = Data()
		replacement.appendUInt64LE(value)
		replaceSubrange(offset ..< offset + 8, with: replacement)
	}

	func readUInt16LE(at offset: Int) -> UInt16 {
		UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
	}

	func readUInt32LE(at offset: Int) -> UInt32 {
		UInt32(self[offset])
			| UInt32(self[offset + 1]) << 8
			| UInt32(self[offset + 2]) << 16
			| UInt32(self[offset + 3]) << 24
	}

	func readUInt64LE(at offset: Int) -> UInt64 {
		UInt64(readUInt32LE(at: offset)) | UInt64(readUInt32LE(at: offset + 4)) << 32
	}
}
