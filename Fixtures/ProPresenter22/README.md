# ProPresenter 22 fixtures

`Interchange/` contains native exports from macOS ProPresenter **22 beta,
build 369098875**, on macOS **27.0.1**, collected October 14, 2026. These are
independently authored test documents, not content from the private library.

- `NativePresentation.pro`: native Presentation export of the CLI-created
  ProCRUD22Probe, an 854×480 slide with a cyan rectangle. Native import assigned
  a new root UUID while retaining nested identities. Contains native 22 metadata.
- `MetadataFreeTheme/Theme`: unmodified payload extracted from the native Themes export of the independently authored
  Deep Look Theme. Its `Deep Look Theme/Theme` payload omits application metadata. The archive
  manifest is excluded because it contains private workspace locations.
- `EmptyPlaylist.proPlaylist`: native Playlist export of an empty standard
  presentation playlist, with Include media within presentations enabled.
- `NativeEditedTarget21.pro` and `NativeEditedTarget22.pro`: fresh CLI-generated
  21-profile and 22-profile rectangle bundles imported into the pinned 22 build,
  edited natively (CCLI song title), and re-exported through Presentation.
  Both files therefore declare native application 22. The profile in the name
  identifies the original CLI input, not a claim of receiving-app 21.4 testing.

The document payloads are unmodified native exports. Tests must not regenerate these with
DocumentFactory. Collection details are in
`Internal/Research/Format/ProPresenter22NativeExperiments.md`. These fixtures
qualify these interchange cases only; they do not qualify native workspace
writes, Cloud, animation, or connected playlist delivery.

`Native/Presentation.loro` and `Presentation.version-vector` are the original
shared stream snapshot and version vector of the same disposable ProCRUD22Probe,
read from a consistent SQLite backup before the native test presentation was
deleted. No other workspace streams or registry/account data are included.
Its native root identity is `48e32307-7a5a-56cc-8cca-0bc82d6079c1`. Tests use
this independent native snapshot to validate the official Swift Loro binding,
then construct disposable SQLite envelopes for integrity and transaction cases.

`Native/Persistence/` contains native before/after snapshots, vectors, the exact
native update and receipt for one CCLI title edit on the independently authored
acceptance probe. `Native/schema-9.sql` captures table/index definitions only.
`Native/LocalCommit/` records the separate disposable local workspace experiment:
original history, a CLI metadata commit, a continued native edit after restart,
the durable receipt, and native Presentation re-export. These snapshots contain
only the owned rectangle presentation and its test metadata, including retained
history; no other workspace documents or account data are included. The update
hash must agree with its receipt, and the native continuation must extend the
CLI-authored version vector. See
`Internal/Research/Format/ProPresenter22LocalPersistence.md` for exact provenance
and the deliberately limited metadata-write acceptance scope.

`Native/MediaIdentity/` contains an unmodified owned two-cue presentation snapshot
and vector. `Interchange/MediaIdentity/NativeBundle.pro` is its unmodified native
Presentation Bundle payload, with the one owned PNG under Media/Assets. The
native standalone export is retained separately as NativeStandalone.pro: that
export omits both media payloads, whereas the bundle preserves them. The two
native occurrences have distinct reference UUIDs and share one asset UUID with
identity schema string `"1"`. No private manifest or default stock media is
included. Exact provenance and scope are in
`Internal/Research/Format/ProPresenter22MediaIdentity.md`.
