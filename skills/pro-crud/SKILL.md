---
name: pro-crud
description: Design, create, inspect, edit, package, document, and render ProPresenter presentations, themes, playlists, workspaces, and bundles with the pro-crud CLI. Use for audience-slide design and readability guidance, background selection or generation, reusable templates, or any work with .pro, .proTheme, .proPlaylist, .probundle, and related ProPresenter document formats.
---

# ProCRUD

Use `pro-crud` for ProPresenter document work. Run `pro-crud --help` and the
relevant subcommand's `--help` before constructing a command; do not guess flags
or component paths.

## Workflow

1. Before editing a live ProPresenter library, confirm ProPresenter is not
   running; if it is, ask the user to quit it. Use a copied or disposable
   document for experiments.
2. Inspect the input with `pro-crud dump <input>`. Use `--format json` for the
   structured semantic report and its canonical component paths. Use
   `--format protobuf-json` only for known protobuf fields that the semantic
   report does not expose.
3. Choose a purpose-built command:
   - `create` for presentations, themes, and playlists.
   - `edit` for component and content changes.
   - `expand` and `bundle` for archive conversion.
   - `render` for slide image output.
   - `docs format` and `docs protobuf` for bundled format and schema references.
4. Prefer `--output` when an edit command supports it so the source remains
   unchanged. Edit a copied supported archive directly; expand and rebundle it
   only when the task requires access to its extracted structure.
5. Use `edit apply` for coordinated changes so the document is loaded and
   written once and a failed command leaves it unchanged.
6. Verify the result with `validate` and `dump`; for visual changes, also use
   `render`.

Use the bundled documentation before inferring undocumented format behavior.
Preserve unknown protobuf fields by using `pro-crud` operations instead of
rebuilding messages from incomplete JSON.

## Presentation authoring

When turning notes, an outline, imported text, or an existing presentation into
an ordered multi-cue deck, read
[`references/presentation-authoring.md`](references/presentation-authoring.md).
It covers evidence priority, source interpretation, behavior-preserving cue
construction, effective cue order, atomic editing, visual diagnostics, and
final-artifact verification.

## Cue groups

Cue groups define Master/native cue order and the units expanded by
arrangements. Start with `dump --format json`. It reports each group's UUID,
canonical `/cue_groups[uuid="..."]` path, name, color, hotkey,
application-group metadata, and ordered canonical `/cues[uuid="..."]`
references. Names can be duplicate or empty, so prefer UUID paths.

Create a group with repeated cues in the desired order, or create an explicitly
empty group:

```sh
pro-crud edit add-cue-group INPUT \
  --name NAME \
  --cue CUE_PATH \
  --cue CUE_PATH \
  --color '#RRGGBB' \
  --after GROUP_PATH \
  --output OUTPUT

pro-crud edit add-cue-group INPUT \
  --name NAME \
  --empty \
  --output OUTPUT
```

`--cue` and `--empty` are mutually exclusive; `--color` and `--after` are
optional. Added cues are transferred from every old group occurrence,
maintaining exclusive ownership. Listing the same cue more than once is
rejected. Use
`edit set-cue-group-cues --path GROUP_PATH` with repeated `--cue` or `--empty`
to replace a group's complete membership. Its safe defaults reject incoming
cues owned elsewhere, omitted existing cues, and duplicate cue paths. Add
`--transfer` to take incoming cues from their current groups; add
`--leave-omitted-ungrouped` to retain omissions outside every group. The latter
is required to empty a nonempty group.

Move one cue with:

```sh
pro-crud edit move-cue-to-group INPUT \
  --path CUE_PATH \
  --group DESTINATION_GROUP_PATH \
  --first \
  --output OUTPUT
```

The destination position defaults to the end. Use `--first` or
`--after DESTINATION_CUE_PATH` for another position; they are mutually
exclusive. The cue is removed from all old group occurrences and inserted
exactly once.

Use generic `edit rename --path GROUP_PATH --name NAME` to rename a group and
`edit move --path GROUP_PATH --after SIBLING_GROUP_PATH` to reorder Master.
Use `edit set-cue-group-color --path GROUP_PATH --color '#RRGGBB'` or `--clear`
to change its local color.

Set or clear a local hotkey with:

