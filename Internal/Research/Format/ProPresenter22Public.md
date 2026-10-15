# ProPresenter 22 beta: public and HTTP API audit

Investigated October 14, 2026 (America/Los_Angeles). Scope: macOS ProPresenter 22 build 369098875 and the public references available that day. This is research evidence and implementation planning, not a claim of completed support. No state-changing HTTP API operations were performed.

## Installed target

`/Applications/ProPresenter.app/Contents/Info.plist` reported `CFBundleShortVersionString = 22` and `CFBundleVersion = 369098875`. Network enabled and port `50001` were established from local preferences.

The read-only `GET http://127.0.0.1:50001/version` returned `platform: mac`, `os_version: 27.0.1`, `host_description: ProPresenter 22`, and `api_version: v1`. The machine name is omitted here. Keep the unversioned `/version` probe and choose `/v1` from that response; no API-path rename to v22 is indicated.

## Official release inventory

[Release notes](https://www.renewedvision.com/propresenter/download) identify 22 beta, build 369098875, October 14, 2026. New features: Cloud; text animation builds revealing characters, words, or lines with pace, direction and continued motion; animated ProContent stickers; Amazing APlay import; audio/video HLS URL stream actions; ProDisplay export; macOS 27 support. Improvements include disabling configured screens and choosing whether PowerPoint backgrounds import. Relevant macOS fixes cover older presentation text scaling, alternate-theme list scaling, Reflow persistence, multilingual text, custom output targets, Planning Center bundles/playlists, stale active-playlist API data, and nested Planning Center playlist API 404s. These areas warrant compatibility fixtures rather than speculative renderer changes.

The [official feature announcement](https://www.renewedvision.com/blog/whats-new-in-propresenter-22), dated October 14, corroborates the feature inventory. New integrations require preserving identifiers/actions and clear support limits; direct service connectors or account automation are separate optional features, rather than a prerequisite for document compatibility.

## Workspace migration and Cloud

[Getting Started With Cloud](https://support.renewedvision.com/hc/en-us/articles/55701696829715-Getting-Started-With-Cloud-in-ProPresenter) describes a new workspace format and one-time upgrade. The upgraded workspace is initially local; Cloud conversion is separate. Cloud covers presentations, playlists, media, themes, macros and other workspace content. Smart playlists convert to standard media playlists during Cloud conversion. Screens/output configuration remains per computer. Implications: distinguish legacy, local v22 and Cloud v22; do not infer Cloud use from the upgrade; separate machine configuration from synchronizable content; test smart-playlist conversion.

[Downgrade instructions](https://support.renewedvision.com/hc/en-us/articles/55756898162451-How-to-Downgrade-from-ProPresenter-v22) describe major internal changes for Cloud. v22 edits do not appear in 21.4, and later 21.4 edits do not automatically re-import to v22. The supported bridge is **File → Export → Legacy Workspace** in v22, followed by **Workspace Manager → Import Legacy ProPresenter Folder** in 21.4. macOS downgrade also requires removing the newer Workspaces helper; that helper is not presentation/media storage. Implications: retained legacy data is stale rather than live; provide explicit format/version reporting and test the export/import bridge.

[Cloud best practices](https://support.renewedvision.com/hc/en-us/articles/45519344429587-Best-Practices-for-ProPresenter-Cloud) says Cloud content is also local for offline operation, reconnects can conflict, and syncing covers whole workspaces without selective-file sync. Bibles, account sign-ins, screen/output setup and external media are excluded. Workspace edits/deletes propagate. Timed Pause Sync survives quitting. Implications: establish coherent snapshots and helper coordination before offering writes to an active v22 workspace. Account/subscription internals are outside this investigation.

## Public HTTP API compatibility

The [official reference](https://openapi.propresenter.com/) and [specification asset](https://openapi.propresenter.com/swagger.json) were fetched October 14. The asset's HTTP `Last-Modified` was **June 25, 2025 12:39:55 GMT**. It was 323,905 bytes, SHA-256 `073e12d4ca6fd25e47453780d7b260603320c6196c965a6c7dd37f1b259a1312`. It remains JavaScript beginning `var openapi_spec =`, OpenAPI 3.0.2, display version 1.0, with 194 path templates and 231 operations. No published Cloud/workspace, animation/sticker, HLS creation, Amazing or ProDisplay endpoint family appeared. This does not prove the application lacks private operations; private operations must not be presented as official public API.

Read-only routes succeeded for libraries, playlists, themes, screens, media/audio playlists, macro collections and looks. `/v1/status/slide` returned 204 with no slide active.

| Read endpoint | Installed 22 result | Hosted specification |
| --- | --- | --- |
| `/v1/libraries` | Bare `[{uuid,name,index}]` | `[{id:{uuid,name,index}}]` |
| `/v1/playlists` | `[{id,field_type,children}]` | `type` and `playlists` for groups |
| `/v1/themes` | Object `{groups,themes}` | Array of groups |
| `/v1/status/slide` | `204 No Content` with no active slide | 200/404 documented |

These are observed runtime-versus-documentation differences, not established v22 regressions. Older vendored protobufs already model libraries as identifiers, playlist children, and theme results as groups/themes; upstream 21.4 agrees. Compare a 21.4 runtime before attributing these differences to v22.

### API skill plan

- Keep `propresenter-api` independent and self-contained; do not introduce an HTTP API wrapper into pro-crud.
- Add installed-version payload inspection and empty read responses to troubleshooting, using sanitized response fixtures with build provenance.
- Verify chunked/SSE subscriptions and reconnects, binary thumbnails, UUID resolution, playlist arrangements, and Planning Center routes against the installed build using authorized test data.
- Keep exact methods and mutation bodies grounded in official schemas. Record discrepancies with version/build and observed JSON rather than inventing endpoints or fields.

The initial raw snapshots were lost during a system interruption that cleared `/private/tmp`; this document retains their observed results. Repeated probes and the identical hosted specification were saved under `.build/pro22-investigation` as `api-readonly-current.json`, `hosted-swagger.js`, `hosted-swagger.json` and `hosted-swagger-headers.txt`. The later API snapshot reflects test content added during the investigation and again returned 204 from `/v1/status/slide`.

## Upstream protobuf baseline

The [upstream repository](https://github.com/greyshirtguy/ProPresenter7-Proto) is the primary source for its own unofficial reverse-engineered definitions. Latest `autogen-proto` update was [6931e91501c2245de77aa8b9974f9f78532d805c](https://github.com/greyshirtguy/ProPresenter7-Proto/commit/6931e91501c2245de77aa8b9974f9f78532d805c), June 30, 2026 01:22:39Z, titled `Update protobufs for ProPresenter 21.4,352583705`. Current master `1c019ab1897286c9bc611f0a10f9f7da8d01dcbb` only changed README October 13. No upstream 22 snapshot was available. The 21.4 tree already contains split API definitions and `workspace.bootstrap.proto`, `workspace.calls.proto`, `workspace.entities.local.proto`, `workspace.entities.remote.proto`, `workspace.notifications.proto`, and `psbWorkspace.proto`.

Extract installed 22 descriptors and compare against both vendor and that exact 21.4 baseline. An upstream vendor refresh alone cannot establish v22 support. Regenerate Swift through repository scripts after intentional schema changes, preserving unknown protobuf fields.

## Installed 22 descriptor comparison

### Extraction provenance and limits

Serialized `google.protobuf.FileDescriptorProto` data is embedded in
`/Applications/ProPresenter.app/Contents/Frameworks/ProCore.framework/ProCore`.
The installed universal binary was 460,782,208 bytes and had SHA-256
`793c50c3e28dc742a06eb6ac2029478843372a3667963302737e0f746d273e09`.
A read-only scanner recovered **165 distinct named proto3 descriptor files**,
containing **2,049 nested/top-level message definitions**. This count includes
private runtime/helper and analytics messages, not 2,049 persisted document
formats. The scan is not a completeness claim for all protobuf dialects or all
app/framework binaries. It rejected 34 candidate byte sequences; system proto2
reflection definitions are not treated as removed product schemas.

Descriptors were parsed by wire field number, nesting, scalar/message type,
cardinality, oneof membership and enum values. Representative extracted blobs
were independently decoded with `protoc --decode=google.protobuf.FileDescriptorProto`.
Multiple embedded copies differ in generated JSON-name/source metadata;
comparison disregards `json_name` metadata. The first recovered descriptor per
filename was used for the field inventory. A second scan compared all **5,634 recovered copies** and found no differences
in the normalized message/field/enum/import structures across copies and both
architectures. A release schema generator must additionally retain custom
options and verify a complete import graph rather than promoting this forensic
scanner into production.

The exact upstream 21.4 commit identified above and current vendor sources were
compiled with `protoc --include_imports` into descriptor sets. Comparing message
identities against upstream 21.4 found 67 changed and 439 newly present messages;
many new messages are private helper/runtime additions. Comparing vendor found
110 changed common message identities. Broad added/removed counts are affected
by the vendor's old nested API naming and schema organization and must not be
reported as an equal count of new features or removed file support.

Private artifacts and the one-off extraction/comparison scripts are under
`.build/pro22-investigation`: `installed22-descriptors/`,
`installed22-descriptors.json`, `installed22-normalized.json`,
`upstream21.4-schema.pb`, `vendor-schema.pb`, and the respective
`*-vs22-delta.json` files. No captured descriptors, account schema copies, app
binaries, or user media are proposed as shipped fixtures. No private RPC or
account endpoint was called.

### Confirmed changes from upstream 21.4

Field notation below uses protobuf field numbers. These are schema facts;
ordering precedence, migration and rendering still require native fixtures.

| Area | Installed 22 schema change | Implementation consequence |
| --- | --- | --- |
| Presentation order and groups | `Presentation.cue_group_placements=24` adds UUID nodes containing group metadata or a cue marker; `Arrangement.group_identifiers_v2=4` and `CueGroup.cue_identifiers_v2=3` are repeated UUIDs | Reconcile v2 authority with legacy membership/order before changing sorting, arrangements, duplication, deletion, group edits or UUID remapping |
| Build order | `Slide.element_build_order_v2=8` is repeated UUIDs | Preserve and resolve v2 build order in static/animated rendering and build/text-delivery edits |
| Playlist graph | New `PlaylistNode` UUID/name with group, playlist or item oneof; `PlaylistDocument.playlists=7`, `live_video_playlist_nodes=8`; new local companion nodes/document | Support node graph and local/shared separation as well as legacy root tree; validate group/item references and per-client state |
| Library wrapper | New `LibraryTreeDocument.rootLibrary=1` around existing `Library` | Recognize the new intrinsic/library root without treating it as a presentation |
| Media identity | `Media.container_id=9`, `asset_id=10`, `identity_schema_version=11` | Distinguish occurrence/reference/asset identity and preserve all three through media replacement, archive rewriting and duplication |
| HLS | `Media.hls_stream=12` is a new media-type oneof, with drawing/audio/transport/video and string URL; new `SourceInfo` file/HLS oneof, attached to audio/image/video source fields 4/3/6 | Classify remote streams before local file validation or packaging; preserve transport and drawing state without downloading live sources |
| Provider linkage | New `ProviderInfo` contains provider, item, rendition, content-version and parent strings. Added at `Media.provider=13`, `Presentation.provider=25`, `PresentationSlide.provider=6`, `Playlist.provider_info=17`, `PlaylistItem.Presentation.provider=6`; also present in new playlist nodes | Preserve provider-owned relationships, rendition/version data and refresh linkage during local overlays; do not pretend an ordinary local copy is still refreshable without testing |
| Text animations | `Effect.EffectVariable` adds grouping=8, motion=9 and motion_style=10 oneof alternatives; grouping enumerates character/word/line/all, motion none/grow/shrink/up/down and style subtle/standard/dramatic. Runtime `RenderLayer.text_animation=15` contains segment bounds and texture atlases | Saved builds still use Transition/Effect; preserve new variables and inspect native effect IDs/parameters. Runtime texture data is not a new saved slide format. Rendering needs real animation samples |
| Key mappings | Fields 101–106 now reference `KeyMapping.CollectionElementTypeKey`, with UUID `parameter_uuid=1` and string `parameter_name=2`, replacing `CollectionElementType` | Same field tags do not guarantee nested message compatibility: old field 2 was a UUID message, new field 2 is plain text. Test both versions, route by proven root/version shape, and prevent corrupt remapping |
| Copyright tokens | `CopyrightLayout.tokens_v2=3`, repeated Token | Reconcile v2 token order with legacy representation for copyright edits, text links and export |
| Calendar exclusions | `Calendar.Event.recurrence_excluded_dates_v2=10`, repeated Timestamp | Preserve recurrence exclusions and compare native import/export; do not flatten recurrence based solely on legacy fields |
| Timelines | `TimedPlayback.Sequence` field 3 changes from singular `presentation` to repeated `presentations`; `SequenceItem.presentation_uuid=8` is added | Old singular decoding may merge multiple message occurrences rather than represent the list. Qualify timeline inspection/editing and reference remapping explicitly |
| Workspace metadata | `ProPresenterWorkspace.media_identity_schema_version=17`, `bundled_theme_rollout_sequence=18`; local workspace adds record_settings=7 and new recording-local preset/stream roots | Separate shared content/version state from machine-local recording destinations and rollout state |
| API macro request | `API_v1_Macro_Request.PutMacro.actions_change=5` introduces a nested ActionsChange | This private serialized API message does not change the published HTTP mutation contract by itself; recheck installed HTTP docs before advising a new body |

No fields were removed from the listed common persisted document messages
relative to upstream 21.4. Internal feature flags removed old fields 17/18 and
added text-animation/persistence fields 19/20. Internal document/workspace helper
messages changed substantially: local/remote metadata now says `schema_version`
instead of `pro_version`; document intrinsic enum ordinals shifted after adding
CommunicationDevices; document roots gained stored/effect/transition kinds;
several private calls changed field numbers/types and gained generation,
operation and causal-version data. Consequently, old private helper descriptors
must not be used as an API contract or as a native write implementation.

### Features whose storage still needs native evidence

- **Stickers:** the recovered ProContent download enum adds
  `ASSET_TYPE_STICKER=7`, with sticker analytics messages. No separate persisted
  sticker/lottie media oneof was found. Native export must establish whether its
  animation is a JSON/vector asset, ordinary media or an effect dependency, and
  how transforms, color changes, alpha and timing are persisted. Existing
  JSON-named assets in private exports are clues, not sufficient format proof.
- **Amazing APlay:** generic provider roots and private content-provider
  rendition definitions distinguish FILE/HLS delivery. `ProviderInfo` is the
  persisted preservation target, but a native imported sample is required to
  establish the actual provider string, playlist/item hierarchy, refresh
  ownership and HLS/file combinations. Do not infer account integration needs
  from document preservation requirements.
- **ProDisplay:** new private `prodisplay.call.Export` has create/replace
  operations carrying `rv.data.Presentation`, destination folder/tag identifiers
  and target version. This supports a service-export interpretation. It proves
  no new local file extension. A native export sample remains the acceptance
  gate for any new package/format support; private RPC discovery does not
  authorize or require implementing the service client.
- **Disabled screens:** `ProPresenterScreen.rendering_enabled=9` exists in the
  installed descriptor and upstream 21.4 but is missing from the checked-in
  vendor. Treat its schema addition as stale-vendor catch-up, and test v22's new
  native UI behavior and per-machine scope separately.

### Vendor backlog distinct from v22 changes

The vendor predates several 21.4 features. Its refresh needs reviewed compatibility
for `Graphics.Text.alternate_texts=13`, ligature style, original font/character
sizing, media HDR/alpha/blur/hardware decoding/retrigger fields, AirCast,
additional data links, capture/prop/timer actions, playlist arrangement names,
cloud screen/input metadata, and output delay/HDR configuration. Some nested
enums and Font moved to shared message definitions without necessarily changing
wire values. Legacy social-media fields absent in current descriptors must still
round-trip as unknown data; a schema refresh must not delete support by rebuilding
old messages. Separate this catch-up work from claims about novel v22 semantics.
