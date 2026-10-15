# Legacy registration preferences and native key-mapping authority

October 15, 2026. ProPresenter **22 beta build 369098875**, macOS **27.0.1**.
The installed authorized local test app is used without an account or Cloud
connection. These are separate storage observations, not an active-workspace
selection policy.

## Preference discovery

The macOS `com.renewedvision.propresenter.plist` preference property
`userWorkspaces` is Data containing a JSON array. Entries contain `name`, an
absolute `file:` URL, `isActive` and optional
`minimumRequiredProPresenterVersion`. The observed two entries still point at
the retained legacy UserWorkspaces directories and declare a minimum version
of 22.0.0. That version cannot establish the source storage or producing app
version, and the active flag cannot select a current native workspace.

`WorkspacePreferences.read(from:)` decodes only that property and those metadata
fields. `workspace discover --preferences PATH` reports `root`, `displayName`,
`isActiveHint` and `minimumRequiredProPresenterVersionHint`. It preserves duplicate
names/multiple active hints and unavailable/custom paths. It does not scan,
open, migrate or choose a registration. Call `workspace inspect` on an explicitly
selected root to establish storage. Native discovery remains the independent
`--registry` path. Exactly one metadata source is required.

Constructed metadata tests cover custom/percent-encoded paths, retained copies,
duplicate names, multiple active hints, unavailable local roots, absent
registrations, malformed metadata, non-file/relative/remote-host URLs and
unrelated preference fields. Source preference bytes remain unchanged. No
actual user preference file is committed.

## Key-mapping experiment: unresolved persistence authority

Native Key Mappings → Show initially displays no customized mappings. Recording
K for default **Chorus 4**, then leaving the field, displays a customization.
The UI retains K after normal app quit/restart. The schema-9 KeyMappings stream
in the selected test workspace remains exactly the empty map. The other
registered native workspace also has an empty KeyMappings map. Neither retained
legacy `Configuration/KeyMappings` file has a fresh modification timestamp.

This does not qualify a populated native map-key identity adapter. The keyboard
mapping's actual persistence source remains unresolved; do not infer it from
the descriptor's `TargetIdentifier` annotation or claim the empty stream is the
app's complete effective mapping state. Native mapping export/editing remains
unsupported. Diagnostic empty-stream captures stay in ignored investigation
output, since checking in repeated empty roots would add no behavioral fixture.

An attempted broad Reset Key Mappings was rejected by automatic approval
review because it could discard unrelated shortcuts. It was not executed or
bypassed. The experiment's K shortcut remains in the disposable test instance;
no account, network settings or credentials were inspected or changed.

Validation: **444 core + 95 CLI + one harness test pass**, with the same nine
known rendering issues. SwiftFormat and SwiftLint pass. Actual production
discovery reports both observed legacy registrations with explicit hint fields.
