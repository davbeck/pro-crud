import CryptoKit
import Foundation
import Testing
@testable import ProCRUDCore

@Suite("Native MediaStore inspection")
struct NativeMediaStoreTests {
	@Test func nativeSnapshotMatchesTheIndependentManifestTableAndWALOracleWithoutWrites() throws {
		let before = try hashes(fixtures)
		let store = try NativeMediaStoreSnapshot.read(at: fixtures)
		#expect(store.schemaVersion == 1 && store.sequence == 41985)
		#expect(store.tableFiles == ["000143.sst", "000146.sst", "000151.sst"])
		#expect(store.logFiles == ["000152.log"] && store.verifiedTableBlocks == 174)
		#expect(store.nativeModelCount == 343 && store.assets.count == 19 && store.references.count == 90)
		#expect(store.uninspectedModelKinds.values.reduce(0, +) == 233)
		#expect(try NativeMediaStoreSnapshot.read(at: fixtures).fingerprint == store.fingerprint)
		#expect(try hashes(fixtures) == before)
		let evidence = try JSONSerialization.jsonObject(with: Data(contentsOf: modelFixtures.appendingPathComponent("NativeModels.json"))) as? [[String: Any]]
		for entry in try #require(evidence) {
			let key = try #require(entry["key"] as? String), value = try #require(entry["value"] as? NSDictionary)
			let actual = try JSONSerialization.jsonObject(with: #require(store.rawModels[key])) as? NSDictionary
			#expect(actual == value)
		}
	}

	@Test func actualDeclaredAndMaterializedAssetsRemainSeparateFromFileAvailability() throws {
		let store = try NativeMediaStoreSnapshot.read(at: fixtures)
		let occurrences = try JSONDecoder().decode([NativeMediaInventory.Occurrence].self, from: Data(contentsOf: modelFixtures.appendingPathComponent("ObservedOccurrences.json")))
		let associations = NativeMediaStoreAssociation.inspect(occurrences, in: store)
		#expect(occurrences.filter { !$0.localFilesAvailable }.isEmpty)
		#expect(associations.filter { $0.status == .matched }.count == 2)
		let mismatch = try #require(associations.first { $0.status == .differentAsset })
		#expect(mismatch.declaredAssetID == "c9d1f3fa-0a66-59ea-8e21-2a8dc07cc848")
		#expect(mismatch.materializedAssetID == UUID(uuidString: "e9d88797-3cdd-5d73-9d15-e403549de005"))
		#expect(mismatch.storedAssetPath?.hasSuffix("/Media/Assets/EventPhoto.jpg") == true)
	}

	@Test func corruptTablesWALAndManifestAreRejected() throws {
		for name in ["000143.sst", "000152.log", "MANIFEST-000153"] {
			try withCopy { root in
				let file = root.appendingPathComponent(name)
				var data = try Data(contentsOf: file); data[20] ^= 1; try data.write(to: file)
				#expect(throws: NativeMediaStoreError.self) { try NativeMediaStoreSnapshot.read(at: root) }
			}
		}
	}

	@Test func futureFooterAndCurrentPathTraversalCannotBeInterpreted() throws {
		try withCopy { root in
			let file = root.appendingPathComponent("000143.sst")
			var data = try Data(contentsOf: file); data[data.count - 12] = 6; try data.write(to: file)
			#expect(throws: NativeMediaStoreError.self) { try NativeMediaStoreSnapshot.read(at: root) }
		}
		try withCopy { root in
			try Data("../MANIFEST-000153\n".utf8).write(to: root.appendingPathComponent("CURRENT"))
			#expect(throws: NativeMediaStoreError.self) { try NativeMediaStoreSnapshot.read(at: root) }
		}
	}

	@Test func missingOrSymbolicLinkedActiveTablesAreRejected() throws {
		for symlink in [false, true] {
			try withCopy { root in
				let file = root.appendingPathComponent("000143.sst")
				try FileManager.default.removeItem(at: file)
				if symlink {
					try FileManager.default.createSymbolicLink(at: file, withDestinationURL: fixtures.appendingPathComponent("000143.sst"))
				}
				#expect(throws: NativeMediaStoreError.self) { try NativeMediaStoreSnapshot.read(at: root) }
			}
		}
	}

	@Test func committedWALTombstoneCannotResurrectAnOlderTableReference() throws {
		try withCopy { root in
			let key = "v3_helper_workspaces::db::models::reference::Reference:80eb4ec7-9507-5bb1-be56-1b42ab4f077a"
			try appendDeletion(key, sequence: 41986, root: root)
			let store = try NativeMediaStoreSnapshot.read(at: root)
			#expect(store.references.count == 89 && store.nativeModelCount == 342 && store.sequence == 41986)
			#expect(!store.references.contains { $0.id == UUID(uuidString: "80eb4ec7-9507-5bb1-be56-1b42ab4f077a") })
		}
	}

