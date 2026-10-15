# Native 22 file-media static rendering

October 15, 2026; pinned local ProPresenter 22 beta build **369098875**, macOS
**27.0.1**. No API or Cloud connection is required by the renderer.

## Scope and source selection

`NativeMediaRendering` qualifies a rendering-only view of schema-1 local image
and video occurrences with valid reference/asset UUIDs. It resolves the selected
SourceInfo, FileProperties or root URL using the pinned schema precedence.
Exact relative/ROOT_SHOW paths use the explicit workspace/archive resource root;
absolute file URLs can stand alone. Superseded locators and same-basename files
do not substitute for a missing active file. Source protobufs, native histories,
asset associations, container IDs and provider fields remain unchanged.

The rendering compatibility view omits qualified identities/locator metadata
only from its transient validation copy. It never enters an edit/export path.
`DocumentCompatibility` still rejects native media identity conversion for
writing/packaging. Unmapped fields in the media subtree fail explicitly.
SDR/unknown color and straight/unspecified alpha use existing static drawing;
blur must be off. HDR, premultiplied-alpha metadata, provider associations,
HLS/web/live/audio sources and other identity schemas remain gated. Known
retrigger and hardware-decoding preferences do not run during a static preview.
FileProperties/SourceInfo predate 22 and appear in existing 21 fixtures. Only
explicit native identity/provider/HLS fields select this adapter; legacy
interchange keeps its established resolution behavior. A regression test
verifies all nine existing 21 corpus presentations remain unchanged by the
rendering compatibility view.

Native type selects image/video decoding independently of filename extension.
The stored video thumbnail is used; a negative default selects five seconds.

## Independent native references

The original bulk 71-slide PNG export included unloaded media placeholders.
Opening **08 - Media Elements** and **09 - Media Backgrounds** individually
displays real image/video thumbnails. Fresh native **File → Export → Slide
Images**, PNG without slide background color and Include Media Actions enabled,
produces eight actual media images. They are retained separately under
`Fixtures/ProPresenter22/Rendering/ReferenceSlides/LoadedMedia/` with exact
provenance. The old corpus and every 21 reference remain unchanged.

The transparent PNG passes against the new native export with the same
precision/perceptual precision (**0.985/0.5**) as its existing 21 test. No
tolerance is loosened. Full pixel equality is not claimed: the raw sRGB RGBA
comparison differs in 1,869 of 409,920 pixels (mostly sampling edges). The
video-element comparison differs in 13,236 pixels; the six backgrounds differ
in 1,708–36,215 pixels. Those are diagnostic counts, not passing thresholds.
Existing rendering sampling/video limitations remain; no speculative pixel
offset, new recording or broad known-issue exception was added.

## Production and regression checks

The actual `render ROOT --native-stream 04108699-4088-4c02-8ae6-a26c927f594d
--format png,pdf,json` succeeds against the running authorized local workspace,
reading SQLite/Loro and exact workspace assets. Its two PNGs have **zero**
differing RGBA channels against CLI rendering of the independent native bundle
payload and extracted media. Automated checks compare all eight native-stream
and native-export media slides with exact image precision. This proves adapter
agreement, separately from the one native-PNG comparison. Source history and
protobuf values remain unchanged; write capability gates still reject them.

Negative controls cover a missing active source with both a valid root URL and
a same-basename asset, missing relative context, stale fallback paths, schema 2,
provider/HLS sources, HDR, premultiplied alpha, blur, and unknown media/source
fields. Native rendering diagnostics expose errors without reporting an absent
root compatibility URL as missing media. CLI tests cover PNG/PDF/JSON output
from a copied native workspace and unchanged source database, plus failed
missing-media rendering leaving existing output byte-identical.

Final validation: **423 core + 93 CLI + one harness test pass**, with the same
nine known rendering issues. SwiftFormat and SwiftLint pass. The source
precondition error reports the component path and selected locator while
retaining the underlying file-resolution error.
