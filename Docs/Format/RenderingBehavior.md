# Rendering Behavior

This page describes how persisted presentation data maps to slide-image exports
and how `pro-crud` renders that data. Native behavior described here is scoped
to ProPresenter 21.4; renderer policies and compatibility limits are identified
separately.

## Native 22 Presentation Inputs

For schema-9 local/native snapshots, select an exact shared Presentation UUID:

```sh
pro-crud render /exact/native/workspace --native-stream PRESENTATION_UUID \
  --output /separate/render-output
```

The reader materializes a transient interchange view from retained native
history, with native cue/group/arrangement/build ordering resolved. All existing
render formats, slide selection, arrangement selection and supported Theme
options apply. Input history is read-only. An explicit output is required;
output and template reports must be outside source workspace roots and cannot
replace their parent directories. Native schema-1 local image and video media
can be previewed from exact file locators. The selected SourceInfo takes
precedence over FileProperties and the root URL; relative paths require the
selected workspace or archive resource root. Native sources never fall back to
a same-basename file or a superseded locator. Missing files fail before
replacing output. The preview preserves source occurrence/asset identities and
history; it does not qualify media editing or packaging.

Native previews support SDR/unknown color metadata, straight/unspecified alpha
and the existing static image/video drawing behavior. HDR, premultiplied-alpha
metadata, blur, provider associations, live/web/HLS sources, unknown media
fields and other identity schemas return explicit errors. Video uses its native
type and stored thumbnail position (five seconds for the default negative
position), rather than running transport or audio. These previews retain the
existing image-sampling and video-frame comparison limitations; pixel-exact
native media rendering is not claimed. Static rendering retains its existing
runtime-feature limitations.

HLS actions and fills produce `rendering.unsupported-runtime-media`, including
media-only cues and sources without native asset identities. Static rendering
does not fetch the stream or use superseded file locators as a preview.

Use `--workspace ROOT --look LOOK_UUID --screen SCREEN_UUID` with this input to
apply a supported media-free native Look. When the source and Look workspace
are the same root, Presentation, shared/client configuration and selected Theme
are read from the same consistent snapshot. No running app, API, or Cloud
connection is required.

## Canvas And Coordinates

Each slide stores its canvas dimensions in
`slide.presentation.base_slide.size`. Use those dimensions rather than assuming
a fixed resolution.

`pro-crud` bitmap and PDF rendering rejects non-finite canvas sizes, dimensions smaller
than one pixel, and canvases larger than 100 million pixels before converting
dimensions to integers or allocating backing storage.

Element bounds are in slide-space coordinates. For exported slide images, those bounds behave as top-left-origin rectangles. AppKit/CoreGraphics text drawing uses bottom-left coordinates, so renderers need to convert rectangles before drawing attributed strings.

Stored color components map directly to sRGB components in tested PNG exports. Using AppKit's calibrated color space changes the component values and does not match the exported fills.

Untouched pixels are transparent in PNG slide-image exports with slide
background color disabled. The renderer preserves that transparency.

An element opacity of exactly zero hides a shape element's fill and stroke.
For text elements, ProPresenter applies element opacity to the box appearance
but still draws the RTF glyphs at full opacity. Generated text should be hidden
or removed rather than relying on element opacity to hide its glyphs. Generated
visible shape elements should write an explicit opacity of one.

Full-slide media often has a natural size equal or very close to the slide size. If `custom_image_bounds` is empty, drawing the media to the full canvas is the renderer policy for simple background media.

For legacy-style media, when a URL has both an absolute source path and a matching archive-local
filename, renderers should resolve the archive-local file first. The absolute
path is a portability fallback for documents whose media was not embedded.

## Theme And Look Resolution Precedes Drawing

A theme is not an extra paint layer over a presentation slide. Applying a
template first resolves source content into the template's element slots and
produces either a materialized presentation slide or a per-screen live slide.
Only that effective `rv.data.Slide` is then painted.

