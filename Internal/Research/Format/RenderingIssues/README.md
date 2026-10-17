# Known rendering issues — October 16, 2026

Investigated the nine `withKnownIssue` comparisons using the existing
ProPresenter 21.4 exports and the independent native 22 text export. No existing
reference PNG, comparison strategy, precision, or perceptual precision changed.

## Resolved

- **Rendering Edge Cases, slide 4:** finite-height layout discarded line
  fragments during fitting and centering. Measuring the full text removes the
  need for the prior link-specific vertical offsets. Positive RTF stroke width
  is an outline-only stroke, not the doubled outside stroke used for a negative
  fill-and-stroke width. The complete native image passes at **0.99 / 0.99**.
- **Media Backgrounds, slide 3:** AppKit enlargement produced harder color
  boundaries than the native export. Core Image affine sampling before
  placement passes at **0.98 / 0.99**. Downsampling remains on the existing
  AppKit path; applying this enlargement path to video made its comparison worse.

Both expected-failure wrappers were removed.

## Feather falloff resolved

The first pass corrected the former filter's squared fill alpha and eroded
stroke interiors, but left five whole-image comparisons below the required
precision. The follow-up fixes the remaining mask rasterization and compositing.

The mask now comes from an inset **vector** path. The renderer draws its fill
and a continuous miter-joined stroke as separate blurred shadows into an 8-bit
device-gray bitmap. Stroke width remains independent of the inset, and dash
patterns affect the paint rather than the mask. Core Graphics clipping applies
that mask while drawing the original fill and stroke, retaining their opacity
and native premultiplied color rounding.

Two coordinate details matter: the mask is generated in top-down coordinates,
and its bounds keep their fractional origin while bitmap width and height are
rounded to the nearest pixel. Building a bottom-up mask, snapping its origin,
or rasterizing before the blur introduces different subpixel coverage. These
rules apply to the geometry without fixture-specific offsets or blur constants.
The inset is implemented with Core Graphics path subtraction and miter joins.

Whole-image matching fractions at the unchanged perceptual precision **0.99**:

| Shape Effects slide | Before follow-up | After | Required |
| --- | ---: | ---: | ---: |
| 11, fill | 0.9763295 | 0.9995072 | 0.99 |
| 12, solid stroke | 0.9784958 | 0.9989803 | 0.99 |
| 13, dashed stroke | 0.9888222 | 0.9994218 | 0.99 |
| 14, fill + solid stroke | 0.9806450 | 0.9993340 | 0.99 |
| 15, fill + dashed stroke | 0.9896809 | 0.9994170 | 0.99 |

All five expected-failure wrappers were removed. The existing exact alpha
assertions remain: slide 14's fill at (600, 240) is 204, and slide 12's inside
stroke at (600, 340) is opaque. Combined feather-and-shadow behavior and
feathered line-fill masks are not independently qualified by these fixtures.

### Independent native check

On October 16, the existing `07 - Shape Effects` presentation in the authorized
local ProPresenter **22 beta build 369098875**, macOS **27.0.1**, was exported via
**File → Export → Slide Images**, **PNG (without slide background color)**,
with **Include Media Actions** enabled. The export contains 15 images at 854×480
in `/tmp/pro-crud-feather-native22`. Slides 11, 12, and 14 are pixel-identical to
the checked-in 21.4 references. Slides 13 and 15 retain small dash-boundary
variations; the tests continue to use the original 21.4 exports unchanged.
The previously selected `ProCRUDTarget22Acceptance-3` presentation was restored.
No library content or output configuration was changed.

Read-only inspection of the installed build's mask routine confirmed grayscale
storage, separate vector fill/stroke shadow passes, fractional bounds and rounded
dimensions. Standalone diagnostic renderings validated these observations
against the independent exports before integration. No application binary,
disassembly, or diagnostic rendering was added to the repository.

## Video fill

