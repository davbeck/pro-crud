# Experiment Backlog

Before an experiment changes saved ProPresenter library data, confirm that the user has identified the local instance as a development/test host or otherwise authorized library changes. If not, ask whether the local library may be changed; until authorized, use disposable documents or copied libraries. The goal of each experiment is to produce a small fixture, a decoded field map, and a ProPresenter-exported reference image or round-trip artifact when the behavior affects rendering or import compatibility.

## Verified Round Trips

The following observations were reproduced with ProPresenter 21.4 (build 352583705) on macOS 26.5.2 on July 18, 2026. The presentation experiments used a disposable local workspace and compared raw protobuf payloads as well as archive entries; they did not rely on rendered output.

### Presentation And Bundle Exports

- **Presentation** export writes the selected library `.pro` into a chosen directory without changing its protobuf bytes.
- **Presentation Bundle** export also preserves the library `.pro` payload byte-for-byte. Media files are stored under their absolute source paths, and the `.pro` retains its absolute URL plus `ROOT_SHOW` local path.
- ProPresenter's ZIP writer stores these entries without compression and records the central-directory length 98 bytes too large. The native reader tolerates that exact defect after independently validating the archive structure.
- Re-exporting an imported ProCRUD bundle again preserves the newly installed library `.pro` byte-for-byte.

### Import Normalization

- ProPresenter 21.4 accepts ProCRUD bundles with a root `.pro`, root or nested relative media entries, and matching `url.relative_path` references.
- On import, ProPresenter copies media into `Media/Assets`, replaces the portable URL with an absolute file URL plus a `ROOT_SHOW` local path, sets the URL platform to macOS, and retains the media UUID.
- ProPresenter fills many empty/default submessages, updates `application_info` to the importing application and OS version, and can regenerate the presentation UUID. The installed presentation name follows the installed `.pro` filename, including a `-1` suffix chosen for a filename collision.
- Importing two distinct archive entries named `a/shared.png` and `b/shared.png` flattens both into `Media/Assets`. Choosing **New Version** for the collision installs them as `shared.png` and `shared-1.png` and rewrites each media URL accordingly. A raw `.pro` whose two absolute media URLs have the same basename follows the same copy/version/rewrite behavior.

These results establish that portable relative bundles do not need to reproduce ProPresenter's unusual absolute ZIP entry names. Writers should avoid ambiguous archive destinations, use ProPresenter's `-1`, `-2`, and later suffix convention for distinct external files with the same basename, and expect ProPresenter to normalize paths when it installs the document.

## Round-Trip Safety

1. Decode and re-encode representative `.pro`, `Theme`, playlist, and configuration documents with unknown-field preservation enabled. Import or reopen them in ProPresenter and verify there are no warnings or data loss.
2. Repeat selected round trips with unknown-field preservation disabled to identify which generated-code paths are unsafe.
3. Edit one text element in an existing presentation, import it, export slide images, and verify only the intended text changed.
4. Edit one media reference in an existing presentation, import it, and verify ProPresenter preserves or rewrites the URL fields as expected.

## Archive And Path Semantics

1. Finish comparing bundle-without-media, playlist, and theme exports. Presentation-only and bundle-with-media behavior is recorded under Verified Round Trips.
2. Continue with absolute-only, missing, relocated, and `ROOT_CURRENT_RESOURCE` media paths. Root and nested relative archive-local paths are accepted and normalized as recorded above.
3. Test the remaining duplicate-name choices (**Write Over** and **Use Existing**) and a ProPresenter-authored document whose live media sources share a basename. **New Version** behavior for a ProCRUD bundle and raw `.pro` is recorded above.
4. Test whether ProPresenter accepts standard ZIP central directories, absolute entry names, relative entry names, and normalized permissions.

## Text Rendering

1. Complete ProPresenter-exported verification for all `SCALE_BEHAVIOR_*` values, especially `SCALE_BEHAVIOR_ADJUST_CONTAINER_HEIGHT`.
2. Test font resolution for installed fonts, missing fonts, family-only references, face-only references, and custom imported fonts. The focused malformed-bundle probe now covers one- and two-face Helvetica tables with stale range metadata, but not missing/custom font import.
3. Determine how paired `originalFontSize` and `fontScaleFactor` custom attributes interact. A standalone scale factor of 0.5 or 2.0 did not change the focused ProPresenter export.
4. Create sparse-RTF and no-RTF text fixtures to determine when protobuf `Graphics.Text.Attributes` becomes the visible source of text styling.
5. Map all capitalization modes, including all caps and small caps, against fully styled RTF and minimally styled RTF.

## Builds And Text Delivery

The persistent graph, official product behavior, two native By Bullet samples,
and the proposed implementation sequence are documented in
[TextBuilds.md](TextBuilds.md). The highest-value unresolved questions are the
exact text unit represented by `ChildBuild.index`, the meaning and base of
`reveal_from_index`, Underline segmentation, contextual start-enum labels,
parent-transition inheritance, and Build Order grouping.

