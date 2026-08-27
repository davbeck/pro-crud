import AppKit
import Foundation
import ProPresenterProto
import SwiftProtobuf

public enum TemplateResolutionMode: String, Codable, Sendable {
	case applyExisting
	case instantiateNew
	case runtimeLook
}

public enum TemplateActionPolicy: String, Codable, Sendable {
	/// Keep the cue's existing non-slide actions and do not copy template actions.
	case preserve
	/// Keep existing actions and append identity-safe copies of template actions.
	case append
	/// Replace existing non-slide actions with identity-safe template actions.
	case replace
}

public struct TemplateResolutionReport: Codable, Sendable {
	public struct Size: Codable, Sendable {
		public var width: Double
		public var height: Double
	}

	public struct Transform: Codable, Sendable {
		public var xScale: Double
		public var yScale: Double
		public var fontScale: Double
	}

	public struct Element: Codable, Sendable {
		public var index: Int
		public var name: String
		public var uuid: String
	}

	public struct TextRun: Codable, Sendable {
		public var location: Int
		public var length: Int
		public var font: String
		public var foregroundColor: String
		public var otherAttributes: String
	}

	public struct Assignment: Codable, Sendable {
		public var source: Element
		public var template: Element
		public var resultUUID: String
		public var reason: String
		public var textRuns: [TextRun]
	}

	public var schemaVersion = 1
	public var mode: TemplateResolutionMode
	public var templateName: String
	public var sourceSlideUUID: String?
	public var templateSlideUUID: String
	public var resultSlideUUID: String
	public var templateSize: Size
	public var destinationSize: Size
	public var transform: Transform
	public var assignments: [Assignment]
	public var removedSourceElements: [Element]
	public var unfilledTemplateElements: [Element]
	public var warnings: [String]
}

public struct TemplateResolutionResult: Sendable {
	public var slide: Rv_Data_Slide
	public var actions: [Rv_Data_Action]
	public var report: TemplateResolutionReport
}

public struct PresentationTemplateResolution: Sendable {
	public var document: PresentationDocument
	public var reports: [TemplateResolutionReport]
}

public enum PresentationTemplateResolver {
	/// Applies Look-style template resolution transiently to every cue that has a
	/// presentation-slide action. The returned document is independent of the
	/// source and can be passed through every renderer output format.
	public static func resolve(
		document: PresentationDocument,
		template: ThemeTemplateSource.Candidate,
		destinationSize: CGSize? = nil,
		includeTemplateActions: Bool = false,
		slideIndices: Set<Int>? = nil,
	) throws -> PresentationTemplateResolution {
		var resolvedDocument = document
		if let owner = template.temporaryResourceOwner,
		   !resolvedDocument.temporaryResourceOwners.contains(where: { $0 === owner })
		{
			resolvedDocument.temporaryResourceOwners.append(owner)
		}
		var reports: [TemplateResolutionReport] = []
		for (orderedIndex, cueIndex) in resolvedDocument.presentation.presentationOrderCueIndices.enumerated()
			where slideIndices?.contains(orderedIndex) ?? true
		{
			let actionIndices = resolvedDocument.presentation.cues[cueIndex].actions.indices.filter {
				resolvedDocument.presentation.cues[cueIndex].actions[$0].type == .presentationSlide
			}
			guard let actionIndex = actionIndices.first,
			      case var .presentation(presentationSlide)? = resolvedDocument.presentation.cues[cueIndex].actions[actionIndex].slide.slide
			else { continue }
			let source = presentationSlide.baseSlide
			let canvas = destinationSize ?? CGSize(width: source.size.width, height: source.size.height)
			let resolution = try TemplateResolver.resolve(
				template: template.slide,
				source: source,
				destinationSize: canvas,
				mode: .runtimeLook,
			)
			presentationSlide.baseSlide = resolution.slide
			resolvedDocument.presentation.cues[cueIndex].actions[actionIndex].slide.presentation = presentationSlide
			var retainedMedia = ThemeTemplateSource.mediaReferences(in: resolution.slide)
			if includeTemplateActions {
				resolvedDocument.presentation.cues[cueIndex].actions.append(contentsOf: resolution.actions)
				retainedMedia.formUnion(ThemeTemplateSource.mediaReferences(in: resolution.actions))
			}
			resolvedDocument.preferredMediaReferences.formUnion(
				retainedMedia.intersection(template.preferredMediaReferences),
			)
			var report = resolution.report
			report.warnings.append(contentsOf: template.mediaWarnings)
			if actionIndices.count > 1 {
				report.warnings.append("Cue contains multiple presentation-slide actions; only the first renderable action was resolved.")
			}
			report.warnings = Array(Set(report.warnings)).sorted()
			reports.append(report)
		}
		return PresentationTemplateResolution(document: resolvedDocument, reports: reports)
	}
}

public enum TemplateResolutionError: Error, CustomStringConvertible, Sendable {
	case invalidCanvas(label: String, width: Double, height: Double)
	case invalidSourceRTF(index: Int, element: String)
	case missingSource(TemplateResolutionMode)

	public var description: String {
		switch self {
		case let .invalidCanvas(label, width, height):
			"Invalid \(label) canvas \(width)x\(height)."
		case let .invalidSourceRTF(index, element):
			"Source element \(index) (\(element)) has nonempty RTF that cannot be decoded safely."
		case let .missingSource(mode):
			"Template resolution mode \(mode.rawValue) requires a source slide."
		}
	}
}

