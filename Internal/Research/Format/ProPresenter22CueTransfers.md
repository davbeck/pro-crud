# Native cue ownership transfers and empty-group cleanup

October 15, 2026. ProPresenter 22 beta 369098875, macOS 27.0.1, authorized local
ProCRUD Local Persistence Test workspace. Owned Presentation stream
`bfa7b647-93ab-5ee6-b397-ec61b08bcfee` only; Cloud is outside this qualification.

## Native ownership evidence

The native Group → Chorus command split the original graphic cue from CLI Batch
Group into a new Chorus group. Presentation → New Slide added a blank cue to that
source group. `Native/CueTransfers/split-before` and `native-before` retain the
owned states. The original graphic cue `E053CC8D-2DB9-4498-8DCE-FD56B900F02F`
kept placement node `169@1`; native history moved its parent from `159@1` to
`407@898452`. Its metadata and entire cue payload were unchanged. Native history
contains a tree create for the new group, a move of the original node, and a
create for the new blank cue's placement. This is reparenting, not cue recreation.
The new blank cue is `2FABF989-5E73-4CCE-8139-33F50F483922`.

`workspace transfer-cue ROOT --stream UUID --cue UUID --group UUID [--after UUID]
--registry PATH` uses the official existing-tree move. Omitted `--after` appends;
a supplied anchor must belong to the destination. Matching/self/already-after
placements are no-ops. The operation retains cue data and placement identity,
group metadata and unrelated arrangements, using the same stopped-writer/local
registration/optimistic-conflict/atomic-publication rules as other native edits.
The native edit manifest also accepts `transfer-cue` with `cue`, destination
`group`, and optional `after`.

## Native invariant discovered during acceptance

The first two production transfer experiments moved the graphic after the first
blank cue, then appended the source's remaining blank cue. Native restart opened
the workspace and showed all four cues repeated twice. However the app generated
an `enforce presentation tree invariants` commit deleting the now-empty Chorus
node. `empty-before-repair` and `empty-native-repair` retain that evidence;
EmptySourceNativeReexport.pro is the fresh native export from this experiment.
The original empty source was not a stable native representation. The writer
was corrected before exposing the operation in a committed feature.

Read-only inspection of the pinned app identified
`presentation_tree_invariants::scrub_arrangements`. A separate controlled probe
qualified its behavior against actual native snapshots. A one-off Swift program
linked the already built official Loro binding using normal build/module caches.
It created only a new group and its metadata containers inside the existing
owned history, reparented the existing blank cue, and inserted that new group's
UUID between/after the retained arrangement occurrences. It did not rebuild the
Presentation from diagnostic JSON. The app reopened this two-group graph with
its snapshot byte-identical to the prepared one. That accepted input is
`referenced-native-before`.

Emptying this source produced `referenced-empty`, with arrangement sequence
A, B, A, B and empty B. The app's independent invariant commit removed the empty
group node and deleted exactly positions 3 then 1 from the arrangement movable
list. A, A and its original occurrences remained. `referenced-native-repair`
retains this app-authored result. No other content was changed.

The implementation now removes an emptied source group and each corresponding
arrangement occurrence in the same transaction as the ownership transfer.
It deletes reference occurrences in reverse index order rather than recreating
the sequence or moving surviving occurrences. Unknown native content blocks
this group deletion until its references are qualified. Moving into an existing
empty destination is supported without replacing its group or cue nodes.

Tests prepare a corrected transfer from the independently accepted referenced
input and compare its **entire native deep value** with the app's independent
repair output, including placement fractional indexes. Replay of the prepared
update reaches that same state. A future-group-reference negative control blocks
deletion; other tests cover no-ops, unresolved destinations/anchors, repeated
arrangement expansion, cue/node/metadata preservation and empty destinations.

## Corrected production qualification

A fresh owned group/arrangement probe using the already accepted construction
shape supplied `qualified-before`: A, B, A, B with one cue in B. The corrected
production command transferred B's cue to A and atomically removed empty B plus
both B references. Only the selected shared Presentation changed, registry bytes
were unchanged, one receipt was added, and a repeated transfer was a complete
no-op. `qualified-cli-after` retains the exact result.

Native restart opened successfully. `qualified-native-open` is **byte-identical**
to the CLI snapshot/vector: the app made no invariant repair or history rewrite.
Native Operator Notes were then changed to
`Native continued editing after qualified cue transfers`;
`qualified-native-continued` retains that continued native history. Cue payloads,
placement identities, the remaining group's metadata and repeated arrangement
stayed intact. File → Export → Presentation produced NativeReexport.pro, SHA-256
`6b8a4efc292c6d7a29c1b78fac35058fedd3c84548b135359a94101105d74d97`.
Tests compare native-exported groups, arrangements, selection, Operator Notes and
cue identities, and replay the final native continuation into the pre-transfer
history. Native acceptance also exercises the corrected stored state-vector
encoding beyond the earlier hash-map capacity boundary.

The probes used only the owned local Presentation. Their explicit bounded
SQLite publications checked the exact original snapshot and stopped writers,
updated only its five persistence columns, and recorded their own operation
receipts. General group creation/deletion and unknown-reference conversions are
not exposed by these contributor experiments.
