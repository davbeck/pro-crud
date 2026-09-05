import ProPresenterProto

struct EffectivePlaylistItem {
	var outer: Rv_Data_PlaylistItem
	var content: Rv_Data_PlaylistItem?
	var planningCenter: Rv_Data_PlaylistItem.PlanningCenter?

	init(_ outer: Rv_Data_PlaylistItem) {
		self.outer = outer
		if case let .planningCenter(value)? = outer.itemType {
			planningCenter = value
			content = value.hasLinkedData ? value.linkedData : nil
		} else {
			planningCenter = nil
			content = outer
		}
	}

	var isHidden: Bool {
		outer.isHidden || content?.isHidden == true
	}
}

extension Rv_Data_Playlist {
	var isPlanningCenterConnected: Bool {
		if case .pcoPlan? = linkData {
			return true
		}
		return false
	}
}