/// Resolves a Theme template into the concrete slide graph used by an editor,
/// a new cue, or a transient Look-style render.
public enum TemplateResolver {
	public static func resolve(
		template: Rv_Data_Template.Slide,
		source: Rv_Data_Slide?,
		destinationSize: CGSize,
		mode: TemplateResolutionMode,
	) throws -> TemplateResolutionResult {
		try validate(size: template.baseSlide.size, label: "template")
		guard destinationSize.width.isFinite,
		      destinationSize.height.isFinite,
		      destinationSize.width > 0,
		      destinationSize.height > 0
		else {
			throw TemplateResolutionError.invalidCanvas(
				label: "destination",
				width: destinationSize.width,
				height: destinationSize.height,
			)
		}

		let xScale = destinationSize.width / template.baseSlide.size.width
		let yScale = destinationSize.height / template.baseSlide.size.height
		let emptyRTF = try canonicalEmptyRTF()
		var warnings = unsupportedWarnings(
			for: template.baseSlide,
			source: source,
			xScale: xScale,
			yScale: yScale,
			mode: mode,
		)
		if containsUnknownFields(in: template) {
			warnings.append("Unknown protobuf fields are preserved, but UUID references hidden inside them cannot be remapped after template identity changes.")
		}

		if mode == .instantiateNew {
			var slide = template.baseSlide
			normalizeKnownMaterializedElementInfo(in: &slide)
			scaleGeometry(in: &slide, x: xScale, y: yScale)
			slide.size.width = destinationSize.width
			slide.size.height = destinationSize.height
			for index in slide.elements.indices {
				if !slide.elements[index].element.hasText {
					slide.elements[index].element.text = defaultTemplateText()
				}
				slide.elements[index].element.text.rtfData = emptyRTF
				slide.elements[index].element.text.attributes.customAttributes = []
			}
			slide = ProPresenterGraphCopier.freshSlide(slide)
			let actions = template.actions.map(ProPresenterGraphCopier.freshAction)
			let unfilled = slide.elements.enumerated().map { index, element in
				reportElement(index: index, element: element.element)
			}
			let report = makeReport(
				template: template,
				source: nil,
				result: slide,
				destinationSize: destinationSize,
				mode: mode,
				xScale: xScale,
				yScale: yScale,
				assignments: [],
				removed: [],
				unfilled: unfilled,
				warnings: warnings,
			)
			return TemplateResolutionResult(slide: slide, actions: actions, report: report)
		}

		guard let source else { throw TemplateResolutionError.missingSource(mode) }
		if containsUnknownFields(in: source) {
			warnings.append("Source unknown protobuf fields may be removed with source-only elements or retained without hidden UUID remapping.")
		}
		for index in source.elements.indices {
			let element = source.elements[index].element
			guard element.hasText, !element.text.rtfData.isEmpty else { continue }
			guard (try? attributedString(from: element.text.rtfData)) != nil else {
				let identity = element.name.isEmpty ? element.uuid.string : element.name
				throw TemplateResolutionError.invalidSourceRTF(index: index, element: identity)
			}
		}

		var slide = template.baseSlide
		normalizeKnownMaterializedElementInfo(in: &slide)
		scaleGeometry(in: &slide, x: xScale, y: yScale)
		slide.size.width = destinationSize.width
		slide.size.height = destinationSize.height
		slide.uuid = source.uuid

		let sourceTextIndices = source.elements.indices.filter {
			meaningfulText(in: source.elements[$0].element)
		}
		var availableTemplateIndices = Set(slide.elements.indices)
		var matchedTemplateBySource: [Int: (index: Int, reason: String)] = [:]

		// ProPresenter's controlled outputs first honored exact names. Iterating
		// source and template stored order also preserves duplicate-name pairing.
		for sourceIndex in sourceTextIndices {
			let sourceName = source.elements[sourceIndex].element.name
			guard !sourceName.isEmpty else { continue }
			guard let templateIndex = slide.elements.indices.first(where: {
				availableTemplateIndices.contains($0) && slide.elements[$0].element.name == sourceName
			}) else { continue }
			matchedTemplateBySource[sourceIndex] = (templateIndex, "exact-name")
			availableTemplateIndices.remove(templateIndex)
		}

		let unmatchedSource = sourceTextIndices.filter { matchedTemplateBySource[$0] == nil }
		for sourceIndex in unmatchedSource {
			let textSlot = slide.elements.indices.reversed().first(where: {
				availableTemplateIndices.contains($0) && meaningfulText(in: slide.elements[$0].element)
			})
			let anySlot = slide.elements.indices.reversed().first(where: availableTemplateIndices.contains)
			guard let templateIndex = textSlot ?? anySlot else { continue }
			matchedTemplateBySource[sourceIndex] = (
				templateIndex,
				textSlot == nil ? "reverse-order-graphics-fallback" : "reverse-order-text-fallback",
			)
			availableTemplateIndices.remove(templateIndex)
		}

		var assignments: [TemplateResolutionReport.Assignment] = []
		var templateToResultUUID: [String: Rv_Data_UUID] = [:]
		for sourceIndex in sourceTextIndices {
			guard let match = matchedTemplateBySource[sourceIndex] else { continue }
			let sourceElement = source.elements[sourceIndex].element
			let templateElement = template.baseSlide.elements[match.index].element
			var resultElement = slide.elements[match.index].element
			resultElement.uuid = sourceElement.uuid

			let textResult = resolvedText(
				source: sourceElement.text,
				template: templateElement.hasText ? templateElement.text : nil,
				fontScale: yScale,
			)
			resultElement.text = textResult.text
			warnings.append(contentsOf: textResult.warnings.map {
				"Element \(sourceElement.name.isEmpty ? sourceElement.uuid.string : sourceElement.name): \($0)"
			})
			slide.elements[match.index].element = resultElement
			if !templateElement.uuid.string.isEmpty {
				templateToResultUUID[templateElement.uuid.string] = resultElement.uuid
			}
			assignments.append(TemplateResolutionReport.Assignment(
				source: reportElement(index: sourceIndex, element: sourceElement),
				template: reportElement(index: match.index, element: templateElement),
				resultUUID: resultElement.uuid.string,
				reason: match.reason,
				textRuns: textResult.runs,
			))
		}

		for templateIndex in availableTemplateIndices {
			let element = slide.elements[templateIndex].element
			if !element.hasText {
				slide.elements[templateIndex].element.text = defaultTemplateText()
			}
			slide.elements[templateIndex].element.text.attributes.font.size *= yScale
			slide.elements[templateIndex].element.text.rtfData = emptyRTF
			slide.elements[templateIndex].element.text.attributes.customAttributes = []
			if !element.uuid.string.isEmpty {
				templateToResultUUID[element.uuid.string] = element.uuid
			}
		}
		ProPresenterGraphCopier.remapInternalReferences(in: &slide, using: templateToResultUUID)

		let assignedSource = Set(matchedTemplateBySource.keys)
		let removed = source.elements.indices.filter { !assignedSource.contains($0) }.map {
			reportElement(index: $0, element: source.elements[$0].element)
		}
		let unfilled = availableTemplateIndices.sorted().map {
			reportElement(index: $0, element: slide.elements[$0].element)
		}
		if sourceTextIndices.count > assignments.count {
			warnings.append("\(sourceTextIndices.count - assignments.count) source text element(s) overflowed the template slot inventory and were removed.")
		}

		let report = makeReport(
			template: template,
			source: source,
			result: slide,
			destinationSize: destinationSize,
			mode: mode,
			xScale: xScale,
			yScale: yScale,
			assignments: assignments.sorted { $0.template.index < $1.template.index },
			removed: removed,
			unfilled: unfilled,
			warnings: warnings,
		)
		return TemplateResolutionResult(
			slide: slide,
			actions: template.actions.map(ProPresenterGraphCopier.freshAction),
			report: report,
		)
	}

