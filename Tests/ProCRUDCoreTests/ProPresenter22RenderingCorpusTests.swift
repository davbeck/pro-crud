import AppKit
import CryptoKit
import Foundation
import ProPresenterProto
import SnapshotTesting
import Testing
@testable import ProCRUDCore

@Suite("Native 22 rendering corpus and Presentation collections")
struct ProPresenter22RenderingCorpusTests {
	private let counts = [1, 12, 8, 10, 6, 11, 15, 2, 6]

	@Test func retainedNativeImagesPayloadsAndStreamsMatchTheirExportHashes() throws {
		let provenance = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: corpus.appendingPathComponent("provenance.json")))
		#expect(provenance.build == "369098875")
		#expect(provenance.images.count == 71)
		#expect(provenance.payloads.count == 12)
		#expect(provenance.streams.count == 9)
		for entry in provenance.images + provenance.payloads {
			let data = try Data(contentsOf: corpus.appendingPathComponent(entry.path))
			#expect(hash(data) == entry.sha256)
			if entry.path.hasSuffix(".png"), entry.path.hasPrefix("Images/") {
				let image = try #require(NSBitmapImageRep(data: data))
				#expect(image.pixelsWide == 854 && image.pixelsHigh == 480)
			}
		}
		for entry in provenance.streams {
			#expect(try hash(Data(contentsOf: corpus.appendingPathComponent("Native/\(entry.name).loro"))) == entry.snapshotSHA256)
			#expect(try hash(Data(contentsOf: corpus.appendingPathComponent("Native/\(entry.name).vector"))) == entry.vectorSHA256)
		}
	}

	@Test func nineNativeStreamsMaterializeInMasterOrderAndRetainExportedIdentities() throws {
		let provenance = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: corpus.appendingPathComponent("provenance.json")))
		for (index, entry) in provenance.streams.enumerated() {
			let data = try Data(contentsOf: corpus.appendingPathComponent("Native/\(entry.name).loro"))
			let vector = try Data(contentsOf: corpus.appendingPathComponent("Native/\(entry.name).vector"))
			let stream = NativeWorkspaceStream(identity: .init(documentID: entry.documentID, scope: .shared, kind: "Presentation", corePath: "Default/\(entry.name)", availability: .available, byteCount: Int64(data.count), sha256: entry.snapshotSHA256, updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
			let view = try stream.protobufProjection().presentation()
			let native = try PresentationLoader.load(from: corpus.appendingPathComponent("Documents/\(entry.name).pro"))
			#expect(try stream.presentationLayout().orderedCueIDs().count == counts[index])
			#expect(native.orderedCues.count == counts[index])
			#expect(UUID(uuidString: view.uuid.string) == UUID(uuidString: native.presentation.uuid.string))
			#expect(view.cueGroups == native.presentation.cueGroups)
			#expect(Set(view.cues.flatMap(\.actions).map(\.uuid)) == Set(native.presentation.cues.flatMap(\.actions).map(\.uuid)))
		}
	}

	@Test func collectionLoadingRetainsAllNativePayloadsAndSharedMediaWithoutChoosingAnEditTarget() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let bundle = directory.appendingPathComponent("NativeCollection.probundle")
		let documents = corpus.appendingPathComponent("Documents")
		let entries = try DocumentLoader.recursiveFiles(in: documents).map { try DocumentLoader.relativePath(of: $0, in: documents) }
		try ZIPArchive.create(from: documents, entries: entries, to: bundle)
		var loaded = try PresentationLoader.loadPresentations(from: bundle)
		#expect(loaded.count == 9)
		#expect(loaded.map(\.document.orderedCues.count) == counts)
		for entry in loaded {
			#expect(entry.usesOutputSubdirectory)
		}
		#expect(loaded.map(\.sourceName) == entries.filter { $0.hasSuffix(".pro") }.sorted().map { String($0.dropLast(4)) })
		let extracted = try #require(loaded.first?.document.mediaDirectory)
		#expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("Media/Assets/ImageSample.png").path))
		let references = try loaded.flatMap { try MediaReference.collect(protobuf: $0.document.presentation.serializedData(), messageType: Rv_Data_Presentation.protoMessageName) }
		#expect(references.count == 8)
		#expect(Set(references.map(\.referenceID)).count == 8)
		#expect(Set(references.compactMap(\.assetID)).count == 3)
		#expect(references.allSatisfy { $0.identitySchemaVersion == "1" })
		#expect(throws: DocumentLoadError.self) { try DocumentLoader.load(from: bundle) }
		#expect(throws: ArchiveError.self) { try PresentationLoader.loadPresentations(from: bundle, archiveLimits: .init(maximumEntryCount: 1)) }
		loaded.removeAll()
		#expect(!FileManager.default.fileExists(atPath: extracted.path))
	}

	@Test func singleBundleRetainsItsExistingOutputNaming() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let bundle = directory.appendingPathComponent("Custom Name.probundle")
		try ZIPArchive.create(from: corpus.appendingPathComponent("Documents"), entries: ["01 - Element Layering.pro"], to: bundle)
		let load: (URL) throws -> [LoadedPresentationDocument] = PresentationLoader.loadPresentations(from:)
		let loaded = try load(bundle)
		#expect(loaded.count == 1)
		#expect(loaded.first?.sourceName == "Custom Name")
		#expect(loaded.first?.usesOutputSubdirectory == false)
	}

	@Test func mediaFreeCollectionsBundleEveryPayloadAndRejectAnInvalidLaterDocumentAtomically() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let input = directory.appendingPathComponent("Input")
		try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		for name in ["01 - Element Layering", "06 - Shapes"] {
			try FileManager.default.copyItem(at: corpus.appendingPathComponent("Documents/\(name).pro"), to: input.appendingPathComponent("\(name).pro"))
		}
		let bundle = try DocumentArchive.bundle(input, to: directory.appendingPathComponent("Collection.probundle"))
		let loaded = try PresentationLoader.loadPresentations(from: bundle)
		#expect(loaded.map(\.document.orderedCues.count) == [1, 11])
		for entry in loaded {
			let original = try PresentationLoader.load(from: input.appendingPathComponent("\(entry.sourceName).pro"))
			#expect(entry.document.presentation == original.presentation)
		}
		let before = try Data(contentsOf: bundle)
		try Data([0xFF]).write(to: input.appendingPathComponent("ZZ Invalid.pro"))
		#expect(throws: (any Error).self) { try DocumentArchive.bundle(input, to: bundle, replace: true) }
		#expect(try Data(contentsOf: bundle) == before)
	}

	@Test func emptyCollectionsAndCollidingOutputNamesAreExplicitErrors() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory.appendingPathComponent("Group"), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let bundle = directory.appendingPathComponent("Empty.probundle")
		try ZIPArchive.create(from: directory, entries: [], to: bundle)
		#expect(throws: DocumentLoadError.self) { try PresentationLoader.loadPresentations(from: bundle) }
		let original = corpus.appendingPathComponent("Documents/01 - Element Layering.pro")
		for path in ["Group/Deck.pro", "Group-Deck.pro"] {
			try FileManager.default.copyItem(at: original, to: directory.appendingPathComponent(path))
		}
		let collision = directory.appendingPathComponent("Collision.probundle")
		try ZIPArchive.create(from: directory, entries: ["Group/Deck.pro", "Group-Deck.pro"], to: collision)
		#expect(throws: DocumentLoadError.self) { try PresentationLoader.loadPresentations(from: collision) }
	}

	@Test func editedCLICollectionImportsBothDocumentsAndPreservesTheEditThroughNativeExport() throws {
		let directory = corpus.appendingPathComponent("Roundtrip")
		let proof = try JSONDecoder().decode(Roundtrip.self, from: Data(contentsOf: directory.appendingPathComponent("provenance.json")))
		let bundle = directory.appendingPathComponent("CLI.probundle")
		#expect(try hash(Data(contentsOf: bundle)) == proof.bundleSHA256)
		let inputs = try PresentationLoader.loadPresentations(from: bundle)
		#expect(inputs.count == 2 && proof.streams.count == 2)
		for entry in proof.streams {
			let data = try Data(contentsOf: directory.appendingPathComponent("\(entry.originalName).loro"))
			let vector = try Data(contentsOf: directory.appendingPathComponent("\(entry.originalName).vector"))
			#expect(hash(data) == entry.snapshotSHA256)
			#expect(hash(vector) == entry.vectorSHA256)
			let stream = NativeWorkspaceStream(identity: .init(documentID: entry.documentID, scope: .shared, kind: "Presentation", corePath: "Default/\(entry.nativeName)", availability: .available, byteCount: Int64(data.count), sha256: entry.snapshotSHA256, updatedAtMilliseconds: 0), snapshot: data, versionVector: vector, lastSharedVersionVector: nil)
			let native = try stream.protobufProjection().presentation()
			let input = try #require(inputs.first { $0.sourceName == entry.originalName }).document.presentation
			#expect(native.name == entry.nativeName)
			#expect(UUID(uuidString: native.uuid.string) != UUID(uuidString: input.uuid.string))
			#expect(native.ccli == input.ccli)
			#expect(Set(native.cues.map(\.uuid)) == Set(input.cues.map(\.uuid)))
			let exportedData = try Data(contentsOf: directory.appendingPathComponent("NativeExports/\(entry.nativeName).pro"))
			#expect(hash(exportedData) == entry.exportSHA256)
			let exported = try Rv_Data_Presentation(serializedBytes: exportedData)
			#expect(exported.ccli == input.ccli)
			#expect(exported.cueGroups == native.cueGroups)
			if entry.originalName == "01 - Element Layering" {
				#expect(exported.ccli.songTitle == "CLI collection round trip")
			}
		}
	}

	@Test(arguments: [6, 8, 10]) func unchangedShapeControlsMatchFresh22Exports(slide: Int) throws {
		let document = try PresentationLoader.load(from: corpus.appendingPathComponent("Documents/06 - Shapes.pro"))
		let bitmap = try PresentationRenderer(document: document).render(cue: document.orderedCues[slide - 1])
		let image = NSImage(size: bitmap.size)
		image.addRepresentation(bitmap)
		let reference = try #require(NSImage(contentsOf: corpus.appendingPathComponent("Images/06 - Shapes/\(slide).png")))
		if let failure = Snapshotting<NSImage, NSImage>.proCRUDImage().diffing.diffV2(reference, image) {
			Issue.record(Comment(rawValue: failure.0))
		}
	}

	private struct Provenance: Decodable {
		struct File: Decodable { let path: String; let sha256: String }
		struct Stream: Decodable { let name: String; let documentID: UUID; let snapshotSHA256: String; let vectorSHA256: String }
		let build: String
		let images: [File]
		let payloads: [File]
		let streams: [Stream]
	}

	private struct Roundtrip: Decodable {
		struct Stream: Decodable {
			let originalName: String
			let nativeName: String
			let documentID: UUID
			let snapshotSHA256: String
			let vectorSHA256: String
			let exportSHA256: String
		}

		let bundleSHA256: String
		let streams: [Stream]
	}

	private var corpus: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/ProPresenter22/Rendering/ReferenceSlides")
	}

	private func hash(_ data: Data) -> String {
		Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
	}
}
