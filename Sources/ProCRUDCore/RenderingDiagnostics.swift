import AppKit
import Foundation
import ProPresenterProto

public struct RenderingDiagnostic: Sendable, Equatable, CustomStringConvertible {
	public enum Code: String, Sendable {
		case noRenderableContent = "rendering.no-renderable-content"
		case multiplePresentationSlideActions = "rendering.multiple-presentation-slide-actions"
		case missingPresentationSlidePayload = "rendering.missing-presentation-slide-payload"
		case invalidCanvasSize = "rendering.invalid-canvas-size"
		case canvasPixelLimit = "rendering.canvas-pixel-limit"
		case missingElementUUID = "rendering.missing-element-uuid"
		case duplicateElementUUID = "rendering.duplicate-element-uuid"
		case nonfiniteElementBounds = "rendering.nonfinite-element-bounds"
		case nonpositiveElementBounds = "rendering.nonpositive-element-bounds"
		case elementOutsideCanvas = "rendering.element-outside-canvas"
		case invalidElementOpacity = "rendering.invalid-element-opacity"
		case zeroElementOpacity = "rendering.zero-element-opacity"
		case nonfiniteElementRotation = "rendering.nonfinite-element-rotation"
		case missingTextRTF = "rendering.missing-text-rtf"
		case invalidTextRTF = "rendering.invalid-text-rtf"
		case invalidTextCustomAttributeRange = "rendering.invalid-text-custom-attribute-range"
		case missingMediaURL = "rendering.missing-media-url"
		case unresolvedMedia = "rendering.unresolved-media"
	}

	public enum Severity: String, Sendable {
		case warning
		case error
	}

	public var code: Code
	public var severity: Severity
	public var componentPath: String
	public var message: String

	public init(code: Code, severity: Severity, componentPath: String, message: String) {
		self.code = code
		self.severity = severity
		self.componentPath = componentPath
		self.message = message
	}

	public var description: String {
		"\(severity.rawValue.capitalized) at \(componentPath): \(message)"
	}
}

public extension PresentationDocument {
	/// Finds persisted states that are accepted by protobuf decoding but are
	/// likely to disappear, normalize, or render differently in ProPresenter.
	///
	/// Diagnostics are deliberately non-mutating. Warnings identify valid but
	/// surprising output, while errors identify unsafe numeric state that the
	/// renderer refuses to pass to AppKit/Core Graphics.
	var renderingDiagnostics: [RenderingDiagnostic] {
		var results: [RenderingDiagnostic] = []
		for storageIndex in presentation.presentationCueIndexOrder.storageIndices {
			results.append(contentsOf: renderingDiagnostics(forCueAtStorageIndex: storageIndex))
		}
		return results
	}

	func renderingDiagnostics(for cue: Rv_Data_Cue) -> [RenderingDiagnostic] {
		guard let storageIndex = presentation.cues.firstIndex(of: cue) else {
			return renderingDiagnostics(for: cue, cuePath: "/")
		}
		return renderingDiagnostics(forCueAtStorageIndex: storageIndex)
	}

	func renderingDiagnostics(forCueAtStorageIndex storageIndex: Int) -> [RenderingDiagnostic] {
		guard presentation.cues.indices.contains(storageIndex) else { return [] }
		return renderingDiagnostics(
			for: presentation.cues[storageIndex],
			cuePath: presentation.componentPath(forCueAtStorageIndex: storageIndex),
		)
	}

