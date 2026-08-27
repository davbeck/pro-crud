# Fixtures

`Fixtures/` is the single source for checked-in ProPresenter documents, media,
and ProPresenter-exported reference images. It contains no third-party Theme or
font packages.

- `ProPresenter/` contains the portable 480p playlist fixture with its media
  dependencies and the workflow for installing ProPresenter-exported PNG
  references. Its `MalformedGeneratedBundle/` regression fixture is generated
  from focused stale-range, font-scale, line-break, and opacity probes.
- `ProPresenter/Typography/Typography.probundle` is a standalone, media-free fixture for
  built-in macOS font faces, RTF spacing and ligature attributes, and emoji.
- `ProPresenter/RenderingEdgeCases/RenderingEdgeCases.probundle` is a
  standalone, media-free fixture for lists, text insets, line-mask height
  offsets, rotations and clipping, rounded-rectangle limits, and linked text.

Reference images are stored only under
`Tests/ProCRUDCoreTests/__Snapshots__/`, where SnapshotTesting reads them.

The former third-party Theme snapshot suite is replaced by focused,
independently sourced coverage:

- `ReferenceSlides.proPlaylist` and its 71 ProPresenter-exported references
  cover text, shapes, effects, ordering, and media rendering.
- `Typography.probundle` and its six ProPresenter-exported references cover
  system-font selection, font faces, ligatures, kerning, backslant, spacing,
  and emoji.
- `RenderingEdgeCases.probundle` and its four ProPresenter-exported references
  cover list markers, asymmetric text margins, nonzero line-mask height
  offsets, rotation and clipping, 0.5 shape roundness, and alternate-text-link
  rendering interactions.
- `MalformedGeneratedBundle.probundle` and its five ProPresenter-exported
  references cover stale range metadata, line breaks, font tables, and element
  opacity boundaries.
- The independently authored `ProCRUD Design System.proTheme` is structurally
  tested across all 99 variations, including translucent fills, rotations,
  elliptical shapes, text outlines, shadows, and linked text. Every variation
  is also rendered at its native 1920 by 1080 size.
