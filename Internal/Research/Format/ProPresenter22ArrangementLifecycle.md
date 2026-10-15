# Native 22 arrangement creation and duplication

October 15, 2026, ProPresenter **22 beta build 369098875**, macOS **27.0.1**.
All experiments use the authorized local test instance without an account or
Cloud connection. The source is the owned ProCRUDTarget22Acceptance Presentation.

## Independent native controls

Native **New Arrangement** appends a new map with a fresh UUID, explicit name
and a `group_identifiers_v2` movable list containing each Master group once.
It selects the new arrangement. Native **Duplicate** also appends and selects;
it preserves repeated group occurrences, independently of the source's list
position. The native default copy name adds a numeric suffix. The CLI instead
requires an explicit output name and selection policy.

The checked-in controls under `Fixtures/ProPresenter22/Native/ArrangementLifecycle`
include actual before/created/deleted/duplicated snapshots and encoded vectors.
Only `arrangements` and `selected_arrangement` change in native creation and
duplication. Deleting the selected disposable native control clears selection
to Master and restores the original full deep state. Production deletion and cross-document reference handling are qualified in
[the separate deletion experiment](ProPresenter22ArrangementDeletion.md).

## Qualified Loro operations

`NativePresentationEdit.createArrangement` inserts a new map into the existing
movable arrangement list, then a new movable group sequence; source containers
and their history remain intact. It accepts explicit group order/repetition or
an empty sequence. Creation resolves group strings against native placements.
`duplicateArrangement` uses the source's exact group strings, preserving UUID
spelling. It rejects additional/unmapped arrangement fields instead of copying
a possibly self-referential future policy to the new identity. Independent new
creation retains such fields in every existing arrangement.

Both require stable caller-supplied UUIDs, a nonempty name and explicit selection
policy. Exact matching identity/name/sequence replay makes no change, including
selection when already correct; conflicting reuse fails. Batch operations run
against the current in-memory state, so a subsequent rename/selection can address
a newly created arrangement. Missing groups, source IDs and invalid names fail
before database publication. Existing metadata/selection operations are unchanged.

The version-1 manifest adds `add-arrangement` with `arrangement`, `name`, `groups`
and `select`; `duplicate-arrangement` uses source `arrangement`, new
`newArrangement`, explicit `name` and `select`. Required fields do not receive
implicit defaults. The normal registered-local/stopped-writer checks apply.

## Production native acceptance

The actual three-operation production `workspace apply` batch creates an
arrangement repeating the group twice, an empty arrangement, and a duplicate
of the original repeated arrangement. Its exact manifest is retained. With
ProPresenter and its helper stopped, an invalid fourth operation leaves every
stream hash, registry hash and receipt count unchanged. The valid batch changes
only the owned shared Presentation stream and adds one receipt (**139 → 140**).
Registry bytes remain identical. Replaying all three operations returns no
receipts and leaves all hashes identical.

Native restart shows the selected **CLI Duplicate Arrangement**, eight repeated
cue occurrences and every new name. Actual reopened snapshot/vector bytes are
identical to CLI output. Selecting **CLI Empty Arrangement** displays the native
empty-arrangement placeholder and zero cues; **CLI Created Repeated** displays
eight cue cells. Native duplication of the CLI-created empty arrangement then
creates **CLI Empty Arrangement 1**, also empty, with a new UUID and selection.
Native **File → Export → Presentation** independently retains all seven
arrangements and selection. The continuation's Loro updates merge into the CLI
history with exact deep-state agreement.

Fixtures retain only owned Presentation streams, the exact CLI manifest and
unmodified native export. `provenance.json` records per-file hashes, app/build,
OS, source identity and workflow. No configuration/account data is included.
Native group creation/deletion, general placement/build changes, library
membership remain separate work.

Final validation: **429 core + 94 CLI + one harness test pass**, with the same
nine known rendering issues. SwiftFormat and SwiftLint pass. Six core tests
include exact independent native creation/duplication, ordered/empty/repeated
batches, collisions/unknown fields, actual native reopen/continuation/export,
and the retained native-only deletion control.
