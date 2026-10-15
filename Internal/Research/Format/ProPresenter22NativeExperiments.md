# ProPresenter 22 native interchange experiments

Investigation: October 14, 2026 (America/Los_Angeles), ProPresenter 22 beta
build 369098875, macOS 27.0.1. The local app is an explicitly authorized test
host. Product source and checked-in rendering snapshots were not changed.

Private local artifacts are under `.build/pro22-investigation/` and are not
shipped fixtures. Temporary investigation files from before a system interruption
were lost; the native export experiments below were repeated in persistent
workspace storage.

## Native exports

The selected migrated presentation was exported through **File → Export →
Presentation** and **Presentation Bundle**. The standalone `.pro` parses with
the existing schema and identifies application version 22/build 369098875 and
macOS 27.0.1. The `.probundle` extracts successfully with the existing archive
reader, but its embedded `.pro` is rejected by the current loader with
`missing application_info`. These are distinct export paths; do not generalize
the missing-metadata observation to every 22 `.pro`.

**File → Export → Themes** with only the independently authored `Deep Look
Theme` selected produces `Native22Theme.proTheme`. Existing archive extraction
succeeds, while loading `Deep Look Theme/Theme` fails with the same missing
metadata check.

**File → Export → Playlist** from the empty standard presentation playlist,
with **Include media within presentations** enabled, produces
`probe-roundtrip/Native22Playlist.proPlaylist`. Current protobuf dump succeeds;
the root `data` includes application version 22 and an empty standard playlist.
This does not qualify populated or Planning Center playlist archive behavior.

The current reader handles these native ZIP archives. Python's ordinary
`zipfile.ZipFile` rejects the native bundle with `Bad magic number for central
directory`, consistent with the already documented native ZIP64 directory-size
defect. Do not remove or generalize the reader's narrow existing workaround
without exact record-boundary comparisons.

## Legacy Workspace bridge

**File → Export → Legacy Workspace** exported the active migrated workspace to
`LegacyExport22`. The UI creates a hidden sibling `.exporting-<UUID>` staging
folder while the multi-gigabyte export runs, then publishes the completed
folder. Absence of a visible destination during that interval is not failure.

The output has the old `Libraries`, `Playlists`, `Themes`, and `Configuration`
shape. The finished export reports **71 media entries unavailable** and offers
a Copy button. The complete copied report is stored privately as
`legacy-export-missing-media.txt`; `legacy-export-alert.txt` records the alert.
It includes unavailable filenames and at least one diagnostic that a file media
has neither a portable locator nor a durable materialized source. It must not
be conflated with the six-media upgrade warning in the supplied screenshot.

See the storage report for exact inventory reconciliation and migration limits.
Representative exported legacy protobufs fail the current `application_info`
check; the compatibility plan requires dedicated structurally valid fixtures.

## Existing CLI authoring and native rendering

Using the freshly built repository CLI (not `/usr/local/bin/pro-crud`, which was
an older installed version), created `ProCRUD22Probe.pro` with a single 854×480
slide, then added an opaque `#00AADD` rectangle at x=100, y=100, width=300,
height=200. Bundled it with the CLI and imported it through **File → Import →
File** into the test workspace's MISC library. No existing presentation was
overwritten. The app names the imported document `ProCRUD22Probe` from the
archive/payload filename.

Exported native **Slide Images** as **PNG (without slide background color)**
with **Include Media Actions** enabled to `probe-native-reference/1.png`.
Rendered the original CLI document to `probe-cli-render/1.png`.

A Swift/CoreGraphics diagnostic decodes both images into sRGB premultiplied
RGBA. Result: **854×480 for both, zero differing channels, maximum delta 0**.
The native PNG was also visually inspected and contains the expected cyan
rectangle. This proves one simple geometry case, not typography, media, Looks,
animation, or complete renderer parity. No checked-in snapshot was replaced.

Exported the imported presentation back through **Presentation** to
`probe-roundtrip/ProCRUD22Probe.pro`. Current protobuf dump succeeds and appInfo
is application 22/build 369098875, platform macOS 27.0.1. Native import changes
the root presentation UUID from `9EDC75EF-CB4E-42CB-8379-478C60F62DEB` to
`48E32307-7A5A-56CC-8CCA-0BC82D6079C1`; cue, action, slide, group and rectangle
UUIDs remain in the re-export. Native serialization adds default submessages
and text attributes. Future reference-resolution tests must model root identity
mapping rather than assuming file/protobuf/native stream identity equality.

After the experiment, deleted only the generated `ProCRUD22Probe` through the
native library's Delete command, verified the confirmation named that document,
and verified the MISC inventory returned from 16 to 15 items. Generated input,
native export and PNG evidence remain in the ignored investigation directory.
No temporary output screen or other saved test configuration was created.

## Boundaries

No native database writes, Cloud conversion, Cloud merge experiment, live
output trigger, new screen, third-party service change or account inspection
was performed. Slide image export supplies native rendering evidence without
changing live Audience output. No Syphon sources were available in the initial
diagnostic inventory; the simple static experiment used native image exports.
Further animation/live-source tests in the plan require a dedicated Syphon
output and time-based captures.
