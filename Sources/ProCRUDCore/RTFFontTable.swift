import Foundation

/// Inspects conventional, plain-name font-table entries without rewriting RTF.
enum RTFFontTable {
	static func referencedNames(in data: Data) -> [String] {
		let source = String(decoding: data, as: UTF8.self)
		guard let start = source.range(of: #"{\fonttbl"#) else { return [] }
		var depth = 1
		var escaped = false
		var end = start.upperBound
		while end < source.endIndex, depth > 0 {
			let character = source[end]
			if escaped {
				escaped = false
			} else if character == "\\" {
				escaped = true
			} else if character == "{" {
				depth += 1
			} else if character == "}" {
				depth -= 1
			}
			end = source.index(after: end)
		}
		guard depth == 0 else { return [] }
		let table = String(source[start.upperBound ..< end])
		// Skip escaped/encoded names and nested alternate-name destinations rather
		// than treating their control words as part of a requested font name.
		guard let expression = try? NSRegularExpression(
			pattern: #"\\f\d+\s*(?:\\[a-z]+-?\d*\s*)*\s*([^\\{};]+);"#,
		) else { return [] }
		return expression.matches(in: table, range: NSRange(table.startIndex..., in: table)).compactMap { match in
			guard let name = Range(match.range(at: 1), in: table) else { return nil }
			return table[name].trimmingCharacters(in: .whitespacesAndNewlines)
		}
	}
}
