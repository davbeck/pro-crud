import Foundation
import ProCRUDCore
import ProPresenterProto

func planningCenterPlaylist(
	name: String = "Core Values",
	documentURL: URL? = nil,
) -> Rv_Data_PlaylistDocument {
	var document = DocumentFactory.playlist(name: name)
	document.rootNode.uuid.string = "PLAYLIST-ROOT"
	document.rootNode.playlists.playlists[0].uuid.string = "CONNECTED-PLAYLIST"
	document.liveVideoPlaylist.uuid.string = "LIVE-VIDEO-PLAYLIST"
	document.downloadsPlaylist.uuid.string = "DOWNLOADS-PLAYLIST"
	var playlist = document.rootNode.playlists.playlists[0]

	var plan = Rv_Data_PlanningCenterPlan()
	plan.planIDStr = "plan-123"
	plan.parentIDStr = "service-456"
	plan.seriesTitle = "Core Values"
	plan.planTitle = "September 5"
	plan.dateList = "September 5, 2026"
	playlist.pcoPlan = plan

	var remoteItem = Rv_Data_PlanningCenterPlan.PlanItem()
	remoteItem.itemType = .song
	remoteItem.pcoIDStr = "item-789"
	remoteItem.serviceIDStr = "service-456"
	remoteItem.parentIDStr = "plan-123"
	remoteItem.name = "Abide"
	remoteItem.linkedSong.pcoIDStr = "song-101"
	remoteItem.linkedSong.arrangementIDStr = "arrangement-202"
	remoteItem.linkedSong.ccli.songTitle = "Abide"
	remoteItem.linkedSong.ccli.songNumber = 12345
	remoteItem.linkedSong.sequence.pcoIDStr = "sequence-303"
	remoteItem.linkedSong.sequence.name = "Service Sequence"
	remoteItem.linkedSong.sequence.groupNames = ["Verse 1", "Chorus"]

	var connected = Rv_Data_PlaylistItem.PlanningCenter()
	connected.item = remoteItem
	if let documentURL {
		var linked = Rv_Data_PlaylistItem()
		linked.uuid.string = "LINKED-ITEM"
		linked.name = "Abide"
		linked.presentation.documentPath.absoluteString = documentURL.absoluteString
		linked.presentation.arrangement.string = "LOCAL-ARRANGEMENT"
		connected.linkedData = linked
	}

	var item = Rv_Data_PlaylistItem()
	item.uuid.string = "CONNECTED-ITEM"
	item.name = "Abide"
	item.planningCenter = connected
	playlist.items.items = [item]
	document.rootNode.playlists.playlists[0] = playlist
	return document
}
