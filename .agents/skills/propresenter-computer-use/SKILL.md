---
name: propresenter-computer-use
description: Operate and inspect the local macOS ProPresenter app through Computer Use, including library and playlist navigation, menus and dialogs, slide triggering, screen configuration, and live Audience or Stage output validation with snap-syphon. Use for ProPresenter UI experiments, reproducing app behavior, importing or exporting test content, changing development-library state with permission, or visually verifying what a running instance renders when the file CLI or HTTP API cannot perform the UI workflow.
---

# ProPresenter Computer Use

Control the local ProPresenter UI with `node_repl` and `@oai/sky`, then validate rendered output independently with `snap-syphon`. Prefer `pro-crud` for document-file operations and `propresenter-api` for official HTTP API work; use this skill when the app UI itself is part of the task.

## Establish permission and scope

1. Read the request and repository instructions for the host classification.
2. If the user explicitly identifies the instance as a development/test host or authorizes local-library changes, make only the scoped changes needed for the experiment. Record temporary configuration created during the test and remove only that temporary state afterward.
3. If permission to change saved library data is absent, ask whether the local ProPresenter library may be changed before importing, editing, renaming, deleting, or changing saved configuration. Continue with read-only inspection while waiting when useful.
4. Without permission, use copied/disposable documents and do not change the library in place. Treat audience/stage triggers, clears, active looks, capture, and timers as live-control actions; perform them only when the user's request authorizes control of this instance.
5. Never treat an apparently old, empty, or test-looking library as permission. Authorization comes from the user or project context, not visible content.

## Start and inspect ProPresenter

Follow the Computer Use skill and use `node_repl` for every UI action. Do not use AppleScript, `osascript`, System Events, or synthetic input.

```js
globalThis.sky = (await import("@oai/sky")).sky;
var ppState = await sky.get_app_state({ app: "ProPresenter" });
nodeRepl.write(ppState.text);
```

- Target `ProPresenter` first. If that fails, retry with bundle identifier `com.renewedvision.propresenter` after resolving it with `list_apps()`.
- `get_app_state` launches ProPresenter when it is not running. If the activation sheet appears and the task does not require an account, click the fresh `Skip for Now` element.
- Call `get_app_state` after every action. Derive new `element_index` values from the fresh tree; menu, dialog, and window changes renumber them.
- Use the default accessibility diff when it contains enough context. Request `{ disableDiff: true }` before locating an element not present in the diff.
- Prefer accessible rows, buttons, menus, text fields, and exposed secondary actions. Use screenshots only where the accessibility tree omits essential visual state.
- If Computer Use reports that the Mac is locked and cannot unlock it, ask the user to unlock it; do not work around the lock.

## Navigate the workspace reliably

- Select a library or playlist row, refresh state, then select the presentation row returned for that collection. A selected presentation is loaded in the workspace but is not necessarily live.
- Do not click an already-selected presentation row again when preparing a command: ProPresenter may enter inline name editing. Before using **Edit → Delete** or another row-scoped command, verify the state reports `Selected: <row>` rather than `Selected text`. Select a different row and then the target once if necessary.
- Expect slide thumbnails, media thumbnails, and canvas content to be absent from the accessibility tree. The slide container normally appears as `ContiguousScrollView`; inspect a screenshot when choosing visual content.
- Avoid unanchored coordinate clicks across multi-display or full-screen layouts. They can fail with `windowNotFoundAtPosition`. Refresh the state and prefer an accessible element, a coordinate anchored to the relevant container, or keyboard navigation.
- Before sending `Right` or `Left` to advance slides, ensure the intended presentation is selected and the slide area is focused. Refresh afterward and verify the rendered result; never infer a trigger solely from selection or focus.
- Use accessible menu items for deterministic controls. For example, clear test output through **Presentation → Clear Groups → Clear All**, resolving each item from a fresh tree rather than caching indices.
- Use `set_value` for editable fields. Use `type_text` only after verifying focus; returns in typed text may submit dialogs.

For a visual target omitted from accessibility:

```js
ppState = await sky.get_app_state({ app: "ProPresenter", disableDiff: true });
var fs = await import("node:fs/promises");
var { fileURLToPath } = await import("node:url");
if (ppState.screenshot) {
  await nodeRepl.emitImage({
    bytes: await fs.readFile(fileURLToPath(ppState.screenshot.url)),
    mimeType: "image/png",
  });
}
```

## Import disposable test content

Use the native import flow when testing ProPresenter's importer rather than merely opening a bundle in Finder.

1. Obtain permission before the import because it adds saved library data.
2. Open **File → Import → File…**.
3. In the Open panel, press `super+shift+g`, refresh state, set the `PathTextField` to the absolute `.probundle`, `.proPlaylist`, `.proTheme`, or supported document path, and press Return.
4. Refresh state, verify the intended filename is selected, then click `Import` with ID `OKButton`.
5. In **Import Presentation**, choose the exact destination Library and optional Playlist, refresh, and click `OK`.
6. Verify the imported presentation appears in the intended destination. Opening the bundle in Finder and pressing Return is not a substitute for this flow.

