# Planning Center Playlists

Planning Center playlists use the normal `rv.data.PlaylistDocument` store, but
they are not ordinary editable playlists. A connected playlist is a local view
of a Planning Center Services plan, with local presentation or media links
nested inside Planning Center wrapper items.

This note separates official workflow guarantees from observed persistence.
The local observations were made on September 5, 2026 with ProPresenter 21.4
(build 352583705), using the connected **Core Values - Core Values - September
6, 2026** playlist in the authorized LSSS test workspace. No Planning Center
identifiers, account data, or document binaries from that workspace are stored
in this repository.

## Official Workflow

Renewed Vision documents these connected-playlist behaviors:

- A Planning Center plan is imported with **Add → Planning Center Service** and
  remains identifiable by the Planning Center icon.
- ProPresenter can periodically or manually check the source plan for updates.
- Matching can link existing library presentations automatically. Unmatched
  plan items can be linked to a Planning Center attachment, a new presentation,
  a local file, or an existing library presentation.
- A linked item can be unlinked without removing its Planning Center
  attachment. Connected-plan items can also be hidden locally and later
  unhidden.
- Planning Center headers cannot be edited like standard ProPresenter headers.
- **Convert to Standard Playlist** permanently removes the Planning Center
  connection and enables ordinary playlist and header editing. A standard
  playlist cannot be converted back; the plan must be imported again.
- With **Make Arrangements from Sequences** enabled, a Planning Center song
  sequence can create and select a ProPresenter arrangement.
- Automatic upload can attach linked ProPresenter documents or media to the
  Planning Center item. Automatic download chooses an applicable attachment;
  attachment ordering and cleanup therefore matter.

Planning Center's own documentation establishes the other side of the model:
song sequences belong to arrangements, may contain repeated and custom section
labels, and can be changed for one plan or saved back to the arrangement. Files
may belong to a plan, plan item, song, arrangement, or key. Those scopes should
not be flattened into a single ProPresenter-local attachment concept.

Official references:

