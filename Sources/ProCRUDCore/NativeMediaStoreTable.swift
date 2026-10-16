import Foundation

struct MediaStoreTable {
	struct Handle {
		let offset: Int
		let size: Int
	}

	let data: Data
	private(set) var verifiedBlocks = 0

	mutating func records(maximumRecords: Int) throws -> [MediaStoreRecord] {
		guard data.count >= 53 else { throw NativeMediaStoreError.invalid("truncated table footer") }
		var footer = MediaStoreCursor(data: Data(data.suffix(53)))
		guard try footer.byte() == 4 else { throw NativeMediaStoreError.unsupported("table checksum algorithm; expected XXH3") }
		let meta = try handle(&footer), index = try handle(&footer)
		footer.position = 41
		guard try footer.fixed(4) == 5 else { throw NativeMediaStoreError.unsupported("table format version; expected 5") }
		guard try footer.fixed(8) == 0x88E2_41B7_85F4_CFF7 else { throw NativeMediaStoreError.invalid("table magic") }
		let metadata = try entries(block(meta), maximumEntries: maximumRecords)
		guard metadata.count == 1, metadata[0].key == Data("rocksdb.properties".utf8) else { throw NativeMediaStoreError.unsupported("table metadata beyond the qualified properties block") }
		var propertyHandle = MediaStoreCursor(data: metadata[0].value)
		let properties = try entries(block(handle(&propertyHandle)), maximumEntries: maximumRecords)
		var names: [String: Data] = [:]
		for property in properties {
			guard let name = String(data: property.key, encoding: .utf8), names.updateValue(property.value, forKey: name) == nil else { throw NativeMediaStoreError.invalid("duplicate or non-UTF-8 table property") }
		}
		guard names["rocksdb.block.based.table.index.type"] == Data([0, 0, 0, 0]),
		      names["rocksdb.index.key.is.user.key"] == Data([1]),
		      names["rocksdb.index.value.is.delta.encoded"] == Data([1])
		else { throw NativeMediaStoreError.unsupported("table index layout") }
		let handles = try indexHandles(block(index), maximumEntries: maximumRecords)
		var result: [MediaStoreRecord] = []
		for handle in handles {
			for entry in try entries(block(handle), maximumEntries: maximumRecords) {
				guard entry.key.count >= 8 else { throw NativeMediaStoreError.invalid("short internal table key") }
				var trailer = MediaStoreCursor(data: Data(entry.key.suffix(8)))
				let tag = try trailer.fixed(8), type = tag & 255
				guard [0, 1, 7].contains(type) else { throw NativeMediaStoreError.unsupported("internal table value type \(type)") }
				guard let key = String(data: entry.key.dropLast(8), encoding: .utf8) else { throw NativeMediaStoreError.invalid("non-UTF-8 table model key") }
				guard result.count < maximumRecords else { throw NativeMediaStoreError.limitExceeded }
				result.append(.init(key: key, sequence: tag >> 8, value: type == 1 ? entry.value : nil))
			}
		}
		return result
	}

	private func handle(_ cursor: inout MediaStoreCursor) throws -> Handle {
		try .init(offset: cursor.integer(), size: cursor.integer())
	}

	private mutating func block(_ handle: Handle) throws -> Data {
		guard handle.offset >= 0, handle.size >= 4, handle.size <= data.count - 58,
		      handle.offset <= data.count - 58 - handle.size
		else { throw NativeMediaStoreError.invalid("table block outside file bounds") }
		let end = handle.offset + handle.size
		let compression = data[end]
		guard compression == 0 else { throw NativeMediaStoreError.unsupported("table compression \(compression)") }
		var checksum = MediaStoreCursor(data: data.subdata(in: end + 1 ..< end + 5))
		let payload = data.subdata(in: handle.offset ..< end)
		guard try UInt64(MediaStoreChecksum.xxh3(payload, lastByte: compression)) == checksum.fixed(4) else { throw NativeMediaStoreError.invalid("table XXH3 checksum mismatch") }
		verifiedBlocks += 1
		return payload
	}

