# ProPresenter 22 beta: repository compatibility audit

Investigation date: October 14, 2026. Native build: ProPresenter 22 beta,
22.0 (369098875), on macOS 27.0.1. This is an implementation plan and evidence
record, not a claim of released support. No product code or reference images
were changed during this audit. Private source exports and forensic results
are retained only in ignored `.build/pro22-investigation/`.

## Established compatibility changes

1. **The native workspace is a different storage system.** The migrated
   workspace contains `DocumentStore/workspace-v1.sqlite3` and native Loro CRDT
   snapshots, not editable `Libraries/**/*.pro`, `Playlists/Library`,
   `Playlists/Media`, `Themes/**/Theme`, and `Configuration/Workspace` files.
   Historical suffixed files left in some folders are not authoritative
   replacements. A current `pro-crud dump <native-workspace-root>` fails with
   the generic unsupported-document error.
2. **Protobuf remains an interchange format.** The native Legacy Workspace
   export restores the older directory layout and protobuf payloads. Its 336
   original presentation paths, 21 Theme payloads, and 3 primary playlist
   payloads have no root `application_info` field. The current loader rejects
   all these payloads solely at its first mandatory metadata guard; validation
   separately classifies absent metadata as an error.
3. **Export commands differ.** The inspected native presentation bundle and
   Theme archive also omit `application_info`, while a standalone `.pro`
   export and a presentation-playlist archive `data` payload contain current
   application metadata. Do not assume one successful export workflow
   establishes compatibility for the others. The bundle's `.pro` and Theme
   payload are otherwise decodable with the vendored protobuf definitions.
4. **Existing creation/import can work.** A new CLI-generated presentation
   bundle imports in beta 22. Its native standalone export is readable by the
   current CLI. The root presentation UUID changes on that import, while the
   inspected cue, action, slide, and element UUIDs remain stable. The simple
   rectangle's 854×480 native PNG is pixel-identical to the CLI render in the
   root investigation. This qualifies that small case only.
5. **Native SQLite rows need more than a payload update.** The storage audit
   found a `(document_id, scope)` stream key, stream kinds, logical paths,
   availability, Loro snapshots, version vectors, SHA-256, byte counts,
   timestamps, and shared-version metadata. Presentation logical paths omit
   both `Libraries/` and `.pro`. Shared document state and per-client state can
   occupy separate scopes. Native media projections contain richer structured
   references; the existing old playlist registry is absent.
6. **Native ordering is a tree, while inspected exports downconvert it.** All
   337 decoded presentation streams, including the synthetic probe, contain a
   nonempty `cue_group_placements` Loro tree, no old `cue_groups` array, and a
   dictionary of cues. The decoded corpus has 325 nonempty arrangement
   `group_identifiers_v2` lists and 21 nonempty slide/template
   `element_build_order_v2` lists. Installed descriptors add protobuf
   `Presentation.cue_group_placements` (24),
   `Arrangement.group_identifiers_v2` (4), `CueGroup.cue_identifiers_v2` (3),
   and `Slide.element_build_order_v2` (8). A recursive wire scan of 360
   inspected export payloads found none of those fields: the present export
   bridge materializes old ordering. Neither form should be inferred from
   the other without an explicit adapter and native verification.
7. **Metadata is the first loader blocker, not a complete schema proof.** In
   an ignored diagnostic mirror only, appending a native `application_info`
   field to the 360 Legacy Workspace presentation/Theme/primary-playlist
   payloads makes all 360 pass the current loader and protobuf JSON dump.
   Original exports remain unchanged. `protoc` decodes all 360 originals;
   353 contain fields unknown to the checked-in schema. Their semantic
   interpretation and editing remain separate work.

The full native-store and migration evidence is maintained by the companion
storage investigation. Counts above distinguish 336 original presentations
from the one synthetic probe added during this investigation.

## Exact existing source assumptions

