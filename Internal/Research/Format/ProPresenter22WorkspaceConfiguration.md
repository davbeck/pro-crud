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
this is not a writable or complete interchange Workspace projection. Native
Look rendering, physical-output execution and configuration mutation remain
separate qualification work.
