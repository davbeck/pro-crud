import AppKit
import ProPresenterProto

/// Settled states in stored Build Order, independent of animation timing.
struct SlideBuildStep {
	var hiddenElements: Set<Int> = []
	var visibleTextUnits: [Int: Set<Int>] = [:]

	static func states(for cue: Rv_Data_Cue) throws -> [Self] {
		guard let slide = cue.actions.compactMap(\.presentationBaseSlide).first else { return [Self()] }
		struct Entry {
			var element: Int
			var kind: Kind
			enum Kind { case buildIn, buildOut, text(Int) }
		}
		var entries: [String: Entry] = [:]
		let order = slide.elementBuildOrder.map(\.string)
		let scheduled = Set(order)
		var state = Self()
		func register(_ id: String, _ entry: Entry) throws {
			guard scheduled.contains(id) else { return }
			guard !id.isEmpty, entries.updateValue(entry, forKey: id) == nil else {
				throw RenderError.unsupportedBuildSteps("Build Order contains ambiguous build UUIDs.")
			}
		}
		for (index, element) in slide.elements.enumerated() {
			if element.revealType != .none, element.revealType != .bullet {
				throw RenderError.unsupportedBuildSteps("Underline and unknown text Delivery modes are not supported.")
			}
			if element.hasBuildIn {
				try register(element.buildIn.uuid.string, Entry(element: index, kind: .buildIn))
				if scheduled.contains(element.buildIn.uuid.string) {
					state.hiddenElements.insert(index)
				}
			}
			if element.hasBuildOut {
				try register(element.buildOut.uuid.string, Entry(element: index, kind: .buildOut))
			}
			if element.revealType == .bullet {
				if let issue = try TextDelivery.issue(in: slide, elementIndex: index) {
					throw RenderError.unsupportedBuildSteps(issue)
				}
				state.visibleTextUnits[index] = Set(0 ..< Int(element.revealFromIndex))
				if element.revealFromIndex == 0 {
					state.hiddenElements.insert(index)
				}
				for child in element.childBuilds {
					try register(child.uuid.string, Entry(element: index, kind: .text(Int(child.index) + 1)))
				}
			} else if !element.childBuilds.isEmpty {
				throw RenderError.unsupportedBuildSteps("Child builds require By Bullet Delivery.")
			}
		}
		guard scheduled.count == order.count, order.allSatisfy({ entries[$0] != nil }) else {
			throw RenderError.unsupportedBuildSteps("Build Order contains duplicate or unresolved build references.")
		}
		var states = [state]
		for entry in order.compactMap({ entries[$0] }) {
			switch entry.kind {
			case .buildIn:
				state.hiddenElements.remove(entry.element)
				if state.visibleTextUnits[entry.element] != nil {
					state.visibleTextUnits[entry.element]?.insert(0)
				}
			case .buildOut:
				state.hiddenElements.insert(entry.element)
			case let .text(unit):
				state.visibleTextUnits[entry.element]?.insert(unit)
			}
			states.append(state)
		}
		return states
	}

	static let hiddenTextAttribute = NSAttributedString.Key("ProCRUDHiddenBuildText")

	static func hideMarkedText(in text: NSMutableAttributedString) {
		text.enumerateAttribute(hiddenTextAttribute, in: NSRange(location: 0, length: text.length)) { value, range, _ in
			guard value != nil else { return }
			for key in [NSAttributedString.Key.shadow, .underlineStyle, .strikethroughStyle] {
				text.removeAttribute(key, range: range)
			}
			for key in [NSAttributedString.Key.foregroundColor, .backgroundColor, .strokeColor] {
				text.addAttribute(key, value: NSColor.clear, range: range)
			}
		}
	}

	/// Mark hidden paragraphs without removing characters or changing font metrics.
	static func maskedText(_ text: NSAttributedString, visibleUnits: Set<Int>) -> NSAttributedString {
		let result = NSMutableAttributedString(attributedString: text)
		let string = text.string as NSString
		let separators = CharacterSet(charactersIn: "\r\n\u{2029}")
		var start = 0
		var unit = 0
		while start < string.length {
			let separator = string.rangeOfCharacter(from: separators, range: NSRange(location: start, length: string.length - start))
			let end = separator.location == NSNotFound ? string.length : separator.location
			let range = NSRange(location: start, length: end - start)
			if !string.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				if !visibleUnits.contains(unit) {
					result.addAttribute(hiddenTextAttribute, value: true, range: range)
				}
				unit += 1
			}
			start = end + 1
		}
		hideMarkedText(in: result)
		return result
	}
}
