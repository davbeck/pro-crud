import AppKit
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import ProPresenterProto
import Synchronization
import UniformTypeIdentifiers

public struct RenderOptions: Sendable {
	public var outputDirectory: URL
	public var imageType: ImageType

	public init(outputDirectory: URL, imageType: ImageType = .png) {
		self.outputDirectory = outputDirectory
		self.imageType = imageType
	}

	public enum ImageType: Sendable, Equatable {
		case png
		case jpg
		case heic

		var fileExtension: String {
			switch self {
			case .png: "png"
			case .jpg: "jpg"
			case .heic: "heic"
			}
		}
	}
}

public struct RenderResult: Sendable {
	public var slideCount: Int
	public var outputDirectory: URL
}

public final class PresentationRenderer {
	static let maximumCanvasPixelCount = 100_000_000.0

	private let document: PresentationDocument
	private let fileManager: FileManager

	public init(document: PresentationDocument, fileManager: FileManager = .default) {
		self.document = document
		self.fileManager = fileManager
	}

	public static func effectiveRendering(documents: [PresentationDocument], slideIndices: Set<Int>? = nil) throws -> EffectiveRendering {
		try EffectiveRendering(presentations: documents.map { try PresentationRenderer(document: $0).effectiveRendering(slideIndices: slideIndices) })
	}

	public func effectiveRendering(slideIndices: Set<Int>? = nil) throws -> EffectiveRendering.Presentation {
		let slides = try selectedCues(slideIndices: slideIndices).map { occurrence in
			try validateForRendering(occurrence.cue, storageIndex: occurrence.cueStorageIndex)
			return try effectiveRendering(
				for: occurrence.cue,
				index: occurrence.sequenceIndex,
				storageIndex: occurrence.cueStorageIndex,
				groupUUID: occurrence.groupUUID,
				arrangementGroupOccurrenceIndex: occurrence.arrangementGroupOccurrenceIndex,
			)
		}
		return try EffectiveRendering.Presentation(
			name: document.presentation.name,
			uuid: document.presentation.uuid.string,
			arrangement: document.resolvedArrangement().map {
				EffectiveRendering.Arrangement(name: $0.name, uuid: $0.uuid, path: $0.path)
			},
			slides: slides,
		)
	}

	public func render(options: RenderOptions, slideIndices: Set<Int>? = nil) throws -> RenderResult {
		try fileManager.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)

		let cues = try selectedCues(slideIndices: slideIndices)
		for occurrence in cues {
			try validateForRendering(occurrence.cue, storageIndex: occurrence.cueStorageIndex)
			let image = try renderValidated(cue: occurrence.cue)
			let outputURL = options.outputDirectory.appendingPathComponent("\(occurrence.sequenceIndex + 1).\(options.imageType.fileExtension)")
			try image.data(for: options.imageType).write(to: outputURL)
		}

