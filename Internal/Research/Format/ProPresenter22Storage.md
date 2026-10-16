# ProPresenter 22 beta: workspace storage investigation

Investigated on 2026-10-14 against the installed macOS ProPresenter 22 beta,
build 369098875. This is experimental evidence for implementation planning,
not a public format specification or a claim about the eventual release.

## Findings

The workspace upgrade changes the authoritative document store. Presentations,
Themes, playlists, and configuration now live as **Loro CRDT snapshots inside
SQLite**, rather than editable protobuf files in the workspace tree. The old
workspace remains a separate legacy copy. Adding support for the new root path
alone cannot make the existing workspace implementation compatible.

The migrated workspace contained all **336 original presentations**. Native
Legacy Workspace export reproduced exactly the same 336 relative `.pro` paths.
The migration manifest's **334 documents** means documents whose media identities
were changed; it does not mean two presentations failed to migrate.

Every physical file under the old workspace's `Media/` was retained without
changes: **2,325 files, 15,935,940,406 bytes**, with matching SHA-256 hashes at
the corresponding new paths. Twelve media files were added: eleven JSON
animation assets and `Background.jpg`.

## Scope and reproducibility

The investigated old workspace was `UserWorkspaces/LSSS`; its replacement was
`Workspaces/49c14fcc-d6b9-4c12-839e-a76c2d536358` below the standard local
RenewedVision ProPresenter application-support directory. The old workspace was
read only throughout this investigation. The native app was used separately to
export documents and import a disposable probe.

Initial observations, before the probe import, found 384 native streams. A
later SQLite backup found 385 streams because the probe added one presentation.
The counts below distinguish that change. No live SQLite or RocksDB files were
modified by the forensic scripts. SQLite's backup API with a read-only source
captured a consistent view including the active WAL.

Private copies and diagnostic output are kept in the ignored
`.build/pro22-investigation/storage/` directory. They include a SQLite backup,
schema, stream index, native snapshots, decoded JSON, media hash comparison,
and missing-media analysis. Decoded workspace settings can contain private
configuration; these copies are not fixtures and must not be published.

