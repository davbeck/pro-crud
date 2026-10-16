# Native media-action lifecycle and removal

October 15, 2026, ProPresenter **22 beta build 369098875**, macOS **27.0.1**.
All controls use the authorized local test instance and owned content. No Cloud
service, extra app version or Intel host is required.

## Native controls

An owned copy of the earlier NativeMediaIdentity bundle imported as Presentation
`58884c2c-1eb4-50f8-99ac-c88b29cb0f34`, Default/ProCRUD File Replacement Probe.
It has two slide cues with background-media actions sharing the registered
SharedRectangle asset. The name records the experiment's initial intent; the
native result establishes addition rather than replacement.

**Add Media Action → From Finder** on the first cue, selecting the existing
managed LogoTransparent.png, appends action
`4F239108-7355-4DDD-A83F-C965313FC1DC`. It retains both old actions and all
other root fields. The new action is type 2/media with the native audio subtype,
image element, occurrence `BBBFB028-5753-43D8-A264-9392E194692A`, asset
`FE240A1B-DE9A-5518-976E-4C72A07A65A4`, and selected SourceInfo file URL
ROOT_SHOW/Media/Assets/LogoTransparent.png. FileProperties has an empty locator.
Its natural image size is 540×471. This control does not qualify a media writer.

Removing that exact action through **Remove Actions → LogoTransparent.png**
changes only the first cue's action list. A second native control removes the
second cue's type-13/background-media action
`DDE126BA-14B9-4AAB-B6B9-9BEB04FAD1E3`, also retaining its slide cue. The SDK
operation reproduces each independent native deep value exactly while retaining
the original history and replaying its actual Loro update.

## Helper lifecycle

The newly created Reference initially has projectionOwned=false. After native
restart it becomes true, so that initial value is not a permanent ownership
classification. Immediate native action removal changes no MediaStore bytes:
the reference remains present and not tombstoned. On restart it becomes
tombstoned while the native document snapshot/vector remain byte-identical.

This demonstrates the tested helper's deferred rematerialization for these
document-backed references. It does not justify writing arbitrary MediaStore
models or treating every model as disposable. Selected typed records are in
ReferenceLifecycle.json; their source values come from the independently
checksum-verified production reader. Other assets and reference consumers are
retained, including the shared registered PNG.

## Production batch acceptance

The actual `workspace apply` batch removes the remaining first cue's background
action `F2421D65-4D95-4434-8DFE-1520C8B3B09D` and sets the CCLI title to
**Native Media Removal CLI**. A later invalid cue move rejects the whole batch,
with all stream rows, receipt count and registry unchanged. The valid batch
changes exactly one Presentation and adds one receipt. All **25** managed-asset
and MediaStore files remain byte-identical; registry bytes are unchanged. Full
manifest replay is a no-op, including the already absent action.

Native reopening accepts the exact CLI snapshot and vector. Its helper marks
the removed occurrence `03faed06-5361-5b33-a317-731f3d4e3c81` tombstoned; the
second native control's occurrence is likewise tombstoned. The shared asset is
still present and not purged. A continued native **Group → Chorus 4** edit
creates the second group without restoring media. An independent Presentation
export retains the title, both cues and no media action.

Owned snapshots/vectors, production manifest, lifecycle values and native
re-export are in `Fixtures/ProPresenter22/Native/MediaActionCreation`, with
individual file hashes and exact build provenance. Neither PNG artwork nor
generated rendering references are added by this experiment.

## Qualified policy

`remove-media-action` resolves one exact media action UUID in a cue containing
a presentation-slide action. It deletes that existing Loro movable-list item,
preserving all other nodes and fields. An absent UUID is deliberately a no-op
for batch replay. Non-media actions, ambiguous UUIDs, incomplete native
projections and active after-action completion selectors targeting the action
fail before publication. No cue is deleted and no file/MediaStore write is made.
Media-only cue deletion, new media actions, replacement, arbitrary asset-store
mutation and file relocation remain separate acceptance work.

The full suite passes **475 core, 99 CLI and one harness** tests with the same
nine known rendering issues. SwiftFormat, SwiftLint and embedded schema
freshness pass. Existing 21 references and tolerances are unchanged.
