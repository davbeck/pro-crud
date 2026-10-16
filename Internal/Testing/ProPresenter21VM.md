# ProPresenter 21.4 Tart environment

Provisioned October 15, 2026. The dedicated VM `pro-crud-21-4` boots and accepts
key-only SSH. ProPresenter 21.4 is installed and has launched inside it. First-run
configuration is complete and its empty Default library was observed in the UI.
The VM is stopped to release host memory. A powered-off baseline named
`pro-crud-21-4-baseline` is preserved. Native rendering and bundle round-trip
acceptance remain separate follow-up tests. Host ProPresenter 22
and its workspaces were not changed.

## Pinned environment

- Tart 2.40.1, installed through `openai/tools`, with Softnet 0.24.0.
- Image: `ghcr.io/cirruslabs/macos-tahoe-base@sha256:4aaa751fa7538902d73c767f27a066fc87e83f183069da4e4b5022863abd4c77`.
- Verified guest: macOS 26.6.2, build 25G83, arm64.
- Four virtual CPUs, 4096 MiB RAM, fixed 1440×900 display, 50 GB virtual disk.
- Store: `/Users/davbeck/.tart/vms/pro-crud-21-4`. Image and clone share APFS
  blocks; their displayed sizes must not be added to estimate physical usage.
- ProPresenter `/Applications/ProPresenter.app` **inside the guest**: 21.4,
  build 352583705, Team ID `97GAAZ6CPX`, bundle ID `com.renewedvision.propresenter`.
- Installer: [official Renewed Vision ZIP](https://renewedvision.com/downloads/propresenter/mac/ProPresenter_21.4_352583705.zip).
  SHA-256 `a428409c5a59c0e1f0ced0d8788d521c75672fadd50ec15e20992a1fffbd4b9d`,
  independently matched after transfer into the guest. Deep/strict code-signature
  verification passed on host and guest. Host Gatekeeper accepted the notarized
  app. After enabling Gatekeeper in the base image, guest `spctl --assess`
  reported `rejected`, `source=Notarized Developer ID`, with a log reason of no
  matching active rule. Native Finder launch nevertheless succeeded. This guest
  policy discrepancy remains unresolved; no Gatekeeper exception was added.

## Start, connect, and stop

Run from the repository root:

```sh
tart run --no-clipboard \
  --dir=installer:"$PWD/.build/propresenter21-vm/installer":ro \
  --dir=evidence:"$PWD/.build/propresenter21-vm/evidence" \
  pro-crud-21-4
```

Guest shares appear under `/Volumes/My Shared Files`. Only the installer and
ignored evidence folder are shared, not the host library or repository. Use SCP
for application bundles: copying a framework-bearing app through the VirtioFS
share produced symlink errors. Transferring the ZIP and extracting on the guest
disk with `ditto -x -k` preserved signatures. The failed partial app is in the
guest admin user's Trash.

```sh
tart ip pro-crud-21-4
ssh -F /Users/davbeck/.ssh/pro-crud-21-4/config pro-crud-21-4
scp -F /Users/davbeck/.ssh/pro-crud-21-4/config ./fixture.pro pro-crud-21-4:~/Downloads/
tart stop pro-crud-21-4 --timeout 30
```

The current DHCP IP is `192.168.64.2`. If it changes, update only `HostName` in
that private SSH config after checking `tart ip`. The dedicated key and pinned
known-hosts file are in `/Users/davbeck/.ssh/pro-crud-21-4/`; they are not tracked.
The base image's public `admin` login remains for the guest console. SSH password
and keyboard-interactive authentication are disabled in
`/etc/ssh/sshd_config.d/000-pro-crud-key-only.conf`. The temporary bootstrap
password helper has been removed. Do not sign this disposable image into personal
accounts or treat its console login as a secret.

## Isolation and performance

All ProPresenter preferences, helpers, and the fresh workspace live on the guest
disk. The initial workspace root is
`/Users/admin/Library/Application Support/RenewedVision/ProPresenter/UserWorkspaces/ProPresenter`.
No host workspace was imported. Gatekeeper is enabled; Spotlight indexing was
disabled inside the guest after observing heavy indexing CPU usage during setup.
Microphone and local-network discovery permission requests were declined.

The host has only 8 GiB RAM. First boot stalled and required a restart; subsequent
boot established SSH. Desktop input and first-run startup were slow. Avoid running
other memory-heavy VMs during experiments. Docker was observed running a separate
4 GiB VM during initial setup and was left untouched.

Host Computer Use can observe the Tart window and operate the guest visually,
although input delivery was unreliable and actions sometimes needed repeating;
but the guest's accessibility tree is not exposed through that window. SSH gives
file/process access; a guest-side automation runtime and its permissions are a
separate capability. Syphon sources do not automatically cross the VM boundary.
Do not claim native image export, Syphon capture, HTTP API control, or GPU fidelity
until each has been tested inside this VM.

## Remaining acceptance

1. Version/build were verified from the installed bundle and the process path,
   while the main workspace was observed in the UI. The About dialog was not
   successfully opened through Tart. `SUEnableAutomaticChecks` and
   `SUAutomaticallyUpdate` are explicitly false, verified after stopping the app.
   Pinning is also enforced by checking the bundle version before each test.
2. Import a disposable repository fixture, reopen it, export a bundle and native
   slide images, and compare identifiers/media and visual results. Keep VM evidence
   separate from checked-in ProPresenter references until provenance is recorded.
3. Enable and verify the HTTP API only when needed; prefer an SSH local forward
   for host access. Verify Syphon within the guest independently.
4. Baseline `pro-crud-21-4-baseline` was created after shutdown. Create a disposable
   experiment VM with `TART_NO_AUTO_PRUNE=1 tart clone pro-crud-21-4-baseline
   pro-crud-21-4-experiment`. Keep the baseline stopped. Clones receive distinct
   identities; avoid concurrent boots on this 8 GiB host. Guest SSH host keys and
   authorized keys are inherited, so document the clone IP explicitly.

Local setup metadata is in `.build/propresenter21-vm/setup-manifest.json`.
[Tart documentation](https://tart.run/quick-start/) describes SSH, directory shares,
and VM cloning.

## AppleScript over SSH experiment

On October 15, a disposable clone `pro-crud-21-4-automation` (DHCP IP initially
`192.168.64.3`) successfully ran System Events UI scripts over the existing
key-only SSH connection. The SSH user was the logged-in console user `admin`.
No new permissions, guest desktop-app install, or LaunchAgent were required
for the tested image. The baseline and original VM were unchanged.

The experiment dismissed the real activation sheet, opened/read/closed About,
and repeated launch → activation dismissal → native version verification. About
visually confirmed 21.4 (352583705), resolving the earlier About-dialog inspection
limitation. Checked-in helper scripts, SSH commands, selector constraints, and
validation details are in [Scripts/ProPresenterUI](../../Scripts/ProPresenterUI/README.md).
The experiment VM is retained but stopped to release memory. File interchange
and rendering acceptance remain untested by this experiment.