		return RenderResult(slideCount: cues.count, outputDirectory: options.outputDirectory)
	}

	public func renderPDF(to outputURL: URL, slideIndices: Set<Int>? = nil) throws -> RenderResult {
		try Self.renderPDF(documents: [document], to: outputURL, slideIndices: slideIndices)
	}

	public static func renderPDF(documents: [PresentationDocument], to outputURL: URL, slideIndices: Set<Int>? = nil) throws -> RenderResult {
		let renderers = documents.map { PresentationRenderer(document: $0) }
		let renderInputs = try renderers.map { renderer in
			try (renderer: renderer, cues: renderer.selectedCues(slideIndices: slideIndices))
		}
		guard let firstInput = renderInputs.first(where: { !$0.cues.isEmpty }),
		      let first = firstInput.cues.first
		else {
			throw RenderError.pdfCreationFailed
		}
		let firstRenderer = firstInput.renderer
		try firstRenderer.validateForRendering(first.cue, storageIndex: first.cueStorageIndex)
		var mediaBox = try CGRect(origin: .zero, size: firstRenderer.canvasSize(for: first.cue))
		guard let context = CGContext(outputURL as CFURL, mediaBox: &mediaBox, nil) else {
			throw RenderError.pdfCreationFailed
		}
		defer { context.closePDF() }
		var slideCount = 0
		for input in renderInputs {
			for occurrence in input.cues {
				try input.renderer.validateForRendering(occurrence.cue, storageIndex: occurrence.cueStorageIndex)
				let size = try input.renderer.canvasSize(for: occurrence.cue)
				var pageBox = CGRect(origin: .zero, size: size)
				context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &pageBox, length: MemoryLayout<CGRect>.size)] as CFDictionary)
				let previousContext = NSGraphicsContext.current
				NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
				input.renderer.draw(cue: occurrence.cue, canvasSize: size)
				NSGraphicsContext.current = previousContext
				context.endPDFPage()
				slideCount += 1
			}
		}
		return RenderResult(slideCount: slideCount, outputDirectory: outputURL.deletingLastPathComponent())
	}

	private func selectedCues(slideIndices: Set<Int>?) throws -> [PresentationCueOccurrence] {
		try document.cueOccurrences().filter { occurrence in
			slideIndices?.contains(occurrence.sequenceIndex) ?? true
		}
	}

	public func render(cue: Rv_Data_Cue) throws -> NSBitmapImageRep {
		try validateForRendering(cue)
		return try renderValidated(cue: cue)
	}

	private func renderValidated(cue: Rv_Data_Cue) throws -> NSBitmapImageRep {
		let canvasSize = try canvasSize(for: cue)
		guard let bitmap = NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(canvasSize.width),
			pixelsHigh: Int(canvasSize.height),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0,
		), let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
			throw RenderError.bitmapCreationFailed
		}
		bitmap.size = canvasSize
		bitmap.bitmapData?.initialize(
			repeating: 0,
			count: bitmap.bytesPerRow * bitmap.pixelsHigh,
		)

		let previousContext = NSGraphicsContext.current
		NSGraphicsContext.current = bitmapContext
		defer { NSGraphicsContext.current = previousContext }

		draw(cue: cue, canvasSize: canvasSize)

		return bitmap
	}

	private func canvasSize(for cue: Rv_Data_Cue) throws -> CGSize {
		guard let size = cue.actions.compactMap(\.presentationBaseSlide).first?.size.cgSize else {
			return CGSize(width: 3840, height: 2160)
		}
		guard size.width.isFinite,
		      size.height.isFinite,
		      size.width >= 1,
		      size.height >= 1,
		      size.width * size.height <= Self.maximumCanvasPixelCount
		else {
			if let error = document.renderingDiagnostics(for: cue).first(where: { $0.severity == .error }) {
				throw RenderError.invalidDocument(error)
			}
			throw RenderError.bitmapCreationFailed
		}
		return size
	}

	private func draw(cue: Rv_Data_Cue, canvasSize: CGSize) {
		let slide = cue.actions.compactMap(\.presentationBaseSlide).first
		let canvas = CGRect(origin: .zero, size: canvasSize)
		let context = NSGraphicsContext.current?.cgContext
		context?.saveGState()
		context?.setBlendMode(.copy)
		context?.setFillColor(NSColor.clear.cgColor)
		context?.fill(canvas)
		context?.restoreGState()

		for media in cue.actions.compactMap(\.renderableMedia) {
			draw(media: media, in: CGRect(origin: .zero, size: canvasSize))
		}

		if let slide {
			let hasAlternateTextLinks = slide.elements.contains { slideElement in
				slideElement.dataLinks.contains { dataLink in
					if case .alternateText? = dataLink.propertyType {
						true
					} else {
						false
					}
				}
			}
			for slideElement in slide.elements.reversed() {
				let element = elementResolvingAlternateText(for: slideElement, in: slide)
				let hasAlternateTextLink = slideElement.dataLinks.contains(where: { dataLink in
					if case .alternateText? = dataLink.propertyType {
						true
					} else {
						false
					}
				})
				if hasAlternateTextLink {
					let textVerticalOffset = alternateTextLinkVerticalOffset(
						for: element.text,
					)
					draw(
						element: element,
						canvasSize: canvasSize,
						textVerticalOffset: textVerticalOffset,
					)
					drawAlternateTextLinkOutline(
						around: element,
						canvasSize: canvasSize,
					)
				} else {
					draw(
						element: element,
						canvasSize: canvasSize,
						textVerticalOffset: hasAlternateTextLinks && element.hasText ? 1 : 0,
					)
				}
			}
		}
	}

	private func effectiveRendering(
		for cue: Rv_Data_Cue,
		index: Int,
		storageIndex: Int,
		groupUUID: String?,
		arrangementGroupOccurrenceIndex: Int?,
	) throws -> EffectiveRendering.Slide {
		let canvasSize = try canvasSize(for: cue)
		let canvas = CGRect(origin: .zero, size: canvasSize)
		let cuePath = document.presentation.componentPath(forCueAtStorageIndex: storageIndex)
		let actionIdentities = cue.actions.map(\.uuid.string)
		var layers: [EffectiveRendering.Layer] = []

		for (actionIndex, action) in cue.actions.enumerated() {
			guard let media = action.renderableMedia else { continue }
			let actionPath = ComponentPathBuilder.repeatedPath(
				parent: cuePath,
				field: "actions",
				storageIndex: actionIndex,
				identities: actionIdentities,
			)
			layers.append(EffectiveRendering.Layer(
				index: layers.count,
				sourceIndex: actionIndex,
				kind: "action-media",
				componentPath: actionPath,
				uuid: action.uuid.string,
				name: nonEmpty(action.name.isEmpty ? action.label.text : action.name),
				actionType: String(describing: action.type),
				bounds: renderRect(canvas),
				opacity: nil,
				rotation: nil,
				zOrder: nil,
				alternateTextOutline: nil,
				fill: nil,
				lineFillMask: nil,
				stroke: nil,
				shadow: nil,
				media: mediaDescription(media),
				text: nil,
			))
		}

		if let slideActionIndex = cue.actions.indices.first(where: { cue.actions[$0].presentationBaseSlide != nil }),
		   let slide = cue.actions[slideActionIndex].presentationBaseSlide
		{
			let slidePath = ComponentPathBuilder.repeatedPath(
				parent: cuePath,
				field: "actions",
				storageIndex: slideActionIndex,
				identities: actionIdentities,
			) + "/slide/presentation/base_slide"
			let elementIdentities = slide.elements.map(\.element.uuid.string)
			let hasAlternateTextLinks = slide.elements.contains { slideElement in
				slideElement.dataLinks.contains { dataLink in
					if case .alternateText? = dataLink.propertyType {
						true
					} else {
						false
					}
				}
			}
			for elementIndex in slide.elements.indices.reversed() {
				let slideElement = slide.elements[elementIndex]
				let element = elementResolvingAlternateText(for: slideElement, in: slide)
				guard !element.hidden else { continue }
				let bounds = element.bounds.cgRect.flipped(in: canvasSize)
				guard bounds.width > 0, bounds.height > 0 else { continue }

				let hasAlternateTextLink = slideElement.dataLinks.contains { dataLink in
					if case .alternateText? = dataLink.propertyType {
						true
					} else {
						false
					}
				}
				let textVerticalOffset = hasAlternateTextLink
					? alternateTextLinkVerticalOffset(for: element.text)
					: hasAlternateTextLinks && element.hasText ? 1 : 0
				let text = element.hasText && !element.text.rtfData.isEmpty
					? try textDescription(element.text, in: bounds.offsetBy(dx: 0, dy: textVerticalOffset))
					: nil
				let lineFillMask: Rv_Data_Graphics.Text.LineFillMask? = if case let .textLineMask(mask)? = element.mask, mask.enabled {
					mask
				} else {
					nil
				}
				let drawsAppearance = !(element.mask != nil && element.hasText && element.text.rtfData.isEmpty)
				let elementPath = ComponentPathBuilder.repeatedPath(
					parent: slidePath,
					field: "elements",
					storageIndex: elementIndex,
					identities: elementIdentities,
				) + "/element"
				layers.append(EffectiveRendering.Layer(
					index: layers.count,
					sourceIndex: elementIndex,
					kind: "slide-element",
					componentPath: elementPath,
					uuid: element.uuid.string,
					name: nonEmpty(element.name),
					actionType: nil,
					bounds: renderRect(bounds),
					opacity: nonDefault(element.opacity, default: 1),
					rotation: nonZero(element.rotation.truncatingRemainder(dividingBy: 360)),
					zOrder: slideElement.info == 0 ? nil : Int(slideElement.info),
					alternateTextOutline: hasAlternateTextLink ? true : nil,
					fill: fillDescription(element.fill, enabled: drawsAppearance && element.hasFill && element.fill.enable),
					lineFillMask: lineFillMask.map(lineFillMaskDescription),
					stroke: strokeDescription(element.stroke, enabled: drawsAppearance && element.hasStroke && element.stroke.enable),
					shadow: elementShadowDescription(
						element.shadow,
						enabled: drawsAppearance && element.shadow.enable && !hasVisibleText(element.text),
					),
					media: nil,
					text: text,
				))
			}
		}

		let cueGroup: EffectiveRendering.CueGroup? = groupUUID.flatMap { uuid in
			guard let groupIndex = document.presentation.cueGroups.firstIndex(where: { $0.group.uuid.string == uuid }) else {
				return nil
			}
			let group = document.presentation.cueGroups[groupIndex].group
			return EffectiveRendering.CueGroup(
				name: group.name,
				uuid: uuid,
				path: ComponentPathBuilder.repeatedPath(
					field: "cue_groups",
					storageIndex: groupIndex,
					identities: document.presentation.cueGroups.map(\.group.uuid.string),
				),
				arrangementOccurrenceIndex: arrangementGroupOccurrenceIndex,
			)
		}
		return EffectiveRendering.Slide(
			index: index,
			name: cue.name,
			uuid: cue.uuid.string,
			cueGroup: cueGroup,
			canvasSize: renderSize(canvasSize),
			background: nil,
			layers: layers,
		)
	}

	private func validateForRendering(_ cue: Rv_Data_Cue) throws {
		if let error = document.renderingDiagnostics(for: cue).first(where: { $0.severity == .error }) {
			throw RenderError.invalidDocument(error)
		}
	}

	private func validateForRendering(_ cue: Rv_Data_Cue, storageIndex: Int) throws {
		if let error = document.renderingDiagnostics(forCueAtStorageIndex: storageIndex).first(where: { $0.severity == .error }) {
			throw RenderError.invalidDocument(error)
		}
	}

	private func textDescription(
		_ text: Rv_Data_Graphics.Text,
		in rect: CGRect,
	) throws -> EffectiveRendering.Text? {
		guard let layout = effectiveTextLayout(text: text, in: rect) else { return nil }
		let range = NSRange(location: 0, length: layout.drawnText.length)
		let rtfData = try layout.drawnText.data(
			from: range,
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		)
		let initialFontSize = fontSize(at: 0, in: layout.preparedText)
		let fittedFontSize = fontSize(at: 0, in: layout.fittedText)
		let fontScale = if let initialFontSize, let fittedFontSize, initialFontSize > 0 {
			fittedFontSize / initialFontSize
		} else {
			1.0
		}
		return EffectiveRendering.Text(
			plainText: layout.drawnText.string,
			effectiveRTF: String(decoding: rtfData, as: UTF8.self),
			scaleBehavior: text.scaleBehavior == .none ? nil : String(describing: text.scaleBehavior),
			fontScale: nonDefault(fontScale, default: 1),
			verticalAlignment: text.verticalAlignment == .top ? nil : String(describing: text.verticalAlignment),
			transform: text.transform == .none ? nil : String(describing: text.transform),
			capitalization: text.attributes.capitalization == .none ? nil : String(describing: text.attributes.capitalization),
			margins: insetsDescription(text.margins),
			contentBounds: renderRect(layout.contentRect),
			drawBounds: layout.drawRect == layout.contentRect ? nil : renderRect(layout.drawRect),
			layoutBounds: renderRect(layout.layoutBounds),
			lineCount: nonDefault(textLayoutLineCount(for: layout.drawnText, in: layout.drawRect.size), default: 1),
			runs: textRuns(layout.drawnText),
		)
	}

	private func textRuns(_ attributedString: NSAttributedString) -> [EffectiveRendering.TextRun] {
		var runs: [EffectiveRendering.TextRun] = []
		attributedString.enumerateAttributes(
			in: NSRange(location: 0, length: attributedString.length),
		) { attributes, range, _ in
			let font = attributes[.font] as? NSFont
			let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
			let shadow = attributes[.shadow] as? NSShadow
			runs.append(EffectiveRendering.TextRun(
				location: range.location,
				length: range.length,
				text: (attributedString.string as NSString).substring(with: range),
				font: font.map(fontDescription),
				foregroundColor: (attributes[.foregroundColor] as? NSColor).flatMap(colorDescription),
				backgroundColor: (attributes[.backgroundColor] as? NSColor).flatMap(colorDescription),
				underlineStyle: (attributes[.underlineStyle] as? NSNumber).flatMap { nonZero($0.intValue) },
				strikethroughStyle: (attributes[.strikethroughStyle] as? NSNumber).flatMap { nonZero($0.intValue) },
				strokeWidth: (attributes[.strokeWidth] as? NSNumber).flatMap { nonZero($0.doubleValue) },
				strokeColor: (attributes[.strokeColor] as? NSColor).flatMap(colorDescription),
				kern: (attributes[.kern] as? NSNumber).flatMap { nonZero($0.doubleValue) },
				baselineOffset: (attributes[.baselineOffset] as? NSNumber).flatMap { nonZero($0.doubleValue) },
				paragraph: paragraph.flatMap(paragraphDescription),
				shadow: shadow.map(textShadowDescription),
			))
		}
		return runs
	}

	private func fontSize(at index: Int, in attributedString: NSAttributedString) -> Double? {
		guard attributedString.length > index,
		      let font = attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont
		else {
			return nil
		}
		return font.pointSize
	}

	private func fontDescription(_ font: NSFont) -> EffectiveRendering.Font {
		let traits = font.fontDescriptor.symbolicTraits
		return EffectiveRendering.Font(
			postscriptName: font.fontName,
			familyName: font.familyName,
			pointSize: font.pointSize,
			bold: traits.contains(.bold) ? true : nil,
			italic: traits.contains(.italic) ? true : nil,
		)
	}

	private func paragraphDescription(_ paragraph: NSParagraphStyle) -> EffectiveRendering.Paragraph? {
		let alignment = switch paragraph.alignment {
		case .left: "left"
		case .right: "right"
		case .center: "center"
		case .justified: "justified"
		case .natural: "natural"
		@unknown default: "unknown"
		}
		let description = EffectiveRendering.Paragraph(
			alignment: alignment == "natural" ? nil : alignment,
			lineSpacing: nonZero(paragraph.lineSpacing),
			paragraphSpacing: nonZero(paragraph.paragraphSpacing),
			paragraphSpacingBefore: nonZero(paragraph.paragraphSpacingBefore),
			firstLineHeadIndent: nonZero(paragraph.firstLineHeadIndent),
			headIndent: nonZero(paragraph.headIndent),
			tailIndent: nonZero(paragraph.tailIndent),
			minimumLineHeight: nonZero(paragraph.minimumLineHeight),
			maximumLineHeight: nonZero(paragraph.maximumLineHeight),
			lineHeightMultiple: nonZero(paragraph.lineHeightMultiple),
		)
		return description.hasValues ? description : nil
	}

	private func colorDescription(_ color: NSColor) -> EffectiveRendering.Color? {
		guard let color = color.usingColorSpace(.sRGB) else { return nil }
		return EffectiveRendering.Color(
			red: nonZero(color.redComponent),
			green: nonZero(color.greenComponent),
			blue: nonZero(color.blueComponent),
			alpha: nonDefault(color.alphaComponent, default: 1),
		)
	}

	private func colorDescription(
		_ color: Rv_Data_Color,
		alpha: Double? = nil,
	) -> EffectiveRendering.Color {
		EffectiveRendering.Color(
			red: nonZero(Double(color.red)),
			green: nonZero(Double(color.green)),
			blue: nonZero(Double(color.blue)),
			alpha: nonDefault(alpha ?? Double(color.alpha), default: 1),
		)
	}

	private func textShadowDescription(_ shadow: NSShadow) -> EffectiveRendering.Shadow {
		EffectiveRendering.Shadow(
			color: shadow.shadowColor.flatMap(colorDescription),
			offset: shadow.shadowOffset == .zero ? nil : renderSize(shadow.shadowOffset),
			blurRadius: nonZero(shadow.shadowBlurRadius),
		)
	}

	private func elementShadowDescription(
		_ shadow: Rv_Data_Graphics.Shadow,
		enabled: Bool,
	) -> EffectiveRendering.Shadow? {
		guard enabled else { return nil }
		let radians = CGFloat(shadow.angle * .pi / 180)
		let color = colorDescription(
			shadow.color,
			alpha: Double(shadow.color.alpha) * shadow.opacity,
		)
		let offset = CGSize(
			width: cos(radians) * shadow.offset,
			height: sin(radians) * shadow.offset,
		)
		return EffectiveRendering.Shadow(
			color: color,
			offset: offset == .zero ? nil : renderSize(offset),
			blurRadius: nonZero(shadow.radius),
		)
	}

	private func fillDescription(
		_ fill: Rv_Data_Graphics.Fill,
		enabled: Bool,
	) -> EffectiveRendering.Fill? {
		guard enabled else { return nil }
		return switch fill.fillType {
		case let .color(color) where color.alpha > 0:
			EffectiveRendering.Fill(kind: "color", color: colorDescription(color), media: nil)
		case let .media(media):
			EffectiveRendering.Fill(kind: "media", color: nil, media: mediaDescription(media))
		case .color, .gradient, .backgroundEffect, .none:
			nil
		}
	}

	private func strokeDescription(
		_ stroke: Rv_Data_Graphics.Stroke,
		enabled: Bool,
	) -> EffectiveRendering.Stroke? {
		guard enabled, stroke.width > 0, stroke.color.alpha > 0 else { return nil }
		let pattern: [Double] = if !stroke.pattern.isEmpty {
			stroke.pattern
		} else {
			switch stroke.style {
			case .solidLine, .UNRECOGNIZED: []
			case .squareDash: [stroke.width, stroke.width]
			case .shortDash: [stroke.width * 2, stroke.width * 2]
			case .longDash: [stroke.width * 4, stroke.width * 2]
			}
		}
		return EffectiveRendering.Stroke(
			width: stroke.width,
			color: colorDescription(stroke.color),
			pattern: pattern.isEmpty ? nil : pattern,
		)
	}

	private func lineFillMaskDescription(
		_ mask: Rv_Data_Graphics.Text.LineFillMask,
	) -> EffectiveRendering.LineFillMask {
		EffectiveRendering.LineFillMask(
			style: mask.maskStyle == .fullWidth ? nil : String(describing: mask.maskStyle),
			heightOffset: nonZero(mask.heightOffset),
			verticalOffset: nonZero(mask.verticalOffset),
			widthOffset: nonZero(mask.widthOffset),
			horizontalOffset: nonZero(mask.horizontalOffset),
		)
	}

	private func mediaDescription(_ media: Rv_Data_Media) -> EffectiveRendering.Media {
		let type = switch media.typeProperties {
		case .audio?: "audio"
		case .image?: "image"
		case .video?: "video"
		case .liveVideo?: "live-video"
		case .webContent?: "web-content"
		case nil: "unknown"
		}
		return EffectiveRendering.Media(
			source: nonEmpty(media.url.renderPath),
			resolvedSource: resolvedURL(for: media)?.path,
			type: type == "unknown" ? nil : type,
		)
	}

	private func insetsDescription(
		_ insets: Rv_Data_Graphics.EdgeInsets,
	) -> EffectiveRendering.Insets? {
		let description = EffectiveRendering.Insets(
			top: nonZero(insets.top),
			left: nonZero(insets.left),
			bottom: nonZero(insets.bottom),
			right: nonZero(insets.right),
		)
		return description.hasValues ? description : nil
	}

	private func nonEmpty(_ value: String) -> String? {
		value.isEmpty ? nil : value
	}

	private func nonZero(_ value: Double) -> Double? {
		abs(value) < 0.000_001 ? nil : value
	}

	private func nonZero(_ value: Int) -> Int? {
		value == 0 ? nil : value
	}

	private func nonDefault(_ value: Double, default defaultValue: Double) -> Double? {
		abs(value - defaultValue) < 0.000_001 ? nil : value
	}

	private func nonDefault(_ value: Int, default defaultValue: Int) -> Int? {
		value == defaultValue ? nil : value
	}

	private func renderRect(_ rect: CGRect) -> EffectiveRendering.Rect {
		EffectiveRendering.Rect(
			x: nonZero(rect.origin.x),
			y: nonZero(rect.origin.y),
			width: rect.width,
			height: rect.height,
		)
	}

	private func renderSize(_ size: CGSize) -> EffectiveRendering.Size {
		EffectiveRendering.Size(width: size.width, height: size.height)
	}

	private func drawAlternateTextLinkOutline(
		around element: Rv_Data_Graphics.Element,
		canvasSize: CGSize,
	) {
		let rect = element.bounds.cgRect.flipped(in: canvasSize)
		guard rect.width > 0, rect.height > 0 else { return }

		NSColor(
			srgbRed: 131 / 255,
			green: 132 / 255,
			blue: 37 / 255,
			alpha: 1,
		).setStroke()
		let outline = NSBezierPath(rect: rect)
		outline.lineWidth = 2
		outline.stroke()
	}

	private func alternateTextLinkVerticalOffset(for text: Rv_Data_Graphics.Text) -> CGFloat {
		guard let attributedString = attributedString(from: text) else {
			return 1
		}
		return attributedString.string.contains("\n") ? 5 : 1
	}

	private func elementResolvingAlternateText(
		for slideElement: Rv_Data_Slide.Element,
		in slide: Rv_Data_Slide,
	) -> Rv_Data_Graphics.Element {
		let element = slideElement.element
		guard let link = alternateTextLink(in: slideElement) else {
			return element
		}
		let source = slide.elements.first {
			$0.element.uuid.string == link.otherElementUuid.string
		}?.element
		guard let source,
		      source.hasText,
		      element.hasText,
		      let sourceText = attributedString(from: source.text),
		      let resolvedText = alternateText(sourceText.string, applying: link.textTransform),
		      let targetText = attributedString(from: element.text),
		      targetText.length > 0
		else {
			return element
		}

		let replacement = NSMutableAttributedString(attributedString: targetText)
		replacement.replaceCharacters(
			in: NSRange(location: 0, length: replacement.length),
			with: resolvedText,
		)
		guard let rtfData = try? replacement.data(
			from: NSRange(location: 0, length: replacement.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
		) else {
			return element
		}

		var resolvedElement = element
		resolvedElement.text.rtfData = rtfData
		return resolvedElement
	}

	private func alternateTextLink(
		in slideElement: Rv_Data_Slide.Element,
	) -> Rv_Data_Slide.Element.DataLink.AlternateElementText? {
		for dataLink in slideElement.dataLinks {
			guard case let .alternateText(link)? = dataLink.propertyType else { continue }
			return link
		}
		return nil
	}

	private func attributedString(from text: Rv_Data_Graphics.Text) -> NSAttributedString? {
		decodedText(from: text)?.attributedString
	}

	private func decodedText(from text: Rv_Data_Graphics.Text) -> DecodedText? {
		ProcessFontRegistry.registerFonts(referencedByRTF: text.rtfData)
		let restoredRTF = restoringListTextDestinations(in: text.rtfData)
		guard let attributedString = try? NSMutableAttributedString(
			data: restoredRTF.data,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		) else {
			return nil
		}
		return DecodedText(
			attributedString: attributedString,
			hasRestoredNativeListText: restoredRTF.didRestore,
		)
	}

	private func restoringListTextDestinations(in rtfData: Data) -> RestoredListTextRTF {
		guard let rtf = String(data: rtfData, encoding: .utf8) else {
			return RestoredListTextRTF(data: rtfData, didRestore: false)
		}
		// AppKit suppresses `listtext` destinations, even though they contain the
		// marker's formatting and its two native tab stops.
		let restored = rtf
			.replacingOccurrences(of: "{\\*\\listtext", with: "{")
			.replacingOccurrences(of: "{\\listtext", with: "{")
		return RestoredListTextRTF(
			data: Data(restored.utf8),
			didRestore: restored != rtf,
		)
	}

	private func alternateText(
		_ text: String,
		applying transform: Rv_Data_Slide.Element.DataLink.AlternateElementText.TextTransformOption,
	) -> String? {
		switch transform {
		case .none:
			text
		case .removeLineReturns:
			text
				.replacingOccurrences(of: "\r\n", with: " ")
				.replacingOccurrences(of: "\r", with: " ")
				.replacingOccurrences(of: "\n", with: " ")
		case .oneWordPerLine, .oneCharacterPerLine, .UNRECOGNIZED:
			nil
		}
	}

	private func draw(
		element: Rv_Data_Graphics.Element,
		canvasSize: CGSize,
		textVerticalOffset: CGFloat = 0,
	) {
		guard !element.hidden else { return }

		let rect = element.bounds.cgRect.flipped(in: canvasSize)
		guard rect.width > 0, rect.height > 0 else { return }

		NSGraphicsContext.saveGraphicsState()
		defer { NSGraphicsContext.restoreGraphicsState() }

		let hasElementOpacity = element.opacity < 1
		if !element.hasText, hasElementOpacity {
			NSGraphicsContext.current?.cgContext.setAlpha(element.opacity)
		}

		let rotation = element.rotation.truncatingRemainder(dividingBy: 360)
		if rotation != 0 {
			let context = NSGraphicsContext.current?.cgContext
			context?.translateBy(x: rect.midX, y: rect.midY)
			context?.rotate(by: CGFloat(rotation * .pi / 180))
			context?.translateBy(x: -rect.midX, y: -rect.midY)
		}

		let appearanceRect = adjustedTextContainerRect(for: element.text, in: rect) ?? rect

		let hasTextLineMask = element.mask != nil
		let lineFillMask: Rv_Data_Graphics.Text.LineFillMask? = if case let .textLineMask(mask)? = element.mask, mask.enabled {
			mask
		} else {
			nil
		}
		let isEmptyTextLineMaskElement = hasTextLineMask && element.hasText && element.text.rtfData.isEmpty
		if element.hasText, hasElementOpacity {
			NSGraphicsContext.saveGraphicsState()
			NSGraphicsContext.current?.cgContext.setAlpha(element.opacity)
		}
		let drawsElementAppearance = !isEmptyTextLineMaskElement
		if !hasVisibleText(element.text), element.shadow.enable, drawsElementAppearance {
			drawElementAppearance(
				element,
				in: appearanceRect,
				canvasSize: canvasSize,
				lineFillMask: lineFillMask,
				withShadow: true,
			)
		} else if drawsElementAppearance {
			drawElementAppearance(
				element,
				in: appearanceRect,
				canvasSize: canvasSize,
				lineFillMask: lineFillMask,
			)
		}
		if element.hasText, hasElementOpacity {
			NSGraphicsContext.restoreGraphicsState()
		}
		if element.hasText, !element.text.rtfData.isEmpty {
			draw(
				text: element.text,
				in: rect.offsetBy(dx: 0, dy: textVerticalOffset),
				lineFill: element.hasFill && element.fill.enable ? element.fill : nil,
				lineFillMask: lineFillMask,
			)
		}
	}

	private func adjustedTextContainerRect(
		for text: Rv_Data_Graphics.Text,
		in elementRect: CGRect,
	) -> CGRect? {
		guard text.scaleBehavior == .adjustContainerHeight else {
			return nil
		}
		guard let decodedText = decodedText(from: text),
		      decodedText.attributedString.length > 0
		else {
			return nil
		}
		let attributedString = decodedText.attributedString

		applyCustomFontMetadata(from: text.attributes, to: attributedString)
		applyTextTransform(from: text, to: attributedString)
		applyCustomCapitalization(from: text.attributes, to: attributedString)
		applyTextListMarkers(
			to: attributedString,
			hasRestoredNativeListText: decodedText.hasRestoredNativeListText,
		)
		normalizeFonts(in: attributedString)
		if text.isSuperscriptStandardized {
			standardizeSuperscripts(in: attributedString)
		}
		includeFontLeadingInLineSpacing(in: attributedString)

		let margins = text.margins
		let textRect = elementRect
			.insetBy(
				dx: CGFloat(margins.left + margins.right) / 2,
				dy: CGFloat(margins.top + margins.bottom) / 2,
			)
			.offsetBy(
				dx: CGFloat(margins.left - margins.right) / 2,
				dy: CGFloat(margins.top - margins.bottom) / 2,
			)
			.insetBy(dx: 5, dy: 5)
		let used = textLayoutBounds(
			for: attributedString,
			in: CGSize(width: textRect.width, height: .greatestFiniteMagnitude),
		)
		let contentHeight = ceil(used.height) + CGFloat(margins.top + margins.bottom) + 10
		guard contentHeight != elementRect.height else { return nil }

		return CGRect(
			x: elementRect.minX,
			y: elementRect.maxY - contentHeight,
			width: elementRect.width,
			height: contentHeight,
		)
	}

	private func hasVisibleText(_ text: Rv_Data_Graphics.Text) -> Bool {
		guard !text.rtfData.isEmpty,
		      let attributedString = attributedString(from: text)
		else {
			return false
		}
		return attributedString.length > 0
	}

	private func drawElementAppearance(
		_ element: Rv_Data_Graphics.Element,
		in rect: CGRect,
		canvasSize: CGSize,
		lineFillMask: Rv_Data_Graphics.Text.LineFillMask?,
		withShadow: Bool = false,
	) {
		let feather = element.feather
		if element.hasFeather, feather.enable, feather.radius > 0 {
			drawFeatheredElementAppearance(
				element,
				in: rect,
				canvasSize: canvasSize,
				lineFillMask: lineFillMask,
				withShadow: withShadow,
			)
			return
		}

		let path = drawingPath(for: element.path, in: rect)
		drawRawElementAppearance(
			element,
			in: rect,
			canvasSize: canvasSize,
			path: path,
			lineFillMask: lineFillMask,
			withShadow: withShadow,
		)
	}

	private func drawFeatheredElementAppearance(
		_ element: Rv_Data_Graphics.Element,
		in rect: CGRect,
		canvasSize: CGSize,
		lineFillMask: Rv_Data_Graphics.Text.LineFillMask?,
		withShadow: Bool,
	) {
		let radius = CGFloat(element.feather.radius) * min(rect.width, rect.height)
		guard radius > 0 else { return }

		let padding = ceil(radius * 3)
		let destinationOrigin = CGPoint(x: floor(rect.minX) - padding, y: floor(rect.minY) - padding)
		let localOrigin = CGPoint(x: rect.minX - destinationOrigin.x, y: rect.minY - destinationOrigin.y)
		let imageSize = CGSize(width: ceil(localOrigin.x + rect.width + padding), height: ceil(localOrigin.y + rect.height + padding))
		guard let bitmap = NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(imageSize.width),
			pixelsHigh: Int(imageSize.height),
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 0,
			bitsPerPixel: 0,
		), let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
			return
		}
		bitmap.size = imageSize
		bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)

		let localRect = CGRect(origin: localOrigin, size: rect.size)
		let previousContext = NSGraphicsContext.current
		NSGraphicsContext.current = bitmapContext
		drawRawElementAppearance(
			element,
			in: localRect,
			canvasSize: canvasSize,
			path: drawingPath(for: element.path, in: localRect),
			lineFillMask: lineFillMask,
			withShadow: withShadow,
		)
		NSGraphicsContext.current = previousContext

		guard let sourceImage = bitmap.cgImage else { return }
		let source = CIImage(cgImage: sourceImage)
		// ProPresenter's normalized radius maps to an inset mask followed by a softer blur.
		let insetRadius = max(1, Int(radius.rounded()))
		let blurRadius = radius * 0.49
		let inset = source.applyingFilter(
			"CIMorphologyMinimum",
			parameters: [kCIInputRadiusKey: insetRadius],
		)
		let blurred = inset
			.clampedToExtent()
			.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
			.cropped(to: source.extent)
		let feathered = source.applyingFilter(
			"CISourceInCompositing",
			parameters: [kCIInputBackgroundImageKey: blurred],
		)
		guard let image = CIContext().createCGImage(feathered, from: source.extent) else { return }
		NSGraphicsContext.current?.cgContext.draw(
			image,
			in: CGRect(origin: destinationOrigin, size: imageSize),
		)
	}

	private func drawRawElementAppearance(
		_ element: Rv_Data_Graphics.Element,
		in rect: CGRect,
		canvasSize: CGSize,
		path: NSBezierPath,
		lineFillMask: Rv_Data_Graphics.Text.LineFillMask?,
		withShadow: Bool,
	) {
		let context = NSGraphicsContext.current?.cgContext
		if withShadow {
			let shadow = element.shadow
			let radians = CGFloat(shadow.angle * .pi / 180)
			context?.saveGState()
			context?.setShadow(
				offset: CGSize(
					width: cos(radians) * CGFloat(shadow.offset),
					height: sin(radians) * CGFloat(shadow.offset),
				),
				blur: CGFloat(shadow.radius),
				color: shadow.color.nsColor.withAlphaComponent(
					CGFloat(shadow.color.alpha) * CGFloat(shadow.opacity),
				).cgColor,
			)
			context?.beginTransparencyLayer(auxiliaryInfo: nil)
		}

		if element.hasFill, element.fill.enable, lineFillMask == nil {
			draw(fill: element.fill, in: rect, canvasSize: canvasSize, path: path)
		}
		if element.hasStroke, element.stroke.enable {
			draw(stroke: element.stroke, along: path)
		}

		if withShadow {
			context?.endTransparencyLayer()
			context?.restoreGState()
		}
	}

	private func draw(
		fill: Rv_Data_Graphics.Fill,
		in rect: CGRect,
		canvasSize: CGSize,
		path: NSBezierPath? = nil,
	) {
		switch fill.fillType {
		case let .color(color):
			guard color.alpha > 0 else { return }
			color.nsColor.setFill()
			let fillPath = path ?? NSBezierPath(rect: rect)
			fillPath.fill()
		case let .media(media):
			NSGraphicsContext.saveGraphicsState()
			path?.addClip()
			draw(media: media, in: rect)
			NSGraphicsContext.restoreGraphicsState()
		case .gradient, .backgroundEffect, .none:
			break
		}
	}

	private func draw(stroke: Rv_Data_Graphics.Stroke, along path: NSBezierPath) {
		guard stroke.width > 0, stroke.color.alpha > 0 else { return }

		let strokedPath = path.copy() as? NSBezierPath ?? path
		strokedPath.lineWidth = CGFloat(stroke.width)
		strokedPath.lineJoinStyle = .miter
		strokedPath.lineCapStyle = .butt

		let pattern = stroke.pattern.map { CGFloat($0) }
		if !pattern.isEmpty {
			strokedPath.setLineDash(pattern, count: pattern.count, phase: 0)
		} else {
			switch stroke.style {
			case .solidLine:
				break
			case .squareDash:
				let width = CGFloat(stroke.width)
				strokedPath.setLineDash([width, width], count: 2, phase: 0)
			case .shortDash:
				let width = CGFloat(stroke.width)
				strokedPath.setLineDash([width * 2, width * 2], count: 2, phase: 0)
			case .longDash:
				let width = CGFloat(stroke.width)
				strokedPath.setLineDash([width * 4, width * 2], count: 2, phase: 0)
			case .UNRECOGNIZED:
				break
			}
		}

		stroke.color.nsColor.setStroke()
		strokedPath.stroke()
	}

	private func drawingPath(for path: Rv_Data_Graphics.Path, in rect: CGRect) -> NSBezierPath {
		switch path.shape.type {
		case .rectangle, .unknown, .UNRECOGNIZED:
			return NSBezierPath(rect: rect)
		case .ellipse:
			return NSBezierPath(ovalIn: rect)
		case .isoscelesTriangle:
			return polygonPath(
				points: [CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)],
				in: rect,
			)
		case .rightTriangle:
			return polygonPath(
				points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)],
				in: rect,
			)
		case .rhombus:
			return polygonPath(
				points: [
					CGPoint(x: 0.5, y: 0),
					CGPoint(x: 1, y: 0.5),
					CGPoint(x: 0.5, y: 1),
					CGPoint(x: 0, y: 0.5),
				],
				in: rect,
			)
		case .roundedRectangle:
			let radius = min(rect.width, rect.height) * CGFloat(path.shape.roundedRectangle.roundness)
			return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
		case .polygon:
			return regularPolygonPath(sides: Int(path.shape.polygon.numberSides), in: rect)
		case .star:
			return starPath(
				points: Int(path.shape.star.numberPoints),
				innerRadius: CGFloat(path.shape.star.innerRadius),
				in: rect,
			)
		case .custom, .rightArrow, .doubleArrow:
			return bezierPath(from: path, in: rect) ?? NSBezierPath(rect: rect)
		}
	}

	private func polygonPath(points: [CGPoint], in rect: CGRect) -> NSBezierPath {
		let path = NSBezierPath()
		for (index, point) in points.enumerated() {
			let mapped = CGPoint(
				x: rect.minX + point.x * rect.width,
				y: rect.maxY - point.y * rect.height,
			)
			if index == 0 {
				path.move(to: mapped)
			} else {
				path.line(to: mapped)
			}
		}
		path.close()
		return path
	}

	private func regularPolygonPath(sides: Int, in rect: CGRect) -> NSBezierPath {
		guard sides >= 3 else { return NSBezierPath(rect: rect) }
		let points = (0 ..< sides).map { index in
			let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(sides)
			return CGPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
		}
		return polygonPath(points: points, in: rect)
	}

	private func starPath(points: Int, innerRadius: CGFloat, in rect: CGRect) -> NSBezierPath {
		guard points >= 2 else { return NSBezierPath(rect: rect) }
		let vertices = (0 ..< (points * 2)).map { index in
			let radius: CGFloat = index.isMultiple(of: 2) ? 0.5 : innerRadius * 0.5
			let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(points)
			return CGPoint(x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
		}
		return polygonPath(points: vertices, in: rect)
	}

	private func bezierPath(from path: Rv_Data_Graphics.Path, in rect: CGRect) -> NSBezierPath? {
		guard let first = path.points.first else { return nil }

		func mapped(_ point: Rv_Data_Graphics.Point) -> CGPoint {
			CGPoint(
				x: rect.minX + CGFloat(point.x) * rect.width,
				y: rect.maxY - CGFloat(point.y) * rect.height,
			)
		}

		let result = NSBezierPath()
		result.move(to: mapped(first.point))
		for index in path.points.indices.dropFirst() {
			let previous = path.points[index - 1]
			let current = path.points[index]
			if previous.curved || current.curved {
				result.curve(
					to: mapped(current.point),
					controlPoint1: mapped(previous.q1),
					controlPoint2: mapped(current.q0),
				)
			} else {
				result.line(to: mapped(current.point))
			}
		}
		if path.closed {
			result.close()
		}
		return result
	}

	private func draw(media: Rv_Data_Media, in destination: CGRect) {
		guard let mediaURL = resolvedURL(for: media) else { return }

		if mediaURL.pathExtension.lowercased() == "m4v" || mediaURL.pathExtension.lowercased() == "mp4" || mediaURL.pathExtension.lowercased() == "mov" {
			let imageTime = media.video.video.thumbnailPosition < 0
				? 5
				: media.video.video.thumbnailPosition
			guard let image = frameImage(from: mediaURL, at: imageTime) else { return }
			draw(image: image.retaggedAsSRGB ?? image, with: media.video.drawing, in: destination)
			return
		}

		let image = NSImage(contentsOf: mediaURL)
		guard let image else { return }
		draw(image: image, with: media.image.drawing, in: destination)
	}

	private func draw(
		image: CGImage,
		with drawing: Rv_Data_Media.DrawingProperties,
		in destination: CGRect,
	) {
		let image = NSImage(cgImage: image, size: .zero)
		draw(image: image, with: drawing, in: destination)
	}

	private func draw(
		image: NSImage,
		with drawing: Rv_Data_Media.DrawingProperties,
		in destination: CGRect,
	) {
		let sourceSize = image.size
		guard sourceSize.width > 0, sourceSize.height > 0 else { return }

		let cropInsets = drawing.cropInsets
		let sourceRect: CGRect
		if drawing.cropEnable {
			let left = CGFloat(cropInsets.left)
			let right = CGFloat(cropInsets.right)
			let top = CGFloat(cropInsets.top)
			let bottom = CGFloat(cropInsets.bottom)
			switch drawing.nativeRotation {
			case .rotate90:
				sourceRect = CGRect(
					x: top,
					y: right,
					width: max(0, sourceSize.width - top - bottom),
					height: max(0, sourceSize.height - left - right),
				)
			case .rotate270:
				sourceRect = CGRect(
					x: bottom,
					y: right,
					width: max(0, sourceSize.width - top - bottom),
					height: max(0, sourceSize.height - left - right),
				)
			case .rotateStandard, .rotate180, .UNRECOGNIZED:
				sourceRect = CGRect(
					x: left,
					y: bottom,
					width: max(0, sourceSize.width - left - right),
					height: max(0, sourceSize.height - top - bottom),
				)
			}
		} else {
			sourceRect = CGRect(origin: .zero, size: sourceSize)
		}
		guard sourceRect.width > 0, sourceRect.height > 0 else { return }

		let quarterTurn = drawing.nativeRotation == .rotate90 || drawing.nativeRotation == .rotate270
		let orientedSize = quarterTurn
			? CGSize(width: sourceRect.height, height: sourceRect.width)
			: sourceRect.size
		let mediaLayoutSize = CGSize(
			width: ceil(orientedSize.width / 2) * 2,
			height: ceil(orientedSize.height / 2) * 2,
		)
		let target = mediaRect(
			for: mediaLayoutSize,
			in: destination,
			scaleBehavior: drawing.scaleBehavior,
			alignment: drawing.scaleAlignment,
		)

		NSGraphicsContext.saveGraphicsState()
		defer { NSGraphicsContext.restoreGraphicsState() }

		let context = NSGraphicsContext.current?.cgContext
		context?.clip(to: target)
		context?.translateBy(x: target.midX, y: target.midY)
		context?.scaleBy(x: target.width / orientedSize.width, y: target.height / orientedSize.height)
		switch drawing.nativeRotation {
		case .rotate90:
			context?.rotate(by: .pi / 2)
		case .rotate180:
			context?.rotate(by: .pi)
		case .rotate270:
			context?.rotate(by: -.pi / 2)
		case .rotateStandard, .UNRECOGNIZED:
			break
		}
		context?.scaleBy(
			x: drawing.flippedHorizontally ? -1 : 1,
			y: drawing.flippedVertically ? -1 : 1,
		)
		image.draw(
			in: CGRect(
				x: -sourceRect.width / 2,
				y: -sourceRect.height / 2,
				width: sourceRect.width,
				height: sourceRect.height,
			),
			from: sourceRect,
			operation: .sourceOver,
			fraction: 1,
		)
	}

	private func mediaRect(
		for sourceSize: CGSize,
		in destination: CGRect,
		scaleBehavior: Rv_Data_Media.DrawingProperties.ScaleBehavior,
		alignment: Rv_Data_Media.DrawingProperties.ScaleAlignment,
	) -> CGRect {
		let scale: CGFloat
		switch scaleBehavior {
		case .stretch:
			return destination
		case .fill:
			scale = max(destination.width / sourceSize.width, destination.height / sourceSize.height)
		case .fit, .custom, .UNRECOGNIZED:
			scale = min(destination.width / sourceSize.width, destination.height / sourceSize.height)
		}

		let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
		let origin: CGPoint
		switch alignment {
		case .topLeft:
			origin = CGPoint(x: destination.minX, y: destination.maxY - size.height)
		case .topCenter:
			origin = CGPoint(x: destination.midX - size.width / 2, y: destination.maxY - size.height)
		case .topRight:
			origin = CGPoint(x: destination.maxX - size.width, y: destination.maxY - size.height)
		case .middleRight:
			origin = CGPoint(x: destination.maxX - size.width, y: destination.midY - size.height / 2)
		case .bottomRight:
			origin = CGPoint(x: destination.maxX - size.width, y: destination.minY)
		case .bottomCenter:
			origin = CGPoint(x: destination.midX - size.width / 2, y: destination.minY)
		case .bottomLeft:
			origin = CGPoint(x: destination.minX, y: destination.minY)
		case .middleLeft:
			origin = CGPoint(x: destination.minX, y: destination.midY - size.height / 2)
		case .middleCenter, .UNRECOGNIZED:
			origin = CGPoint(x: destination.midX - size.width / 2, y: destination.midY - size.height / 2)
		}
		return CGRect(origin: origin, size: size)
	}

	private func draw(image: NSImage, in destination: CGRect) {
		guard let source = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
		      source.pixelsWide == Int(destination.width),
		      abs(source.pixelsHigh - Int(destination.height)) <= 1,
		      let intermediate = NSBitmapImageRep(
		      	bitmapDataPlanes: nil,
		      	pixelsWide: source.pixelsWide / 2,
		      	pixelsHigh: source.pixelsHigh / 2,
		      	bitsPerSample: 8,
		      	samplesPerPixel: 4,
		      	hasAlpha: true,
		      	isPlanar: false,
		      	colorSpaceName: .deviceRGB,
		      	bytesPerRow: 0,
		      	bitsPerPixel: 0,
		      ),
		      let intermediateContext = NSGraphicsContext(bitmapImageRep: intermediate)
		else {
			image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1)
			return
		}

		let previousContext = NSGraphicsContext.current
		NSGraphicsContext.current = intermediateContext
		image.draw(
			in: CGRect(x: 0, y: 0, width: intermediate.pixelsWide, height: intermediate.pixelsHigh),
			from: .zero,
			operation: .sourceOver,
			fraction: 1,
		)
		NSGraphicsContext.current = previousContext

		let previousInterpolation = NSGraphicsContext.current?.imageInterpolation
		NSGraphicsContext.current?.imageInterpolation = .low
		intermediate.draw(in: destination)
		NSGraphicsContext.current?.imageInterpolation = previousInterpolation ?? .default
	}

	private struct EffectiveTextLayout {
		var preparedText: NSAttributedString
		var fittedText: NSAttributedString
		var drawnText: NSAttributedString
		var contentRect: CGRect
		var drawRect: CGRect
		var layoutBounds: CGRect
		var centeredCorrection: CGFloat
	}

	private func draw(
		text: Rv_Data_Graphics.Text,
		in elementRect: CGRect,
		lineFill: Rv_Data_Graphics.Fill? = nil,
		lineFillMask: Rv_Data_Graphics.Text.LineFillMask? = nil,
	) {
		guard let layout = effectiveTextLayout(text: text, in: elementRect) else { return }

		if let lineFill, let lineFillMask {
			drawLineFills(
				for: layout.fittedText,
				in: layout.drawRect,
				elementBounds: elementRect,
				centeredCorrection: layout.centeredCorrection,
				fill: lineFill,
				mask: lineFillMask,
			)
		}

		drawAttributedText(layout.drawnText, in: layout.drawRect)
	}

	private func effectiveTextLayout(
		text: Rv_Data_Graphics.Text,
		in elementRect: CGRect,
	) -> EffectiveTextLayout? {
		guard let decodedText = decodedText(from: text),
		      decodedText.attributedString.length > 0
		else {
			return nil
		}
		let attributedString = decodedText.attributedString

		applyCustomFontMetadata(from: text.attributes, to: attributedString)
		applyTextTransform(from: text, to: attributedString)
		applyCustomCapitalization(from: text.attributes, to: attributedString)
		applyTextListMarkers(
			to: attributedString,
			hasRestoredNativeListText: decodedText.hasRestoredNativeListText,
		)
		normalizeFonts(in: attributedString)
		if text.isSuperscriptStandardized {
			standardizeSuperscripts(in: attributedString)
		}
		if text.scaleBehavior == .adjustContainerHeight {
			includeFontLeadingInLineSpacing(in: attributedString)
		}
		applyTextShadowFallback(from: text.shadow, to: attributedString)
		normalizeShadows(in: attributedString)
		let preparedText = NSAttributedString(attributedString: attributedString)

		let margins = text.margins
		var rect = elementRect.insetBy(
			dx: CGFloat(margins.left + margins.right) / 2,
			dy: CGFloat(margins.top + margins.bottom) / 2,
		)
		rect.origin.x += CGFloat(margins.left - margins.right) / 2
		rect.origin.y += CGFloat(margins.top - margins.bottom) / 2
		rect = rect.insetBy(dx: 5, dy: 5)

		let fitted = fittedText(attributedString, in: rect.size, scaleBehavior: text.scaleBehavior)
		let layoutSize: CGSize
		switch text.scaleBehavior {
		case .none, .adjustContainerHeight:
			layoutSize = CGSize(width: rect.width, height: .greatestFiniteMagnitude)
		case .scaleFontDown, .scaleFontUp, .scaleFontUpDown, .UNRECOGNIZED:
			layoutSize = rect.size
		}
		let used = textLayoutBounds(for: fitted, in: layoutSize)

		var drawRect = rect
		var centeredCorrection: CGFloat = 0
		var containerWasExpanded = false
		if text.scaleBehavior == .none || text.scaleBehavior == .adjustContainerHeight {
			let expandedHeight = max(drawRect.height, ceil(used.height))
			containerWasExpanded = expandedHeight > drawRect.height
			let expansion = expandedHeight - drawRect.height
			drawRect.origin.y -= text.scaleBehavior == .adjustContainerHeight ? expansion : expansion / 2
			drawRect.size.height = expandedHeight
		}
		if text.scaleBehavior != .adjustContainerHeight {
			switch text.verticalAlignment {
			case .middle:
				drawRect.origin.y -= max(0, (rect.height - ceil(used.height)) / 2)
				centeredCorrection = centeredLineSpacingCorrection(in: fitted)
				drawRect.origin.y += centeredCorrection
			case .bottom:
				drawRect.origin.y -= max(0, rect.height - ceil(used.height))
				drawRect.origin.y += maximumParagraphLineSpacing(in: fitted)
			case .top:
				drawRect.origin.y += uniformLineHeightCorrection(in: fitted)
			case .UNRECOGNIZED:
				break
			}
		}
		if text.scaleBehavior == .scaleFontUp {
			drawRect.origin.y -= 5
			drawRect.size.height += 5
		} else if text.scaleBehavior == .none,
		          text.verticalAlignment == .middle,
		          containerWasExpanded,
		          textLayoutLineCount(for: fitted, in: layoutSize) > 1
		{
			drawRect.origin.y += 4
		}

		let drawnText = text.scaleBehavior == .adjustContainerHeight
			? textByPreservingLayoutLineBreaks(fitted, in: drawRect.size)
			: fitted
		return EffectiveTextLayout(
			preparedText: preparedText,
			fittedText: fitted,
			drawnText: drawnText,
			contentRect: rect,
			drawRect: drawRect,
			layoutBounds: used,
			centeredCorrection: centeredCorrection,
		)
	}

	private func textByPreservingLayoutLineBreaks(
		_ attributedString: NSAttributedString,
		in size: CGSize,
	) -> NSAttributedString {
		let textStorage = NSTextStorage(attributedString: attributedString)
		let layoutManager = NSLayoutManager()
		let textContainer = NSTextContainer(size: size)
		textContainer.lineFragmentPadding = 0
		layoutManager.addTextContainer(textContainer)
		textStorage.addLayoutManager(layoutManager)

		layoutManager.ensureLayout(for: textContainer)
		let glyphRange = layoutManager.glyphRange(for: textContainer)
		var lineEnds: [Int] = []
		layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, _ in
			let characterRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
			lineEnds.append(NSMaxRange(characterRange))
		}

		guard lineEnds.count > 1 else { return attributedString }
		let result = NSMutableAttributedString(attributedString: attributedString)
		for lineEnd in lineEnds.dropLast().reversed() {
			guard lineEnd < result.length,
			      lineEnd == 0 || (result.string as NSString).character(at: lineEnd - 1) != 0x0A,
			      (result.string as NSString).character(at: lineEnd) != 0x0A
			else {
				continue
			}
			result.insert(NSAttributedString(string: "\n"), at: lineEnd)
		}
		return result
	}

	private func drawAttributedText(_ attributedString: NSAttributedString, in rect: CGRect) {
		let fullRange = NSRange(location: 0, length: attributedString.length)
		var hasStroke = false
		attributedString.enumerateAttribute(.strokeWidth, in: fullRange) { value, _, stop in
			guard let width = value as? NSNumber, width.doubleValue != 0 else { return }
			hasStroke = true
			stop.pointee = true
		}

		guard hasStroke else {
			attributedString.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
			return
		}

		let strokePass = NSMutableAttributedString(attributedString: attributedString)
		strokePass.addAttribute(.foregroundColor, value: NSColor.clear, range: fullRange)
		strokePass.removeAttribute(.shadow, range: fullRange)

		let fillPass = NSMutableAttributedString(attributedString: attributedString)
		fillPass.removeAttribute(.shadow, range: fullRange)
		let shadowPass = NSMutableAttributedString(attributedString: attributedString)
		var hasShadow = false
		shadowPass.enumerateAttribute(.shadow, in: fullRange) { value, _, stop in
			guard value != nil else { return }
			hasShadow = true
			stop.pointee = true
		}
		attributedString.enumerateAttribute(.strokeWidth, in: fullRange) { value, range, _ in
			guard let width = value as? NSNumber, width.doubleValue != 0 else { return }
			strokePass.addAttribute(.strokeWidth, value: abs(width.doubleValue) * 2, range: range)
			fillPass.removeAttribute(.strokeWidth, range: range)
			fillPass.removeAttribute(.strokeColor, range: range)
			shadowPass.addAttribute(.strokeWidth, value: -abs(width.doubleValue) * 2, range: range)
		}

		if hasShadow {
			shadowPass.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
		}
		strokePass.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
		fillPass.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
	}

	private func drawLineFills(
		for attributedString: NSAttributedString,
		in rect: CGRect,
		elementBounds: CGRect,
		centeredCorrection: CGFloat,
		fill: Rv_Data_Graphics.Fill,
		mask: Rv_Data_Graphics.Text.LineFillMask,
	) {
		guard case let .color(color) = fill.fillType, color.alpha > 0 else { return }

		let textStorage = NSTextStorage(attributedString: attributedString)
		let layoutManager = NSLayoutManager()
		let textContainer = NSTextContainer(size: rect.size)
		textContainer.lineFragmentPadding = 0
		layoutManager.addTextContainer(textContainer)
		textStorage.addLayoutManager(layoutManager)

		layoutManager.ensureLayout(for: textContainer)
		let glyphRange = layoutManager.glyphRange(for: textContainer)

		var lineRects: [CGRect] = []
		layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, glyphRange, _ in
			guard glyphRange.length > 0 else { return }
			lineRects.append(usedRect)
		}
		guard !lineRects.isEmpty else { return }

		let maximumLineWidth = lineRects.map(\.width).max() ?? 0
		let nominalLineHeight = lineRects.map(\.height).min() ?? 0
		let lineHeightMultipleAdjustment = lineHeightMultipleAdjustment(in: attributedString)
		let usesConstrainedLineHeight = lineRects.count == 1
			&& nominalLineHeight + CGFloat(mask.heightOffset) > rect.height
		let drawingRect: CGRect
		let lineHeight: CGFloat
		if usesConstrainedLineHeight {
			let verticalCentering = max(0, (rect.height - ceil(nominalLineHeight)) / 2)
			drawingRect = rect.offsetBy(
				dx: 0,
				dy: -centeredCorrection + verticalCentering,
			)
			lineHeight = attributedString.boundingRect(
				with: rect.size,
				options: [.usesDeviceMetrics],
			).height - lineHeightMultipleAdjustment
		} else {
			drawingRect = rect
			lineHeight = nominalLineHeight - lineHeightMultipleAdjustment
		}
		color.nsColor.setFill()
		let fillPath = NSBezierPath()
		let usesMaxLineWidth: Bool
		switch mask.maskStyle {
		case .maxLineWidth, .UNRECOGNIZED:
			usesMaxLineWidth = true
		case .lineWidth, .fullWidth:
			usesMaxLineWidth = false
		}
		if usesMaxLineWidth {
			guard let widestLine = lineRects.max(by: { $0.width < $1.width }) else { return }
			let minY = lineRects.map(\.minY).min() ?? 0
			let maxY = lineRects.map(\.maxY).max() ?? 0
			let width = widestLine.width + CGFloat(mask.widthOffset)
			let x = drawingRect.minX + widestLine.midX - (width / 2) + CGFloat(mask.horizontalOffset)
			let height = maxY - minY + CGFloat(mask.heightOffset)
			let y = drawingRect.maxY
				- maxY
				- CGFloat(mask.heightOffset / 2)
				+ CGFloat(mask.verticalOffset)
			fillPath.appendRect(CGRect(x: x, y: y, width: width, height: height))
			fillPath.fill()
			return
		}

		for usedRect in lineRects {
			let width: CGFloat
			let x: CGFloat
			switch mask.maskStyle {
			case .lineWidth:
				width = usedRect.width + CGFloat(mask.widthOffset)
				x = drawingRect.minX + usedRect.midX - (width / 2) + CGFloat(mask.horizontalOffset)
			case .maxLineWidth, .UNRECOGNIZED:
				width = maximumLineWidth + CGFloat(mask.widthOffset)
				x = drawingRect.minX + usedRect.midX - (width / 2) + CGFloat(mask.horizontalOffset)
			case .fullWidth:
				width = elementBounds.width + CGFloat(mask.widthOffset * 2)
				x = elementBounds.minX - CGFloat(mask.widthOffset) + CGFloat(mask.horizontalOffset)
			}

			let height: CGFloat
			let y: CGFloat
			if usesConstrainedLineHeight {
				height = elementBounds.height
				y = elementBounds.minY + CGFloat(mask.verticalOffset)
			} else {
				height = lineHeight + CGFloat(mask.heightOffset)
				y = drawingRect.maxY
					- usedRect.minY
					- lineHeight
					- CGFloat(mask.heightOffset / 2)
					+ CGFloat(mask.verticalOffset)
			}
			fillPath.appendRect(CGRect(x: x, y: y, width: width, height: height))
		}
		fillPath.fill()
	}

	private func lineHeightMultipleAdjustment(in attributedString: NSAttributedString) -> CGFloat {
		var adjustment: CGFloat = 0
		attributedString.enumerateAttributes(
			in: NSRange(location: 0, length: attributedString.length),
		) { attributes, _, _ in
			guard let font = attributes[.font] as? NSFont,
			      let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle,
			      paragraphStyle.lineHeightMultiple > 1
			else {
				return
			}
			let lineHeight = font.ascender - font.descender + font.leading
			adjustment = max(adjustment, (paragraphStyle.lineHeightMultiple - 1) * lineHeight)
		}
		return adjustment
	}

	private func fittedText(
		_ attributedString: NSAttributedString,
		in size: CGSize,
		scaleBehavior: Rv_Data_Graphics.Text.ScaleBehavior,
	) -> NSAttributedString {
		switch scaleBehavior {
		case .scaleFontDown:
			return scaledDownText(attributedString, in: size)
		case .scaleFontUp:
			guard text(attributedString, fitsIn: size) else { return attributedString }
			return scaledUpText(attributedString, in: size)
		case .scaleFontUpDown:
			guard text(attributedString, fitsIn: size) else {
				return scaledDownText(attributedString, in: size)
			}
			return scaledUpText(attributedString, in: size)
		case .none, .adjustContainerHeight, .UNRECOGNIZED:
			return attributedString
		}
	}

	private func scaledDownText(_ attributedString: NSAttributedString, in size: CGSize) -> NSAttributedString {
		guard !text(attributedString, fitsIn: size) else { return attributedString }
		return largestFittingText(attributedString, in: size, lowerScale: 0.1, upperScale: 1)
	}

	private func scaledUpText(_ attributedString: NSAttributedString, in size: CGSize) -> NSAttributedString {
		var fittingScale: CGFloat = 1
		var overflowingScale: CGFloat = 2

		while overflowingScale < 8 {
			let candidate = attributedString.scaledFonts(by: overflowingScale)
			guard text(candidate, fitsIn: size) else { break }
			fittingScale = overflowingScale
			overflowingScale *= 2
		}

		return largestFittingText(
			attributedString,
			in: size,
			lowerScale: fittingScale,
			upperScale: min(overflowingScale, 8),
		)
	}

	private func largestFittingText(
		_ attributedString: NSAttributedString,
		in size: CGSize,
		lowerScale: CGFloat,
		upperScale: CGFloat,
	) -> NSAttributedString {
		var lowerScale = lowerScale
		var upperScale = upperScale

		for _ in 0 ..< 20 {
			let scale = (lowerScale + upperScale) / 2
			let candidate = attributedString.scaledFonts(by: scale)
			if text(candidate, fitsIn: size) {
				lowerScale = scale
			} else {
				upperScale = scale
			}
		}

		return attributedString.scaledFonts(by: lowerScale)
	}

	private func text(_ attributedString: NSAttributedString, fitsIn size: CGSize) -> Bool {
		let textStorage = NSTextStorage(attributedString: attributedString)
		let layoutManager = NSLayoutManager()
		let textContainer = NSTextContainer(size: size)
		textContainer.lineFragmentPadding = 0
		layoutManager.addTextContainer(textContainer)
		textStorage.addLayoutManager(layoutManager)

		layoutManager.ensureLayout(for: textContainer)
		let laidOutGlyphs = layoutManager.glyphRange(for: textContainer)
		guard NSMaxRange(laidOutGlyphs) == layoutManager.numberOfGlyphs else { return false }

		let naturalBounds = textLayoutBoundsWithoutDefaultLeading(
			for: attributedString,
			in: CGSize(width: size.width, height: .greatestFiniteMagnitude),
		)
		let verticalFitTolerance: CGFloat = 3.5
		return naturalBounds.width <= size.width + 1 && naturalBounds.height <= size.height + verticalFitTolerance
	}

	private func textLayoutBounds(for attributedString: NSAttributedString, in size: CGSize) -> CGRect {
		let textStorage = NSTextStorage(attributedString: attributedString)
		let layoutManager = NSLayoutManager()
		let textContainer = NSTextContainer(size: size)
		textContainer.lineFragmentPadding = 0
		layoutManager.addTextContainer(textContainer)
		textStorage.addLayoutManager(layoutManager)

		layoutManager.ensureLayout(for: textContainer)
		return layoutManager.usedRect(for: textContainer)
	}

	private func textLayoutBoundsWithoutDefaultLeading(
		for attributedString: NSAttributedString,
		in size: CGSize,
	) -> CGRect {
		let textStorage = NSTextStorage(attributedString: attributedString)
		let layoutManager = NSLayoutManager()
		let textContainer = NSTextContainer(size: size)
		textContainer.lineFragmentPadding = 0
		layoutManager.addTextContainer(textContainer)
		textStorage.addLayoutManager(layoutManager)

		layoutManager.ensureLayout(for: textContainer)
		let bounds = layoutManager.usedRect(for: textContainer)
		let glyphRange = layoutManager.glyphRange(for: textContainer)
		var leading = 0.0 as CGFloat
		layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, lineGlyphRange, _ in
			let characterRange = layoutManager.characterRange(
				forGlyphRange: lineGlyphRange,
				actualGlyphRange: nil,
			)
			guard characterRange.length > 0 else { return }
			guard let paragraphStyle = attributedString.attribute(
				.paragraphStyle,
				at: characterRange.location,
				effectiveRange: nil,
			) as? NSParagraphStyle else {
				return
			}
			guard paragraphStyle.lineSpacing == 0,
			      paragraphStyle.minimumLineHeight == 0,
			      paragraphStyle.maximumLineHeight == 0
			else {
				return
			}

			var glyphHeight = 0.0 as CGFloat
			attributedString.enumerateAttribute(.font, in: characterRange) { value, _, _ in
				guard let font = value as? NSFont else { return }
				glyphHeight = max(glyphHeight, font.ascender - font.descender)
			}
			leading += max(0, lineRect.height - glyphHeight)
		}
		return CGRect(
			x: bounds.minX,
			y: bounds.minY,
			width: bounds.width,
			height: max(0, bounds.height - leading),
		)
	}

	private func textLayoutLineCount(for attributedString: NSAttributedString, in size: CGSize) -> Int {
		let textStorage = NSTextStorage(attributedString: attributedString)
		let layoutManager = NSLayoutManager()
		let textContainer = NSTextContainer(size: size)
		textContainer.lineFragmentPadding = 0
		layoutManager.addTextContainer(textContainer)
		textStorage.addLayoutManager(layoutManager)

		layoutManager.ensureLayout(for: textContainer)
		let glyphRange = layoutManager.glyphRange(for: textContainer)
		var count = 0
		layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, glyphRange, _ in
			if glyphRange.length > 0 {
				count += 1
			}
		}
		return count
	}

	private func normalizeFonts(in attributedString: NSMutableAttributedString) {
		attributedString.enumerateAttribute(.font, in: NSRange(location: 0, length: attributedString.length)) { value, range, _ in
			guard let font = value as? NSFont else { return }
			let descriptor = font.fontDescriptor
			if let postscriptName = descriptor.postscriptName,
			   let exact = NSFont(name: postscriptName, size: font.pointSize)
			{
				attributedString.addAttribute(.font, value: exact, range: range)
				return
			}

			let fallbackName = descriptor.symbolicTraits.contains(.bold) ? "HelveticaNeue-Bold" : "HelveticaNeue"
			if let fallback = NSFont(name: fallbackName, size: font.pointSize) {
				attributedString.addAttribute(.font, value: fallback, range: range)
			}
		}
	}

	private func standardizeSuperscripts(in attributedString: NSMutableAttributedString) {
		let fullRange = NSRange(location: 0, length: attributedString.length)
		attributedString.enumerateAttribute(.superscript, in: fullRange) { value, range, _ in
			guard let superscript = value as? NSNumber,
			      superscript.intValue != 0,
			      let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
			else {
				return
			}
			attributedString.addAttribute(
				.font,
				value: NSFont(descriptor: font.fontDescriptor, size: font.pointSize / 2) ?? font,
				range: range,
			)
		}
	}

	private func applyCustomFontMetadata(
		from attributes: Rv_Data_Graphics.Text.Attributes,
		to attributedString: NSMutableAttributedString,
	) {
		for customAttribute in attributes.customAttributes {
			guard case let .originalFontSize(size)? = customAttribute.attribute,
			      size.isFinite,
			      size > 0
			else {
				continue
			}
			let start = max(0, Int(customAttribute.range.start))
			let end = min(attributedString.length, Int(customAttribute.range.end))
			guard start < end else { continue }
			let range = NSRange(location: start, length: end - start)
			attributedString.enumerateAttribute(.font, in: range) { value, runRange, _ in
				guard let font = value as? NSFont else { return }
				let resized = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
				attributedString.addAttribute(.font, value: resized, range: runRange)
			}
		}
	}

	private func includeFontLeadingInLineSpacing(in attributedString: NSMutableAttributedString) {
		let fullRange = NSRange(location: 0, length: attributedString.length)
		var adjustments: [(NSRange, NSParagraphStyle, CGFloat)] = []
		attributedString.enumerateAttributes(in: fullRange) { attributes, range, _ in
			guard let font = attributes[.font] as? NSFont,
			      font.leading > 0,
			      let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
			else {
				return
			}
			adjustments.append((range, paragraphStyle, font.leading))
		}
		for (range, paragraphStyle, leading) in adjustments {
			guard let adjusted = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle else { continue }
			adjusted.lineSpacing += leading
			attributedString.addAttribute(.paragraphStyle, value: adjusted, range: range)
		}
	}

	private func maximumParagraphLineSpacing(in attributedString: NSAttributedString) -> CGFloat {
		var maximum: CGFloat = 0
		attributedString.enumerateAttribute(
			.paragraphStyle,
			in: NSRange(location: 0, length: attributedString.length),
		) { value, _, _ in
			guard let paragraphStyle = value as? NSParagraphStyle else { return }
			maximum = max(maximum, paragraphStyle.lineSpacing)
		}
		return maximum
	}

	private func centeredLineSpacingCorrection(in attributedString: NSAttributedString) -> CGFloat {
		var pointSizes = Set<CGFloat>()
		var lineHeightMultiples = Set<CGFloat>()
		var lineHeightCorrections = Set<CGFloat>()
		attributedString.enumerateAttribute(
			.font,
			in: NSRange(location: 0, length: attributedString.length),
		) { value, _, _ in
			guard let font = value as? NSFont else { return }
			pointSizes.insert(font.pointSize)
		}
		guard pointSizes.count == 1 else { return 0 }

		attributedString.enumerateAttributes(
			in: NSRange(location: 0, length: attributedString.length),
		) { attributes, _, _ in
			guard let font = attributes[.font] as? NSFont,
			      let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
			else {
				return
			}
			let multiple = paragraphStyle.lineHeightMultiple
			lineHeightMultiples.insert(multiple)
			guard multiple > 0 else { return }
			let fontLineHeight = font.ascender - font.descender + font.leading
			lineHeightCorrections.insert((multiple - 1) * fontLineHeight / 2)
		}

		let lineHeightCorrection = lineHeightMultiples.count == 1 && lineHeightCorrections.count == 1
			? lineHeightCorrections.first ?? 0
			: 0
		return maximumParagraphLineSpacing(in: attributedString) / 2 + lineHeightCorrection
	}

	private func uniformLineHeightCorrection(in attributedString: NSAttributedString) -> CGFloat {
		var corrections = Set<CGFloat>()
		attributedString.enumerateAttributes(
			in: NSRange(location: 0, length: attributedString.length),
		) { attributes, _, _ in
			guard let font = attributes[.font] as? NSFont,
			      let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle,
			      paragraphStyle.lineHeightMultiple > 0
			else {
				return
			}
			let fontLineHeight = font.ascender - font.descender + font.leading
			corrections.insert((paragraphStyle.lineHeightMultiple - 1) * fontLineHeight)
		}
		return corrections.count == 1 ? corrections.first ?? 0 : 0
	}

	private func normalizeShadows(in attributedString: NSMutableAttributedString) {
		let fullRange = NSRange(location: 0, length: attributedString.length)
		attributedString.enumerateAttribute(.shadow, in: fullRange) { value, range, _ in
			guard let shadow = value as? NSShadow else { return }
			let normalized = NSShadow()
			normalized.shadowBlurRadius = shadow.shadowBlurRadius
			normalized.shadowColor = shadow.shadowColor
			normalized.shadowOffset = shadow.shadowOffset
			attributedString.addAttribute(.shadow, value: normalized, range: range)
		}
	}

	private func applyTextShadowFallback(
		from shadow: Rv_Data_Graphics.Shadow,
		to attributedString: NSMutableAttributedString,
	) {
		guard shadow.enable else { return }

		let fullRange = NSRange(location: 0, length: attributedString.length)
		var hasRTFShadow = false
		attributedString.enumerateAttribute(.shadow, in: fullRange) { value, _, stop in
			guard value != nil else { return }
			hasRTFShadow = true
			stop.pointee = true
		}
		guard !hasRTFShadow else { return }

		let radians = CGFloat(shadow.angle * .pi / 180)
		let fallback = NSShadow()
		fallback.shadowBlurRadius = CGFloat(shadow.radius)
		fallback.shadowColor = shadow.color.nsColor.withAlphaComponent(
			CGFloat(shadow.color.alpha) * CGFloat(shadow.opacity),
		)
		fallback.shadowOffset = CGSize(
			width: cos(radians) * CGFloat(shadow.offset),
			height: sin(radians) * CGFloat(shadow.offset),
		)
		attributedString.addAttribute(.shadow, value: fallback, range: fullRange)
	}

	private func applyTextTransform(
		from text: Rv_Data_Graphics.Text,
		to attributedString: NSMutableAttributedString,
	) {
		switch text.transform {
		case .none, .UNRECOGNIZED:
			return
		case .singleLine:
			replaceOccurrences(of: "\n", with: " ", in: attributedString)
		case .oneWordPerLine:
			replaceOccurrences(of: " ", with: "\n", in: attributedString)
		case .oneCharacterPerLine:
			let string = attributedString.string
			guard !string.isEmpty else { return }
			attributedString.replaceCharacters(
				in: NSRange(location: 0, length: attributedString.length),
				with: string.map(String.init).joined(separator: "\n"),
			)
		case .replaceLineReturns:
			replaceOccurrences(of: "\n", with: text.transformDelimiter, in: attributedString)
		}
	}

	private func replaceOccurrences(
		of search: String,
		with replacement: String,
		in attributedString: NSMutableAttributedString,
	) {
		guard !search.isEmpty else { return }
		while true {
			let range = (attributedString.string as NSString).range(of: search)
			guard range.location != NSNotFound else { return }
			attributedString.replaceCharacters(in: range, with: replacement)
		}
	}

	private func applyTextListMarkers(
		to attributedString: NSMutableAttributedString,
		hasRestoredNativeListText: Bool,
	) {
		let string = attributedString.string as NSString
		var paragraphRanges: [NSRange] = []
		var location = 0
		while location < string.length {
			let range = string.paragraphRange(for: NSRange(location: location, length: 0))
			paragraphRanges.append(range)
			location = NSMaxRange(range)
		}

		var itemNumbers: [ObjectIdentifier: Int] = [:]
		var insertions: [(location: Int, marker: String, attributes: [NSAttributedString.Key: Any])] = []
		for range in paragraphRanges {
			guard range.location < attributedString.length,
			      let paragraphStyle = attributedString.attribute(
			      	.paragraphStyle,
			      	at: range.location,
			      	effectiveRange: nil,
			      ) as? NSParagraphStyle,
			      let textList = paragraphStyle.textLists.last
			else {
				continue
			}
			if hasRestoredNativeListText,
			   (attributedString.string as NSString).character(at: range.location) == 0x09
			{
				continue
			}

			let identifier = ObjectIdentifier(textList)
			let itemNumber = itemNumbers[identifier, default: textList.startingItemNumber]
			itemNumbers[identifier] = itemNumber + 1
			let attributes = attributedString.attributes(at: range.location, effectiveRange: nil)
			insertions.append((range.location, "\(textList.marker(forItemNumber: itemNumber))\t\t", attributes))
		}

		for insertion in insertions.reversed() {
			attributedString.insert(
				NSAttributedString(string: insertion.marker, attributes: insertion.attributes),
				at: insertion.location,
			)
		}
	}

	private struct DecodedText {
		let attributedString: NSMutableAttributedString
		let hasRestoredNativeListText: Bool
	}

	private struct RestoredListTextRTF {
		let data: Data
		let didRestore: Bool
	}

	private func applyCustomCapitalization(
		from attributes: Rv_Data_Graphics.Text.Attributes,
		to attributedString: NSMutableAttributedString,
	) {
		for customAttribute in attributes.customAttributes {
			let start = max(0, Int(customAttribute.range.start))
			let end = min(attributedString.length, Int(customAttribute.range.end))
			guard start < end else { continue }
			let range = NSRange(location: start, length: end - start)
			switch customAttribute.capitalization {
			case .allCaps:
				replaceAttributedCharacters(in: range, of: attributedString) { $0.uppercased() }
			case .titleCase:
				applyWordCapitalization(in: range, of: attributedString, usesTitleCase: true)
			case .startCase:
				applyWordCapitalization(in: range, of: attributedString, usesTitleCase: false)
			case .none, .smallCaps, .UNRECOGNIZED:
				continue
			}
		}
	}

	private func applyWordCapitalization(
		in range: NSRange,
		of attributedString: NSMutableAttributedString,
		usesTitleCase: Bool,
	) {
		let substring = attributedString.attributedSubstring(from: range)
		let string = substring.string
		var wordRanges: [NSRange] = []
		string.enumerateSubstrings(in: string.startIndex ..< string.endIndex, options: .byWords) { _, wordRange, _, _ in
			wordRanges.append(NSRange(wordRange, in: string))
		}

		let minorTitleCaseWords: Set = ["a", "and", "of"]
		for (wordIndex, rangeInSubstring) in wordRanges.enumerated().reversed() {
			let wordRange = NSRange(location: range.location + rangeInSubstring.location, length: rangeInSubstring.length)
			let word = (string as NSString).substring(with: rangeInSubstring).lowercased()
			let capitalizesFirstCharacter = !usesTitleCase || wordIndex == 0 || !minorTitleCaseWords.contains(word)
			replaceAttributedWord(
				in: wordRange,
				of: attributedString,
				capitalizesFirstCharacter: capitalizesFirstCharacter,
			)
		}
	}

	private func replaceAttributedWord(
		in range: NSRange,
		of attributedString: NSMutableAttributedString,
		capitalizesFirstCharacter: Bool,
	) {
		let substring = attributedString.attributedSubstring(from: range)
		let string = substring.string
		let replacement = NSMutableAttributedString()
		var isFirstCharacter = true
		string.enumerateSubstrings(
			in: string.startIndex ..< string.endIndex,
			options: .byComposedCharacterSequences,
		) { character, characterRange, _, _ in
			guard let character else { return }
			let attributes = substring.attributes(
				at: NSRange(characterRange, in: string).location,
				effectiveRange: nil,
			)
			let transformed = isFirstCharacter && capitalizesFirstCharacter
				? character.uppercased()
				: character.lowercased()
			replacement.append(NSAttributedString(string: transformed, attributes: attributes))
			isFirstCharacter = false
		}
		attributedString.replaceCharacters(in: range, with: replacement)
	}

	private func replaceAttributedCharacters(
		in range: NSRange,
		of attributedString: NSMutableAttributedString,
		transform: (String) -> String,
	) {
		let substring = attributedString.attributedSubstring(from: range)
		let replacement = NSMutableAttributedString()
		substring.enumerateAttributes(
			in: NSRange(location: 0, length: substring.length),
		) { attributes, attributeRange, _ in
			let string = (substring.string as NSString).substring(with: attributeRange)
			replacement.append(NSAttributedString(string: transform(string), attributes: attributes))
		}
		attributedString.replaceCharacters(in: range, with: replacement)
	}

	private func frameImage(from url: URL, at thumbnailPosition: Double) -> CGImage? {
		let asset = AVURLAsset(url: url)
		if let image = decodedFrameImage(from: asset, at: thumbnailPosition) {
			return image
		}
		let generator = AVAssetImageGenerator(asset: asset)
		generator.appliesPreferredTrackTransform = true
		generator.requestedTimeToleranceBefore = .zero
		generator.requestedTimeToleranceAfter = .zero
		let sampleTime = CMTime(seconds: max(0, thumbnailPosition), preferredTimescale: 600)
		let generatedImage = Mutex<CGImage?>(nil)
		let semaphore = DispatchSemaphore(value: 0)
		generator.generateCGImageAsynchronously(for: sampleTime) { image, _, _ in
			generatedImage.withLock { $0 = image }
			semaphore.signal()
		}
		semaphore.wait()
		return generatedImage.withLock { $0 }
	}

	private func decodedFrameImage(from asset: AVAsset, at thumbnailPosition: Double) -> CGImage? {
		guard let track = asset.tracks(withMediaType: .video).first,
		      let reader = try? AVAssetReader(asset: asset)
		else {
			return nil
		}
		let output = AVAssetReaderTrackOutput(
			track: track,
			outputSettings: [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
			],
		)
		guard reader.canAdd(output) else { return nil }
		reader.add(output)
		guard reader.startReading() else { return nil }

		let sampleTime = max(0, thumbnailPosition)
		while let sample = output.copyNextSampleBuffer() {
			guard CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) >= sampleTime else { continue }
			guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
			return rgbImage(from: pixelBuffer)
		}
		return nil
	}

	private func rgbImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
		guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2,
		      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
		else {
			return nil
		}
		CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
		defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
		guard let lumaAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
		      let chromaAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
		else {
			return nil
		}

		let width = CVPixelBufferGetWidth(pixelBuffer)
		let height = CVPixelBufferGetHeight(pixelBuffer)
		let luma = lumaAddress.assumingMemoryBound(to: UInt8.self)
		let chroma = chromaAddress.assumingMemoryBound(to: UInt8.self)
		let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
		let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
		var data = [UInt8](repeating: 0, count: width * height * 4)

		for y in 0 ..< height {
			for x in 0 ..< width {
				let lumaValue = CGFloat(luma[y * lumaStride + x]) - 16
				let chromaOffset = (y / 2) * chromaStride + (x / 2) * 2
				let cb = CGFloat(chroma[chromaOffset]) - 128
				let cr = CGFloat(chroma[chromaOffset + 1]) - 128
				let red = 1.156 * lumaValue + 2 * cr
				let green = 1.156 * lumaValue - 0.333 * cb - 0.333 * cr
				let blue = 1.156 * lumaValue + 1.8 * cb
				let offset = (y * width + x) * 4
				data[offset] = UInt8(max(0, min(255, Int(red.rounded()))))
				data[offset + 1] = UInt8(max(0, min(255, Int(green.rounded()))))
				data[offset + 2] = UInt8(max(0, min(255, Int(blue.rounded()))))
				data[offset + 3] = 255
			}
		}
		return CGContext(
			data: &data,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
		)?.makeImage()
	}

	private func resolvedURL(for media: Rv_Data_Media) -> URL? {
		let url = media.url
		let renderPath = url.renderPath
		let reference = ThemeTemplateSource.MediaReference(
			uuid: media.uuid.string,
			renderPath: renderPath,
		)
		if document.preferredMediaReferences.contains(reference) {
			if let absolute = URL(string: renderPath),
			   absolute.isFileURL,
			   fileManager.fileExists(atPath: absolute.path)
			{
				return absolute
			}
			return nil
		}

		if let mediaDirectory = document.mediaDirectory {
			let decodedName = renderPath.removingPercentEncoding ?? renderPath
			let sourcePath: String
			if let sourceURL = URL(string: decodedName), sourceURL.isFileURL {
				sourcePath = sourceURL.path
			} else {
				sourcePath = decodedName
			}
			let normalizedPath = sourcePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
			let embeddedCandidate = mediaDirectory.appendingPathComponent(normalizedPath)
			if fileManager.fileExists(atPath: embeddedCandidate.path) {
				return embeddedCandidate
			}

			let basename = URL(fileURLWithPath: decodedName).lastPathComponent
			let candidate = mediaDirectory.appendingPathComponent(basename)
			if fileManager.fileExists(atPath: candidate.path) {
				return candidate
			}
		}

		if let absolute = URL(string: renderPath), absolute.isFileURL, fileManager.fileExists(atPath: absolute.path) {
			return absolute
		}

		return nil
	}
}

