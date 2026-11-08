import AppKit
import Foundation

enum RTFFontDiagnostics {
	static func diagnostics(for data: Data, decoded: NSAttributedString, at path: String) -> [RenderingDiagnostic] {
		var resolvedNames = Set<String>()
		decoded.enumerateAttribute(.font, in: NSRange(location: 0, length: decoded.length)) { value, _, _ in
			if let font = value as? NSFont {
				resolvedNames.insert(font.fontName)
			}
		}
		let resolved = resolvedNames.sorted().joined(separator: ", ")
		var results: [RenderingDiagnostic] = []
		var inspected = Set<String>()
		for name in RTFFontTable.referencedNames(in: data) where inspected.insert(name).inserted {
			if NSFont(name: name, size: 12) == nil {
				results.append(RenderingDiagnostic(
					code: .unavailableRTFFont,
					severity: .warning,
					componentPath: path,
					message: "RTF font table requests '\(name)', which is unavailable to this process. Decoded text uses [\(resolved)]. A used declaration may be substituted; unused table entries do not affect output. Install the requested face and verify in ProPresenter.",
				))
			}
		}
		return results
	}
}
