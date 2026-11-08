import Foundation
import Loro
import ProPresenterProto

public enum NativeTemplateEdit: Codable, Sendable, Equatable {
	case rename(UUID, String)
	case move(UUID, after: UUID?)
	case text(slide: UUID, element: UUID, content: NativeSlideTextContent)
}

enum NativeTemplateEditing {
	static func apply(_ edit: NativeTemplateEdit, document: LoroDoc, identity: NativeWorkspaceStream.Identity) throws {
		guard identity.kind == "Theme" else { throw NativeSemanticError.invalidValue(path: "/theme", expected: "shared Theme stream") }
		let projection = try NativeProtobufProjection.read(identity: identity, source: NativeWorkspaceValue(document.getDeepValue()))
		guard case let .theme(theme) = try projection.payload() else { throw NativeSemanticError.invalidValue(path: "/theme", expected: "Theme projection") }
		guard let slides = document.getMap(id: "root").get(key: "slides")?.asLoroMovableList() else { throw NativeSemanticError.invalidValue(path: "/slides", expected: "native movable template list") }
		let id: UUID
		switch edit { case let .rename(value, _), let .move(value, _), let .text(value, _, _): id = value }
		let matches = theme.slides.indices.filter { UUID(uuidString: theme.slides[$0].baseSlide.uuid.string) == id }
		guard matches.count == 1, let index = matches.first, let stored = slides.get(index: UInt32(index))?.asLoroMap() else { throw NativeSemanticError.missingReference(path: "/slides", identity: id.uuidString) }
		switch edit {
		case let .rename(_, name):
			guard !name.isEmpty else { throw NativeSemanticError.invalidValue(path: "/slides/\(id)/name", expected: "nonempty template name") }
			if theme.slides[index].name != name {
				try stored.insert(key: "name", v: name)
			}
		case let .move(_, after):
			if after == id {
				return
			}
			let remaining = theme.slides.filter { UUID(uuidString: $0.baseSlide.uuid.string) != id }
			let position: Int
			if let after {
				guard let anchor = remaining.firstIndex(where: { UUID(uuidString: $0.baseSlide.uuid.string) == after }) else { throw NativeSemanticError.missingReference(path: "/slides", identity: after.uuidString) }
				position = anchor + 1
			} else {
				position = 0
			}
			if position != index {
				try slides.mov(from: UInt32(index), to: UInt32(position))
			}
		case let .text(_, element, content):
			try NativeTextEditing.replace(content, elementID: element, slide: theme.slides[index].baseSlide, native: NativeContainerAccess.map(stored, keys: ["base_slide"]))
		}
	}
}
