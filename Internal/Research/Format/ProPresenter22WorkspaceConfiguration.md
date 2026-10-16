# Native local workspace configuration view

October 15, 2026; ProPresenter 22 build 369098875, macOS 27.0.1. The retained
385-stream consistent snapshot and native Legacy Workspace export remain the
independent comparison sources. No Cloud connection was used.

The shared and client Workspace streams have the same document UUID and
different owning scopes. Saved `audience_looks` and logical
`cloud_output_screens` belong to shared state. Physical `pro_screens` and
`live_audience_look` belong to client state. The shared field's internal name
does not make reading these local definitions a Cloud-service operation.

`workspace configuration ROOT` exposes this selected view without flattening
the whole configuration document. Saved Looks and the live Look remain separate,
including the live Look's original saved-Look identity, ordered screen mappings,
layer/mask switches and native Theme references. A logical screen joins its
physical local configuration by UUID. Missing local configuration remains
explicit; it is not filled from a legacy Workspace file. An explicit false
rendering flag stays false, while an absent flag remains absent.

The captured snapshot contains ten saved Looks, one separate live Look, four
logical screens and four matching local screens. All seven referenced Theme
documents resolve by exact ROOT_SHOW-relative `Themes/.../Theme` core path to
shared native stream identities. A stale absolute path or another Theme with
the same basename cannot substitute for that identity. Missing/unavailable Theme
references remain visible.

An independent wire decoder of the native Legacy Workspace export agrees with
the view for every saved Look's UUID/name and ordered screen/Theme/template
mappings, the live Look's identity/name/mappings, and all four ordered screen
UUID/name/type triples. All four captured rendering flags are explicitly true.
Constructed Loro tests additionally cover false/absent flags, missing client
state, missing/unavailable Themes, duplicate mappings/screens, mismatched
shared/client identities, unsafe paths and unknown selected visual fields.
Those constructed cases qualify the reader's representation/diagnostics, not a
native disabled-output execution experiment.

Other root fields (including recording, device and audio configuration) are
listed by field name as uninspected. Their values are not included in this
report or copied into fixtures. Unknown fields within a selected Look/screen
block that view instead of disappearing. The original histories remain intact;
this is not a writable or complete interchange Workspace projection. The static
Look scope qualified below is separate from physical-output execution and
configuration mutation.

## Static native Look rendering

The renderer now selects configuration and Theme content from one native
snapshot. It keeps the shared saved Looks and separate client live Look intact,
matches screen/template UUIDs, and uses the shared logical canvas (or valid local
geometry). A stored disabled flag is reported without enabling output. No client
configuration can still yield a static preview using valid shared dimensions,
with an explicit warning. Native selected-slide media rebasing remains gated;
unused templates and ignored Theme actions do not enter that capability check.
Missing Theme content and dangling template UUIDs fail without legacy fallback.

The unmodified owned Deep Look Theme snapshot/vector are retained separately as
`Fixtures/ProPresenter22/Native/LookTheme`. Its geometry, fills and active RTF
bytes agree with its independent native export. Constructed scoped configurations
test disabled/missing client state, unavailable Themes, dangling template IDs,
selected versus unused media, and ignored Theme actions against that source.

A new disposable preset, **ProCRUD Native Look Acceptance**, was created in the
local test workspace and assigned the owned Conflict Template through the
already-enabled official local API. The existing service was confirmed in
Settings → Network at port 50001, `/version` reported `v1`, and the installed
instance's own documentation defined the complete Look PUT body. No network
setting or Cloud connection was introduced. The PUT returned 200 on this build
(the local specification describes 204); a separate GET and SQLite/Loro view
confirmed the saved assignment.

That fresh app-authored Theme URL uses **ROOT_CURRENT_RESOURCE=12** with
`Themes/Deep Look Theme/Theme`, relative to the Workspace document. The migrated
references used ROOT_SHOW=10. The resolver permits root 12 only with that explicit
Workspace context; generic Theme resource references are not reinterpreted.
The owned API response and that single native URL value are retained as fixtures,
without unrelated Workspace settings/history or account/hardware data.

The production CLI reads the actual live local workspace and renders the owned
Look at **1440×900**. Its premultiplied sRGB output has **zero differing channels**
against rendering the independent native-export Theme at the same canvas. This
compares two file-rendering paths, not a native Audience/Syphon capture. Runtime
layers retain the existing warnings. Computer Use timed out during a separate
attempt to activate the test app, so no new physical-output or Syphon execution
claim is made and no output binding was changed.
An independent read of the selected client screen's output metadata confirmed
the original Built-in Retina Display binding remained in place.

The retained pre-existing workspace additionally has three Look template UUIDs
absent from all 21 native Theme documents. They now produce exact missing-reference
diagnostics; four other selected mappings require media rebasing. Resolving all
seven Theme *document* references does not imply that every template or runtime
dependency is available. No arbitrary substitute was chosen.
