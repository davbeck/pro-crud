# ProPresenter Rendering Fixtures

This directory holds the ProPresenter rendering fixtures and their embedded
media dependencies. See `../README.md` for the fixture layout.

`ReferenceSlides.proPlaylist` is a ProPresenter playlist export with **Include
media within presentations** enabled. It groups the fixture by rendering area.
Styled RTF attributes are split into individual slides, except the four
capitalization styles, which share one text box on one slide so their output
can be compared directly. The spacing samples include unstyled text before and
after the affected text so paragraph interaction remains visible. Related star
and polygon variants share one slide per shape family, and every shape-effect
slide pairs a star with a polygon. The reverse-paint-order fixture keeps its
three overlapping elements together to exercise their ordering relationship.

Every generated presentation uses an 854 by 480 canvas. Isolated elements are
scaled and centered within that canvas so transparent pixels do not dominate
snapshot comparisons.

## Typography fixture

`Typography/Typography.probundle` is a standalone, media-free six-slide
fixture for built-in macOS typography. It covers Avenir Next faces and kerning,
Avenir Next ligatures, synthetic backslant and a physical italic face, Menlo
tracking, tabs and line spacing, and Apple Color Emoji (including a ZWJ/
skin-tone sequence) in mixed-font paragraph spacing.

Its reference images belong only in
`Tests/ProCRUDCoreTests/__Snapshots__/TypographyRenderingFixtureTests/` and
are named `rendersTypographySlide.slide-1.png` through
`rendersTypographySlide.slide-6.png`.

To refresh them, import `Typography/Typography.probundle` into ProPresenter,
then use **File → Export → Slide Images** with **PNG (without slide background
color)** and **Include Media Actions** enabled. Export all six 854 by 480
slides into one directory as `1.png` through `6.png`, then run:

```sh
swift run FixtureGenerator install-typography-references --from /path/to/exported-pngs --replace
```

The checked-in typography references were exported by ProPresenter 21.4 on
macOS 26.5.2 with that workflow. Record the ProPresenter version and export
workflow whenever these references change.

## Rendering edge-cases fixture

`RenderingEdgeCases/RenderingEdgeCases.probundle` is a standalone, media-free
four-slide fixture for rendering behaviors that were previously covered only
by the removed third-party sample suite. It covers decimal and disc lists plus an
asymmetric text inset, line-fill-mask height offsets (including a constrained
single-line box), nonzero and full-turn rotations with clipping, a rounded
rectangle at 0.5 roundness, and alternate-text links with line-return removal,
opacity, outline, and scale-down interactions.

Slides 1 through 3 match the native exports at the fixture precision. Slide 4
retains a known snapshot difference in scale-to-fit/link-outline positioning;
its separate structural and effective-rendering tests still verify source UUID
resolution, line-return transforms, target formatting, opacity, and outline
metadata.

Its reference images belong only in
`Tests/ProCRUDCoreTests/__Snapshots__/RenderingEdgeCasesFixtureTests/` and are
named `rendersRenderingEdgeCasesSlide.slide-1.png` through
`rendersRenderingEdgeCasesSlide.slide-4.png`.

To refresh them, regenerate and import the fixture into ProPresenter:

```sh
swift run FixtureGenerator generate-rendering-edge-cases
```

Then use **File → Export → Slide Images** with **PNG (without slide background
color)** and **Include Media Actions** enabled. Export all four 1920 by 1080
slides into one directory as `1.png` through `4.png`, then run:

```sh
swift run FixtureGenerator install-rendering-edge-cases-references --from /path/to/exported-pngs --replace
```

The checked-in rendering edge-case references were exported by ProPresenter
21.4 on macOS 26.5.2 with that workflow. Record the ProPresenter and macOS
versions whenever these references change.

## List-indentation fixture

`ListIndentation/ListIndentation.probundle` is a standalone, media-free
three-slide fixture for native list-marker rendering. It covers a marker with
separate RTF color styling, decimal list indentation, and nested lower-alpha /
lower-roman lists with depth-specific tab stops. Its user-provided source and
reference images were exported by ProPresenter 21.4 on macOS 26.5.2 using the
same PNG slide-image workflow described above.

Its references belong only in
`Tests/ProCRUDCoreTests/__Snapshots__/ListIndentationFixtureTests/` and are
named `rendersListIndentationSlide.slide-1.png` through
`rendersListIndentationSlide.slide-3.png`.

## Regenerating the playlist and references

1. In ProPresenter, select the rendering-fixture playlist and use **File →
   Export → Playlist**. Enable **Include media within presentations**, then
   replace `ReferenceSlides.proPlaylist` with that export. This keeps the three
   media dependencies portable with the fixture.

2. Import the exported `ReferenceSlides.proPlaylist` into ProPresenter to
   verify the portable playlist opens and retains all nine area presentations.

3. For each presentation in the imported playlist, use **File → Export → Slide
   Images**, select **PNG (without slide background color)**, leave **Include
   Media Actions** enabled, and save into one common export root. Name each
   export folder exactly after its area: `Element Layering`, `Text Attributes`,
   `Text Scaling`, `Text Alignment`, `Text Effects`, `Shapes`, `Shape Effects`,
   `Media Elements`, and `Media Backgrounds`. The root must contain numbered
   PNGs such as `Text Attributes/1.png` through `Text Attributes/12.png`.

4. Install the ProPresenter PNGs as SnapshotTesting references:

   ```sh
   swift run FixtureGenerator install-references --from /path/to/export-root --replace
   ```

   The installer loads the checked-in playlist, validates all 71 854 by 480
   exports, then replaces the rendering snapshot directory with area/slide
   snapshot names. It leaves the export root intact.

5. Run the focused suites:

   ```sh
   swift test --filter RenderingFixtureTests
   ```

   Each PNG has its own named test method, so an individual slide can be run
   directly. For example:

   ```sh
   swift test --filter TextAttributesRenderingFixtureTests/capitalization
   ```

The current references were exported by ProPresenter 21.4. Record the
ProPresenter version and the export workflow whenever references change.