	private struct ResolvedText {
		var text: Rv_Data_Graphics.Text
		var runs: [TemplateResolutionReport.TextRun]
		var warnings: [String]
	}

	private static func resolvedText(
		source: Rv_Data_Graphics.Text,
		template: Rv_Data_Graphics.Text?,
		fontScale: Double,
	) -> ResolvedText {
		var result = template ?? defaultTemplateText()
		var warnings: [String] = []
		let unscaledTemplateAttributes = result.attributes
		if result.hasAttributes {
			result.attributes.font.size *= fontScale
		}

		let sourceLength = (try? attributedString(from: source.rtfData))?.length ?? 0
		let meaningfulSourceAttributes = source.attributes.customAttributes.filter { $0.attribute != nil }
		result.attributes.customAttributes = clippedMeaningfulCustomAttributes(
			source.attributes.customAttributes,
			utf16Length: sourceLength,
		)
		if result.attributes.customAttributes.count != meaningfulSourceAttributes.count ||
			zip(result.attributes.customAttributes, meaningfulSourceAttributes).contains(where: {
				$0.range.start != $1.range.start || $0.range.end != $1.range.end
			})
		{
			warnings.append("Malformed or stale meaningful custom-attribute ranges were clipped or dropped against the source UTF-16 length.")
		}
		if source.attributes.customAttributes.contains(where: { $0.attribute == nil }) {
			warnings.append("Discarded range-only custom attributes while rebuilding source text ranges.")
		}
		if source.attributes.customAttributes.contains(where: {
			switch $0.attribute {
			case .originalFontSize?, .fontScaleFactor?: true
			default: false
			}
		}) {
			warnings.append("Preserved original-font-size/font-scale-factor custom values without resolution scaling because native template-application behavior is unproven.")
		}
		if let template,
		   template.attributes.customAttributes.contains(where: { $0.attribute != nil })
		{
			warnings.append("Meaningful template custom attributes are not mapped from placeholder ranges; source custom ranges take precedence.")
		}

		do {
			let sourceAttributed = try attributedString(from: source.rtfData)
			let templateAttributed = try template.flatMap { value in
				value.rtfData.isEmpty ? nil : try attributedString(from: value.rtfData)
			}
			let merged = mergeAttributedText(
				source: sourceAttributed,
				sourceMetadata: source.attributes,
				template: templateAttributed,
				templateMetadata: unscaledTemplateAttributes,
				fontScale: fontScale,
			)
			result.rtfData = try merged.value.data(
				from: NSRange(location: 0, length: merged.value.length),
				documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
			)
			return ResolvedText(text: result, runs: merged.runs, warnings: warnings)
		} catch {
			result.rtfData = source.rtfData
			warnings.append("RTF could not be merged (\(error.localizedDescription)); source RTF bytes were retained.")
			return ResolvedText(text: result, runs: [], warnings: warnings)
		}
	}

