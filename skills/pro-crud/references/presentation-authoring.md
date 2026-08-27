# Presentation authoring and delivery

Use this reference when creating or revising an ordered presentation from
notes, an outline, imported text, or an existing presentation. Read
[`design-guidance.md`](design-guidance.md) as well when choosing or changing the
visual treatment.

## Contents

- [Choose the evidence and working document](#choose-the-evidence-and-working-document)
- [Plan cues from the source](#plan-cues-from-the-source)
- [Inspect structure and effective rendering](#inspect-structure-and-effective-rendering)
- [Author cue groups safely](#author-cue-groups-safely)
- [Author and preview arrangements](#author-and-preview-arrangements)
- [Preserve cue behavior](#preserve-cue-behavior)
- [Make coordinated edits](#make-coordinated-edits)
- [Tune and review](#tune-and-review)
- [Verify the deliverable](#verify-the-deliverable)

## Choose the evidence and working document

Use this authority order while honoring the user's explicit request:

1. The supplied source content and current delivery requirements.
2. Manual changes already present in the target presentation.
3. A current approved local presentation, Theme, or series example.
4. Recent comparable finished presentations.
5. Written guidance and the bundled Theme as fallbacks.

Inspect the actual exemplar rather than relying on remembered coordinates,
labels, actions, or styling. When sources disagree, preserve deliberate target
edits and follow the most current approved evidence unless the user requests a
different direction.

Keep the source artifact unchanged. Prefer copying and editing an existing
target over rebuilding it. The edit commands accept supported archives such as
`.probundle` and `.proTheme` directly and preserve unchanged entries and media
references. Expand an archive only when its extracted structure must be
inspected or changed; do not introduce an unnecessary expand-and-rebundle cycle.

## Plan cues from the source

Preserve meaningful headings, emphasis, lists, paragraph boundaries, and
ordering when reading source material. Treat labels, blank blocks, indentation,
formatting, and repetition as evidence of intent rather than as a rigid grammar.

Infer the semantic role of each cue before editing. Common roles include title,
section transition, concise point, point with explanation, question, list,
quotation, scripture or other long-form reading, image, progressive reveal, and
closing state. Do not invent missing content. Resolve material ambiguities with
the user when the intended wording, order, attribution, or behavior cannot be
inferred safely.

Make a short cue plan containing:

- presentation order and source range;
- semantic role and intended communication purpose;
- local exemplar cue or Theme template;
- semantic text and media slots;
- actions and progressive behavior to preserve or change;
- relevant Audience Screens and Looks.

Preserve deliberate repetition when it represents a progression or reveal.
Give genuinely parallel or contrasting statements equal visual weight unless
the content establishes a hierarchy.

## Inspect structure and effective rendering

Start with the text report, then use semantic JSON when exact structure or
component paths matter:

```sh
pro-crud dump INPUT
pro-crud dump INPUT --format json
```

Use dump JSON for native document order, cue groups, stored arrangements,
actions, labels, notes, text, media, build-presence summaries, and canonical
selectors. Use `--format protobuf-json` only when a required known protobuf
field is not represented in the semantic report.
Use effective-rendering JSON for presentation order, visible layers, resolved
text and RTF runs, font faces, line count, scale-to-fit results, rendered
bounds, and reported `componentPath` values.

The stored `presentation.cues` order can differ from the Master/native document
order, which is defined by cue groups. Arrangements are ordered cue-group
sequences: repeated group references repeat those cues, omitted groups do not
render, and an empty sequence is valid. They do not replace the native order
used by presentation component paths. Paths such as `/cues[index=N]` use
zero-based native document order. `pro-crud render --slide` uses one-based
numbers in the effective native or arranged sequence, while render JSON retains
zero-based occurrence `index` values.

## Author cue groups safely

Use cue groups to define Master/native order and reusable arrangement sections.
The semantic dump reports each group's UUID, canonical path, name, color,
hotkey, application-group UUID and name, and ordered global cue paths:

```text
/cue_groups[uuid="GROUP-UUID"]
/cues[uuid="CUE-UUID"]
```

Names may be duplicate or empty. Copy UUID paths from `dump --format json`
rather than relying on a name selector, and remember that a group's cue
identifiers reference global cues rather than child objects.

Create a group by transferring cues in the intended order:

```sh
pro-crud edit add-cue-group INPUT \
  --name 'Tag' \
  --cue FIRST_CUE_PATH \
  --cue SECOND_CUE_PATH \
  --color '#CC293D' \
  --after PREVIOUS_GROUP_PATH \
  --output CANDIDATE
```

Repeat `--cue`, or use `--empty` instead; the two forms are mutually exclusive.
Selected cues are removed from every old group occurrence and inserted once in
the new group, preserving exclusive ownership. Repeating the same cue path is
rejected. The new group is appended when `--after` is omitted. A transfer can
leave an old group empty, but does not remove it.

For one cue, move it directly:

```sh
pro-crud edit move-cue-to-group INPUT \
  --path CUE_PATH \
  --group DESTINATION_GROUP_PATH \
  --first \
  --output CANDIDATE
```

The destination position is the end by default. `--first` or
`--after DESTINATION_CUE_PATH` chooses another position; they are mutually
exclusive. The command removes the cue from every former group occurrence
before inserting it exactly once.

Use `edit set-cue-group-cues --path GROUP_PATH` with repeated `--cue` values
to replace the complete ordered membership, or use `--empty`. The default is
intentionally conservative: it rejects cues owned by another group and rejects
existing cues omitted from the replacement; duplicate cue paths are also
rejected. `--transfer` explicitly takes incoming cues from their groups.
`--leave-omitted-ungrouped` retains omitted cues outside all groups, where the
native reader appends them in stored cue order; that flag is required when
emptying a nonempty group.

Use generic `edit rename --path GROUP_PATH --name NAME` for the label and
generic `edit move --path GROUP_PATH --after SIBLING_GROUP_PATH` for Master
group order. Set a local color with
`edit set-cue-group-color --path GROUP_PATH --color '#RRGGBB'`, or clear it
with `--clear`.

Set a group hotkey with a key code and optional control identifier:

```sh
pro-crud edit set-cue-group-hotkey INPUT \
  --path GROUP_PATH \
  --code ansi-v \
  --control-identifier CONTROL_ID \
  --output CANDIDATE
```

Use `--clear` instead of `--code` to clear it. Exactly one of those options is
required, and `--control-identifier ID` is valid only with `--code VALUE`. Key
spellings are case-insensitive and flexible: `ansiV`, `ansi-v`, `ansi_v`,
canonical `KEY_CODE_ANSI_V`, and bare `V` all select the same code. A raw
integer such as `22` is also valid, and numeric future enum values are
preserved. Digit keys need an ANSI spelling such as `ansi-1` because bare `1`
means raw enum value 1.

Clearing retains a present empty `rv.data.HotKey` protobuf message rather than
making the field absent. Changing a linked group's name, or explicitly setting
or clearing its color or hotkey, detaches its application-group UUID and name
so locally customized metadata does not retain a stale workspace link.

Duplicate a whole authored section with
`edit duplicate-cue-group --path GROUP_PATH [--name NAME]`. This is a deep
copy: the group, cues, actions, and slide graphs receive fresh identities, and
completion targets between copied cues are remapped. It is inserted after the
source. Copied cues are named `<source name> Copy`, or `Slide Copy` when the
source name is empty. With no name override it preserves the source label and
application-group link; a different name detaches the copy. Generic `edit
duplicate` performs the same copy without a name override.

Remove a group only with the desired cue policy:

```sh
pro-crud edit remove-cue-group INPUT \
  --path OLD_GROUP_PATH \
  --move-cues-to RETAINED_GROUP_PATH \
  --remove-from-arrangements \
  --output CANDIDATE
```

Choose no more than one of `--delete-cues`,
`--leave-cues-ungrouped`, or `--move-cues-to GROUP_PATH`. Without one, only
an empty group can be removed. Arrangement references are rejected unless
`--remove-from-arrangements` removes every occurrence. The final group cannot
be removed. Deletion also rejects cues still referenced by other groups,
retained completion targets, or the timeline, and cannot delete all cues.
Generic `edit remove` is therefore limited to an empty,
arrangement-unreferenced group.

Group operations have deliberately different sequence effects:

- changing membership updates every arrangement occurrence of each affected
  group;
- moving a group changes Master/native order but not an arrangement's explicit
  UUID sequence;
- adding or duplicating a group does not add it to existing arrangements;
- removing a referenced group requires explicit arrangement cleanup.

Adding reports only the `Created` group. Renaming, moving, recoloring, changing
a hotkey, or replacing membership reports the `Affected` group; moving a cue
between groups reports the `Affected` cue. Duplication reports its `Affected`
source plus the new `Created` group, and removal reports the original group as
`Removed`. Prefer `--output CANDIDATE`, then validate, dump, and render both
Master and any affected arrangement before replacing the source.

## Author and preview arrangements

Use a separate arrangement when one presentation needs different service,
venue, or delivery sequences. Preserve Master as the stable authoring order and
express repetition and omission in the arrangement rather than duplicating or
removing stored cues.

Create the sequence from canonical cue-group paths reported by `dump`:

```sh
pro-crud edit add-arrangement INPUT \
  --name 'Short Service' \
  --group VERSE_1_GROUP_PATH \
  --group CHORUS_GROUP_PATH \
  --group VERSE_2_GROUP_PATH \
  --group CHORUS_GROUP_PATH \
  --select \
  --output CANDIDATE
```

With neither `--group` nor `--empty`, `add-arrangement` uses every native cue
group once. Use that default only when it is the intended arrangement sequence.
Use `edit set-arrangement-groups --path ARRANGEMENT_PATH` with repeated
`--group` values to replace the sequence, or with `--empty` to retain a valid
arrangement with no cue occurrences. Use `edit select-arrangement` and
`edit clear-selected-arrangement` for the stored selection. Use the generic
`rename`, `duplicate`, `remove`, and `move` commands with arrangement paths for
those structural changes. Prefer UUID paths because arrangement names need not
be unique.

Preview the intended selection explicitly:

```sh
pro-crud render CANDIDATE \
  --arrangement ARRANGEMENT_UUID \
  --format pdf,png,json \
  --output ARRANGEMENT_PREVIEW \
  --replace
```

Explicit render selection overrides a playlist item's arrangement, which
otherwise overrides the presentation's stored selection. With neither stored
reference, rendering uses Master. `--arrangement native` forces Master and
`--arrangement selected` requests the stored selection. Check effective JSON's
arrangement metadata and occurrence indices as well as the visual output.

## Preserve cue behavior

When adapting a local presentation, duplicate the cue whose semantic role and
behavior most closely match the intended result. Treat the complete cue action
set as part of that exemplar, not as incidental metadata. Audit labels, macros,
timers, media actions, transitions, and other nonvisual actions instead of
copying only the slide geometry or background.

If appearance comes from one cue and behavior from another, explicitly verify
the final action set against the intended role. Preserve identifiers only within
the configuration where they are known to resolve; do not transplant local
macro, timer, or media identities into an unrelated workspace by assumption.

Preserve semantic element names so Theme assignment and alternate Looks can map
content reliably. Keep action changes intentional and use the `apply-template`
action policy that matches the requested result.

Preserve existing native builds when duplicating a proven cue. Static rendering
shows the effective fully revealed composition and cannot prove reveal timing or
progression. Inspect the dump's build summary, use protobuf JSON only for
unmodeled build details, and click through the result in ProPresenter when
builds matter. Do not synthesize undocumented build graphs from guessed
protobuf fields.

## Make coordinated edits

Use `edit apply` for deck generation or any related duplication, movement,
renaming, text, geometry, media, and action changes:

```sh
pro-crud edit apply INPUT \
  --file EDITS.json \
  --output CANDIDATE \
  --replace
```

Commands run in array order, and the document is written only after every
command succeeds. Prefer UUID selectors for objects that exist before the batch
when structural edits can shift positions. Use an exact semantic name when it
is unique. Record the canonical affected and created paths reported by edit
commands instead of deriving paths from protobuf array positions.

Use plain `set-text --text` when the element's base style should remain uniform.
Use `rtf-file` for intentional mixed inline styling so shell and JSON escaping
cannot corrupt the RTF. Avoid raw `patch` for behavior already supported by a
purpose-built edit command.

## Tune and review

Render PDF, images, and effective JSON together:

```sh
pro-crud render CANDIDATE \
  --format pdf,png,json \
  --output PREVIEW_DIRECTORY \
  --replace
```

- Use the PDF to review deck-wide order, rhythm, and consistency.
- Use the images for close visual judgment of every composition.
- Use JSON to diagnose, when present, `plainText`, `effectiveRTF`, resolved runs,
  `familyName`, `postscriptName`, `lineCount`, `fontScale`, `contentBounds`,
  `drawBounds`, and `componentPath`.

Treat unexpected font substitution as invalid layout evidence. Resolve the
intended family and face before tuning wrapping or geometry because substitute
font metrics can change both. Numeric diagnostics support visual judgment; they
do not replace it.

Tune text-box width, authored font size, leading, and paragraph spacing together.
Avoid manual line breaks added only to force wrapping. Reject clipping,
collisions, unsafe margins, isolated final words, unbalanced rhetorical blocks,
and unintended font-down scaling. Re-render only affected one-based slide
numbers while iterating, then review the complete deck again.

## Verify the deliverable

Verify the actual file that will be delivered or imported, not only an earlier
editable candidate:

1. Run `pro-crud dump FINAL` and confirm the name, native document order,
   arrangements, stored selection, visible text, actions, and archive contents
   when applicable. Use the full `--format json` report to verify the action
   inventory and labels, canvas sizes, media references, ordered arrangement
   groups, and playlist-item arrangement UUIDs. Add `--path` when you only need
   a component's identity, child counts, or visible text. Use
   `--format protobuf-json` for action configuration or other known fields
   missing from the semantic report.
2. Render the final artifact to PDF, images, and JSON for every required
   arrangement and repeat the visual, order, and font-resolution checks.
3. Run `pro-crud validate FINAL` and investigate every structural or rendering
   diagnostic. When workspace media is involved, also run
   `pro-crud validate FINAL --workspace WORKSPACE --strict-media` and
   investigate every warning.
4. If internal archive layout or root filenames are delivery requirements,
   expand a copy into a temporary directory and inspect it without rebuilding
   the verified archive.
5. Preview every relevant Look and validate live behavior that static rendering
   cannot reproduce, including builds, transitions, timers, macros, camera,
   masks, props, messages, and other runtime layers.
