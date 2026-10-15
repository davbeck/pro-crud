# Native HLS interchange profile

October 15, 2026, ProPresenter **22 beta build 369098875**, macOS **27.0.1**.
This extends the runtime-source classification in ProPresenter22HLS.md with a
qualified, bounded target-22 interchange profile. The existing authorized local
test workspace was used. No Cloud service or extra installation was required.

## Independent fresh-input acceptance

The native standalone HLS export was decoded and re-encoded with the pinned
22 descriptor. Only the Presentation name/UUID, occurrence UUID, asset UUID and
stream URL were changed. The new URL is a second loopback server at
`http://127.0.0.1:49765/stream.m3u8`, serving the same owned six-second VOD.
The asset UUID `5F7CC3BF-2920-489D-ABAE-2E531F18892D` and URL had not been used
in the workspace before this import. This avoids relying on an existing asset
or cached source association. ConstructedInput.pro is labeled as a constructed
probe, not a native export or rendering reference.

Native File → Import accepts that input, generates Presentation
`cf9668c3-03e2-4c31-b265-c0aa64f4528c` and occurrence
`2ed9679f-181d-5dd0-a6c3-4290fd2d647b`, and preserves the fresh asset, URL and
six-second transport. No missing-file prompt appears. This is fresh-content
acceptance inside the existing local workspace, not a separate-workspace claim.

## Production writer and native re-export

`workspace export --target-version 22` exports that native stream with **zero
compatibility issues**. Its CLIExport.pro is retained. The production raw
`edit patch --path /ccli` sets **Portable HLS CLI Interchange** on the constructed
input. Independent pinned-descriptor decoding shows exactly that title addition;
the complete media action is unchanged. The production bundler creates a target
22 bundle containing only the edited `.pro`, with no asset copy or warning.

Native import accepts this actual CLI bundle, creates Presentation
`e3592c20-2828-5688-827d-1242bf558e03`, regenerates its occurrence identity and
retains the same asset, source and title. Its stored media element, after removing
the occurrence UUID, is byte-identical to the first native probe's projection.
An independent native Presentation re-export retains the new title, HLS URL,
asset UUID and normalized transport. Both native snapshots/vectors and all owned
input/CLI/native payloads are in `Fixtures/ProPresenter22/Native/HLSInterchange`,
with individual provenance hashes.

## Qualified adapter and limits

The adapter permits only `Action.MediaType.element` selecting
`Media.video.source.hls`, identity schema `"1"`, valid occurrence/asset UUIDs
and a nonempty HTTP(S) source. It does not synthesize a MediaStore record or
change any identities/locators. File locators, provider/container identities,
effects, transitions and playback markers remain gated. The action's entire
media subtree uses the pinned native descriptor, including UUID children;
unknown fields/enums are errors even for target 22. Other native media retains
its previous gates. The root `Media.hls_stream` variant, fills and target 21
remain unsupported. Transport/layer values are preserved without executing them.

Tests reproduce the earlier target-22 rejection, then cover all three original
native exports, unknown parent/source/identity fields, unknown enums, malformed
identity, stale root/file URLs, file-provider metadata, effects/markers, HLS
fills and the alternate root variant. CLI tests preserve complete media through
an edit and media-free bundle; target-21 bundling and static rendering fail
without replacing existing output or changing source bytes.

The final full suite passes **460 core, 97 CLI and one harness** tests with the
same nine known rendering issues. SwiftFormat, SwiftLint and embedded schema
freshness pass. With ProPresenter and its helper stopped, both localhost access
logs remain unchanged through these tests (46 and 16 native requests), proving
zero validation/edit/bundling/render-test downloads.
