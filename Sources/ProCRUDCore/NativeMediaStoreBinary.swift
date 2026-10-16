import CXXHash
import Foundation

public enum NativeMediaStoreError: Error, CustomStringConvertible, Sendable {
	case invalid(String)
	case unsupported(String)
	case limitExceeded
	case changedDuringRead

	public var description: String {
		switch self {
		case let .invalid(detail): "Invalid native MediaStore: \(detail)"
		case let .unsupported(detail): "Unsupported native MediaStore: \(detail)"
		case .limitExceeded: "Native MediaStore exceeds the bounded read limits."
		case .changedDuringRead: "Native MediaStore changed during inspection; retry after its writers are idle."
		}
	}
}

struct MediaStoreCursor {
	let data: Data
	var position = 0
	var remaining: Int {
		data.count - position
	}

	mutating func byte() throws -> UInt8 {
		guard remaining > 0 else { throw NativeMediaStoreError.invalid("truncated field") }
		defer { position += 1 }
		return data[position]
	}

	mutating func bytes(_ count: Int) throws -> Data {
		guard count >= 0, count <= remaining else { throw NativeMediaStoreError.invalid("truncated byte field") }
		defer { position += count }
		return data.subdata(in: position ..< position + count)
	}

	mutating func varint() throws -> UInt64 {
		var result: UInt64 = 0
		for shift in stride(from: 0, to: 64, by: 7) {
			let value = try byte()
			guard shift < 63 || value <= 1 else { throw NativeMediaStoreError.invalid("overflowing varint") }
			result |= UInt64(value & 127) << shift
			if value < 128 {
				return result
			}
		}
		throw NativeMediaStoreError.invalid("unterminated varint")
	}

	mutating func integer() throws -> Int {
		let value = try varint()
		guard let result = Int(exactly: value) else { throw NativeMediaStoreError.limitExceeded }
		return result
	}

	mutating func lengthPrefixed() throws -> Data {
		let count = try integer()
		return try bytes(count)
	}

	mutating func fixed(_ count: Int) throws -> UInt64 {
		var result: UInt64 = 0
		for shift in 0 ..< count {
			let value = try byte()
			result |= UInt64(value) << (shift * 8)
		}
		return result
	}
}

enum MediaStoreChecksum {
	private static let table: [UInt32] = (0 ..< 256).map { input in
		var value = UInt32(input)
		for _ in 0 ..< 8 {
			value = (value >> 1) ^ (value & 1 == 1 ? 0x82F6_3B78 : 0)
		}
		return value
	}

	static func maskedCRC32C(_ data: Data) -> UInt32 {
		var value = UInt32.max
		for byte in data {
			value = table[Int((value ^ UInt32(byte)) & 255)] ^ (value >> 8)
		}
		value ^= UInt32.max
		return ((value >> 15) | (value << 17)) &+ 0xA282_EAD8
	}

	static func xxh3(_ data: Data, lastByte: UInt8) -> UInt32 {
		let hash = data.withUnsafeBytes { pro_crud_xxh3_64($0.baseAddress, $0.count) }
		return UInt32(truncatingIfNeeded: hash) ^ (UInt32(lastByte) &* 0x6B90_83D9)
	}
}

enum MediaStoreLog {
	static func records(_ data: Data, maximumRecordBytes: Int, maximumRecords: Int) throws -> [Data] {
		var result: [Data] = [], fragments = Data(), fragmentOpen = false, offset = 0
		while offset < data.count {
			let remaining = min(32768 - offset % 32768, data.count - offset)
			if remaining < 7 {
				guard data[offset ..< offset + remaining].allSatisfy({ $0 == 0 }) else { throw NativeMediaStoreError.invalid("nonzero log trailer") }
				offset += remaining; continue
			}
			var header = MediaStoreCursor(data: data.subdata(in: offset ..< offset + 7))
			let checksum = try UInt32(header.fixed(4)), length = try Int(header.fixed(2)), type = try header.byte()
			if type == 0, length == 0 {
				guard data[offset ..< offset + remaining].allSatisfy({ $0 == 0 }) else { throw NativeMediaStoreError.invalid("nonzero log padding") }
				offset += remaining; continue
			}
			guard (1 ... 4).contains(type) else { throw NativeMediaStoreError.unsupported("log record type \(type)") }
			guard length <= remaining - 7 else { throw NativeMediaStoreError.invalid("log record crosses its block or file boundary") }
			let payload = data.subdata(in: offset + 7 ..< offset + 7 + length)
			guard MediaStoreChecksum.maskedCRC32C(Data([type]) + payload) == checksum else { throw NativeMediaStoreError.invalid("log CRC32C mismatch") }
			switch type {
			case 1:
				guard !fragmentOpen else { throw NativeMediaStoreError.invalid("full record inside fragmented log record") }
				result.append(payload)
			case 2:
				guard !fragmentOpen else { throw NativeMediaStoreError.invalid("nested first log fragment") }
				fragments = payload; fragmentOpen = true
			case 3, 4:
				guard fragmentOpen else { throw NativeMediaStoreError.invalid("log fragment without a first fragment") }
				guard payload.count <= maximumRecordBytes - fragments.count else { throw NativeMediaStoreError.limitExceeded }
				fragments.append(payload)
				if type == 4 {
					result.append(fragments); fragments = Data(); fragmentOpen = false
				}
			default: break
			}
			guard result.count <= maximumRecords, payload.count <= maximumRecordBytes, fragments.count <= maximumRecordBytes else { throw NativeMediaStoreError.limitExceeded }
			offset += 7 + length
		}
		guard !fragmentOpen else { throw NativeMediaStoreError.invalid("incomplete fragmented log record") }
		return result
	}
}

struct MediaStoreRecord: Equatable {
	let key: String
	let sequence: UInt64
	let value: Data?
}

enum MediaStoreWriteBatch {
	static func records(_ data: Data, maximumRecords: Int) throws -> [MediaStoreRecord] {
		var cursor = MediaStoreCursor(data: data)
		let sequence = try cursor.fixed(8), count = try Int(cursor.fixed(4))
		guard count <= maximumRecords else { throw NativeMediaStoreError.limitExceeded }
		var result: [MediaStoreRecord] = []
		while cursor.remaining > 0 {
			let tag = try cursor.byte()
			if tag == 3 {
				_ = try cursor.lengthPrefixed(); continue
			}
			guard [0, 1, 4, 5, 7, 8].contains(tag) else { throw NativeMediaStoreError.unsupported("write-batch operation \(tag)") }
			if [4, 5, 8].contains(tag), try cursor.varint() != 0 {
				throw NativeMediaStoreError.unsupported("nondefault column family")
			}
			guard let key = try String(data: cursor.lengthPrefixed(), encoding: .utf8) else { throw NativeMediaStoreError.invalid("non-UTF-8 model key") }
			let value: Data? = try [1, 5].contains(tag) ? cursor.lengthPrefixed() : nil
			let (itemSequence, overflow) = sequence.addingReportingOverflow(UInt64(result.count))
			guard !overflow, result.count < count else { throw NativeMediaStoreError.invalid("write-batch count or sequence overflow") }
			result.append(.init(key: key, sequence: itemSequence, value: value))
		}
		guard result.count == count else { throw NativeMediaStoreError.invalid("write-batch count mismatch") }
		return result
	}
}
