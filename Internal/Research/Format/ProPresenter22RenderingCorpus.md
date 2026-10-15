# Native 22 rendering corpus and collection bundles

Collected October 15, 2026 with the authorized local **ProCRUD Local Persistence
Test** workspace, ProPresenter **22 beta build 369098875**, macOS **27.0.1**.
Cloud setup was skipped. Existing 21.4 references are unchanged.

## Independent native evidence

Imported the existing native-exported
`Fixtures/ProPresenter/ReferenceSlides.proPlaylist` through native **File →
Import → File**. It contains nine independently authored area presentations,
71 slides and three owned media files. All nine appeared in the native playlist.
Selecting all nine rows and using **File → Export → Slide Images**, **PNG
(without slide background color)** and **Include Media Actions** produced all
71 images at 854×480. The export completed asynchronously; collection waited
until all nine area counts matched `[1,12,8,10,6,11,15,2,6]`.

`Fixtures/ProPresenter22/Rendering/ReferenceSlides/Images/` contains those
unmodified native PNGs. `Documents/` contains the unmodified nine native
Presentation Bundle payloads and three media files. `Native/` contains only
those nine owned imported Presentation streams and their actual vectors.
`provenance.json` records exact hashes, source playlist hash, app/OS/options and
native stream identities. The native export manifest is omitted because it
contains workspace locations; no Workspace/account/configuration history is
included. All nine streams materialize through the pinned descriptor adapter,
with matching exported Master counts, root/group/cue/action identities.

The native bundle's SHA-256 is
`e3595c376e2c8de2546135761ca1d4a2169477d43517f16d2c47007920ecdd6a`.
The archive retains the known native ZIP central-directory overcount of 98
bytes, which the existing validated reader handles. Its manifest declares
`target_contract: presentation_bundle`, nine documents, three media files,
eight media references and no compatibility warnings.

## Newly established container behavior

Exporting **Presentation Bundle** with nine selected presentations creates
**one** `.probundle` containing nine independent `.pro` payloads, not nine
separate bundles. The proposed filename is the first selected presentation's
name; that filename must not be used to silently select one payload.

`PresentationLoader.loadPresentations` now opens every payload and retains the
shared extracted resource owner across all returned documents. Multiple
presentations get separate deterministic output subdirectories; single-bundle
output naming is unchanged. Explicit archive limits still apply, empty
collections fail, and names that would collide after output sanitization fail
before rendering. The existing one-argument public function remains available,
with a separate explicit-limits overload.

Single-document loading/editing remains deliberately ambiguous for a collection:
expand it and select the exact `.pro` file. This avoids silently dropping other
presentations during an edit. `DocumentArchive.bundle` now accepts multiple root
presentations, validates every payload and packages all of them. An invalid
later document leaves existing output byte-identical. Existing media and target
compatibility gates remain; this change does not qualify native media identity
rewrites or stale native export-manifest regeneration.

## Production edit/bundle/render/native round trip

The production CLI bundled copies of **01 - Element Layering** and **06 -
Shapes** with target 22 and no compatibility issues. It rendered all **12**
slides in separate output folders. ProPresenter imported both and assigned its
normal `-1` receiving-library suffixes.

A separate actual CLI patch set the first copy's CCLI song title to **CLI
collection round trip**, followed by production `bundle` to a new collection.
The native app imported both edited-bundle documents, now with `-2` suffixes.
`Roundtrip/CLI.probundle` is the exact CLI input. `Roundtrip/` also retains the
two received native streams/vectors and independent native **File → Export →
Presentation** payloads. Its provenance records all hashes and the edit.
Tests confirm both new root identities, retained cue identities/group records,
all CCLI fields including the new title, and native re-export agreement.
Native receipt/source vector details remain scoped to those owned documents.

## Rendering comparison limits

The 71 fresh PNGs are an independent 22 reference corpus, not automatically
accepted CLI output. Comparing host CLI renders of the existing source playlist
finds three pixel-exact shape controls: **06 - Shapes**, slides **6, 8 and 10**.
Those exact controls are asserted against the native 22 payload and PNG at full
precision. Other cases have color, text layout, effects or media differences;
no tolerance was loosened and no renderer rule was changed by this commit.
Raw differing-byte percentages alone are not perceptual pass/fail results:
one-channel color rounding across a large rectangle can affect many bytes.
The existing per-case 21.4 comparisons remain their independent regression gate.

An initial sandboxed standalone render could not decode the video frames;
rerunning with normal host execution restored the media output. The recorded
comparison uses that host render. It is not evidence of a new file-format or
video-decoder defect. Fonts/OS, native export normalization and individual layout
cases still need investigation before any new 22 rendering rule is adopted.

Other planned typography, list, edge-case, sermon and text-delivery 22 exports
remain work. This corpus does not qualify animations, stickers, runtime output,
full native media rendering, or the entire support plan.

Full regression suite: **412 core + 92 CLI + one harness test pass**, with the
same nine tracked rendering issues. SwiftFormat and SwiftLint pass. The native
collection evidence adds no broad rendering exception or snapshot recording.

## Loaded-media export control

Subsequent inspection found that the initial bulk native image export contains
placeholders for the two Media Elements slides. The actual owned assets exist,
and opening each media Presentation individually displays the real image/video
thumbnails. Repeating native **Export → Slide Images** separately after that
observation produces actual media content. The original 71 images are preserved
as collected. `LoadedMedia/Images/` retains the separate eight unmodified PNGs
from the two media Presentations; `LoadedMedia/provenance.json` records exact
hashes/options. The initial placeholders do not qualify media rendering parity.
No inference about asset-store corruption or a missing file is warranted from
that bulk-export result. See `ProPresenter22MediaRendering.md`.
