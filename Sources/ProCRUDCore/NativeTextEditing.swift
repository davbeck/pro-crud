import AppKit
import Foundation
import Loro
import ProPresenterProto

public enum NativeSlideTextContent: Codable, Sendable, Equatable {
	case text(String)
	case rtf(Data)
}

enum NativeTextEditing {
	static func apply(_ content: NativeSlideTextContent, actionID: UUID, elementID: UUID, root: LoroMap, identity: NativeWorkspaceStream.Identity, value: NativeWorkspaceValue) throws {
		var presentation = try NativeProtobufProjection.read(identity: identity, source: value).presentation()
		let actions = presentation.cues.enumerated().flatMap { cueIndex, cue in
			cue.actions.enumerated().compactMap { actionIndex, action in
				UUID(uuidString: action.uuid.string) == actionID ? (cueIndex, actionIndex) : nil
			}
		}
		guard actions.count == 1, let (cueIndex, actionIndex) = actions.first,
		      case let .presentation(slide)? = presentation.cues[cueIndex].actions[actionIndex].slide.slide
		else { throw NativeSemanticError.invalidValue(path: "/actions/\(actionID)", expected: "one Presentation slide action") }
		let elements = slide.baseSlide.elements.indices.filter { UUID(uuidString: slide.baseSlide.elements[$0].element.uuid.string) == elementID }
		guard elements.count == 1, let elementIndex = elements.first else {
			throw NativeSemanticError.invalidValue(path: "/actions/\(actionID)/elements/\(elementID)", expected: "one existing slide element")
		}
		let original = slide.baseSlide.elements[elementIndex]
		let oldText = original.element.text
		switch content {
		case let .text(text):
			let existing = oldText.rtfData.isEmpty ? "" : try NSAttributedString(data: oldText.rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
			if existing == text {
				return
			}
		case let .rtf(data):
			if oldText.rtfData == data {
				return
			}
		}
		guard original.revealType == .none, original.childBuilds.isEmpty, !original.hasBuildIn, !original.hasBuildOut else {
			throw NativeSemanticError.invalidValue(path: "/actions/\(actionID)/elements/\(elementID)", expected: "text without delivery or element builds; native build editing is not yet qualified")
		}
		let cueID = presentation.cues[cueIndex].uuid.string
		let storedActionID = presentation.cues[cueIndex].actions[actionIndex].uuid.string
		let storedElementID = original.element.uuid.string
		let path = try ComponentPath("/cues[uuid=\"\(cueID)\"]/actions[uuid=\"\(storedActionID)\"]/slide/presentation/base_slide/elements[uuid=\"\(storedElementID)\"]/element/text")
		switch content {
		case let .text(text): try DocumentEditor.setText(in: &presentation, at: path, to: text)
		case let .rtf(data): try DocumentEditor.setRTF(in: &presentation, at: path, data: data)
		}
		let replacement = presentation.cues[cueIndex].actions[actionIndex].slide.presentation.baseSlide.elements[elementIndex].element.text
		guard let cues = root.get(key: "cues")?.asLoroMap(), let cue = cues.get(key: cueID)?.asLoroMap(),
		      let actions = cue.get(key: "actions")?.asLoroMovableList(), let action = actions.get(index: UInt32(actionIndex))?.asLoroMap()
		else { throw NativeSemanticError.invalidValue(path: path.description, expected: "native cue map and movable action list") }
		let baseSlide = try map(action, keys: ["ActionTypeData", "slide", "Slide", "presentation", "base_slide"], path: path.description)
		guard let elements = baseSlide.get(key: "elements")?.asLoroMovableList(), let element = elements.get(index: UInt32(elementIndex))?.asLoroMap() else {
			throw NativeSemanticError.invalidValue(path: path.description, expected: "native movable element list")
		}
		let text = try map(element, keys: ["element", "text"], path: path.description)
		let attributes = try map(text, keys: ["attributes"], path: path.description)
		guard let ranges = attributes.get(key: "custom_attributes")?.asLoroMovableList() else {
			throw NativeSemanticError.invalidValue(path: path.description, expected: "native movable custom-attribute list")
		}
		if oldText.attributes.font != replacement.attributes.font {
			guard case var .map(font)? = attributes.get(key: "font")?.asValue() else {
				throw NativeSemanticError.invalidValue(path: path.description, expected: "native atomic font map")
			}
			let updated = replacement.attributes.font
			font["name"] = .string(value: updated.name)
			font["family"] = .string(value: updated.family)
			font["size"] = .double(value: updated.size)
			font["bold"] = .bool(value: updated.bold)
			font["italic"] = .bool(value: updated.italic)
			try attributes.insert(key: "font", v: LoroValue.map(value: font))
		}
		if ranges.len() > 0 {
			try ranges.delete(pos: 0, len: ranges.len())
		}
		try text.insert(key: "rtf_data", v: LoroValue.binary(value: replacement.rtfData))
	}

	private static func map(_ parent: LoroMap, keys: [String], path: String) throws -> LoroMap {
		var current = parent
		for key in keys {
			guard let child = current.get(key: key)?.asLoroMap() else { throw NativeSemanticError.invalidValue(path: path, expected: "native \(key) map") }
			current = child
		}
		return current
	}
}
