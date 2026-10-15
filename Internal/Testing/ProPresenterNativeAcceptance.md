# Versioned native acceptance

The existing native-exported 21 corpus, documentation and regression tests are
the baseline for preserving 21 behavior. They remain usable without installing
or launching another app version. Extend that coverage for changed adapters;
use fresh native acceptance where a changed conversion or behavior needs an
additional oracle. Record fixture tests and new native experiments separately.

When actually switching between pinned 21.4 and 22 applications, use isolated
macOS test accounts as described in `../Plans/ProPresenter22Support.md`. A renamed
app alone does not isolate the per-user workspace helper. Cross-version helper
isolation is not a prerequisite for local 22 implementation or fixture tests.
The installed 22 instance is an authorized test host. Use disposable local
workspaces and stop actual workspace writers for direct persistence experiments.
Cloud acceptance is independent of these local experiments.

## Offline preflight harness

`swift run NativeTestHarness --profile /path/profile.json --output /path/run.json`
is a contributor-only preflight for the initial offline persistence experiments.
It is not embedded in the document CLI or its installed skills. Preflight alone never launches applications, stops processes, changes helper
installations, edits document rows, or substitutes for native acceptance. The
explicit metadata experiment described below is a separate write action.

Create a private profile in the isolated account. Pin the actual app path,
version/build and signing team; use the registered workspace identity and exact
root, not a display name. When API/output checks are relevant, obtain the API endpoint from that
instance's Network settings and the Syphon source UUID with `snap-syphon list
--json` before stopping the app/helper. Omit `apiBaseURL` when no endpoint check
is selected; omit both Syphon fields when no Syphon output is configured. The
manifest records these checks as not applicable. Metadata-only experiments do
not require configuring an API server or screen output. A 22 profile has these fields (replace placeholders):

```json
{
  "accountName": "propresenter22-test",
  "applicationPath": "/Applications/ProPresenter 22.app",
  "applicationVersion": "22.0",
  "applicationBuild": "369098875",
  "teamIdentifier": "VERIFIED_SIGNING_TEAM",
  "workspaceRoot": "/Users/propresenter22-test/Library/Application Support/RenewedVision/ProPresenter/Workspaces/WORKSPACE_UUID",
  "workspaceID": "WORKSPACE_UUID",
  "storage": "native-loro-sqlite",
  "registryPath": "/Users/propresenter22-test/Library/Application Support/RenewedVision/ProPresenter/Workspaces/registry-v1.sqlite3",
  "helperRoot": "/Users/propresenter22-test/Library/Application Support/RenewedVision/ProPresenter/Helpers/Workspaces",
  "helperExecutable": "/Users/propresenter22-test/Library/Application Support/RenewedVision/ProPresenter/Helpers/Workspaces/PATH_TO_QUALIFIED_EXECUTABLE",
  "helperSHA256": "SHA256_OF_QUALIFIED_HELPER_EXECUTABLE",
  "apiBaseURL": "http://127.0.0.1:PORT_FROM_NETWORK_SETTINGS",
  "snapSyphonExecutable": "/absolute/path/to/snap-syphon",
  "syphonSourceUUID": "SOURCE_UUID"
}
```

For 21.4 use its exact pinned build and account/app paths,
`"storage": "legacy-protobuf"`, and omit `workspaceID` and `registryPath`
when the legacy workspace has neither. Do not infer originating version from
that folder layout. Disable automatic updates in both test accounts during
qualification without changing signed app bundles.

The harness verifies the account, app signature/team/version/build, account-local
helper installation, executable ownership and pinned helper SHA-256, and absence of ProPresenter/helper writers
in all test sessions. After those checks pass it verifies the API endpoint and
configured Syphon source are stopped, then inspects the explicitly selected
workspace and checks native registration/identity/local status. Mismatches write
a failure manifest without inspecting workspace storage. Invalid/unreadable
profiles remain command errors. Never automate helper deletion as a retry.

The rejection path leaves sentinel workspace bytes unchanged and never queries
an API or inspects the workspace after account/application mismatches. A passing
local 22 profile has now been exercised in the authorized account against the
new disposable **ProCRUD Local Persistence Test** workspace, with exact app
build/signature and helper hash, every native writer stopped, and a local registry
entry. No new macOS account or Cloud connection was needed. This does not qualify
cross-version helper isolation.

## Local metadata experiment

After the pinned process/account/build checks, this contributor-only command
applies targeted Loro operations and commits the new snapshot/vector/integrity
columns with an operation receipt in one SQLite transaction:

```sh
swift run NativeTestHarness --profile /private/local-test-profile.json \
  --output /private/local-test-run.json \
  --document-id DISPOSABLE_PRESENTATION_UUID \
  --set-copyright-title 'Local persistence acceptance'
```

Use only an explicitly disposable local Presentation. No production CLI native
edit command is exposed by this experiment. The writer checks local registration
and stopped writers again before commit, rejects changed source revisions, and
preserves client streams, logical location, shared-version bookkeeping and all
unrelated fields/history. Retries recognize their existing operation receipt;
a matching value creates no patch or receipt. Cloud roots are rejected.

Explicit writer setup may initialize SQLite's normal WAL sidecars while holding
ordinary SQLite handles. This is necessary for the observed closed-WAL case on
this host; it does not bypass SQLite locks or run a migration/repair. Ordinary
inspection retains its read-only opening policy. Preflight-only runs may need a
readable SQLite backup when the stopped source cannot be opened read-only.
No helper installation is deleted or replaced. The tested launchd-managed helper
restarted after SIGTERM; a controlled `launchctl bootout` stopped the submitted
job, and opening the pinned app restored the service automatically.

See `../Research/Format/ProPresenter22LocalPersistence.md` for the actual native
restart, continued edit, re-export, exact affected-row comparison and fixtures.
This evidence qualifies the tested metadata operation. Structure, membership,
media and other native edit families remain separate implementation work.

## Native experiment record

Associate the preflight manifest with the copied source workspace, input bundle,
before/after inventories and hashes, native re-export, and any Slide Images or
Syphon captures. Record the executable build, macOS/fonts, helper ownership and
whether the app/helper was stopped. Initial direct persistence experiments must
use disposable local workspaces with every writer stopped. They must prove
operation receipts, CRDT history/version vectors, generation/notifications,
multi-stream rollback and subsequent native editing before exposing writes.

For receiving-app acceptance, launch only the registered absolute app path in
the correct account. Verify the actual selected native workspace in the UI.
Import the corresponding CLI-generated artifact; reopen, edit, trigger/capture
where needed, restart, and export again. Compare identities/order/dependencies
and native output against the version-specific fixture set. Check the sibling
workspace hashes after alternating-version runs. A successful file decode or
offline preflight cannot substitute for these checks.

Store 22 reference images separately from 21.4 references, with pinned app/OS,
fonts and export settings. Follow `../../Fixtures/ProPresenter/README.md`;
Syphon frames remain diagnostics, not replacements for native Slide Images.
Cloud/offline/reconnect/concurrent-delete acceptance needs a separately
authorized disposable Cloud workspace and remains unqualified here.
