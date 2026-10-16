# Native cue-group names and arrangement sequences

October 15, 2026. ProPresenter 22 beta build 369098875, macOS 27.0.1, authorized
local ProCRUD Local Persistence Test workspace. No Cloud account or second host.
The owned Presentation is `bfa7b647-93ab-5ee6-b397-ec61b08bcfee` at
`Default/ProCRUDTarget22Acceptance`.

## Native evidence

The native UI created arrangement `C049469C-FC98-4BAA-BAF3-290846452E5D`, named
Native Repeated Group. Dragging the source group into its sequence appended a
second occurrence. `Native/Groups/native-repeated` retains this state: three cues
in one placement group and two references to that same group. Both the outer
arrangements collection and its `group_identifiers_v2` are Loro movable lists;
the arrangement is a Loro map.

Native Group → Edit renamed Slides to Native Verse. `native-renamed` retains the
result. Only the placement node's `Kind/group/name` and previously null
`application_group_identifier` changed. The native UI assigned
`DA75DA14-EE4F-4CDB-BF46-4B292E412F3D`; the CLI does not manufacture or replace this
relationship. The cue-group UUID and tree-node ID were unchanged, as were its
color, hotkey, cue membership and repeated arrangement references.

## Implemented operations

`workspace rename-cue-group ROOT --stream UUID --group UUID --name TEXT
--registry PATH` edits only the existing node's group-name map entry. It preserves
application-group identity, color, hotkey and all other metadata. An empty name
or unresolved group fails; a matching name is a no-op.

`workspace set-arrangement-groups ROOT --stream UUID --arrangement UUID
--group UUID [--group UUID …] --registry PATH` sets explicit ordered occurrences.
Repeated group UUIDs are retained. `--clear` explicitly selects an empty sequence.
The operation reuses matching existing occurrences and uses official list moves,
inserts only additional occurrences and deletes only the unselected remainder.
The existing list, arrangement map, arrangement UUID/name and selected arrangement
remain intact. Unresolved arrangements/groups fail before writing.

Parallel legacy group arrays or arrangement sequences are rejected for the
relevant structural edit. Otherwise a source whose two representations initially
agree could become contradictory after changing only the active native graph.
Tests construct such initially valid sources and verify no patch is returned.
Metadata no-ops remain history-preserving.

All operations use the existing stopped-writer, exact local-registration,
optimistic-conflict and atomic stream/vector/integrity/receipt transaction.
`NativePresentationEdit` remains the operation model. General group transfers,
creation/deletion, arrangement creation/deletion and other structural families
still need their own implementation and acceptance.

## Local acceptance

Pinned preflight passed with the UI and all actual workspace helpers stopped.
The production rename changed Native Verse to `CLI Verse — café`, retaining the
native application-group identifier. `cli-renamed` retains this checkpoint.
The production sequence command added a third occurrence of the same group;
`cli-after` retains the result. A hash-only comparison showed only the selected
shared Presentation changed, unchanged registry bytes and exactly two additional
receipts. Repeating both commands returned no changes/receipts and left the
entire stream/registry/receipt hash report unchanged.

Native restart opened the exact test workspace successfully. Both the Groups
palette and all three arrangement occurrences displayed `CLI Verse — café`;
the native grid expanded the three cues to nine slides. File → Export →
Presentation produced the unmodified `NativeReexport.pro`, SHA-256
`21461ff3b96ec9d8b0b39401a3402e9e18680cbf0cb845b8b60ce17ce23d47c0`.
Tests compare its full group/arrangement/selection values with the native
projection, including group identity, application link, color, hotkey and repeated
sequence references.

Native Operator Notes were subsequently changed to
`Native continuation after CLI group and arrangement edits`.
`native-continued` retains that native history. The group's name, placement tree,
cue values and repeated arrangement remained intact. Importing its continuation
updates into the original native history reaches the exact version/deep value.

The movement regression inspects the official Loro JSON update and requires one
`move` with an existing `elem_id`, rather than replacement inserts/deletes. The
binding's document cursor-resolution API did not resolve a moved-list cursor in
this experiment; that diagnostic is not used as evidence of occurrence loss or
as a reason to alter the writer or dependency. Native list operations and update
history provide the direct preservation evidence.
