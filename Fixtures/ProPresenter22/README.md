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

`Native/LookTheme/Theme.loro` and `Theme.vector` retain the owned Deep Look Theme
stream (`e90a8c1e-a43f-5688-8d49-70cf33b1a6e7`) from the original retained
snapshot. Its active slide geometry, fills and RTF agree with the independently
exported `Interchange/MetadataFreeTheme/Theme`. `LookAPI.json` is the unmodified
local API response for the separately created **ProCRUD Native Look Acceptance**
preset in the disposable local workspace. `WorkspaceThemeURL.json` retains only
that preset's native Theme URL value, as a typed diagnostic projection. The app
authored it with ROOT_CURRENT_RESOURCE relative to the Workspace. No full
Workspace configuration/history, hardware data or recording/account settings
are included. See `Internal/Research/Format/ProPresenter22WorkspaceConfiguration.md`.

`Interchange/NonemptyPlaylist.proPlaylist` is an unmodified native export from
22 beta 369098875, macOS 27.0.1, collected October 15, 2026. The separately created
**ProCRUD Native Playlist Acceptance** playlist contains an owned colored header
and two occurrences of the owned ProCRUDTarget22Acceptance Presentation; the
second occurrence is hidden. Include media within presentations was enabled.
The archive contains only `data` and the owned Presentation; no private export
manifest is included. Native export assigns fresh playlist/item UUIDs while
retaining item semantics and the referenced Presentation.

`Native/Playlist/` contains that disposable workspace's unmodified shared
PlaylistLibrary snapshot/vector (`f1d34fe9-54bc-5cce-aa9b-975968deaeae`), its
matching client node expansion state, and the owned referenced Presentation
snapshot/vector (`bfa7b647-93ab-5ee6-b397-ec61b08bcfee`). Shared history contains
only the initial default empty playlist and the owned acceptance playlist,
including its earlier one-item state. No private library content or account
state is included. The shared snapshot SHA-256 is
`81e9442492e3477b590dc406dc4bcc8d4b33f87faebb2088b7b79f3c0131c9db`.
The client snapshot SHA-256 is
`03abe6b4735627840bc50d6c3a3c7726fb260f2fb350f0658adccb483de2544c`.
These fixtures qualify standard playlist materialization and client expansion
joining, not connected-plan overlays or native playlist edits.

`Interchange/PortablePlaylistNativeReexport.proPlaylist` is the unmodified
native re-export after importing a CLI-generated media-free playlist with
`Presentations/<document UUID>/<original name>.pro` dependencies into that same
disposable local workspace. Collected October 15, 2026, same pinned app/OS.
ProPresenter created a new Presentation identity, retained both occurrences and
hidden state, and applied its normal `-1` receiving-library name collision
suffix. Both links point to that one new document. Cue/group data and CCLI
metadata survive, with native initialization of inactive empty-text/chord-chart
defaults as documented in the playlist research. SHA-256:
`301bf3c06bee3e1ab4a722ec6c24b5697172166445258c982b4a559766754d9b`.
See the playlist research for the rejected UUID-only filename experiment.

`Native/Notes/` retains the owned acceptance Presentation before a native Slide
Notes edit, after that independent native multiline Unicode edit, after the
production CLI notes transaction, and after native restart/continued editing.
Each snapshot has its actual version vector. The Presentation stream is
`bfa7b647-93ab-5ee6-b397-ec61b08bcfee`, slide action
`b6f1da61-c874-42c1-b4e9-7fe1148715b3`. Collected October 15, 2026 with the same
pinned 22 build and OS. These histories contain only owned acceptance content.
Native Slide Notes use `Graphics.Text.rtf_data` on the Presentation slide action;
the Presentation's root plain `notes` string remains separate. See
`Internal/Research/Format/ProPresenter22SlideNotes.md` for hashes and acceptance.

`Native/Text/` retains the owned four-cue acceptance Presentation before/after
an independent native Reflow text edit, the production plain-text transaction,
byte-identical native reopen and continued native edit/export, native font-range
formatting, and a production RTF replacement with native reopen/export. Every
snapshot includes its actual version vector. `Replacement.rtf` is the independent
AppKit-authored rich-text input; `RichNativeSlide.png` is an unmodified native
22 Slide Images export, PNG without background, Include Media Actions enabled,
854×480, collected October 15, 2026 on the same pinned app/OS. This image records
a remaining CLI layout difference; it must not be regenerated by the renderer.
See `Internal/Research/Format/ProPresenter22SlideText.md` for identities, hashes,
transaction evidence and the explicit text-build/rendering limitations.

`Native/Arrangements/` contains independent native Master selection and committed
manager naming/duplication controls, followed by the production rename/select
batch, byte-identical native reopen, native Master continuation and independent
Presentation re-export. Each owned Presentation snapshot has its actual vector;
`edits.json` is the exact production input. Collected October 15, 2026 on the
same pinned app/OS. See `Internal/Research/Format/ProPresenter22ArrangementEditing.md`.
The fixture's native duplication is a control; production duplication remains
unimplemented.

The owned media actions/fills in `Native/MediaIdentity/` also serve as the
positive inputs for constructed macro/prop collection, Workspace mask, stage
layout and playlist-template traversal tests. These are reader tests, not native
write fixtures. `Internal/Research/Format/ProPresenter22MediaTraversal.md`
records the 56-file descriptor closure and independent 946-occurrence native
corpus comparison; private configuration snapshots are not checked in.