	private func renderingDiagnostics(for cue: Rv_Data_Cue, cuePath: String) -> [RenderingDiagnostic] {
		let actionIdentities = cue.actions.map(\.uuid.string)
		let slideActionIndices = cue.actions.indices.filter { cue.actions[$0].type == .presentationSlide }
		let mediaActions = cue.actions.filter { $0.renderableMedia != nil }
		var results: [RenderingDiagnostic] = []

		if slideActionIndices.isEmpty, mediaActions.isEmpty {
			results.append(RenderingDiagnostic(
				code: .noRenderableContent,
				severity: .warning,
				componentPath: cuePath,
				message: "Cue has no presentation-slide or renderable media action, so it produces a transparent image.",
			))
		}
		if slideActionIndices.count > 1 {
			results.append(RenderingDiagnostic(
				code: .multiplePresentationSlideActions,
				severity: .warning,
				componentPath: cuePath,
				message: "Cue has \(slideActionIndices.count) presentation-slide actions; the renderer uses only the first slide.",
			))
		}

		guard let actionIndex = slideActionIndices.first else { return results }
		let action = cue.actions[actionIndex]
		let actionPath = ComponentPathBuilder.repeatedPath(
			parent: cuePath,
			field: "actions",
			storageIndex: actionIndex,
			identities: actionIdentities,
		)
		guard case let .presentation(presentationSlide)? = action.slide.slide else {
			results.append(RenderingDiagnostic(
				code: .missingPresentationSlidePayload,
				severity: .error,
				componentPath: actionPath,
				message: "Action type is presentationSlide but its presentation slide payload is missing.",
			))
			return results
		}

		let slide = presentationSlide.baseSlide
		let slidePath = "\(actionPath)/slide/presentation/base_slide"
		let width = slide.size.width
		let height = slide.size.height
		if !width.isFinite || !height.isFinite || width < 1 || height < 1 {
			results.append(RenderingDiagnostic(
				code: .invalidCanvasSize,
				severity: .error,
				componentPath: "\(slidePath)/size",
				message: "Canvas must have finite dimensions of at least one pixel; got \(number(width))×\(number(height)).",
			))
		} else if width * height > PresentationRenderer.maximumCanvasPixelCount {
			results.append(RenderingDiagnostic(
				code: .canvasPixelLimit,
				severity: .error,
				componentPath: "\(slidePath)/size",
				message: "Canvas has \(number(width * height)) pixels, exceeding the safe rendering limit of \(PresentationRenderer.maximumCanvasPixelCount).",
			))
		}

		let elementIdentities = slide.elements.map(\.element.uuid.string)
		var seenElementIDs = Set<String>()
		for (index, slideElement) in slide.elements.enumerated() {
			let element = slideElement.element
			let identifier = element.uuid.string
			let elementPath = ComponentPathBuilder.repeatedPath(
				parent: slidePath,
				field: "elements",
				storageIndex: index,
				identities: elementIdentities,
			) + "/element"
			if identifier.isEmpty {
				results.append(RenderingDiagnostic(
					code: .missingElementUUID,
					severity: .warning,
					componentPath: elementPath,
					message: "Element UUID is missing; edits cannot address this element reliably.",
				))
			} else if !seenElementIDs.insert(identifier).inserted {
				results.append(RenderingDiagnostic(
					code: .duplicateElementUUID,
					severity: .warning,
					componentPath: elementPath,
					message: "Element UUID is duplicated within the slide; component selectors are ambiguous.",
				))
			}

			let bounds = element.bounds
			let components = [
				bounds.origin.x,
				bounds.origin.y,
				bounds.size.width,
				bounds.size.height,
			]
			if !components.allSatisfy(\.isFinite) {
				results.append(RenderingDiagnostic(
					code: .nonfiniteElementBounds,
					severity: .error,
					componentPath: "\(elementPath)/bounds",
					message: "Bounds contain NaN or infinity and cannot be rendered safely.",
				))
			} else if bounds.size.width <= 0 || bounds.size.height <= 0 {
				results.append(RenderingDiagnostic(
					code: .nonpositiveElementBounds,
					severity: .warning,
					componentPath: "\(elementPath)/bounds",
					message: "Element has a non-positive width or height and will not be visible.",
				))
			} else if width.isFinite, height.isFinite, width > 0, height > 0 {
				let frame = CGRect(
					x: bounds.origin.x,
					y: bounds.origin.y,
					width: bounds.size.width,
					height: bounds.size.height,
				)
				if !frame.intersects(CGRect(x: 0, y: 0, width: width, height: height)) {
					results.append(RenderingDiagnostic(
						code: .elementOutsideCanvas,
						severity: .warning,
						componentPath: "\(elementPath)/bounds",
						message: "Element is entirely outside the \(number(width))×\(number(height)) canvas and will not be visible.",
					))
				}
			}

			if !element.opacity.isFinite || element.opacity < 0 || element.opacity > 1 {
				results.append(RenderingDiagnostic(
					code: .invalidElementOpacity,
					severity: .error,
					componentPath: "\(elementPath)/opacity",
					message: "Opacity must be finite and between 0 and 1; got \(number(element.opacity)).",
				))
			} else if element.opacity == 0 {
				let message = element.hasText && !element.text.rtfData.isEmpty
					? "Element opacity is zero. ProPresenter hides the element appearance but still draws its text glyphs at full opacity; remove or hide the element if the text should be invisible."
					: "Element opacity is zero, so its fill and stroke are invisible."
				results.append(RenderingDiagnostic(
					code: .zeroElementOpacity,
					severity: .warning,
					componentPath: "\(elementPath)/opacity",
					message: message,
				))
			}
			if !element.rotation.isFinite {
				results.append(RenderingDiagnostic(
					code: .nonfiniteElementRotation,
					severity: .error,
					componentPath: "\(elementPath)/rotation",
					message: "Rotation contains NaN or infinity and cannot be rendered safely.",
				))
			}

			results.append(contentsOf: textDiagnostics(element.text, at: "\(elementPath)/text", isPresent: element.hasText))
			results.append(contentsOf: mediaDiagnostics(element, at: elementPath))
		}
		for (index, action) in cue.actions.enumerated() {
			guard let media = action.renderableMedia else { continue }
			let actionPath = ComponentPathBuilder.repeatedPath(
				parent: cuePath,
				field: "actions",
				storageIndex: index,
				identities: actionIdentities,
			)
			results.append(contentsOf: mediaDiagnostics(media, at: "\(actionPath)/media/element"))
		}
		return results
	}

