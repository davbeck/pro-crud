# Native 22 configuration roots and typed map keys

October 15, 2026, pinned ProPresenter **22 beta build 369098875**, macOS
**27.0.1**. Read-only work against the retained schema-9 corpus; no account,
network API or Cloud connection is needed. This supplies the mapped roots for
subsequent cross-document reference inspection; it does not expose deletion.

## Descriptor provenance

Added exact `communications.proto` and `testPattern.proto` records and verified
their existing dependency closure. The native descriptor set now contains
**58 files**, SHA-256
`12a01eb9618834ca51a782122088a6bf818922e596d380156b4435cf6526c8fa`.
Each new descriptor byte sequence matches its recorded ProCore offset, length
and SHA-256. The installed ProCore still matches the original pinned source
hash. All original 56 native records remain identical; no 21 descriptor or
generated Swift type changed. The Core resource is the same descriptor set.

## Scoped projections

The generic read-only projection now maps Calendar, CCLI, ClearGroups, shared
and client CommunicationDevices, Groups, KeyMappings, Labels, LibraryData,
shared/client TestPatterns, and shared/client Timers, alongside the previously
mapped roots. Client PlaylistLibrary/PlaylistMedia/PlaylistAudio have independent
PlaylistLocalDocument projections. Shared playlists retain their tree adapter;
inventory still applies matching client expansion state explicitly. Original
Loro content/history and binary fields remain the preservation source.

`workspace inventory --projections` reports all mapped roots and includes scope
per status, rather than conflating shared/client entries with the same document
ID. `protobufProjection()` exposes configuration diagnostics while `payload()`
still rejects those roots: no unsupported configuration export is implied.
The public adapter-availability property does not promise that a particular
stream is available or free of unmapped fields.

All **385** retained streams now project without issues/failures, including
**eight** independent client streams. Media traversal inspects every retained
scope with **zero uninspected streams**, still finding exactly **946** Media
occurrences. The full `(document, scope, reference, asset, schema)` multiset
continues to match the independent official WASM 1.16.2 oracle. These private
streams are not checked in, printed or uploaded; only aggregate results and
schema evidence are retained. Bare URLs, Theme/library links and other non-Media
roles still require their own dependency adapters. This is not media-store
membership or complete file-dependency validation.

## Calendar key typing

The first expanded pass mapped 384 streams and rejected Calendar recurrence
exclusions. The pinned field `Calendar.Event.recurrence_excluded_dates_v2` is
a native map keyed by Timestamp **seconds**, an `int64`, rather than a UUID or
string field. The old encoder compared the stored integer against a string.
Map-key equality now encodes both values using the declared key-field type,
retains an existing value and injects a missing field only into the transient
view. Numeric keys and values must represent exact integers and agree; tests
include negative seconds, Int64.max, preserved nanoseconds and mismatch/type
failures. Existing UUID/string keyed-map checks remain intact.

KeyMappings is an explicit remaining limitation. Its native `keymappings` map
is annotated with **TargetIdentifier**, a oneof name rather than a scalar
field. An empty map is valid and has no entries to resolve. A populated map
requires its own identity adapter and fails explicitly; no synthetic field is
injected and no unqualified key is discarded. The retained corpus contains an
empty map, so its success does not establish populated KeyMapping support.

Constructed owned Loro cases cover all thirteen newly mapped configuration
scopes, unknown-field completeness failures, unsupported client/future scopes,
read-only preservation and the configuration payload/export gate.

Final validation: **432 core + 94 CLI + one harness test pass**, with the same
nine known rendering issues. SwiftFormat, SwiftLint and descriptor resource
freshness pass. The original 21 descriptor resources are unchanged.
