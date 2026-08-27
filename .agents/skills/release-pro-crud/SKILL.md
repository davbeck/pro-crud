---
name: release-pro-crud
description: Prepare and publish signed pro-crud releases end to end. Use when Codex needs to choose or apply a patch or minor version bump, derive user-focused release notes from git history, update release and version references, validate and build notarized macOS artifacts, create and push a release tag, or create and verify a GitHub release for this repository.
---

# Release pro-crud

Release from `main` with the repository's existing `bin/build-release` pipeline. Treat the release as complete only after the version commit and tag are on GitHub, the GitHub release is public with all four artifacts, and the versioned installer link in `README.md` resolves.

## Apply release guardrails

- Read the repository-root `AGENTS.md` before changing files or running release commands.
- Keep the release procedure in this project-only skill. Do not add it to the shipped `skills/pro-crud` skill.
- Run every `gh` command outside the filesystem sandbox, as required by `AGENTS.md`.
- Start from a clean `main` worktree synchronized with `origin/main`. Do not mix unrelated changes into the release preparation commit.
- Never move or overwrite a tag that has been pushed, and never overwrite an already-published release. Correct a published mistake with a new patch release.
- Do not update rendering references, record snapshots, loosen tolerances, or hand-edit generated protobuf Swift files to make release validation pass.
- Confirm the proposed version and release-note body before committing, tagging, or publishing unless the user's request already unambiguously authorizes that exact version or release kind and immediate publication.

## 1. Establish the release range

Fetch `main` and tags, then verify the local starting point before editing:

```sh
git fetch origin main --tags
git status --short --branch
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git describe --tags --abbrev=0 --match 'v[0-9]*'
```

Require all of the following:

- The branch is `main`.
- `HEAD` equals `origin/main` before release preparation.
- The tracked worktree is clean.
- The latest reachable version tag agrees with the current version in `Sources/ProCRUDCore/Version.swift`.
- The tag is backed by an existing stable GitHub release.
- At least one meaningful change exists after that tag.

Inspect the existing releases with `gh release list` and `gh release view`. Abort if the intended new tag or GitHub release already exists.

Set the latest stable tag as the comparison base and inspect both history and the actual diff. Do not derive notes from commit subjects alone:

```sh
git log --reverse --no-merges --date=short \
  --format='%h %ad %s%n%b' <previous-tag>..HEAD
git diff --stat <previous-tag>..HEAD
git diff --name-status <previous-tag>..HEAD
git diff <previous-tag>..HEAD -- \
  README.md Package.swift Packaging Sources/ProCRUDCLI Sources/ProCRUDCore \
  skills Docs
```

Inspect other changed paths whenever they can affect users, installation, packaging, compatibility, bundled assets, or requirements.

## 2. Choose patch or minor

Read the current version as `0.MINOR.PATCH` from `Sources/ProCRUDCore/Version.swift`, then apply the highest-impact category present in the release range:

- Choose a patch release, `0.Y.Z` to `0.Y.(Z+1)`, for backward-compatible bug or security fixes, documentation, maintenance, performance work, and packaging corrections that add no user-facing capability and require no migration.
- Choose a minor release, `0.Y.Z` to `0.(Y+1).0`, for any new user-facing command, option, output, bundled capability, or substantial workflow, and for any breaking change.
- Keep the major component at `0` while this project is pre-1.0. A breaking `0.9.4` release becomes `0.10.0`, never `1.0.0`.

Audit breaking changes explicitly across:

- CLI commands, options, output, defaults, exit behavior, and JSON schemas
- Public `ProCRUDCore` APIs and exhaustive public enums
- ProPresenter document, bundle, archive, and media acceptance or output behavior
- Minimum macOS, Swift, Xcode, dependency, or build requirements
- Installer paths, signing expectations, and automatic installed-skill behavior

Treat a break as minor even when the same range also contains only patch-level work elsewhere.

## 3. Draft user-focused release notes

Synthesize the notes from the comparison range and its diff. Describe what a user can now do, what became more reliable or secure, and what they must change. Omit release mechanics, test-only work, contributor tooling, and internal refactors unless they materially affect users.

Use this shape, omitting empty optional sections:

```markdown
<One short paragraph summarizing the release's user value.>

## Highlights

- <New or substantially improved user outcome.>

## Improvements and fixes

- <Compatible behavior, reliability, security, or packaging improvement.>

## Breaking changes

- **<Affected surface>:** <What changed, who is affected, and the migration action.>

**Full changelog:** https://github.com/davbeck/pro-crud/compare/<previous-tag>...<new-tag>
```

Include `## Breaking changes` whenever any incompatibility exists; place it prominently and make every item actionable. State when a break affects only source-package users and not users of the prebuilt CLI. Do not claim behavior that the diff, tests, or documentation do not support, and do not paste commit subjects as release notes.

Write the approved body to a temporary file outside the repository for `gh release create`. Do not commit a transient release-notes file.

## 4. Bump every current-release surface

Update the canonical version in `Sources/ProCRUDCore/Version.swift`.

Update the current download and manual-install examples in `README.md`:

- the direct `/releases/download/v<version>/pro-crud-<version>-macos-universal.pkg` URL
- the installer filename in the following installation step
- the manual `.tar.gz.sha256` checksum filename
- the manual `.tar.gz` archive filename
- the extracted archive directory passed to `install`