private extension Rv_Data_Graphics.Size {
	var cgSize: CGSize {
		CGSize(width: width, height: height)
	}
}

private extension Rv_Data_Graphics.Rect {
	var cgRect: CGRect {
		CGRect(
			x: origin.x,
			y: origin.y,
			width: size.width,
			height: size.height,
		)
	}
}

private extension CGRect {
	func flipped(in canvasSize: CGSize) -> CGRect {
		CGRect(
			x: origin.x,
			y: canvasSize.height - origin.y - height,
			width: width,
			height: height,
		)
	}
}

private extension Rv_Data_Color {
	var nsColor: NSColor {
		NSColor(
			srgbRed: CGFloat(red),
			green: CGFloat(green),
			blue: CGFloat(blue),
			alpha: CGFloat(alpha),
		)
	}
}

private extension NSBitmapImageRep {
	func data(for type: RenderOptions.ImageType) throws -> Data {
		if type == .heic {
			guard let image = cgImage else { throw RenderError.pngEncodingFailed }
			let output = NSMutableData()
			guard let destination = CGImageDestinationCreateWithData(output, UTType.heic.identifier as CFString, 1, nil) else {
				throw RenderError.pngEncodingFailed
			}
			CGImageDestinationAddImage(destination, image, nil)
			guard CGImageDestinationFinalize(destination) else { throw RenderError.pngEncodingFailed }
			return output as Data
		}
		let fileType: NSBitmapImageRep.FileType = type == .png ? .png : .jpeg
		let properties: [NSBitmapImageRep.PropertyKey: Any] = type == .jpg
			? [.compressionFactor: 0.8]
			: [:]
		guard let data = representation(using: fileType, properties: properties) else {
			throw RenderError.pngEncodingFailed
		}
		return data
	}
}

