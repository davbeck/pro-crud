# Theme Documents And Template Resolution

ProPresenter themes are containers of reusable template slides. A template uses
the same `rv.data.Slide` base message as a presentation slide, but applying it is
not a normal document copy: ProPresenter resolves source content into template
element slots, transforms template geometry into a destination canvas, and
materializes or renders the result differently depending on the workflow.

This page covers three distinct operations:

1. applying a template to an existing presentation slide;
2. creating a new presentation slide from a template; and
3. using a template as an alternate per-screen output through a Look.

See [TopLevelFileFormats.md](TopLevelFileFormats.md) for archive/workspace layout
and [RenderingBehavior.md](RenderingBehavior.md) for drawing an already resolved
`rv.data.Slide`.

## Version Scope

The ProPresenter behavior on this page applies to version 21.4 (build
352583705). `pro-crud` policies are identified separately where exact native
behavior is not established.

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

The known theme fields have no theme-wide master element
collection or persisted inheritance reference. Every template slide owns its
own `base_slide`. No known field instructs a template to inherit elements from
a sibling template.

Other protobuf documents also use “template,” including playlist, message, and
CCLI templates. Those are separate from theme template slides.

## Persistent Structure

### Theme document

A raw theme document has this known structure:

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
archive-local, workspace-relative, and absolute media paths. ProPresenter
import/export resolution is not specified here for every root; a portable rewrite should
therefore preserve the theme directory, `Theme` payload, assets, and unknown URL
fields.

### Presentation document

Presentation content has a different outer structure:

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
slide UUID. Applying a template in the editor writes a resolved slide into the
presentation without a live theme reference.

### Look document

Looks are stored in `Configuration/Workspace`, not in the
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

The destination retains its `base_slide.uuid` and `base_slide.size`. Template
element geometry scales independently on each axis:

```text
x'      = x      * destination_width  / template_width
width'  = width  * destination_width  / template_width
y'      = y      * destination_height / template_height
height' = height * destination_height / template_height
```

For example, applying a 400 by 400 template to an 800 by 600 slide doubles
horizontal values and multiplies vertical values by 1.5. Populated text uses
the vertical ratio for font sizes. Scaling rules for stroke widths, shadows,
feather radii, and media crop/custom bounds are not established here.

### Content assignment and identity

The template supplies the result's element inventory, names, appearance,
geometry, and stored order. Source text supplies content:

- Exact names can match across different stored positions and unrelated UUIDs,
  including a template slot that initially contains only graphics.
- Duplicate-name text boxes can pair in corresponding stored order.
- An unmatched text box can fall back to a higher-index text-bearing slot;
  remaining text can also populate a graphics-only slot.
- Assigned slots retain the source text element's UUID. Unassigned slots retain
  the template element's UUID and have their placeholder text emptied.
- Source graphics without a content assignment are removed.

This establishes name-aware assignment, but not a complete native algorithm
for case differences, whitespace, all duplicate-name conflicts, or overflowing
source text. The deterministic `pro-crud` assignment policy is specified below.
Native remapping of build and data-link references across removed or assigned
slots is not specified here.

`pro-crud` normalizes `slide.elements[].info` from `2` to `3` during template
resolution, matching the ProPresenter 21.4 Theme import/application result for
that value. This is not a general interpretation of `info`, and does not
change element order. See [RenderingBehavior.md](RenderingBehavior.md).

### Text content and run-level attributes

Assigned text retains the source string and combines the template's base style
with distinctions within the source text. Uniform text adopts the template's
font, scaled size, and color. Exceptional runs can retain their font family,
bold, italic, underline, relative size, and varying colors. For example, a run
1.5 times the source base size remains 1.5 times the resolved base size.

Visible styling lives in Cocoa RTF; protobuf text attributes also carry box
defaults. Custom text attributes use UTF-16 ranges as described in
[RenderingBehavior.md](RenderingBehavior.md). Exact native precedence for
mixed template runs, paragraph styling, and custom-range scaling is not
specified. The resolver's supported merge policy and warnings are below.

### Actions and presentation metadata

`Template.Slide.actions[]` is separate from the presentation cue's action list.
ProPresenter exposes **Apply Media Actions with Theme Slide**. The native
inclusion and merge rules are not established here; `pro-crud` provides explicit
action-copy policies below.

