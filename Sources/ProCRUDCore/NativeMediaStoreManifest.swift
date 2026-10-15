import Foundation

struct MediaStoreManifest {
	struct File {
		let number: UInt64
		let size: UInt64
	}

	var files: [UInt64: File] = [:]
	var logNumber: UInt64 = 0
	var previousLogNumber: UInt64 = 0
	var lastSequence: UInt64 = 0

	init(data: Data, maximumRecordBytes: Int, maximumRecords: Int) throws {
		for record in try MediaStoreLog.records(data, maximumRecordBytes: maximumRecordBytes, maximumRecords: maximumRecords) {
			var cursor = MediaStoreCursor(data: record)
			while cursor.remaining > 0 {
				let tag = try cursor.varint()
				switch tag {
				case 1:
					guard try cursor.lengthPrefixed() == Data("leveldb.BytewiseComparator".utf8) else { throw NativeMediaStoreError.unsupported("non-bytewise comparator") }
				case 2: logNumber = try cursor.varint()
				case 4: lastSequence = try cursor.varint()
				case 9: previousLogNumber = try cursor.varint()
				case 3, 10, 203, 300: _ = try cursor.varint()
				case 200:
					guard try cursor.varint() == 0 else { throw NativeMediaStoreError.unsupported("nondefault manifest column family") }
				case 6:
					_ = try cursor.varint()
					try files.removeValue(forKey: cursor.varint())
				case 103:
					_ = try cursor.varint() // Level does not affect a full sequence scan.
					let number = try cursor.varint(), size = try cursor.varint()
					_ = try cursor.lengthPrefixed(); _ = try cursor.lengthPrefixed()
					_ = try cursor.varint(); _ = try cursor.varint()
					while true {
						let field = try cursor.varint()
						if field == 1 {
							break
						}
						guard field & 64 == 0 else { throw NativeMediaStoreError.unsupported("required new-file manifest field \(field)") }
						_ = try cursor.lengthPrefixed()
					}
					guard files.count < maximumRecords || files[number] != nil else { throw NativeMediaStoreError.limitExceeded }
					files[number] = .init(number: number, size: size)
				default:
					guard tag & 8192 != 0 else { throw NativeMediaStoreError.unsupported("manifest tag \(tag)") }
					_ = try cursor.lengthPrefixed() // RocksDB explicitly marks this tag ignorable.
				}
			}
		}
	}
}
