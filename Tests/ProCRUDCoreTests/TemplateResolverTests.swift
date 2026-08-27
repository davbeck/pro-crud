import AppKit
import CustomDump
import Foundation
import ProCRUDCore
import ProPresenterProto
import Testing

@Suite("Theme template resolution")
struct TemplateResolverTests {
	@Test
	func appliesTemplateWithObservedMatchingGeometryIdentityAndTextRules() throws {
		let fixture = try makeConflictFixture()
		let result = try TemplateResolver.resolve(
			template: fixture.template,
			source: fixture.source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)

		#expect(result.slide.uuid.string == "SOURCE-SLIDE")
		#expect(result.slide.size.width == 800)
		#expect(result.slide.size.height == 600)
		#expect(result.slide.elements.map(\.element.name) == ["Shared", "Template Secondary", "Template Only"])
		#expect(result.slide.elements[0].element.uuid.string == "SOURCE-SHARED")
		#expect(result.slide.elements[1].element.uuid.string == "SOURCE-PRIMARY")
		#expect(result.slide.elements[2].element.uuid.string == "TEMPLATE-ONLY")
		#expect(result.slide.elements.map(\.info) == [1, 3, 3])
		#expect(result.slide.elements[0].element.bounds.origin.x == 40)
		#expect(result.slide.elements[0].element.bounds.origin.y == 20)
		#expect(result.slide.elements[0].element.bounds.size.width == 720)
		#expect(result.slide.elements[0].element.bounds.size.height == 200)
		#expect(result.slide.elements[2].element.hasText)
		#expect(try attributedText(result.slide.elements[2]).string.isEmpty)
		#expect(result.slide.elements[2].element.text.attributes.font.size == 84)
		#expect(result.slide.elements[2].element.text.attributes.paragraphStyle.defaultTabInterval == 84)

		expectNoDifference(
			result.report.assignments.map(\.reason),
			["exact-name", "reverse-order-text-fallback"],
		)
		expectNoDifference(result.report.removedSourceElements.map(\.name), ["Source Only"])
		expectNoDifference(result.report.unfilledTemplateElements.map(\.name), ["Template Only"])
		#expect(result.report.transform.xScale == 2)
		#expect(result.report.transform.yScale == 2)
		#expect(result.report.transform.fontScale == 2)

		let shared = try attributedText(result.slide.elements[0])
		#expect(shared.string == "SECOND SOURCE")
		let sharedFont = try #require(shared.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
		#expect(sharedFont.familyName == "Courier New")
		#expect(abs(sharedFont.pointSize - 40) < 0.01)
		let sharedColor = try #require((shared.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.usingColorSpace(.deviceRGB))
		#expect(sharedColor.redComponent > 0.95)
		#expect(sharedColor.greenComponent > 0.85)

		let mixed = try attributedText(result.slide.elements[1])
		#expect(mixed.string == "Source normal SPECIALtail")
		let ordinaryFont = try #require(mixed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
		#expect(ordinaryFont.familyName == "Courier New")
		#expect(abs(ordinaryFont.pointSize - 32) < 0.01)
		let specialFont = try #require(mixed.attribute(.font, at: 14, effectiveRange: nil) as? NSFont)
		#expect(specialFont.familyName == "Times New Roman")
		#expect(abs(specialFont.pointSize - 48) < 0.01)
		#expect(NSFontManager.shared.traits(of: specialFont).contains(.boldFontMask))
		#expect(NSFontManager.shared.traits(of: specialFont).contains(.italicFontMask))
		#expect((mixed.attribute(.underlineStyle, at: 14, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)
		let firstColor = try #require((mixed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.usingColorSpace(.deviceRGB))
		let specialColor = try #require((mixed.attribute(.foregroundColor, at: 14, effectiveRange: nil) as? NSColor)?.usingColorSpace(.deviceRGB))
		#expect(firstColor.redComponent < 0.95)
		#expect(specialColor.redComponent > 0.95)
	}

	@Test
	func exactNameCanPopulateGraphicsSlotAndDuplicateNamesPairInStoredOrder() throws {
		var fixture = try makeConflictFixture()
		fixture.source.elements[0].element.name = "Template Only"
		let typeResult = try TemplateResolver.resolve(
			template: fixture.template,
			source: fixture.source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)
		#expect(try attributedText(typeResult.slide.elements[2]).string == "Source normal SPECIALtail")
		#expect(typeResult.slide.elements[2].element.uuid.string == "SOURCE-PRIMARY")

		let plainFont = try #require(NSFont(name: "Helvetica", size: 24))
		var source = makeSlide(uuid: "DUP-SOURCE", width: 800, height: 600)
		source.elements = try [
			textElement(uuid: "SOURCE-DUP-0", name: "Dup", bounds: .zero, segments: [("FIRST", plainFont, .white, false)]),
			textElement(uuid: "SOURCE-DUP-1", name: "Dup", bounds: .zero, segments: [("SECOND", plainFont, .white, false)]),
		]
		var template = Rv_Data_Template.Slide()
		template.name = "Duplicates"
		template.baseSlide = makeSlide(uuid: "DUP-TEMPLATE", width: 400, height: 300)
		template.baseSlide.elements = try [
			textElement(uuid: "TEMPLATE-DUP-0", name: "Dup", bounds: .zero, segments: [("A", plainFont, .white, false)]),
			textElement(uuid: "TEMPLATE-DUP-1", name: "Dup", bounds: .zero, segments: [("B", plainFont, .white, false)]),
		]
		let duplicateResult = try TemplateResolver.resolve(
			template: template,
			source: source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)
		#expect(try attributedText(duplicateResult.slide.elements[0]).string == "FIRST")
		#expect(try attributedText(duplicateResult.slide.elements[1]).string == "SECOND")
		#expect(duplicateResult.slide.elements[0].element.uuid.string == "SOURCE-DUP-0")
		#expect(duplicateResult.slide.elements[1].element.uuid.string == "SOURCE-DUP-1")
	}