## Creating A New Slide From A Template

A new slide uses the current presentation canvas, clears template placeholder
text, and keeps template names and styles. The base slide, elements, cue, and
slide action receive fresh UUIDs.

For same-aspect creation, element bounds scale to the presentation canvas while
empty text's compatibility font sizes retain the template sizes. This differs
from applying a template to populated source text. Native new-slide geometry
for an aspect-ratio mismatch is not specified here; `pro-crud` uses independent
X/Y scaling.

## Templates Used By Looks

A Look stores a reference to a theme document and template slide for each
screen. Its alternate template resolves against the audience screen canvas
without rewriting the source presentation. Assigning an alternate template
can reformat an already triggered slide without retriggering it.

Template geometry maps directly to the screen using independent horizontal
and vertical scales. A 400 by 300 template on a 3840 by 2160 screen uses scales
of 9.6 and 7.2; it does not first fit the template to the source slide canvas.
Populated text scales with the vertical ratio. Ordinary output without an
alternate template also depends on screen configuration.

The local HTTP API exposes theme slide UUIDs through `GET /v1/themes` and the
per-screen alternate UUID through `GET /v1/look/current`. In ProPresenter 21.4,
a successful `PUT /v1/look/current` can precede the corresponding change in
`GET /v1/look/current`. Confirm effective state or output after updating a Look.

## `pro-crud` Support

The file resolver models the three workflows separately while sharing
content assignment, identity handling, geometry, and attributed-text logic:

- `applyExisting` preserves the destination slide and wrapper, resolves source
  content into template slots, and uses the mixed source/template element UUID
  policy described above.
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
tool's assignment policy; native case/whitespace and overflow behavior are
not specified here.

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

`--template-actions preserve|append|replace` makes the template-action policy explicit:

- `preserve` (the default) keeps every existing cue action and copies no
  template actions;
- `append` keeps existing actions and appends identity-safe copies of all
  template actions; and
- `replace` removes existing non-slide actions, inserts identity-safe template
  actions, and retains the original presentation-slide action at its previous
  index capped by the number of copied template actions.

Fresh action, marker, nested-action, and embedded-slide identities are created,
while referenced media identities remain unchanged. These are explicit tool
policies, not claims about the ProPresenter media-action checkbox behavior.

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

## Compatibility Limits

Resolution reports identify these limits:

1. Stroke, shadow, feather, media crop/custom bounds, and several other scalar
   fields are preserved without extra resolution scaling.
2. Known intra-slide data-link UUIDs are remapped, but live data-link evaluation
   and references hidden in unknown protobuf fields are not emulated.
3. Paragraph/list/tab/kerning/baseline/shadow/stroke/highlight precedence and
   template placeholder custom-range mapping are not fully specified. The
   current implementation uses a documented base-plus-source-exceptions model,
   discards range-only entries, and preserves `originalFontSize`/
   `fontScaleFactor` values without resolution scaling.
4. A persisted Look without an alternate template currently fails explicitly;
   ordinary source-canvas aspect fit is not yet implemented. Masks and runtime
   props, messages, announcements, live video, and other external layers are
   reported but cannot be reconstructed from a presentation file alone.
5. Action copying is explicit because native media-action inclusion and merge
   order are not specified.
6. Template selection supports a specific payload inside a multi-theme archive,
   but generic component editing still targets the primary payload.
7. Direct Theme rendering/editing cannot honor the `ROOT_SHOW` root without a
   workspace. It can still use a reachable absolute URL or unambiguous
   Theme-local fallback. Successfully rebased assets are materialized portably
   for writes; unresolved assets remain warnings and are not copied. The
   transient same-name-source guard is not serialized, so a persisted unresolved
   URL can follow the destination document's normal media fallback on a later
   independent load.
8. Runtime resolution changes only the first presentation-slide action in a cue
   containing more than one and reports a warning. Persistent
   `edit apply-template` instead requires exactly one presentation-slide action.

Dry-run/template reports surface the supported geometry, media, data-link, and
unknown-field warning cases described above. They also warn when source Build
or text Delivery state will be dropped, or template state retained, but do not
yet offer an explicit precedence policy. The current implicit behavior and
support limits are documented in [TextBuilds.md](TextBuilds.md).
