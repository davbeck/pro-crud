# Native local MediaStore models

October 15, 2026, ProPresenter **22 beta build 369098875**, macOS **27.0.1**.
The authorized disposable local workspace was closed and its helper stopped.
All 20 MediaStore files were copied to an ignored research directory and hashed;
no live store file was opened for writing. This is read-only investigation,
not a production RocksDB backend or a media mutation qualification.

## Verified frozen storage

The store marker is `__rv_media_store_schema`, with JSON
`{"application_id":"com.renewedvision.media-store","version":1}`.
This version is separate from workspace SQLite schema 9 and each document's
media identity-schema string `"1"`.

The current manifest selects SST files 143, 146 and 151, with log number 148
and persisted last sequence 40201. All three current tables use uncompressed
block format 5 with XXH3 checksums. An independent diagnostic reader verifies
all **174** table blocks, handles prefix/delta index encoding and internal
sequence/type keys, and reads **1,015** SST records. The only current WAL is
152: **1,519** complete batches and **1,784** operations, all with verified
masked CRC32C checksums and batch counts. Replaying sequence order over current
tables yields **343** current JSON model records.

The parser follows the pinned RocksDB 8.10.0 implementations of
[table checksums/footer](https://github.com/facebook/rocksdb/blob/v8.10.0/table/format.cc)
and [manifest records](https://github.com/facebook/rocksdb/blob/v8.10.0/db/version_edit.cc),
plus the official [WAL](https://github.com/facebook/rocksdb/wiki/Write-Ahead-Log-File-Format)
and [index format](https://github.com/facebook/rocksdb/wiki/Index-Block-Format)
references. The one-off checksum helper uses the official xxHash 0.8.2 header;
none of this diagnostic tooling adds a shipped dependency.

Current model families are Asset (19), Reference (90), Transformation,
Snapshot, ImportOperation and Settings, plus the schema marker. Native Reference
JSON has its own UUID, asset and transformation associations, projection-owned
and tombstoned flags and timestamps. Asset JSON has a managed path, opaque
32-byte checksum, file metadata, availability/purge state and optional provider
metadata. Transformation JSON holds geometry/effects/alpha interpretation;
Snapshot JSON tracks generated thumbnail output. The stored checksum algorithm
has not been qualified and is not treated as the CLI's SHA-256 file digest.

## Actual occurrence associations

The current document inventory has **78** file-media occurrences and four HLS
occurrences. Every file occurrence has a matching Reference model. Only **77**
have an Asset model under the asset UUID declared in their document. The
remaining Theme occurrence has a different materialized association:

| Field | UUID |
| --- | --- |
| Theme stream, Black/Theme | 97f094d1-79a8-541c-a49a-f3643222948c |
| Occurrence | b3f57269-e05d-5ea7-9ac5-5cbbe0a95628 |
| Document-declared asset | c9d1f3fa-0a66-59ea-8e21-2a8dc07cc848 |
| Reference-model asset | e9d88797-3cdd-5d73-9d15-e403549de005 |

That Reference is projection-owned and not tombstoned. Its associated Asset
points to the existing owned `Media/Assets/EventPhoto.jpg` and is Ready. The
document's exact file also exists, so existing read-only file availability
correctly succeeds while explicitly leaving asset-store membership unverified.
Neither the document-declared ID nor file existence alone proves the current
materialized association. No corrective write or missing-asset diagnosis is
justified by this mismatch without understanding native deduplication rules.

The two owned SharedRectangle occurrences retain distinct Reference models,
one shared Asset `322e4d08-cba2-4b08-bd43-842ae317f6df`, and separate Transformation
UUIDs. Both original occurrence IDs and source geometry agree with the earlier
native document fixture. All four HLS sources have no Asset model under their
document asset UUID; they remain runtime dependencies rather than missing files.

`Fixtures/ProPresenter22/Native/MediaStoreModels` retains twelve selected native
JSON model values, the three corresponding read-only document occurrence
reports and provenance hashes for all copied source files. This is selected
semantic evidence, not a complete or portable MediaStore image. No sticker
artwork, thumbnail or other media resource is included.

## Remaining implementation and acceptance

Production inspection now offers explicit `workspace media --asset-store`.
The reader captures the active manifest, tables and WAL without opening RocksDB
or creating any files, checks file identity/size/nanosecond timestamps before,
after and across the capture, and retries a changed source at most three times.
It verifies XXH3 and masked CRC32C checksums, record counts, sequence precedence
and point tombstones. Unknown column families, required manifest extensions,
table metadata/layout/compression, asset/reference namespaces, bad UUIDs and
future schema markers fail explicitly. Budgets are 64 MiB per file, 512 MiB
total, 16 MiB per logical log record, one million records and 30 seconds.

Asset and Reference models are typed; all raw values remain available internally
and other model-family counts remain explicitly uninspected. The report joins
file occurrences by Reference UUID, keeping declared/materialized asset IDs,
native availability and stored paths separate from file-availability results.
Runtime HLS sources are excluded from missing-file/asset membership comparisons.
Independent document and MediaStore captures are not presented as a cross-store
transaction. Native checksums remain opaque.

The unmodified active manifest/three tables/WAL are retained in
`Fixtures/ProPresenter22/Native/MediaStoreSnapshot`, with original byte hashes.
Ten core tests cover the independent 343-model/19-asset/90-reference oracle,
all twelve earlier selected JSON values, the actual Theme association difference,
table/WAL/manifest corruption, future format/path traversal, missing/symlinked
tables, tombstone precedence, concurrent append retry and bounded instability,
byte/record budgets, fragmented logs and incomplete/unknown write batches.
A CLI test exercises `--asset-store` with a native document database and proves
both stores' source bytes/directory entries stay unchanged. The native corpus
caught and corrected an index-versus-file bounds error in the initial reader.

The command also succeeds against the running test instance after native media
controls: 358 models, 19 assets, 95 Reference records, 232 verified table blocks
and 81 file occurrences. Eighty associations match and the same single Theme
difference remains explicit. All 85 occurrences are retained, including four
HLS runtime sources. xxHash 0.8.2 is vendored unchanged behind a small C bridge
for its checksum algorithm; its BSD notice is included in release and installer
packaging. The Rust/RocksDB database engine is not linked.

With native writers stopped, the production command inspects those same 81
associations with local hashing enabled while preserving all **40** document,
media-store, managed-asset and registry files and their directory entries.
The full suite passes **470 core, 98 CLI and one harness** tests with the same
nine known rendering issues. SwiftFormat, SwiftLint, schema-resource freshness
and release-script syntax checks pass. The CLI test checks the actual report
route and encoded membership field, keeps raw unrelated models out of JSON,
and verifies that omitting the flag retains the previous unverified behavior.
The final CLI acceptance script also passes with refreshed embedded user docs
and skill guidance.

Without the flag, asset-store membership remains unverified. MediaStore writes
remain unsupported. Native-controlled replacement/deletion/reopen experiments must
establish which records are canonical, derived or recreated before writes,
relocation or cross-store transactions can be implemented safely. No fresh
ProPresenter 21 host or Cloud connection is required for this local work.