	private func entryBoundary(_ data: Data) throws -> (end: Int, restarts: Set<Int>) {
		guard data.count >= 4 else { throw NativeMediaStoreError.invalid("short table block") }
		var trailer = MediaStoreCursor(data: Data(data.suffix(4)))
		let count = try Int(trailer.fixed(4))
		guard count > 0, count <= (data.count - 4) / 4 else { throw NativeMediaStoreError.invalid("table restart count") }
		let end = data.count - 4 - count * 4
		var offsets = MediaStoreCursor(data: data.subdata(in: end ..< data.count - 4)), restarts = Set<Int>(), previous = -1
		for _ in 0 ..< count {
			let offset = try Int(offsets.fixed(4))
			guard offset >= 0, offset <= end, offset > previous else { throw NativeMediaStoreError.invalid("table restart offset") }
			restarts.insert(offset); previous = offset
		}
		guard restarts.contains(0) else { throw NativeMediaStoreError.invalid("table restart origin") }
		return (end, restarts)
	}

	private func entries(_ data: Data, maximumEntries: Int) throws -> [(key: Data, value: Data)] {
		let boundary = try entryBoundary(data)
		var cursor = MediaStoreCursor(data: data), previous = Data(), result: [(Data, Data)] = [], encountered = Set<Int>()
		while cursor.position < boundary.end {
			let start = cursor.position, shared = try cursor.integer(), unshared = try cursor.integer(), count = try cursor.integer()
			guard shared <= previous.count, !boundary.restarts.contains(start) || shared == 0 else { throw NativeMediaStoreError.invalid("table key prefix") }
			let key = try Data(previous.prefix(shared)) + cursor.bytes(unshared), value = try cursor.bytes(count)
			guard cursor.position <= boundary.end else { throw NativeMediaStoreError.invalid("table entry crosses restart array") }
			guard result.count < maximumEntries else { throw NativeMediaStoreError.limitExceeded }
			result.append((key, value)); previous = key; encountered.insert(start)
		}
		guard cursor.position == boundary.end, boundary.end == 0 || boundary.restarts.isSubset(of: encountered) else { throw NativeMediaStoreError.invalid("table restart does not address an entry") }
		return result
	}

	private func indexHandles(_ data: Data, maximumEntries: Int) throws -> [Handle] {
		let boundary = try entryBoundary(data)
		var cursor = MediaStoreCursor(data: data), previous = Data(), result: [Handle] = [], encountered = Set<Int>()
		while cursor.position < boundary.end {
			let start = cursor.position, shared = try cursor.integer(), unshared = try cursor.integer()
			guard shared <= previous.count, !boundary.restarts.contains(start) || shared == 0 else { throw NativeMediaStoreError.invalid("index key prefix") }
			let key = try Data(previous.prefix(shared)) + cursor.bytes(unshared)
			let next: Handle
			if shared == 0 {
				next = try handle(&cursor)
			} else {
				guard let previous = result.last else { throw NativeMediaStoreError.invalid("index delta without a previous handle") }
				let raw = try cursor.varint(), delta = Int64(bitPattern: (raw >> 1) ^ (0 &- (raw & 1)))
				let (size, overflow) = Int64(previous.size).addingReportingOverflow(delta)
				guard !overflow, size >= 4, size <= self.data.count else { throw NativeMediaStoreError.invalid("index size delta") }
				next = .init(offset: previous.offset + previous.size + 5, size: Int(size))
			}
			guard cursor.position <= boundary.end, next.offset >= 0, next.size >= 4, next.size <= self.data.count - 58,
			      next.offset <= self.data.count - next.size - 58
			else { throw NativeMediaStoreError.invalid("index block handle") }
			guard result.count < maximumEntries else { throw NativeMediaStoreError.limitExceeded }
			result.append(next); previous = key; encountered.insert(start)
		}
		guard cursor.position == boundary.end, boundary.end == 0 || boundary.restarts.isSubset(of: encountered) else { throw NativeMediaStoreError.invalid("index restart does not address an entry") }
		return result
	}
}
