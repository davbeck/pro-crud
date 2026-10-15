# ProPresenter 22 implementation status

Tracking `ProPresenter22Support.md`. This branch is a **partial implementation**
and must remain a draft; it does not satisfy the plan's completion criteria.
Do not describe the entire ProPresenter 22 feature set or native writes as supported.

| Plan area | Implemented | Remaining gate/work |
| --- | --- | --- |
| Storage boundary | Explicit-root storage inspection; native markers take precedence over leftovers; expanded exports distinguished; native access rejected in legacy readers/writers/Look/media/batch paths | Registered legacy preference discovery, broader ambiguous/mixed fixture matrix |
| Export compatibility | Optional application metadata; independent 22 raw/Theme/empty-playlist fixtures; empty playlist expand/rebundle; absent metadata and unknown-field preservation | Fresh nonempty/connected playlists, populated/media bundle and native edit/reimport acceptance across every export path |
| Targets and conversion | Typed 21/22 profiles; default 22 construction/export; retained 21 construction; JSON results; recursive wire/enum issues; known v2/media gates; atomic failed export | Complete versioned schemas/adapters; dependency/feature conversions and receiving-app 21.4/22 qualification; no lossy fallback is currently qualified |
| Schema | Existing generated 21 decoder retained; independently pinned 53-file 22 descriptor set with binary provenance, CRDT map/tree/atomic annotations and versioned binary materialization; repeated timeline and nested KeyMapping descriptor tests; schema resource checks pass | Full 21.4 catch-up and explicit cross-target KeyMapping/timeline conversions. Existing generated Swift drifts with installed protoc-gen-swift 1.38.1 through generator output changes; do not hand-edit generated files to suppress that check |
| Native reader | System SQLite read-only/in-memory WAL snapshot, schema-9 gates, IDs/scopes/availability/checksums/counts/vectors; pinned official Swift Loro; registry metadata; typed library membership, logical presentation references, Master/group/arrangement ordering, playlist trees; 336 native-export comparisons pass; all 358 retained Presentation/Theme streams materialize without unmapped fields; separate-target export and pixel-exact native probe render | Playlist/configuration protobuf materialization, Looks/screens and media resolution; bounded external-writer retry matrix |
| Native media | Native identity/provider/HLS fields are diagnosed and unsafe legacy operations rejected | Authoritative native media resolver, identity/reference/asset adapters, dependency export and stale projection cases |
| Native writes | Targeted existing-Loro metadata operations; atomic SQLite stream/receipt publication, no-op/idempotency/conflict/rollback tests; pinned contributor harness; disposable local CCLI commit survives native restart, continued edit and native re-export | Production CLI integration and remaining edit families: placement/group/build graphs, library locations, creation/deletion/duplication, playlists/PCO, templates and media transactions; corresponding native acceptance |
| New features/rendering | Existing unknown bytes preserved; unsupported active representations are visible and gated; existing 21 snapshots retained | Native fixtures and independent inspect/preserve/edit/render/package statuses for animations, stickers, APlay, HLS, ProDisplay, disabled screens, PowerPoint backgrounds and new rendering/PCO cases |
| CI/docs/release | Distinct immutable-fixture 21/22 checks plus full suite; scoped public docs/skills; native test guidance; Loro license packaging; arm64 runtime and x86_64 compile | Extend existing 21 regression coverage for changed adapters; native 22 acceptance for new behavior; signed universal package and transitive dependency license audit |
| Cloud | Deferred by the user; discovery reports local/Cloud metadata and the writer rejects Cloud registrations | Outside the current local implementation scope |

Evidence is in `../Research/Format/ProPresenter22Reader.md`. The official Swift
binding decoded all 385 retained native snapshots, with exact deep-value agreement
against independent official WASM projections. This qualifies diagnostic decoding,
not semantic materialization or editing.

`../Research/Format/ProPresenter22TargetAcceptance.md` records fresh 21-profile
and 22-profile bundles importing successfully into the pinned 22 build, a
committed native metadata edit, and native re-export with retained nested IDs.
The two generated MISC test presentations remain available for review.

Local validation: full Swift suite (308 core + 78 CLI + one harness test; eight existing known
rendering issues), CLI acceptance, SwiftFormat/SwiftLint, protobuf resource
freshness, and bundled four-document/99-variation Theme freshness pass. The Theme
generator now fixes only AppKit's informational RTF writer-version header: all
140 host-generated differences were exactly that header; the shipped asset and
reference images remain unchanged. The native harness adds a separate passing
negative-control test and the pinned positive local metadata experiment. x86_64 compilation passes. An x86_64 runtime smoke test
can use Rosetta; a separate Intel host is not required and this check does not
block local implementation.

`../Research/Format/ProPresenter22LocalPersistence.md` records the first qualified
local metadata commit: exact native update/receipt hash, only one affected shared
stream, native restart/continued editing/re-export, integrated writer WAL setup,
and a byte-identical real no-op. No production CLI native edit command is exposed
by the contributor experiment.

The existing native-exported 21 fixtures, reference images, documentation and
tests are the 21 regression baseline. Reuse them rather than requiring a new 21
installation to continue implementation. Fresh receiving-app acceptance is
useful for changed conversion semantics that the existing corpus cannot prove;
it is not a prerequisite for unrelated code or local 22 experiments. Separate
account/helper isolation is needed when actually switching native app versions,
not for every test against the existing corpus.

The installed 22 test instance is authorized for local experiments. Stop actual
workspace writers and use disposable copies for direct persistence experiments.
No active Cloud connection is needed for local reads, exports, media resolution,
local editing, or their tests. The plan explicitly permits local/offline writes
without qualified Cloud merges. The absent Cloud workspace limits only Cloud
write claims; it does not block the remaining local implementation.