```sh
pro-crud edit set-cue-group-hotkey INPUT \
  --path GROUP_PATH \
  --code ansi-v \
  --control-identifier CONTROL_ID \
  --output OUTPUT

pro-crud edit set-cue-group-hotkey INPUT \
  --path GROUP_PATH \
  --clear \
  --output OUTPUT
```

Exactly one of `--code VALUE` or `--clear` is required.
`--control-identifier ID` is optional and can accompany only `--code`. Key
spellings are case-insensitive: `ansiV`, `ansi-v`, `ansi_v`,
`KEY_CODE_ANSI_V`, and bare `V` are equivalent. A raw integer such as `22` is
also accepted, including unknown future enum values that must be preserved. Use
`ansi-1` for the digit key; bare `1` means raw enum value 1. Clearing retains a
present empty `rv.data.HotKey` protobuf message rather than removing field
presence.

Changing a linked group's name, or explicitly setting or clearing its color or
hotkey, detaches its stored application-group UUID and name.

`edit duplicate-cue-group --path GROUP_PATH [--name NAME]` deep-copies the
group and its cues, actions, and slide graphs with fresh identities, remapping
copied internal cue-completion targets. Copied cues are named
`<source name> Copy`, or `Slide Copy` when the source name is empty. It inserts
the copy after the source and does not change existing arrangements. With no
name override it preserves the source label and application-group link; a
different name detaches the copy. Generic `edit duplicate` performs the same
copy without a name override.

Use `edit remove-cue-group --path GROUP_PATH` with at most one cue policy:
`--delete-cues`, `--leave-cues-ungrouped`, or
`--move-cues-to DESTINATION_GROUP_PATH`. Without a policy the group must be
empty. Referencing arrangements block removal unless
`--remove-from-arrangements` removes every occurrence. The final group cannot
be removed, and cue deletion is rejected when it would remove all cues or
leave group, completion-target, or timeline references dangling. Generic
`edit remove` only removes an empty, arrangement-unreferenced cue group.

Moving a group changes Master order only; explicit arrangement UUID sequences
stay stable. Changing group membership changes every occurrence of that group.
New and duplicated groups are not added to existing arrangements. Adding
reports only the `Created` group. Renaming, moving, recoloring, changing a
hotkey, or replacing membership reports the `Affected` group; moving a cue
between groups reports the `Affected` cue. Duplication reports the `Affected`
source and `Created` copy, and removal reports the original group as `Removed`.

## Arrangements

Use arrangements for alternate song or service sequences without changing the
presentation's Master/native cue-group order. Start with `dump`; it reports the
stored selected arrangement, every arrangement's UUID, name, ordered group
references, canonical paths, and playlist-item arrangement UUIDs.

Render Master, the stored selection, or an exact arrangement UUID without
rewriting the source:

```sh
pro-crud render INPUT --arrangement native --output MASTER_PREVIEW
pro-crud render INPUT --arrangement selected --output SELECTED_PREVIEW
pro-crud render INPUT --arrangement ARRANGEMENT_UUID --output PREVIEW
```

With no explicit option, selection precedence is playlist item, stored selected
arrangement, then Master. An explicit `--arrangement` overrides that chain;
`selected` fails when the presentation has no stored selection.

Create an arrangement with `edit add-arrangement --name NAME` and repeat
`--group GROUP_PATH` in the exact desired sequence. Repeating a path repeats
that group's cues. With neither `--group` nor `--empty`, the new arrangement
uses each native cue group once. Use `--empty` for an intentionally empty
arrangement, and add `--select` when the new arrangement should become the
stored selection. Replace a sequence with
`edit set-arrangement-groups --path ARRANGEMENT_PATH`, using repeated `--group`
values or `--empty`.

Use `edit select-arrangement --path ARRANGEMENT_PATH` or
`edit clear-selected-arrangement` to change stored selection. Arrangement paths
also work with generic `rename`, `duplicate`, `remove`, and `move`. Arrangement
names can be ambiguous; prefer canonical UUID paths from `dump`. Arrangement
selection never changes native `/cues[index=N]` component-path semantics.

## Design and templates

