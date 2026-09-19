# Sermon List Rendering

`SermonListRendering.probundle` is a focused derivative of the user-provided,
pro-crud-generated sermon presentation that exposed a native-list rendering
difference in released pro-crud builds. Slide 3 stores each bullet as a native
Cocoa RTF `listtext` destination with a leading tab, marker, and trailing tab.
ProPresenter lays that sequence out with the marker on a separate line from the
item text.

The source slide's unavailable Montserrat faces were replaced with built-in
Helvetica faces, and its two media actions were removed. The list structure,
tab stops, text bounds, and font sizes remain unchanged. This isolates the list
behavior from font substitution and background-media compositing.

The reference image is checked in under
`Tests/ProCRUDCoreTests/__Snapshots__/SermonListRenderingFixtureTests/`. It is
slide 3 from a **File → Export → Slide Images** PNG export after importing
this focused bundle into ProPresenter 21.4 on macOS 27.0. PNG without slide
background color and Include Media Actions were selected. The user supplied the
original generated bundle, generated PDF, ProPresenter re-export, and exported
PNGs on 2026-09-19; the focused reference was exported locally the same day.
