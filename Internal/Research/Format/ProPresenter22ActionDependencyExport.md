# Native action-definition workspace export

October 16, 2026. ProPresenter **22 beta build 369098875**, macOS **27.0.1**,
signing team **97GAAZ6CPX**. The user explicitly reconfirmed that the local setup
is disposable and authorized all needed test changes. No account, Cloud service,
remote plan refresh or credential access was used.

## Separate artifact and dependency boundary

`workspace export-dependencies ROOT --playlist UUID --output NEW_DIRECTORY`
creates a separate legacy-workspace directory for native target-22 import.
It does not disguise configuration files as a `.proPlaylist` or merge them into
an existing native store. Native standalone playlist import removed the synthetic
external Macro header action; the workspace route preserves definitions and their
references together.

The exporter selects the requested library playlist, follows exact local
Presentation links, and traverses actions recursively. Macro, timer, Look, Prop,
message, clear-group and stage-layout selectors resolve typed definitions by UUID
or a unique explicit name. Referenced media/audio playlists retain their item
identities. Message timer tokens and name-based Theme links with explicit slide IDs have
separate reference handling. Theme document-UUID/index-only selectors are gated
because native Theme document IDs change on workspace import. Unmapped/provider/runtime/device/preset dependencies
remain errors, rather than fabricated definitions. A document-trigger action
whose native target identification is obsolete still cannot be resolved safely.

Configuration roots are copied as owning collections. This deliberately includes
their remaining definitions, metadata, order and transitive dependencies; an
unavailable dependency elsewhere in such a copied collection also blocks export.
Cycles register before traversal, and every Presentation/file asset is packaged
once. The existing file locator, identity, content-collision and coherent native
MediaStore checks also apply. ROOT_SHOW points to the copied workspace files.
HLS stays remote. Unknown fields in the prepared native dependency representation
are errors. Ordinary raw/configuration writers retain their original gates.

All work happens in a sibling staging directory. Missing dependencies and
interchange errors aggregate before publication; existing outputs and native
source destinations are rejected. The completed directory is installed with an
exclusive atomic rename. No source document, MediaStore or managed asset is
changed by export. A separate stopped-writer/preflight-qualified production
`workspace apply` transaction linked the owned source Presentation into its test
playlist; that fixture preparation is distinct from the read-only exporter.

## Native controls and receiving-workspace acceptance

A native **ProCRUD Dependency Macro** was created with three independent actions:
**Segment Countdown**, **ProCRUD Native Look Acceptance**, and the owned
**SharedRectangle.png**. The Look selects the owned **CLI Template Ordering**
Theme. An independently authored blank Presentation references that Macro.
Native legacy import created **OwnedDependencySource**
(`f020ebdb-ef65-4fab-b719-6f3893847e39`); its malformed one-off playlist input was
rejected by the app. The qualified production playlist writer then created the
correct link. The CLI exports exactly six document files plus the shared image:

- `Playlists/Library`
- `Libraries/Default/Owned Dependencies.pro`
- `Configuration/Macros`
- `Configuration/Timers`
- `Configuration/Workspace`
- `Themes/CLI Template Ordering/Theme`

The final CLI artifact imports through native **Import Legacy ProPresenter Folder**
into **CLIWorkspaceDependenciesVerified**
(`d6e1c748-da06-4e32-83c0-e324473869d6`). Native history retains the Presentation
and its Macro selector, timer definitions, ordered Macro actions, saved Look
mappings and complete Theme values. The imported occurrence/asset association is
**matched / Ready**. Native Macro rename to **ProCRUD Dependency Macro Continued**
retains the Macro/action UUIDs. Independent native Legacy Workspace export emits
21 files with **zero compatibility warnings**. Only owned selected content and
shared histories are retained; machine output bindings are not checked in.

## Two demonstrated interchange corrections

The first workspace artifact wrote native `MacroCollection.macros` only. The app
silently imported an empty collection. Its actual empty native history is retained
as a negative control. Native Legacy Workspace export instead places definitions
in top-level `MacrosDocument.macros` and uses ordered collection ID items.
The adapter now writes that representation; the corrected import retains the
Macro and all three actions. The analogous declared Prop collection layout uses
top-level cues and ordered prop-cue IDs.

The Macro adapter agrees with the independent native export under the pinned 22
descriptor's protobuf value semantics. Explicit versus omitted non-presence
scalar defaults are equivalent; oneof/message presence, repeated order and all
other fields remain exact. Native export additionally writes the obsolete root
Media URL. Native import removes it; tests require that it matches the selected
SourceInfo locator before omitting it for the comparison. The exporter does not
invent a legacy root locator in the stored native graph.

Theme import multiplies the inactive horizontal scroller repeat distance by
element width. Passing through native coordinate units therefore changed six
values in the first received two-template Theme (for example 36,000 became
12,960,000 at width 360). The native Theme-export control from the prior work
independently demonstrates division by width. Applying that conversion to this
separate workspace artifact produces exact source/receiving Theme projections.
Active/non-left or invalid-dimension forms stay gated. Original snapshots and
rendering tolerances are unchanged.

## Scope and validation

Shared saved Looks and logical screen IDs are portable definitions. Client
physical outputs, live Look and running timer state are not copied. Native import
rebuilds logical dimensions from its local display binding: these retained
fixtures record source **1440×900** and receiving **1728×1080**, with the same
logical screen UUID and Look mappings. An attempted unbound compatibility layout
did not prevent that native behavior and was removed. This export does not claim
to clone physical output execution or geometry on another machine.

Native receiving acceptance specifically covers Presentation → Macro → timer /
Look → Theme / file-media. Other mapped selector families have explicit structural
resolution, while physical/runtime/provider/preset and unresolved target cases
remain diagnosed. Full native 22 support, authenticated PCO refresh, template
application/lifecycle, media-store writes and Cloud merges remain separate work.

Fixtures are in `Fixtures/ProPresenter22/Native/ActionDependencies`, with per-file
hashes in `provenance.json`. Regression tests exercise the complete six-document
closure, unchanged source histories, recursive Macro graphs, aggregated missing
dependencies, native collection loss, exact received definitions and atomic output
rejection. Existing 21 images and generated protobuf sources are unchanged.

Final validation: **505 core + 100 CLI + one harness test pass**, with the same
nine known rendering issues. SwiftFormat and SwiftLint pass. The three superseded
receiving workspaces were moved to native Trash after capture; the verified
workspace and owned source remain available, and the original test workspace was
restored as active.

Cleanup of a malformed one-off playlist import through the native context menu
crashed ProPresenter. With the app and workspace helper stopped, the qualified
atomic writer removed that control and the temporary header/timer playlist
(four tree-node deletions). Hash comparison confirmed that only the intended
PlaylistLibrary stream and one receipt changed; all other streams and asset-store
files were unchanged. Native startup initially reported background processes
disabled. System Settings Computer Use access was not approved, so no system
setting was changed. ProPresenter's Retry restored its existing helper; after
dismissing the activation and Cloud setup screens, the original workspace reached
`ProPresenterMainWindow.Ready`, with both temporary playlists absent and the
temporary Macro removed. No crash report was submitted.
