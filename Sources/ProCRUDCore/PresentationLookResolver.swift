import AppKit
import CoreGraphics
import Foundation
import ProPresenterProto

/// Resolves a fixed Look/Macro variation or the Look state reached in cue order.
/// Macro actions are inspected for Look changes only; no runtime action executes.
public enum PresentationLookResolver {
	public static func resolve(
		document: PresentationDocument,
		configuration: RenderConfiguration,
		screen: RenderConfiguration.Screen,
		look: String? = nil,
		macro: String? = nil,
		slideIndices: Set<Int>? = nil,
	) throws -> PresentationTemplateResolution {
		guard look == nil || macro == nil else { throw RenderConfigurationError.conflictingSelectors }
		return try LookRenderSession(document: document, configuration: configuration, look: look, macro: macro, slideIndices: slideIndices).resolve(screen: screen)
	}
}

private final class LookRenderSession {
	let document: PresentationDocument
	let configuration: RenderConfiguration
	let look: String?
	let macro: String?
	let slideIndices: Set<Int>?
	var resolvedScreens: [String: PresentationTemplateResolution] = [:]
	var images: [String: URL] = [:]
	var resources: TemporaryDirectoryOwner?

	init(document: PresentationDocument, configuration: RenderConfiguration, look: String?, macro: String?, slideIndices: Set<Int>?) {
		self.document = document; self.configuration = configuration; self.look = look; self.macro = macro; self.slideIndices = slideIndices
	}

	func resolve(screen: RenderConfiguration.Screen, path: [String] = [], occurrence: Int? = nil) throws -> PresentationTemplateResolution {
		let identity = screen.uuid.lowercased()
		guard !path.contains(identity) else { throw RenderConfigurationError.screenCycle(path + [identity]) }
		let selectedSlides = occurrence.map { Set([$0]) } ?? slideIndices
		let cacheKey = identity + "/" + (selectedSlides.map { $0.sorted().map(String.init).joined(separator: ",") } ?? "all")
		if let cached = resolvedScreens[cacheKey] {
			return cached
		}

		let actionResolver = try LookActionResolver(configuration: configuration, macros: look == nil ? configuration.macros() : [])
		let fixedLook: Rv_Data_ProAudienceLook?
		if let look {
			fixedLook = try configuration.look(look)
		} else if let macro {
			let selected = try actionResolver.macro(macro)
			guard let resolved = try actionResolver.look(actions: selected.actions, startingAt: nil, path: [selected.uuid.string.lowercased()]) else {
				throw RenderConfigurationError.macroHasNoLook(macro)
			}
			fixedLook = resolved
		} else {
			fixedLook = nil
		}
		let occurrences = try document.cueOccurrences()
		let last = selectedSlides?.max() ?? occurrences.indices.last
		var current = fixedLook ?? configuration.liveLook
		var result = document
		result.renderScreen = .init(uuid: screen.uuid, name: screen.name)
		var reports: [TemplateResolutionReport] = []
		var templates: [String: LookTemplateSelection] = [:]
		let size = try screen.size
		result.renderCanvasSize = size
		for occurrence in occurrences {
			guard let last, occurrence.sequenceIndex <= last else { break }
			if fixedLook == nil {
				current = try actionResolver.look(actions: occurrence.cue.actions, startingAt: current)
			}
			guard selectedSlides?.contains(occurrence.sequenceIndex) ?? true else { continue }
			guard let current else { throw RenderConfigurationError.missingLook(slide: occurrence.sequenceIndex + 1) }
			var cue = occurrence.cue
			guard let index = cue.actions.firstIndex(where: { $0.type == .presentationSlide }),
			      case var .presentation(slide)? = cue.actions[index].slide.slide else { continue }
			let selection: LookTemplateSelection?
			if let cached = templates[current.uuid.string] {
				selection = cached
			} else {
				selection = try configuration.template(look: current, screen: screen)
				if let selection {
					templates[current.uuid.string] = selection
				}
			}
			let resolution: TemplateResolutionResult
			var warnings: [String]
			if let selection {
				resolution = try TemplateResolver.resolve(template: selection.template.slide, source: slide.baseSlide, destinationSize: size, mode: .runtimeLook)
				warnings = selection.warnings
				if let owner = selection.template.temporaryResourceOwner, !result.temporaryResourceOwners.contains(where: { $0 === owner }) {
					result.temporaryResourceOwners.append(owner)
				}
				result.preferredMediaReferences.formUnion(ThemeTemplateSource.mediaReferences(in: resolution.slide).intersection(selection.template.preferredMediaReferences))
			} else {
				resolution = try aspectFit(slide.baseSlide, to: size)
				let mapping = current.screenLooks.first { RenderConfiguration.sameID($0.proScreenUuid.string, screen.uuid) }
				warnings = mapping.map { LookResolver.warnings(mapping: $0) } ?? []
				if case .renderingEnabled(false)? = screen.document?.renderingEnabledOptional {
					warnings.append("This screen is disabled in ProPresenter. A static preview does not enable its output.")
				}
			}
			slide.baseSlide = try materializeScreenLinks(in: resolution.slide, occurrence: occurrence.sequenceIndex, path: path + [identity], document: &result)
			cue.actions[index].slide.presentation = slide
			result.renderCueOverrides[occurrence.sequenceIndex] = cue
			var report = resolution.report
			report.context = .init(presentationUUID: document.presentation.uuid.string, slideIndex: occurrence.sequenceIndex + 1,
			                       lookUUID: current.uuid.string, lookName: current.name, screenUUID: screen.uuid, screenName: screen.name)
			if resolution.slide.elements.contains(where: { $0.dataLinks.contains {
				if case .outputScreen? = $0.propertyType {
					true
				} else {
					false
				}
			} }) {
				report.warnings.append("Output-screen links use the referenced screen's static composition; runtime layers and animated build state are not simulated.")
			}
			report.warnings = Array(Set(report.warnings + warnings)).sorted()
			reports.append(report)
		}
		let resolved = PresentationTemplateResolution(document: result, reports: reports)
		resolvedScreens[cacheKey] = resolved
		return resolved
	}

