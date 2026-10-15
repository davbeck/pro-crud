# ProPresenter 22 implementation status

Tracking `ProPresenter22Support.md`. This branch is a **partial implementation**
and must remain a draft; it does not satisfy the plan's completion criteria.
Do not describe the entire ProPresenter 22 feature set or native writes as supported.

| Plan area | Implemented | Remaining gate/work |
| --- | --- | --- |
| Storage boundary | Explicit-root storage inspection and explicit macOS userWorkspaces preference discovery with active/minimum-version hints kept separate from actual storage; native markers take precedence over leftovers; expanded exports distinguished; native access rejected in legacy readers/writers/Look/media/batch paths | Broader ambiguous/mixed fixture matrix |
| Export compatibility | Optional application metadata; independent 22 raw/Theme/empty-playlist fixtures; empty playlist expand/rebundle; multi-Presentation bundle collection loading, media-free collection edit/rebundle/native re-import acceptance; absent metadata and unknown-field preservation | Connected playlists, populated/media bundle and native edit/reimport acceptance across every export path |
| Targets and conversion | Typed 21/22 profiles; default 22 construction/export; retained 21 construction; JSON results; recursive wire/enum issues; known v2/media gates; atomic failed export | Complete versioned schemas/adapters; dependency/feature conversions and receiving-app 21.4/22 qualification; no lossy fallback is currently qualified |
| Schema | Existing generated decoder names retained, with verified 21.4 ligature/character-size/original-font fields and optional rendering-enabled state and playlist arrangement names; exact upstream 21.4 baseline with 146 pinned source files and separate descriptor; independently pinned 58-file 22 descriptor set with binary provenance, CRDT map/tree/atomic annotations and versioned binary materialization; repeated timeline preservation through known-field edits, singular-merge negative control and common/scoped KeyMapping wire tests and structured cross-target parent-scope, multi-Presentation timeline and per-item reference gates; schema resources and generated Swift freshness pass using the generator from the resolved SwiftProtobuf 1.38.1 package | Integrate remaining 21.4 fields into editable views and receiving-app KeyMapping/timeline behavior and any deliberate fallback conversions |
| Native reader | System SQLite committed-WAL backups and stable sidecar-free in-memory images with bounded external-writer retries; schema-9 gates, IDs/scopes/availability/checksums/counts/vectors; pinned official Swift Loro; registry metadata; typed library membership, logical presentation/Theme references, Master/group/arrangement ordering, playlist trees and transient protobuf views with matching client node expansion state; portable standard-playlist export with repeated/hidden media-free dependencies and native 22 import/re-export acceptance; selected shared/client saved/live Look and screen inspection with native-export agreement; media-free native Look preview with explicit Workspace-relative Theme context and disabled-state preservation; 336 presentation comparisons pass; all 358 retained Presentation/Theme streams materialize without unmapped fields; separate-target export and direct `render ROOT --native-stream UUID` with same-snapshot native Look resolution and pixel-exact native probe render | Non-menu oneof-keyed KeyMappings, configuration export/editing, connected-playlist local overlays, remaining playlist/action/media dependency export and media resolution/rebasing |
| Native media | Distinct occurrence/asset/container/schema identities and file/source/HLS locators; authoritative SourceInfo/FileProperties/root precedence with all stored locators retained; read-only Presentation/Theme, nested/live-video playlists, macro/prop collections, stage layouts, playlist templates, messages and independent shared/client Workspace dependency inspection, independent client playlist state checks, 946 occurrence identities matching official WASM, exact selected-root file resolution, optional bounded content hashes and explicit uninspected future/unavailable content; all 385 retained scopes now project and inspect; independent native shared-asset/bundle/standalone fixtures; unsafe writes remain gated | Asset-store authority, remaining non-Media dependency traversal, write/reference adapters, dependency export, real stale projection and complete migration mapping cases |
| Native writes | Targeted existing-Loro metadata and static slide plain-text/RTF replacement with native range cleanup, atomic font values and byte-identical native reopen/export, plus same-group cue-tree moves, cue ownership transfers with native empty-source/reference cleanup, group-name, arrangement-name/default-selection and arrangement-sequence operations, plus stable-ID arrangement creation/duplication and reference-aware deletion with explicit document-action unlinking, native child containers and independent native acceptance; native state-vector byte encoding regression and accepted restart; atomic SQLite stream/receipt publication and production `workspace apply` batches with ordered operations, one Loro commit per document and native two-document acceptance, no-op/idempotency/conflict/rollback tests; pinned contributor harness and production `workspace set-copyright-title`, action-UUID `workspace set-slide-notes` with plain/RTF content, `workspace move-cue`, `workspace rename-cue-group`, `workspace set-arrangement-groups` and `workspace transfer-cue`; disposable local CCLI commit survives native restart, continued edit and native re-export | Remaining production edit families: remaining placement/group/build operations, library locations, creation/deletion/duplication, playlists/PCO, templates and media transactions; corresponding native acceptance |
| New features/rendering | Existing unknown bytes preserved; schema-1 native local image/video static previews with exact selected-root resolution, explicit HDR/alpha/blur/provider/live/unknown-field gates, eight native-vs-export exact CLI comparisons and a fresh loaded native PNG comparison at existing 21 precision; unsupported active representations are visible and gated; existing 21 snapshots retained | Native fixtures and independent inspect/preserve/edit/render/package statuses for animations, stickers, APlay, HLS, ProDisplay, disabled screens, PowerPoint backgrounds and new rendering/PCO cases |
| CI/docs/release | Distinct immutable-fixture 21/22 checks plus full suite; scoped public docs/skills; native test guidance; Loro license packaging; universal arm64/x86_64 release build, local ad-hoc signature and arm64 CLI/native-reader acceptance | Extend existing 21 regression coverage for changed adapters; native 22 acceptance for new behavior; signed universal package and transitive dependency license audit |
| Cloud | Deferred by the user; discovery reports local/Cloud metadata and the writer rejects Cloud registrations | Outside the current local implementation scope |

