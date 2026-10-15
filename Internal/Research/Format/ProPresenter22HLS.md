# Local HLS actions

October 15, 2026. Native macOS ProPresenter **22 beta, build 369098875**,
macOS **27.0.1**, authorized disposable local workspace. No Cloud service or
additional app installation was used.

## Native source and exports

An owned Presentation received **Add Media Action → Video Stream** through
the native UI. Its URL was `http://127.0.0.1:61541/stream.m3u8`, served only on
loopback. The six-second VOD uses six one-second MPEG-TS segments encoded from
the repository's owned frame-test video. The dialog recognized its six-second
duration. The fixture server restricts paths to this manifest and its segments.

The selected source is `Media.video.source.SourceType.hls.url`, not the separate
root `Media.hls_stream` variant. The media has schema string `"1"`, occurrence
UUID `473204A8-A75F-4D4A-8B7B-7518C1497D26` and asset UUID
`92C2701D-3874-4D50-8F8D-A2A52BEF730F`. Container/provider identities are absent;
root URL and file local URL have no selection. Native transport retains end
point 6, play rate 1, loop count 1 and retrigger 3. The parent media action's
subtype is audio despite the element being video; no speculative correction is
made to this native state.

Standalone export omits the empty file-locator wrapper present in the native
projection. The source classification and active HLS locator are unchanged;
tests compare those semantics rather than requiring identical empty-wrapper
presence across native export normalization. Standalone export also sets the
two fade flags while their durations remain zero. The post-edit transport is
checked against the independent pre-edit standalone export; native stored
transport is checked unchanged across the CLI edit.

Both native **Presentation** and **Presentation Bundle** exports retain the HLS
action, URL and asset association. This differs from the earlier file-image
standalone export experiment. The bundle's raw `.pro` payload is retained;
archive manifests with workspace paths are excluded. The existing ZIP64 repair
reader extracts the native archive unchanged, while Python's zipfile rejects its
central-directory trailer. No archive-reader change was needed.

Native bundle reimport creates `ProCRUD Local HLS Control-1`, changes the
occurrence UUID to `7d7c5913-6538-5c5e-8ac0-733431987c44`, and preserves the
asset UUID, stream URL and action UUID. UUID case is normalized. This experiment
uses the same workspace; it does not prove fresh asset-store construction.

Unmodified snapshots/vectors, both original exports and the later metadata
export are in `Fixtures/ProPresenter22/Native/HLSStream`, with source and file
hashes in provenance.json. These are inspection fixtures; tests never fetch the
recorded URL and do not require a running server.

## Demonstrated fixes and preservation

Regression tests first reproduced three failures: strict validation reported a
missing file for this native source; media-only cues skipped media diagnostics;
and bundling a compatibility-shaped HLS action copied/rebased a superseded root
file locator. Canonical source classification now excludes streams from file
validation and bundling copy/rebase work. Actual file failures remain covered.

Static rendering reports `rendering.unsupported-runtime-media` for HLS actions
and fills, including media-only cues and constructed wire messages without
native identities. PNG/PDF/effective-rendering paths reject the source. The
single-cue output test preserves existing PNG/PDF bytes. No live playback,
thumbnail extraction or stream availability claim is made.

With the native app and helper stopped, the production copyright-title editor
set the original stream's title to **HLS CLI Metadata**. Exactly one Presentation
row and one receipt changed; registry bytes and all 24 media-store files were
unchanged. Replay was a no-op. Native reopening retained the exact CLI snapshot
and vector; an independent native Presentation export retains the title, HLS
locator and identities. The complete media action is unchanged by the edit.

The localhost access log stayed at 17 native requests through focused tests,
metadata edit and replay. Thus these offline operations made zero HTTP requests.
After native reopening/export raised that count to 30, the final full regression
run left it at 30. All **457 core, 96 CLI and one harness** tests pass with the
same nine known rendering issues. SwiftFormat, SwiftLint and embedded schema
resource freshness checks pass.

## Remaining gates

Native asset-identity raw writes/exports and media-store transactions remain
gated. The bundling regression strips native-only identity fields to test its
file-handling policy; it does not qualify a native-identity interchange adapter.
Fresh-workspace import, root Media.hls_stream, other source variants, transport
execution, playback markers, provider effects and migration require independent
qualification. No ProPresenter 21 HLS runtime acceptance is claimed.