	private func materializeScreenLinks(in source: Rv_Data_Slide, occurrence: Int, path: [String], document: inout PresentationDocument) throws -> Rv_Data_Slide {
		var slide = source
		for index in slide.elements.indices where !slide.elements[index].element.hidden {
			let links = slide.elements[index].dataLinks.compactMap { link -> Rv_Data_Slide.Element.DataLink.OutputScreen? in
				if case let .outputScreen(value)? = link.propertyType {
					return value
				}
				return nil
			}
			guard let link = links.first else { continue }
			guard links.count == 1 else { throw NativeSemanticError.invalidValue(path: "/elements/\(index)/data_links", expected: "one output-screen link") }
			let selector = link.screenID.string.isEmpty ? link.screenName : link.screenID.string
			let target = try configuration.selectScreens([selector])
			guard let screen = target.first else { throw RenderConfigurationError.selector(kind: "Audience screen", value: selector, candidates: []) }
			let key = "\(screen.uuid)/\(occurrence)"
			let url: URL
			if let cached = images[key] {
				url = cached
			} else {
				let resolved = try resolve(screen: screen, path: path, occurrence: occurrence)
				guard let cue = try resolved.document.cueOccurrences().first(where: { $0.sequenceIndex == occurrence })?.cue else { throw RenderConfigurationError.missingLook(slide: occurrence + 1) }
				let bitmap = try PresentationRenderer(document: resolved.document).render(cue: cue)
				let owner = try resourceOwner()
				url = owner.url.appendingPathComponent(UUID().uuidString + ".png")
				guard let data = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.pngEncodingFailed }
				try data.write(to: url)
				images[key] = url
			}
			if let resources, !document.temporaryResourceOwners.contains(where: { $0 === resources }) {
				document.temporaryResourceOwners.append(resources)
			}
			let media = Rv_Data_Media.with {
				$0.uuid.string = UUID().uuidString
				$0.url.absoluteString = url.absoluteString
				$0.image.drawing.scaleBehavior = .fit
			}
			slide.elements[index].element.fill.enable = true
			slide.elements[index].element.fill.media = media
			slide.elements[index].dataLinks.removeAll {
				if case .outputScreen? = $0.propertyType {
					true
				} else {
					false
				}
			}
			document.preferredMediaReferences.insert(.init(uuid: media.uuid.string, renderPath: media.url.renderPath))
		}
		return slide
	}

	private func resourceOwner() throws -> TemporaryDirectoryOwner {
		if let resources {
			return resources
		}
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProCRUD-Look-" + UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let owner = TemporaryDirectoryOwner(url: root)
		resources = owner
		return owner
	}

	private func aspectFit(_ source: Rv_Data_Slide, to size: CGSize) throws -> TemplateResolutionResult {
		guard source.size.width.isFinite, source.size.height.isFinite, source.size.width > 0, source.size.height > 0 else {
			throw TemplateResolutionError.invalidCanvas(label: "source", width: source.size.width, height: source.size.height)
		}
		let scale = min(size.width / source.size.width, size.height / source.size.height)
		let fitted = CGSize(width: source.size.width * scale, height: source.size.height * scale)
		var slide = source
		var warnings: [String] = []
		if scale != 1 {
			var template = Rv_Data_Template.Slide()
			template.baseSlide = source
			let scaled = try TemplateResolver.resolve(template: template, source: source, destinationSize: fitted, mode: .runtimeLook)
			for index in slide.elements.indices {
				slide.elements[index].element.bounds = scaled.slide.elements[index].element.bounds
				if source.elements[index].element.hasText {
					slide.elements[index].element.text = scaled.slide.elements[index].element.text
				}
			}
			warnings.append("Source geometry and text use uniform aspect-fit scaling. Stroke widths, shadows, feather radii, and media custom bounds retain their stored scalar values.")
		}
		let offset = CGPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2)
		if offset != .zero {
			for index in slide.elements.indices {
				slide.elements[index].element.bounds.origin.x += offset.x
				slide.elements[index].element.bounds.origin.y += offset.y
			}
		}
		slide.size.width = size.width
		slide.size.height = size.height
		let report = TemplateResolutionReport(mode: .runtimeLook, templateName: "Source slide (no alternate Theme)", sourceSlideUUID: source.uuid.string,
		                                      templateSlideUUID: source.uuid.string, resultSlideUUID: source.uuid.string,
		                                      templateSize: .init(width: source.size.width, height: source.size.height), destinationSize: .init(width: size.width, height: size.height),
		                                      transform: .init(xScale: scale, yScale: scale, fontScale: scale), assignments: [], removedSourceElements: [], unfilledTemplateElements: [], warnings: warnings)
		return .init(slide: slide, actions: [], report: report)
	}
}