	@Test func stableRetryCapturesAnAppendedCommitAndRepeatedChangesAreBounded() throws {
		try withCopy { root in
			var attempts = 0
			let capture = try MediaStoreCapture.read(at: root, limits: .init()) {
				attempts += 1
				if attempts == 1 {
					try appendDeletion("test-model", sequence: 41986, root: root)
				}
			}
			#expect(attempts == 2 && capture.sequence == 41986)
			var repeated = 0
			#expect(throws: NativeMediaStoreError.self) {
				try MediaStoreCapture.read(at: root, limits: .init()) {
					repeated += 1
					try appendDeletion("test-model", sequence: UInt64(41986 + repeated), root: root)
				}
			}
			#expect(repeated == 3)
		}
	}

	@Test func byteAndRecordBudgetsStopBeforeUnboundedAllocation() throws {
		var bytes = NativeMediaStoreReadLimits(); bytes.maximumFileBytes = 128; bytes.maximumRecordBytes = 128
		#expect(throws: NativeMediaStoreError.self) { try NativeMediaStoreSnapshot.read(at: fixtures, limits: bytes) }
		var records = NativeMediaStoreReadLimits(); records.maximumRecords = 100
		#expect(throws: NativeMediaStoreError.self) { try NativeMediaStoreSnapshot.read(at: fixtures, limits: records) }
	}

	@Test func fragmentedLogRecordsNeedEveryFragmentChecksumAndAClosingFragment() throws {
		let first = Data(repeating: 42, count: 32761), last = Data(repeating: 7, count: 200)
		let record = physical(first, type: 2) + physical(last, type: 4)
		#expect(try MediaStoreLog.records(record, maximumRecordBytes: 40000, maximumRecords: 10) == [first + last])
		#expect(throws: NativeMediaStoreError.self) { try MediaStoreLog.records(physical(first, type: 2), maximumRecordBytes: 40000, maximumRecords: 10) }
		var corrupt = record; corrupt[corrupt.count - 1] ^= 1
		#expect(throws: NativeMediaStoreError.self) { try MediaStoreLog.records(corrupt, maximumRecordBytes: 40000, maximumRecords: 10) }
	}

	@Test func unknownWriteOperationsCountsAndIncompleteWALTailsFail() throws {
		let header = fixed(42000, bytes: 8) + fixed(1, bytes: 4)
		#expect(throws: NativeMediaStoreError.self) { try MediaStoreWriteBatch.records(header + Data([9]), maximumRecords: 10) }
		#expect(throws: NativeMediaStoreError.self) { try MediaStoreWriteBatch.records(header + Data([5, 1]), maximumRecords: 10) }
		#expect(throws: NativeMediaStoreError.self) { try MediaStoreWriteBatch.records(header, maximumRecords: 10) }
		try withCopy { root in
			let file = root.appendingPathComponent("000152.log")
			try Data(Data(contentsOf: file).dropLast()).write(to: file)
			#expect(throws: NativeMediaStoreError.self) { try NativeMediaStoreSnapshot.read(at: root) }
		}
	}

	private var fixtures: URL {
		root.appendingPathComponent("Fixtures/ProPresenter22/Native/MediaStoreSnapshot")
	}

	private var modelFixtures: URL {
		root.appendingPathComponent("Fixtures/ProPresenter22/Native/MediaStoreModels")
	}

	private var root: URL {
		URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
	}

	private func hashes(_ root: URL) throws -> [String: Data] {
		try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: root.path).map { name in
			try (name, Data(SHA256.hash(data: Data(contentsOf: root.appendingPathComponent(name)))))
		})
	}

	private func withCopy(_ operation: (URL) throws -> Void) throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStore-\(UUID().uuidString)")
		try FileManager.default.copyItem(at: fixtures, to: root)
		defer { try? FileManager.default.removeItem(at: root) }
		try operation(root)
	}

	private func fixed(_ value: UInt64, bytes: Int) -> Data {
		Data((0 ..< bytes).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
	}

	private func varint(_ input: Int) -> Data {
		var value = input, data = Data()
		while value > 127 {
			data.append(UInt8(value & 127) | 128); value >>= 7
		}
		data.append(UInt8(value)); return data
	}

	private func physical(_ payload: Data, type: UInt8 = 1) -> Data {
		fixed(UInt64(MediaStoreChecksum.maskedCRC32C(Data([type]) + payload)), bytes: 4) + fixed(UInt64(payload.count), bytes: 2) + Data([type]) + payload
	}

	private func appendDeletion(_ key: String, sequence: UInt64, root: URL) throws {
		let file = root.appendingPathComponent("000152.log"), original = try Data(contentsOf: file)
		let batch = fixed(sequence, bytes: 8) + fixed(1, bytes: 4) + Data([0]) + varint(key.utf8.count) + Data(key.utf8)
		let record = physical(batch), remaining = 32768 - original.count % 32768
		let padding = remaining < record.count ? Data(repeating: 0, count: remaining) : Data()
		try (original + padding + record).write(to: file)
	}
}
