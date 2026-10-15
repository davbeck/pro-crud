# Native 22 arrangement names and selection

Collected October 15, 2026 using ProPresenter 22 beta build **369098875** on
macOS **27.0.1**, in the authorized **ProCRUD Local Persistence Test** workspace.
Cloud setup was skipped. Only owned acceptance content is retained.

## Independent native behavior

`Fixtures/ProPresenter22/Native/Arrangements/` retains Presentation stream
`bfa7b647-93ab-5ee6-b397-ec61b08bcfee`. Its four Master cues and repeated group
arrangement come from the earlier cue-transfer/text experiments. Arrangement
`C049469C-FC98-4BAA-BAF3-290846452E5D` references group
`58FFCB48-ABA1-4C54-9FDE-12CB23439550` twice.

In the native Arrangements popup, selecting **Master** changed exactly one
field: root `selected_arrangement` changed from the arrangement UUID string to
**null**. `native-before` and `native-master` are the independent before/after
pair. Re-selecting an arrangement uses its stored UUID string, not its name.

The native arrangement manager renamed that entry to **Native Arrangement
Control** and duplicated it as **Native Arrangement Control 1**, UUID
`AD1CEC3E-CF8E-4C3D-B16A-47B07E8EF624`. Native duplication also selected the new
arrangement. `native-duplicated` retains both entries and their two repeated
group references each. This is independent evidence for the first entry's name
and a two-arrangement selection control; no production duplication operation is
qualified by this change. The native manager commits a name on completion of
text editing; changing the accessibility field's displayed value alone did not
persist it. Only committed snapshots are retained.

## Production implementation and acceptance

Version-1 `workspace apply` accepts:

```json
{
  "version": 1,
  "operations": [
    {"stream":"PRESENTATION_UUID","op":"rename-arrangement","arrangement":"ARRANGEMENT_UUID","name":"Verse"},
    {"stream":"PRESENTATION_UUID","op":"select-arrangement","arrangement":"ARRANGEMENT_UUID"},
    {"stream":"PRESENTATION_UUID","op":"select-arrangement","arrangement":null}
  ]
}
```

An omitted selection field is an error; explicit null selects Master. Names
must be nonempty, selected UUIDs must resolve uniquely within the Presentation,
and matching names/selections are no-ops. Naming modifies only the existing
arrangement map's name. Selection modifies only the root scalar and retains the
actual stored UUID spelling. All existing movable-list, arrangement-map and
unknown child-container identities survive. Repeated sequences, cues, group
placements, other arrangements and external references remain untouched.

The production batch in `edits.json` renamed the original arrangement to
**CLI Arrangement — café** and selected it. `cli-before` is byte-identical to
`native-duplicated`. The app and registered helper were stopped and pinned
harness preflight passed. Exactly one workspace stream changed, one receipt was
added, and registry bytes were unchanged. Replaying the whole batch reported
no changes/receipts and preserved all row hashes and registry bytes.

Native restart accepted `cli-after` byte-for-byte, including the stored vector
(`native-open`). The library label and arrangement popup displayed **CLI
Arrangement — café** as selected, with the native-created second arrangement
still available. Selecting **Master** in the native popup produced
`native-continued`, extending the CLI-authored history. Native **File → Export
→ Presentation** produced the unmodified `NativeReexport.pro`; its arrangement
records and optional selection agree with the continued native projection.

Tests compare Master selection with the entire independent native deep value,
check the native-manager name, one-field rename preservation, ordered batch
behavior/no-ops, invalid IDs/names and strict manifest selection. A constructed
future-policy container and lowercase UUID exercise preservation of opaque
values, every existing container ID and original UUID spelling. Production
fixtures verify repair-free reopen, history continuation and native re-export.

## SHA-256

| Snapshot | SHA-256 |
| --- | --- |
| `native-before.loro` | `73cef56fa55503193a2b956035aabff6016a883446e3039ffb479eec468b483c` |
| `native-master.loro` | `af0432c9a99134956071e00f7654f5f16f65e28af03b1ede1e32f5d6baf04b31` |
| `native-duplicated.loro` | `317dac6f442dc085b4962b5d422fea6af412c995533f18ff2a8d8888a6d49a0c` |
| `cli-after.loro` | `81343a8eed015a9ed6d82574229a1b73d45bb593563c052f0c39ae471861cd86` |
| `native-continued.loro` | `2779a728770bb0bd554c3a67a249a7448179f34e6de20353b8f62593b48b2095` |

Arrangement creation/deletion/duplication and playlist-item arrangement overrides
remain separate work. Naming and local default selection do not implement those
operations or alter playlist overrides.

Full regression suite: **401 core + 92 CLI + one harness test pass**, with
the same nine tracked rendering issues. SwiftFormat and SwiftLint pass.