Run the focused matrix in that note before exposing purpose-built Delivery
authoring or build-state rendering. Use ProPresenter-authored documents and
Syphon video for time-dependent behavior. Do not synthesize a graph, observe
that ProPresenter normalizes it, and treat the result as proof of the intended
field semantics.

## Shapes And Images

1. Create one-slide fixtures for supported path shapes: rectangle, rounded rectangle, ellipse, triangles, rhombus, star, polygon, arrows, and custom paths.
2. Exercise fill types: solid color, gradient, media fill, background blur, and invert.
3. Exercise stroke styles, feather, opacity, rotation, flips, locked/aspect-ratio flags, and crop insets.
4. Test image drawing scale modes: fit, fill, stretch, custom bounds, natural size, native rotation, and alpha inversion.
5. Extend the authoritative `Rendering Edge Cases` line-mask probe with
   nonzero height offsets for full-width and max-line-width masks. The current
   four-slide probe establishes line-width offsets, including a constrained
   one-line box.

## Video And Audio

1. Determine how ProPresenter chooses representative video frames for exported slide images.
2. Add foreground media, background media, and fill media actions for still image, video, and audio.
3. Exercise video playback behavior: stop, loop, loop count, loop time, soft loop, end on black, end on clear, fade to black, and fade to clear.
4. Add playback markers with nested actions and verify persisted marker structure.
5. Test audio channel routing and custom mappings with a fixture that does not depend on external devices.

## Cues, Groups, And Arrangements

Stored arrangement structure is established: an arrangement contains an ordered
sequence of cue-group UUIDs, repeated references are meaningful, an empty
sequence is valid, selection is optional, and playlist items can carry their
own arrangement UUID. The file renderer implements explicit selection,
playlist-item selection, stored selection, then Master/native fallback in that
order.

The file editor now models cue groups as ordered, normally exclusive owners of
global cue UUIDs. Its explicit transfer, ungroup, deletion, destination-group,
and arrangement-cleanup policies avoid silently discarding cues or changing
arrangements. Deep duplication regenerates the copied group, cue, action, and
slide identities and remaps completion targets within the copied set. A local
rename, color change, or explicit hotkey set/clear detaches stored
application-group metadata. Hotkey clear deliberately retains a present empty
`rv.data.HotKey` message. These are safe file-editing semantics, not claims
about every corresponding ProPresenter UI operation.

In ProPresenter 21.4 on August 15, 2026, a song with arrangements but no
`selected_arrangement` opened on Master, while selecting a stored empty
arrangement displayed **Empty Arrangement** with no slide thumbnails. **New
Arrangement…** appended a fresh arrangement containing every native cue group
once and selected it; duplicating an arrangement created a separately named
entry that could be edited independently. These UI observations establish the
Master and empty-selection behavior but are not substitutes for the slide-image
export comparisons below.

Remaining focused work:

1. Author a small media-free ProPresenter fixture with reordered, repeated,
   omitted, and empty group sequences. Export slide images for each UI
   selection and compare them with the file renderer without changing existing
   reference images speculatively.
2. Export and reimport a playlist that references the same presentation more
   than once with different arrangement UUIDs. Confirm the saved item
   references and rendered/exported sequence for each item.
3. Rename, duplicate, reorder, and delete selected and playlist-referenced
   arrangements in ProPresenter. Record UUID regeneration, selection cleanup,
   stale-reference handling, and duplicate-name behavior.
4. Determine which arrangement ProPresenter's standalone **Export → Slide
   Images** workflow uses when the document, playlist item, and current UI
   context disagree.
5. Inspect presentation-document actions whose `Action.DocumentType` contains
   `selected_arrangement`; determine how that action-level reference interacts
   with document and playlist selection.
6. In the UI, create built-in, custom, application-linked, and empty cue groups.
   Compare the saved local UUID, name, color, hotkey, application-group fields,
   insertion position, and empty-group persistence.
7. Rename, recolor, and set or clear the hotkey of an application-linked group
   in ProPresenter. Determine whether the UI detaches, updates, or preserves
   the link, and whether a later workspace-group edit propagates back into the
   presentation.
8. Move cues between groups, replace a group's full membership, and leave the
   source group empty in the UI. Inspect ordering and ownership after save and
   reimport. Also open controlled malformed fixtures containing duplicate
   references within one group, shared references across groups, and ungrouped
   cues to learn whether ProPresenter preserves or normalizes them.
9. Duplicate a cue group in the UI and compare every nested cue, action, slide,
   and completion-target identity. Record whether the application-group link is
   retained and whether any arrangement receives the new group.
10. Delete empty and nonempty cue groups in the UI. Record the offered
    delete/regroup/unassigned choices, arrangement-reference cleanup, and the
    behavior when attempting to remove the final group or all cues.
11. Reorder cue groups while Master, a stored arrangement, and a playlist-item
    arrangement are active. Confirm which sequences change in the UI and in
    **Export → Slide Images** output.
12. Exercise cue completion targets/actions: next, random, specific cue, first
    cue, after action, and after time.