Evidence is in `../Research/Format/ProPresenter22Reader.md`. The official Swift
binding decoded all 385 retained native snapshots, with exact deep-value agreement
against independent official WASM projections. This qualifies diagnostic decoding,
not semantic materialization or editing.

`../Research/Format/ProPresenter22TargetAcceptance.md` records fresh 21-profile
and 22-profile bundles importing successfully into the pinned 22 build, a
committed native metadata edit, and native re-export with retained nested IDs.
The two generated MISC test presentations remain available for review.

Local validation: full Swift suite (447 core + 95 CLI + one harness test; nine known rendering issues, including the fresh native 22 text-layout comparison), CLI acceptance, SwiftFormat/SwiftLint, protobuf generation/resource
freshness, and bundled four-document/99-variation Theme freshness pass. The Theme
generator now fixes only AppKit's informational RTF writer-version header: all
140 host-generated differences were exactly that header; the shipped asset and
reference images remain unchanged. The native harness adds a separate passing
negative-control test and the pinned positive local metadata experiment. x86_64 compilation passes. An x86_64 runtime smoke test
can use Rosetta; a separate Intel host is not required and this check does not
block local implementation.

`../Research/Format/ProPresenter22LocalPersistence.md` records the first qualified
local metadata commit: exact native update/receipt hash, only one affected shared
stream, native restart/continued editing/re-export, integrated writer WAL setup,
and a byte-identical real no-op. The production `workspace set-copyright-title` command now calls this same
qualified writer. Native Slide Notes now use the same writer with action-UUID selection, rich-text preservation and native restart/continued-edit validation. Same-group `workspace move-cue` now retains placement identities and passes native restart, independent re-export and continued native editing; other native edit families are not exposed.

The existing native-exported 21 fixtures, reference images, documentation and
tests are the 21 regression baseline. Reuse them rather than requiring a new 21
installation to continue implementation. Fresh receiving-app acceptance is
useful for changed conversion semantics that the existing corpus cannot prove;
it is not a prerequisite for unrelated code or local 22 experiments. Separate
account/helper isolation is needed when actually switching native app versions,
not for every test against the existing corpus.

The user confirmed that additional isolated 21.4/22 installations and a disposable
Cloud workspace are unavailable at present. Use the existing 21 corpus for
regression qualification and the authorized local 22 instance for new native
experiments; record any receiving-app coverage limits with the affected change.

The installed 22 test instance is authorized for local experiments. Stop actual
workspace writers and use disposable copies for direct persistence experiments.
No active Cloud connection is needed for local reads, exports, media resolution,
local editing, or their tests. The plan explicitly permits local/offline writes
without qualified Cloud merges. The absent Cloud workspace limits only Cloud
write claims; it does not block the remaining local implementation.

`../Research/Format/ProPresenter22GroupEditing.md` records the native repeated
arrangement, group rename, production operations, unchanged unrelated rows,
native restart, independent re-export and continued native editing. Parallel
legacy arrays that would become stale are explicitly rejected for structural
edits. Other native structural families remain unfinished.

`../Research/Format/ProPresenter22AtomicBatches.md` records the production
six-operation/two-Presentation transaction, an invalid-final-operation negative
control with unchanged hashes, complete no-op replay, independent native exports
of both documents and continued native editing. Atomic batches cover the already
qualified edit families; media/file and membership transactions remain unfinished.