ProPresenter 21.4 uses independent horizontal and vertical
template-to-destination scaling, name-aware content assignment, removal of
source-only elements, empty unmatched template placeholders, and a run-aware
text merge. A Look targets the output screen directly and leaves the source
presentation unchanged. See [ThemeDocuments.md](ThemeDocuments.md) for the
supported behavior and compatibility limits.

The file resolver represents an empty template placeholder with a canonical
Cocoa RTF document that decodes to an empty string, not with zero bytes. It also
adds the known 42-point Helvetica Neue/default paragraph metadata when a
graphics-only template slot must become text-capable: centered alignment,
84-point default tabs, line-height multiple 1, and opaque white text fill. This
is an explicit authoring policy; empty placeholders have no visible content, but their exact RTF byte
representation is not prescribed.

## Build And Delivery State

The current renderer does not evaluate object Build Ins, Build Outs, text
Delivery, or Build Order. It draws the stored, unanimated composition: every
non-hidden element eligible for normal painting is considered regardless of
its scheduled build state. This is neither an initial state nor necessarily a
completed state, because a Build In can initially hide an object and a Build
Out can remove it before playback completes.

See [TextBuilds.md](TextBuilds.md) for the persistent graph and build-support
limits.

## Element Paint Order

Slide elements paint in reverse stored order. Preserve
`slide.elements[].info` as compatibility metadata; it does not determine paint
order and its full meaning is not specified.

## Action Composition

Presentation slides are represented as `ACTION_TYPE_PRESENTATION_SLIDE` actions. Media backgrounds can be represented either as separate `ACTION_TYPE_MEDIA` actions or as media fills on slide elements.

The checked-in renderer targets **Export → Slide Images with “without slide
background color”**, not a configured live Audience Screen. Therefore it clears
the canvas, draws renderable media actions below slide elements, and deliberately
does not paint `Presentation.background` or
`Slide.draws_background_color/background_color`.

