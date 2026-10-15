# ProPresenter 22 support plan

Investigation date: October 14, 2026, America/Los_Angeles. Target: macOS
ProPresenter **22 beta, build 369098875**, running on macOS **27.0.1**. This is an
implementation plan, not a claim that the current release supports the new
workspace format. Windows and later beta builds need separate qualification.

## Decision

Maintain **both 21 and 22 as supported read/write targets**. Treat 21 support
as a release requirement, not a legacy import-only path. Start qualification
with the exact macOS 21.4 build used for the existing fixtures and 22 beta build
369098875; expand to earlier 21.x builds only with a declared tested range.

Support 22 in stages: first restore compatibility with its exported protobuf
documents and explain the new workspace boundary; then add native workspace
inspection; finally add native editing only after its persistence and merge
semantics have been verified. Retain the existing protobuf implementation for
legacy files and interchange. A renamed directory or newer `.proto` snapshot
alone cannot support the new workspace.

The app's upgrade is a copy-and-convert operation. The previous workspace is a
separate, stale branch of the user's content. Writing there cannot update the
active 22 workspace. Local 22 workspaces and Cloud workspaces are distinct;
upgrading does not itself enable Cloud.

## Dual-version compatibility contract

Workspace storage generation, source application version, feature capabilities
and requested output version are separate properties. Do not infer any of them
from whichever ProPresenter app happens to be installed or running.

| Operation | Default | Explicit compatibility behavior |
| --- | --- | --- |
| Read/dump/render/validate workspace | Detect the source storage format and select its backend | Both 21 and 22 remain supported; report evidence, schema version and unresolved capabilities |
| Modify existing workspace/document | Preserve its storage generation and source-version semantics | Editing a 21 workspace never migrates it or adds 22-only structures; editing 22 uses native structures |
| Create new standalone content | Target 22 | Allow an explicit 21 target; construction uses only capabilities representable there |
| Export/bundle presentation, playlist or Themes | Target 22 | Provide a common explicit target-version option for 21 and 22 |
| Convert/export an entire workspace | Write to a separate destination | Preserve the source; explicitly select the output target, defaulting new exports to 22 |
| Edit an existing export archive | Preserve the archive's supported representation | Conversion is explicit; editing is not an implicit upgrade or downgrade |

Use one typed compatibility profile throughout the library, writer, bundler,
validator and CLI. The proposed CLI spelling is `--target-version 21|22`
(**planned, not implemented**) on relevant creation/export commands. Report
the selected target in command results and machine-readable reports. Add
equivalent fields to batch manifests where they create/export content, and
reject conflicting per-operation choices. Define how existing CLI output
commands request conversion without making a plain edit change formats.

### Workspace detection and inspection

Provide an explicit workspace inspection/discovery operation returning the
resolved root/identity, storage generation, backend/schema version, source app
metadata when present, supported capabilities, and detection evidence. Detection
must be independent of the installed application and preserve both registered
and explicitly supplied/custom-location 21 workspaces. A retained 21 workspace
remains intentionally editable when the user selects it.

Raw legacy files and 22 compatibility exports can share the same layout and
omit application metadata. Report `legacy-protobuf` / 21-compatible storage
where proven, with source application version unknown when appropriate; do not
claim an exact originating app version from folder shape alone. Native SQLite
schema 9 is a storage schema, not application major version 9. For ambiguous or
contradictory inputs, expose the evidence and fail unsupported writes rather
than guessing. Test unknown future versions and copied mixed-version folders.

### Target conversion and loss reporting

The target affects actual content, ordering, media identity/URLs and container
encoding; changing `application_info` or the file extension is insufficient.
Maintain independent 21 and 22 readers/writers or explicit compatibility
adapters where wire semantics differ. New 22 defaults must not leak into the
21 write path through shared factories or regenerated protobuf types.

Before writing a 21-compatible bundle, inspect the complete dependency graph
and produce structured issues with feature, component path, source/target,
severity and available conversion. Categorize each as lossless, a documented
semantic fallback, or unsupported. Preserve order, identity relationships,
arrangements, playlist links, Theme actions and media dependencies for the
lossless case. Handle v2 order, asset/reference identities, timelines and key
mappings explicitly. Treat animations, stickers, HLS and provider relationships
according to native-tested capabilities; do not assume they can all flatten.