`../Research/Format/ProPresenter22CueTransfers.md` records native reparenting,
independent app-enforced empty-group and repeated-reference cleanup, full deep
state agreement with the corrected writer, unknown-reference deletion gating,
production atomicity/no-op checks, repair-free native reopen, continued editing
and native re-export. Group creation/deletion beyond that native transfer rule
remains unfinished.

`../Research/Format/ProPresenter22SlideText.md` records independent native Reflow
and font-range edits, production plain-text and RTF transactions, byte-identical
native reopens, continued native editing and independent Presentation exports.
Static text replacement is qualified; text delivery/element builds are gated.
The fresh 22 native PNG exposes a remaining CLI text-layout difference, retained
as a precise known-issue comparison without changing any 21 references.

`../Research/Format/ProPresenter22ArrangementEditing.md` records independent
native Master selection and arrangement naming, production batch rename/select,
byte-identical native reopen, no-op replay, native continuation and independent
re-export. Existing IDs, repeated sequences, unknown containers and stored UUID
spelling are preserved. Arrangement creation/duplication and reference-aware deletion are qualified separately below.

`../Research/Format/ProPresenter22MediaTraversal.md` extends the pinned native
descriptor closure to 56 files and media traversal to eight additional scopes.
All 946 detected Media occurrences across the retained 385-stream corpus match
the official WASM oracle; 19 macro references were previously uninspected.
Scope is retained per occurrence. Asset-store authority and non-Media dependency
roles remain separate work, and thirteen scopes remain explicitly uninspected.

`../Research/Format/ProPresenter22RenderingCorpus.md` retains fresh native 22
exports of the existing nine-area/71-slide corpus, all native payloads/media
and owned streams, and a production edited two-Presentation bundle with native
import/re-export acceptance. Collection loading preserves all payloads/resources;
media-free collection bundling validates all documents atomically. Three exact
shape controls pass; broader 22 rendering parity and the remaining fixture
families still require individual qualification. Existing 21 images are unchanged.

`../Research/Format/ProPresenter22MediaRendering.md` records native file-media
previews, source precedence, exact CLI agreement across native stream/export
paths, actual local-workspace PNG/PDF/JSON rendering and separate loaded-media
native PNGs. Existing 21 file/source fields do not select the native identity
adapter. One transparent PNG passes the existing 21 comparison precision;
full pixel parity is not claimed. Media writes, asset-store authority and
provider/live/HDR/blur behavior remain separate work.

`../Research/Format/ProPresenter22ArrangementLifecycle.md` records independent
native creation/deletion/duplication controls and production stable-ID
creation/duplication, including empty/repeated sequences, explicit selection,
matching no-op replay, invalid-final-operation atomicity, one changed stream
and receipt, byte-identical native reopen, continued native empty duplication
and an independent export of all seven arrangements.

`../Research/Format/ProPresenter22ArrangementDeletion.md` qualifies reference-aware
arrangement deletion and explicit Presentation document-action selector clearing.
All mapped shared/client streams are inspected; unresolved matching links and
uninspected scopes block deletion. The final batch graph and its complete
reference read set are checked atomically. A real two-document batch passes
reference rejection, invalid-final-operation rollback, no-op unlink replay,
byte-identical native reopen, continued native edits and independent exports.

`../Research/Format/ProPresenter22ConfigurationRoots.md` expands the exact pinned
descriptor set to 58 files and maps the remaining configuration roots with
independent client status. All 385 retained streams project, including eight
client streams; all 946 media identities still match WASM with zero uninspected
streams. Typed Timestamp map keys fix the demonstrated Calendar failure.
Non-menu oneof-keyed KeyMappings, configuration export/editing and non-Media
dependency roles remain explicitly unqualified.

`../Research/Format/ProPresenter22WorkspacePreferences.md` records the native
legacy registration shape and read-only preference discovery. Active/minimum-
version hints can still point at retained copies, so no automatic workspace
selection is introduced. It also records the distinction between group hotkeys and menu mappings; non-menu map-key
support remains gated.

`../Research/Format/ProPresenter22KeyMappings.md` qualifies native-authored menu
map identities, target matching, stored keyboard/MIDI values and byte-identical
native restart. Unknown oneof-wrapper members now receive completeness issues,
verified by a previously failing injected-field test. All 385 retained and 62
local streams still project completely. Non-menu mapping categories remain gated.
`../Research/Format/ProPresenter22UniversalBuild.md` records universal compilation,
CLI/resource/skill acceptance and local ad-hoc signing. Rosetta is absent;
Developer ID installer/notarization and dependency notices remain release gates.