- [Using Planning Center with ProPresenter](https://support.renewedvision.com/hc/en-us/articles/4408670102419-Using-Planning-Center-with-ProPresenter)
- [Adding a Planning Center Plan to ProPresenter](https://support.renewedvision.com/hc/en-us/articles/360062310714-Adding-a-Planning-Center-Plan-to-ProPresenter)
- [Edit song sequences](https://pcoservices.zendesk.com/hc/en-us/articles/204461530-Edit-song-sequences)
- [Create, upload, or link to files](https://pcoservices.zendesk.com/hc/en-us/articles/360026676133-Create-upload-or-link-to-files)
- [Manage files and storage](https://pcoservices.zendesk.com/hc/en-us/articles/236278887-Manage-files-and-storage)

## Stored Model

A standard presentation playlist stores each item directly as a header,
presentation, cue, or placeholder. A connected playlist instead uses both
Planning Center link layers from `playlist.proto`:

| Concern | Standard playlist | Planning Center playlist |
| --- | --- | --- |
| Playlist identity | No `pco_plan` | Playlist `link_data` selects `pco_plan` |
| Item type | Direct `header`, `presentation`, `cue`, or `placeholder` | Outer item selects `planning_center` |
| Remote item snapshot | None | `planning_center.item` |
| Local linked content | The item itself | `planning_center.linked_data`, itself a regular `PlaylistItem` |
| Local visibility | Outer `PlaylistItem.is_hidden` | Also the outer wrapper's `is_hidden` |
| Order ownership | Local playlist | Mirrored Planning Center plan order |

`Playlist.pco_plan` stores the plan and service-type identifiers, series and
plan titles, display date, source update date, and last-update-check date. Each
`PlanningCenterPlan.PlanItem` stores its remote item and service identifiers,
parent identifier, remote name, item type, update date, attachments, and
optional song data. Song data can include song, arrangement, CCLI, and sequence
identifiers plus the ordered sequence group names.

The nested `planning_center.linked_data` is the local half of a link. For a
presentation it contains a second local playlist-item UUID, a `document_path`,
an optional ProPresenter arrangement UUID, the content destination, and the
user music key. Unlinked plan items omit `linked_data` while retaining their
remote snapshot.

The outer item name, remote item name, and linked-data name are separate stored
values and can differ in capitalization or punctuation. Treating any one of
them as the authoritative name for all three layers would lose information.

## Core Values Observation

The live playlist contained 22 outer Planning Center items before the local
edit. Twenty had `linked_data`; **Abide** and **Announcement Reminder** were
unlinked. Five items carried song metadata. Two linked songs had populated
sequence group lists and selected local arrangements whose UI names ended in
`(PCO)`.

The item UI also differed by link state:

- An unlinked item offered **New Presentation**, **Import**, **Search**, and
  **Attachments** in the content area. Its context menu offered **Hide Item**;
  copy, paste, duplicate, and delete were disabled.
- A linked presentation item offered **Upload to Planning Center Services**,
  **Unlink**, **Hide Item**, arrangement and destination selection, editing,
  library navigation, and export. Copy, paste, duplicate, and delete remained
  disabled.

For the controlled modification, **Announcement Reminder** was hidden through
the ProPresenter UI. The visible count changed from 22 to 21 and the UI added
**1 Additional Hidden Item**. A before/after deterministic protobuf-JSON diff
contained exactly this semantic change:

```diff
 {
+  "isHidden": true,
   "name": "Announcement Reminder",
   "planningCenter": { ... }
 }
```

The outer item UUID, nested Planning Center item, playlist `pco_plan`, source
update date, and last-update-check date were unchanged. This establishes
`PlaylistItem.is_hidden` as a local overlay, not a mutation of the remote item
snapshot.

The post-edit `Playlists/Library` document passed the current structural
validator. The edit remains in the authorized local test workspace.

## Implemented Compatibility

The checked-in protobuf schema includes `PlanningCenterPlan`,
`Playlist.pco_plan`, and `PlaylistItem.planning_center`. Connected-playlist
support now builds on that lossless representation:

- Effective-item traversal retains the outer synchronization wrapper while
  resolving its nested local item when linked.
- Semantic text and JSON dumps expose plan identity, remote item identity and
  type, attachment names, song and sequence data, link state, effective local
  type, presentation path, and selected arrangement. Outer, remote, and linked
  names remain separate.
- Playlist rendering follows linked presentations in plan order, skips outer
  or nested hidden items, and ignores legitimate unlinked items.
- Structural validation checks plan and item identities, nested item UUIDs and
  presentation paths, orphaned or unwrapped items, and accidental nested
  Planning Center wrappers.
- Generic rename, duplicate, remove, move, and add-item operations reject
  Planning Center-managed structure and direct users to convert the playlist
  in ProPresenter first.
- `edit set-playlist-item-hidden --hidden` and `--visible` modify only the
  proven outer local overlay. The same operation is available to `edit apply`
  as `{"command":"set-playlist-item-hidden","path":"...","hidden":true}`.
- `edit unlink-planning-center-item` clears only the wrapper's `linked_data`,
  leaving the outer UUID, remote plan-item snapshot, tags, name, order, and
  hidden state intact. The item consequently remains as the unlinked
  placeholder shown by ProPresenter.
- `edit link-planning-center-item --document PRESENTATION.pro` links an
  unlinked wrapper to an existing local presentation. It creates a fresh
  nested playlist-item identity, uses the presentation's stored name, and
  writes the absolute document URL. When the playlist and presentation are in
  the same ProPresenter workspace it also writes ProPresenter's observed
  `ROOT_SHOW`-relative `Libraries/...` path. Reassigning an already linked item
  is rejected; unlink it first, matching the UI's two-step workflow.

Both link commands are available to `edit apply`:

```json
[
  {
    "command": "unlink-planning-center-item",
    "path": "/root_node/playlists/playlists[uuid=PLAYLIST_UUID]/items/items[uuid=ITEM_UUID]"
  },
  {
    "command": "link-planning-center-item",
    "path": "/root_node/playlists/playlists[uuid=PLAYLIST_UUID]/items/items[uuid=ITEM_UUID]",
    "document": "/path/to/Libraries/Songs/Replacement.pro"
  }
]
```

`create playlist` and `add-playlist-item` remain standard-playlist operations;
they do not synthesize remote identity. Upload, download, refresh, and Planning
Center attachment association remain authenticated service workflows and are
intentionally not simulated through protobuf edits. Local link/unlink does not
upload, download, or otherwise modify Planning Center Services.

For additional compatibility work, capture a small ProPresenter-authored fixture from a
disposable Planning Center test plan. It should contain a header, an ordinary
item, media, linked and unlinked presentations, a hidden item, a song sequence
with a repeated group, and a selected PCO-created arrangement. Do not check in
real organization identifiers or absolute user paths.

## Remaining Experiments

The September 5 observation did not establish these behaviors:

1. Export a connected playlist as `.proPlaylist` and compare its wrapper items,
   embedded documents, and import round trip with a standard playlist export.
2. Refresh after hiding, linking, unlinking, and changing a selected
   arrangement; determine which local overlays survive remote order and name
   changes.
3. Convert a copied connected playlist to standard and diff the exact removal
   or normalization of `pco_plan`, wrapper items, hidden state, headers, links,
   and arrangement selections.
4. Import a plan containing Planning Center headers and confirm current 21.4
   persistence and the documented editing restrictions.
5. Test automatic upload/download only with disposable account content while
   recording attachment choice, duplication, replacement, and storage effects.