	private struct AttributedMerge {
		var value: NSAttributedString
		var runs: [TemplateResolutionReport.TextRun]
	}

	private static func mergeAttributedText(
		source: NSAttributedString,
		sourceMetadata: Rv_Data_Graphics.Text.Attributes,
		template: NSAttributedString?,
		templateMetadata: Rv_Data_Graphics.Text.Attributes,
		fontScale: Double,
	) -> AttributedMerge {
		guard source.length > 0 else {
			return AttributedMerge(value: source, runs: [])
		}
		let entire = NSRange(location: 0, length: source.length)
		var sourceBase = modalAttributes(in: source)
		if sourceMetadata.hasFont, sourceMetadata.font.size > 0 {
			sourceBase[.font] = appKitAttributes(from: sourceMetadata)[.font]
		}
		var templateBase = template.flatMap { $0.length > 0 ? $0.attributes(at: 0, effectiveRange: nil) : nil }
			?? appKitAttributes(from: templateMetadata)
		if let font = templateBase[.font] as? NSFont {
			templateBase[.font] = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * fontScale) ?? font
		}

		let result = NSMutableAttributedString(string: source.string, attributes: templateBase)
		let varyingColor = hasMultipleValues(in: source, key: .foregroundColor)
		let varyingBackground = hasMultipleValues(in: source, key: .backgroundColor)
		let varyingParagraph = hasMultipleValues(in: source, key: .paragraphStyle)
		let exceptionalKeys: [NSAttributedString.Key] = [
			.underlineStyle,
			.underlineColor,
			.strikethroughStyle,
			.strikethroughColor,
			.kern,
			.baselineOffset,
			.strokeWidth,
			.strokeColor,
			.shadow,
		]
		let varyingExceptionalKeys = exceptionalKeys.filter {
			hasMultipleValues(in: source, key: $0)
		}
		var reports: [TemplateResolutionReport.TextRun] = []