Default to failing before publishing output when conversion would lose
behavior. Any lossy conversion requires an explicit opt-in and reports every
change. Do not silently drop unknown fields, fetch unbounded live media, or
pretend preserved unknown bytes are executable support in 21. Write atomically
to a separate destination; failed conversion leaves source and existing output
unchanged. A 21-target artifact must import and function in 21.4; a 22-target
artifact must import and function in the pinned 22 build. No arbitrary native
22 binary is required if its documented interchange format is the correct
delivery format: target 22 means qualified 22 behavior, not a guessed container.

## Continuous compatibility verification

Make both versions mandatory CI/release coverage. Current
`.github/workflows/tests.yml` runs one `swift test` job on macOS 26; it does not
prove two application-version contracts. Existing tests also generate many
inputs with the current `DocumentFactory`, so a factory change can change both
test inputs and implementation together. Retain immutable native-exported 21
fixtures and add independently sourced 22 fixtures.

### Automated test matrix

| Suite | Required cases and assertions |
| --- | --- |
| Detection | 21, native 22, 22 legacy export, absent metadata, both installed, custom/moved roots, stale preferences, incomplete/mixed folders and unsupported future schemas; detection never mutates input |
| Existing-workspace CRUD | Run every currently supported edit family against 21 and 22 backend fixtures, including text/RTF, cues/groups/arrangements, actions, Themes, local PCO overlays and media batches; verify source version, unchanged state and native semantics |
| Creation/export targets | Test omitted target equals explicit 22; explicit 21 for presentations/bundles, playlists and Themes; invalid targets fail; 21 profile cannot emit active 22-only representations |
| Source × target | 21→21, 21→22, 22→22 and 22→21; inspect, edit, export and reload with the destination profile; lossless semantics agree, unsupported/lossy cases fail or require the deliberate conversion policy |
| Preservation | Unedited/unknown fields, optional presence, nested identities, shared assets, ordering and repeated arrangements; no-op writes preserve semantics/history as applicable; don't require byte equality for valid native normalization |
| Downgrade failures | New/unknown features, multiple timeline presentations, incompatible mappings, remote/unavailable media and provider links; full issue reports and no partial writes |
| Atomicity | Failed edit/apply, conflict, interrupted media copy and conversion rollback for each backend; source and unrelated workspace hashes remain unchanged |
| Rendering | Separate native 21 and 22 reference sets with pinned build, OS, fonts and export settings; versioned expected differences instead of replacing the old goldens |
| CLI/package | Same installed CLI opens/edits both, targets both, installs the correct docs/skills and reports its selected profile; universal release includes both adapters |

Parameterize behavior-based Swift Testing suites over backend/profile/fixture
cases, while keeping version-specific exceptions named and explicit. Include
21-only and 22-only tests; do not force false equivalence for features that
native versions render differently. Cross-target tests must use an independent
destination decoder/native export oracle, not just reload with the same writer.
Keep schemas/types or compatibility adapters versioned for changed nested
types and cardinalities; regeneration must not remove the 21 decoder contract.

Both compatibility suites must execute on every relevant PR and branch build,
with distinguishable results and required checks for each. A single run may
execute both matrices if it demonstrably runs every case; duplicate jobs are
not themselves evidence of coverage. Keep app-independent fixture tests on
ordinary CI. Add pinned native integration jobs to dedicated interactive Macs
or isolated local environments and require their results before releasing
compatibility changes. Do not silently skip a missing app/font/fixture and mark
that version qualified. Report exact target builds and fixture-set revisions.

### Native application acceptance

For each app version, start from a disposable version-specific workspace; verify
the actual executable/build, helper ownership and workspace root. Import the
corresponding CLI-generated bundle, reopen and edit it natively, trigger/capture
where needed, export again, and compare structure, references and native output.
Run the 21→22 and 22→21 delivery cases in the receiving application. Include
restart persistence and alternating-version runs, checking the other version's
workspace remains unchanged. Native upgrade is tested only on copied 21 input.
Changes in either workspace do not automatically synchronize to its sibling.

## Keeping both applications locally

Keeping two separately named application bundles is feasible, but it does not
isolate their per-user settings, workspace registry or installed helpers. The
currently installed app uses bundle ID `com.renewedvision.propresenter` and a
helper under `~/Library/Application Support/RenewedVision/ProPresenter/Helpers/Workspaces`.