	@Test
	func instantiatesAtDestinationSizeClearsSamplesAndFreshensCompleteGraph() throws {
		var fixture = try makeConflictFixture()
		var action = Rv_Data_Action()
		action.uuid.string = "TEMPLATE-ACTION"
		action.type = .media
		action.media.element.uuid.string = "MEDIA-ASSET"
		var marker = Rv_Data_Action.MediaType.PlaybackMarker()
		marker.uuid.string = "MARKER"
		var nested = Rv_Data_Action()
		nested.uuid.string = "NESTED-ACTION"
		marker.actions = [nested]
		action.media.markers = [marker]
		var nestedSlideAction = Rv_Data_Action()
		nestedSlideAction.uuid.string = "NESTED-SLIDE-ACTION"
		nestedSlideAction.type = .presentationSlide
		nestedSlideAction.slide.presentation.baseSlide.uuid.string = "NESTED-SLIDE"
		var wrapperGuide = Rv_Data_AlignmentGuide()
		wrapperGuide.uuid.string = "WRAPPER-GUIDE"
		nestedSlideAction.slide.presentation.templateGuidelines = [wrapperGuide]
		fixture.template.actions = [action, nestedSlideAction]

		let result = try TemplateResolver.resolve(
			template: fixture.template,
			source: nil,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .instantiateNew,
		)
		#expect(result.slide.size.width == 800)
		#expect(result.slide.size.height == 600)
		#expect(result.slide.uuid != fixture.template.baseSlide.uuid)
		#expect(Set(result.slide.elements.map(\.element.uuid.string)).count == result.slide.elements.count)
		for element in result.slide.elements {
			#expect(try attributedText(element).string.isEmpty)
		}
		#expect(result.slide.elements[0].element.text.attributes.font.size == 20)
		#expect(result.slide.elements[2].element.text.attributes.font.size == 42)
		#expect(result.slide.elements.map(\.info) == [1, 3, 3])
		#expect(result.slide.elements[2].element.text.attributes.paragraphStyle.defaultTabInterval == 84)
		#expect(result.slide.elements[0].element.bounds.origin.x == 40)
		#expect(result.actions[0].uuid.string != "TEMPLATE-ACTION")
		#expect(result.actions[0].media.element.uuid.string == "MEDIA-ASSET")
		#expect(result.actions[0].media.markers[0].uuid.string != "MARKER")
		#expect(result.actions[0].media.markers[0].actions[0].uuid.string != "NESTED-ACTION")
		#expect(result.actions[1].slide.presentation.templateGuidelines[0].uuid.string != "WRAPPER-GUIDE")

		let presentation = try DocumentFactory.applying(
			template: fixture.template,
			to: DocumentFactory.presentation(
				name: "Destination",
				canvasSize: CGSize(width: 1280, height: 720),
			),
		)
		let slide = presentation.cues[0].actions[0].slide.presentation.baseSlide
		#expect(slide.size.width == 1280)
		#expect(slide.size.height == 720)
		#expect(presentation.cues[0].actions.count == 1)
	}

	@Test
	func normalizesOnlyTheObservedTemplateElementInfoValueWithoutReordering() throws {
		let input: [UInt32] = [0, 1, 2, 3, 4, .max]
		var template = Rv_Data_Template.Slide()
		template.name = "Element Info"
		template.baseSlide = makeSlide(uuid: "INFO-TEMPLATE", width: 400, height: 300)
		template.baseSlide.elements = input.indices.map { index in
			shapeElement(uuid: "INFO-\(index)", name: "Element \(index)", bounds: .zero)
		}
		for index in input.indices {
			template.baseSlide.elements[index].info = input[index]
		}

		let result = try TemplateResolver.resolve(
			template: template,
			source: nil,
			destinationSize: CGSize(width: 400, height: 300),
			mode: .instantiateNew,
		)
		#expect(result.slide.elements.map(\.element.name) == input.indices.map { "Element \($0)" })
		#expect(result.slide.elements.map(\.info) == [0, 1, 3, 3, 4, .max])
	}

	@Test
	func addingTemplateSlideToEmptyGroupUsesCurrentPresentationCanvas() throws {
		let fixture = try makeConflictFixture()
		var presentation = DocumentFactory.presentation(
			name: "Empty Group",
			canvasSize: CGSize(width: 800, height: 600),
		)
		var emptyGroup = Rv_Data_Presentation.CueGroup()
		emptyGroup.group.uuid.string = "EMPTY-GROUP"
		emptyGroup.group.name = "Empty"
		presentation.cueGroups.append(emptyGroup)

		let report = try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath("/cue_groups[index=1]"),
			template: fixture.template,
		)

