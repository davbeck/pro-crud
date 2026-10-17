import AppKit
import ProPresenterProto

/// The cap-height-based layout used by native 22 text without font scaling.
final class NativeTextLayout: NSObject, NSLayoutManagerDelegate {
	private let storage: NSTextStorage
	private let manager = NSLayoutManager()
	private let container: NSTextContainer
	private(set) var alignmentBounds = CGRect.null

	init(_ text: NSAttributedString, width: CGFloat) {
		storage = NSTextStorage(attributedString: text)
		container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
		super.init()
		container.lineFragmentPadding = 0
		manager.delegate = self
		storage.addLayoutManager(manager)
		manager.addTextContainer(container)
		manager.ensureLayout(for: container)
		manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, used, _, glyphs, _ in
			let metrics = self.fontMetrics(for: glyphs)
			// Leading precedes the cap-height-centered body. Include the corrected
			// body of every line when aligning the entire text block.
			self.alignmentBounds = self.alignmentBounds.union(CGRect(
				x: used.minX,
				y: rect.maxY - metrics.height,
				width: used.width,
				height: metrics.height,
			))
		}
	}

	func offset(in height: CGFloat, alignment: Rv_Data_Graphics.Text.VerticalAlignment) -> CGFloat {
		switch alignment {
		case .middle: height / 2 - alignmentBounds.midY
		case .bottom: height - alignmentBounds.maxY
		case .top, .UNRECOGNIZED: -alignmentBounds.minY
		}
	}

	func draw(in rect: CGRect, offset: CGFloat) {
		guard let context = NSGraphicsContext.current?.cgContext else { return }
		NSGraphicsContext.saveGraphicsState()
		defer { NSGraphicsContext.restoreGraphicsState() }
		context.translateBy(x: rect.minX, y: rect.maxY)
		context.scaleBy(x: 1, y: -1)
		context.clip(to: CGRect(origin: .zero, size: rect.size))
		NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
		manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: CGPoint(x: 0, y: offset))
	}

	func layoutManager(
		_ layoutManager: NSLayoutManager,
		lineSpacingAfterGlyphAt glyphIndex: Int,
		withProposedLineFragmentRect rect: NSRect,
	) -> CGFloat {
		let attributes = storage.attributes(at: layoutManager.characterIndexForGlyph(at: glyphIndex), effectiveRange: nil)
		return ((attributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing ?? 0)
			+ ((attributes[.font] as? NSFont)?.leading ?? 0)
	}

	func layoutManager(
		_ layoutManager: NSLayoutManager,
		shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
		lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
		baselineOffset: UnsafeMutablePointer<CGFloat>,
		in textContainer: NSTextContainer,
		forGlyphRange glyphRange: NSRange,
	) -> Bool {
		let metrics = fontMetrics(for: glyphRange)
		let bodyBaseline = baselineOffset.pointee - (lineFragmentRect.pointee.height - metrics.height)
		let correction = (metrics.height + metrics.capHeight) / 2 - bodyBaseline
		if metrics.capHeight > 0, metrics.height > 0, bodyBaseline > 0, abs(correction) <= metrics.height {
			baselineOffset.pointee += correction
		}
		return true
	}

	private func fontMetrics(for glyphs: NSRange) -> (capHeight: CGFloat, height: CGFloat) {
		let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
		var capHeight: CGFloat = 0
		var descender: CGFloat = 0
		var defaultHeight: CGFloat = 0
		storage.enumerateAttribute(.font, in: characters) { value, _, _ in
			guard let font = value as? NSFont else { return }
			capHeight = max(capHeight, font.capHeight)
			descender = min(descender, font.descender)
			defaultHeight = max(defaultHeight, self.manager.defaultLineHeight(for: font))
		}
		return (capHeight, max(defaultHeight, capHeight - 2 * descender))
	}
}
