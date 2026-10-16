import Foundation
import Loro
import ProPresenterProto

enum NativeMediaActionEditing {
	static func remove(_ actionID: UUID, presentation: Rv_Data_Presentation, root: LoroMap) throws {
		let matches = presentation.cues.flatMap { cue in
			cue.actions.enumerated().compactMap { index, action in UUID(uuidString: action.uuid.string) == actionID ? (cue, index, action) : nil }
		}
		if matches.isEmpty {
			return
		}
		guard matches.count == 1, let (cue, index, action) = matches.first,
		      action.renderableMedia != nil, case .media? = action.actionTypeData,
		      cue.actions.contains(where: { $0.presentationBaseSlide != nil })
		else { throw NativeSemanticError.unsupportedNode(path: "/actions/\(actionID)", kind: "removing one media action from a slide cue") }
		for source in presentation.cues where source.completionActionType == .afterAction && UUID(uuidString: source.completionActionUuid.string) == actionID {
			throw NativeSemanticError.unsupportedNode(path: "/cues/\(source.uuid.string)/completion_action_uuid", kind: "media action selected as an after-action completion source; choose another completion source first")
		}
		guard let cues = root.get(key: "cues")?.asLoroMap(), let stored = cues.get(key: cue.uuid.string)?.asLoroMap(),
		      let actions = stored.get(key: "actions")?.asLoroMovableList()
		else { throw NativeSemanticError.invalidValue(path: "/cues/\(cue.uuid.string)/actions", expected: "native movable action list") }
		try actions.delete(pos: UInt32(index), len: 1)
	}
}