		let addedCue = try #require(presentation.cues.last)
		let addedAction = try #require(addedCue.actions.first { $0.type == .presentationSlide })
		let addedSlide = addedAction.slide.presentation.baseSlide
		#expect(addedSlide.size.width == 800)
		#expect(addedSlide.size.height == 600)
		#expect(report?.destinationSize.width == 800)
		#expect(report?.destinationSize.height == 600)
		#expect(presentation.cueGroups[1].cueIdentifiers == [addedCue.uuid])
	}

	@Test
	func addingTemplateSlideUsesAfterCueCanvasBeforeTargetGroupCanvas() throws {
		let fixture = try makeConflictFixture()
		var presentation = DocumentFactory.presentation(
			name: "After Canvas",
			canvasSize: CGSize(width: 800, height: 600),
		)
		try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath("/cue_groups[index=0]"),
		)
		presentation.cues[1].actions[0].slide.presentation.baseSlide.size.width = 1024
		presentation.cues[1].actions[0].slide.presentation.baseSlide.size.height = 768
		let afterCueID = presentation.cues[1].uuid.string

		try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath("/cue_groups[index=0]"),
			after: ComponentPath("/cues[uuid=\(afterCueID)]"),
			template: fixture.template,
		)

		let addedCue = try #require(presentation.cues.last)
		let addedAction = try #require(addedCue.actions.first { $0.type == .presentationSlide })
		let addedSlide = addedAction.slide.presentation.baseSlide
		#expect(addedSlide.size.width == 1024)
		#expect(addedSlide.size.height == 768)
		#expect(presentation.cueGroups[0].cueIdentifiers == presentation.cues.map(\.uuid))
	}

	@Test
	func factoryAppliesToPresentationActionWhenAnotherActionComesFirst() throws {
		let fixture = try makeConflictFixture()
		var presentation = DocumentFactory.presentation(
			name: "Action Order",
			canvasSize: CGSize(width: 1280, height: 720),
		)
		let slideAction = presentation.cues[0].actions[0]
		var mediaAction = Rv_Data_Action()
		mediaAction.uuid.string = "LEADING-MEDIA"
		mediaAction.type = .media
		mediaAction.label.text = "Keep Media Label"
		presentation.cues[0].actions = [mediaAction, slideAction]

		let application = try DocumentFactory.applyingWithReport(
			template: fixture.template,
			to: presentation,
		)
		let actions = application.presentation.cues[0].actions
		#expect(actions.map(\.type) == [.media, .presentationSlide])
		#expect(actions.map(\.uuid) == [mediaAction.uuid, slideAction.uuid])
		#expect(actions[0].label.text == "Keep Media Label")
		#expect(actions[1].label.text == fixture.template.name)
		#expect(actions[1].slide.presentation.baseSlide.size.width == 1280)
		#expect(actions[1].slide.presentation.baseSlide.size.height == 720)
	}

	@Test
	func factoryRejectsFirstCueWithoutPresentationAction() throws {
		let fixture = try makeConflictFixture()
		var presentation = DocumentFactory.presentation(name: "No Slide")
		var mediaAction = Rv_Data_Action()
		mediaAction.type = .media
		presentation.cues[0].actions = [mediaAction]

		#expect(throws: DocumentCreationError.self) {
			try DocumentFactory.applyingWithReport(
				template: fixture.template,
				to: presentation,
			)
		}
	}

	@Test
	func graphCopyRemapsKnownInternalReferencesAndPreservesExternalIdentities() throws {
		var slide = makeSlide(uuid: "SLIDE", width: 800, height: 600)
		var first = shapeElement(uuid: "FIRST", name: "First", bounds: .zero)
		var second = shapeElement(uuid: "SECOND", name: "Second", bounds: .zero)
		first.buildIn.uuid.string = "BUILD-IN"
		first.buildIn.elementUuid.string = "SECOND"
		first.buildOut.uuid.string = "BUILD-OUT"
		first.buildOut.elementUuid.string = "FIRST"
		var child = Rv_Data_Slide.Element.ChildBuild()
		child.uuid.string = "CHILD"
		first.childBuilds = [child]

		var alternateText = Rv_Data_Slide.Element.DataLink()
		alternateText.alternateText.otherElementUuid.string = "SECOND"
		var alternateFill = Rv_Data_Slide.Element.DataLink()
		alternateFill.alternateFill.otherElementUuid.string = "FIRST"
		var elementVisibility = Rv_Data_Slide.Element.DataLink.VisibilityLink.Condition.ElementVisibility()
		elementVisibility.otherElementUuid.string = "SECOND"
		var condition = Rv_Data_Slide.Element.DataLink.VisibilityLink.Condition()
		condition.elementVisibility = elementVisibility
		var visibility = Rv_Data_Slide.Element.DataLink.VisibilityLink()
		visibility.conditions = [condition]
		var visibilityLink = Rv_Data_Slide.Element.DataLink()
		visibilityLink.visibilityLink = visibility
		first.dataLinks = [alternateText, alternateFill, visibilityLink]
		second.dataLinks = []
		slide.elements = [first, second]
		slide.elementBuildOrder = [uuid("CHILD")]
		var guide = Rv_Data_AlignmentGuide()
		guide.uuid.string = "GUIDE"
		slide.guidelines = [guide]

		let copy = ProPresenterGraphCopier.freshSlide(slide)
		let newFirst = copy.elements[0].element.uuid
		let newSecond = copy.elements[1].element.uuid
		#expect(copy.uuid.string != "SLIDE")
		#expect(newFirst.string != "FIRST")
		#expect(newSecond.string != "SECOND")
		#expect(copy.elements[0].buildIn.uuid.string != "BUILD-IN")
		#expect(copy.elements[0].buildIn.elementUuid == newSecond)
		#expect(copy.elements[0].buildOut.uuid.string != "BUILD-OUT")
		#expect(copy.elements[0].buildOut.elementUuid == newFirst)
		#expect(copy.elements[0].childBuilds[0].uuid.string != "CHILD")
		#expect(copy.elementBuildOrder == [copy.elements[0].childBuilds[0].uuid])
		#expect(copy.elements[0].dataLinks[0].alternateText.otherElementUuid == newSecond)
		#expect(copy.elements[0].dataLinks[1].alternateFill.otherElementUuid == newFirst)
		#expect(copy.elements[0].dataLinks[2].visibilityLink.conditions[0].elementVisibility.otherElementUuid == newSecond)
		#expect(copy.guidelines[0].uuid.string != "GUIDE")

		var presentation = DocumentFactory.presentation(name: "Self Target")
		presentation.cues[0].completionTargetType = .cue
		presentation.cues[0].completionTargetUuid = presentation.cues[0].uuid
		try DocumentEditor.addBlankSlide(
			to: &presentation,
			groupPath: ComponentPath("/cue_groups[index=0]"),
			duplicateCuePath: ComponentPath("/cues[index=0]"),
		)
		#expect(presentation.cues[1].completionTargetUuid == presentation.cues[1].uuid)
	}

	@Test
	func editApplyPreservesPresentationWrapperAndUsesExplicitActionPolicy() throws {
		let fixture = try makeConflictFixture()
		var presentation = DocumentFactory.presentation(name: "Wrapper")
		presentation.cues[0].actions[0].slide.presentation.baseSlide = fixture.source
		presentation.cues[0].actions[0].slide.presentation.notes.rtfData = Data("notes".utf8)
		presentation.cues[0].actions[0].slide.presentation.chordChart.absoluteString = "file:///chart.txt"
		var guideline = Rv_Data_AlignmentGuide()
		guideline.uuid.string = "WRAPPER-GUIDE"
		presentation.cues[0].actions[0].slide.presentation.templateGuidelines = [guideline]
		let cueID = presentation.cues[0].uuid
		let actionID = presentation.cues[0].actions[0].uuid
		var template = fixture.template
		var mediaAction = Rv_Data_Action()
		mediaAction.uuid.string = "THEME-MEDIA-ACTION"
		mediaAction.type = .media
		template.actions = [mediaAction]

		let report = try DocumentEditor.applyTemplate(
			in: &presentation,
			at: ComponentPath("/cues[index=0]"),
			template: template,
			actionPolicy: .append,
		)
		#expect(report.mode == .applyExisting)
		#expect(presentation.cues[0].uuid == cueID)
		#expect(presentation.cues[0].actions[0].uuid == actionID)
		#expect(presentation.cues[0].actions[0].slide.presentation.notes.rtfData == Data("notes".utf8))
		#expect(presentation.cues[0].actions[0].slide.presentation.chordChart.absoluteString == "file:///chart.txt")
		#expect(presentation.cues[0].actions[0].slide.presentation.templateGuidelines[0].uuid.string == "WRAPPER-GUIDE")
		#expect(presentation.cues[0].actions.count == 2)
		#expect(presentation.cues[0].actions[1].uuid.string != "THEME-MEDIA-ACTION")

		var replacement = DocumentFactory.presentation(name: "Replace Actions")
		replacement.cues[0].actions[0].slide.presentation.baseSlide = fixture.source
		let retainedSlideAction = replacement.cues[0].actions[0]
		var firstMedia = Rv_Data_Action()
		firstMedia.uuid.string = "FIRST-MEDIA"
		firstMedia.type = .media
		var secondMedia = Rv_Data_Action()
		secondMedia.uuid.string = "SECOND-MEDIA"
		secondMedia.type = .media
		replacement.cues[0].actions = [firstMedia, secondMedia, retainedSlideAction]
		try DocumentEditor.applyTemplate(
			in: &replacement,
			at: ComponentPath("/cues[index=0]"),
			template: template,
			actionPolicy: .replace,
		)
		#expect(replacement.cues[0].actions.count == 2)
		#expect(replacement.cues[0].actions[0].uuid.string != "THEME-MEDIA-ACTION")
		#expect(replacement.cues[0].actions[1].uuid == retainedSlideAction.uuid)
	}

	@Test
	func customAttributeRangesUseUTF16AndArePreservedClippedOrDropped() throws {
		let sourceFont = try #require(NSFont(name: "Helvetica", size: 30))
		let templateFont = try #require(NSFont(name: "Courier New", size: 20))
		var source = makeSlide(uuid: "UNICODE-SOURCE", width: 800, height: 600)
		var sourceElement = try textElement(
			uuid: "UNICODE-ELEMENT",
			name: "Unicode",
			bounds: .zero,
			segments: [("A😀B", sourceFont, .white, false)],
		)
		var emojiSize = Rv_Data_Graphics.Text.Attributes.CustomAttribute()
		emojiSize.range.start = 1
		emojiSize.range.end = 3
		emojiSize.originalFontSize = 30
		var clipped = Rv_Data_Graphics.Text.Attributes.CustomAttribute()
		clipped.range.start = -4
		clipped.range.end = 99
		clipped.capitalization = .allCaps
		var stale = Rv_Data_Graphics.Text.Attributes.CustomAttribute()
		stale.range.start = 9
		stale.range.end = 10
		stale.chord = "C"
		var rangeOnly = Rv_Data_Graphics.Text.Attributes.CustomAttribute()
		rangeOnly.range.start = 0
		rangeOnly.range.end = 1
		sourceElement.element.text.attributes.customAttributes = [emojiSize, clipped, stale, rangeOnly]
		source.elements = [sourceElement]

		var template = Rv_Data_Template.Slide()
		template.name = "Unicode Template"
		template.baseSlide = makeSlide(uuid: "UNICODE-TEMPLATE", width: 400, height: 300)
		template.baseSlide.elements = try [textElement(
			uuid: "UNICODE-SLOT",
			name: "Unicode",
			bounds: .zero,
			segments: [("SAMPLE", templateFont, .yellow, false)],
		)]

		let result = try TemplateResolver.resolve(
			template: template,
			source: source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)
		let attributes = result.slide.elements[0].element.text.attributes.customAttributes
		#expect(attributes.count == 2)
		#expect(attributes[0].range.start == 1)
		#expect(attributes[0].range.end == 3)
		#expect(attributes[0].originalFontSize == 30)
		#expect(attributes[1].range.start == 0)
		#expect(attributes[1].range.end == 4)
		#expect(result.report.warnings.contains { $0.contains("clipped or dropped") })
		#expect(result.report.warnings.contains { $0.contains("range-only") })
		#expect(result.report.warnings.contains { $0.contains("native template-application behavior is unproven") })
	}

	@Test
	func rejectsUndecodableSourceRTFInsteadOfDroppingContent() throws {
		var fixture = try makeConflictFixture()
		fixture.source.elements[0].element.text.rtfData = Data([0x00, 0xFF, 0x00, 0xFF])
		#expect(throws: TemplateResolutionError.self) {
			try TemplateResolver.resolve(
				template: fixture.template,
				source: fixture.source,
				destinationSize: CGSize(width: 800, height: 600),
				mode: .applyExisting,
			)
		}
	}

	@Test
	func warnsWhenUnknownFieldsMayContainUnmappedReferences() throws {
		var fixture = try makeConflictFixture()
		let unknown = try Rv_Data_Graphics.Fill(serializedBytes: Data([0xA0, 0x06, 0x01]))
		fixture.template.baseSlide.elements[0].element.fill.unknownFields = unknown.unknownFields
		let result = try TemplateResolver.resolve(
			template: fixture.template,
			source: fixture.source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)
		#expect(result.slide.elements[0].element.fill.unknownFields == unknown.unknownFields)
		#expect(result.report.warnings.contains { $0.contains("UUID references hidden inside") })
	}

	@Test
	func warnsWhenSourceBuildAndDeliveryStateIsDiscarded() throws {
		var fixture = try makeConflictFixture()
		addBuildAndDeliveryState(to: &fixture.source, prefix: "SOURCE")

		let result = try TemplateResolver.resolve(
			template: fixture.template,
			source: fixture.source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)

		expectNoDifference(result.report.warnings, [
			"Source Build In/Out and Build Order state is not transferred; the template slide wrapper remains authoritative. Native precedence and remapping behavior are unproven.",
			"Source text Delivery state is not transferred; the template slide wrapper remains authoritative. Native precedence and segmentation behavior are unproven.",
		])
		#expect(result.slide.elementBuildOrder.isEmpty)
		#expect(result.slide.elements.allSatisfy { !$0.hasBuildIn && !$0.hasBuildOut })
		#expect(result.slide.elements.allSatisfy {
			$0.revealType == .none && $0.childBuilds.isEmpty && $0.revealFromIndex == 0
		})
	}

	@Test
	func warnsWhenTemplateBuildAndDeliveryStateIsRetained() throws {
		var fixture = try makeConflictFixture()
		addBuildAndDeliveryState(to: &fixture.template.baseSlide, prefix: "TEMPLATE")

		let result = try TemplateResolver.resolve(
			template: fixture.template,
			source: fixture.source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)

		expectNoDifference(result.report.warnings, [
			"Template Build In/Out and Build Order state is retained in the resolved slide; native precedence and remapping behavior are unproven.",
			"Template text Delivery state is retained in the resolved slide; native precedence and segmentation behavior are unproven.",
		])
		#expect(result.slide.elementBuildOrder.count == 2)
		#expect(result.slide.elements[2].hasBuildIn)
		#expect(result.slide.elements[0].revealType == .bullet)
		#expect(result.slide.elements[0].childBuilds.count == 1)
	}

	@Test
	func doesNotWarnWhenSourceAndTemplateHaveNoBuildOrDeliveryState() throws {
		let fixture = try makeConflictFixture()
		let result = try TemplateResolver.resolve(
			template: fixture.template,
			source: fixture.source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)

		expectNoDifference(result.report.warnings, [])
	}

	@Test
	func usesProtobufTextMetadataWhenTemplateRTFIsEmpty() throws {
		var fixture = try makeConflictFixture()
		var text = fixture.template.baseSlide.elements[0].element.text
		text.rtfData = Data()
		text.attributes.kerning = 3.5
		text.attributes.underlineStyle.style = .single
		text.attributes.underlineStyle.pattern = .dash
		text.attributes.underlineStyle.byWord = true
		text.attributes.strikethroughStyle.style = .double
		text.attributes.superscript = 1
		text.attributes.strokeWidth = -2
		text.attributes.backgroundColor = protobufColor(.systemPurple)
		var tab = Rv_Data_Graphics.Text.Attributes.Paragraph.TabStop()
		tab.location = 123
		tab.alignment = .right
		text.attributes.paragraphStyle.tabStops = [tab]
		var list = Rv_Data_Graphics.Text.Attributes.Paragraph.TextList()
		list.isEnabled = true
		list.numberType = .decimal
		list.startingNumber = 4
		text.attributes.paragraphStyle.textLists = [list]
		fixture.template.baseSlide.elements[0].element.text = text

		let result = try TemplateResolver.resolve(
			template: fixture.template,
			source: fixture.source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)
		let attributed = try attributedText(result.slide.elements[0])
		let attributes = attributed.attributes(at: 0, effectiveRange: nil)
		#expect((attributes[.kern] as? NSNumber)?.doubleValue == 3.5)
		let underline = try #require((attributes[.underlineStyle] as? NSNumber)?.intValue)
		#expect(underline & NSUnderlineStyle.single.rawValue != 0)
		#expect(underline & NSUnderlineStyle.patternDash.rawValue != 0)
		#expect(underline & NSUnderlineStyle.byWord.rawValue != 0)
		#expect((attributes[.strikethroughStyle] as? NSNumber)?.intValue == NSUnderlineStyle.double.rawValue)
		#expect((attributes[.superscript] as? NSNumber)?.intValue == 1)
		#expect((attributes[.strokeWidth] as? NSNumber)?.doubleValue == -2)
		let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
		#expect(paragraph.tabStops.count == 1)
		#expect(paragraph.tabStops[0].location == 123)
		#expect(paragraph.tabStops[0].alignment == .right)
		#expect(paragraph.textLists.count == 1)
		#expect(paragraph.textLists[0].startingItemNumber == 4)
	}

	@Test
	func templateMediaMaterializationRejectsOnlyIntroducedIdentityConflicts() throws {
		try withTemplateResolverTemporaryDirectory { directory in
			let destination = directory.appendingPathComponent("Destination", isDirectory: true)
			try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
			let existingURL = destination.appendingPathComponent("existing.bin")
			let templateURL = directory.appendingPathComponent("template.bin")
			try Data([0x01]).write(to: existingURL)
			try Data([0x02]).write(to: templateURL)

			var presentation = DocumentFactory.presentation(name: "Collision")
			presentation.cues[0].actions.append(mediaAction(
				uuid: "SHARED-MEDIA",
				storage: .relativePath("existing.bin"),
			))
			presentation.cues[0].actions.append(mediaAction(
				uuid: "SHARED-MEDIA",
				storage: .absoluteString(templateURL.absoluteString),
			))

			#expect(throws: TemplateMediaMaterializationError.self) {
				try TemplateMediaMaterializer.materialize(
					in: &presentation,
					absoluteURLs: [templateURL.absoluteString],
					destinationDirectory: destination,
				)
			}
		}
	}

	@Test
	func templateMediaMaterializationIgnoresUnrelatedDuplicateIdentitiesAndReuseProperties() throws {
		try withTemplateResolverTemporaryDirectory { directory in
			let destination = directory.appendingPathComponent("Destination", isDirectory: true)
			try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
			try Data([0x01]).write(to: destination.appendingPathComponent("first.bin"))
			try Data([0x02]).write(to: destination.appendingPathComponent("second.bin"))
			let templateURL = directory.appendingPathComponent("template.bin")
			try Data([0x03]).write(to: templateURL)

			var presentation = DocumentFactory.presentation(name: "Scoped validation")
			presentation.cues[0].actions.append(mediaAction(
				uuid: "UNRELATED-DUPLICATE",
				storage: .relativePath("first.bin"),
			))
			presentation.cues[0].actions.append(mediaAction(
				uuid: "UNRELATED-DUPLICATE",
				storage: .relativePath("second.bin"),
			))
			var firstTemplateAction = mediaAction(
				uuid: "TEMPLATE-MEDIA",
				storage: .absoluteString(templateURL.absoluteString),
			)
			firstTemplateAction.media.element.image.drawing.customImageBounds.size.width = 100
			var secondTemplateAction = firstTemplateAction
			secondTemplateAction.uuid.string = "SECOND-TEMPLATE-ACTION"
			secondTemplateAction.media.element.image.drawing.customImageBounds.size.width = 200
			presentation.cues[0].actions.append(contentsOf: [firstTemplateAction, secondTemplateAction])

			try TemplateMediaMaterializer.materialize(
				in: &presentation,
				absoluteURLs: [templateURL.absoluteString],
				destinationDirectory: destination,
			)
			let materialized = presentation.cues[0].actions.suffix(2).map(\.media.element.url.relativePath)
			#expect(materialized == ["template.bin", "template.bin"])
			#expect(FileManager.default.contentsEqual(
				atPath: templateURL.path,
				andPath: destination.appendingPathComponent("template.bin").path,
			))
		}
	}

	@Test
	func preservesDominantExceptionalUnderlineAndRemovesUniformBoldFromExceptionalFamily() throws {
		let plain = try #require(NSFont(name: "Helvetica Neue", size: 30))
		let bold = try #require(NSFont(name: "Helvetica Neue Bold", size: 30))
		let exceptionalBold = try #require(NSFont(name: "Times New Roman Bold", size: 30))
		let templateFont = try #require(NSFont(name: "Courier New", size: 20))
		var source = makeSlide(uuid: "ATTRIBUTE-SOURCE", width: 800, height: 600)
		source.elements = try [
			textElement(
				uuid: "UNDERLINE-SOURCE",
				name: "Underline",
				bounds: .zero,
				segments: [
					("A", plain, .white, false),
					("DOMINANT UNDERLINE", plain, .white, true),
					("B", plain, .white, false),
				],
			),
			textElement(
				uuid: "FONT-SOURCE",
				name: "Font",
				bounds: .zero,
				segments: [
					("BASE ", bold, .white, false),
					("FAMILY", exceptionalBold, .white, false),
				],
			),
		]
		var template = Rv_Data_Template.Slide()
		template.name = "Attributes"
		template.baseSlide = makeSlide(uuid: "ATTRIBUTE-TEMPLATE", width: 400, height: 300)
		template.baseSlide.elements = try [
			textElement(
				uuid: "UNDERLINE-TEMPLATE",
				name: "Underline",
				bounds: .zero,
				segments: [("SAMPLE", templateFont, .yellow, false)],
			),
			textElement(
				uuid: "FONT-TEMPLATE",
				name: "Font",
				bounds: .zero,
				segments: [("SAMPLE", templateFont, .yellow, false)],
			),
		]
		let result = try TemplateResolver.resolve(
			template: template,
			source: source,
			destinationSize: CGSize(width: 800, height: 600),
			mode: .applyExisting,
		)
		let underline = try attributedText(result.slide.elements[0])
		#expect((underline.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)
		#expect((underline.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
		let fontText = try attributedText(result.slide.elements[1])
		let exceptional = try #require(fontText.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
		#expect(exceptional.familyName == "Times New Roman")
		#expect(!NSFontManager.shared.traits(of: exceptional).contains(.boldFontMask))
	}
}

