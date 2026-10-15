# Top-Level ProPresenter File Formats

ProPresenter 21 stores editable library documents as raw protobuf files.
ProPresenter 22 beta build 369098875 uses a native SQLite/Loro workspace store;
its Presentation, Presentation Bundle, Playlist, Theme, and Legacy Workspace
exports use protobuf interchange documents. Support for an interchange document
does not imply support for the native workspace store.

Run `pro-crud workspace inspect /exact/workspace/root` to report storage
evidence, supported operations, and Legacy Workspace export manifest counts.
Discovery does not consult the running app or silently select a preserved old
workspace. An explicitly selected legacy workspace remains usable.

Native workspaces contain `DocumentStore/workspace-v1.sqlite3` and storage/ID
markers. `workspace inventory ROOT` captures a consistent read-only SQLite
snapshot including committed WAL content, validates schema 9 and stream
identities/checksums, and reports shared/client streams and unavailable content.
`workspace dump ROOT [--stream UUID] [--scope shared|client]` decodes native
snapshots with the pinned official Loro Swift binding. Its typed diagnostic
values preserve binary data as base64. They are not protobuf JSON and cannot
be used to rebuild native documents. Retained migration patches are not replayed.
`workspace discover --registry /exact/path/registry-v1.sqlite3` reports registry
metadata without selecting an active workspace or consulting account data.

Inspection is bounded to 512 MiB. Active WAL databases use an in-memory SQLite
backup. A database with no journal/sidecars uses a stable main-file image,
deserialized into private memory without opening a writable source or
initializing sidecars. File identity/size/timestamps and continued absence of
journals are checked around that capture; a changing source retries up to three
times. Inspection does not migrate, repair, or write the source database. An
incomplete WAL/shared-memory pair requires a coherent SQLite backup or native
open before inspection.
Other database schemas and storage markers are rejected explicitly.
`workspace inventory ROOT --projections` checks native Presentation, Theme and
playlist protobuf views. Playlist views preserve the shared tree and matching
client node expansion state separately. Connected-playlist local overlays remain
unsupported. Export one standard playlist with media-free Presentation
dependencies using:

```sh
pro-crud workspace export-playlist /exact/native/root --playlist PLAYLIST_UUID \
  --output /separate/path/Service.proPlaylist --target-version 22
```

Select the playlist tree node UUID from `workspace contents`, rather than the
PlaylistLibrary stream UUID. Both profiles (21 and 22) preserve ordered repeated
links, hidden items, headers and arrangements. Each shared Presentation is
embedded once under a UUID directory with its original filename; both URL
representations point into the archive. ProPresenter may add its normal name
collision suffix on import into a populated library. Connected/provider items,
media, header actions and other action dependencies currently return structured
compatibility errors before output publication. Source and output paths must
remain separate.

General native document edits and strict media validation require their native
adapters. Render a supported shared Presentation directly with
`render ROOT --native-stream UUID --output SEPARATE_PATH`. The native reader
resolves order and builds from one consistent snapshot. Native schema-1 local
images/video thumbnails use exact selected-source locators; unsupported native
media/features and missing assets fail before replacing output. See
[RenderingBehavior.md](RenderingBehavior.md) for the static preview limits. The qualified local metadata
operation below and media-free native Look previews have separate support. Use **File → Export → Legacy
Workspace** or export an individual bundle in ProPresenter, then select the
exported documents. A Legacy Workspace export is a point-in-time snapshot;
later native edits do not update it. The preserved `UserWorkspaces` copy is a
separate branch of content and writing there does not update the native store.

For a registered local schema-9 workspace, set an existing Presentation's CCLI
song title with:

```sh
pro-crud workspace set-copyright-title /exact/native/root \
  --stream PRESENTATION_STREAM_UUID \
  --registry /exact/path/registry-v1.sqlite3 \
  --title 'Song title'
```

Select the shared stream UUID from `workspace inventory`. ProPresenter and its
workspace helpers must be stopped; the command reports active writers when
necessary. It verifies the exact local registration, retains native Loro history,
and commits the snapshot, version vector, integrity metadata and operation
receipt in one SQLite transaction. A concurrent revision change fails without
publishing the edit. A matching title is a no-op. JSON output includes the
selected document identity, `changed` and commit receipts. An empty title clears
the CCLI song title. This operation does not rename the Presentation or change
its library location. Set native rich-text Slide Notes by exact Presentation slide-action UUID with:

