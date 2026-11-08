# Native playlist, connected overlays and Theme editing

October 15, 2026. ProPresenter **22 beta build 369098875**, macOS **27.0.1**,
signing team **97GAAZ6CPX**. Authorized disposable **ProCRUD Local Persistence
Test** workspace. Contributor preflights pinned the existing app/helper and local
registration; every actual UI/helper writer was stopped for production writes.
The app restored its helper after restart. No account or Cloud connection was used.

## Native playlist transactions

The existing PlaylistLibrary uses a Loro tree. Node metadata owns `uuid`, `name`
and the `Kind` wrapper. Standard group metadata is empty; playlist metadata has
an unselected `LinkData` map. Item metadata owns `is_hidden` and `ItemType`.
Headers have a native atomic color and movable action list. Presentation links
use platform 1 and a ROOT_SHOW-relative logical library path. Client expansion
state remains separate.

Independent native controls renamed the owned acceptance playlist and hid one
of its Presentation occurrences. The writer produces the same protobuf view,
preserves placement identities and replays the original history plus its update.
The linked native control later confirmed the same outer visibility field for
a Planning Center wrapper.

The production eight-operation manifest creates a folder, playlist, black header
and two local Presentation links, hides one link, renames a Theme template and
changes one template text slot. It changes exactly the selected shared
PlaylistLibrary and Theme streams, with receipts **193 → 195**. All other stream
hashes and all owned asset/MediaStore file hashes are unchanged. An invalid final
template selector leaves all stream hashes and receipt counts unchanged. Matching
replay returns no receipts and leaves the complete captured state unchanged.

That replay exposed an incorrect creation precondition: an existing item whose
visibility was set later in the same batch was treated as conflicting identity
reuse. Creation now initializes visibility only for new nodes and validates the
existing structural payload separately. The regression is retained.

Actual native reopen retains both CLI snapshot and vector bytes exactly. The
native sidebar displays the created folder/playlist, header and linked media
Presentation, with one additional hidden item. Native Export → Playlist retains
those local semantics and the selected arrangement definitions. Creation, rename,
move and leaf/empty-container removal use existing tree operations, with parent,
sibling, cycle, identity and complete final-graph reference checks. Creation is
limited to groups, playlists, black headers and local Presentation links; this
work does not add inline media/cue authoring or node duplication.

## Theme text and names

Theme template selection uses the base-slide UUID, distinct from the owning
Theme stream UUID. Naming, movable-list reordering and static element text edits
retain existing containers/history. Text uses the established Presentation text
policy: preserve a matching plain string, replace RTF/range data deliberately and
update the native atomic font value when needed. Delivery/element builds remain
gated. The shared text implementation still passes the original native text
acceptance and rendering comparisons.

Native Export → Themes, with only the owned **Deep Look Theme** selected, retains
the CLI name/text and every other field except a native export normalization:
for these left-scrolling-default elements, stored inactive `repeat_distance=100`
is divided by element width (360, 200, 120), producing 0.2777777777777778, 0.5 and
0.8333333333333334. `should_scroll` is false. Native history is byte-identical
before and after export. Tests assert these exact observed values, then compare
the remainder of every template field. No reference images or tolerances change.
A separate owned two-template interchange control is imported into **CLI Template
Ordering**. A real production move/name batch retains the two Loro row-container
identities, reorders the templates, commits one stream/receipt and replays without
changes. Initial native reopen retains snapshot/vector bytes exactly. Loading and
exporting the Theme later reserializes snapshot bytes but retains the exact stored
vector, deep value, row containers and independent WASM oplog frontier; no new
operations are present. Native export has the requested new order and identical
remaining template fields after the same explicit scroller-unit normalization.
Template application, creation/duplication, deletion and native build editing
remain separate work.

## Connected local overlays and stored sequence workflow

The owned synthetic `OwnedOfflineInput.proPlaylist` has synthetic remote IDs,
no attachment URLs and a sequence `Slides / Chorus 4 / Slides`. Native import
recognizes it as a Planning Center playlist with an unlinked song placeholder.
This is an offline format control, not an authenticated plan import/refresh.