private struct ConflictFixture {
	var source: Rv_Data_Slide
	var template: Rv_Data_Template.Slide
}

private func makeConflictFixture() throws -> ConflictFixture {
	let helvetica = try #require(NSFont(name: "Helvetica", size: 30))
	let special = try #require(NSFont(name: "Times New Roman Bold Italic", size: 45))
	let courier20 = try #require(NSFont(name: "Courier New", size: 20))
	let courier16 = try #require(NSFont(name: "Courier New", size: 16))
	var source = makeSlide(uuid: "SOURCE-SLIDE", width: 800, height: 600)
	source.elements = try [
		textElement(
			uuid: "SOURCE-PRIMARY",
			name: "Source Primary",
			bounds: CGRect(x: 0, y: 0, width: 500, height: 100),
			segments: [
				("Source normal ", helvetica, NSColor(white: 0.92, alpha: 1), false),
				("SPECIAL", special, .red, true),
				("tail", helvetica, .systemBlue, false),
			],
		),
		textElement(
			uuid: "SOURCE-SHARED",
			name: "Shared",
			bounds: CGRect(x: 0, y: 0, width: 500, height: 100),
			segments: [("SECOND SOURCE", helvetica, .white, false)],
		),
		shapeElement(uuid: "SOURCE-ONLY", name: "Source Only", bounds: CGRect(x: 0, y: 0, width: 50, height: 50)),
	]

	var template = Rv_Data_Template.Slide()
	template.name = "Conflict Template"
	template.baseSlide = makeSlide(uuid: "TEMPLATE-SLIDE", width: 400, height: 300)
	template.baseSlide.elements = try [
		textElement(
			uuid: "TEMPLATE-SHARED",
			name: "Shared",
			bounds: CGRect(x: 20, y: 10, width: 360, height: 100),
			segments: [("TEMPLATE SHARED", courier20, .yellow, false)],
		),
		textElement(
			uuid: "TEMPLATE-SECONDARY",
			name: "Template Secondary",
			bounds: CGRect(x: 20, y: 140, width: 200, height: 60),
			segments: [("TEMPLATE SECONDARY", courier16, .green, false)],
		),
		shapeElement(
			uuid: "TEMPLATE-ONLY",
			name: "Template Only",
			bounds: CGRect(x: 250, y: 210, width: 120, height: 90),
		),
	]
	template.baseSlide.elements[0].info = 1
	template.baseSlide.elements[1].info = 2
	template.baseSlide.elements[2].info = 3
	return ConflictFixture(source: source, template: template)
}