		source.enumerateAttributes(in: entire) { attributes, range, _ in
			var resolved = templateBase
			let fontChoice = resolvedFont(
				source: attributes[.font] as? NSFont,
				sourceBase: sourceBase[.font] as? NSFont,
				template: templateBase[.font] as? NSFont,
			)
			if let font = fontChoice.font {
				resolved[.font] = font
			}

			if varyingColor, let color = attributes[.foregroundColor] {
				resolved[.foregroundColor] = color
			}
			if varyingBackground, let color = attributes[.backgroundColor] {
				resolved[.backgroundColor] = color
			}
			if varyingParagraph, let paragraph = attributes[.paragraphStyle] {
				resolved[.paragraphStyle] = paragraph
			}

			let usedExceptionalAttribute = !varyingExceptionalKeys.isEmpty
			for key in varyingExceptionalKeys {
				if let value = attributes[key] {
					resolved[key] = value
				} else {
					resolved.removeValue(forKey: key)
				}
			}

			result.setAttributes(resolved, range: range)
			reports.append(TemplateResolutionReport.TextRun(
				location: range.location,
				length: range.length,
				font: fontChoice.provenance,
				foregroundColor: varyingColor ? "source-exception-map" : "template-base",
				otherAttributes: usedExceptionalAttribute || varyingBackground || varyingParagraph
					? "template-base+source-exceptions"
					: "template-base",
			))
		}
		return AttributedMerge(value: result, runs: reports)
	}

	private static func resolvedFont(
		source: NSFont?,
		sourceBase: NSFont?,
		template: NSFont?,
	) -> (font: NSFont?, provenance: String) {
		guard let source, let sourceBase else {
			return (template, "template-base")
		}
		let ratio = sourceBase.pointSize > 0 ? source.pointSize / sourceBase.pointSize : 1
		let familyChanged = source.familyName != sourceBase.familyName
		let manager = NSFontManager.shared
		var resolved = template ?? sourceBase
		if familyChanged, let family = source.familyName {
			resolved = manager.convert(resolved, toFamily: family)
		}
		let sourceTraits = manager.traits(of: source)
		let baseTraits = manager.traits(of: sourceBase)
		for trait in [NSFontTraitMask.boldFontMask, .italicFontMask] {
			guard sourceTraits.contains(trait) != baseTraits.contains(trait) else { continue }
			resolved = sourceTraits.contains(trait)
				? manager.convert(resolved, toHaveTrait: trait)
				: manager.convert(resolved, toNotHaveTrait: trait)
		}
		let size = resolved.pointSize * ratio
		let provenance = if familyChanged {
			"source-exceptional-family-relative-size"
		} else if template == nil {
			"source-fallback"
		} else if ratio == 1 {
			"template-base"
		} else {
			"template-base+source-relative-size"
		}
		return (NSFont(descriptor: resolved.fontDescriptor, size: size) ?? resolved, provenance)
	}

	private static func modalAttributes(in attributed: NSAttributedString) -> [NSAttributedString.Key: Any] {
		guard attributed.length > 0 else { return [:] }
		var keys = Set<NSAttributedString.Key>()
		attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, _, _ in
			keys.formUnion(attributes.keys)
		}
		var result: [NSAttributedString.Key: Any] = [:]
		for key in keys {
			var candidates: [String: (length: Int, value: Any, order: Int)] = [:]
			var order = 0
			attributed.enumerateAttribute(
				key,
				in: NSRange(location: 0, length: attributed.length),
			) { value, range, _ in
				let signature = attributeSignature(value)
				if var candidate = candidates[signature] {
					candidate.length += range.length
					candidates[signature] = candidate
				} else {
					candidates[signature] = (range.length, value ?? NSNull(), order)
					order += 1
				}
			}
			let modal = candidates.values.max {
				$0.length == $1.length ? $0.order > $1.order : $0.length < $1.length
			}
			if let value = modal?.value, !(value is NSNull) {
				result[key] = value
			}
		}
		return result
	}

	private static func hasMultipleValues(in attributed: NSAttributedString, key: NSAttributedString.Key) -> Bool {
		guard attributed.length > 0 else { return false }
		var signatures = Set<String>()
		attributed.enumerateAttribute(key, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
			signatures.insert(attributeSignature(value))
			if signatures.count > 1 {
				stop.pointee = true
			}
		}
		return signatures.count > 1
	}

	private static func attributeSignature(_ value: Any?) -> String {
		guard let value else { return "<nil>" }
		if let font = value as? NSFont {
			return "font:\(font.fontName):\(font.pointSize)"
		}
		if let color = value as? NSColor,
		   let converted = color.usingColorSpace(.deviceRGB)
		{
			return "color:\(converted.redComponent):\(converted.greenComponent):\(converted.blueComponent):\(converted.alphaComponent)"
		}
		return String(describing: value)
	}

	private static func attributedString(from data: Data) throws -> NSAttributedString {
		ProcessFontRegistry.registerFonts(referencedByRTF: data)
		return try NSAttributedString(
			data: data,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		)
	}

	private static func canonicalEmptyRTF() throws -> Data {
		let value = NSAttributedString(string: "")
		return try value.data(
			from: NSRange(location: 0, length: 0),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)
	}

	static func appKitAttributes(
		from metadata: Rv_Data_Graphics.Text.Attributes,
	) -> [NSAttributedString.Key: Any] {
		let size = metadata.font.size > 0 ? metadata.font.size : 42
		let requestedName = metadata.font.name.isEmpty ? metadata.font.family : metadata.font.name
		var font = NSFont(name: requestedName, size: size) ?? NSFont.systemFont(ofSize: size)
		let manager = NSFontManager.shared
		if metadata.font.bold {
			font = manager.convert(font, toHaveTrait: .boldFontMask)
		}
		if metadata.font.italic {
			font = manager.convert(font, toHaveTrait: .italicFontMask)
		}
		var result: [NSAttributedString.Key: Any] = [.font: font]
		if case let .textSolidFill(color)? = metadata.fill {
			result[.foregroundColor] = appKitColor(color)
		} else {
			result[.foregroundColor] = NSColor.white
		}
		if metadata.hasUnderlineStyle {
			result[.underlineStyle] = appKitUnderlineStyle(metadata.underlineStyle)
		}
		if metadata.hasUnderlineColor {
			result[.underlineColor] = appKitColor(metadata.underlineColor)
		}
		if metadata.kerning != 0 {
			result[.kern] = metadata.kerning
		}
		if metadata.superscript != 0 {
			result[.superscript] = metadata.superscript
		}
		if metadata.hasStrikethroughStyle {
			result[.strikethroughStyle] = appKitUnderlineStyle(metadata.strikethroughStyle)
		}
		if metadata.hasStrikethroughColor {
			result[.strikethroughColor] = appKitColor(metadata.strikethroughColor)
		}
		if metadata.strokeWidth != 0 {
			result[.strokeWidth] = metadata.strokeWidth
		}
		if metadata.hasStrokeColor {
			result[.strokeColor] = appKitColor(metadata.strokeColor)
		}
		if metadata.hasBackgroundColor {
			result[.backgroundColor] = appKitColor(metadata.backgroundColor)
		}
		if metadata.hasParagraphStyle {
			let source = metadata.paragraphStyle
			let paragraph = NSMutableParagraphStyle()
			paragraph.alignment = appKitAlignment(source.alignment)
			paragraph.firstLineHeadIndent = source.firstLineHeadIndent
			paragraph.headIndent = source.headIndent
			paragraph.tailIndent = source.tailIndent
			paragraph.lineHeightMultiple = source.lineHeightMultiple
			paragraph.maximumLineHeight = source.maximumLineHeight
			paragraph.minimumLineHeight = source.minimumLineHeight
			paragraph.lineSpacing = source.lineSpacing
			paragraph.paragraphSpacing = source.paragraphSpacing
			paragraph.paragraphSpacingBefore = source.paragraphSpacingBefore
			paragraph.tabStops = source.tabStops.map {
				NSTextTab(
					textAlignment: appKitAlignment($0.alignment),
					location: $0.location,
					options: [:],
				)
			}
			paragraph.defaultTabInterval = source.defaultTabInterval
			let textLists = source.textLists.isEmpty && source.hasTextList
				? [source.textList]
				: source.textLists
			paragraph.textLists = textLists.filter(\.isEnabled).map(appKitTextList)
			result[.paragraphStyle] = paragraph
		}
		return result
	}

	private static func appKitAlignment(
		_ alignment: Rv_Data_Graphics.Text.Attributes.Paragraph.Alignment,
	) -> NSTextAlignment {
		switch alignment {
		case .left: .left
		case .right: .right
		case .center: .center
		case .justified: .justified
		case .natural, .UNRECOGNIZED: .natural
		}
	}

	private static func appKitAlignment(
		_ alignment: Rv_Data_Graphics.Text.Attributes.Paragraph.TabStop.Alignment,
	) -> NSTextAlignment {
		switch alignment {
		case .left: .left
		case .right: .right
		case .center: .center
		case .justified: .justified
		case .natural, .UNRECOGNIZED: .natural
		}
	}

	private static func appKitUnderlineStyle(
		_ value: Rv_Data_Graphics.Text.Attributes.Underline,
	) -> Int {
		var result: NSUnderlineStyle = switch value.style {
		case .none: []
		case .single: .single
		case .thick: .thick
		case .double: .double
		case .UNRECOGNIZED: []
		}
		let pattern: NSUnderlineStyle = switch value.pattern {
		case .solid: []
		case .dot: .patternDot
		case .dash: .patternDash
		case .dashDot: .patternDashDot
		case .dashDotDot: .patternDashDotDot
		case .UNRECOGNIZED: []
		}
		result.formUnion(pattern)
		if value.byWord {
			result.formUnion(.byWord)
		}
		return result.rawValue
	}

	private static func appKitTextList(
		_ value: Rv_Data_Graphics.Text.Attributes.Paragraph.TextList,
	) -> NSTextList {
		let format: NSTextList.MarkerFormat = switch value.numberType {
		case .box: .box
		case .check: .check
		case .circle: .circle
		case .diamond: .diamond
		case .disc: .disc
		case .hyphen: .hyphen
		case .square: .square
		case .decimal: .decimal
		case .lowercaseAlpha: .lowercaseAlpha
		case .uppercaseAlpha: .uppercaseAlpha
		case .lowercaseRoman: .lowercaseRoman
		case .uppercaseRoman: .uppercaseRoman
		case .UNRECOGNIZED: .disc
		}
		return NSTextList(
			markerFormat: format,
			options: [],
			startingItemNumber: Int(value.startingNumber),
		)
	}

	private static func appKitColor(_ color: Rv_Data_Color) -> NSColor {
		NSColor(
			deviceRed: CGFloat(color.red),
			green: CGFloat(color.green),
			blue: CGFloat(color.blue),
			alpha: CGFloat(color.alpha),
		)
	}

	private static func defaultTemplateText() -> Rv_Data_Graphics.Text {
		var text = Rv_Data_Graphics.Text()
		text.attributes.font.name = "HelveticaNeue"
		text.attributes.font.family = "Helvetica Neue"
		text.attributes.font.size = 42
		text.attributes.paragraphStyle.alignment = .center
		text.attributes.paragraphStyle.defaultTabInterval = 84
		text.attributes.paragraphStyle.lineHeightMultiple = 1
		text.attributes.paragraphStyle.textList = Rv_Data_Graphics.Text.Attributes.Paragraph.TextList()
		text.attributes.underlineStyle = Rv_Data_Graphics.Text.Attributes.Underline()
		text.attributes.strikethroughStyle = Rv_Data_Graphics.Text.Attributes.Underline()
		var white = Rv_Data_Color()
		white.red = 1
		white.green = 1
		white.blue = 1
		white.alpha = 1
		text.attributes.textSolidFill = white
		text.isSuperscriptStandardized = true
		text.chordPro.color.red = 0.993
		text.chordPro.color.green = 0.76
		text.chordPro.color.blue = 0.032
		text.chordPro.color.alpha = 1
		text.transformDelimiter = "  •  "
		return text
	}

	private static func clippedMeaningfulCustomAttributes(
		_ attributes: [Rv_Data_Graphics.Text.Attributes.CustomAttribute],
		utf16Length: Int,
	) -> [Rv_Data_Graphics.Text.Attributes.CustomAttribute] {
		attributes.compactMap { source in
			guard source.attribute != nil else { return nil }
			var value = source
			let lower = max(0, min(Int(value.range.start), utf16Length))
			let upper = max(lower, min(Int(value.range.end), utf16Length))
			guard lower < upper else { return nil }
			value.range.start = Int32(lower)
			value.range.end = Int32(upper)
			return value
		}
	}

	private static func meaningfulText(in element: Rv_Data_Graphics.Element) -> Bool {
		guard element.hasText, !element.text.rtfData.isEmpty,
		      let attributed = try? attributedString(from: element.text.rtfData)
		else { return false }
		return !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private static func normalizeKnownMaterializedElementInfo(in slide: inout Rv_Data_Slide) {
		// In both controlled 21.4 materialization paths, the template sequence
		// [1, 2, 3] became [1, 3, 3]. Other values remain unproven, so keep this
		// compatibility rewrite deliberately narrow.
		for index in slide.elements.indices where slide.elements[index].info == 2 {
			slide.elements[index].info = 3
		}
	}

	private static func scaleGeometry(in slide: inout Rv_Data_Slide, x: Double, y: Double) {
		for index in slide.elements.indices {
			slide.elements[index].element.bounds.origin.x *= x
			slide.elements[index].element.bounds.origin.y *= y
			slide.elements[index].element.bounds.size.width *= x
			slide.elements[index].element.bounds.size.height *= y
		}
	}

	private static func unsupportedWarnings(
		for templateSlide: Rv_Data_Slide,
		source: Rv_Data_Slide?,
		xScale: Double,
		yScale: Double,
		mode: TemplateResolutionMode,
	) -> [String] {
		var warnings: [String] = []
		if mode == .instantiateNew, abs(xScale - yScale) > 0.000_001 {
			warnings.append("Aspect-mismatched new-slide scaling has not been isolated in ProPresenter; independent X/Y geometry scaling was used.")
		}
		if templateSlide.elements.contains(where: {
			$0.element.stroke.enable || $0.element.shadow.enable || $0.element.feather.enable
		}) {
			warnings.append("Stroke widths, shadows, and feather radii are preserved without scalar resolution scaling because their ProPresenter behavior is unproven.")
		}
		if templateSlide.elements.contains(where: {
			if case let .media(media)? = $0.element.fill.fillType {
				switch media.typeProperties {
				case let .image(properties): properties.drawing.hasCustomImageBounds
				case let .video(properties): properties.drawing.hasCustomImageBounds
				case let .liveVideo(properties): properties.drawing.hasCustomImageBounds
				case let .webContent(properties): properties.drawing.hasCustomImageBounds
				case .audio, nil: false
				}
			} else {
				false
			}
		}) {
			warnings.append("Media crop/custom-image bounds are preserved without additional scaling because their ProPresenter behavior is unproven.")
		}
		if templateSlide.elements.contains(where: { !$0.dataLinks.isEmpty }) {
			warnings.append("Known intra-slide data-link UUIDs were remapped; runtime data-link resolution itself is not emulated.")
		}
		if hasBuildState(in: templateSlide) {
			warnings.append("Template Build In/Out and Build Order state is retained in the resolved slide; native precedence and remapping behavior are unproven.")
		}
		if hasDeliveryState(in: templateSlide) {
			warnings.append("Template text Delivery state is retained in the resolved slide; native precedence and segmentation behavior are unproven.")
		}
		if let source, hasBuildState(in: source) {
			warnings.append("Source Build In/Out and Build Order state is not transferred; the template slide wrapper remains authoritative. Native precedence and remapping behavior are unproven.")
		}
		if let source, hasDeliveryState(in: source) {
			warnings.append("Source text Delivery state is not transferred; the template slide wrapper remains authoritative. Native precedence and segmentation behavior are unproven.")
		}
		return warnings
	}

	private static func hasBuildState(in slide: Rv_Data_Slide) -> Bool {
		!slide.elementBuildOrder.isEmpty || slide.elements.contains {
			$0.hasBuildIn || $0.hasBuildOut
		}
	}

	private static func hasDeliveryState(in slide: Rv_Data_Slide) -> Bool {
		slide.elements.contains {
			$0.revealType != .none || !$0.childBuilds.isEmpty || $0.revealFromIndex != 0
		}
	}

	private static func containsUnknownFields(in value: Any) -> Bool {
		var visitedObjects = Set<ObjectIdentifier>()
		return containsUnknownFields(in: value, visitedObjects: &visitedObjects)
	}

	private static func containsUnknownFields(
		in value: Any,
		visitedObjects: inout Set<ObjectIdentifier>,
	) -> Bool {
		if let message = value as? any SwiftProtobuf.Message,
		   !message.unknownFields.data.isEmpty
		{
			return true
		}
		let mirror = Mirror(reflecting: value)
		if mirror.displayStyle == .class {
			let identifier = ObjectIdentifier(value as AnyObject)
			guard visitedObjects.insert(identifier).inserted else { return false }
		}
		return mirror.children.contains {
			containsUnknownFields(in: $0.value, visitedObjects: &visitedObjects)
		}
	}

	private static func validate(size: Rv_Data_Graphics.Size, label: String) throws {
		guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
			throw TemplateResolutionError.invalidCanvas(label: label, width: size.width, height: size.height)
		}
	}

	private static func makeReport(
		template: Rv_Data_Template.Slide,
		source: Rv_Data_Slide?,
		result: Rv_Data_Slide,
		destinationSize: CGSize,
		mode: TemplateResolutionMode,
		xScale: Double,
		yScale: Double,
		assignments: [TemplateResolutionReport.Assignment],
		removed: [TemplateResolutionReport.Element],
		unfilled: [TemplateResolutionReport.Element],
		warnings: [String],
	) -> TemplateResolutionReport {
		TemplateResolutionReport(
			mode: mode,
			templateName: template.name,
			sourceSlideUUID: source?.uuid.string,
			templateSlideUUID: template.baseSlide.uuid.string,
			resultSlideUUID: result.uuid.string,
			templateSize: .init(width: template.baseSlide.size.width, height: template.baseSlide.size.height),
			destinationSize: .init(width: destinationSize.width, height: destinationSize.height),
			transform: .init(
				xScale: xScale,
				yScale: yScale,
				fontScale: mode == .instantiateNew ? 1 : yScale,
			),
			assignments: assignments,
			removedSourceElements: removed,
			unfilledTemplateElements: unfilled,
			warnings: Array(Set(warnings)).sorted(),
		)
	}

	private static func reportElement(
		index: Int,
		element: Rv_Data_Graphics.Element,
	) -> TemplateResolutionReport.Element {
		TemplateResolutionReport.Element(
			index: index,
			name: element.name,
			uuid: element.uuid.string,
		)
	}
}

