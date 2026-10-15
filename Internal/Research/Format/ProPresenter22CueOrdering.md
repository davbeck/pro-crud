# Native local cue placement edits

October 15, 2026, pinned ProPresenter 22 beta 369098875 on macOS 27.0.1. Local
ProCRUD Local Persistence Test workspace only; no Cloud connection or other host.

The native UI added two blank slides to the owned ProCRUDTarget22Acceptance
Presentation. `Native/Ordering/before` retains its actual snapshot/vector with
three cues in one group, including the original graphic and notes acceptance
content. Native authoring supplied all new cue/action/slide identities and Loro
placement node IDs. No imported private content is included.

`workspace move-cue ROOT --stream UUID --cue UUID --after UUID --registry PATH`
selects existing cue identities in one group. It calls the official Loro tree
move operation on the existing nodes, with fractional ordering enabled locally.
It does not rebuild the tree, create replacement identities, mutate the cue map,
rewrite arrangement sequences or update old arrays as a competing authority.
The public operation enum is now NativePresentationEdit because it also supports
structural edits. Library-location, media, client and Cloud writes remain separate.

Tests retain every cue value, group ID/attributes, arrangement and placement node
ID while checking the resulting order. The compatibility projection follows the
new order, and its cue payloads still match by identity. Update replay produces
the same deep state/version. Repeating a placement, moving after itself and
unresolved identities have explicit no-op/error behavior. Cross-group moves are
not exposed by this first qualified operation.

The pinned local preflight passed after normal app quit and stopping the launchd
workspace helper. The production command moved original cue
`e053cc8d-2db9-4498-8dce-fd56b900f02f` after
`03374ff1-aef9-4148-86f3-f846178e818a`. A hash-only row comparison showed exactly
one changed shared Presentation stream, unchanged registry bytes and one new
receipt. Repeating the command returned changed=false and no receipts.
The source Presentation stream is `bfa7b647-93ab-5ee6-b397-ec61b08bcfee`.


The first move attempt exposed a shared writer bug: native restart rejected the
stored snapshot version vector. Both official Swift and WASM decoders reported
semantic vector equality. A metadata-only control reproduced it, including with
a matching Loro 1.16.2 binding, ruling out the tree operation and dependency
version as fixes. Each failed attempt was restored to the exact captured owned
Presentation and its own receipt removed; unrelated rows were untouched.

Read-only inspection of the pinned app's repository validator identified its
contract: import the stored snapshot, obtain `state_vv`, encode it, and compare
those bytes with the stored vector. Its postcard map encoding differs from the
semantically equivalent `oplog_vv` encoding for the retained eight-peer native
fixture. The writer now reimports the exported snapshot and stores that state
vector encoding in both stream and receipt. The existing pinned Swift binding
1.13.3 remains unchanged. A regression test checks the native vector's exact
encoding, the contrasting oplog encoding, and the newly prepared snapshot.

A corrected metadata control reopened successfully in the native app. Its
CCLI title is `Native state vector acceptance`. `native-before` retains that
accepted history. The production move then ran with the original pinned binding,
changed only this shared Presentation plus one receipt, and a repeated command
left every stream/registry/receipt hash unchanged. `cli-after` is this corrected
move, replacing the rejected experimental snapshot; rejected output is not a
qualified fixture.

Native restart opened the test workspace successfully and displayed the original
cyan graphic in position three after the two blank slides. File → Export →
Presentation produced `NativeReexport.pro`, independently confirming the order,
group membership, identities and CCLI title. The native export retains the old
cue storage-array order while its group's cue identifiers contain the new
playback order. The test compares cue/action/slide/element identities, geometry, fills and
notes and asserts the independent native group order; storage-array position is not the authority. Native Operator Notes were then
changed to `Native continuation after CLI cue-tree move`; `native-continued`
retains that native update with the CLI cue order intact. Importing native
continuation updates into both the pre-move and CLI histories yields the exact
continued version and deep value. No Loro history was rebuilt from JSON.


Native export also normalizes inactive empty text defaults, empty action labels,
empty chord URLs and text-scroller distance units. Whole exported protobuf cue
bytes are therefore not an identity-preservation oracle. The retained native
snapshots prove the entire cue map is unchanged by the CLI move; the independent
export checks ordered group references, nested identities, geometry, fills and
Slide Notes. Native scroller-unit conversion needs its own active-feature
fixture before claiming scrolling rendering parity.
