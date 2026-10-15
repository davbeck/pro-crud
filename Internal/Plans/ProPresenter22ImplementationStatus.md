# ProPresenter 22 implementation status

Tracking `ProPresenter22Support.md`. This branch is a **partial implementation**
and must remain a draft; it does not satisfy the plan's completion criteria.
Do not describe the entire ProPresenter 22 feature set or native writes as supported.

| Plan area | Implemented | Remaining gate/work |
| --- | --- | --- |
| Storage boundary | Explicit-root storage inspection; native markers take precedence over leftovers; expanded exports distinguished; native access rejected in legacy readers/writers/Look/media/batch paths | Registered legacy preference discovery, broader ambiguous/mixed fixture matrix |
| Export compatibility | Optional application metadata; independent 22 raw/Theme/empty-playlist fixtures; empty playlist expand/rebundle; absent metadata and unknown-field preservation | Fresh nonempty/connected playlists, populated/media bundle and native edit/reimport acceptance across every export path |
| Targets and conversion | Typed 21/22 profiles; default 22 construction/export; retained 21 construction; JSON results; recursive wire/enum issues; known v2/media gates; atomic failed export | Complete versioned schemas/adapters; dependency/feature conversions and receiving-app 21.4/22 qualification; no lossy fallback is currently qualified |
| Schema | Existing generated 21 decoder retained; known 22 representations surfaced as unsupported; schema resource checks pass | Full 21.4 catch-up/22 schema inventory and generation; KeyMapping/timeline/cardinality adapters. Existing generated Swift drifts with installed protoc-gen-swift 1.38.1 solely through generator output changes; do not hand-edit generated files to suppress that check |
| Native reader | System SQLite read-only/in-memory WAL snapshot, schema-9 gates, IDs/scopes/availability/checksums/counts/vectors; pinned official Swift Loro; diagnostic inventory/dump and registry metadata | Typed semantic materialization for libraries/playlist trees/order/arrangements/Looks/screens/configuration; domain reference resolution; bounded external-writer retry matrix |
| Native media | Native identity/provider/HLS fields are diagnosed and unsafe legacy operations rejected | Authoritative native media resolver, identity/reference/asset adapters, dependency export and stale projection cases |
| Native writes | No native writes exposed; contributor offline environment preflight and failure manifest | Controlled persistence experiments, operations/history/receipts, conflicts, atomic multi-stream/media commits and native restart/edit/render acceptance |
| New features/rendering | Existing unknown bytes preserved; unsupported active representations are visible and gated; existing 21 snapshots retained | Native fixtures and independent inspect/preserve/edit/render/package statuses for animations, stickers, APlay, HLS, ProDisplay, disabled screens, PowerPoint backgrounds and new rendering/PCO cases |
| CI/docs/release | Distinct immutable-fixture 21/22 checks plus full suite; scoped public docs/skills; native test guidance; Loro license packaging; arm64 runtime and x86_64 compile | Required pinned interactive native jobs, both isolated app environments, Intel execution, signed universal package and transitive dependency license audit |
| Cloud | Discovery reports local/Cloud metadata; offline preflight requires local native registration | Disposable account/workspace, offline/reconnect/concurrent-writer/delete/tombstone acceptance |

Evidence is in `../Research/Format/ProPresenter22Reader.md`. The official Swift
binding decoded all 385 retained native snapshots, with exact deep-value agreement
against independent official WASM projections. This qualifies diagnostic decoding,
not semantic materialization or editing.

`../Research/Format/ProPresenter22TargetAcceptance.md` records fresh 21-profile
and 22-profile bundles importing successfully into the pinned 22 build, a
committed native metadata edit, and native re-export with retained nested IDs.
The two generated MISC test presentations remain available for review.

Local validation: full Swift suite (276 core + 78 CLI tests; eight existing known
rendering issues), CLI acceptance, SwiftFormat/SwiftLint, protobuf resource
freshness, and bundled four-document/99-variation Theme freshness pass. The Theme
generator now fixes only AppKit's informational RTF writer-version header: all
140 host-generated differences were exactly that header; the shipped asset and
reference images remain unchanged. The native harness adds a separate passing
negative-control test. Intel compilation passes; execution is unavailable on
this host because Rosetta is absent.

Missing external prerequisites: an isolated pinned 21.4 environment, a pinned 22
environment with verified helper/account isolation, a disposable Cloud workspace,
and Intel execution. The local registry currently has two local roots and no
Cloud workspace. Do not install/downgrade shared helpers or fabricate passing
native acceptance to bypass those prerequisites.