| Area | Source | Present assumption and consequence |
| --- | --- | --- |
| Document detection | `Sources/ProCRUDCore/DocumentModel.swift` | `DocumentKind` has presentation, theme, playlist; raw names are `.pro`, `Theme`, `data`, `Library`, `Media`, `Audio`. Directory loading describes an expanded single export, not a general native workspace. |
| Metadata validation | `Sources/ProCRUDCore/DocumentModel.swift`, `Sources/ProCRUDCore/DocumentValidation.swift` | `hasApplicationInfo` is mandatory for every supported root, rejecting native 22 archive and Legacy Workspace exports. |
| Edit/write orchestration | `Sources/ProCRUDCore/DocumentEditSession.swift`, `Sources/ProCRUDCore/DocumentModel.swift` | Sources and destinations are raw files or ZIP payload members, and serialization is protobuf. They have no native stream identity, scope, revision, or transactional metadata. |
| Media registry | `Sources/ProCRUDCore/PlaylistMediaSource.swift` | Selects canonical media from hardcoded `Playlists/Media`, with a fallback to a containing `Media` file. Native 22 has neither authoritative raw playlist file. |
| Strict validation | `Sources/ProCRUDCore/StrictMediaValidation.swift` | Missing `Playlists/Media` silently yields an empty registry. A native workspace can therefore skip all canonical-registry comparisons without warning. Existing `ROOT_SHOW` handling is useful, but workspace selection and canonical registry data must change. |
| Batch media edits | `Sources/ProCRUDCLI/EditSetMediaBatchCommand.swift` | Every document/source is an ordinary workspace-relative file; atomicity is sibling-file staging/rollback; playlist-source discovery duplicates the hardcoded registry paths. |
| Looks | `Sources/ProCRUDCore/LookResolver.swift` | Reads raw `Configuration/Workspace` as `Rv_Data_ProPresenterWorkspace`; resolves Theme file paths against that root. Native 22 stores those documents and client selections in streams. |
| Playlist rendering | `Sources/ProCRUDCore/PresentationDocument.swift` | Resolves local `.pro` references against a directory/archive and then absolute paths. Native logical document identities cannot be followed through that interface. |
| Planning Center links | `Sources/ProCRUDCore/DocumentEditing.swift` | `planningCenterShowRoot` infers a root from a raw file in `Playlists/` and validates links beneath `Libraries/`; native paths and stream IDs need their own mapping. |
| Media rendering/materialization | `Sources/ProCRUDCore/Renderer.swift`, `Sources/ProCRUDCore/DocumentCreation.swift`, `Sources/ProCRUDCore/DocumentArchive.swift` | Resolution uses a resource directory, archive-relative assets, absolute URLs, and specific local roots. Native logical roots, media identities, and projection cache freshness require an adapter. |
| Semantic dump/components | `Sources/ProCRUDCore/DocumentDump.swift`, `Sources/ProCRUDCore/ComponentPath.swift`, `Sources/ProCRUDCLI/DumpTextFormatter.swift` | Expose protobuf paths and three payload families. Native normalized state must map to a supported semantic model without silently dropping fields. |
| Patching/copying | `Sources/ProCRUDCore/ProtobufJSONPatcher.swift`, `Sources/ProCRUDCore/TemplateResolver.swift`, `Sources/ProCRUDCore/DocumentEditing.swift` | Existing protobuf mutation preserves unknown wire fields. That guarantee does not preserve Loro containers, operation history, native references, or unmodeled native schema. |
| Ordering and arrangements | `Sources/ProCRUDCore/PresentationDocument.swift`, `Sources/ProCRUDCore/DocumentEditing.swift`, `Sources/ProCRUDCore/DocumentValidation.swift`, `Sources/ProCRUDCore/DocumentDump.swift`, `Sources/ProCRUDCore/TemplateResolver.swift`, `Sources/ProCRUDCore/TextDelivery.swift` | Current cue-group membership, Master order, arrangements, copy/remap, build and component-index behavior use old arrays. Native trees and v2 lists need one authoritative model and explicit materialization; merely retaining unknown v2 bytes can leave stale order or references after an edit. |
| Playlist schema evolution | `Sources/ProCRUDCore/PlanningCenterPlaylist.swift`, `Sources/ProCRUDCore/PlaylistMediaSource.swift`, `Sources/ProCRUDCore/PresentationDocument.swift`, `Sources/ProCRUDCore/DocumentEditing.swift`, `Sources/ProCRUDCore/DocumentDump.swift` | Installed 22 adds `PlaylistDocument.playlists` (7) and `live_video_playlist_nodes` (8). Existing code traverses old wrappers/children; it needs versioned tree materialization and explicit coexistence precedence before structural edits. |
| New-document metadata | `Sources/ProCRUDCore/DocumentCreation.swift` | Factory currently stamps application major 7 and macOS major 26. Changing that to 22 is not the workspace compatibility fix; choose any metadata change from native import evidence. |
| Containers | `Sources/ProCRUDCore/DocumentArchive.swift`, `Sources/ProCRUDCore/DocumentEditSession.swift`, `Sources/ProCRUDCore/ZIPArchiveReader.swift`, `Sources/ProCRUDCore/ZIPArchiveWriter.swift` | Export member selection and rewriting use the older payload shapes. Native ZIP archives remain readable by the existing bounded reader; Python's standard ZIP reader rejected the inspected archive central directory, so retain the narrowly validated native ZIP64 workaround. |
| CLI | `Sources/ProCRUDCLI/{DumpCommand,ValidateCommand,RenderCommand,CreateCommand,EditCommand,EditApplyCommand,ArchiveCommands}.swift` | Need clear document selectors/capabilities for native stores without changing existing raw/archive behavior by implication. |
| Dependencies and release | `Package.swift`, `bin/build-release`, `Packaging/Scripts/`, `.github/workflows/` | No native-store/Loro backend. Any new native library must work in the universal signed/notarized standalone executable and be accounted for in installer/resource checks. |