If ProPresenter reports an existing name, inspect the presented choices. `Write Over` replaces saved library content; use it only when the user has authorized that exact replacement. Prefer a unique test name where cached rendering of a previous same-named import would make the result ambiguous.

When cleaning up an imported test presentation, select the presentation row—not its editable text field—then use **Edit → Delete**. Follow the Computer Use confirmation policy at the irreversible confirmation dialog.

## Export slide-image references

Use ProPresenter's native slide-image export when producing or checking repository reference images:

1. Select the presentation and open **File → Export → Slide Images…**.
2. Inspect the format controls. Choose JPEG when the slide background color must be included or PNG when it must be omitted; set **Include Media Actions** as required by the fixture workflow.
3. Press `super+shift+g`, refresh, set `PathTextField` to the absolute destination directory, and press Return.
4. Refresh, set `saveAsNameTextField` to the export folder name, verify the controls again, and click `Save` with ID `OKButton`.
5. Verify the numbered images on disk, including count, format, dimensions, and representative pixels/content.

The exported slide images use the presentation canvas resolution, which can differ from a configured Syphon output resolution.

## Configure a Syphon test output

Use Syphon when the rendered Audience or Stage frame is the evidence under test.

1. Open **Screens → Configure Screens…** through fresh accessible menu elements.
2. Inspect existing Audience and Stage outputs before changing anything. Reuse a suitable Syphon output when possible.
3. When the authorized test requires a new output, click the appropriate Audience or Stage `add` button, choose **New Syphon**, and choose the intended resolution. ProPresenter assigns a screen name and publishes a source such as `Syphon - 2`.
4. Keep the Audience or Stage switch enabled for the source being tested.
5. After the test, delete only an output created for that test by invoking the row's exposed `Delete` secondary action. Verify that pre-existing outputs remain.

The source name displayed in Screen Configuration is the name `snap-syphon` discovers. Do not assume its number or UUID.

## Inspect live output with snap-syphon

Run `snap-syphon` outside the filesystem sandbox when necessary. A sandboxed `list` may return an empty array even while ProPresenter is publishing a source.

Discover sources first:

```sh
snap-syphon list --json
```

Resolve the exact ProPresenter source. Prefer its UUID when names are duplicated or may change. Capture a stable diagnostic frame:

```sh
snap-syphon snapshot /tmp/propresenter-output.png \
  --source "<source name or UUID from list>" \
  --stable-frames 20 \
  --threshold 0.001 \
  --sample-rate 30 \
  --timeout 45
```

- Use a new temporary path. Add `--force` only to intentionally replace an earlier disposable capture.
- Open the captured image and inspect it visually. Confirm expected text, media, layers, crop, alpha, and resolution; a successful command alone proves only that a frame was captured.
- Captures retain the configured source resolution. Check dimensions when resolution matters.
- If stable-frame capture times out on animated content, record it instead of weakening the stability check.

Record transitions, video, timers, or other time-dependent behavior:

```sh
snap-syphon record /tmp/propresenter-output.mov \
  --source "<source name or UUID from list>" \
  --duration 2 \
  --fps 30
```

Inspect the recording or verify its stream metadata before drawing conclusions. Syphon captures are diagnostic evidence, not checked-in reference exports. For repository rendering references, follow `../../../Fixtures/ProPresenter/README.md` and ProPresenter's **Export → Slide Images** workflow.

## Experiment loop

1. Record the selected presentation, relevant live state, and existing screen outputs.
2. Capture a baseline frame when visual output is involved.
3. Perform one UI change at a time and refresh the accessibility state.
4. Capture or record the resulting output and inspect it.
5. Compare observed UI and rendered behavior with the expected outcome. Do not treat unchanged output as success merely because the click or key call returned successfully.
6. Restore live-control state when appropriate and remove only temporary screens or content created by the test.
7. Report the exact ProPresenter behavior, source resolution, and any library/configuration changes left behind.

## Troubleshooting

- **No sources:** Confirm ProPresenter is running, the relevant output group is enabled, and a Syphon output exists in Screen Configuration. Rerun `list --json` outside the sandbox before concluding no source exists.
- **Wrong source:** Re-run discovery and select by UUID. Never rely on a remembered index after outputs are added or removed.
- **Unchanged capture:** Selection is not a trigger. Focus the intended slide area, perform the authorized trigger, and compare a fresh capture.
- **Coordinate click fails:** Stop guessing display coordinates. Refresh the full tree, raise the ProPresenter window if needed, and use an accessible control, container-anchored click, or keyboard command.
- **Window briefly disappears:** Large imports or presentation loads can leave the process and Syphon output alive while Computer Use reports no window. Check `list_apps`, wait for the load to settle, and retry state inspection before diagnosing a crash.
- **Delete edits a name instead:** Undo the text edit, select a different presentation, then select the target row once. Confirm row selection in fresh accessibility state before reopening **Edit → Delete**.
- **Stale imported rendering:** Same-named bundle imports can replace a presentation while leaving cached visuals. On an authorized development library, prefer a unique test name; otherwise restart ProPresenter or use a copied workflow before diagnosing the document renderer.
