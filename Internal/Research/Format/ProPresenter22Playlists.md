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

This does not implement connected-plan local overlays, portable dependency
export, native playlist edits, provider refresh ownership or media registry
writes. Those remain local implementation work. The owned acceptance playlist
is retained in the disposable workspace for subsequent export/import testing.
