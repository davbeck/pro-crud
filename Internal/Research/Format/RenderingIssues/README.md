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

## Feather opacity correction and remaining falloff

The former feather filter eroded the painted image itself. This squared the
alpha of a translucent fill and eroded both edges of a stroke-only shape.
The native exports instead retain the filled outer envelope as a mask, even
when the fill is disabled or the stroke has gaps. Fill and stroke need separate
mask application before compositing: masking their already-composited result
changes their overlap color and opacity.

The renderer now uses that opaque envelope, a geometric inset, and a Core
Graphics blur at the stored radius. Exact native pixel-alpha checks protect
fill opacity and stroke interiors independently of the remaining whole-image
failures. At pixel (600, 240), slide 14's reference alpha is 204; the former
renderer produced 163. At (600, 340), slide 12's solid stroke must remain opaque.

Whole-image matching fractions at the unchanged perceptual precision **0.99**:

| Shape Effects slide | Before | After | Required |
| --- | ---: | ---: | ---: |
| 11, fill | 0.9714505 | 0.9763295 | 0.99 |
| 12, solid stroke | 0.9223288 | 0.9784958 | 0.99 |
| 13, dashed stroke | 0.9551620 | 0.9888222 | 0.99 |
| 14, fill + solid stroke | 0.7915081 | 0.9806450 | 0.99 |
| 15, fill + dashed stroke | 0.8101849 | 0.9896809 | 0.99 |

All five remain explicit known issues. Radius rounding, alternate blur kernels,
and backing-resolution experiments did not establish full parity and their
experimental switches were removed. These results do not qualify combined
feather-and-shadow behavior or feathered line-fill masks.

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

This confirms the horizontal-inset and fractional vertical-placement
mismatches. It does not establish a general replacement rule: direct string
drawing, TextKit glyph drawing, local text bitmaps, Retina backing bitmaps,
and font-descriptor preservation did not reproduce the native pixels exactly.
No guessed native-22 offset or version-specific renderer branch was retained.
The original exact native comparison remains a known issue.

Seven of the original nine known issues remain: five feather falloff cases,
video fill, and native 22 rich text. This is partial progress, not full parity.

## Validation

The final core run passed 506 tests with the seven known issues above. The CLI
target passed all 100 tests after rebuilding its embedded documentation. A
prior combined run stalled in macOS FontRegistry lookups during CLI fixture
creation; the retry used normal parallel execution without test serialization.
The focused rendering run also passed the new exact feather-opacity assertions.
SwiftFormat and strict SwiftLint passed for the changed Swift files.
