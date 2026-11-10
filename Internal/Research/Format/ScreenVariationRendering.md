# Screen variation rendering evidence

## November 8, 2026 local check

- ProPresenter 22, build **369098875**, on macOS **27.0.1**.
- The user explicitly authorized experiments on the local test library.
- Input: user-supplied `Sermon 2026-11-08.probundle`, eleven cues. The bundle,
  artwork, and local workspace are not copied into this repository.
- Configuration source: the registered local **LSSS** native workspace, with
  shared Looks/Themes/Macros and client physical screens/live Look.
- No checked-in rendering references or snapshot tolerances were changed.

Read-only configuration inspection found Projector (3840 × 2160) and Livestream
(1920 × 1080), in that audience-screen order. The bundle's action UUIDs resolve
to the owning Macro definitions:

| Cue family | Macro | Look | Livestream template |
| --- | --- | --- | --- |
| Artwork | Sermon Blank | Stream Blank | None |
| Scripture | Scripture Sermon | Scripture | SlideOverlay |
| Sermon points | Sermon Notes | Sermon Notes | Scripture Notes |

The same Looks have no alternate Theme on Projector. The CLI resolved all eleven
cues independently for both screens, including carry-forward through the second
artwork cue and switching back to Stream Blank at the ending artwork.

The bundle was imported into MISC without adding a playlist item. Triggering its
third cue selected **Scripture** in ProPresenter's Look toolbar. Switching the
native preview from Projector to Livestream displayed the Projector composition
inside a smaller rectangle. The selected Theme's visible graphic has an
`output_screen` data link to Projector, with bounds x=50, y=580, width=800,
height=450 on the 1920 × 1080 Theme canvas. Its stored blue fill is a placeholder;
it is replaced by the linked screen image at runtime. Hidden text placeholders
in this Theme remain hidden. This motivated resolving output-screen dependencies
before painting the transient Look slide.

The CLI preview was inspected visually: it places the Projector source text in
the same rectangle rather than painting the blue placeholder. This is a semantic
and layout check, not a pixel-reference qualification. The native preview also
retained background media from previously triggered cues. The file renderer
retains its existing per-cue media composition policy and does not simulate that
live background state. `snap-syphon list --json`, including outside the sandbox,
reported no active sources; no Syphon frame is claimed as evidence.

No saved screen bindings, Looks, Themes, or Macros were changed. Playback was
cleared, the active Look restored to Stream Blank, and the preview restored to
Projector. The imported sermon copy remains in MISC; the app's deletion dialog
states that removal cannot be undone, so it was cancelled. The Desktop bundle
was not changed.

## Automated coverage

Synthetic tests cover nested Macro traversal, disabled actions, UUID precedence,
cycles, timed actions, fixed variations, selected-cue state, repeated arrangement
occurrences, main/multiple/all screens, bundles, PNG/PDF/JSON output, linked-screen
rasterization and dependency cycles, workspace-relative Theme precedence, and
preservation of existing output on failure. Opposite screen links on different
cue occurrences are resolved separately rather than treated as a cycle.

Native Macro collection tests use the existing ProPresenter-authored
`Fixtures/ProPresenter22/Native/ActionDependencies` exports and Loro snapshots.
Native Theme media tests extend the existing Look configuration fixture with a
known file source; source snapshots stay unchanged. These are resolver tests,
not newly recorded ProPresenter rendering references.
