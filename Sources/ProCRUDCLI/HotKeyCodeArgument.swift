import ArgumentParser
import Foundation
import ProPresenterProto

struct HotKeyCodeArgument: Decodable, ExpressibleByArgument, Equatable, Sendable {
	var value: Rv_Data_HotKey.KeyCode

	init?(argument: String) {
		guard let value = Self.parse(argument) else { return nil }
		self.value = value
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let rawValue = try? container.decode(Int.self) {
			value = Self.code(rawValue: rawValue)
			return
		}
		let source = try container.decode(String.self)
		guard let value = Self.parse(source) else {
			throw DecodingError.dataCorruptedError(
				in: container,
				debugDescription: "Invalid hot-key code \(source).",
			)
		}
		self.value = value
	}

	private static func parse(_ source: String) -> Rv_Data_HotKey.KeyCode? {
		if let rawValue = Int(source) {
			return code(rawValue: rawValue)
		}
		var normalized = source.unicodeScalars
			.filter(CharacterSet.alphanumerics.contains)
			.map { String($0).lowercased() }
			.joined()
		if normalized.hasPrefix("keycode") {
			normalized.removeFirst("keycode".count)
		}
		if normalized.count == 1,
		   normalized.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
		{
			normalized = "ansi\(normalized)"
		}
		return Rv_Data_HotKey.KeyCode.allCases.first { code in
			normalizedName(for: code) == normalized
		}
	}

	private static func normalizedName(for code: Rv_Data_HotKey.KeyCode) -> String {
		String(describing: code).unicodeScalars
			.filter(CharacterSet.alphanumerics.contains)
			.map { String($0).lowercased() }
			.joined()
	}

	private static func code(rawValue: Int) -> Rv_Data_HotKey.KeyCode {
		Rv_Data_HotKey.KeyCode(rawValue: rawValue) ?? .UNRECOGNIZED(rawValue)
	}
}
