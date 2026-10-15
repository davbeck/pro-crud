# Local arrangement deletion and reference protection

October 15, 2026. ProPresenter **22 beta build 369098875**, macOS **27.0.1**.
All native changes use the authorized local test workspace without an account
or Cloud connection. The existing native-exported 21 corpus remains unchanged.

## Reference inventory

`workspace arrangement-references ROOT` visits complete pinned-22 protobuf
projections for every mapped shared/client stream. It follows active oneofs,
singular-message merge semantics and repeated fields, including repeated native
timelines. Explicit roles are playlist Presentation `arrangement` and
`arrangement_name`, and document-action `selected_arrangement`. Playlist targets
resolve through exact ROOT_SHOW logical library paths; no basename guessing is
used. Unknown fields, unmapped kinds/scopes and unavailable content are reported
as uninspected and block destructive deletion. Unrelated metadata edits retain
their existing capability boundary.

An independent official Loro WASM inventory of the retained 385-stream corpus
finds two playlist arrangement references. Every source/scope/role/target/
arrangement/name tuple agrees with the production reader; neither reports an
additional reference. This corpus contains no document-action selectors.

The owned `CLIReferenceInput.pro` supplies an enabled Presentation document
action selecting the disposable target arrangement. Native File → Import retains
the selector and action identity but omits `identification`. The pinned native
descriptor marks that field with custom option **51301, obsolete**. Consequently
the inventory does not treat that legacy target hint as authoritative, even
when it appears in an injected diagnostic value. Document-action targets remain
unresolved, and a matching arrangement UUID still prevents deletion. Runtime
target triggering is not qualified by this experiment.

## Qualified writes and atomicity

`remove-arrangement` deletes the existing definition from the retained Loro
movable list. If selected, it clears selection to Master, matching the independent
native deletion control in `ArrangementLifecycle`. Cues, groups, other
arrangements and history remain intact. Missing identities fail.

`clear-document-action-arrangement` requires the exact UUID of one Presentation
cue document action. It clears only that action's selector, retains the action
and target metadata, and is a no-op when already empty. It does not expose Macro
editing or automatically remove any link.

The writer inspects the final graph after preparing every operation, allowing
explicit unlinking and deletion in one batch. A UUID link to a resolved different
Presentation does not protect an unrelated same-UUID definition. Unresolved
UUID links and name-only playlist links are retained as protection. The complete
reference stream read set, including membership, content/vector, kind, path and
availability, is checked under BEGIN IMMEDIATE before any update. Changes or
new/deleted streams cause conflict and rollback. Prepared operation receipt
retries do not repeat deletion or replace later native edits.

## Actual production acceptance

The owned target initially has seven arrangements and selects the disposable
empty **CLI Empty Arrangement 1** (`7017BE68-8867-48CE-9102-60E9C49DF61D`).
The native-imported reference document stores that selector in document action
`12F67BC0-D8DE-47F3-91D9-B1692A758620`.

With the app and workspace helper stopped:

- Deletion alone rejects the exact stored reference, with source component path;
  every stream hash, registry hash and receipt count remains unchanged.
- Unlink + deletion + invalid final deletion leaves all the same values unchanged.
- The exact retained two-operation manifest changes only the two selected shared
  Presentation streams and adds two receipts (**147 → 149**). Registry bytes and
  every owned Media/Assets hash remain unchanged.
- Repeating only the unlink returns no receipts and preserves all hashes.

Native restart retains both CLI snapshots and encoded vectors byte-for-byte.
The target displays Master with four slides and the six retained arrangements.
Selecting **CLI Created Repeated** produces eight cue occurrences and persists
a native selection update. In the reference document, native New Arrangement
creates **Native After Unlink**, preserving the cleared document action.
Both native continuations merge into their CLI histories with exact deep-state
agreement. Independent File → Export → Presentation exports retain the six
target definitions, new native selections and the cleared selector/action.
Native export omits the reference action's stored empty `label` message; the
test asserts this exact normalization before comparing the entire action.

`Fixtures/ProPresenter22/Native/ArrangementDeletion` retains only owned source
streams/vectors, CLI input/manifest, identities and untouched native re-exports.
Its provenance records app/build, OS, source and per-file hashes. Regression
tests cover exact source-state changes, invalid/slide action IDs, graph
protection, atomic reference-read conflicts, update replay, native reopen,
continued editing and independent exports. No reference image is changed.

Validation: **442 core + 95 CLI + one harness test pass**, with the same nine
known rendering issues. SwiftFormat, SwiftLint and schema resource freshness pass.
