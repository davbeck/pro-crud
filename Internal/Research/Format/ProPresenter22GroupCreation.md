# Native cue-group splitting

October 15, 2026. ProPresenter **22 beta build 369098875**, macOS **27.0.1**.
Authorized local test workspace, owned `ProCRUDTarget22Acceptance` Presentation.
No account, Cloud connection or additional host is used.

## Independent native controls

In Master, native cue context menu **Group → Chorus 4** on cue two splits the
original four-cue group. It creates a fresh placement-group UUID immediately
after the original group and reparents cue two and every following cue, retaining
their tree-node IDs and cue values. Only `cue_group_placements` changes.
Every existing arrangement retains its exact group sequence, including repeats;
the newly created group is not inserted implicitly.

The new group's metadata copies the chosen native definition: name, application
group identifier, color and hotkey. In this control the previously customized
Chorus 4 supplies `hot_key.code = 11`, ANSI K. A second native split within that
new group, using Chorus 4 again, produces another independent group with the
same metadata and retains cue-node identities. It also leaves arrangements
unchanged. The exact snapshots/vectors are retained in `Native/GroupCreation`.

Official WASM inspection distinguishes the container types: placement `Kind`
and `group` are Loro maps; `hot_key` is another map; **color is an atomic value**.
Writing a nested color container instead would not reproduce the native model.

## Qualified operation

Version-1 batch `split-cue-group` takes `cue`, new `group`, existing
`templateGroup` UUIDs and explicit `name`. The template is an existing group in
the selected Presentation. This is an explicit copy policy: retain its color,
hotkey and application link, including when assigning a different label. It
does not resolve global definitions by name or silently reset copied metadata.

The operation creates the new group after the source with official tree
`createAt` and `movTo` operations. Existing cue and source-group containers stay
in place; the selected cue and suffix move without a JSON rebuild. It creates
the observed child maps and copies the atomic color value directly from the
retained template container. Unknown template/color/hotkey fields block copying;
the existing descriptor encoder also validates copied scalar types before any
new containers are created. A failing malformed-color test demonstrated why
field-name checks alone were insufficient.
Matching stable identity/metadata/first-cue replay is a no-op. Conflicting UUIDs,
missing references, empty names and splitting at a group's first cue fail.
The existing parallel-legacy-group gate remains in force.

This qualifies splitting a nonempty prefix/suffix. It does not expose empty-group
creation, first-cue group-definition replacement, deletion or general group
duplication. Use an explicit arrangement-sequence operation in the same batch
when the new group belongs in an arrangement.

## Production acceptance

With ProPresenter and the workspace helper stopped, the retained three-operation
manifest splits the last two-cue native group, names the new definition
**CLI Split Group**, sets one arrangement to original/new/new and selects it.
An invalid final split leaves every stream hash, registry hash and receipt count
unchanged. The valid batch changes only the selected shared Presentation and
adds one receipt (**159 → 160**). Registry bytes and every owned Media/Assets
hash remain unchanged. All three operations replay with no receipts or changes.

Actual native reopen retains CLI snapshot and encoded-vector bytes exactly,
without repair. The selected arrangement displays three occurrences. Master
displays four one-cue groups in the original cue order, with the copied color
and explicit CLI name. Native **Group → Edit** then renames the new group to
**Native Continued Split**, retaining its group and cue-node identities. Native
editing assigns a fresh application-group identifier and clears the shortcut
for that custom definition; its color is retained. This differs from the CLI's
explicit metadata-copy policy and is recorded rather than attributed to a
repair on reopen.

The continuation's updates merge into the CLI history with exact deep-state
agreement. Independent **File → Export → Presentation** retains all four group
definitions, cue order, repeated arrangement links, native selection and native
continuation metadata. Owned streams/vectors, exact CLI manifest and unmodified
export are retained with app/build/OS and per-file hashes in `provenance.json`.
The raw exported cue array uses map iteration order rather than Master order;
the test exercises the existing `PresentationDocument.orderedCues` group-order
adapter, compares every cue identity and compares all group memberships directly.

Validation: **451 core + 96 CLI + one harness test pass**, with the same nine
known rendering issues. SwiftFormat and SwiftLint pass. The full suite includes
the independent native controls, production reopen/continuation/export, scalar
validation and CLI manifest requirements. No reference images are changed.
