# Native local playlist materialization

October 15, 2026, macOS 27.0.1, ProPresenter 22 beta 369098875. Local test
workspace only; no Cloud or account connection was used.

## Native oracle

Created **ProCRUD Native Playlist Acceptance** in the disposable **ProCRUD Local
Persistence Test** workspace. Its standard playlist UUID is
`d0ab014c-0771-4441-9de5-c61098ca8f3c`. The native app authored a colored header
and two references to owned shared Presentation
`bfa7b647-93ab-5ee6-b397-ec61b08bcfee`; the second reference is hidden.
The already-enabled installed local API authored those saved items. Initial
requests failed without modifying the playlist: this build requires all nested
`presentation_info` strings when that optional object is supplied, and header
UUID input must be a string despite the installed documentation's null example.
The accepted request used the documented minimal presentation item shape and a
string header UUID. This is contributor fixture setup, not a document CLI API
wrapper.

The native UI selected that playlist and exported **Playlist**, with **Include
media within presentations** enabled. The resulting unmodified archive contains
only `data` and `ProCRUDTarget22Acceptance.pro`; it is retained as
`Fixtures/ProPresenter22/Interchange/NonemptyPlaylist.proPlaylist`. The matching
shared/client playlist history and owned Presentation are retained separately
under `Native/Playlist`. Provenance and hashes are in the fixture README.

The native export assigns fresh root/playlist/item UUIDs. Therefore comparison
checks names, ordered item kinds/references, hidden state, header color and
arrangements independently of the newly assigned export identities. The native
read view retains each original identity. Both occurrences still reference the
same exact library document; they are not deduplicated into one occurrence.

## Implementation and validation

`NativePlaylistProjection` adapts native group/playlist/item tree nodes into
legacy protobuf hierarchy. It validates native metadata before adaptation, so
unknown fields remain explicit rather than being omitted when only common
identity fields are copied. Unknown root fields also block complete views.
Shared and client stream identity/kind/scope must match. Only `node_states`
expansion values are joined from client scope; missing nonoptional protobuf
boolean values retain the false default. Unapplied client identities are
reported separately. Legacy/v2 mixed authoritative trees are rejected.

The nonempty native fixture agrees with its independent native export for
ordering, visibility, colors, library references and Master arrangement state.
Tests retain source bytes, reject mismatched client identity, check shared-only
views and keyed/default-valued client state, and report unknown node/root fields.
`workspace inventory ROOT --projections` now checks these views alongside
Presentations and Themes. All three retained original corpus playlist streams
(Library, Media and Audio), with matching clients, materialize without unmapped
fields. That corpus check is decoding/materialization evidence; it does not
claim complete native application acceptance of exported dependencies.

This materialization does not implement connected-plan local overlays, native
playlist edits, provider refresh ownership or media registry writes. Those remain local implementation work. The owned acceptance playlist
is retained in the disposable workspace for subsequent export/import testing.

## Portable media-free export acceptance

`workspace export-playlist ROOT --playlist UUID --output PATH` selects one
standard playlist node and resolves direct Presentation links by exact native
logical path in one consistent snapshot. Repeated occurrences, hidden state,
headers, arrangement selection and tags are retained; each distinct dependency
is embedded once. Connected wrappers, provider relationships, media and
non-slide action dependencies remain explicit unsupported issues before output
publication. Output cannot overlap the native source root.

The first actual CLI archive used UUID-only filenames. Native import succeeded
but renamed the Presentation to that UUID, proving this layout was lossy. It was
replaced with `Presentations/<source document UUID>/<original library name>.pro`,
with both URL storage and ROOT_CURRENT_RESOURCE local path rebased coherently.
This retains names and gives distinct archive paths to equal basenames. Native
22 imported the nested layout successfully; it did not reuse the original
Presentation UUID or fall back to the old library link. Its newly created
Presentation UUID was `900d3c21-55ae-4446-8f44-1563b0dbbb1c`. The existing name
in the receiving library caused ProPresenter's normal `-1` suffix. Both visible
and hidden occurrences resolve to that one new document. Header color/order
and the second occurrence's hidden flag survive.

Native File → Export → Playlist re-export is retained unmodified as
`Interchange/PortablePlaylistNativeReexport.proPlaylist`. It contains `data` and
`ProCRUDTarget22Acceptance-1.pro`, retaining the original cue/group and CCLI
data with a new root document identity. As in the earlier native export probe,
ProPresenter initializes inactive text defaults on the rectangle, its empty line
mask and an empty macOS chord chart. The test accounts for those specific native
normalizations and compares the remaining complete cue data. Generated input archive SHA-256:
`c0a1fb31af987542283c9058eb596abde07919c1dc4a5653cd30df707f8afe73`.
The original acceptance playlist and both test imports remain in the disposable
workspace. No live Look or slide was triggered.

The retained decoder now types `PlaylistItem.Presentation.arrangement_name=5`,
already present in the pinned 21.4 baseline. Independent baseline wire encoding
is tested; empty native values no longer become spurious opaque-field downgrade
failures. Both output profiles pass automated archive/load tests. Native import
was performed in 22; the existing 21 fixtures remain the 21 baseline and fresh
21 receiving-app acceptance is unavailable.