ProPresenter's [live output layers](https://support.renewedvision.com/hc/en-us/articles/13634000690323-ProPresenter-Output-Layers)
have different composition rules: enabled presentation/slide colors can cover
background media, while foreground media remains above them. Static file
rendering does not reproduce the complete configured Audience Screen stack.
Presentation and slide gradient backgrounds are also unrendered.
[Background effects](https://support.renewedvision.com/hc/en-us/articles/10911852908819-Using-Background-Effects-in-ProPresenter)
operate on live media/video-input layers and are not simulated as local shape
effects by the static renderer.

Other rendering rules:

- Image fills on slide elements participate in normal element drawing.
- Macro, timer, and audience-look actions do not necessarily draw pixels in a basic audience PNG export, though they can affect routing, state, or dynamic data in broader workflows.

The action list still needs to be preserved exactly for editing and round-tripping. Rendering order is a view of the action semantics, not a rewrite rule for the persisted document.

## Text Source And Attributes

ProPresenter stores text as Cocoa RTF in `Graphics.Text.rtf_data`, with additional protobuf metadata in `Graphics.Text.Attributes`.

Text rendering follows these rules:

- Fully styled RTF determines visible font, size, color, and run-level styling.
- Before decoding RTF, locally installed faces referenced by its font table need
  to be registered with the rendering process. Some command-line AppKit
  processes do not discover fonts present in the standard user or local font
  directories and silently substitute Helvetica. When a directory contains a
  font family, its faces should be registered from that same directory so
  duplicate installations do not mix incompatible versions.
- RTF run-level bold, italic, underline, strikethrough, foreground color, background/highlight color, stroke, shadow, kerning, baseline offset, and paragraph styling are preserved by ProPresenter.
- Box-level attributes such as capitalization do not globally replace fully styled RTF content in tested documents.
- Custom capitalization ranges apply all-caps and word-initial capitalization transforms while preserving the RTF styling within those ranges. Title case leaves minor words such as the conjunction `and`, the preposition `of`, and the article `a` lowercase, while start case capitalizes every word.
- Custom attributes are UTF-16 ranges into the RTF string. ProPresenter clips
  an oversized `originalFontSize` range to the overlapping text and applies
  that size even when the range extends beyond the string. Handling of invalid
  ranges depends on attribute kind and font state; there is no general rule
  for normalizing all malformed ranges. The interaction between paired
  `originalFontSize` and `fontScaleFactor` values is not specified here.
- Complete text replacement must clear all prior custom attributes. The
  renderer reports stale out-of-bounds ranges because imported behavior can
  depend on the attribute kind and font state instead of admitting one safe
  normalization rule.
- Template application is not complete text replacement. The resolver keeps
  meaningful source custom attributes at clipped UTF-16 ranges, discards empty
  and range-only entries, and ignores placeholder-specific template ranges.
  `originalFontSize` and `fontScaleFactor` values are retained without applying
  the template's resolution scale and produce an explicit warning because
  native precedence/scaling is not specified.
- Sparse or minimal RTF does not provide a supported guarantee that protobuf text attributes alone define visible text.

Generated text should use platform-native Cocoa RTF when targeting ProPresenter compatibility.

## Text Layout

`Graphics.Text.vertical_alignment` is applied within the text element's bounds after measuring the attributed string. Top, middle, and bottom alignment are independent of RTF paragraph alignment.

The ProPresenter 21.4 layout uses a 5-point inset on every edge. In the flipped AppKit bitmap context, bottom alignment must be inverted to preserve ProPresenter's visual direction. Cocoa RTF shadow offsets are already interpreted in the matching direction by AppKit and should be preserved.

For ProPresenter 22 documents with font scaling disabled, the renderer uses no
intrinsic text inset. Baselines center each line's cap height within a body
that accommodates its font descenders; vertical alignment uses the union of
those line bodies. This also accounts for mixed text and emoji fonts. Text is
clipped to its content bounds. Glyph antialiasing is not yet pixel-exact with
native 22 exports. Other scaling modes retain the existing layout behavior.

Paragraph alignment, line spacing, tabs, and indents encoded in Cocoa RTF are preserved. Literal bullet or numbered-list markers in the RTF string render as normal text. Native lists use both paragraph `textLists` metadata and RTF `\\listtext` destinations. AppKit otherwise discards that destination, so the renderer restores it as ordinary RTF before decoding. This preserves the marker's own styling and its native tab sequence, including depth-specific nested-list indentation. For lists without a native destination, the renderer synthesizes a marker and two tabs as a compatibility fallback.

Alternate-text data links resolve the source by element UUID, retain the target element's RTF formatting and layout, and replace the target content using the stored transform. `NONE` retains line returns and `REMOVE_LINE_RETURNS` replaces them with spaces. The renderer retains the native outline treatment. `ONE_WORD_PER_LINE` and `ONE_CHARACTER_PER_LINE` retain the stored target
text in the renderer because their native transforms are not supported.
Scale-down placement measures every line before vertical centering. Positive
RTF stroke widths draw an outline without a fill; negative widths retain the
combined fill-and-stroke treatment.

`Graphics.Text.scale_behavior` controls font resizing:

| Value | `pro-crud` behavior | Native compatibility |
| --- | --- | --- |
| `SCALE_BEHAVIOR_NONE` | Draw without font scaling; overflowing content expands around the box center | Exact native parity is not established. |
| `SCALE_BEHAVIOR_SCALE_FONT_DOWN` | Shrink to fit only | Supports native shrink-to-fit behavior. |
| `SCALE_BEHAVIOR_SCALE_FONT_UP` | Grow to the largest fitting proportional scale when original text fits | Exact native parity is not established. |
| `SCALE_BEHAVIOR_SCALE_FONT_UP_DOWN` | Grow or shrink to the largest fitting proportional scale | Exact native parity is not established. |
| `SCALE_BEHAVIOR_ADJUST_CONTAINER_HEIGHT` | Preserve font sizes and adjust the drawing container from its top edge | Matches native contraction and expansion behavior. |

For stroked text, the shadow follows the combined fill-and-stroke silhouette.
Renderers that split text into separate stroke and fill passes need one shadow
pass behind both visible passes rather than dropping or duplicating the shadow.

When font scaling is applied to mixed-size RTF, ProPresenter scales runs proportionally instead of flattening all runs to one size. Scale-down fit measurement uses an unbounded-height AppKit text container at the available width, then checks the complete typographic height. Placement also measures the full line fragments, including their leading, rather than only the lines visible in a height-constrained container.

## Line Masks

`text_line_mask` is a oneof on `Graphics.Element`. Its presence changes fill behavior for text-related elements:

- Enabled line masks render the element fill as per-line bars behind text instead of as a full element rectangle.
- `LINE_MASK_STYLE_MAX_LINE_WIDTH` uses a single bar spanning the complete
  multiline text block, with the width of its widest line. It does not create a
  separate bar for each wrapped line.
- Some helper elements carry a present but default line-mask value with empty RTF text. These act as helpers and should not render their fill as a full rectangle.
- In a line-width mask, `widthOffset` is the total added width rather than padding on both sides. For text with a positive line-height multiple, ProPresenter's bar height excludes the additional multiple-leading. When a one-line bar plus `heightOffset` would exceed its text box, the bar is constrained to that box's height.

Native compatibility for full-width and max-line-width masks with nonzero
height offsets is not established.

## Shape Feathering

Enabled shape feathering fades the outer shape envelope, including the stroke
width. Its mask is independent of the paint opacity and the gaps in a dashed
stroke. Fill and stroke receive the mask before compositing, preserving a
partially transparent fill and the inside edge of a stroke-only shape. The
stored radius is normalized to the smaller element dimension. The renderer
insets the vector path, blurs its fill and continuous stroke into a grayscale
mask, and clips the original paint through that mask. Mask rasterization uses
top-down coordinates, fractional path bounds, and rounded bitmap dimensions.
The star and polygon fill, solid-stroke, and dashed-stroke variants match the
ProPresenter 21.4 exports at 0.99 pixel and 0.99 perceptual precision.

## Media Sampling

Enlarged image media uses linear texture sampling before placement. Reducing
media retains the AppKit sampling path; video-fill sampling still differs from
the native reference.

## Video Frames

Video media actions can render a thumbnail or representative frame in exported
slide images. That frame is not necessarily the first frame. Exact native frame
selection, cached thumbnails, and export-time playback state are not specified;
video previews may therefore differ from ProPresenter exports.

## Rendering Accuracy

Output can differ from ProPresenter because of font availability, text
antialiasing, shadows, stroke rasterization, feathering, line-mask geometry,
and video frame selection. Use the same installed fonts and check the rendered
result in ProPresenter when visual parity matters.

## Arrangement Resolution

Arrangement resolution is a cue-sequencing step that occurs before template or
Look resolution and before drawing. An arrangement appends each referenced cue
group's cues in order. Repeated group references therefore create repeated cue
occurrences, omitted groups contribute no cues, and a valid empty arrangement
resolves to an empty sequence. These are file-renderer sequencing rules; exact ProPresenter export selection
when document, playlist, and active UI arrangements differ is not specified.

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

An explicitly selected native 22 workspace is also supported for static Looks
whose selected Theme slide contains no media. Saved/shared and live/client Looks
remain separate and can be selected by UUID when names overlap. Theme references
resolve to native streams in the same database snapshot, using ROOT_SHOW or a
Workspace-scoped ROOT_CURRENT_RESOURCE path. The preview uses shared logical
dimensions, with local screen geometry as a fallback. A disabled screen emits a
warning; previewing it does not enable output. Missing client configuration can
use valid shared dimensions with a warning. Missing/unavailable Themes, dangling
template UUIDs and selected-slide media are diagnosed before publishing output.
Media on unused templates and ignored Theme actions does not block the Look.

Theme media is resolved against its Theme origin before source-document
basename fallback. `ROOT_CURRENT_RESOURCE` uses the Theme directory.
`ROOT_SHOW` can be resolved when the persisted Look supplies a user-workspace
root. Direct `--theme` rendering has no show root, although it can still use a
reachable stored absolute URL or an unambiguous asset in the Theme resource
roots. Otherwise the media is reported as unresolved. An unresolved template
reference is not allowed to borrow an equal-named source asset.
