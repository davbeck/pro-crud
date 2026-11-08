# Planning Center Playlists

Planning Center playlists use the normal `rv.data.PlaylistDocument` store, but
they are not ordinary editable playlists. A connected playlist is a local view
of a Planning Center Services plan, with local presentation or media links
nested inside Planning Center wrapper items.

The stored connected-playlist behavior described here applies to ProPresenter
21.4 (build 352583705).

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

## Local Visibility

Hiding a connected item sets the outer `PlaylistItem.is_hidden` flag. The
remote item snapshot, outer UUID, plan identity, source update date, and
last-update-check date remain unchanged by that local visibility edit.
ProPresenter keeps the item available to unhide.

Connected items expose local linking, unlinking, and visibility controls.
Ordinary copy, paste, duplicate, and delete operations are disabled for these
managed items. Convert the playlist to standard in ProPresenter to edit its
structure independently of the source plan.

## `pro-crud` Support

The checked-in protobuf schema includes `PlanningCenterPlan`,
`Playlist.pco_plan`, and `PlaylistItem.planning_center`. Connected-playlist
support builds on that lossless representation:

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
  outer local visibility flag. The same operation is available to `edit apply`
  as `{"command":"set-playlist-item-hidden","path":"...","hidden":true}`.
- `edit unlink-planning-center-item` clears only the wrapper's `linked_data`,
  leaving the outer UUID, remote plan-item snapshot, tags, name, order, and
  hidden state intact. The item consequently remains as the unlinked
  placeholder shown by ProPresenter.
- `edit link-planning-center-item --document PRESENTATION.pro` links an
  unlinked wrapper to an existing local presentation. It creates a fresh
  nested playlist-item identity, uses the presentation's stored name, and
  writes the absolute document URL. When the playlist and presentation are in
  the same ProPresenter workspace it also writes ProPresenter's
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

## Compatibility Limits

Connected-playlist export/import, conversion to standard, and preservation of
local overlays across remote refreshes are not specified by this file-editing
contract. Use ProPresenter for those service workflows.


## Native 22 local workflows

In native 22 storage, inspect `workspace contents ROOT` and the shared
PlaylistLibrary stream with `workspace dump ROOT --stream UUID`. Version-1
`workspace apply` batches support local `link-planning-center-item`,
`unlink-planning-center-item`, `set-playlist-item-hidden` and
`set-playlist-item-arrangement` operations. Their UUID fields and transaction
rules are documented in [Top-level file formats](TopLevelFileFormats.md).
These native operations preserve the remote plan/item snapshots and shared tree
placements. Unlinking deletes `linked_data`; repeating it makes no change.
Client expansion state and media-store records remain independent.

A stored Planning Center sequence can drive a local arrangement:

```sh
pro-crud workspace planning-center-sequence /exact/native/root \
  --stream PLAYLIST_LIBRARY_STREAM_UUID --item OUTER_ITEM_UUID \
  --presentation PRESENTATION_STREAM_UUID --arrangement LOCAL_ARRANGEMENT_UUID \
  --name 'Service Sequence' --linked-item NEW_LOCAL_ITEM_UUID --dry-run
```

The preview reports ordered group names and UUIDs. Each name must match exactly
one local cue group. Repeated names produce repeated occurrences; missing or
ambiguous labels fail before any write. Omit `--dry-run` and provide `--registry
/exact/path/registry-v1.sqlite3` to apply with ProPresenter and helpers stopped.
The arrangement UUID identifies the definition to create or update; its stored
Presentation selection stays unchanged. The item selects this arrangement
locally. An existing link must target the explicitly selected Presentation;
reassignment requires explicit unlinking. Visibility stays unchanged. A matching
replay creates no receipts. Definition and link publication share one transaction,
with all reference reads checked before commit.

This workflow uses the remote snapshot already stored locally. Refresh, upload,
download, attachment association and remote sequence changes require the
respective authenticated service workflow and are not performed by this command.
The native 22 local contract is qualified against build 369098875. Authenticated
refresh/reconciliation and cross-account behavior are outside this contract.

CLI `workspace export-playlist` retains connected wrappers, remote metadata and
local overlays. Native 22 **Export → Playlist** instead flattens connected items
into standard local items; that export is a snapshot of local content and must
not be treated as a preserved service connection.