private extension CGImage {
	var retaggedAsSRGB: CGImage? {
		guard let dataProvider,
		      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
		return CGImage(
			width: width,
			height: height,
			bitsPerComponent: bitsPerComponent,
			bitsPerPixel: bitsPerPixel,
			bytesPerRow: bytesPerRow,
			space: colorSpace,
			bitmapInfo: bitmapInfo,
			provider: dataProvider,
			decode: decode,
			shouldInterpolate: shouldInterpolate,
			intent: renderingIntent,
		)
	}
}

private extension NSAttributedString {
	func scaledFonts(by scale: CGFloat) -> NSAttributedString {
		let copy = NSMutableAttributedString(attributedString: self)
		copy.enumerateAttribute(.font, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
			guard let font = value as? NSFont else { return }
			copy.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: max(1, font.pointSize * scale)) ?? font, range: range)
		}
		return copy
	}
}

private extension EffectiveRendering.Paragraph {
	var hasValues: Bool {
		alignment != nil ||
			lineSpacing != nil ||
			paragraphSpacing != nil ||
			paragraphSpacingBefore != nil ||
			firstLineHeadIndent != nil ||
			headIndent != nil ||
			tailIndent != nil ||
			minimumLineHeight != nil ||
			maximumLineHeight != nil ||
			lineHeightMultiple != nil
	}
}

private extension EffectiveRendering.Insets {
	var hasValues: Bool {
		top != nil || left != nil || bottom != nil || right != nil
	}
}

public enum RenderError: Error, CustomStringConvertible {
	case bitmapCreationFailed
	case invalidDocument(RenderingDiagnostic)
	case pngEncodingFailed
	case pdfCreationFailed

	public var description: String {
		switch self {
		case .bitmapCreationFailed:
			"Could not create a bitmap for the requested canvas."
		case let .invalidDocument(diagnostic):
			diagnostic.description
		case .pngEncodingFailed:
			"Could not encode the rendered bitmap."
		case .pdfCreationFailed:
			"Could not create the PDF output."
		}
	}
}
