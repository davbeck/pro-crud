# Top-Level ProPresenter File Formats

ProPresenter stores editable library data primarily as raw protobuf files. User-facing import/export formats are ZIP archives whose payloads are those same protobuf documents plus optional media assets.

Archive extensions identify the export workflow. The extension is part of the user-facing format contract; the payload files inside still need to be identified and decoded by entry name and protobuf root type.

## Export Containers

| Extension | Container | Typical entries | Primary payloads | Purpose |
| --- | --- | --- | --- | --- |
| `.probundle` | ZIP | One root `.pro` file; optional media files | `rv.data.Presentation` in the `.pro` file | Presentation bundle export/import. A media-free presentation can contain only the `.pro`; a bundle with media can include images, videos, or audio alongside it. |
| `.proPlaylist` | ZIP | One root `data` file plus one or more root `.pro` files | `rv.data.PlaylistDocument` in `data`; `rv.data.Presentation` in each `.pro` | Playlist export/import. The `data` file preserves playlist tree structure, item ordering, per-item arrangement UUIDs, and references to embedded presentation documents. |
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

## Live Workspace Layout

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

The primary editable document model lives in `Libraries/`, `Playlists/`, `Themes/`, and `Configuration/`. `Media/` stores referenced assets. Runtime databases, generated thumbnails, caches, and downloaded support data are derived state unless a specific workflow proves otherwise.

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
regular `PlaylistDocument` or overwrite it with a playlist. Add a focused,
ProPresenter-authored store fixture before exposing inspect/edit commands; it
must cover headers, placeholders, and presentation items plus template
creation from the UI.

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
creates, refreshes, or detaches linked groups remains a separate compatibility
experiment.

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
| Runtime database folders | LevelDB-style files plus generated assets | Derived application state. Useful for observation, but not the primary editing model. |

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
- When portable media from separate external locations would collide at one archive path, retain every file by adding `-1`, `-2`, and later suffixes before the extension. This matches ProPresenter's observed **New Version** naming convention.

## Direct Archive Editing

The `edit` subcommands accept `.probundle`, `.proPlaylist`, and `.proTheme` files directly in addition to their raw document forms. Archive edits are performed in an owned temporary workspace and written to a validated replacement archive only after the edit succeeds. The replacement normalizes ZIP headers and trailers, stores the edited protobuf entry and new assets, and copies each unchanged compressed byte stream without decompressing or recompressing it. `edit apply` performs this work once for the entire command array.

Existing archive entries and media references are preserved rather than passed through the bundler's media-portability rewrite. When an edit introduces a new media UUID backed by a local file, that file is copied into the archive and only the new reference is changed to its archive-relative path. An identical asset already stored at the intended path is reused; a different asset with the same filename receives a `-1`, `-2`, or later numeric suffix.

For `.proPlaylist`, edits address the root `data` playlist document and preserve embedded presentations. For a `.proTheme` containing multiple `*/Theme` documents, the existing `/slides[...]` paths address the first theme in display order while the other theme documents remain unchanged.
