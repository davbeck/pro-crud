# Native reader qualification

October 14, 2026, macOS 27.0.1, ProPresenter 22 beta build 369098875.

The implementation uses the official `loro-dev/loro-swift` **1.13.3** release,
revision pinned in Package.resolved, with the upstream XCFramework checksum.
The macOS static library contains arm64 and x86_64 slices. SQLite is the system
library; no database engine or writable native backend is bundled.

A consistent backup of the investigated native workspace, including the
independently authored disposable probe, contains **385** streams. The Swift
reader verified every envelope's ID, scope, location, availability, snapshot
length and SHA-256. Every Loro import completed without pending dependencies,
and its decoded version vector agreed with the SQLite vector. The deep-value
projection of **all 385 streams** matched the independently captured official
`loro-crdt` **1.16.4** JS/WASM projection exactly, including binary RTF and tree
metadata. Binary data was normalized to byte arrays for that comparison only.
The original snapshot bytes remain the preservation source.

The current live registry contains two locally available roots and no Cloud
workspace. Read-only registry discovery queried only the `workspaces` metadata
table. The current live workspace inventory contains **384 streams** (376
shared, eight client); the disposable probe was deleted after the earlier
export experiment. No migration patches were applied and no live database or
media files were written.

Automated tests use the independently authored native probe snapshot and its
original version vector in disposable schema-9 SQLite envelopes. They cover
committed WAL visibility, exclusion of an open uncommitted transaction,
unchanged source main/WAL bytes, corrupt envelopes, schemas 8/10/99, unavailable
content, shared/client identity separation, and mismatched version vectors.

The interface is diagnostic. It does not materialize native streams into
editable protobuf documents, render native slides, resolve the native media
registry, or write CRDT operations. Those capabilities retain the plan's
independent acceptance gates. The reader does not qualify Cloud merges or
newer storage schemas. SQLite snapshots are bounded to 512 MiB in memory;
unknown schema/storage versions fail without migration or repair.
