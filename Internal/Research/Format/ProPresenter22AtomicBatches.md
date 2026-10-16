# Native local atomic edit batches

October 15, 2026. Pinned ProPresenter 22 beta 369098875 on macOS 27.0.1, local
ProCRUD Local Persistence Test workspace. Cloud remains outside this scope.

`workspace apply ROOT --file FILE --registry PATH` accepts a version-1 JSON
manifest of explicitly selected native Presentation operations. Supported
operations are CCLI song title, plain Operator Notes, plain/RTF Slide Notes,
same-group cue moves, cue-group names and existing arrangement group sequences.
The manifest version is its own schema version, not the ProPresenter version.
Unknown operations/keys/versions, invalid identities, missing fields and
conflicting Slide Notes content sources fail. RTF files resolve relative to the
manifest directory, including directory URLs without a trailing slash; absolute
paths also remain ordinary file paths. All decoding/file reads precede workspace
publication. Diagnostics identify the manifest coding path and concrete problem.

The writer reads one consistent native workspace snapshot and groups operations
by exact document identity in first-occurrence order. Operations within each
document retain their manifest order. Each operates on the current state of one
imported Loro document, so later notes, names, arrangement and placement edits
observe earlier changes. Each changed document gets one Loro commit, update,
state-vector encoding and receipt. All changed streams/receipts publish in one
SQLite transaction after all operations prepare successfully. No native document
is reconstructed from diagnostic JSON. Empty/no-op document changes produce no
receipt. Existing-source generation and unrelated fields/scopes are preserved.

Automated coverage verifies operation ordering, one history change per document,
update replay, unknown containers, malformed manifest rejection and relative RTF
files. Multi-document tests include an invalid final document before publication,
external edits between preparation and commit, rollback of earlier stream and
receipt writes after a later conflict, idempotent prepared-patch retry and final
environment failure rollback. Existing single-operation commands use this same
batch entry point.

## Actual production acceptance

Pinned preflight passed with the UI and its actual helpers stopped. The owned
source Presentations were:

- `bfa7b647-93ab-5ee6-b397-ec61b08bcfee`,
  `Default/ProCRUDTarget22Acceptance`.
- `900d3c21-55ae-4446-8f44-1563b0dbbb1c`,
  `Default/ProCRUDTarget22Acceptance-1`, imported by the earlier portable-playlist
  acceptance. Both contain only independently authored test content.

`Native/Batches/edits.json` is the actual six-operation production manifest. Its
first document receives Operator Notes, CCLI title, group name, a two-occurrence
arrangement and rich Slide Notes; the second receives a different CCLI title.
A negative control appends an unresolved final stream. The command rejected that
batch, and every stream/registry/receipt hash remained unchanged.

The valid command changed exactly the two selected shared Presentation streams,
retained registry bytes and added exactly two receipts. Repeating the entire
manifest returned changed=false, six operations and no receipts, with every
stream/registry/receipt hash unchanged. The owned before and CLI snapshots/vectors
are retained separately for both documents.

Native restart opened the exact local workspace. The selected arrangement had
two occurrences/six slides with the CLI Batch Group name, and native Operator
Notes displayed `CLI atomic batch operator notes`. Native notes were then changed
to `Native continued editing after atomic batch`. Both Presentations were selected
and exported together with File → Export → Presentation. The unmodified native
exports are retained as FirstNativeReexport.pro (SHA-256
`7041df8e27932f58f3de5faa491d8d4f4475a537ced44999d134480029bcc2b5`) and
SecondNativeReexport.pro (`044ec26e8b49978de330e39df93418844dfce9f83931e7e3bbacc7934d13daed`).

Tests independently compare both exports' CCLI, groups, arrangement sequences,
selection, Operator Notes and nested cue identities; they check the rich
Slide Notes value including accented text/emoji. The second
export normalizes its lower-case native root UUID string to upper case; identity
comparison uses the UUID value, preserving the source native spelling. Both
CLI updates have exactly one history change and replay into their before
histories. Continued native histories replay without losing the CLI operations.
No other workspace's content was edited.
