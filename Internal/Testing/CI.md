# Continuous integration

`.github/workflows/tests.yml` runs lint and tests once for each
pull-request update and each push to `main`. Feature-branch pushes are covered
by their pull request; `workflow_dispatch` supports manual checks. A newer run
cancels the previous run for the same pull request or branch.

`.github/workflows/swiftformat.yml` retains automatic formatting on branch pushes
that change Swift files or formatting configuration. It runs `bin/format` and
commits any Swift changes. Formatting runs only on pushes, not again on PR events.
Both formatting and lint use the package's resolved tool versions.

Commits made with `GITHUB_TOKEN` do not trigger push or pull-request workflows,
so the formatter explicitly dispatches CI after creating a formatting commit.
This requires `actions: write` in addition to `contents: write` for that workflow.
The dispatched run checks the updated branch and shares a concurrency group with
the PR run, cancelling obsolete checks. No personal access token is required.
Run `bin/format` locally to apply formatting or `bin/format --lint` to check it.

Tests use the `xcode-27` Apple silicon runner with Xcode 27.0. Its macOS 27.0.1
environment matches the independent native 22 text-placement exports documented
in [the rendering investigation](../Research/Format/RenderingIssues/README.md).
The former macOS 26 runner failed both exact occupied-pixel comparisons in
`NativeTextEditingTests.unscaledTextMatchesNative22InkPlacement` across PRs #3
and #4, as well as the merged `main` commits. Reference images and comparison
precision are unchanged. GitHub currently labels this runner as a public preview;
see its [image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md).
The workflow reports OS and toolchain versions to help diagnose future image
updates. The workflow preserves the existing
`SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1` setting. An unrestricted
hosted run built successfully but stalled after starting the core tests, despite
passing locally; concurrency changes need a separate investigation.

To run the same checks locally on macOS 27.0.1 with Xcode 27.0:

```sh
cp .env.example .env # Only when .env does not already exist.
bin/format --lint
bin/lint
swift test
```

The application's minimum supported OS remains macOS 26. This workflow pins the
rendering reference environment; it does not provide a minimum-OS test matrix.
