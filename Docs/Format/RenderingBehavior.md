# Rendering Behavior

These notes describe how persisted presentation data maps to ProPresenter slide-image exports. They are based on observed documents and generated probes that were imported into ProPresenter and exported back to images.

## Canvas And Coordinates

Slide size is stored on `slide.presentation.base_slide.size`. Observed audience exports commonly use a 3840 by 2160 canvas.

Bitmap and PDF rendering rejects non-finite canvas sizes, dimensions smaller
than one pixel, and canvases larger than 100 million pixels before converting
dimensions to integers or allocating backing storage.

Element bounds are in slide-space coordinates. For exported slide images, those bounds behave as top-left-origin rectangles. AppKit/CoreGraphics text drawing uses bottom-left coordinates, so renderers need to convert rectangles before drawing attributed strings.

Stored color components map directly to sRGB components in tested PNG exports. Using AppKit's calibrated color space changes the component values and does not match the exported fills.

Untouched pixels in tested PNG exports are transparent. The focused `Transparent background` reference slide isolates this behavior. Those fields should not be composited into a basic PNG render without a fixture proving that they paint for that export workflow.

An element opacity of exactly zero hides a shape element's fill and stroke.
For text elements, ProPresenter applies element opacity to the box appearance
but still draws the RTF glyphs at full opacity. Generated text should be hidden
or removed rather than relying on element opacity to hide its glyphs. Generated
visible shape elements should write an explicit opacity of one.

Full-slide media often has a natural size equal or very close to the slide size. If `custom_image_bounds` is empty, drawing the media to the full canvas matches the observed framing for simple background media.

When a media URL has both an absolute source path and a matching archive-local
filename, renderers should resolve the archive-local file first. The absolute
path is a portability fallback for documents whose media was not embedded.

## Theme And Look Resolution Precedes Drawing

A theme is not an extra paint layer over a presentation slide. Applying a
template first resolves source content into the template's element slots and
produces either a materialized presentation slide or a per-screen live slide.
Only that effective `rv.data.Slide` is then painted.

Controlled ProPresenter 21.4 probes found independent horizontal and vertical
template-to-destination scaling, name-aware content assignment, removal of
source-only elements, empty unmatched template placeholders, and a run-aware
text merge. A Look targets the output screen directly and leaves the source
presentation unchanged. See [ThemeDocuments.md](ThemeDocuments.md) for the
complete observed contract and remaining unknowns.

The file resolver represents an empty template placeholder with a canonical
Cocoa RTF document that decodes to an empty string, not with zero bytes. It also
adds the known 42-point Helvetica Neue/default paragraph metadata when a
graphics-only template slot must become text-capable: centered alignment,
84-point default tabs, line-height multiple 1, and opaque white text fill. This
is an explicit authoring policy; the ProPresenter probes establish the absence
of visible placeholder content, not a single required empty-RTF byte sequence.

## Build And Delivery State

The current renderer does not evaluate object Build Ins, Build Outs, text
Delivery, or Build Order. It draws the stored, unanimated composition: every
non-hidden element eligible for normal painting is considered regardless of
its scheduled build state. This is neither an initial state nor necessarily a
completed state, because a Build In can initially hide an object and a Build
Out can remove it before playback completes.

Future stable-state rendering must resolve start/grouping rules, delays, and
text segmentation. The current behavior should remain explicitly named
`stored`; playback terms such as `initial`, `advance:N`, and `completed` should
be introduced only with fixture-backed semantics. See
[TextBuilds.md](TextBuilds.md) for the persistent graph, evidence, and proposed
experiments.

## Element Paint Order

Slide elements paint in reverse stored order. The focused `Reverse stored
element paint order` fixture stores blue, orange, and violet at source indices
`[0, 1, 2]` with `info` values `[0, 2, 1]`; ProPresenter paints them violet,
orange, then blue (`[2, 1, 0]`). This disproves descending-`info` sorting.
Preserve `slide.elements[].info` as unresolved compatibility metadata, but do
not use it to reorder elements.