Renewed Vision explicitly says 21.4 will not replace the newer helper installed
by 22. Its [downgrade procedure](https://support.renewedvision.com/hc/en-us/articles/55756898162451-How-to-Downgrade-from-ProPresenter-v22)
requires quitting ProPresenter, removing that helper installation and ending
matching processes before installing 21.4. Renaming `.app` bundles and changing
workspace folders therefore does not establish safe switching in one account.
The official [download page](https://www.renewedvision.com/propresenter/download)
provides past releases, including 21.4.

**Preferred local setup:** keep pinned 21.4 and 22 app bundles in distinct
locations and use separate macOS test accounts, one per version. Give each its
own disposable workspace/media/preferences and launch by explicit app path,
not bundle ID, name, Finder file association or `open -a ProPresenter`. Disable
automatic app updates in the test environments. Record bundle signatures,
versions/builds and downloaded artifact hashes without modifying signed bundles.

Separate accounts are a proposed isolation strategy based on the per-user
helper location, not an already completed side-by-side experiment. During setup,
verify helper/launch-agent ownership, preferences, ports and shared services
actually remain isolated across logins. Fully log out/stop one test session
before switching initially; do not start concurrent output sessions as a
default. Use separate macOS installations/VMs or machines if account isolation
is insufficient. Hardware/rendering fidelity needs separate validation in a VM.

Provide a small Swift/TypeScript native-test launcher/harness that selects a
registered app path and workspace profile, checks the executable/build and
process owners, verifies the expected isolated helper and output/API endpoints,
and writes a run manifest. Refuse mismatched environments before touching a
workspace. Do not change bundle identifiers, falsify app versions, or automate
helper deletion in the normal test loop. Same-account helper teardown/reinstall
is a separate controlled switch procedure with restore checks if ever needed.

**Status:** only 22 is installed under `/Applications` at inspection time.
Neither 21 installation nor new macOS test-account creation was performed as
part of this planning update. Dual-app isolation must pass the native acceptance
gate before it is advertised as a supported experiment environment.

## Evidence and current compatibility

Detailed investigation records:

- [Storage and migration](../Research/Format/ProPresenter22Storage.md).
- [Code audit](../Research/Format/ProPresenter22CodeAudit.md).
- [Official release, Cloud, API, and schema sources](../Research/Format/ProPresenter22Public.md).
- [Native import, export, and image experiments](../Research/Format/ProPresenter22NativeExperiments.md).

| Area | Observed result | Consequence |
| --- | --- | --- |
| Workspace location | Active data moved from `UserWorkspaces/<name>` to `Workspaces/<UUID>`; old path remains in preferences | Do not discover the active workspace from the legacy `applicationShowDirectory` preference alone |
| Native documents | `DocumentStore/workspace-v1.sqlite3` schema 9, Loro snapshots, retained `.loropatch` migration updates, separate RocksDB media store | Add a storage backend; the current raw-document loader cannot open this workspace |
| Migration completeness | Native Legacy Workspace export reproduces all 336 original presentation relative paths | No missing presentation documents were demonstrated by the six-media warning |
| Native stream decoding | All inspected snapshots import with official `loro-crdt` 1.16.4 | Feasible read-only prototype; this does not establish write/merge compatibility |
| Raw Presentation export | Sample parses with appInfo 22/build 369098875/macOS 27.0.1 | Existing protobuf document model remains useful |
| Presentation Bundle export | ZIP extracts; sampled embedded presentation omits `application_info` and is rejected | Current document identification/validation has a definite 22 incompatibility |
| Theme export | ZIP extracts; sampled `*/Theme` omits `application_info` and is rejected | Same compatibility problem for themes |
| Legacy Workspace export | Recreates raw Libraries, Playlists, Themes, Configuration; all 336 presentations, 21 Themes and three playlist roots omit `application_info` | Bridge is real but needs loader qualification and media diagnostics |
| Playlist export | Empty standard playlist archive parses, with appInfo 22 | Nonempty and Planning Center archives still require fixtures |
| CLI authoring into 22 | Generated `.probundle` imports successfully | Basic existing output remains consumable by 22 |
| Simple rendering | Imported rectangle's native PNG and CLI PNG have identical sRGB premultiplied RGBA pixels at 854×480 | Geometry baseline only; no general text/media/animation parity claim |
| Imported identities | Native import changes root presentation UUID; nested cue/action/slide/element IDs survive in the probe | Resolve workspace identity explicitly rather than assuming root UUID/file name equivalence |
| Public HTTP API | Target still advertises `api_version: v1`; hosted schema differs from runtime in several old collection shapes | Keep the separate API skill and installed-version verification; do not introduce a document CLI API wrapper |

Adding only native `application_info` bytes to ignored diagnostic copies made
all 360 supported Legacy Workspace payloads load with the existing CLI. The
originals were untouched. This isolates the first interchange blocker; both
loader and validator need a deliberate optional-metadata contract.

### The media warnings

The supplied screenshot reports **six media files that could not be upgraded**
and says the originals remain in the previous workspace. Do not interpret that
as six missing presentations, six missing files in total, or a confirmed
pro-crud defect.

The controlled **Legacy Workspace export separately reports 71 unavailable
media entries**. That count describes export materialization, including a
diagnostic for media without a portable locator or durable materialized source.
It is not the original migration error count. Retain both reports separately.
All **2,325 old `Media/` files (15,935,940,406 bytes)** are present under the
new root with identical SHA-256 hashes. Exactly six old media actions already
lack a source URL; their corresponding native projections have a null source.
These are strong candidates for the original six-item warning. The six
`invalid_projection` items in the export manifest match them. The other 65
export entries have unavailable source locators whose equivalent old paths are
also absent. The storage report identifies the six presentations and cues.
No retained report explicitly ties their names to the first-run alert, so that
last attribution remains an inference. There is no evidence that migration
deleted or changed physical media that existed in the old `Media/` folder.

### Confirmed schema changes that affect existing operations

Read-only extraction from the installed ProCore binary recovered 165 named
proto3 descriptors and 2,049 message definitions. Compared with the exact
upstream 21.4 descriptor set, 67 common messages changed and 439 messages were
newly present, including private runtime/helper messages. All 5,634 recovered
embedded descriptor copies agree structurally. This is a forensic inventory,
not a completeness claim or a count of persisted feature formats.

| Area | Confirmed fields/shape | Required treatment |
| --- | --- | --- |
| Master/group/arrangement order | `Presentation.cue_group_placements=24`, `Arrangement.group_identifiers_v2=4`, `CueGroup.cue_identifiers_v2=3` | Native Loro trees/maps replace the old ordering arrays; adapt every structural edit and ordering-dependent render |
| Build order | `Slide.element_build_order_v2=8` | Resolve and mutate the active build representation rather than leaving a stale authoritative list |
| Playlist/library graph | `PlaylistDocument.playlists=7`, `live_video_playlist_nodes=8`, new `PlaylistNode`, `LibraryTreeDocument` | Adapt graph hierarchy and local/shared overlays; define precedence with old root fields |
| Media | `container_id=9`, `asset_id=10`, `identity_schema_version=11`, `hls_stream=12`, `provider=13` | Separate media occurrence/container/asset identity; do not carry forward the old single-UUID asset rule |
| Text animation | Effect variables `grouping=8`, `motion=9`, `motion_style=10` | Preserve and interpret effects/build parameters; runtime texture-atlas messages do not define saved slide storage |
| Provider linkage | `ProviderInfo` in media, presentations, slides, playlists and playlist items | Preserve rendition/version/parent relationship and native refresh ownership |
| Key mappings | Fields 101–106 now reference `CollectionElementTypeKey`; nested field 2 is string name instead of UUID message | Explicit version/shape adapter; a regenerated type alone does not qualify old files |
| Timelines | `TimedPlayback.Sequence` field 3 becomes repeated `presentations`; item `presentation_uuid=8` | Avoid singular decoding that silently merges multiple messages; preserve cross-presentation references |
| Other v2 arrays | `CopyrightLayout.tokens_v2=3`, `Calendar.Event.recurrence_excluded_dates_v2=10` | Preserve order/recurrence semantics and validate legacy/native conversion |
| Workspace/local state | Media schema version/Theme rollout metadata, client recording settings and preset/stream roots | Keep machine-local recording destinations separate from shared content |

The native corpus uses placement trees in every presentation, UUID-keyed cue
maps, 325 nonempty arrangement v2 sequences, and 21 nonempty slide/template v2
build-order sequences. A scan of 360 relevant exported protobuf payloads found
none of the four new presentation/group/arrangement/build ordering fields:
the tested export bridge downconverts ordering to the old representation.
Therefore qualify exports and native streams separately. Of 360 supported raw
Legacy Workspace roots, 353 contain unknown wire fields under the old schema;
successful loading after fixing metadata is not complete semantic support.

## Work packages and dependencies

The numbered packages are implementation-sized boundaries. Packages 2 and 3
can run alongside the native-backend work. Rendering feature work follows the
schema inventory. Every package retains legacy regression coverage.

### 1. Describe and detect the compatibility boundary — first release

**Change:** introduce explicit input/storage classification for raw protobuf,
export archive/expanded archive, legacy workspace, and native 22 workspace.
Recognize the observed `DocumentStore` marker/database layout without treating
unrelated SQLite files or `.loropatch` artifacts as presentations. Report the
detected format and the exact supported operation. Keep expanded single-export
directories distinct from a whole workspace.

**Code:** `DocumentModel.swift`, `DocumentArchive.swift`, `Archive.swift`, CLI
argument help and errors; `StrictMediaValidation.swift`, `LookResolver.swift`,
`PlaylistMediaSource.swift`, `EditSetMediaBatchCommand.swift`.

**Behavior:** until native support lands, native workspace commands return an
actionable unsupported-format error pointing to the native export workflow.
They must not silently scan the preserved legacy workspace. Missing native
registry/configuration support must not be reported as successful validation.
Give validation an explicit incomplete/unsupported result when required context
cannot be inspected. Exact public command/flag spelling is to be designed with
the implementation, not inferred from this plan.

**Acceptance:** fixtures for legacy-only, native-only, both coexisting,
renamed/custom-location workspaces, copied incomplete workspaces, mixed leftover
files, unsupported schema versions, and arbitrary non-workspace directories.
Prove read-only discovery makes no database/filesystem changes.

### 2. Restore exported-document compatibility — first release

**Change:** replace `application_info` as a required identity discriminator
with evidence-based structural recognition for each protobuf root. Metadata
absence can be valid; arbitrary protobuf bytes still must not become a valid
presentation/theme/playlist. Preserve absent metadata on edits and round-trips.
Do not manufacture a ProPresenter version to make a read succeed.

**Code:** `DocumentModel.swift`, `PresentationDocument.swift`,
`DocumentValidation.swift`, `DocumentDump.swift`, `DocumentCreation.swift`,
archive document-selection paths and corresponding tests.

**Fixtures:** independently authored presentations exported by 22 through
Presentation, Presentation Bundle, Playlist, Themes, and Legacy Workspace.
Include missing metadata, present 22 metadata, empty/minimal valid content,
multiple payloads, and corrupt/wrong-root negative controls. Capture variants
before and after opening/editing/resaving a migrated document; do not assume all
22 export paths serialize identically.

**Acceptance:** dump, validate, edit, bundle/expand, render, and atomic edit apply
work on every supported variant; failed edits leave originals unchanged.
Unknown field bytes/presence and unrelated archive compressed members survive.
Retest existing ZIP64/trailer defect handling against fresh 22 archives without
broadening corruption tolerance. Verify native re-import and export after an
edit, including media, duplicate file names, Theme document selection, and
nonempty/connected playlists. Do not use private library content as a shipped
fixture.

Legacy Workspace workflows must inspect and surface
`.procore/legacy-export-manifest.json`: target contract, reopened documents,
copied references, preserved unavailable media and compatibility warnings.
The observed manifest uses `current_pro7` with `preserve_and_report`; its 196
occurrence warnings consolidate to the 71 user-facing entries. Preserve this
distinction, and describe the export as a point-in-time compatibility snapshot.

### 3. Inventory and update the 22 protobuf schemas

**Change:** compare installed-build descriptors against the checked-in vendor
and the exact upstream 21.4 baseline. Upstream's latest autogen schema at
investigation time is 21.4, not 22; merely pulling upstream is insufficient.
Record descriptor extraction provenance, package/message names, field numbers,
wire types, oneofs, enums, renamed/removed fields and new opaque payloads.

**Code:** `Vendor/ProPresenter7Proto`, `Scripts/generate-protobufs.sh`,
`Scripts/sync-protobuf-assets.sh`, `ProtobufSchema.swift`, bundled descriptor
set, CLI source/schema resources and revision/hash metadata. Regenerate Swift;
never hand-edit generated `.pb.swift` files.

**Acceptance:** schema drift and asset freshness checks pass. Old files still
decode/write correctly. Inject unknown nested fields and enum values into
presentation/theme/playlist/action/media fixtures and prove preservation through
every affected operation. Known-new features receive capability diagnostics;
successful protobuf decoding must not imply editable or renderable semantics.
Keep captured native schema evidence separate from independently authored
redistributable fixtures.

**Required compatibility adapters:** test both KeyMapping nested layouts and
multi-presentation timelines before replacing generated definitions. Define
old/v2 precedence for playlist graphs, copyright tokens, calendar exclusions
and group/build order. Separate stale-vendor 21.4 catch-up (including screen
`rendering_enabled`, ligature/original-font data, media properties and output
configuration) from changes first observed in 22. Never remove older behavior
simply because a field is absent from a newer descriptor extraction.

### 4. Implement a native workspace reader

**Design:** add a native storage boundary beneath workspace operations rather
than teaching each call site to query SQLite. Reuse typed protobuf/domain code
through explicit materialization adapters where lossless representation is
proven. Keep the original Loro document as the preservation source; JSON
decoding is diagnostic, not a round-trip editing format.

**Tasks:**

1. Define a workspace identity/location model: registry entry, stable workspace
   ID, explicit directory, display name, local/Cloud distinction and availability.
   Preferences are hints; never silently select the old workspace or another
   workspace with the same name. Limit registry reads to workspace metadata.
2. Read consistent SQLite snapshots, including committed WAL content. Use the
   database backup/read-transaction mechanism; do not copy only the main DB or
   bypass SQLite locking. Preserve and validate schema version, stream scope,
   availability, checksums, byte counts and version vectors. No automatic
   migrations or repair on open.
3. Import Loro snapshots with a pinned official implementation. Investigate the
   official Swift binding/binary packaging first; validate imported 22 data and
   both release architectures before adopting it. A forensic JS/WASM decoder
   succeeding does not prove Swift/runtime compatibility.
4. Map every observed stream kind and both scopes. Separate shared content,
   client selection/state, core paths and unavailable/lazy streams. Treat patches,
   compaction/recovery artifacts and database snapshots according to proven
   authority rules; avoid double-applying history or reviving deleted content.
   All 334 retained migration patches are Loro updates already integrated into
   the current database: replay left all 334 serialized snapshots unchanged.
   Their presence is not a pending-edit journal.
5. Materialize library membership/order, presentations, playlist trees and
   connected wrappers, theme/group hierarchy, Workspace/Looks/screens, and the
   other configuration kinds. Resolve root stream identity separately from
   legacy protobuf UUIDs and paths. Detect missing/dangling references explicitly.
6. Route Look resolution, media lookup, strict validation, workspace batch
   enumeration, playlist selection, and library reference resolution through
   this interface. Keep ordinary document operations independent of a live app.

**Acceptance:** a sanitized native fixture decodes without the app running;
semantic inventories agree with native UI/API and native exports, including
counts/order/IDs. Reads during app writes observe a consistent generation or
retry with a bounded error; unavailable streams produce specific diagnostics.
Unsupported DB/Loro/schema versions fail without mutation. Include nested
libraries/playlists, duplicate names, empty/deleted content, both scopes and
core-backed streams. A full workspace dump must be a defined operation, not an
accidental consequence of expanded-export loading.

**Ordering adapter:** native cue maps are unordered. Read placement-tree
parents/node identities/fractional indexes for Master and cue-group membership,
then expand arrangements with repeated group IDs exactly. Handle empty groups,
ungrouped cue markers, ownership and build order explicitly. The same rule
applies to playlist trees. Tests must exercise both old and v2 representations,
mixed/stale representations, and precedence; until this works, reject
legacy-only structural edits on a v2 graph even if unknown bytes are preserved.
Group metadata/color/hotkeys, move/duplicate/remove, arrangement repetition,
cue transfers and build/text-delivery edits must update the active graph.

### 5. Update media identity and resolution

**Change:** support the native media reference/projection model in addition to
legacy `rv.data.Media` and `Playlists/Media`. Establish which metadata is
authoritative and which stores are derived before implementing writes. Keep
native per-occurrence reference UUID, container identity, `asset_id`, legacy
mapping, locator and materialized path distinct. All 892 inspected occurrence
reference IDs changed during upgrade, with 372 new asset identities. Do not use
cached paths or thumbnails as proof of availability.

**Code:** `Archive.swift`, `DocumentArchive.swift`, `PlaylistMediaSource.swift`,
`StrictMediaValidation.swift`, `EffectiveRendering.swift`, `Renderer.swift`,
`DocumentEditing.swift`, `DocumentEditSession.swift`, batch CLI.

**Acceptance:** tests for workspace-relative and absolute legacy URLs, native
identifiers, archive-local/Theme-local assets, moved workspace roots, same asset
under multiple paths, same basename/different assets, unavailable Cloud content,
unmanaged external media, remote streams and missing original files. Validate
every identity/reference class rather than skipping a missing `Playlists/Media`.
Bundle export includes all available dependencies, reports every unresolved one,
and leaves URL/identity relationships coherent after native re-import.

Two occurrences of one asset must have distinct reference IDs and share an
`asset_id`. Replacing one occurrence changes only its asset association;
relocation preserves asset identity; duplication creates new references while
preserving intentional asset sharing. Cross-check the complete old-to-new
reference mapping and asset grouping in a controlled migration fixture.
Include a stale projection cache carrying old IDs after the database has
already advanced; this was observed in the beta.

### 6. Add native edits only after persistence semantics are proven

**Prerequisite:** packages 3–5 and controlled before/after native experiments.
Native reads can ship before native writes. Retain the native import/export
bridge while direct writes are unqualified.

**Tasks:** prove how ProPresenter commits Loro operations, version vectors,
document hashes/counts, generation changes, operation receipts, shared/local
scope, media changes and helper notifications. Use a copied/disposable local
workspace with the app and relevant helper stopped for initial experiments;
quitting the UI alone may not stop all workspace writers. Discover actual
process ownership instead of assuming it.

Apply operations to existing Loro containers/history. Rebuilding a document
from JSON or replacing the SQLite snapshot blob is not an editing implementation.
Implement optimistic version checks and atomic multi-stream commits for edits
that affect memberships, references, identities and media. Preserve unknown
maps/containers and client-only state. Define rollback/recovery for failed
multi-file/DB commits and file copies before exposing workspace batch edits.

**Acceptance:** test no-op round-trip, one-field edits, reorder, duplicate,
create/delete, arrangements, Planning Center local links/visibility, template
application and media replacement. Verify app reopen, native re-export, native
rendering and continued native editing without reversion, corruption or resurrected
content. Conflict tests exercise external edits between load and commit; failed
edits leave all streams/assets coherent. Extend existing unknown-reference
remapping policies to new features before allowing duplication/deletion.

For Cloud workspaces, independently prove offline edits, reconnect merges,
concurrent writers, deletes/tombstones, paused sync and unavailable content in a
disposable Cloud workspace. Cloud testing requires a suitable account/workspace;
this investigation does not claim it happened. If those conditions are not met,
release an explicit local/offline write boundary. Do not invent private HTTP
endpoints or modify sync/account credentials to bypass that boundary.

### 7. Cover every new feature and changed rendering behavior

| 22 area | Required document work and diagnostic policy | Native validation |
| --- | --- | --- |
| Text animations | Identify build hierarchy, character/word/line segmentation, pace/direction and continuing-motion fields; preserve all; make existing `set-text-delivery`, template copy, duplication and render diagnostics animation-aware | Native-authored examples for each mode, mixed styles, multiline/multilingual/emoji, chained builds; capture frames/video and define an explicit static-frame policy before adding animation rendering |
| Animated stickers | Identify graphic/media type, animation resources, timing and placement; preserve native identity and dependencies; warn if static renderer cannot reproduce it | Native export/re-import of portable examples, alpha/crop/size/order, missing resources, timing via Syphon |
| Amazing APlay | Inspect native imported document/action/media representation; preserve grouping, identities and dependencies | Use an available authorized sample if this format is to be advertised; do not build an account/download integration merely to support its resulting documents |
| HLS stream actions | Distinguish live URL/action from local file media; preserve URL, playback/layer/transport fields; validation/bundling must not label a remote URL as a missing local file or fetch an endless stream | Controlled accessible stream; persistent action after export/import; static rendering emits an explicit unsupported/live-source diagnostic |
| ProDisplay export | Extracted schema describes service create/replace export carrying a presentation and folder/tag identifiers; no new local extension was established | Inspect the native service workflow and resulting document semantics if available; add a local container only with an actual artifact. Service-client integration is a separate scope decision |
| Disabled screens | Identify persisted enable/disable/routing semantics and per-computer scope | Disabled and enabled Audience/Stage/custom-target Look cases; static Look resolver must choose/report intended screen state correctly |
| PowerPoint backgrounds | Check resulting background/media/action representation and portability | Import one controlled deck with and without the option; compare exported documents and native images |
| Cloud/workspace | Preserve collaborative/shared vs computer-local content and availability | Local upgrade first; Cloud conversion/whole-workspace sync separately; cover documented smart-playlist conversion and excluded computer/account/Bible/external-media state |
| Rendering fixes | Test older text scaling, alternate-Theme list scaling, Reflow persistence and multilingual text | Re-export the relevant existing fixtures from 22 on the same host/fonts; retain 21.4 references and version the evidence |
| Playlist/PCO fixes | Recheck nested/active playlists, bundle import and linked arrangements/sequence groups | Controlled local/connected fixtures; preserve remote-owned structure and test only existing authorized local overlays |

Full feature support has separate **inspect**, **preserve**, **edit**, **render**
and **package** statuses. First make unsupported behavior visible and lossless;
do not infer rendering support from newly generated protobuf fields. Any new
renderer logic must follow a native image/video comparison, not a release-note
guess. Static PNG tests cannot validate timing.

### 8. Refresh the test corpus, documentation, skills and release gates

**Fixture matrix:** legacy raw documents and archives; fresh 22 raw/bundle/
playlist/Theme/Legacy Workspace exports; sanitized native local workspace;
native shared/local streams; the new feature examples above; corrupt inputs,
unknown fields/versions, missing media and failed multi-stream operations.
Keep native documents, exported reference images and schema extraction provenance
associated with exact ProPresenter/macOS builds. Add Windows exports/native
layout to a separate qualification matrix rather than claiming parity.

**Rendering:** import the existing typography, list indentation, edge cases,
sermon list, text Delivery and 71-slide reference playlist; export fresh 22 PNGs
using the documented workflow. Compare side by side with 21.4 and current CLI.
Investigate fonts/OS before changing renderer logic. Do not overwrite references,
loosen precision, or record snapshots merely to pass. Revalidate all four bundled
Theme documents/99 variations, their semantic text slots and media absence; run
the generator freshness check if its sources change.

**Documentation:** update `Docs/Format/TopLevelFileFormats.md`, companion
presentation/theme/playlist/build/render pages, README and CLI help with tested
version/scope. Explain active vs preserved workspace and native export/import.
Update shipped `skills/pro-crud` workflows so they resolve actual workspace
storage and use supported editing paths. Keep migration research, schema history
and this implementation plan in `Internal`, not shipped skills. Update contributor
computer-use/fixture guidance for 22 UI, helper ownership and versioned captures.

**API skill:** keep `skills/propresenter-api` self-contained. Continue `/version`
then `/v1`; document target-observed schema/no-content discrepancies without
calling them proven 22 regressions. Validate documented inventory, binary
thumbnails, UUID resolution, nested/active Planning Center playlists and streaming
reconnect behavior against the installed target. Do not invent new mutation
bodies from read responses or turn this into an API wrapper in pro-crud.

**Release:** verify architecture/dependency licensing/package assets and signed
universal CLI behavior if adding Loro/SQLite dependencies. Run focused tests,
full Swift tests, CLI acceptance, schema/resource drift, skill installation and
design Theme freshness checks appropriate to changed areas. Use normal build
caches; no serialized-test workaround. Run SwiftFormat and require SwiftLint
before commits under the repository rules. Version the compatibility table and
release notes with exactly what shipped; preserve 21.4 behavior.

## Delivery sequence and completion criteria

1. **Interchange compatibility:** packages 1–3, explicit 21/22 target profiles,
   preserved 21 workspace CRUD, native-export fixtures and scoped
   docs/skill updates. Every supported 22 export path reads/edits/re-imports; the
   native workspace is clearly diagnosed; no unsupported media validation passes.
2. **Native inspection:** packages 4–5 with supported inventory, media validation,
   rendering/Looks and export resolution. Native snapshot semantics and registry
   selection are proven without altering workspace state.
3. **Native local editing:** package 6 with proven atomic operations and helper
   lifecycle, plus required new-field preservation/diagnostics from package 7.
4. **Extended feature and Cloud support:** native feature rendering/authoring
   and Cloud writes only as their independent acceptance gates pass. Mark any
   remaining capabilities explicitly rather than calling the whole version
   supported without qualification.

Every stage must pass its applicable **21 and 22** regression/target matrix;
22 functionality cannot ship by turning off 21 tests. Implementation work must
carry the dual-version contract, conversion diagnostics, test matrix and isolated
native environments through packages 1–8, not defer compatibility to a later
cleanup. Defaults to 22 apply to creation/export; existing-source edits retain
their detected version.

Planning is complete when each observed break maps to a work package, every
new release feature has a capability/fixture decision, and unresolved beta or
Cloud behavior has a concrete acceptance gate. Implementation is complete only
after those gates pass; this investigation does not implement the plan.
