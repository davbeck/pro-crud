# Versioned native acceptance

Use separate isolated macOS test accounts for pinned 21.4 and 22 beta builds,
as required by `../Plans/ProPresenter22Support.md`. A renamed app alone does
not isolate the per-user workspace helper. The available local environment has
not yet qualified that isolation; do not represent fixture CI as native-app
acceptance. No Cloud workspace is currently registered on the investigated host.

## Offline preflight harness

`swift run NativeTestHarness --profile /path/profile.json --output /path/run.json`
is a contributor-only preflight for the initial offline persistence experiments.
It is not embedded in the document CLI or its installed skills. It never
launches applications, stops processes, changes helper installations, edits a
workspace, or treats a successful preflight as a passed acceptance experiment.

Create a private profile in the isolated account. Pin the actual app path,
version/build and signing team; use the registered workspace identity and exact
root, not a display name. Obtain the API endpoint from that instance's Network
settings and the Syphon source UUID with `snap-syphon list --json` before
stopping the app/helper. A 22 profile has these fields (replace placeholders):

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

Only the rejection path has been exercised here: a deliberately mismatched
account/application emits a failure manifest, leaves sentinel workspace bytes
unchanged, and does not query its API or inspect its workspace. Passing isolated
21/22 profiles must be supplied and exercised before the preflight can qualify
an experiment environment. Shared ports/services and account isolation still
need the plan's cross-login acceptance.

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
