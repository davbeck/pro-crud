# ProPresenter guest UI helpers

Small contributor-only AppleScripts for an explicitly authorized test instance.
Run these **inside the guest**, through SSH, as the user logged into its graphical
session. Do not run them on the host when intending to control the VM. English
ProPresenter **21.4 (352583705)** on macOS 26.6.2 is the tested configuration.
These helpers are not embedded in the CLI or installed agent skills.

| Script | Result |
| --- | --- |
| `launch.applescript` | Opens the pinned `/Applications/ProPresenter.app`; waits up to 60 seconds for an accessible window and menu bar; returns `window-ready`. This does not mean startup sheets are dismissed. |
| `dismiss-login.applescript [wait-seconds]` | Clicks **Skip for Now** on the verified activation sheet. Returns `dismissed` only after the sheet disappears; `not-present` if no sheet appears within the optional wait (default 0, maximum 60 seconds). |
| `about.applescript [close]` | Opens About and returns the version text, or closes only the verified About window and reports its version. |
| `inspect-front.applescript` | Returns the accessibility hierarchy of the front ProPresenter window. Read-only; the main-window result may be large. |

## SSH usage

Start the disposable VM `pro-crud-21-4-automation` with Tart, then run from the
repository root. This local shell function passes the script intact through
standard input; it avoids nested AppleScript/shell quoting:

```sh
vm_ip="$(tart ip pro-crud-21-4-automation)"
guest_osascript() {
  ssh -F /Users/davbeck/.ssh/pro-crud-21-4/config \
    -o "HostName=$vm_ip" -o HostKeyAlias=192.168.64.2 \
    -o BatchMode=yes pro-crud-21-4 /usr/bin/osascript - "$@"
}

guest_osascript < Scripts/ProPresenterUI/launch.applescript
guest_osascript 30 < Scripts/ProPresenterUI/dismiss-login.applescript
guest_osascript < Scripts/ProPresenterUI/about.applescript
guest_osascript close < Scripts/ProPresenterUI/about.applescript
guest_osascript < Scripts/ProPresenterUI/inspect-front.applescript
```

The `HostKeyAlias` intentionally verifies the existing pinned key inherited from
the baseline. It does not disable verification. A separately installed guest
needs its own independently verified host key/configuration. The private SSH key
and config are machine-local and are not part of this repository.

## Selectors and limits

The activation sheet's four buttons have no AX titles in this build. A fresh
screenshot and AX positions established their order: Help, Sign Up, Sign In,
**Skip for Now**. The helper uses button 4 only after checking the installed build,
exact English activation heading/body, and button count. It fails on unexpected
sheets instead of clicking a generic OK/default button. A changed version or
localization requires a fresh native inspection before extending this selector.
The About window has no useful window title; it is identified across the app’s
windows through its Acknowledgments checkbox and version static text. Repeated
open calls read the existing About window rather than opening it again.

The scripts poll observable UI conditions and propagate permission/AX failures.
They do not accept EULAs, enter credentials, change account activation, grant
permissions, or suppress arbitrary dialogs. `not-present` describes only the
front-window sheet; it is not a general readiness assertion. Launch/dismissal
must run sequentially. The optional wait handles delayed activation prompts.

Direct `osascript` over SSH worked in the tested base-image-derived guest without
new permission approvals or a LaunchAgent. This does not establish that fresh
macOS installations need no permissions. If macOS denies Automation or assistive
access, grant the responsible process the required permissions inside the guest
through normal System Settings UI, then retry. Do not edit TCC databases. If the
SSH user is not the graphical-session owner, or that desktop is locked/logged
out, resolve that session condition before attempting UI automation.

The native Quit command presents a confirmation even in this empty test library.
A direct `tell application ... to quit` can time out while that confirmation is
waiting; inspect it and handle it explicitly rather than treating the timeout as
process exit. No generic auto-confirm helper is provided.

## Native validation

On October 15, 2026, in `pro-crud-21-4-automation`, cloned from the stopped baseline:

- Read process/menu/window AX state over key-only SSH as console user `admin`.
- Inspected the actual activation sheet and visually matched the unlabeled Skip
  button, clicked it through System Events, and verified sheet disappearance.
- Opened About through its named menu item; visually confirmed and read
  `Version 21.4 (352583705)` through AX; closed it with its AX close button.
- Verified repeated login-helper execution returns `not-present` without clicking.
- Quit through native UI and confirmed process exit; relaunched with the helper,
  dismissed the new activation prompt with the checked-in helper, and read the
  same version again. No guest-side Codex installation or LaunchAgent was needed.
- Rebooted the VM and repeated launch/dismissal. Verified the corrected About
  helper reads the existing dialog twice and closes it, then verified login
  dismissal remains a no-op. The first front-window-only About implementation
  had failed a cleanup call; it was replaced with control-based window lookup.
- Compiled the checked-in scripts with `osacompile`; behavior was validated
  against the native guest app, not mocked accessibility fixtures.

This validates these UI helpers, not presentation import/export, rendering,
ProPresenter 22 selectors, or a full compatibility test suite. Keep those acceptance
checks separate. Diagnostic screenshots are not rendering reference images.
