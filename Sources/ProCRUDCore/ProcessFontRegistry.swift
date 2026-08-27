import AppKit
import CoreText
import Foundation
import Synchronization

enum ProcessFontRegistry {
	private struct FontFile {
		var url: URL
		var postScriptName: String
		var familyName: String
	}

	private static let registeredURLs = Mutex<Set<URL>>([])

	private static let fontFiles: [FontFile] = {
		let fileManager = FileManager.default
		let directories = [
			fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts", isDirectory: true),
			URL(fileURLWithPath: "/Library/Fonts", isDirectory: true),
			URL(fileURLWithPath: "/Network/Library/Fonts", isDirectory: true),
		]
		let fontExtensions = Set(["otf", "ttf", "ttc"])
		var files: [FontFile] = []

		for directory in directories {
			guard let enumerator = fileManager.enumerator(
				at: directory,
				includingPropertiesForKeys: [.isRegularFileKey],
				options: [.skipsHiddenFiles],
			) else {
				continue
			}
			for case let url as URL in enumerator {
				guard fontExtensions.contains(url.pathExtension.lowercased()),
				      let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
				else {
					continue
				}
				for descriptor in descriptors {
					guard let postScriptName = CTFontDescriptorCopyAttribute(
						descriptor,
						kCTFontNameAttribute,
					) as? String else {
						continue
					}
					let familyName = CTFontDescriptorCopyAttribute(
						descriptor,
						kCTFontFamilyNameAttribute,
					) as? String ?? postScriptName
					files.append(FontFile(
						url: url,
						postScriptName: postScriptName,
						familyName: familyName,
					))
				}
			}
		}
		return files
	}()

	static func registerFonts(referencedByRTF data: Data) {
		for postScriptName in referencedPostScriptNames(in: data) where NSFont(name: postScriptName, size: 12) == nil {
			guard let requestedFont = fontFiles.first(where: {
				$0.postScriptName.compare(postScriptName, options: .caseInsensitive) == .orderedSame
			}) else {
				continue
			}

			let requestedDirectory = requestedFont.url.deletingLastPathComponent()
			let familyFonts = fontFiles.filter {
				$0.familyName.compare(requestedFont.familyName, options: .caseInsensitive) == .orderedSame
					&& $0.url.deletingLastPathComponent() == requestedDirectory
			}
			var selectedNames = Set<String>()
			for font in [requestedFont] + familyFonts {
				guard selectedNames.insert(font.postScriptName.lowercased()).inserted else { continue }
				let url = font.url
				let shouldRegister = registeredURLs.withLock { $0.insert(url).inserted }
				guard shouldRegister else { continue }
				CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
			}
		}
	}

	private static func referencedPostScriptNames(in data: Data) -> [String] {
		guard let rtf = String(data: data, encoding: .utf8),
		      let expression = try? NSRegularExpression(pattern: #"\\fcharset\d+\s+([^;}]+)"#)
		else {
			return []
		}
		let range = NSRange(rtf.startIndex..., in: rtf)
		return expression.matches(in: rtf, range: range).compactMap { match in
			guard let nameRange = Range(match.range(at: 1), in: rtf) else { return nil }
			return String(rtf[nameRange])
		}
	}
}
