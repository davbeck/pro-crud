# Native 22 media traversal across document roots

Collected October 15, 2026 against the retained 385-stream schema-9 native
snapshot and owned acceptance fixtures, pinned ProPresenter 22 beta build
**369098875**, macOS **27.0.1**. No Cloud connection or service is involved.
This extends the read-only work in `ProPresenter22MediaIdentity.md`.

## Persistent descriptor closure

The initial 53-file 22 descriptor bundle omitted `macros.proto`,
`propDocument.proto` and `playlistTemplate.proto`. Those persistent document
roots must not be inferred from the old generated types. The bundle now has
**56 files**, including these exact native descriptor records and their import
closure. Each added record was rechecked against its source binary byte range
and SHA-256; the actual installed ProCore SHA-256 still matches the existing
pin `793c50c3e28dc742a06eb6ac2029478843372a3667963302737e0f746d273e09`.
`Vendor/ProPresenter22Proto/provenance.json` records every offset/length/hash.
The new descriptor-set SHA-256 is
`e14d58defe05e9a9f31a31ce5af10dcec624c829ec225d755e052d5cac8cefe8`.

No 21 generated types or descriptors changed. Resource byte equality and
`Scripts/sync-protobuf-assets.sh --check` pass.

## Extended read-only graph

Media traversal now includes these distinct native roots, using the pinned 22
message descriptor and rejecting unknown fields before returning a stream's
complete results:

| Kind/scope | Message |
| --- | --- |
| Workspace/shared | `rv.data.ProPresenterWorkspace` |
| Workspace/client | `rv.data.ProPresenterLocalWorkspace` |
| Macros/shared | `rv.data.MacrosDocument` |
| Props/shared | `rv.data.PropDocument` |
| Stage/shared | `rv.data.Stage.Document` |
| PlaylistTemplates/shared | `rv.data.PlaylistTemplate` |
| Messages/shared | `rv.data.MessageDocument` |
| Messages/client | `rv.data.MessageLocalDocument` |

This includes native macro/prop collections, retained top-level macro/cue
fields, Workspace mask media, stage graphics and playlist-template cue actions.
It retains the original native snapshot; no configuration export or write is
introduced. Shared and client streams are independently encoded and inspected,
never merged or used as fallbacks. Every reported occurrence now includes its
source scope as well as document ID. Derived thumbnail URLs and other non-Media
roles are not reclassified as document file assets.

The Workspace root retains keys such as
`bundled_theme_rollout_sequence__version_3`. The pinned descriptor's source
comment explicitly says Core retains monotonic versioned markers and projects
**their maximum** into `bundled_theme_rollout_sequence` for export. The native
control contains legacy value 0 and markers 1, 2 and 3. The read-only adapter
projects maximum 3; it validates unsigned 32-bit marker values. Unrecognized
suffixes and other unknown fields remain visible to the descriptor gate. It
does not delete or rewrite stored markers or treat arbitrary unknown fields as
ignorable metadata.

## Native corpus and independent oracle

The same retained snapshot now enumerates **946** `rv.data.Media` occurrences:

| Kind/scope | Occurrences |
| --- | ---: |
| Presentation/shared | 828 |
| Theme/shared | 75 |
| PlaylistMedia/shared | 24 |
| Macros/shared | 19 |

All 946 reference IDs are distinct. There are still **384** distinct asset IDs;
the 19 macro references intentionally share assets already referenced elsewhere.
An independent recursive scan of all 385 snapshots through official Loro WASM
1.16.2 finds the exact same `(document, scope, reference, asset, schema)`
multiset, with no missing or extra occurrences. The newly traversed eight
scopes produce no unmapped-field errors. Thirteen other scopes remain explicitly
uninspected, rather than claiming full dependency validation from zero detected
Media messages. Bare file URLs, Theme/library links, device roles and other
configuration dependencies require their own adapters.

This corpus is not checked in: it contains private workspace content. Only
aggregate results and schema evidence are recorded here. No recording/service
credentials or unrelated configuration values are exposed. The existing owned
native media snapshot/export remains the positive asset/reference oracle.
Constructed Loro documents place those owned native actions/fills into the
additional root shapes; they exercise traversal, not native mutation acceptance.
Tests include native collections and retained top-level fields, independent
client state, source scope, unknown-field invalidation, local file resolution,
rollout maxima and invalid/future markers.

The retained corpus has no copied media tree, so its comparison proves identity
enumeration, not local file availability there. The owned-media tests verify
exact local resolution. Asset-store membership, media write/copy authority,
provider refresh, full file/Theme dependency closure, rebasing and native media
transactions remain unqualified. Existing rendering references are unchanged.

Full suite: **404 core + 92 CLI + one harness test pass**, with the same nine
tracked rendering issues. SwiftFormat, SwiftLint and descriptor resource
freshness pass.
