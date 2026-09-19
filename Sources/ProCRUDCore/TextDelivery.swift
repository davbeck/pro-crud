import AppKit
import ProPresenterProto

/// By Bullet storage observed in ProPresenter 21.4. Index zero belongs to
/// the second nonempty paragraph; the parent build introduces the first.
enum TextDelivery {
	static func issue(in slide: Rv_Data_Slide, elementIndex: Int) throws -> String? {
		let element = slide.elements[elementIndex]
		guard element.revealType == .bullet else {
			return element.revealType != .none || !element.childBuilds.isEmpty
				? "This Delivery mode is preserved but cannot be rebuilt or checked by pro-crud. Verify it in ProPresenter after changing text."
				: nil
		}
		let count = try unitCount(element.element.text.rtfData)
		guard element.hasBuildIn, !element.buildIn.uuid.string.isEmpty,
		      Int(element.revealFromIndex) <= count,
		      element.childBuilds.map(\.index).sorted() == (0 ..< max(0, count - 1)).map(UInt32.init)
		else { return "By Bullet builds do not match the \(count) nonempty text paragraphs. Run set-text-delivery with the intended --initially-visible count." }
		var expected = element.childBuilds.filter { Int($0.index) + 1 >= Int(element.revealFromIndex) }.map(\.uuid.string)
		if count > 0, element.revealFromIndex == 0 {
			expected.insert(element.buildIn.uuid.string, at: 0)
		}
		let owned = Set(element.childBuilds.map(\.uuid.string) + [element.buildIn.uuid.string])
		let scheduled = slide.elementBuildOrder.map(\.string).filter { owned.contains($0) }
		guard !expected.contains(""), Set(expected).count == expected.count, scheduled.sorted() == expected.sorted() else {
			return "By Bullet Build Order does not schedule the expected text units exactly once. Run set-text-delivery with the intended --initially-visible count."
		}
		return nil
	}

	static func unitCount(_ data: Data) throws -> Int {
		guard !data.isEmpty else { return 0 }
		let text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
		return text.replacingOccurrences(of: "\r\n", with: "\n")
			.components(separatedBy: CharacterSet(charactersIn: "\r\n\u{2029}"))
			.count { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
	}

	static func refresh(in slide: inout Rv_Data_Slide, elementIndex: Int, initiallyVisible: Int? = nil) throws {
		var element = slide.elements[elementIndex]
		guard initiallyVisible != nil || element.revealType == .bullet else { return }
		let count = try unitCount(element.element.text.rtfData)
		let visible = initiallyVisible ?? min(Int(element.revealFromIndex), count)
		guard visible >= 0, visible <= count else {
			throw DocumentEditError.unsupportedPatchValue("Initially visible must be between 0 and the text's \(count) nonempty paragraphs.")
		}
		let oldIDs = Set(element.childBuilds.map(\.uuid.string) + (element.hasBuildIn ? [element.buildIn.uuid.string] : []))
		if !element.hasBuildIn {
			element.buildIn.uuid.string = UUID().uuidString
			element.buildIn.transition.duration = 0.3
			var effect = Rv_Data_Effect()
			effect.uuid.string = UUID().uuidString
			effect.name = "Dissolve"
			effect.category = "Dissolves"
			effect.behaviorDescription = "Cross Dissolve."
			effect.renderID = "EC52A828-AD85-4602-B70C-1DEE7C904DB6"
			element.buildIn.transition.effect = effect
		}
		element.buildIn.elementUuid = element.element.uuid
		element.revealType = .bullet
		element.revealFromIndex = UInt32(visible)
		let oldChildren = element.childBuilds
		element.childBuilds = (0 ..< max(0, count - 1)).map { index in
			if let existing = oldChildren.first(where: { $0.index == UInt32(index) }) {
				return existing
			}
			var child = Rv_Data_Slide.Element.ChildBuild()
			child.uuid.string = UUID().uuidString
			child.index = UInt32(index)
			return child
		}
		var desired: [Rv_Data_UUID] = []
		if visible == 0, count > 0 {
			desired.append(element.buildIn.uuid)
		}
		desired += element.childBuilds.filter { Int($0.index) + 1 >= visible }.map(\.uuid)
		let desiredIDs = Set(desired.map(\.string))
		let oldOrder = slide.elementBuildOrder
		var order = oldOrder.filter { !oldIDs.contains($0.string) || desiredIDs.contains($0.string) }
		// Retain the positions and timing of existing steps, including interleaved
		// builds from other objects. Insert new steps next to their nearest sibling.
		for (index, reference) in desired.enumerated() where !order.contains(where: { $0.string == reference.string }) {
			if let previous = desired[..<index].last(where: { ref in order.contains { $0.string == ref.string } }),
			   let position = order.lastIndex(where: { $0.string == previous.string })
			{
				order.insert(reference, at: position + 1)
			} else if let next = desired.dropFirst(index + 1).first(where: { ref in order.contains { $0.string == ref.string } }),
			          let position = order.firstIndex(where: { $0.string == next.string })
			{
				order.insert(reference, at: position)
			} else {
				let anchor = oldOrder.firstIndex { oldIDs.contains($0.string) }
				let position = anchor.map { oldOrder[..<$0].filter { ref in order.contains { $0.string == ref.string } }.count }
					?? order.firstIndex { element.hasBuildOut && $0.string == element.buildOut.uuid.string }
					?? order.count
				order.insert(reference, at: position)
			}
		}
		slide.elements[elementIndex] = element
		slide.elementBuildOrder = order
	}

	static func clear(in slide: inout Rv_Data_Slide, elementIndex: Int) {
		var element = slide.elements[elementIndex]
		let ids = Set(element.childBuilds.map(\.uuid.string) + [element.buildIn.uuid.string])
		slide.elementBuildOrder.removeAll { ids.contains($0.string) }
		element.clearBuildIn()
		element.childBuilds = []
		element.revealType = .none
		element.revealFromIndex = 0
		slide.elements[elementIndex] = element
	}
}