## Prioritized implementation work

### 1. Restore interchange compatibility and explain native workspace detection

- Accept genuinely optional `application_info` for identified, structurally
  valid native 22 protobuf roots in both loader and validator. Preserve its
  absence on write. Keep wrong-root and malformed-file rejection; do not
  manufacture metadata simply to pass the old guards.
- Add explicit detection of the versioned native workspace store and a
  targeted unsupported-capability message until that backend ships. Distinguish
  an expanded document directory from a native user workspace in help/errors.
- Make strict-media reports state registry availability. A recognized native
  store must not silently pass by treating a missing old registry as empty.
- Preserve the existing validated ZIP64 tolerance; change ZIP behavior only
  when fresh native exports demonstrate another actual requirement.

**Acceptance:** native raw presentation, `.probundle`, `.proTheme`,
`.proPlaylist`, and representative Legacy Workspace documents load/dump/
validate/edit/round-trip as appropriate, retaining absent metadata, unknown
fields, member names, nonedited members, and media identity. Malformed and
wire-compatible wrong-root files still fail. Both old and native workspace
inputs receive accurate capability diagnostics.

### 2. Add a versioned, read-only native workspace backend

- Introduce one workspace locator/store interface used by media selection,
  strict validation, Looks, playlist rendering, and Planning Center resolution.
  Implement old-directory and native-22 adapters rather than duplicating path
  switches in each feature.
- Use SQLite snapshot/backup semantics for a coherent view, including committed
  WAL content; copying only the main file is insufficient. Validate schema and
  storage markers and report unsupported future versions precisely.
