# Local media identity and export paths

Collected October 15, 2026 with macOS ProPresenter 22, build 369098875, on
macOS 27.0.1. The authorized disposable **ProCRUD Local Persistence Test**
workspace was used. No Cloud account or service was used.

## Controlled input and independent observations

The CLI created an 854×480 presentation named NativeMediaIdentity. Two cues
reference the same independently authored PNG (the native-exported cyan
rectangle probe). The legacy input deliberately shares one Media UUID, as
required by its single asset identity model. A Presentation Bundle was imported
through the native UI.

The resulting shared Presentation stream is
`12080506-ffda-5a60-9e6d-4c99a9a8f82f`, at Default/NativeMediaIdentity. Its
unmodified Loro snapshot/vector are in
`Fixtures/ProPresenter22/Native/MediaIdentity`. Both media occurrences have
identity schema **string** `"1"`, distinct reference UUIDs, and one shared asset:

| Occurrence UUID | Asset UUID |
| --- | --- |
| 80eb4ec7-9507-5bb1-be56-1b42ab4f077a | 322e4d08-cba2-4b08-bd43-842ae317f6df |
| a334238d-6c81-5441-85f6-3c61ffaf9004 | 322e4d08-cba2-4b08-bd43-842ae317f6df |

Each image's `file.local_url` is ROOT_SHOW-relative
`Media/Assets/SharedRectangle.png`; `source.SourceType` has no selection. The
root Media URL is absent in the stored snapshot. The current file at that exact
relative path exists; basename lookup and the derived projection cache are not
needed. Container and provider fields are absent in this probe.

Native **Presentation Bundle** export preserves both media actions and these
identity classes. Its unmodified `.pro` payload additionally populates the root
Media URL with the same ROOT_SHOW-relative path. The original PNG is included.
Only those owned payloads are checked in under
`Fixtures/ProPresenter22/Interchange/MediaIdentity`; the archive manifest, which
contains workspace locations, is excluded.

Native standalone **Presentation** export leaves each media action's basic
UUID/name/label/enabled envelope but omits its type and media payload. The
presentation-slide action remains. The unmodified export is retained as
NativeStandalone.pro. This export path therefore cannot qualify media
preservation for this probe. No adapter should silently reproduce that loss.

A second independently created control set the action's image subtype before
import. Its standalone export also omitted media, while its native bundle kept
media. The original native bundle keeps media even though that subtype is
absent. There is no demonstrated subtype writer defect, and no speculative
subtype change was made.

## Qualified reader scope

`MediaReference` reads the pinned 22 descriptor's identity/locator fields while
retaining the original protobuf/Loro separately. It traverses nested actions and
fills, obeys protobuf message merging and active oneofs, and distinguishes
ROOT_SHOW paths, ordinary absolute/relative URLs, and HLS remote sources.

`workspace media ROOT [--hash-files]` reads available shared Presentation/Theme
streams and presentation/media/audio playlist trees from one database snapshot.
Playlist inspection includes nested items and the separate live-video tree;
client node state is checked separately rather than merged into content. Tree
metadata is encoded through the pinned PlaylistNode descriptor for dependency
traversal, without flattening or inventing a legacy playlist root. Unknown node
fields invalidate a stream's complete enumeration. Automated tree tests use
real Loro containers with owned native media actions; these constructed trees
exercise traversal, not native playlist mutation acceptance.

The retained 385-stream SQLite snapshot enumerates **927** occurrences: 828 in
Presentations, 75 in Themes and 24 in PlaylistMedia. PlaylistLibrary/PlaylistAudio
and all three client playlist streams inspect successfully with no occurrences.
All 927 reference IDs are distinct; there are 385 asset IDs. An independent
recursive scan of the previously captured official WASM projections matches the
complete `(document, reference, asset, schema)` multiset exactly, with zero
missing/extra occurrences. Twenty-one remaining stream scopes/kinds are explicit
as uninspected (including PlaylistTemplates and Workspace); this is not complete
workspace dependency validation. The retained snapshot has no copied media tree,
so that comparison qualifies identity enumeration, not file availability there.

The command reports each occurrence, exact local
files and optional SHA-256 agreement, diagnostics, and every uninspected stream.
ROOT_SHOW lookup is anchored to the selected root, so a moved workspace does
not fall back to a stale absolute path or a same-basename file. Optional hashing
uses regular files and a 30-second total budget. Remote/live sources are never
downloaded or mislabeled as missing local files. Native asset-store membership
is explicitly unverified: file existence does not establish that registry role.

## Remaining qualification

This probe proves import-time reference/asset separation and read-only file
availability. It does not qualify new native media writes, replacements,
duplication, relocation, provider refresh, all MediaStore roles, or a full
migration mapping. Media editing/packaging gates remain until the writer keeps
all locator representations coherent and receiving-app behavior is verified.
Existing 21 fixtures remain the regression baseline for its asset UUID model.
