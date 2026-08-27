# Presentation Documents

Presentation documents are raw protobuf files whose root message is `rv.data.Presentation`. They appear as `*.pro` files in libraries and as root entries inside `.probundle` and `.proPlaylist` archives.

## Object Graph

The stable protobuf schema represents a presentation roughly as:

```text
Presentation
  application_info
  uuid, name, category, notes
  background
  selected_arrangement
  arrangements[]
  cue_groups[]
  cues[]
    Cue
      uuid, name, hot_key, completion settings
      actions[]
        Action
          uuid, name, label, type, layer, duration, delay
          oneof ActionTypeData
            slide.presentation.base_slide
            media
            timer
            macro
            audience_look
            clear
            ...
```

Renderable slide content for a slide action is mostly stored under:

```text
Action(type: ACTION_TYPE_PRESENTATION_SLIDE)
  slide.presentation.base_slide
    size
    background_color
    element_build_order[]
    elements[]
      element
        uuid, name, bounds, rotation, opacity
        path, fill, stroke, shadow, feather
        text
          attributes
          rtf_data
          vertical_alignment
          scale_behavior
          margins
          transform, transformDelimiter
        fill.media
      build_in, build_out
      reveal_type, reveal_from_index
      data_links
      childBuilds
      text_scroller
```

Media is represented by `rv.data.Media` from `graphicsData.proto`. Media URLs can be absolute or relative and can point at images, videos, audio, live video, or web content.

Object Build In/Out, text Delivery, the ordered UUID graph, native observations,
and the proposed supported tool surface are documented separately in
[TextBuilds.md](TextBuilds.md). Static rendering currently ignores those fields
and draws the stored, unanimated composition, including elements that a
completed Build Out would remove.

### Media Actions, Transitions, And Playback Markers

A cue's `rv.data.Action.MediaType` carries the media element, its layer type,
transition/effect selection, retrigger flag, and ordered `markers[]`. Each
marker has its own UUID, time, color, name, and nested actions. The file layer
preserves that graph and refreshes marker plus nested-action UUIDs when an
action is copied into a new slide or template result.