Native **Hide Item** changes only the outer item flag. Generic copy, paste,
duplicate and delete controls are disabled. The production stored-sequence command
matches each sequence label to exactly one local group; repeated labels retain
repeated group occurrences. Missing/ambiguous labels are errors. It creates or
updates an explicit stable local arrangement without changing the Presentation's
stored selection, and links/selects that arrangement on the outer plan item.
Presentation definitions prepare before dependent local links, including when
input operation order is reversed; the original complete reference read set is
checked inside the transaction.

The real command modifies only PlaylistLibrary and the owned **ProCRUD File
Replacement Probe** Presentation, with receipts **213 → 215**, no asset/store
changes and a receipt-free matching replay. Native reopen retains both snapshots
and vectors byte-for-byte. The hidden-item menu names **CLI Service Sequence**;
native Unhide Item displays the linked Presentation and selected three-occurrence
arrangement. The plan and remote item snapshots remain unchanged.

Native **Unlink** deletes the `linked_data` key rather than assigning null. The
writer now does the same; the complete deep value matches this independent native
control. An absent local link is a no-op. Link creation uses a new nested item
UUID, preserves the outer wrapper, and requires explicit unlinking before a
different assignment. Visibility/arrangement changes remain local overlays.

Native Export → Playlist **flattens** the connected wrapper into a standard local
Presentation item and drops the plan connection. It retains the local arrangement
UUID/name. CLI export deliberately retains the remote wrappers instead. Its
actual native re-import remains connected, retains the exact plan/item snapshot
and hidden flag, and resolves the embedded document to a new native Presentation
(`ProCRUD File Replacement Probe-1`). Native import replaces outer/nested local
item identities and clears the optional arrangement-name string, while retaining
the arrangement UUID. Authenticated refresh, upload/download, attachment
association and remote sequence reconciliation remain outside this qualification.

## Portable dependency export

The exporter walks all active message fields, including nested connected links,
headers, inline cues and playback-marker actions. Singular message fields merge;
repeated fields retain their independent order/identity. Each Presentation is
embedded once under its native logical identity and original basename. File
media keeps occurrence and asset UUIDs separate, uses authoritative selected
locators and copies shared assets once. All file URL representations are rebased
coherently; same-asset/different-content conflicts fail. HLS is never downloaded.

For a real native source root, export also checks checksum-verified MediaStore
Reference/Asset models: missing, tombstoned, purged or differently associated
identities fail instead of rewriting the declaration. A changed store fingerprint
during capture aborts publication. File availability still comes from actual
selected document locators, not cached thumbnails or stored availability labels.
The retained independent declared/materialized mismatch is an export rejection
test; the actual owned image occurrences and imported copies have matched,
Ready associations to the same shared file.

The first new import exposed a regression: rebuilding a link URL with default
platform 0 imported the embedded files but left playlist links at unresolved
ROOT_CURRENT_RESOURCE paths with empty names. Retained negative/positive histories
prove that preserving platform 1 restores ROOT_SHOW links to the newly imported
Presentation identities. Header/order/hidden state survives; native import uses
the linked document names rather than arbitrary outer aliases. The corrected CLI
archive and native histories are retained. Its shared image asset is included
once and native imported occurrences receive distinct fresh reference UUIDs.
The CLI renderer also resolves this coherent archive-local representation. A
regression test deletes the original source image before rendering the exported
playlist and compares every rendered cue exactly to the original native preview.
Arbitrary native ROOT_CURRENT_RESOURCE locators still require their own resource
owner and cannot fall back to a same-path workspace file.

Missing occurrences and unavailable/unsupported action dependencies are collected
before output publication. Configuration-referencing actions (Macros, Looks,
timers, stage/physical devices and playlist triggers), selected effect presets,
provider relationships and unqualified runtime sources remain explicit errors.
A `.proPlaylist` does not install those external workspace definitions. This is
complete traversal/reporting of the implemented archive dependency classes, not a
claim that configuration/action-definition export belongs in `.proPlaylist`.
The subsequent separate workspace exporter and receiving-app qualification are
recorded in [ProPresenter22ActionDependencyExport.md](ProPresenter22ActionDependencyExport.md).

Evidence is in `Fixtures/ProPresenter22/Native/{PlaylistEditing,TemplateEditing,
PlanningCenterEditing}` with per-file hashes and actual production receipts.
Existing 21 reference images remain untouched. Fresh receiving-app 21 coverage
for these new adapters remains unavailable; the retained 21 corpus is the
regression baseline.