For new audience slides, theme creation, or visual restyling, read
[`references/design-guidance.md`](references/design-guidance.md). Before choosing
a style, inspect the existing workspace: configured Screens and Looks, exact
main Audience-screen resolution, Themes, representative library content, Media
Bin, installed and currently used fonts, church branding, and series or event
artwork. Match established conventions unless the user requests a new direction.
In ProPresenter, find output names and pixel dimensions under **Screens ->
Configure Screens** and review routing and alternate Themes under **Screens ->
Edit Looks**.

When selecting, acquiring, assigning, or generating a worship or teaching
background, also read
[`references/background-sourcing.md`](references/background-sourcing.md). Treat
media already available in the local library as usable. Reuse one background
throughout a song, but give every other song in the service a distinct visual
unless it is an intentional reprise or medley.

Use `assets/themes/ProCRUD Design System.proTheme` when the library has no more
appropriate house or series Theme. It contains four Theme documents and all 99
variations in these groups: Classic Worship, Creative Worship, Teaching, and
Streaming. Avenir Next is the bundled Theme's default, not a universal font
recommendation. Adapt the destination presentation to the exact pixel dimensions
of the main Audience screen.

The group documents can contain similarly named templates. Inspect the Theme
with `dump`, then use `--theme-document` with its archive-relative document path
and `--template` with the exact template name. Copy the Theme into the task
workspace before customizing it. Prefer semantic element names with
`edit set-text --text`; plain text retains the element's base style. Use RTF
only for intentional mixed inline styling.

## Theme templates and Looks

Apply a Theme template to an existing cue with `edit apply-template`. Start with
`--dry-run` and review its assignments, scaling, removed content, unfilled slots,
and warnings before writing. Use semantic element names in both the source and
template when possible. The selected cue must contain exactly one
presentation-slide action.

Template actions are explicit: `preserve` keeps existing actions, `append` adds
fresh template-action copies, and `replace` removes existing non-slide actions
while retaining the presentation-slide action. Use `--include-template-actions`
for new slides only when the requested workflow needs them.

Preview a template without writing the source:

```sh
pro-crud render INPUT \
  --theme THEME \
  --theme-document THEME_DOCUMENT \
  --template TEMPLATE \
  --size WIDTHxHEIGHT \
  --template-report REPORT.json
```

Use the exact destination Audience-screen size for `--size`. Omit
`--theme-document` only when the archive contains one Theme document or the
selection is otherwise unambiguous.

Inspect configured Looks before delivery. A Look can preserve full-screen
content and media on the room output while translating the same content through
another template over camera video on a stream or auxiliary screen. Preview
each relevant alternate output:

```sh
pro-crud render INPUT \
  --workspace USER_WORKSPACE \
  --look LOOK_NAME_OR_UUID \
  --screen SCREEN_NAME_OR_UUID
```

Static Look rendering cannot recreate live layers that are absent from the
documents. Treat emitted warnings as material and validate the actual output
when camera, masks, props, messages, or other live state matters.

When a template references media, supply the Theme or workspace context needed
to resolve it. An unresolved-template-media warning means the asset will not be
copied or rendered; do not ignore it.

## Media identity

Treat a media UUID as the asset identity, not as path metadata. Never use
`edit patch` to change only `rv.data.Media.url` when replacing content.

- Use `edit set-media --source FILE` for a new local asset. It generates a new
  media UUID by default.
- Use `edit set-media --from-playlist SOURCE --playlist NAME --item NAME` when
  the asset already exists in a media playlist. This copies its canonical media
  object and UUID.
- Use `--preserve-uuid` only when relocating the same asset.
- Use `edit apply` for several replacements in one document.
- Use `edit set-media-batch WORKSPACE --file MANIFEST` for replacements across
  several raw workspace documents.

Choose how media is attached by playback behavior, not packaging. Use a slide
element when the media belongs to that slide's composition. Use a background
media action when it should persist across several cues. A `.probundle` can
include referenced media in either case.

Both raw documents and `.probundle` or `.proTheme` archives are supported.
Verify the media UUID and URL with `dump` after editing. For workspace-aware
integrity checks, run:

```sh
pro-crud validate DOCUMENT --workspace WORKSPACE --strict-media
```

Investigate every missing identity, URL disagreement, dimension mismatch, UUID
conflict, missing asset, registry conflict, or filename-label mismatch.