Keep the generic `/releases/latest` link unchanged. Preserve historical statements such as “Releases starting with v0.1.1” and “Starting with v0.1.2”; those versions describe signing milestones, not the current release.

Search every tracked source for the old version and version-shaped release links before and after editing so newly added release surfaces are not missed:

```sh
git grep -n -F '<old-version>'
git grep -n -F 'v<old-version>'
rg -n 'releases/(download|latest)|pro-crud-[0-9]+\.[0-9]+\.[0-9]+' \
  README.md Sources Packaging bin skills .agents
```

Classify every match rather than blindly replacing it. Normally do not edit these derived surfaces:

- `bin/build-release` reads the canonical Swift version and derives the tag, artifact names, and package versions.
- `Packaging/Distribution.xml` and `Packaging/Scripts/postinstall` contain no app-version literal.
- CLI version reporting and its test both reference `proCRUDVersion`.
- `Package.swift` has no package marketing-version field.

Review those files only when the release diff changes their actual behavior or metadata.

## 5. Validate and prepare the release commit

Run the complete release validation from the repository root:

```sh
bin/format
git diff --check
swift test
Scripts/cli-acceptance.sh
swift run FixtureGenerator generate-design-system --check
swift run FixtureGenerator generate-malformed-bundle --check
Scripts/check-protobuf-drift.sh
bin/lint
```

Investigate failures. Regenerate deterministic assets only from their documented generator sources when they are genuinely stale. Never regenerate ProPresenter-exported snapshot references merely to pass tests.

After formatting and validation, review the full diff and repeat the version/link search. Commit only the intended release-preparation changes with a message such as `Prepare v<version> release`. Require a clean tracked worktree after the commit.

## 6. Tag and build before pushing

Preserve the repository's lightweight-tag convention:

```sh
git tag v<version>
```

Confirm that `v<version>^{commit}` equals `HEAD`, then build the signed and notarized universal archive and installer:

```sh
CODESIGN_IDENTITY='Developer ID Application: ThinkUltimate LLC (7TR2B85D62)' \
INSTALLER_IDENTITY='Developer ID Installer: ThinkUltimate LLC (7TR2B85D62)' \
NOTARYTOOL_PROFILE='pro-crud-notary' \
  bin/build-release
```

Require the ThinkUltimate LLC Developer ID Application and Developer ID Installer certificates and the `pro-crud-notary` Keychain profile. If the profile is missing, ask the user to provision it once with an app-specific password; never request or handle that password:

```sh
xcrun notarytool store-credentials pro-crud-notary \
  --apple-id '<apple-id>' \
  --team-id 7TR2B85D62
```

Let `bin/build-release` enforce the clean tagged `HEAD`, universal architectures, hardened runtime, secure timestamps, code and installer identities, binary version, package contents, two accepted notarizations without issues, stapling, and Gatekeeper assessment.

Require these exact ignored artifacts in `dist/`:

```text
pro-crud-<version>-macos-universal.pkg
pro-crud-<version>-macos-universal.pkg.sha256
pro-crud-<version>-macos-universal.tar.gz
pro-crud-<version>-macos-universal.tar.gz.sha256
```

Verify both checksum files from inside `dist/` and confirm there are exactly four target-version artifacts. If the build fails before the tag is pushed, fix the cause and remove/recreate only that unpushed local tag as needed. First verify that the tag is absent from the remote. Never move a pushed tag.

```sh
(
  cd dist
  shasum -a 256 -c pro-crud-<version>-macos-universal.pkg.sha256
  shasum -a 256 -c pro-crud-<version>-macos-universal.tar.gz.sha256
)
```

## 7. Push and publish on GitHub

Immediately before publication, verify again that:

- local `main` contains only the intended release-preparation commit beyond `origin/main`
- the local release tag points at `HEAD`
- the remote tag and GitHub release do not exist
- the temporary notes contain the approved body
- all four artifacts and checksums pass verification

Use `git ls-remote --tags origin refs/tags/v<version>` to check the remote tag and `gh release view v<version> --repo davbeck/pro-crud` to check the release. Treat no matching output or a not-found response as the expected pre-publication state; abort on any match.

Push `main` and its tag atomically:

```sh
git push --atomic origin main v<version>
```

Create a draft GitHub release with the exact four explicit artifact paths; do not use a broad glob:

```sh
gh release create v<version> \
  dist/pro-crud-<version>-macos-universal.pkg \
  dist/pro-crud-<version>-macos-universal.pkg.sha256 \
  dist/pro-crud-<version>-macos-universal.tar.gz \
  dist/pro-crud-<version>-macos-universal.tar.gz.sha256 \
  --repo davbeck/pro-crud \
  --verify-tag \
  --fail-on-no-commits \
  --title 'pro-crud <version>' \
  --notes-file <temporary-notes-path> \
  --draft
```

Inspect the draft with `gh release view`. Verify the tag, title, complete notes, non-prerelease status, and four uniquely named assets. Repair only the draft if needed, then publish it and mark it latest:

```sh
gh release edit v<version> \
  --repo davbeck/pro-crud \
  --verify-tag \
  --draft=false \
  --latest
```

Verify the public release with `gh release view`, including its URL and all asset names. Confirm that the direct installer URL now present in `README.md` resolves to the published `.pkg`. Report the release URL, version and tag, validation results, artifact names and checksums, and every breaking change called out in the published notes.