The [official Playback Markers workflow](https://support.renewedvision.com/hc/en-us/articles/7171761588371-How-to-use-Playback-Markers)
limits markers to video and audio **media actions**; they do not apply to image
media or media slide elements. A static image export selects one video
thumbnail and does not run media time, transitions, marker actions, transport
seeks, or marker data links. A focused native video/audio-action fixture is
still required before semantic marker inspection or editing commands are
exposed.

### Replacing Media Safely

A media UUID identifies the asset, not merely the stored URL. Changing only
`rv.data.Media.url` can leave the document pointing at one file while
ProPresenter's media registry associates the UUID with another. `edit patch`
therefore rejects URL-only media changes unless `--allow-url-only` is passed for
an intentional relocation of the same asset.

Use `edit set-media` to replace media content in raw or bundled presentation
and Theme documents. It accepts presentation media actions plus presentation
or theme slide-element fills and their containing elements:

```sh
pro-crud edit set-media Welcome.pro \
  --path '/cues[index=0]/actions[index=1]/media/element' \
  --source '/path/to/Welcome.png'

pro-crud edit set-media Welcome.pro \
  --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/fill/media' \
  --source '/path/to/Background.png'

pro-crud edit set-media Themes/Series/Theme \
  --path '/slides[name=Series]/base_slide/elements[name=Background]/element/fill/media' \
  --source '/path/to/Series.png'
```

`--source` constructs a complete media message and generates a new UUID by
default. `--preserve-uuid` is available only for relocating the same asset.

To reuse an asset already registered by a ProPresenter media playlist, copy its
complete canonical media message rather than reconstructing it from a path:

```sh
pro-crud edit set-media Welcome.pro \
  --path '/cues[index=0]/actions[index=1]/media/element' \
  --from-playlist '/path/to/Playlists/Media' \
  --playlist '2026 Values' \
  --item 'CV_Welcome'
```

This retains the playlist UUID, URL variants, dimensions, metadata, drawing
properties, and unknown protobuf fields. The same options can be used in an
atomic `edit apply` batch for presentations and themes with JSON keys
`from-playlist`, `playlist`, and `item`.

For a series change spanning several live-workspace documents, use one
workspace transaction instead of invoking `set-media` once per file:

```sh
pro-crud edit set-media-batch '/path/to/ProPresenter/Workspace' \
  --file values-media.json
```

```json
[
  {
    "document": "Libraries/Main Service Sections/Welcome.pro",
    "path": "/cues[uuid=43DF...]/actions[uuid=11F9...]/media/element",
    "from-playlist": ".",
    "playlist": "Values",
    "item": "CV_Welcome",
    "sync-label": true
  },
  {
    "document": "Themes/Series/Theme",
    "path": "/slides[name=Scripture]/base_slide/elements[uuid=4F65...]/element/fill/media",
    "from-playlist": "Playlists/Media",
    "playlist": "Values",
    "item": "CV-Text Ready 2@2x"
  }
]
```

Each `document`, `source`, and `from-playlist` path in the manifest is relative
to the workspace. `from-playlist` may name the exact raw playlist document or a
containing directory such as `.`; the latter resolves `Playlists/Media`.
Absolute paths, workspace escapes, and symlinked inputs are rejected.

`set-media-batch` supports raw presentation and Theme documents. It validates
every manifest entry and component edit, serializes every updated document to a
staging area, and only then begins atomic per-file replacement. A commit failure
restores the byte-for-byte originals of files already replaced. `sync-label`
updates labels in the containing cue only when they still match the old media
basename, including filename labels stored on a sibling presentation-slide
action. Deliberately customized and semantic labels are preserved.

After replacement, validate media identity against the live workspace:

```sh
pro-crud validate Welcome.pro \
  --workspace '/path/to/ProPresenter/Workspace' \
  --strict-media
```

Strict media validation reports component paths for missing assets, missing
UUIDs, absolute/local URL disagreement, actual-versus-stored image dimensions,
one UUID referring to conflicting files, disagreement with the canonical
`Playlists/Media` registry, and filename-like cue labels that disagree with the
selected asset. It does not modify the document.

## Cue Groups

Each `Presentation.CueGroup` pairs an embedded `rv.data.Group` with an ordered
array of cue UUID references. The embedded group carries its UUID, name, color,
hotkey, and optional application-group UUID and name. The semantic dump reports
that metadata plus every referenced cue's canonical global path.

Use UUID selectors when editing:

```text
/cue_groups[uuid="GROUP-UUID"]
/cues[uuid="CUE-UUID"]
```

Group names may be duplicate or empty, so name selectors can be ambiguous.
Index selectors are zero-based and may change after structural edits. A group's
`cue_identifiers` entries are references to the presentation's global cues,
not nested cue objects.

### Ownership And Membership Editing

Normal presentation structure gives each cue exclusive ownership in one cue
group. The cue-group commands preserve that invariant unless an explicit
ungrouping policy is requested.

Create a group from one or more cue paths:

```sh
pro-crud edit add-cue-group Song.pro \
  --name 'Tag' \
  --cue '/cues[uuid="FIRST-CUE-UUID"]' \
  --cue '/cues[uuid="SECOND-CUE-UUID"]' \
  --color '#CC293D' \
  --after '/cue_groups[uuid="PREVIOUS-GROUP-UUID"]' \
  --output Song-grouped.pro
```

`add-cue-group` accepts repeated `--cue` in the desired order, or `--empty`,
but not both. It removes every selected cue from all existing group occurrences
before inserting it once in the new presentation-local group. A duplicate cue
path in the requested sequence is rejected. The group is appended unless
`--after GROUP_PATH` is supplied. A transfer may leave a source group empty; it
does not remove that group.

Replace one group's complete ordered membership with:

```sh
pro-crud edit set-cue-group-cues Song.pro \
  --path '/cue_groups[uuid="GROUP-UUID"]' \
  --cue '/cues[uuid="FIRST-CUE-UUID"]' \
  --cue '/cues[uuid="SECOND-CUE-UUID"]' \
  --output Song-regrouped.pro
```

This command also requires repeated `--cue` or `--empty`. By default it rejects
an incoming cue owned by another group and rejects an existing group cue
omitted from the replacement. A duplicate cue path is rejected.
`--transfer` explicitly removes incoming cues from all other group occurrences.
`--leave-omitted-ungrouped` explicitly retains omitted cues without a group;
the native-order reader appends them after grouped cues in stored cue order.
That flag is required when `--empty` replaces a nonempty group.

For a single transfer, use:

```sh
pro-crud edit move-cue-to-group Song.pro \
  --path '/cues[uuid="CUE-UUID"]' \
  --group '/cue_groups[uuid="DESTINATION-GROUP-UUID"]' \
  --after '/cues[uuid="DESTINATION-CUE-UUID"]' \
  --output Song-regrouped.pro
```

The cue is removed from every old group occurrence and inserted exactly once
in the destination. It is appended by default; `--first` and
`--after DESTINATION_CUE_PATH` are mutually exclusive alternatives.

### Group Metadata And Structural Editing

Generic `edit rename --path GROUP_PATH --name NAME` renames a group, and
generic `edit move --path GROUP_PATH --after GROUP_PATH` changes its stored
Master position. Set or clear the local color with
`edit set-cue-group-color --path GROUP_PATH --color '#RRGGBB'` or `--clear`;
exactly one color option is required.

Set a local hotkey with:

```sh
pro-crud edit set-cue-group-hotkey Song.pro \
  --path '/cue_groups[uuid="GROUP-UUID"]' \
  --code ansi-v \
  --control-identifier CONTROL_ID \
  --output Song-hotkey.pro
```

Exactly one of `--code VALUE` or `--clear` is required, and
`--control-identifier ID` is valid only with `--code`. Symbolic key spellings
are case-insensitive and accept compact, hyphenated, underscored, canonical
protobuf, and bare-letter forms. For example, `ansiV`, `ansi-v`, `ansi_v`,
`KEY_CODE_ANSI_V`, and `V` select the same key. A raw integer such as `22` is
also accepted. Numeric future enum values are preserved. Digit keys need an
ANSI spelling such as `ansi-1` because bare `1` means raw enum value 1.

`--clear` retains protobuf presence by writing an empty `rv.data.HotKey`
message. It does not make the group's hotkey field absent; that field-presence
distinction remains in the serialized document.

When a group has application-group metadata, changing its name with `rename` or
setting or clearing its color or hotkey detaches the stored application-group
UUID and name. This avoids retaining a workspace-group link after local
metadata diverges. A rename to the existing name does not detach it.

`edit duplicate-cue-group --path GROUP_PATH [--name NAME]` inserts a deep copy
immediately after the source. The new group and every copied cue, action, and
slide graph receive fresh identities; a copied cue-completion target that
pointed to another copied cue is remapped. Each copied cue is named
`<source name> Copy`, or `Slide Copy` when its source name is empty. Existing
arrangements are unchanged. Without `--name`, the label and application-group
link are preserved. A different name detaches the copy. Generic
`edit duplicate` on a cue-group path performs the same deep copy without a name
override.

Removing a cue group requires explicit retention intent:

```sh
pro-crud edit remove-cue-group Song.pro \
  --path '/cue_groups[uuid="OLD-GROUP-UUID"]' \
  --move-cues-to '/cue_groups[uuid="RETAINED-GROUP-UUID"]' \
  --remove-from-arrangements \
  --output Song-pruned.pro
```

Choose at most one cue policy: `--delete-cues`,
`--leave-cues-ungrouped`, or `--move-cues-to GROUP_PATH`. With no cue policy,
the group must be empty. The command rejects arrangement references unless
`--remove-from-arrangements` is present, in which case every occurrence is
removed from every arrangement. The final cue group cannot be removed.
`--delete-cues` also rejects cues referenced by another group, by a retained
cue-completion target, or by the timeline, and it cannot remove all cues.
Generic `edit remove` therefore removes only an empty,
arrangement-unreferenced cue group.

All direct commands support the normal `--output` and `--replace` destination
options. `edit apply` exposes the same command names and option keys; repeated
`cue` values can be supplied as an ordered JSON array. Adding reports only the
`Created` group. Renaming, moving, recoloring, changing a hotkey, or replacing
membership reports the `Affected` group; moving a cue between groups reports
the `Affected` cue. Duplication reports the `Affected` source followed by the
`Created` copy, and removal reports the original canonical group path as
`Removed`.

### Master And Arrangement Effects

Cue groups define both Master order and the content expanded by arrangements:

| Edit | Master/native effect | Existing arrangement effect |
| --- | --- | --- |
| Add a group | Inserts the group in stored group order. | The new group is omitted until explicitly added to an arrangement. Transferred cues disappear from occurrences of their former groups. |
| Set group cues or move a cue | Changes cue ownership and order. | Every occurrence of each affected group expands its updated membership. |
| Move a group | Changes stored Master group order. | Explicit arrangement UUID sequences are unchanged. |
| Duplicate a group | Inserts the deep copy after the source. | Existing arrangements do not gain the copied group. |
| Remove a group | Applies the selected delete, ungroup, or move policy. | Referencing arrangements block removal unless every occurrence is explicitly removed. |

## Native Cue Ordering

The stored order of `presentation.cues` is not necessarily the Master/native
slide order. That order comes from flattening
`presentation.cue_groups[].cue_identifiers` in cue-group order.

A deterministic reader should:

1. Flatten cue UUIDs from `cue_groups` in stored order.
2. Resolve those UUIDs against `presentation.cues`.
3. Append any cues that are not referenced by a group in their stored order.

Component paths follow the same semantics as ProPresenter's control API: for
presentations, `/cues[index=N]` uses this effective presentation order rather
than the raw `presentation.cues` protobuf occurrence. UUID and name selectors
still address cue identity directly. Indices are zero-based, matching the API.

Arrangements do not replace this native order. Presentation component paths
always use native cue-group order, even while an arrangement is selected for
rendering.

## Arrangements

`Presentation.arrangements` stores alternative cue-group sequences. Each
`Presentation.Arrangement` has its own UUID and name plus an ordered
`group_identifiers` array. To resolve one, process the group references in
their stored order and append each referenced group's cues in that group's
stored order.

The group-reference array is a sequence, not a set. Repeating a group UUID
repeats all of that group's cues at that point in the effective sequence. A
group that is not referenced is omitted from that arrangement. An arrangement
with no group references is valid and resolves to an empty cue sequence.

`Presentation.selected_arrangement` is an optional UUID reference. A
presentation with no selected arrangement uses its Master/native order. A
presentation playlist item can independently store an arrangement UUID for the
same presentation. The file renderer resolves these sources in this order:

1. An explicit `render --arrangement` value.
2. The presentation playlist item's arrangement UUID.
3. The presentation's stored `selected_arrangement` UUID.
4. Master/native cue-group order.

`render --arrangement native` explicitly selects Master and
`render --arrangement selected` explicitly requests the stored selection. The
latter fails if the presentation has no stored selection. Any other value is
matched as an exact arrangement UUID. Render-only selection does not rewrite
the presentation or playlist.

The semantic text and JSON dump formats report the stored selected UUID,
arrangement UUIDs and names, ordered group references, canonical arrangement
and group paths, and playlist-item arrangement UUIDs. Effective-rendering JSON
also identifies the arrangement used for that render; its `arrangement` value
is absent for Master.

### Arrangement Editing

Create an arrangement by supplying cue-group component paths in sequence:

```sh
pro-crud edit add-arrangement Song.pro \
  --name 'Short Service' \
  --group '/cue_groups[name="Verse 1"]' \
  --group '/cue_groups[name=Chorus]' \
  --group '/cue_groups[name="Verse 2"]' \
  --group '/cue_groups[name=Chorus]' \
  --select
```

Repeated `--group` values are retained. With neither `--group` nor `--empty`,
the new arrangement contains every native cue group once. Use `--empty`
instead of `--group` to create an empty arrangement. `--select` also stores the
new arrangement as the presentation selection.

Replace an existing sequence atomically with
`edit set-arrangement-groups --path ARRANGEMENT_PATH`, again using repeated
`--group` values or `--empty`. Use
`edit select-arrangement --path ARRANGEMENT_PATH` and
`edit clear-selected-arrangement` to set or clear the stored selection.

Arrangement component paths also support the generic `edit rename`,
`duplicate`, `remove`, and `move` operations. Names need not be unique, so use
the canonical UUID path reported by `dump` when a name selector would be
ambiguous. Structural edit output reports canonical affected and created paths.

## Minimal Authored Presentation

A generated presentation that ProPresenter can import needs at least:

- `Presentation.application_info`
- `Presentation.uuid`
- `Presentation.name`
- one or more `Presentation.cues`
- one or more `Presentation.cue_groups` entries that reference cue UUIDs for ordering
- a cue with an enabled `ACTION_TYPE_PRESENTATION_SLIDE` action
- `PresentationSlide.base_slide` with a canvas `size`, a background, and any desired elements

A `.probundle` can contain only that root `.pro` file when there are no external media assets. The internal `.pro` filename does not need to match the archive filename.

ProPresenter may rewrite generated documents on import. Observed rewrites include UUID changes, normalized text element structure, adjusted bounds, normalized font metadata, explicit element `info` values, current `application_info`, and default submessages. The installed presentation name follows the installed `.pro` filename, including a suffix chosen to resolve a library filename collision. A writer should therefore target behavior and data preservation, not byte identity after ProPresenter installs the document.

Export alone behaves differently from import: ProPresenter 21.4's presentation-only export and the `.pro` payload in its bundle are byte-identical to the current live-library file. Re-exporting an imported document likewise preserves the already-normalized installed bytes.

## Slide Elements

Shape elements can be represented as `Graphics.Element` values with bounds, opacity, a normalized path, and fill/stroke styling. Rectangles use normalized path points from `(0, 0)` to `(1, 1)` plus `shape.type = TYPE_RECTANGLE`.

Text elements should include both:

- Cocoa RTF in `Graphics.Text.rtf_data`
- compatible `Graphics.Text.Attributes`

RTF is the visible text source in tested documents. ProPresenter preserves RTF run-level font, size, color, underline, strikethrough, highlight, stroke, shadow, kerning, baseline offset, and paragraph spacing. Box-level protobuf attributes remain important metadata for compatibility, but they should not be assumed to override fully styled RTF content unless a focused test document proves that specific fallback.

### Styled Text Editing

`pro-crud edit set-text` accepts exactly one text source:

```sh
# Uniform platform-native styling
pro-crud edit set-text deck.pro --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text' --text 'Plain text'

# Mixed styling supplied directly by the caller
pro-crud edit set-text deck.pro --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text' --rtf '{\rtf1\ansi Heading \b bold\b0}'

# Mixed styling loaded without shell escaping
pro-crud edit set-text deck.pro --path '/cues[index=0]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text' --rtf-file content.rtf
```

Inline and file RTF are decoded before the presentation is changed, and their original bytes are preserved. The first RTF run also updates the text box's compatibility font metadata; mixed run styling remains in the RTF itself.

Replacing the complete RTF also clears all `custom_attributes`. Those entries
are ranges into the previous string and can otherwise apply stale
capitalization, original-size, scale, fill, chord, and color-preservation
metadata to unrelated replacement text.

### Batch Editing

`pro-crud edit apply` accepts a JSON array whose objects use an existing edit subcommand name and the same option names as that subcommand:

```json
[
  { "command": "patch", "path": "/", "json": "{\"name\":\"Sunday Service\"}" },
  { "command": "duplicate", "path": "/cues[index=0]" },
  { "command": "rename", "path": "/cues[index=1]", "name": "Welcome" },
  {
    "command": "set-text",
    "path": "/cues[index=1]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text",
    "rtf": "{\\rtf1\\ansi Welcome \\b everyone\\b0}"
  }
]
```

Apply the file in place or use the batch-level output options:

```sh
pro-crud edit apply deck.pro --file edits.json
pro-crud edit apply deck.pro --file edits.json --output edited.pro --replace
```

Commands run in array order, so later paths can select content created or renamed by earlier commands. The input is loaded once and the result is written once, only after every command succeeds. A failing command reports its one-based array position and leaves the input and output unchanged.

Text transforms are applied at render time. For example, `Graphics.Text.transform = replace_line_returns` with `transformDelimiter` renders a multiline RTF string as one line joined by the delimiter.

## Element Paint Order

Slide elements are stored front-to-back and painted in reverse stored order.
The focused `Reverse stored element paint order` fixture isolates this behavior.
Its stored `info` sequence is `[0, 2, 1]`, while ProPresenter paints source
indices `[2, 1, 0]`; that counterexample proves `info` is not the sorting key.

The meaning of `slide.elements[].info` remains unresolved. Preserve it as
compatibility metadata, but do not reorder elements from it.

## Presentation Background And Slide Background

Presentation-level background and slide-level background are separate. The focused `Transparent background` reference slide verifies whether untouched PNG pixels remain transparent when the generated document includes visible elements.

Writers should choose the field that matches ProPresenter's UI behavior for the intended operation and verify with an export when background parity matters. Renderers should preserve transparent untouched pixels unless a fixture proves that a stored background paints for that export workflow.