## Action Composition

Presentation slides are represented as `ACTION_TYPE_PRESENTATION_SLIDE` actions. Media backgrounds can be represented either as separate `ACTION_TYPE_MEDIA` actions or as media fills on slide elements.

The checked-in renderer targets **Export → Slide Images with “without slide
background color”**, not a configured live Audience Screen. Therefore it clears
the canvas, draws renderable media actions below slide elements, and deliberately
does not paint `Presentation.background` or
`Slide.draws_background_color/background_color`. The native `Reverse stored
element paint order` export has an enabled opaque gray slide background but
transparent pixels outside its elements; it is the regression guard for this
export-mode choice.

This is narrower than ProPresenter's [fixed live output-layer
model](https://support.renewedvision.com/hc/en-us/articles/13634000690323-ProPresenter-Output-Layers),
where background media can be covered by enabled presentation/slide colors and
foreground media remains visible above them. A future live-output renderer must
make its output/screen configuration explicit, then model background media,
presentation and slide colors, foreground media, elements, video input,
props/messages/masks, and screen color in their documented order. It must not
silently change the portable slide-image export behavior to approximate that
stack.

Presentation and slide **gradient** backgrounds also remain unrendered until a
focused ProPresenter export establishes their geometry and stop semantics.
[Background effects](https://support.renewedvision.com/hc/en-us/articles/10911852908819-Using-Background-Effects-in-ProPresenter)
operate on the live media/video-input layers, so a basic static renderer must
not substitute a local blur or invert for them without that output context.

Other rendering rules:

- Image fills on slide elements participate in normal element drawing.
- Macro, timer, and audience-look actions do not necessarily draw pixels in a basic audience PNG export, though they can affect routing, state, or dynamic data in broader workflows.

The action list still needs to be preserved exactly for editing and round-tripping. Rendering order is a view of the action semantics, not a rewrite rule for the persisted document.

## Text Source And Attributes

ProPresenter stores text as Cocoa RTF in `Graphics.Text.rtf_data`, with additional protobuf metadata in `Graphics.Text.Attributes`.

Tested behavior:

- Fully styled RTF determines visible font, size, color, and run-level styling.
- Before decoding RTF, locally installed faces referenced by its font table need
  to be registered with the rendering process. Some command-line AppKit
  processes do not discover fonts present in the standard user or local font
  directories and silently substitute Helvetica. When a directory contains a
  font family, its faces should be registered from that same directory so
  duplicate installations do not mix incompatible versions.
- RTF run-level bold, italic, underline, strikethrough, foreground color, background/highlight color, stroke, shadow, kerning, baseline offset, and paragraph styling are preserved by ProPresenter.
- Box-level attributes such as capitalization do not globally replace fully styled RTF content in tested documents.
- Custom capitalization ranges apply all-caps and word-initial capitalization transforms while preserving the RTF styling within those ranges. Title case leaves minor words such as the conjunction `and`, the preposition `of`, and the article `a` lowercase, while start case capitalizes every word. The focused capitalization fixture applies none, all caps, title case, and start case to identical text ranges in one text box.
- Custom attributes are UTF-16 ranges into the RTF string. ProPresenter clips
  an oversized `originalFontSize` range to the overlapping text and applies
  that size even when the range extends beyond the string. Negative-start,
  reversed, and past-end ranges did not remove inline bold in the focused
  Helvetica probes. A standalone `fontScaleFactor` of 0.5 or 2.0 did not change
  the tested output; paired scale metadata still needs a separate probe.
- Complete text replacement must clear all prior custom attributes. The
  renderer reports stale out-of-bounds ranges because imported behavior can
  depend on the attribute kind and font state instead of admitting one safe
  normalization rule.
- Template application is not complete text replacement. The resolver keeps
  meaningful source custom attributes at clipped UTF-16 ranges, discards empty
  and range-only entries, and ignores placeholder-specific template ranges.
  `originalFontSize` and `fontScaleFactor` values are retained without applying
  the template's resolution scale and produce an explicit warning because
  native precedence/scaling remains unproven.
- Sparse or minimal RTF should not be treated as proof that protobuf text attributes alone define visible text. That fallback needs separate verification.

Generated text should use platform-native Cocoa RTF when targeting ProPresenter compatibility.

## Text Layout

`Graphics.Text.vertical_alignment` is applied within the text element's bounds after measuring the attributed string. Top, middle, and bottom alignment are independent of RTF paragraph alignment.

ProPresenter lays out text with a 5-point inset on every edge. In the flipped AppKit bitmap context, bottom alignment must be inverted to preserve ProPresenter's visual direction. Cocoa RTF shadow offsets are already interpreted in the matching direction by AppKit and should be preserved.

Paragraph alignment, line spacing, tabs, and indents encoded in Cocoa RTF are preserved. Literal bullet or numbered-list markers in the RTF string render as normal text. The authoritative `Rendering Edge Cases` and `List Indentation` fixtures establish that native lists use both paragraph `textLists` metadata and RTF `\\listtext` destinations. AppKit otherwise discards that destination, so the renderer restores it as ordinary RTF before decoding. This preserves the marker's own styling and its native tab sequence, including depth-specific nested-list indentation. For lists without a native destination, the renderer synthesizes a marker and two tabs as a compatibility fallback.

Alternate-text data links resolve the source by element UUID, retain the target element's RTF formatting and layout, and replace the target content using the stored transform. `NONE` retains line returns and `REMOVE_LINE_RETURNS` replaces them with spaces. The renderer retains the native outline treatment. `ONE_WORD_PER_LINE` and `ONE_CHARACTER_PER_LINE` still need a controlled ProPresenter probe; until then they safely retain the stored target text. The focused alternate-text export is a known pixel-parity issue because mixed scale-to-fit and link-outline positioning have not yet been fully reconciled, while structural and effective-rendering tests verify content substitution and target formatting.

`Graphics.Text.scale_behavior` controls font resizing:

| Value | Observed local-renderer behavior | ProPresenter verification |
| --- | --- | --- |
| `SCALE_BEHAVIOR_NONE` | Draw without font scaling; overflowing content expands around the box center | Not yet covered by the focused fixture. |
| `SCALE_BEHAVIOR_SCALE_FONT_DOWN` | Shrink to fit only | Common in exported presentations; shrink-to-fit behavior is required. |
| `SCALE_BEHAVIOR_SCALE_FONT_UP` | Grow to the largest fitting proportional scale when original text fits | Not yet covered by the focused fixture. |
| `SCALE_BEHAVIOR_SCALE_FONT_UP_DOWN` | Grow or shrink to the largest fitting proportional scale | Not yet covered by the focused fixture. |
| `SCALE_BEHAVIOR_ADJUST_CONTAINER_HEIGHT` | Preserve font sizes and adjust the drawing container from its top edge | Verified by the focused contract and expand fixtures. |

For stroked text, the shadow follows the combined fill-and-stroke silhouette.
Renderers that split text into separate stroke and fill passes need one shadow
pass behind both visible passes rather than dropping or duplicating the shadow.

When font scaling is applied to mixed-size RTF, ProPresenter scales runs proportionally instead of flattening all runs to one size. Fit measurement must use an AppKit text container so clipped glyph ranges are not accepted as fitting text.

## Line Masks

`text_line_mask` is a oneof on `Graphics.Element`. Its presence changes fill behavior for text-related elements:

- Enabled line masks render the element fill as per-line bars behind text instead of as a full element rectangle.
- `LINE_MASK_STYLE_MAX_LINE_WIDTH` uses a single bar spanning the complete
  multiline text block, with the width of its widest line. It does not create a
  separate bar for each wrapped line.
- Some helper elements carry a present but default line-mask value with empty RTF text. These act as helpers and should not render their fill as a full rectangle.
- In a line-width mask, `widthOffset` is the total added width rather than padding on both sides. For text with a positive line-height multiple, ProPresenter's bar height excludes the additional multiple-leading. When a one-line bar plus `heightOffset` would exceed its text box, the bar is constrained to that box's height.

The `Rendering Edge Cases` fixture verifies line-width masks at height offsets 0, 10, 55, and 60. Full-width and max-line-width masks with nonzero height offsets remain unproven.

## Shape Feathering

Enabled shape feathering is an inside alpha feather that applies to the combined fill and stroke appearance. In the focused Shape Effects fixture, ProPresenter first insets the alpha mask, then applies a Gaussian falloff; pixels outside the original shape remain transparent. The stored radius is normalized to the smaller element dimension, so the renderer converts it to canvas points before producing the feathered mask.

## Video Frames

Video media actions can render a thumbnail or representative frame in exported slide images. Extracting the first video frame is not always correct; one tested bumper export matched an early visible frame several seconds into the clip rather than a black first frame.

Exact frame selection, cached thumbnail behavior, and export-time video state should be treated as a separate rendering experiment.

## Acceptance Strategy

Rendering validation should assert:

- decoded slide count and output dimensions
- non-empty rendered output
- comparison against ProPresenter-exported images with an explicit tolerance

Strict pixel parity is hard because of font availability, text antialiasing, shadows, stroke rasterization, feathering, line-mask geometry, and video frame selection. Toleranced image comparisons are appropriate until each source of variance has a dedicated focused example.

## Arrangement Resolution

Arrangement resolution is a cue-sequencing step that occurs before template or
Look resolution and before drawing. An arrangement appends each referenced cue
group's cues in order. Repeated group references therefore create repeated cue
occurrences, omitted groups contribute no cues, and a valid empty arrangement
resolves to an empty sequence. This behavior describes the file renderer; the
remaining ProPresenter export comparisons are tracked in
[Experiments.md](Experiments.md).

Without an explicit option, the renderer uses the playlist item's arrangement
UUID, then the presentation's stored selected arrangement, then Master/native
order. `--arrangement native`, `--arrangement selected`, or an exact UUID
overrides that fallback. `selected` requires a stored selected arrangement.

Arrangement selection changes effective occurrence order, not presentation
component paths. A cue repeated by an arrangement has a separate zero-based
render `index` for each occurrence, while its layers keep component paths based
on the cue's native document identity. Effective-rendering JSON includes the
resolved arrangement's `name`, `uuid`, and canonical `path`; the arrangement
value is absent for Master.

## Effective Rendering JSON

`pro-crud render INPUT --format json` writes a structured description of the
same effective values consumed by the image and PDF renderer. Presentations and
slides use effective presentation order. Each slide's `layers` are ordered
back-to-front: renderable media actions first, followed by visible slide
elements in paint order. Bounds use a bottom-left coordinate system, matching
the renderer after converting ProPresenter's stored top-left rectangles.

Each grouped slide also includes `cueGroup` with the local group's `name`,
`uuid`, and stable canonical `path`. In Master/native output,
`arrangementOccurrenceIndex` is absent. In arranged output it is the zero-based
position of that group occurrence in the arrangement, so repeated occurrences
of the same group retain the same UUID and path but have distinct occurrence
indices. An ungrouped Master cue has no `cueGroup` value.

For schema-version compatibility, a slide element layer's JSON `zOrder` field
currently exposes the raw nonzero `slide.elements[].info` value. It is metadata,
not the rule used to order `layers`; `sourceIndex` identifies the original
stored position.

Text entries include the transformed plain text, effective Cocoa RTF, resolved
attribute runs, content and drawing bounds, line count, and font scale. The
effective RTF is generated after the renderer applies RTF styling, custom
capitalization, list markers, font normalization, superscript handling, shadow
fallback, text-box margins and alignment, and scale-to-fit. This keeps the JSON
description and bitmap rendering on one text-layout path.

The JSON is intentionally sparse. Omitted numeric style values default to zero;
omitted opacity, color alpha, and font scale default to one; and omitted text
settings use their no-op enum cases. Empty margins, offsets, dash patterns, and
paragraph styles are omitted entirely. Structural indices remain explicit even
when zero because they identify slide and layer order.

## Preview Outputs

`render` accepts comma-delimited formats, an optional arrangement selection,
and repeated one-based slide numbers:

```sh
pro-crud render deck.probundle \
  --arrangement '9EF1E828-DC80-425B-86A3-23389BE0F9CD' \
  --format pdf,png,json \
  --slide 2 \
  --slide 5 \
  --output Preview
```

`--slide` addresses the effective arranged sequence when an arrangement is in
use and the Master/native sequence otherwise. With multiple formats, `--output`
is a directory. Image files retain those effective slide numbers (`2.png` and
`5.png` in this example),
while PDF and JSON files use the input's base name (`deck.pdf` and `deck.json`).
The PDF contains only the selected slides, and JSON retains their original
zero-based structural `index` values. For themes and playlists, each selected
slide number is applied within every rendered presentation's effective
sequence.

A single format keeps the existing output behavior: images use an output
directory, while PDF and JSON use an output file. Without `--slide`, all slides
are rendered.

## Template And Look Resolution

`render` can resolve an external Theme template onto every selected source
slide before any format-specific output runs:

```sh
pro-crud render deck.pro \
  --theme Series.proTheme \
  --template 'Lower Third' \
  --size 1920x1080 \
  --format png,pdf,json \
  --template-report resolution.json
```

Without `--size`, each slide's stored canvas is the destination. `--size`
instead models an alternate Look template targeting an output canvas directly.
The resolver uses independent horizontal and vertical geometry scales and the
vertical scale for populated text. PNG, PDF, and effective JSON all consume the
same resolved in-memory presentation, so format selection cannot change
template assignment. The source file is never rewritten.

If `--slide` is present, template resolution and its validation are restricted
to those one-based selected slides. The template report likewise contains only
selected slides; unselected cues remain unchanged in the transient document.
Without `--slide`, every ordered cue is resolved. Runtime resolution uses the
first presentation-slide action when a cue has several and reports that limit.

`--template-report` is distinct from effective-rendering JSON. It describes
how the materialized view was produced: source/template/result element UUIDs,
name or fallback match reason, removed and unfilled elements, geometry/font
scales, text-run provenance, and unsupported-field warnings.

A persisted audience Look can supply both the template and canvas:

```sh
pro-crud render deck.pro \
  --workspace '/path/to/UserWorkspace' \
  --look 'Stream Match' \
  --screen Projector
```

This reads `Configuration/Workspace`, follows the selected screen mapping's
theme path and template slide UUID, and uses the logical audience screen's
combined bounds. It models the alternate-template part of a Look only. A Look
without an alternate template fails explicitly, and runtime masks, props,
messages, announcements, live video, and other external layers are reported as
unsupported because they are not present in the source document. Persisted
background/foreground switches are reported but not separated by the file
renderer, and Look rendering does not copy template actions.

Theme media is resolved against its Theme origin before source-document
basename fallback. `ROOT_CURRENT_RESOURCE` uses the Theme directory.
`ROOT_SHOW` can be resolved when the persisted Look supplies a user-workspace
root. Direct `--theme` rendering has no show root, although it can still use a
reachable stored absolute URL or an unambiguous asset in the Theme resource
roots. Otherwise the media is reported as unresolved. An unresolved template
reference is not allowed to borrow an equal-named source asset.