/// Creates identity-safe copies of slide/action graphs and rewrites the known
/// UUID references whose targets are inside the copied graph.
public enum ProPresenterGraphCopier {
	public static func freshSlide(_ source: Rv_Data_Slide) -> Rv_Data_Slide {
		var slide = source
		slide.uuid = freshUUID(preserving: slide.uuid)
		var mapping: [String: Rv_Data_UUID] = [:]
		for index in slide.elements.indices {
			let old = slide.elements[index].element.uuid.string
			let fresh = freshUUID(preserving: slide.elements[index].element.uuid)
			slide.elements[index].element.uuid = fresh
			if !old.isEmpty, mapping[old] == nil {
				mapping[old] = fresh
			}
		}
		for index in slide.guidelines.indices {
			slide.guidelines[index].uuid = freshUUID(preserving: slide.guidelines[index].uuid)
		}
		for index in slide.elements.indices {
			if slide.elements[index].hasBuildIn {
				let old = slide.elements[index].buildIn.uuid.string
				let fresh = freshUUID(preserving: slide.elements[index].buildIn.uuid)
				slide.elements[index].buildIn.uuid = fresh
				if !old.isEmpty, mapping[old] == nil {
					mapping[old] = fresh
				}
			}
			if slide.elements[index].hasBuildOut {
				let old = slide.elements[index].buildOut.uuid.string
				let fresh = freshUUID(preserving: slide.elements[index].buildOut.uuid)
				slide.elements[index].buildOut.uuid = fresh
				if !old.isEmpty, mapping[old] == nil {
					mapping[old] = fresh
				}
			}
			for childIndex in slide.elements[index].childBuilds.indices {
				let old = slide.elements[index].childBuilds[childIndex].uuid.string
				let fresh = freshUUID(preserving: slide.elements[index].childBuilds[childIndex].uuid)
				slide.elements[index].childBuilds[childIndex].uuid = fresh
				if !old.isEmpty, mapping[old] == nil {
					mapping[old] = fresh
				}
			}
		}
		remapInternalReferences(in: &slide, using: mapping)
		return slide
	}