Media Elements slide 1 remains at **0.9758685**, below its required **0.98**
matching fraction at **0.99** perceptual precision. Its stored default thumbnail
selects the expected `05` frame; the broad background and white-number colors
match, while sampling around glyphs and the media boundary still differs.
Texture reduction, cubic sampling, alternate interpolation flags, integral
bounds, and hard clipping did not improve the comparison. None was retained.

## Independent native 22 alignment probe

The authorized local app was `/Applications/ProPresenter.app`, ProPresenter
**22 beta build 369098875**, on macOS **27.0.1**. In the existing
`ProCRUDTarget22Acceptance` presentation, the fourth slide's rich text was
selected. The UI confirmed Helvetica Neue Bold Italic, left alignment, no
scaling, and middle vertical alignment. Its text was unchanged.

Changing only vertical alignment to **Top**, then using **File → Export → Slide
Images**, **PNG (without slide background color)** with **Include Media Actions**
enabled, produced the independent diagnostic [Native22TopAlignment.png](Native22TopAlignment.png).
The full export was made to `/tmp/pro-crud-native-top-probe`; the retained image
is its unmodified fourth slide, **854×480**. Middle alignment was restored and
verified in the native inspector afterward.

SHA-256: `cc13cfe82d9d4c6810788e27841fc79031800d5bf1ab94978fbef34777ca39f5`.

The rich text corresponds to the element retained in
`Fixtures/ProPresenter22/Native/Text/RichNativeReexport.pro`, bounds
(66.71875, 44.4444444, 720.5625, 391.1111111). With alpha greater than 100 and
cyan channels greater than 200, the new top-aligned native export's text rows
occupy y=65…98 and y=111…144. The retained middle-aligned native reference has
rows y=209…242 and y=256…289. Both start at x=67. The baseline renderer starts
at x=72 / x=71 and y=203…236 / y=249…282.

The subsequent alignment investigation established the native font-metric
model for unscaled text. TextKit uses zero line-fragment padding. For each line,
the body height is the maximum of its fonts' default line heights and
`maximumCapHeight - 2 * minimumDescender`. Its baseline centers the cap height
within that body, after the line's leading. Vertical alignment uses the union
of these bodies, including the first body's negative origin when an emoji's
metrics exceed the default line fragment. The glyph pass uses the element's
local, flipped coordinate system and clips to its content bounds.

For this fixture, the first body starts at y=-11.5001625 and the used text ends
at y=91.04425048828125. The resulting middle-aligned drawing origin is
y=200.22795600585937 in slide coordinates; top alignment starts at
y=55.944606944444445. These are derived from the fonts and container, not
fixture-specific offsets. Both retained exports now have exactly the same
occupied-pixel sets as the renderer, including the emoji. A regression test
checks both independent exports. ProPresenter 21 rendering and 22 font-scaling
paths retain their existing behavior.

The full sRGB premultiplied-byte comparison improved from 55,935 differing
bytes to 96 bytes at 32 letter-edge pixels. The remaining alpha differences
are identical for top and middle alignment. Font normalization, graphics
context color spaces/channel order, glyph batching, font smoothing and
subpixel flags, paragraph normalization, and additional glyph passes did not
eliminate them. None of those unsuccessful changes was retained. The original
full-color comparison remains a known issue with precision and
perceptualPrecision unchanged at 1; no reference images were changed.

Two of the original nine known issues remain: video fill and native 22 rich
text. The five feather comparisons are now ordinary passing tests.

## Validation

The full `swift test` run after the native 22 alignment correction passed
507 core tests with the two remaining known issues above, all 100 CLI tests,
and the environment-preflight test. The new placement test passed both top
and middle alignment cases against the independent native exports.
The focused Shape Effects run passed all 16 tests, including the five feather
comparisons and exact feather-opacity assertions, with no known issues.
Tests used normal parallel execution without serialization. SwiftFormat ran
on the changed Swift files, and strict SwiftLint passed for the repository.