private func makeSlide(uuid value: String, width: Double, height: Double) -> Rv_Data_Slide {
	var slide = Rv_Data_Slide()
	slide.uuid.string = value
	slide.size.width = width
	slide.size.height = height
	return slide
}

private func shapeElement(uuid value: String, name: String, bounds: CGRect) -> Rv_Data_Slide.Element {
	var element = Rv_Data_Graphics.Element()
	element.uuid.string = value
	element.name = name
	element.opacity = 1
	element.bounds.origin.x = bounds.origin.x
	element.bounds.origin.y = bounds.origin.y
	element.bounds.size.width = bounds.width
	element.bounds.size.height = bounds.height
	var slideElement = Rv_Data_Slide.Element()
	slideElement.element = element
	return slideElement
}

private func textElement(
	uuid value: String,
	name: String,
	bounds: CGRect,
	segments: [(String, NSFont, NSColor, Bool)],
) throws -> Rv_Data_Slide.Element {
	var slideElement = shapeElement(uuid: value, name: name, bounds: bounds)
	let attributed = NSMutableAttributedString()
	for (string, font, color, underline) in segments {
		var attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: color,
		]
		if underline {
			attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
		}
		attributed.append(NSAttributedString(string: string, attributes: attributes))
	}
	let baseFont = try #require(segments.first?.1)
	let baseColor = try #require(segments.first?.2)
	slideElement.element.text.rtfData = try attributed.data(
		from: NSRange(location: 0, length: attributed.length),
		documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf],
	)
	slideElement.element.text.attributes.font.name = baseFont.fontName
	slideElement.element.text.attributes.font.family = baseFont.familyName ?? ""
	slideElement.element.text.attributes.font.size = baseFont.pointSize
	slideElement.element.text.attributes.textSolidFill = protobufColor(baseColor)
	slideElement.element.text.scaleBehavior = .scaleFontDown
	return slideElement
}

