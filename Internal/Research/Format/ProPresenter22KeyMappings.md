# Native menu key-mapping projections

October 15, 2026. ProPresenter **22 beta build 369098875**, macOS **27.0.1**.
Authorized local test instance; no account, Cloud connection or additional host.

## Independent native evidence

The Key Mappings UI contains separate Show and Menu areas. Editing **Show →
Group → Chorus 4** to K changes `Group.hotKey.code` to **11, ANSI K**, in the
Groups stream. The KeyMappings stream remains empty. A UI shortcut alone is
therefore not evidence of a populated KeyMappings map.

Editing **Menu → ProPresenter → About ProPresenter** to Control-Shift-Command-K
does populate the KeyMappings stream. Its map key is a JSON object with exact
`category` and `name` members:

```json
{"category":"KEYMAPPING_PREFERENCES_SECTION_HEADER_MENU_SUFFIX_title","name":"MAIN_MENU_APPLICATION_ABOUT_PROPRESENTER_title"}
```

The entry retains `TargetIdentifier` tagged `menu_item`, with that same command
identifier; keyboard equivalent `k`; modifier flags **[3, 1, 0]** (Control,
Shift, Command); and a zero-valued MIDI message. Normal app restart shows the
same shortcut and retains snapshot/vector bytes exactly. The owned native
before/after/reopened streams and per-file provenance are checked in under
`Fixtures/ProPresenter22/Native/KeyMappings`. The official WASM projection agrees
with this exact key, oneof and stored values.

## Qualified read-only adapter

The map annotation `TargetIdentifier` names a oneof, not a scalar field. The
adapter validates the observed menu identity, requires its name to agree with
the actual stored `menu_item`, and passes the entry unchanged to the pinned
protobuf encoder. It never synthesizes a TargetIdentifier from a map key.
Source history, containers, ordering within keyboard flags and unknown entry
fields remain intact. The normal completeness gate still reports unknown fields.

Other category strings and target branches remain unsupported. Malformed keys,
extra identity members, mismatched targets and two distinct serialized keys for
the same logical menu command fail. This does not qualify configuration editing,
export, MIDI hardware operation or non-menu mapping identities. Existing
21/22 scoped-key conversion gates and generated protobuf types are unchanged.

Native inventory help and capability diagnostics now identify these remaining
gates instead of claiming that every native read/write operation is unavailable.
The legacy file-access error directs callers to the qualified native commands
or a separate native export while retaining the storage boundary.

A failing injected-field test exposed an existing completeness gap: unknown
entry fields were reported, but unknown members inside a oneof wrapper were
removed from the transient view without an issue. The encoder now enumerates
unknown wrapper members before selecting the active branch. Known inactive
branches retain the existing oneof semantics. The test verifies both entry and
wrapper paths; source values/history remain unchanged.

Validation: **447 core + 95 CLI + one harness test pass**, with the same nine
known rendering issues. SwiftFormat, SwiftLint and schema resource freshness
pass. Fresh production inventory projects all **385 retained** and **62 local**
streams with zero issues/failures. The retained two-reference oracle is unchanged.