	public static func freshAction(_ source: Rv_Data_Action) -> Rv_Data_Action {
		var action = source
		action.uuid = freshUUID(preserving: action.uuid)
		if case var .presentation(presentationSlide)? = action.slide.slide {
			presentationSlide.baseSlide = freshSlide(presentationSlide.baseSlide)
			for index in presentationSlide.templateGuidelines.indices {
				presentationSlide.templateGuidelines[index].uuid = freshUUID(
					preserving: presentationSlide.templateGuidelines[index].uuid,
				)
			}
			action.slide.presentation = presentationSlide
		} else if case var .prop(propSlide)? = action.slide.slide {
			propSlide.baseSlide = freshSlide(propSlide.baseSlide)
			action.slide.prop = propSlide
		}
		if case .media? = action.actionTypeData {
			var media = action.media
			for markerIndex in media.markers.indices {
				media.markers[markerIndex].uuid = freshUUID(preserving: media.markers[markerIndex].uuid)
				media.markers[markerIndex].actions = media.markers[markerIndex].actions.map(freshAction)
			}
			action.media = media
		}
		return action
	}

	public static func remapInternalReferences(
		in slide: inout Rv_Data_Slide,
		using mapping: [String: Rv_Data_UUID],
	) {
		for index in slide.elementBuildOrder.indices {
			if let replacement = mapping[slide.elementBuildOrder[index].string] {
				slide.elementBuildOrder[index].string = replacement.string
			}
		}
		for elementIndex in slide.elements.indices {
			if slide.elements[elementIndex].hasBuildIn,
			   let replacement = mapping[slide.elements[elementIndex].buildIn.elementUuid.string]
			{
				slide.elements[elementIndex].buildIn.elementUuid.string = replacement.string
			}
			if slide.elements[elementIndex].hasBuildOut,
			   let replacement = mapping[slide.elements[elementIndex].buildOut.elementUuid.string]
			{
				slide.elements[elementIndex].buildOut.elementUuid.string = replacement.string
			}
			for linkIndex in slide.elements[elementIndex].dataLinks.indices {
				var link = slide.elements[elementIndex].dataLinks[linkIndex]
				switch link.propertyType {
				case var .alternateText(value):
					if let replacement = mapping[value.otherElementUuid.string] {
						value.otherElementUuid.string = replacement.string
					}
					link.alternateText = value
				case var .alternateFill(value):
					if let replacement = mapping[value.otherElementUuid.string] {
						value.otherElementUuid.string = replacement.string
					}
					link.alternateFill = value
				case var .visibilityLink(value):
					for conditionIndex in value.conditions.indices {
						if case var .elementVisibility(condition)? = value.conditions[conditionIndex].conditionType,
						   let replacement = mapping[condition.otherElementUuid.string]
						{
							condition.otherElementUuid.string = replacement.string
							value.conditions[conditionIndex].elementVisibility = condition
						}
					}
					link.visibilityLink = value
				case nil, .ticker, .timerText, .clockText, .chordChart, .outputScreen, .pcoLive,
				     .slideText, .stageMessage, .videoCountdown, .slideImage, .ccliText,
				     .groupName, .groupColor, .presentationNotes, .playlistItem,
				     .autoAdvanceTimeRemaining, .captureStatusText, .captureStatusColor,
				     .slideCount, .audioCountdown, .presentation, .slideLabelText,
				     .slideLabelColor, .rssFeed, .fileFeed, .chordProChart,
				     .playbackMarkerText, .playbackMarkerColor, .timecodeText, .timecodeStatus:
					break
				}
				slide.elements[elementIndex].dataLinks[linkIndex] = link
			}
		}
	}

	private static func freshUUID(preserving identifier: Rv_Data_UUID) -> Rv_Data_UUID {
		var result = identifier
		result.string = DocumentFactory.uuid().string
		return result
	}
}