The official `loro-crdt` 1.16.4 JavaScript/WASM package successfully imported all
384 initial snapshots, then all 385 later snapshots, with zero decoding failures.
The downloaded package tarball was verified against the npm registry's SHA-512
integrity value. `LoroDoc.import(bytes)` and `toJSON()` are sufficient for
inspection; see [the official Loro API](https://loro.dev/docs/api/js) and
[snapshot encoding documentation](https://loro.dev/docs/tutorial/encoding).
This establishes read feasibility, not safe support for native writes.

## Old and new storage

| Category | Legacy workspace | Migrated native workspace |
| --- | --- | --- |
| Presentations | 336 `.pro` files in `Libraries/` | 336 `Presentation` streams; no physical `Libraries/` folder |
| Library catalog | `Libraries/LibraryData` | One `LibraryData` stream |
| Playlists | Four files in `Playlists/` | Four shared streams plus three separate client streams |
| Configuration | 14 active files in `Configuration/` | 14 shared streams plus five separate client streams |
| Themes | 18 canonical `Theme` documents | 21 `Theme` streams: 18 migrated, three supplied by beta |
| Media | 2,325 files | Same 2,325 files plus 12 supplied assets |
| Media registry | Outside the legacy document model | Workspace-local `MediaStore/`, RocksDB 8.10.0 |
| Generated thumbnails | Separate runtime state | Workspace-local `Thumbnails/` |

The new workspace retains eight duplicate-named configuration files such as
`Workspace 2` and some unused Theme-side files. These are exact copies of
pre-existing leftovers, not the active configuration renamed during upgrade.
Their presence must not lead discovery code to treat the new workspace as a
partially populated legacy workspace.

The three added Theme streams are `Neon/Theme`, `Color Pop!/Theme`, and
`Bright Side - Animate/Theme`.

### Registry

`Workspaces/registry-v1.sqlite3` replaces name-derived workspace discovery.
Its `workspaces` table has `local_uuid`, unique `root_path`, `display_name`,
optional `cloud_uuid`, `schema_version`, and `availability`. A separate `meta`
table and cloud-organization association table also exist. Only the workspace
layout/schema was inspected; no account databases or credentials were queried.

`Workspaces/legacy-handoff-v1` identifies the replacement workspace UUID and
`registry-v1.migrated` contains `1` plus a newline. The per-workspace
`DocumentStore/workspace-id` contains its UUID and
`DocumentStore/workspace-storage-v1` contains `sqlite-v1` plus a newline.

### SQLite envelope

`DocumentStore/workspace-v1.sqlite3` has `user_version = 9` and
`application_id = 1381390163`. Its main table is `workspace_streams`:

| Column | Observed role |
| --- | --- |
| `document_id` | 16-byte identity; part of primary key |
| `scope` | 0 or 1; other part of primary key; shared content and client state are separate streams |
| `location_type` | Intrinsic versus collection location |
| `kind` | Document kind string |
| `core_path`, `core_path_key` | Logical placement, not a filesystem path |
| `availability` | Present snapshot versus unavailable collection document |
| `snapshot` | Native Loro binary snapshot, beginning with `loro` |
| `version_vector` | Loro version vector |
| `sha256`, `byte_count` | Snapshot integrity and size |
| `updated_at_ms` | Update timestamp |
| `last_shared_version_vector`, `last_shared_version_vector_absence_reason` | Shared-state bookkeeping |

The table enforces document identity length, valid enum values, snapshot/hash/
version-vector presence, and byte count. Presentation `core_path` values look
like `Songs/Example` without `Libraries/` or `.pro`; Theme values look like
`Name/Theme`. Existing URLs inside content may still carry legacy logical
`Libraries/...pro` paths and old absolute paths. Resolving these requires the
catalog and logical collection location, not a physical file-existence check.

Other tables are `workspace_metadata`, `workspace_operation_receipts`,
`workspace_cutover_acknowledgements`, `workspace_cutover_recovery_artifacts`,
and `workspace_migration_quarantine`. The last three were empty. Metadata
included `catalog_published = 1` and `presentation_placement_cutover = 1`.
Operation receipts include the native `import-legacy-document-batch` operation.
These tables, shared version vectors, and integrity constraints make a blind
SQLite blob replacement an incomplete native write strategy.

### Native kinds and scopes

| Kind | Shared streams | Client streams |
| --- | ---: | ---: |
| `Presentation` | 336 initially; 337 after probe import | 0 |
| `Theme` | 21 | 0 |
| `Calendar`, `Ccli`, `ClearGroups`, `Groups`, `KeyMappings`, `Labels`, `LibraryData`, `Macros`, `PlaylistTemplates`, `Props`, `Stage` | One each | 0 |
| `CommunicationDevices`, `Messages`, `PlaylistAudio`, `PlaylistLibrary`, `PlaylistMedia`, `TestPatterns`, `Timers`, `Workspace` | One each | One each |
| Total | 376 initially; 377 after probe import | 8 |

Client state holds local screen/audio configuration, runtime message/timer
state, and playlist expansion state. Shared Workspace content holds Looks,
masks, and other shared document data. Reconstructing the previous aggregate
protobuf Workspace therefore needs both streams.

### Native document representation

The decoded state has a `root` map. Much of the slide geometry/action data is
recognizable, but the representation is not protobuf JSON:

- Presentation `cues` is a UUID-keyed map. Master/group order lives in a Loro
  tree, `cue_group_placements`, with group/cue nodes, parent identities,
  fractional indexes, and node metadata. Map iteration is not slide order.
- Arrangements use `group_identifiers_v2`. The selected arrangement is a string
  UUID. Existing arrangement repetitions are preserved.
- Playlists use tree nodes with `meta.Kind`, local node IDs, parent relations,
  and fractional indexes. Expansion state is stored in the client stream.
- Oneofs become tagged unions such as `ActionTypeData.__tag`, `Slide.__tag`,
  `FillType.__tag`, and `TypeProperties.__tag`.
- UUIDs are strings rather than nested protobuf UUID messages. Optional values
  are explicit `null` in many places; field casing is mixed.
- Binary RTF remains binary inside Loro. Plain `JSON.stringify` of a
  `Uint8Array` creates numeric-key objects and is a diagnostic view, not an
  interchange encoding suitable for rebuilding documents.
- `value_array_migration_version` appears in presentations, Themes, Stage,
  CCLI, and Workspace documents.

A native reader needs explicit adapters for ordering, unions, binary values,
optional presence, shared/client overlays, and path resolution. A native
writer must retain the CRDT containers and unrecognized state rather than
rebuilding a Loro document from its diagnostic JSON projection.

## Media identity migration

The persisted `DocumentStore/media-identity-migrations/<id>/manifest.json` has
version 4 and phase `Activated`. Its plan contains 372 assets and 892 media
occurrences. It changed 334 documents:

| Kind | Documents affected |
| --- | ---: |
| Presentation | 325 |
| Theme | 6 |
| Workspace | 1 |
| PlaylistMedia | 1 |
| Macros | 1 |

All 892 old occurrence reference UUIDs changed; all 372 asset UUIDs were newly
assigned. Old occurrences had no `asset_id`. The media object now has a
per-occurrence `uuid`, a separate `asset_id`, and `identity_schema_version = 1`.
Treating the reference UUID as the asset identity is no longer valid.

The manifest records baseline/migrated hashes, version vectors, occurrence
paths, source and descriptor fingerprints, and patch hashes. Its named
`.procloud` snapshots are migration/intermediate paths; the current authoritative
documents are SQLite streams. The retained `.loropatch` files contain Loro
updates, not protobuf documents.

This was checked for all 334 retained patches using
`decodeImportBlobMeta(bytes, true)`: every blob reports mode `update`, with no
checksum errors. Importing each patch into its corresponding current SQLite
snapshot and exporting that in-memory document again leaves the serialized
snapshot hash unchanged in all 334 cases. They are already-applied migration
history, not standalone authoritative documents or newer edits waiting to be
loaded. Some imported alone into an empty Loro document produce no root data
because their dependencies are absent. No patch was written back to disk or
applied to the live store.

`media-projection-cache-v1.json` has version 6. It projects occurrence identity,
asset identity, source, transformation, fingerprints, and issues. File sources
have a typed URL with a local root/path and optional ProContent identifier;
live-video sources use a separate variant. Transformations include natural
size, insets, effects, rotation, flips, alpha interpretation, and thumbnail
position. Initial cache data was stale relative to the applied migration,
showing old identities; later data showed current identities. This is a cache,
not a safe canonical editing surface.

The RocksDB options identify version 8.10.0. Its authoritative role for media
identity/materialization needs separate verification; the old documentation's
blanket description of runtime databases as derived state cannot be carried
forward to version 22 without qualification.

## The original warning about six media files

The screenshot reports only a count, not filenames. No durable upgrade report
directly associating that alert with filenames was found. The strongest match
is exactly six source-less file-media occurrences, each already source-less in
the old `.pro` file:

| Planning Center presentation | Cue label in old document | Cue UUID |
| --- | --- | --- |
| His Mercy is More | rolling low clouds_brown geo | `2ADB4BA0-D84B-4735-9AA9-9D3D1D7F6007` |
| This I Believe | anton-repponen-sfgH9dXcMRw-unsplash | `5EF2CAF7-2F6E-488A-90DA-4A60FE78CBC8` |
| Living Hope | jake-blucker-OJX7gIU3E6U-unsplash | `EC534FDA-ECC0-46A1-BCD8-372D1C5135BE` |
| Is He Worthy | aleks-dahlberg-b7DzEp2lsRI-unsplash | `951F976A-BDBA-469C-AE7E-185E08DB4FE4` |
| O Praise the Name | Final Song Slide | `C0CA7C9F-E34B-4FFB-BB4B-EBCB580E4DC1` |
| Rock of Ages | ayush-sharma-1197233-unsplash | `899D98FD-FC31-49DE-8C43-06A0C14B105A` |

Each old protobuf has an enabled image media action with its UUID/drawing
settings but no file URL or usable source. The corresponding native projection
has `source = null`. The old Media folder has no filenames matching the five
recognizable cue-derived asset labels. The sixth cue label does not identify
an original filename. Repeated native helper logs count six unsupported media
ensures. The later Legacy Workspace export reports exactly six
`invalid_projection` entries matching these occurrences.

**Conclusion:** these are strong candidates for the six upgrade warnings, and
their missing sources predate the upgrade. Direct attribution to the first-run
alert remains unproven. The exhaustive physical-file hash comparison rules out
the migration deleting or changing files that were present in old `Media/`.

Filtered unified logs show migration approval at 18:07:49 and the helper
reporting successful workspace migration at 18:08:15. Other log errors concern
unavailable ProContent materialization. Their message text was inspected only;
no credentials, tokens, private account databases, or undocumented service
endpoints were inspected.

## Separate Legacy Workspace export warning

Native Legacy Workspace export completed successfully and reported **71 media
items unavailable**. This is separate from the original six-item upgrade alert.
The export's `.procore/legacy-export-manifest.json` provides a useful diagnostic
contract:

- Version 1, `target_contract = current_pro7`, policy `preserve_and_report`.
- 376 exported documents, every one marked `reopened = true`: 336 original
  presentations, 21 Themes, and 19 intrinsic shared documents.
- 313 media files listed in the manifest and 726 copied media-reference
  occurrences. Assets include Theme-local files, not only `Media/` files.
- 196 compatibility warnings: 190 unavailable-source occurrences and six
  invalid projections. The user-facing list consolidates them to 65
  `missing_source` items and six `invalid_projection` items.
- All 65 missing-source locators were absent from disk; their equivalent old
  workspace paths were also absent. Of these, 64 filenames had no match
  anywhere in the old workspace. One `SA Art.png` exists under
  `Themes/Standalone/Assets`, while the broken locator points to `Media/Assets`.

This export produces the legacy folder shape consumed by the current tool and
is a practical compatibility bridge. It is a generated snapshot: future native
edits do not update it. Unavailable references remain in documents and are
reported rather than silently deleted. Import/export bridge workflows must
surface the native export manifest and media warnings, and must not promise
lossless support for all version-22-only features.

## Implications for the implementation plan

1. Detect storage generation explicitly; discover registered UUID-rooted native
   workspaces and distinguish legacy copies, native stores, and legacy exports.
2. Initially reject unsupported native mutations with an actionable Legacy
   Workspace export path. Do not silently operate on the old workspace or on
   duplicate leftover raw files.
3. Preserve existing protobuf/archive support as an independent backend. Add
   native read support through a Loro/SQLite adapter with version/schema gates,
   WAL-consistent reads, logical catalog placement, and separate client state.
4. Adapt semantic inspection, ordering, arrangements, playlist links, Looks,
   media resolution, and rendering through a shared semantic model. Preserve
   native-only state outside any protobuf projection.
5. Design native writes only after proving transactions, CRDT identity/history,
   client/shared overlays, operation receipts, integrity bookkeeping, and
   media-service coordination. An isolated SQLite transaction alone is not
   evidence of compatibility with the running app's actors or undo state.
6. Replace asset-identity assumptions with distinct occurrence/reference and
   asset identities. Test reusing one asset, replacing one occurrence,
   relocating an asset, batch replacements, media action/fill references, and
   legacy export/import preservation.
7. Maintain migration fixtures covering all 19 intrinsic kinds, both scopes,
   collection trees, binary RTF, unknown state, missing sources, unavailable
   documents, stale caches, and beta schema changes. Use independently authored
   disposable content for checked-in fixtures instead of this private library.
8. Test the supported compatibility bridge and native backend separately.
   Require native reopen/trigger/export verification for future native writers;
   successful Loro decoding and protobuf projection cannot establish rendering
   or write correctness by themselves.