	private func textDiagnostics(
		_ text: Rv_Data_Graphics.Text,
		at path: String,
		isPresent: Bool,
	) -> [RenderingDiagnostic] {
		guard isPresent else { return [] }
		guard !text.rtfData.isEmpty else {
			return [RenderingDiagnostic(
				code: .missingTextRTF,
				severity: .warning,
				componentPath: "\(path)/rtf_data",
				message: "Text payload is present but has no RTF data, so it draws no glyphs.",
			)]
		}
		guard let attributed = try? NSAttributedString(
			data: text.rtfData,
			options: [.documentType: NSAttributedString.DocumentType.rtf],
			documentAttributes: nil,
		) else {
			return [RenderingDiagnostic(
				code: .invalidTextRTF,
				severity: .error,
				componentPath: "\(path)/rtf_data",
				message: "RTF data cannot be decoded by Cocoa.",
			)]
		}

		var results: [RenderingDiagnostic] = []
		for (index, attribute) in text.attributes.customAttributes.enumerated() {
			let start = Int(attribute.range.start)
			let end = Int(attribute.range.end)
			guard start < 0 || end > attributed.length || start > end else { continue }
			results.append(RenderingDiagnostic(
				code: .invalidTextCustomAttributeRange,
				severity: .warning,
				componentPath: "\(path)/attributes/custom_attributes[index=\(index)]/range",
				message: "Range \(start)..<\(end) is outside the replacement text's UTF-16 length \(attributed.length). ProPresenter clips or ignores malformed ranges differently by attribute kind; replace the RTF through set-text/set-rtf to clear this stale metadata.",
			))
		}
		return results
	}

	private func mediaDiagnostics(
		_ element: Rv_Data_Graphics.Element,
		at path: String,
	) -> [RenderingDiagnostic] {
		guard case let .media(media)? = element.fill.fillType else { return [] }
		return mediaDiagnostics(media, at: "\(path)/fill/media")
	}

	private func mediaDiagnostics(_ media: Rv_Data_Media, at path: String) -> [RenderingDiagnostic] {
		let source = media.url.renderPath
		guard !source.isEmpty else {
			return [RenderingDiagnostic(
				code: .missingMediaURL,
				severity: .warning,
				componentPath: "\(path)/url",
				message: "Media URL is empty, so the asset cannot be rendered.",
			)]
		}
		guard resolveMedia(media) == nil else { return [] }
		return [RenderingDiagnostic(
			code: .unresolvedMedia,
			severity: .warning,
			componentPath: "\(path)/url",
			message: "Media asset cannot be found at \(source). Embed it in the bundle or replace the reference with a reachable file.",
		)]
	}

	private func resolveMedia(_ media: Rv_Data_Media) -> URL? {
		let source = media.url.renderPath
		let decoded = source.removingPercentEncoding ?? source
		let reference = ThemeTemplateSource.MediaReference(
			uuid: media.uuid.string,
			renderPath: source,
		)
		if preferredMediaReferences.contains(reference) {
			if let absolute = URL(string: source),
			   absolute.isFileURL,
			   FileManager.default.fileExists(atPath: absolute.path)
			{
				return absolute
			}
			return nil
		}
		if let mediaDirectory {
			let sourcePath: String
			if let sourceURL = URL(string: decoded), sourceURL.isFileURL {
				sourcePath = sourceURL.path
			} else {
				sourcePath = decoded
			}
			let normalizedPath = sourcePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
			let embeddedCandidate = mediaDirectory.appendingPathComponent(normalizedPath)
			if FileManager.default.fileExists(atPath: embeddedCandidate.path) {
				return embeddedCandidate
			}
			let basename = URL(fileURLWithPath: decoded).lastPathComponent
			let candidate = mediaDirectory.appendingPathComponent(basename)
			if FileManager.default.fileExists(atPath: candidate.path) {
				return candidate
			}
		}
		if let absolute = URL(string: source),
		   absolute.isFileURL,
		   FileManager.default.fileExists(atPath: absolute.path)
		{
			return absolute
		}
		return nil
	}

	private func number(_ value: Double) -> String {
		value.isFinite ? value.formatted(.number.precision(.fractionLength(0 ... 3))) : String(describing: value)
	}
}