```sh
pro-crud workspace set-slide-notes /exact/native/root \
  --stream PRESENTATION_STREAM_UUID --action SLIDE_ACTION_UUID \
  --registry /exact/path/registry-v1.sqlite3 --text 'Slide notes'
```

Select the action UUID from a supported `workspace export` or native diagnostic
`workspace dump`. This edits the selected slide's notes, separate from the
Presentation's plain metadata `notes` field. Use `--rtf FILE` instead of `--text`
for complete rich-text replacement. Plain text retains the first existing
character's formatting; new notes use Helvetica Neue at 24 points (system font
fallback) and white text. Matching plain text preserves formatting and makes no
change; empty text clears the notes. The same stopped-writer, registration,
history, transaction and conflict rules apply.

Move an existing native cue after another cue in the same group with:

```sh
pro-crud workspace move-cue /exact/native/root \
  --stream PRESENTATION_STREAM_UUID --cue CUE_UUID --after ANCHOR_CUE_UUID \
  --registry /exact/path/registry-v1.sqlite3
```

This moves the existing placement-tree node and retains cue content, identities,
group metadata and arrangements. Selecting itself or its current predecessor
makes no change. For ownership transfers use `transfer-cue` below. The same offline/local
transaction rules apply. Structural edits reject parallel legacy arrays that
would become stale.

Transfer an existing cue into a destination group with:

```sh
pro-crud workspace transfer-cue /exact/native/root \
  --stream PRESENTATION_STREAM_UUID --cue CUE_UUID --group GROUP_UUID \
  --after DESTINATION_CUE_UUID --registry /exact/path/registry-v1.sqlite3
```

Omit `--after` to append. The cue and placement identities and complete cue
content are retained. Following native 22 behavior, moving the last cue out of
a group removes that emptied group and every arrangement occurrence referencing
it. Other group occurrences retain their order and identities. Unmapped native
content blocks this deletion before publication. Matching placements make no
change; unresolved destinations/anchors fail. The same local transaction rules apply.

Rename an existing group with `workspace rename-cue-group ROOT --stream UUID
--group GROUP_UUID --name TEXT --registry PATH`. This preserves group identity,
application-group link, color, hotkey, membership and arrangements. Matching
names make no change; names must be nonempty.

Set an existing arrangement's sequence with `workspace set-arrangement-groups
ROOT --stream UUID --arrangement ARRANGEMENT_UUID --group GROUP_UUID
--group GROUP_UUID --registry PATH`. Supply `--group` once for each ordered
occurrence, including repeats, or use `--clear` for an empty arrangement.
Existing occurrence identities are reused during moves; the arrangement's name,
identity and selected state are preserved. These commands use the same local,
stopped-writer transaction rules. Other native edits still use native export/import.

Apply supported edits across existing native Presentations atomically with:

```sh
pro-crud workspace apply /exact/native/root --file native-edits.json \
  --registry /exact/path/registry-v1.sqlite3