private func attributedText(_ element: Rv_Data_Slide.Element) throws -> NSAttributedString {
	try NSAttributedString(
		data: element.element.text.rtfData,
		options: [.documentType: NSAttributedString.DocumentType.rtf],
		documentAttributes: nil,
	)
}

private func protobufColor(_ source: NSColor) -> Rv_Data_Color {
	let color = source.usingColorSpace(.deviceRGB) ?? source
	var result = Rv_Data_Color()
	result.red = Float(color.redComponent)
	result.green = Float(color.greenComponent)
	result.blue = Float(color.blueComponent)
	result.alpha = Float(color.alphaComponent)
	return result
}

private func uuid(_ string: String) -> Rv_Data_UUID {
	var value = Rv_Data_UUID()
	value.string = string
	return value
}

private func addBuildAndDeliveryState(to slide: inout Rv_Data_Slide, prefix: String) {
	let deliveryIndex = 0
	let objectBuildIndex = slide.elements.count - 1

	slide.elements[objectBuildIndex].buildIn.uuid.string = "\(prefix)-OBJECT-BUILD-IN"
	slide.elements[objectBuildIndex].buildIn.elementUuid = slide.elements[objectBuildIndex].element.uuid
	slide.elements[deliveryIndex].buildIn.uuid.string = "\(prefix)-DELIVERY-BUILD-IN"
	slide.elements[deliveryIndex].buildIn.elementUuid = slide.elements[deliveryIndex].element.uuid
	slide.elements[deliveryIndex].revealType = .bullet
	slide.elements[deliveryIndex].revealFromIndex = 1
	var child = Rv_Data_Slide.Element.ChildBuild()
	child.uuid.string = "\(prefix)-DELIVERY-CHILD"
	slide.elements[deliveryIndex].childBuilds = [child]
	slide.elementBuildOrder = [
		slide.elements[objectBuildIndex].buildIn.uuid,
		child.uuid,
	]
}

private func mediaAction(
	uuid: String,
	storage: Rv_Data_URL.OneOf_Storage,
) -> Rv_Data_Action {
	var action = Rv_Data_Action()
	action.uuid.string = UUID().uuidString
	action.type = .media
	action.media.element.uuid.string = uuid
	action.media.element.url.storage = storage
	return action
}

private func withTemplateResolverTemporaryDirectory<Result>(
	_ operation: (URL) throws -> Result,
) throws -> Result {
	let directory = FileManager.default.temporaryDirectory
		.appendingPathComponent("pro-crud-template-resolver-tests-\(UUID().uuidString)", isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: directory) }
	return try operation(directory)
}
