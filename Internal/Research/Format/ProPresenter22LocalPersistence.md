# ProPresenter 22 local persistence acceptance

October 15, 2026. ProPresenter 22 beta **369098875**, macOS **27.0.1**,
arm64. The local instance is explicitly authorized as a test host. Cloud support
is deferred; no account activation or Cloud workspace was used.

## Native bookkeeping oracle

A native CCLI title edit on the independently authored existing acceptance probe
changed exactly its shared Presentation row's `snapshot`, `version_vector`,
`sha256`, `byte_count` and `updated_at_ms`. It added one `patch` operation receipt;
workspace metadata, other streams, logical location, shared-version vector and
absence reason were unchanged. The receipt's payload fingerprint is exactly the
SHA-256 of the Loro update exported between the before/after version vectors:
`76a4d85b8b021606e80da9b1d138975546fc9e1734779229510ce3c7e03276a8`.
The official Swift binding reproduces that exact native update and hash and
replays it idempotently. Owned native snapshots, vectors, update and receipt are
in `Fixtures/ProPresenter22/Native/Persistence`. `schema-9.sql` contains only the
native table/index definitions, with no user content.

## Disposable local write and native acceptance

The native UI created **ProCRUD Local Persistence Test**, local workspace UUID
`9f65d640-6477-441e-9b71-70ef74bb12d7`. The independently authored 22-target
acceptance bundle imported into its Default library as shared Presentation
`bfa7b647-93ab-5ee6-b397-ec61b08bcfee`. Other default workspace content was not
copied into the repository.

After quitting ProPresenter, its verified account-owned launchd helper and
snapshot child were stopped. SIGTERM alone restarted the helper; unloading its
submitted launchd job stopped the actual writers without deleting any installed
helper. The profile pinned app version **22**, build **369098875**, signing team
**97GAAZ6CPX**, exact workspace identity/root, local registry entry and helper
SHA-256 `a23c75db8ddd828776aaa7c98abaf5d30ef25a7462bcedb1ce0009b33714a84e`.
No Syphon source was configured and no API check was selected for this metadata
experiment; those checks are recorded as not applicable, rather than fabricated
or required merely to edit document metadata.

The writer imported the existing Loro history, inserted only the CCLI title,
exported a real update and full retained history, and committed the five native
persistence columns plus a `patch` receipt in one SQLite transaction. Offline
writer generation zero is distinct from a live helper generation; native reopen
and continued editing accepted that receipt context. Original shared-version
metadata, client state, locations, other documents and workspace metadata were
preserved. A consistent before/after comparison found **exactly one changed
stream** and receipt count **7 → 8**. Registry content was byte-identical.

Opening `/Applications/ProPresenter.app` restored its helper service and the
same local workspace. Account/Cloud onboarding was skipped. The native editor
showed **CLI Local Commit Accepted** exactly. A subsequent native edit changed
it to **Native Continued Edit After CLI**, and a native Presentation re-export
retained that title and the original one-cue graph. The native continuation
extends the CLI-authored history; the automated test replays both writers'
updates and verifies their values/version vectors and native re-export.
Owned artifacts are in `Fixtures/ProPresenter22/Native/LocalCommit`.

## Writer setup and transaction coverage

On this host, stopping the helper removed WAL sidecars and a read-only open
could not initialize them. The first controlled experiment held ordinary
SQLite handles while the read-only snapshot and transaction ran. The integrated
Swift writer now owns that setup explicitly and was exercised directly through
the harness, with no auxiliary process, to write **CLI Writer Setup Accepted**.
Repeating that same value produced no receipt or history operation; the actual
workspace and registry main-file SHA-256 hashes remained identical.
Read-only inspection does not silently take this writable path or bypass SQLite
locking. The writer never migrates or repairs the store.

Focused tests cover unchanged native history/unknown values, exact native update
hashing, no-op operation preparation, consistent receipt/integrity publication,
idempotent retry, operation-ID collision, external edit conflicts, rollback of
previously staged streams/receipts on a later conflict, and rollback when the
final offline-environment check fails. The SQLite tests use the captured schema
and independently authored native data.

This acceptance is for local metadata commits. It does not qualify native
structural edits, library/path moves, media changes, Planning Center overlays,
concurrent live writers, unknown future schemas or Cloud synchronization. Those
are implementation/acceptance work, not prerequisites for this local result.
The disposable workspace is retained for further testing and review.