```

For example, `native-edits.json` can contain:

```json
{
  "version": 1,
  "operations": [
    {"stream": "PRESENTATION_UUID", "op": "set-copyright-title", "title": "Song title"},
    {"stream": "PRESENTATION_UUID", "op": "rename-cue-group", "group": "GROUP_UUID", "name": "Verse"}
  ]
}
```

Use actual UUIDs from workspace inspection. Manifest operations run in order
within each Presentation and share one Loro commit; all changed Presentations
and receipts publish in one transaction. Any invalid operation prevents the
entire batch from publishing, and conflicts roll back every affected stream.
An entirely matching batch makes no change. The manifest version is independent
of the application version. The same stopped-writer/local-registration rules apply.

| `op` | Additional fields |
| --- | --- |
| `set-copyright-title` | `title` string; empty clears |
| `set-notes` | `text` string for plain Presentation Operator Notes |
| `set-slide-notes` | `action` UUID and exactly one of `text` or `rtfFile`; RTF paths are relative to the manifest directory |
| `set-text` | `action` and `element` UUIDs and exactly one of `text` or `rtfFile`; replaces static slide text, rejects delivery/element builds |
| `move-cue` | `cue` and `after` UUIDs in the same group |
| `transfer-cue` | `cue` and destination `group` UUIDs; optional `after` UUID, otherwise append |
| `rename-cue-group` | `group` UUID and nonempty `name` |
| `set-arrangement-groups` | `arrangement` UUID and ordered `groups` UUID array, including repeats or an empty array |
| `rename-arrangement` | `arrangement` UUID and nonempty `name`; retains identity, sequence and selection |
| `select-arrangement` | `arrangement` UUID, or explicit JSON `null` to select Master; omitting the field is an error |

Every operation requires `stream` and `op`. Unknown keys, operations and manifest
versions fail. Native editing preserves the source storage generation; target
conversion options are unavailable on this command.

Valid 22 interchange payloads can omit `application_info`. Loading and editing
preserve its absence. Root recognition instead checks presentation identities,
cues and groups; playlist type and root identity; or Theme template structure.
A metadata-free Theme needs template slides as root evidence. Missing metadata
does not identify the originating application version.

## Output Compatibility Profiles

`create presentation`, `create theme`, `create playlist`, and `bundle` accept
`--target-version 21|22`; creation and export default to 22. Both profiles use
protobuf interchange containers. The 21 constructor retains the existing
legacy construction encoding, including its version-7 application metadata;
the 22 constructor declares the requested 22 target. Metadata is not itself
proof of native application acceptance. Existing-source edits preserve their
stored metadata and representation, including absent metadata. `edit --output`
and edit batches do not request conversion: export the edited document with
`bundle --target-version` for explicit target checking.

Use `compatibility INPUT --target-version 21|22` to obtain a structured report.
The core protobuf-root analyzer also handles configuration/runtime roots. It
recognizes the shared UUID/name KeyMapping wire fields and the single embedded
Timeline Presentation layout. Multiple Timeline Presentations or per-item
Presentation UUIDs fail a 21-target check; legacy mapping parent scope fails a
22-target check. These checks preserve source bytes and provide no flattening
fallback. Wire compatibility does not establish native execution or rendering.
It reports the declared source metadata separately from the requested profile,
feature/component paths, severity, and available conversion. Creation and
bundling accept `--json` to include the selected profile in their results.
Bundling checks every embedded presentation and Theme document before publishing
output, and failed compatibility checks preserve source and existing output.

Unknown wire fields and enum values are preserved and reported for 22 output.
They block a 21-target export because their behavior and dependencies are not
qualified. Preserved bytes are not a claim of executable support. There is no
lossy conversion option: no behavior-changing fallback has been qualified.
Known v2 ordering/build/playlist graphs and native media identity, provider,
and HLS representations require adapters; packaging, editing sessions, and
rendering reject them instead of mutating stale legacy arrays. Diagnostic dumps
and validation expose these capability limits. Static render checks respect
selected slides while also checking global ordering dependencies.

The fixture CI matrix exercises independent 21 and 22 exports and native
snapshot reading. Full native delivery, downgrade, new-feature rendering,
Cloud writing, and newer beta/build qualification require separate native
acceptance. These profiles do not imply full-version feature parity.

User-facing import/export containers are ZIP archives with protobuf documents
and optional media assets.

Archive extensions identify the export workflow. The extension is part of the user-facing format contract; the payload files inside still need to be identified and decoded by entry name and protobuf root type.

## Export Containers

| Extension | Container | Typical entries | Primary payloads | Purpose |
| --- | --- | --- | --- | --- |
| `.probundle` | ZIP | One or more `.pro` files; optional shared media files | `rv.data.Presentation` in each `.pro` file | Presentation bundle export/import. Native 22 can package several selected presentations in one bundle. |
| `.proPlaylist` | ZIP | One root `data` file plus embedded `.pro` files | `rv.data.PlaylistDocument` in `data`; `rv.data.Presentation` in each `.pro` | Playlist export/import. The `data` file preserves playlist tree structure, item ordering, per-item arrangement UUIDs, and references to embedded presentation documents. |
| `.proTheme` | ZIP | One directory per exported theme; each directory contains a `Theme` file and may contain assets | `rv.data.Template.Document` in each `Theme` file | Theme export/import. Each theme document contains reusable template slides. |

ProPresenter 21.4 exports use stored entries and ZIP64 size fields even for small files. A presentation-only export and the `.pro` entry in a presentation bundle are byte-identical to the selected live-library document. A media bundle retains the document's absolute media URLs and `ROOT_SHOW` local paths while storing each media file under its absolute source path in the ZIP. This is ProPresenter's native export shape, not a requirement for compatible third-party archives. Its writer also records the central-directory size as 98 bytes too large by including the ZIP64 end record, ZIP64 locator, and classic end record in that size. Readers can tolerate that exact defect after independently validating the entry count, record boundaries, and trailer; other directory-size mismatches remain corruption errors.

Archive parsing and extraction are in-process and bounded. Before writing any output, the reader limits entry count, central-directory work, individual and aggregate expanded sizes, compression ratios, path lengths, and processing time. It rejects encrypted entries, unsupported methods, duplicate normalized destinations, traversal, symbolic links, and special files. Extraction uses a fresh sibling staging directory, resolved containment checks, and restrictive `0700` directory/`0600` regular-file permissions before atomically moving the completed tree into place.

New archives preserve the useful ProPresenter conventions—stored data, UTF-8 names, and ZIP64 sizes—while using relative member names and standards-correct ZIP64 extras and central-directory sizes. The codec dispatch currently accepts stored and raw-DEFLATE entries; an unknown future compression method produces a specific unsupported-method error rather than being mistaken for a damaged protobuf payload.

For `.proTheme`, the internal directory name is the imported theme name; the
archive filename is not. A portable single-theme archive therefore uses
`<theme-name>/Theme`, not a root `Theme` entry. Controlled ProPresenter 21.4
imports of a root `Theme` entry targeted the workspace path `Themes/Theme`,
collided independently of the archive filename, and did not appear as a normal
named theme in the API inventory.

Native 22 Presentation Bundle export can contain several independent `.pro`
payloads with shared media. `render` loads every presentation, uses separate
output subdirectories for a collection, and retains the shared asset context.
Single-presentation output naming is unchanged. Single-document inspection and
editing APIs reject an ambiguous bundle; use `expand`, then select the exact
`.pro` file to inspect or edit. `bundle DIRECTORY` packages every root `.pro`
after validating all of them; an invalid later document leaves an existing
output unchanged. Native media identity and configuration-manifest repackaging
still require their qualified adapters; use ProPresenter export for those cases.

## Legacy Workspace Layout

A ProPresenter user workspace is organized around these top-level folders:

```text
Configuration/
Downloads/
Libraries/
Media/
Playlists/
Presets/
Themes/
```

For legacy storage, editable documents live in `Libraries/`, `Playlists/`,
`Themes/`, and `Configuration/`; `Media/` stores referenced assets. Native 22
database and media stores must not be treated as disposable derived state.
An expanded single-document export is distinct from a whole workspace: select
a raw document within a legacy workspace for dump/edit/render/bundle commands.
Strict media validation reports incomplete context if `Playlists/Media` is
missing; absence of that registry is not successful validation.

## Raw Document Files

| File shape | Typical location | Root protobuf message | Purpose |
| --- | --- | --- | --- |
| `*.pro` | `Libraries/**/*.pro`; root entries inside `.probundle` and `.proPlaylist` exports | `rv.data.Presentation` from `presentation.proto` | Presentation documents: metadata, arrangements, cue groups, cues, slide actions, media actions, CCLI/music metadata, and timeline data. |
| `Playlists/Library` | `Playlists/Library` | `rv.data.PlaylistDocument` from `propresenter.proto` | Presentation playlist tree. Standard playlist items reference `.pro` documents with `rv.data.URL` paths and can select an arrangement UUID. Planning Center playlists add a plan link and wrap the same local item data inside connected items; see [PlanningCenterPlaylists.md](PlanningCenterPlaylists.md). |
| `Playlists/Media` | `Playlists/Media` | `rv.data.PlaylistDocument` | Media playlist tree. Items can inline `rv.data.Cue` values with media actions. |
| `Playlists/Audio` | `Playlists/Audio` | `rv.data.PlaylistDocument` | Audio playlist tree. |
| `Playlists/PlaylistTemplates` | `Playlists/PlaylistTemplates` | `rv.data.PlaylistTemplate` from `playlistTemplate.proto` | Playlist template store. |
| `Themes/<theme-name>/Theme` | `Themes/**/Theme`; theme folders inside `.proTheme` exports | `rv.data.Template.Document` from `template.proto` | Theme/template slide document. Each slide contains a `base_slide`, a template name, and optional actions. See [ThemeDocuments.md](ThemeDocuments.md). |
| `Configuration/Groups` | `Configuration/Groups` | `rv.data.ProGroupsDocument` from `groups.proto` | Cue group definitions, colors, and hotkeys. |
| `Configuration/Labels` | `Configuration/Labels` | `rv.data.ProLabelsDocument` from `labels.proto` | Label definitions used by cues and actions. |
| `Configuration/Timers` | `Configuration/Timers` | `rv.data.TimersDocument` from `timers.proto` | Timer and clock definitions. |
| `Configuration/Props` | `Configuration/Props` | `rv.data.PropDocument` from `propDocument.proto` | Props and overlays. |
| `Configuration/Workspace` | `Configuration/Workspace` | `rv.data.ProPresenterWorkspace` from `proworkspace.proto` | Workspace-level configuration. |
| `Configuration/Messages` | `Configuration/Messages` | `rv.data.MessageDocument` from `messages.proto` | Message templates and content. |
| `Configuration/Macros` | `Configuration/Macros` | `rv.data.MacrosDocument` from `macros.proto` | Macro action bundles. |
| `Configuration/ClearGroups` | `Configuration/ClearGroups` | `rv.data.ClearGroupsDocument` from `clearGroups.proto` | Clear target/group definitions. |
| `Configuration/KeyMappings` | `Configuration/KeyMappings` | `rv.data.KeyMappingDocument` from `keymapping.proto` | Keyboard mappings. |
| `Configuration/Calendar` | `Configuration/Calendar` | `rv.data.Calendar` from `calendar.proto` | Scheduled playlist and macro actions. |
| `Configuration/Stage` | `Configuration/Stage` | `rv.data.Stage.Document` from `stage.proto` | Stage display layouts. |
| `Configuration/TestPatterns` | `Configuration/TestPatterns` | `rv.data.TestPattern` from `testPattern.proto` | Test pattern configuration. |
| `Configuration/CCLI` | `Configuration/CCLI` | `rv.data.CCLIDocument` from `ccli.proto` | CCLI display settings and template slide. |

### Playlist Template Store

The `Playlists/PlaylistTemplates` raw file contains an
`rv.data.PlaylistTemplate` store. Each saved template has a name and ordered
`PlaylistItem` values, so it can preserve the headers, placeholders, and
recurring presentations described in the [official Playlist Templates
workflow](https://support.renewedvision.com/hc/en-us/articles/40377194830995-Creating-and-Using-Playlist-Templates-in-ProPresenter).

The protobuf is vendored and losslessly available to code that handles raw
messages, but `DocumentKind`, `DocumentLoader`, archive editing, and the CLI do
not yet treat this store as a first-class document. Do not misidentify it as a
regular `PlaylistDocument` or overwrite it with a playlist.

### Presentation And Application Groups

A presentation cue group embeds a complete `rv.data.Group` alongside its
ordered cue UUID references. That local group can carry
`application_group_identifier` and `application_group_name` values associated
with a workspace definition in `Configuration/Groups`. Editing the
presentation does not edit that workspace document.

The semantic presentation dump exposes each local group's UUID, canonical
`/cue_groups[uuid="..."]` path, name, color, hotkey, application-group UUID and
name, and its ordered cue paths. Cue names and group names need not be unique,
so those UUID paths are the safe within-document editing identifiers. UUID
identity remains scoped to the containing presentation and can recur in other
documents.

The cue-group editor treats the application-group fields as a link that must
not remain stale after local customization. Changing a linked group's name, or
setting or clearing its color or hotkey, removes both application-group fields.
A deep duplicate preserves them when its name is unchanged and removes them
when a different name is requested.

`edit set-cue-group-hotkey --path GROUP_PATH` accepts `--code VALUE` with an
optional `--control-identifier ID`, or `--clear`. Key names are
case-insensitive and accept forms such as `ansiV`, `ansi-v`, `ansi_v`,
`KEY_CODE_ANSI_V`, and bare `V`. A numeric raw value such as `22` is also
accepted and unknown future enum values are preserved. Use `ansi-1` for the
digit key because bare `1` means raw enum value 1. Clearing writes a present
empty `rv.data.HotKey` message instead of removing field presence. Exactly one
of `--code` or `--clear` is required, and `--control-identifier` is valid only
with `--code`.

These are local file-editing policies; the exact way the ProPresenter UI
creates, refreshes, or detaches linked groups is not specified by these
policies.

Most files above are raw protobuf documents with no wrapping header. Some workspace files are JSON, TOML, databases, or other application state; tools should identify those by known path or content instead of assuming every file under `Configuration/` is protobuf.

## Path Semantics

ProPresenter protobuf documents use `rv.data.URL` to carry absolute file URLs and portable relative paths.

Common relative roots:

| Root | Meaning |
| --- | --- |
| `ROOT_SHOW` | Path is relative to the current user workspace, such as `Libraries/...` or `Media/...`. |
| `ROOT_CURRENT_RESOURCE` | Path is relative to the containing resource folder, such as a theme-local asset referenced by `Themes/<theme-name>/Theme`. |

Archive readers should resolve embedded references against extracted archive contents first, then fall back to workspace-relative paths during import. Writers should prefer relative URLs for newly created portable documents while preserving absolute URL fields during lossless round-trips.

ProPresenter 21.4 accepts root and nested relative media entries referenced by `URL.relative_path`. During import it copies those files into `Media/Assets`, rewrites each URL to an absolute file URL plus a `ROOT_SHOW` local path, sets the URL platform to macOS, and retains the media UUID. Archive directories do not prevent basename collisions at that destination: `a/shared.png` and `b/shared.png` both target `Media/Assets/shared.png`. The **New Version** import choice uses `shared-1.png` for the second file and updates the second URL.

## Adjacent Formats

The broader Renewed Vision data ecosystem includes files outside the presentation/theme/playlist protobuf family:

| File shape | Format | Notes |
| --- | --- | --- |
| `*.rvbible` | ZIP | Bible packages commonly contain metadata XML and scripture XML files. |
| `*.toml` | TOML text | Application or media-manager configuration can be stored as TOML. |
| `*.json` | JSON | Application-level settings and service data can be stored as JSON. |
| Runtime database folders | LevelDB-style files plus generated assets | Derived application state. Not a supported document-editing interface. |

## Reader And Writer Notes

- Treat `.pro`, `Theme`, `Playlists/*`, and known protobuf `Configuration/*` files as raw protobuf documents with no wrapping header.
- Treat `.probundle`, `.proPlaylist`, `.proTheme`, and `.rvbible` as ZIP archives selected by extension.
- For `.probundle`, select the root `.pro` entry by archive contents. Do not require the internal `.pro` basename to match the bundle basename.
- For `.proPlaylist`, decode the root `data` playlist document as well as each
  embedded `.pro`. The `data` file preserves playlist hierarchy, ordering, and
  each presentation item's optional arrangement UUID. The same embedded
  presentation can therefore be referenced by different items with different
  arrangement selections.
- For `.proTheme`, decode each `*/Theme` entry as an independent `rv.data.Template.Document`; preserve the containing directory because it supplies theme identity, and resolve assets as external, archive-local, or theme-local.
- Preserve unknown protobuf fields during read/write.
- When portable media from separate external locations would collide at one archive path, retain every file by adding `-1`, `-2`, and later suffixes before the extension. This matches ProPresenter 21.4's **New Version** naming convention.

## Direct Archive Editing

The `edit` subcommands accept `.probundle`, `.proPlaylist`, and `.proTheme` files directly in addition to their raw document forms. Archive edits are performed in an owned temporary workspace and written to a validated replacement archive only after the edit succeeds. The replacement normalizes ZIP headers and trailers, stores the edited protobuf entry and new assets, and copies each unchanged compressed byte stream without decompressing or recompressing it. `edit apply` performs this work once for the entire command array.

Existing archive entries and media references are preserved rather than passed through the bundler's media-portability rewrite. When an edit introduces a new media UUID backed by a local file, that file is copied into the archive and only the new reference is changed to its archive-relative path. An identical asset already stored at the intended path is reused; a different asset with the same filename receives a `-1`, `-2`, or later numeric suffix.

For `.proPlaylist`, edits address the root `data` playlist document and preserve embedded presentations. For a `.proTheme` containing multiple `*/Theme` documents, the existing `/slides[...]` paths address the first theme in display order while the other theme documents remain unchanged.

## Native Workspace Contents

`pro-crud workspace contents ROOT` reads one consistent native SQLite snapshot
and reports library membership, resolved presentation stream identities,
Master/group cue order, arrangements, and playlist trees. It keeps shared and
client streams separate. Unavailable content, unresolved references, conflicting
ordering, and unmaterialized stream kinds remain explicit in the report.

Loro tree node IDs and fractional positions are distinct from document UUIDs.
Master order follows the resolved placement tree; arrangement expansion retains
repeated group references. Library links resolve through workspace-relative
logical paths rather than stale pre-migration absolute paths. This inspection
does not write native content or perform Cloud synchronization.

`workspace configuration ROOT` reports saved Looks, the separate client live
Look, ordered screen mappings/layer switches, logical and local screens, stored
rendering flags, and referenced native Theme identities. Missing client outputs
and missing/unavailable Themes remain explicit. Other configuration fields are
listed as uninspected by name. This selected read-only view does not export or
edit the whole Workspace document or configure physical outputs.
`render PRESENTATION --workspace ROOT --look NAME_OR_UUID --screen NAME_OR_UUID`
can use this native configuration for media-free selected Theme slides. It reads
the referenced native Theme rather than legacy leftovers and preserves screen
disabled state. See [rendering behavior](RenderingBehavior.md#template-and-look-resolution).

`workspace inventory ROOT --projections` additionally checks Presentation and
Theme interchange materialization and lists unmapped fields. `workspace export
ROOT --stream UUID --output PATH [--target-version 21|22]` writes a supported
shared Presentation or Theme to a separate raw `.pro` or `Theme` file. New
exports default to target 22. It rejects unmapped content and unsupported media
identity conversions before publishing output; it does not copy media assets.
Existing output requires `--replace`, and native workspace destinations are
rejected. The source Loro history and client state remain untouched.

`workspace media ROOT [--hash-files]` inspects media occurrences in available
shared Presentation/Theme streams and presentation/media/audio playlist trees,
including nested items and the separate live-video tree. Client playlist state
is checked independently. Traversal also covers shared macros, props, stage
layouts, playlist templates and messages, plus the independent client messages
and shared/client Workspace configuration graphs. This includes native macro
and prop collections and media inside Workspace masks; it does not export those
configuration documents. Every occurrence reports its document ID and stream
scope. It distinguishes reference, asset and
container identities, identity schema strings, and each stored locator.
`activeLocators` identifies the selected source: a selected `SourceInfo` file or
HLS source takes precedence over type-specific `FileProperties`, which takes
precedence over the root URL. Superseded locators remain inspectable but are not
resolved or hashed as current dependencies. An explicitly selected empty source
does not fall back to a stale URL. Exact
ROOT_SHOW paths resolve against the selected workspace; a same-basename file
does not substitute for a missing asset. Optional hashing checks local content
agreement within a 30-second budget. Remote/live URLs are reported without
downloading. Live devices, remote streams/resources and web content have separate
source states; file and asset UUID requirements do not apply to live devices.
Runtime availability remains unverified. Every unavailable or uninspected stream remains explicit. File
availability does not establish native asset-store membership, and this report
does not qualify native media writes or replace strict legacy media validation.
