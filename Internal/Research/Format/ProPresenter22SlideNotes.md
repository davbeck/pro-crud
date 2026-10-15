# Native local Slide Notes

October 15, 2026, macOS 27.0.1, ProPresenter 22 beta build 369098875. The explicitly
authorized local test workspace is ProCRUD Local Persistence Test, UUID
`9f65d640-6477-441e-9b71-70ef74bb12d7`. No Cloud account or additional host was used.

## Independent native oracle

Selected the owned ProCRUDTarget22Acceptance Presentation, stream
`bfa7b647-93ab-5ee6-b397-ec61b08bcfee`, and opened Editor → Slide Notes. Native UI
set multiline notes containing an em dash, accented text and emoji. The stored
change is solely on slide action `b6f1da61-c874-42c1-b4e9-7fe1148715b3`, under cue
`e053cc8d-2db9-4498-8dce-fd56b900f02f`:

`cues/<cue UUID>/actions/<index>/ActionTypeData/slide/Slide/presentation/notes`.

This is a Graphics.Text map with binary `rtf_data` and native attributes, distinct
from the Presentation's plain root `notes` string. Native actions use an actual
LoroMovableList. Existing maps/lists remain their original containers.

`Native/Notes/before` and `native-after` fixtures retain the actual snapshot and
vector on each side. Only the owned Presentation is included. The temporary tab
inserted while exploring editor focus was removed before the retained after
snapshot. Its decoded text is exactly:

```text
Native notes acceptance — first line
Second line: café 🎵
```

## Production writer and native acceptance

`workspace set-slide-notes` selects an exact shared Presentation stream and
slide-action UUID, requiring one matching Presentation slide action. It operates
on the retained Loro maps/list, creating a notes map only when absent. Updating
RTF changes only its binary field and preserves other notes metadata/history.
Plain text retains the first existing character's formatting. Matching text is
a semantic no-op even if an RTF serialization would differ; empty text clears.
Malformed RTF, unresolved identities and unsupported native shapes fail before
SQLite publication. The existing local registration/stopped-writer/conflict and
atomic receipt transaction are reused.

The app quit normally. The authorized test workspace launchd helper was stopped
with bootout; all actual UI/helper writers were verified stopped. The pinned
native harness preflight passed with the existing local profile. A preliminary
CLI edit succeeded before the hash baseline was available; the hash script was
corrected to use normal read-only SQLite outside the filesystem sandbox. A
second final acceptance edit changed exactly one shared stream, retained all
other stream row hashes and registry bytes, and added exactly one receipt.
Repeating that final text returned `changed: false`, no receipts, and identical
stream/registry/receipt-count results.

Reopening `/Applications/ProPresenter.app` restored its workspace helper. The
native Slide Notes editor displayed the CLI multiline text exactly, including
café and emoji. Native continued editing set another multiline value. Its native
history extends the CLI version vector, and native File → Export → Presentation
produced the unmodified retained `NativeReexport.pro` with that continued value.
No slide/Look was triggered and existing output configuration was unchanged.

Retained snapshot SHA-256:

- before: `d96d0a3bf0048608d9b9a47c56fed8810e9ca24191d17c436b0d090dbc6f0074`
- native-after: `13466c72ead9abd4b1d4a8673a93aeb135807a377b042c55bbbf7d906bc75bce`
- cli-after: `fd13bca396e85165350f441ddb793febc5602233dbdd7149df5cb7505ea13c49`
- native-reexport: `cee1dd56984028a1663af599ab32991c233322bf744fa79f7a50a7e4bd88c0cd`
- native-continued: `dd6102a038689a1775f7fa00b6a539c590782b45f94d6b8894c938593f23f0f2`

Tests cover independent native field placement, multiline Unicode, exact RTF
replacement, absent/existing notes containers, history update replay, unrelated
content, no-ops, clearing, malformed data, unresolved actions, CLI argument
exclusivity, native restart/continuation and the native re-export. The disposable
Presentation and acceptance notes remain available for review.
