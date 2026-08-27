# Theme Documents And Template Resolution

ProPresenter themes are containers of reusable template slides. A template uses
the same `rv.data.Slide` base message as a presentation slide, but applying it is
not a normal document copy: ProPresenter resolves source content into template
element slots, transforms template geometry into a destination canvas, and
materializes or renders the result differently depending on the workflow.

This note covers three distinct operations:

1. applying a template to an existing presentation slide;
2. creating a new presentation slide from a template; and
3. using a template as an alternate per-screen output through a Look.

See [TopLevelFileFormats.md](TopLevelFileFormats.md) for archive/workspace layout
and [RenderingBehavior.md](RenderingBehavior.md) for drawing an already resolved
`rv.data.Slide`.

## Evidence Status

The controlled observations in this note were made with **ProPresenter 21.4
(build 352583705) on macOS 26.5.2**. They are version-specific until repeated on
a newer release.

- **Schema fact**: represented directly by the checked-in protobuf definitions.
- **Observed in 21.4**: reproduced with controlled before/after documents or a
  stable live-output capture.
- **Interpretation**: the smallest resolver model consistent with the probes,
  but not itself persisted in the protobuf.
- **Open**: not yet isolated with a controlled ProPresenter-authored fixture.

The controlled source slide used an 800 by 600 canvas and three elements:

| Stored index | Name | Content |
| --- | --- | --- |
| 0 | `Source Primary` | Mixed RTF: a 30-point Helvetica base, a 45-point Times New Roman bold/italic/underlined red range, and a blue tail |
| 1 | `Shared` | Uniform 26-point Helvetica text, `SECOND SOURCE` |
| 2 | `Source Only` | A blue shape with no source text |

The main template used a 400 by 300 canvas and three independently generated
element UUIDs:

| Stored index | Name | Content |
| --- | --- | --- |
| 0 | `Shared` | Uniform 20-point yellow Courier New placeholder text |
| 1 | `Template Secondary` | Uniform 16-point cyan Courier New placeholder text |
| 2 | `Template Only` | A magenta shape with no placeholder text |

Variants changed element names/counts and changed the template canvas to 400 by
400. Look output was captured through a 3840 by 2160 Syphon audience screen.
Disposable documents used unique internal theme names because ProPresenter may
otherwise retain cached theme UI state after reimport.

Official workflow documentation provides useful product-level context:

- [Themes in ProPresenter](https://support.renewedvision.com/hc/en-us/articles/11910559859603-Themes-in-ProPresenter)
  describes applying themes to slides, presentations, libraries, and Looks, and
  describes theme media actions.
- [Maintaining Text Attributes](https://support.renewedvision.com/hc/en-us/articles/22249643660947-Maintaining-Text-Attributes)
  explains that exceptional bold, italic, underline, and color can survive
  reformatting while uniform box-wide styling is supplied by the theme.
- [Using Looks to Show Different Screen Content](https://support.renewedvision.com/hc/en-us/articles/360041407174-Using-Looks-to-Show-Different-Screen-Content-in-ProPresenter)
  describes selecting an alternate presentation theme independently for each
  audience screen.

## Terminology And Non-Inheritance

- A **theme** is one `rv.data.Template.Document`, normally stored as
  `Themes/<theme-name>/Theme`.
- A **template slide** is one named `rv.data.Template.Slide` within that theme.
  It owns a `base_slide` and may own actions.
- A **source slide** is an existing presentation slide whose content is being
  reformatted.
- A **materialized slide** is the resolved `rv.data.PresentationSlide` written
  into a presentation action.
- A **Look template** is a template selected for one audience screen. It is
  resolved at output time and is not written into the source presentation.

**Schema fact.** The known theme fields have no theme-wide master element
collection or persisted inheritance reference. Every template slide owns its
own `base_slide`. The controlled resolver used the selected template's element
inventory; no known field instructs it to inherit elements from a sibling
template. A newer unknown field or another workflow would require separate
evidence.

Other protobuf documents also use “template,” including playlist, message, and
CCLI templates. Those are unrelated to theme template slides unless a focused
workflow proves an interaction.

## Persistent Structure

### Theme document

**Schema fact.** A raw theme document has this known structure:

```text
rv.data.Template.Document
  application_info
  slides[]
    rv.data.Template.Slide
      name
      base_slide: rv.data.Slide
        elements[]
        element_build_order[]
        guidelines[]
        draws_background_color
        background_color
        size
        uuid
      actions[]
```

The known `Template.Document` fields have no document UUID or display name. The
workspace folder supplies the theme name. In a `.proTheme` archive, the internal
directory containing `Theme` supplies the imported name; renaming only the
archive file does not rename the theme.

A `.proTheme` can contain more than one `*/Theme` entry, each an independent
`Template.Document`. The shared URL schema can represent theme-relative,
archive-local, workspace-relative, and absolute media paths. Exact ProPresenter
import/export resolution for every root remains open; a portable rewrite should
therefore preserve the theme directory, `Theme` payload, assets, and unknown URL
fields.

### Presentation document

**Schema fact.** Presentation content has a different outer structure:

```text
rv.data.Presentation
  cue_groups[] / arrangements[]
  cues[]
    actions[]
      rv.data.Action
        slide.presentation: rv.data.PresentationSlide
          base_slide: rv.data.Slide
          notes
          template_guidelines[]
          chord_chart
          transition
```

Theme documents do not have presentation cues, arrangements, or the cue-owned
`ACTION_TYPE_PRESENTATION_SLIDE`/`PresentationSlide` wrapper. A
`Template.Slide` may own `actions[]`, but it lacks the presentation wrapper's
notes, template guidelines, chord chart, and transition. The shared
`rv.data.Slide` type means both documents can carry the same canvas, elements,
build order, guides, background, size, and UUID fields.

The known `PresentationSlide` fields contain no source-theme path or template
slide UUID. This matches the controlled editor operations: ProPresenter wrote a
resolved slide into the presentation and did not persist a live theme reference
there.

### Look document

**Schema fact.** Looks are stored in `Configuration/Workspace`, not in the
presentation. Each `rv.data.ProAudienceLook.ProScreenLook` identifies a screen
and can store:

- `pro_screen_uuid`;
- `template_document_file_path`;
- `template_slide_uuid`;
- presentation/announcement/media/video/prop/message layer switches; and
- an optional mask UUID.

This is a real runtime reference to a theme document and template slide. It is
fundamentally different from the materialized editor result.

## Applying A Template To An Existing Slide

### Destination identity and canvas

**Observed in 21.4.** The target kept its existing `base_slide.uuid` and
`base_slide.size`. Applying the 400 by 300 template to the 800 by 600 source did
not turn the presentation into a 400 by 300 document and did not persist the
template slide UUID.

Template geometry was transformed into the target coordinate system. The 400 by
400 aspect-mismatch variant proved that X and Y are scaled independently:

```text
x'      = x      * destination_width  / template_width
width'  = width  * destination_width  / template_width
y'      = y      * destination_height / template_height
height' = height * destination_height / template_height
```

For 400 by 400 to 800 by 600, horizontal values doubled and vertical values
were multiplied by 1.5. There was no aspect fit, aspect fill, crop, centering,
or letterboxing in this editor-application path.

Template font sizes were multiplied by the vertical ratio. The 20- and 16-point
template fonts became 30 and 24 points in the 400 by 400 to 800 by 600 probe.
The 42-point default text style ProPresenter added to a graphics-only template
slot became 63 points. Stroke widths, shadows, feather radii, media crop/custom
bounds, and other scalar fields still need isolated probes.

### The template defines the output element slots

**Observed in 21.4.** The resolved slide used the template's element inventory,
names, geometry, appearance, and stored order. It was not the union of source
and template elements.

Source elements participate primarily as content providers:

- `Shared` source text was assigned to the `Shared` template slot even though
  the elements occupied different stored positions and had unrelated UUIDs.
- Renaming the source primary text to `Template Only` assigned that text to the
  template's graphics-only `Template Only` slot. Exact name correspondence was
  therefore not restricted by whether the template initially carried text.
- With two source and two template text boxes both named `Dup`, corresponding
  stored order was retained: source index 0 fed template index 0 and source
  index 1 fed template index 1.
- With a single unmatched source text box, fallback selected the higher stored
  text-bearing template slot (`Template Secondary`) before the lower `Shared`
  slot. This is consistent with a front-to-back/reverse-stored-order scan, but
  the complete algorithm remains an interpretation.
- When the only remaining template slot was a graphics-only shape, the
  remaining source text was inserted into that shape. “Text element” versus
  “shape element” is therefore a preference, not a hard type barrier in the
  unified `Graphics.Element` message.

These probes support an **interpretation** of name-aware assignment followed by
reverse-order fallback that prefers text-bearing template slots, then other
available slots. They do not yet prove case sensitivity, whitespace
normalization, global name-pass ordering, or every duplicate-name tie-break.

### Missing and extra elements

**Observed in 21.4:**

| Condition | Result |
| --- | --- |
| Source text assigned to a template slot | Template name/style/geometry with source content and source element UUID |
| Template slot receives no source content | Template element remains, its placeholder text is emptied, and its template element UUID remains |
| Source graphics-only element has no template/content assignment | Removed from the resolved slide |
| Source text falls back to a graphics-only template slot | Slot gains text, keeps template appearance/name, and receives the source text element UUID |

The sparse-source probe is especially useful: the unmatched `Shared` and
`Template Only` slots remained with their original template UUIDs, but
`TEMPLATE PRIMARY` and other sample content did not leak into the presentation.

One compatibility field was normalized. The raw controlled template's
`slide.elements[].info` values `[1, 2, 3]` became `[1, 3, 3]` in ProPresenter's
imported Theme and stayed `[1, 3, 3]` in both the existing-slide and new-slide
results. Independent duplicate-name and square-canvas variants repeated the
rewrite. The tool therefore reproduces the directly observed `2` to `3`
conversion without reordering elements. The evidence does not isolate whether
that conversion belongs to Theme import, Theme save, or application, and the
rule for zero or values above three remains open. `info` is not the source of
element paint order; see [RenderingBehavior.md](RenderingBehavior.md).

The controlled source had more elements than one template variant, but not more
text-bearing source elements than total template slots. Overflow of source text
past the complete template element count remains open.

### Element UUIDs are result provenance, not match keys

**Observed in 21.4.** All source and template UUIDs were deliberately unrelated,
yet name/order assignment still occurred. A slot that received source content
used the source element UUID. An unassigned template slot retained the template
element UUID. The existing slide UUID itself stayed unchanged.

This mixed identity policy matters for builds, data links, alternate elements,
and visibility conditions that reference element UUIDs. Their reference-remap
behavior has not yet been isolated and must not be guessed.

### Text content and run-level attributes

**Observed in 21.4.** Assigned boxes retained the source string and combined the
template's base text style with source run distinctions. The result was neither
a wholesale copy of the source RTF nor a wholesale copy of the template RTF.

A useful property-by-property model is:

```text
resolved text
  = source string and run partitioning
  + template box/base attributes
  + source attributes that are exceptional within that source box
```

The controlled output showed:

- Uniform source `Shared` text adopted the template's Courier New font, scaled
  size, and yellow color.
- In the mixed source box, ordinary Helvetica runs adopted Courier New and the
  template's scaled base size.
- The exceptional Times New Roman run retained its family, bold, italic,
  underline, and 1.5 size ratio. A 16-point template base became 32 points in
  the 400 by 300 to 800 by 600 probe, and that range became 48 points.
- Because source color varied across the box, the source gray/red/blue color map
  survived. A uniform source color in the other box did not override the
  template color. This matches the official distinction between uniform and
  exceptional text attributes.
- A graphics-only template slot received ProPresenter's default empty-text
  style first; source run distinctions were then resolved against that base.

On import, ProPresenter normalized compatibility fields but the source had no
`custom_attributes`. After template application, the resulting ASCII text had
range-only `custom_attributes` entries aligned with its effective RTF runs;
those entries were otherwise empty. This probe does not itself prove UTF-16
indexing or that ProPresenter always synthesizes one no-op entry per run. The
general UTF-16 range contract is established separately in
[RenderingBehavior.md](RenderingBehavior.md). Visible style still lived in the
Cocoa RTF, while `Graphics.Text.Attributes` carried the template-compatible box
defaults.

This means an implementation must merge attributed strings, not just copy the
first font and not just retain the old RTF bytes. It must preserve or remap
meaningful UTF-16 custom ranges when run boundaries or text change; consistent
synthesis of ProPresenter's empty range-only entries remains open.

Still open in native ProPresenter behavior:

- a template placeholder that itself contains multiple special RTF runs;
- capitalization, `original_font_size`, and `font_scale_factor` precedence and
  scaling during apply;
- paragraph/list/tab/kerning/baseline/shadow/stroke/highlight precedence;
- emoji, combining characters, malformed/stale ranges, empty strings, and
  unequal line/paragraph structure; and
- data-linked/alternate text.

### Actions and presentation-only metadata

`Template.Slide.actions[]` is separate from `base_slide`, while a presentation
cue already owns an action list. The Theme menu exposes an `Apply Media Actions
with Theme Slide` checkbox and official documentation says themes can carry
media actions.

A synthetic image-media action survived theme import, but ProPresenter
normalized its action type and did not copy it in either controlled editor path
with the checkbox enabled. Because ProPresenter did not author that action, this
is not sufficient evidence that a complete native media action is ignored.
Action copy/merge order remains **open** and needs a ProPresenter-authored media
theme fixture.

Notes, chord charts, transitions, template guidelines, builds, child builds,
reveal settings, alignment guides, and data-link reference handling likewise
need focused before/after accounting.

## Creating A New Slide From A Template

Creating a new slide is an instantiation operation; there is no source content
to assign.

**Observed in 21.4:**

- The new slide used the current presentation canvas (800 by 600), not the
  template's 400 by 300 canvas.
- Template element bounds were scaled into the presentation canvas.
- Template placeholder content was removed. The probe establishes an empty
  decoded string, not one required byte representation for that empty RTF.
  Element names and styles remained.
- The new base slide, every element, cue, and slide action received fresh UUIDs.
- Template text compatibility font sizes remained 20 and 16 in the materialized
  protobuf even though bounds doubled. This differs from applying the template
  to populated text, where effective font sizes were scaled to 40 and 32.
- The generated cue name/action label behavior was not stable enough in this
  synthetic import to generalize.

The test theme had no native media actions. The synthetic-action limitation
described above also occurred on new-slide creation, so action semantics remain
open.

## Resolution Summary

| Workflow | Destination canvas | Geometry | Text size observed |
| --- | --- | --- | --- |
| Apply to existing slide | Existing slide size | Independent X/Y template-to-slide scaling | Template base and source relative sizes scaled by destination/template height |
| Create new slide | Current presentation size | Uniform 2× scaling in the same-aspect probe; aspect mismatch open | Empty placeholder metadata kept native template font sizes |
| Look alternate template | Audience screen size | Independent X/Y template-to-screen scaling | Live output consistent with vertical template-to-screen scale |

The existing-slide aspect-mismatch probe is definitive for independent X/Y
geometry scaling. New-slide aspect mismatch still needs a separate controlled
probe even though the same transform is likely.

## Templates Used By Looks

### Runtime resolution and persistence

**Observed in 21.4.** Assigning the 400 by 300 controlled template to the 3840
by 2160 Projector screen immediately reformatted the already triggered 800 by
600 source slide. It did not require a retrigger and did not rewrite the source
presentation. The source `.pro` SHA-256 was identical while the alternate theme
was active and after the saved Look was restored.

The output used the same visible content-assignment behavior as editor apply:

- exact-name `Shared` content occupied the `Shared` template slot;
- the unmatched source primary text occupied `Template Secondary`;
- the source-only blue shape disappeared;
- the unmatched magenta `Template Only` slot appeared with no sample text; and
- uniform source styling adopted the template while mixed run distinctions
  remained visible.

This strongly supports a shared content resolver with a different destination
and persistence policy. The Look stores a path/UUID reference; the presentation
continues to store its original slide.

### Screen resolution

**Observed in 21.4.** The 400 by 300 Look template was mapped directly to the
3840 by 2160 screen:

- horizontal geometry scale: `3840 / 400 = 9.6`;
- vertical geometry scale: `2160 / 300 = 7.2`.

The captured template rectangles landed at those exact screen-relative
positions and dimensions. There was no 4:3 fit/letterbox stage for the alternate
template; the template filled the 16:9 output by independent X/Y scaling.

On the same configured screen without an alternate template, the 800 by 600
source canvas was aspect-fitted into the 3840 by 2160 output with horizontal
pillarboxing. This contrast is important: a Look alternate template targets the
screen canvas directly rather than first materializing into the source slide's
canvas and then applying the ordinary source-canvas output transform. Screen
configuration may affect the no-template path, so that baseline observation is
specific to the tested workspace.

### API observation

The local HTTP API exposes theme slide UUIDs through `GET /v1/themes` and the
per-screen alternate UUID through `GET /v1/look/current`. In this 21.4 build,
`PUT /v1/look/current` returned `204`, but the immediate `GET` still showed the
old state. The Looks editor showed the update, and a later state read reflected
it. Clients should confirm the effective state/output rather than assuming the
first read-after-write is authoritative.

### Remaining Look questions

- stale/missing theme paths, slide UUIDs, media, and screen UUIDs;
- exact matching behavior for duplicate/case/whitespace names;
- backgrounds, masks, builds, actions, transitions, data links, and animations;
- different template sizes on multiple outputs in the same Look; and
- whether editing an active theme updates output immediately or after cache
  invalidation/retrigger.

## Implemented `pro-crud` Support

The file resolver now models the three workflows separately while sharing
content assignment, identity handling, geometry, and attributed-text logic:

- `applyExisting` preserves the destination slide and wrapper, resolves source
  content into template slots, and uses the mixed source/template element UUID
  policy observed above.
- `instantiateNew` retains the requested/current presentation canvas, clears
  sample text, and creates a fresh slide/element/build/guideline/action graph.
- `runtimeLook` performs the same visible resolution in memory against either a
  requested render size or a persisted Look's audience-screen canvas. It does
  not mutate the source presentation.

The identity-safe graph copier remaps known `element_build_order`, build
element, alternate-text, alternate-fill, and element-visibility references. On
fresh-copy paths it also refreshes build, child-build, guideline, action,
playback-marker, and nested marker-action identities while retaining external
media, timer, screen, playlist, layer, and effect-preset identities.

### Implemented content and text scope

The compatibility resolver treats a source element as a content provider only
when its RTF decodes to a non-whitespace string. Source graphics and
whitespace-only text do not consume template slots. Undecodable nonempty source
RTF fails resolution rather than silently dropping content.

Its deterministic assignment policy first pairs exact, case-sensitive,
nonempty names in source/template stored order. Remaining source text is
processed in source order and takes the highest-index remaining text-bearing
slot, then the highest-index remaining slot of any kind. Source text that
outnumbers the complete template inventory is removed and reported. This is the
tool's concrete interpretation of the probes; native case/whitespace and
overflow behavior remain open.

For `instantiateNew`, and for an unfilled slot in `applyExisting` or
`runtimeLook`, the implementation writes a canonical Cocoa RTF document whose
decoded string is empty. This is deliberately not a zero-byte `rtf_data`
sentinel. It clears custom ranges and, when the template element did not
already contain a `Text` message, installs the tool's explicit compatibility
defaults: font name `HelveticaNeue`, family `Helvetica Neue`, size 42, centered
paragraph alignment, 84-point default tabs, line-height multiple 1, and an
opaque white solid text fill. It also initializes empty list,
underline/strikethrough, standardized-superscript, chord-color, and transform
delimiter fields. New-slide metadata remains at its template/default size;
unfilled apply/Look font metadata is multiplied by the vertical destination
scale. The Cocoa-generated empty RTF bytes and these fallback values are
authoring choices, not a claim that native ProPresenter requires one specific
byte representation for empty RTF.

Assigned text starts with the template RTF's first-run/base attributes, or the
same default metadata for a graphics-only slot. The resolver preserves source
font-family and bold/italic differences relative to the source's modal font,
relative run sizes, and properties whose values vary within the source box. It
does not claim complete native precedence for every Cocoa attribute.

Meaningful source `custom_attributes` are copied using UTF-16 ranges, clipped
to the unchanged source string, and dropped if their clipped range is empty.
Range-only entries are discarded, and meaningful template placeholder ranges
are not mapped onto replacement content. `originalFontSize` and
`fontScaleFactor` values are currently preserved without resolution scaling;
the report warns that this policy is compatibility-preserving but not proven to
match native template application. Complete replacement performed by
`edit set-text` with `--text`, `--rtf`, or `--rtf-file` remains a different
operation and clears prior custom attributes.

### Apply to an existing cue

Use `edit apply-template` with a cue component path:

```sh
pro-crud edit apply-template Presentation.pro \
  --path '/cues[uuid=…]' \
  --theme Theme.proTheme \
  --template 'Conflict Template' \
  --dry-run
```

`--dry-run` emits a JSON report without writing. The report includes the
source/template/result UUID for every assignment, match reason, removed source
elements, unfilled slots, X/Y/font scale, per-run style provenance, and
compatibility warnings. Resolution requires the selected cue to contain
exactly one presentation-slide action. Mutating application replaces only
`PresentationSlide.base_slide`; notes, template guidelines, chord chart,
transition, cue UUID, slide-action UUID, label, and unrelated cue metadata stay
in place.

`--template-actions preserve|append|replace` makes the otherwise unproven
template-action decision explicit:

- `preserve` (the default) keeps every existing cue action and copies no
  template actions;
- `append` keeps existing actions and appends identity-safe copies of all
  template actions; and
- `replace` removes existing non-slide actions, inserts identity-safe template
  actions, and retains the original presentation-slide action at its previous
  index capped by the number of copied template actions.

Fresh action, marker, nested-action, and embedded-slide identities are created,
while referenced media identities remain unchanged. These are explicit tool
policies, not claims about the still-open ProPresenter media-action checkbox
contract.

### Create and add

`create presentation --theme` and `edit add-slide --theme` use
`instantiateNew`. Both accept `--theme-document` for an archive containing more
than one `Theme` payload and `--include-template-actions` for an explicit action
copy. Without that flag, new cues omit template actions; with it, fresh copies
are appended after the generated presentation-slide action. Theme-relative
media that can be resolved against the selected Theme's resource directory is
rebased to an exact file URL. A mutating raw-document operation copies that
asset beside the destination `.pro`, choosing a collision-safe filename, while
archive editing copies it into the archive workspace; both persist a portable
relative URL. An unresolved asset is not copied and remains a material warning.
Materialization fails instead of silently choosing when one nonempty media UUID
would identify different files, or when a previously resolved source disappears
before the write.

`ROOT_CURRENT_RESOURCE` is resolved against the selected Theme directory.
`ROOT_SHOW` requires a user-workspace root; it is available when resolving a
persisted Look, but a direct standalone `--theme` command has no show root to
infer. Direct resolution can still use a reachable stored absolute URL or an
unambiguous asset inside the Theme resource roots; otherwise it reports the
reference unresolved. It never falls back to a same-named source-presentation
asset.

### Direct template rendering

Every render format consumes the same transiently resolved documents:

```sh
pro-crud render Presentation.pro \
  --theme Theme.proTheme \
  --template 'Conflict Template' \
  --size 1920x1080 \
  --format png,pdf,json \
  --template-report resolution.json
```

Without `--size`, each source slide keeps its canvas. With `--size`, the
template targets that canvas directly using Look-style independent X/Y scaling.
`--include-template-actions` is available but off by default; when enabled it
appends fresh action copies after each cue's existing actions. Absolute rebased
template media is resolved before source-document basename fallbacks, avoiding
wrong-asset selection when the two roots contain equal filenames.

When one or more `--slide` values are supplied, only those one-based slides are
template-resolved, validated, rendered, and included in `--template-report`.
Unselected cues remain untouched in the transient copy, so an invalid canvas or
RTF on an unselected cue does not make a selected-slide render fail. Without
`--slide`, every ordered cue is considered.

### Persisted Look rendering

Static file rendering can decode `Configuration/Workspace`, select an audience
Look and screen by exact name or UUID, follow the stored theme path and template
slide UUID, and resolve against the union of that logical screen's output
bounds:

```sh
pro-crud render Presentation.pro \
  --workspace Workspace \
  --look 'Stream Match' \
  --screen Projector
```

The Look and audience screen must each match exactly one name or UUID, and the
Look must contain exactly one mapping for that screen. Multi-child canvases
require finite positive bounds for every child and use their union. A
single-child screen can fall back to its configured output-mode size; an
invalid or renderer-oversized canvas fails instead of being guessed.

This is a static equivalent of the alternate-template portion of a Look. It
does not contact or mutate a running ProPresenter instance. It uses
`runtimeLook`, resolves only selected slides when `--slide` is present, and
never includes template actions. The Look's persisted background/foreground
switches are reported but are not yet separated in the file renderer.

## Remaining Tool Gaps

The resolver intentionally reports instead of inventing behavior where the
experiments are incomplete:

1. Stroke, shadow, feather, media crop/custom bounds, and several other scalar
   fields are preserved without extra resolution scaling.
2. Known intra-slide data-link UUIDs are remapped, but live data-link evaluation
   and references hidden in unknown protobuf fields are not emulated.
3. Paragraph/list/tab/kerning/baseline/shadow/stroke/highlight precedence and
   template placeholder custom-range mapping need more native fixtures. The
   current implementation uses a documented base-plus-source-exceptions model,
   discards range-only entries, and preserves `originalFontSize`/
   `fontScaleFactor` values without resolution scaling.
4. A persisted Look without an alternate template currently fails explicitly;
   ordinary source-canvas aspect fit is not yet implemented. Masks and runtime
   props, messages, announcements, live video, and other external layers are
   reported but cannot be reconstructed from a presentation file alone.
5. Action copying is explicit because native media-action inclusion and merge
   order still lack an authored fixture.
6. Template selection supports a specific payload inside a multi-theme archive,
   but generic component editing still targets the primary payload.
7. Compact ProPresenter-authored before/after and Look fixtures still need to be
   checked into `Fixtures/`; the automated suite currently combines synthetic
   graph/CLI tests with the controlled local 21.4 comparison.
8. Direct Theme rendering/editing cannot honor the `ROOT_SHOW` root without a
   workspace. It can still use a reachable absolute URL or unambiguous
   Theme-local fallback. Successfully rebased assets are materialized portably
   for writes; unresolved assets remain warnings and are not copied. The
   transient same-name-source guard is not serialized, so a persisted unresolved
   URL can follow the destination document's normal media fallback on a later
   independent load.
9. Runtime resolution changes only the first presentation-slide action in a cue
   containing more than one and reports a warning. Persistent
   `edit apply-template` instead requires exactly one presentation-slide action.

Dry-run/template reports surface the supported geometry, media, data-link, and
unknown-field warning cases described above. They also warn when source Build
or text Delivery state will be dropped, or template state retained, but do not
yet offer an explicit precedence policy. The current implicit behavior and
proposed policies are documented in [TextBuilds.md](TextBuilds.md).

## Focused Remaining Experiments

1. ProPresenter-authored template media actions with the checkbox on/off for
   existing slides, new slides, and Looks.
2. Builds, build order, alternate text/fill, data links, and visibility UUID
   references across matched/removed/unfilled slots.
3. More source text boxes than total template element slots.
4. Case/whitespace/empty names, crossed name/order collisions, and duplicate
   names across text-bearing and graphics-only slots.
5. Mixed template RTF, paragraph boundaries, Unicode/emoji, and all
   ProPresenter-specific custom attribute kinds.
6. Aspect-mismatched new-slide creation and scaling of effects/media geometry.
7. Missing/stale Look references and live theme cache invalidation.