- Decode native Loro snapshots using the actual library, preserving their
  complete imported state and history. The official experimental
  [loro-swift](https://github.com/loro-dev/loro-swift) package supplies Swift
  bindings and a prebuilt XCFramework. First prove it imports beta snapshots
  and works with both release architectures and Swift 6; pin the tested
  revision. Its availability avoids introducing a shipped Node dependency.
- Map native presentation, Theme, playlist, configuration, and client-state
  schemas explicitly. Treat unmapped fields/stream kinds as retained data with
  clear capability limits. Do not deserialize native JSON as protobuf JSON.
- Keep logical document identity/path, presentation UUID, media UUID, and Loro
  container identity separate. Inventory/select by stable native identity;
  names remain potentially duplicated or movable.
- Resolve canonical media and workspace-relative paths from native data.
  Treat a media projection cache as a cache whose freshness must be checked,
  not a newly writable authoritative registry.
- Preserve native per-occurrence media reference UUID separately from
  `asset_id`; the storage audit establishes that these are different identity
  classes, not a direct replacement for the old single media UUID. Map all
  identity and URL variants at import/export boundaries, preserving repeated
  references and intentional shared assets.

**Acceptance:** one native fixture yields matching native UI/API/Legacy Export
inventories, order, text, group and arrangement identity, per-item arrangement,
Planning Center linkage/visibility, Theme selection, Looks/screens, and media
paths. Include scope separation, unavailable streams, unknown kinds/fields,
logical path moves, non-ASCII names, duplicate labels, external media, and a
committed WAL change. Read operations make no native store changes.

### 3. Native mutation and atomic operations

- Build edits as targeted Loro operations on imported existing containers.
  Rebuilding the document from `toJSON()` loses history, unknown containers,
  and identity. Loro's [encoding documentation](https://www.loro.dev/docs/tutorial/encoding)
  distinguishes snapshots, operation updates, and shallow history; preserve
  the native document's chosen history model.
- Prove per-operation affected streams and metadata before implementing
  writes: snapshot, version vector, checksum, length, timestamps, availability,
  document index/path keys, and shared/client state relationships. Do not
  guess shared-version or synchronization bookkeeping.
- Use one native SQLite transaction for multi-document operations with a
  revision check and rollback, replacing the old file-by-file batch scheme
  only for native stores. Preserve the already-proven old scheme for files.
- Cover every existing edit family: names; content/RTF; backgrounds; media;
  slide/actions; group membership/order/color/hotkeys; arrangements; templates;
  playlist structure and visibility; local Planning Center link/unlink; and
  coordinated `edit apply`/media batches.
- Model native group/cue placement as tree operations with stable node IDs,
  parentage, fractional positions, and separate content identities. Prove how
  group move/rename/color/hotkey edits affect node metadata, how duplicate and
  deletion remap references, and how arrangements retain repeated groups.
  Establish native versus v1/v2 protobuf precedence before enabling edits on
  documents containing both representations; never leave a preserved v2 graph
  pointing at deleted v1 objects. Materialize old export arrays only at the
  proven interchange boundary.
- Integrate existing unknown-field and reference-remapping warnings with
  native unknown containers/references. Distinguish supported preservation
  from unsupported semantic duplication.

**Acceptance:** each supported edit survives native reopen, re-export, and
further native editing; only intended streams change. Validate native undo/
subsequent edit behavior, root versus nested identities, group/arrangement/
completion/build references, linked items, atomic success/failure, interruption,
revision conflict, and no-op writes. Validate duplicate/create/remove/move in
the native UI, not just SQLite or JSON equality. Library edits keep the
existing quit-first product policy until safe concurrent behavior is proven.
Include v1-only, v2-only, matching dual representations, conflicting/stale dual
representations, repeated arrangement groups, group/cue tree moves, and element
build-order copy/removal. Compare native UI order and output after re-import,
not just retention of unknown bytes.

### 4. Rendering, authoring, interchange, and design qualification

- Re-export the existing comprehensive renderer fixtures from beta 22 into a
  separate version-qualified reference set. Keep 21.4 references unchanged
  unless a documented current-version contract deliberately supersedes them.
- Compare all existing typography, shapes/effects, layering, scale/insets,
  list indentation, links, images/video thumbnails, media actions, text builds,
  template matching, cross-resolution application, and persisted Look cases.
  Distinguish font/OS changes from document-schema or renderer changes.
- Import all four independently authored bundled Theme documents and their 99
  variations. Verify names/order/counts/content slots/media absence and native
  application behavior; regenerate only from `DesignSystemFixture.swift` if a
  demonstrated change is needed, then run its freshness check.
- Test all export/import choices separately: single document, media bundle,
  multi-Theme archive, presentation playlist with/without media, and Legacy
  Workspace export; check missing-media, basename collisions, UUID rewriting,
  path relocation, archive-local versus workspace media, and new native
  workspace export/container types if offered.

**Acceptance:** documented visual differences have fresh native PNG evidence,
known fonts and OS/build provenance; no tolerance loosening or arbitrary golden
recording. Syphon checks confirm material live-only Looks/layers/build behavior.
The basic pixel-identical rectangle is retained as a smoke test, not a release
qualification for all rendering or templates.

### 5. Documentation, skills, packaging, and release qualification

- Update `README.md`, `Docs/Format/{README,TopLevelFileFormats,PresentationDocuments,ThemeDocuments,PlanningCenterPlaylists,TextBuilds,RenderingBehavior}.md`,
  and `Docs/ProPresenter.md` with an explicit file/native-workspace/version
  support matrix and current limits. Remove the broad claim that current
  native documents live primarily in raw protobuf files. Qualify old layout
  observations as old-version/interchange behavior.
- Update `skills/pro-crud/SKILL.md` and its background-sourcing, design, and
  authoring references to discover the correct workspace/backend and use
  supported inventory/media commands. Keep research and fixture provenance in
  `Internal/` and contributor skills. Keep the official API skill independent
  of this repository; runtime API changes are a separate evidence-based audit.
- Add native fixtures/tests alongside `DocumentModelTests`, archive, strict
  media, validation, template, Planning Center, group/arrangement, and CLI
  acceptance coverage. Check protobuf drift only if definitions change; never
  hand-edit generated `.pb.swift` files.
- Reconcile installed 22 schema descriptors with the vendored and exact
  upstream 21.4 definitions before regeneration. Explicitly test changed
  existing field semantics as well as additions: the schema audit found
  KeyMapping fields 101–106 switching to a nested key type without the 21.4
  recursive parent scope (both versions retain a string name at field 2), and
  `TimedPlayback.Sequence` field 3 changing from a singular presentation to
  repeated presentations. Those changes can remain wire-decodable while
  changing meaning or dropping repeated values in an older generated type.
- Qualify the Loro/SQLite dependency under standard build caches, macOS targets,
  universal packaging, signing/notarization, license attribution, installed
  resource discovery, and manual/installer upgrades. Run SwiftFormat,
  SwiftLint, focused tests, then the existing package/CLI checks. Do not use
  `.serialized` to hide races.
- Ship beta-qualified interchange/read/native-write capabilities in stages;
  each advertised capability must meet its tests. Native workspace support is
  a new substantial workflow and should follow the repository's minor-release
  policy when actually released. This investigation authorizes no publication.

## Remaining evidence gates

The underlying 22 workspace model, export omission of metadata, and old path
breakages are established. Full native mutation bookkeeping, synchronized
state semantics, all-feature native schema mapping, large fixture visual
comparisons, and import choices beyond tested samples still require controlled
native experiments as implementation gates. These are explicit work items,
not reasons to replace the existing protobuf core wholesale or claim that
parsing alone establishes native compatibility.