13. Test hotkeys on cues and groups, including a locally detached
    application-linked group. Compare symbolic and raw numeric key codes, and
    determine whether ProPresenter distinguishes an absent hotkey field from a
    present empty `rv.data.HotKey` message after save, import, and UI editing.
14. Duplicate individual cues and elements, then inspect which UUIDs are
    regenerated, copied, or referenced.

## Actions And Configuration Documents

1. Create one fixture per `Action.ActionType`: clear, clear group, timer, prop, mask, message, stage layout, audience look, macro, slide destination, communication, audio input, playlist item, presentation document, and external presentation.
2. For each action fixture, export `.pro`, decode it, and write a field map for required and optional fields.
3. Change referenced global configuration items, such as macros and timers, and inspect whether actions reference UUIDs, names, indexes, or a combination.
4. Test macros containing nested actions, especially Looks and media actions.

## Themes And Alternate Outputs

The baseline existing-slide, new-slide, mismatch, mixed-RTF, aspect-ratio, and
live Look probes are complete for ProPresenter 21.4 and documented in
[ThemeDocuments.md](ThemeDocuments.md). They establish materialization versus
runtime references, name-aware content assignment, template-defined output
membership, independent X/Y transforms, vertical font scaling for populated
text, and per-screen live resolution.

Remaining focused work:

1. Author template media actions in ProPresenter and compare checkbox on/off for existing slides, new slides, and Looks. The synthetic action probe was normalized on import and is not authoritative.
2. Cross UUID/name/order intentionally, then test case-only, whitespace, empty, and duplicate names across text-bearing and graphics-only slots.
3. Supply more source text boxes than total template slots and record overflow behavior.
4. Run the source/template build matrix in [TextBuilds.md](TextBuilds.md), then
   exercise alternate text/fill, data links, and visibility references when
   source UUIDs survive, source elements disappear, and template UUIDs remain.
5. Test mixed template RTF against mixed source RTF, including paragraphs, emoji/combining characters, capitalization, `originalFontSize`, and `fontScaleFactor` UTF-16 ranges.
6. Test aspect-mismatched new-slide creation and scale behavior for strokes, shadows, feathering, rounded corners, media crop/custom bounds, and normalized paths.
7. Route distinct template sizes to multiple audience outputs in one Look; test stale/missing theme paths, slide UUIDs, screen UUIDs, and active-theme cache invalidation.
8. Decode `.proTheme` exports with external assets, archive-local assets, and theme-local assets, including a ProPresenter-authored multi-theme export.

## Data Links And Dynamic Text

1. Create text elements linked to timer, clock, CCLI, slide count, slide label, group name/color, presentation notes, playlist item, output screen, video countdown, audio countdown, RSS feed, file feed, and chord charts.
2. For each data link, inspect `Slide.Element.DataLink` oneof selection and required referenced objects.
3. Export rendered PNGs where possible to decide whether a renderer should evaluate dynamic values or expose placeholders.

## Output Layers And Playlist Templates

The [official output-layer documentation](https://support.renewedvision.com/hc/en-us/articles/13634000690323-ProPresenter-Output-Layers)
establishes a live-output stack that differs from the checked-in **Slide Images
without slide background color** export contract. The current renderer
intentionally preserves the latter. The remaining work is native rather than
speculative:

1. Capture each of the four documented color/media cases twice: as a Slide
   Images export with background color disabled and through a configured
   Audience Screen. This must establish which output mode each renderer API
   represents.
2. Add screen-color, video-input, mask, message, prop, and announcement cases
   only when the renderer gains an explicit screen/output configuration model.
3. Test presentation and slide gradient backgrounds separately. Do not infer
   their stops or geometry from ordinary element gradients.
4. Test Background Blur and Color Invert against a live media or video-input
   layer. The [official Background Effects guide](https://support.renewedvision.com/hc/en-us/articles/10911852908819-Using-Background-Effects-in-ProPresenter)
   shows that these are layer-relative effects, not standalone shape fills.
5. Capture a native `Playlists/PlaylistTemplates` store with headers,
   placeholders, and presentation entries. Its schema is present, but the
   general document loader intentionally does not yet expose it as a regular
   playlist.

## Broader Feature Coverage

Use official ProPresenter workflow documentation as a checklist for missing fixtures. Areas still needing focused examples include screens and outputs, Looks, stage screens, announcement layer, Planning Center, Bible integration, alpha keying, audio routing, communication devices, MIDI, DMX, RossTalk, GlobalCache, capture/streaming, props, masks, messages, timers, playlist templates, and CCLI display behavior.

## CLI Acceptance Tests

1. `dump`: print semantic metadata, cue and action structure, media references, fonts, canonical paths, and unsupported fields.
2. `extract-text`: recover plain text from RTF and compare against expected cue labels or exported text fixtures.
3. `rewrite-text`: change one text element, import into ProPresenter, export PNG, and verify only intended slide text changed.
4. `render`: render generated and exported fixtures, comparing against ProPresenter PNG exports with defined tolerances.
5. `create`: generate a complete one-slide `.pro`, then a `.probundle` with one local image, and verify import/export behavior.
