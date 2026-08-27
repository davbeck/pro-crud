# pro-crud

`pro-crud` is a macOS command-line tool and Swift package for creating,
inspecting, editing, packaging, validating, and rendering ProPresenter document
files.

It works directly with documents on disk using a reverse-engineered implementation.

ProPresenter is a trademark of Renewed Vision, LLC. pro-crud is an independent, unofficial project and is not affiliated with, endorsed by, or supported by Renewed Vision.

## Features

- Inspect documents as readable text, semantic JSON, or known-schema protobuf JSON.
- Create presentations, themes, and playlists.
- Edit raw documents and exported archives without rebuilding unrelated archive
  entries.
- Apply ordered edit batches atomically.
- Expand and create portable ProPresenter archives.
- Render slides as PNG, JPEG, HEIC, PDF, or structured JSON.
- Inspect, create, edit, select, and render presentation arrangements, including
  the arrangement stored on a playlist item.
- Start audience-slide designs from a bundled four-family Theme containing 99
  grouped template variations. Avenir Next is the Theme's default, while
  projects can use other installed fonts that suit their visual language. The
  skill ships no production background images or videos; its sourcing guide
  covers existing Media Bin assets, ProContent, CMG, Unsplash stills, and
  original generation.
- Apply Theme templates to existing or newly created slides, or preview their
  Look-style result without modifying the source presentation.
- Validate document structure and rendering, with optional workspace media checks.
- Preserve protobuf fields that are unknown to the checked-in schema.
- Print the bundled format notes and protobuf schema.
- Install bundled AI-agent skills for document workflows and the official
  ProPresenter API.

### Looking for a ProPresenter MCP?

An MCP is one way to give an AI assistant tools it can use. `pro-crud` takes a
different approach: a regular command-line app does the work, while bundled
skills — small instruction guides for AI assistants — teach your assistant how to
choose and use the right tools. For saved ProPresenter files, it runs
`pro-crud`; for a running copy of ProPresenter, it can use ProPresenter's
official local API (its built-in remote-control interface).

With a supported AI assistant, you can still ask for what you want in everyday
language. This approach also has some practical advantages:

- Save the generated commands as a script — a reusable set of steps — and run the
  same workflow next week, share it with your team, or add it to existing
  automation.
- See the exact commands being run, review them before making changes, and run
  them yourself when you prefer.
- Use the CLI yourself when you do not need AI, or use the same skills with
  several supported AI assistants.
- Install one CLI and its skills without setting up a separate MCP server.

This is not an MCP endpoint, so it requires an AI assistant that supports local
skills and command execution. See
[Bundled documentation and agent skills](#bundled-documentation-and-agent-skills)
to get started.

## Supported documents

| Kind         | Raw form                               | Exported archive |
| ------------ | -------------------------------------- | ---------------- |
| Presentation | `.pro`                                 | `.probundle`     |
| Theme        | `Theme`                                | `.proTheme`      |
| Playlist     | `data`, `Library`, `Media`, or `Audio` | `.proPlaylist`   |

See [the format notes](Docs/Format/README.md) for the documented protobuf roots,
archive layouts, and path semantics.

## Requirements

- macOS 26 or newer
- A Swift 6.3 or newer toolchain with the macOS 26 SDK, such as an Xcode release
  that includes Swift 6.3

The release downloads contain a universal binary for Apple silicon and Intel
Macs. The binary and installer package are signed by ThinkUltimate LLC,
notarized by Apple, and stapled for offline Gatekeeper verification.

## Installation

1. [Download pro-crud for macOS](https://github.com/davbeck/pro-crud/releases/download/v0.1.0/pro-crud-0.1.0-macos-universal.pkg).
2. Open `pro-crud-0.1.0-macos-universal.pkg` from your Downloads folder.
3. Follow the Installer prompts.

The installer places `pro-crud` and its two SwiftPM resource bundles in
`/usr/local/bin`. It links both bundled skills into the standard configuration
locations of supported AI agents detected for the logged-in user. Existing
skills copied by an earlier pro-crud release are replaced with those links.

### Manual installation

For checksum verification or installation without the macOS package, download
the files from the
[latest GitHub release](https://github.com/davbeck/pro-crud/releases/latest):

```sh
shasum -a 256 -c pro-crud-0.1.0-macos-universal.tar.gz.sha256
tar -xzf pro-crud-0.1.0-macos-universal.tar.gz
sudo install -m 755 \
  pro-crud-0.1.0-macos-universal/pro-crud \
  /usr/local/bin/pro-crud
sudo /bin/rm -rf -- \
  /usr/local/bin/ProCRUD_ProCRUDCore.bundle \
  /usr/local/bin/ProCRUD_ProCRUDCLI.bundle \
  /usr/local/bin/ProCRUD_ProCRUDResources.bundle
sudo ditto \
  pro-crud-0.1.0-macos-universal/ProCRUD_ProCRUDCore.bundle \
  /usr/local/bin/ProCRUD_ProCRUDCore.bundle
sudo ditto \
  pro-crud-0.1.0-macos-universal/ProCRUD_ProCRUDCLI.bundle \
  /usr/local/bin/ProCRUD_ProCRUDCLI.bundle
pro-crud --version
pro-crud skill install --force
```

To build and install the current source instead:

```sh
git clone https://github.com/davbeck/pro-crud.git
cd pro-crud
swift build -c release
sudo install -m 755 \
  "$(swift build -c release --show-bin-path)/pro-crud" \
  /usr/local/bin/pro-crud
sudo /bin/rm -rf -- \
  /usr/local/bin/ProCRUD_ProCRUDCore.bundle \
  /usr/local/bin/ProCRUD_ProCRUDCLI.bundle \
  /usr/local/bin/ProCRUD_ProCRUDResources.bundle
sudo ditto \
  "$(swift build -c release --show-bin-path)/ProCRUD_ProCRUDCore.bundle" \
  /usr/local/bin/ProCRUD_ProCRUDCore.bundle
sudo ditto \
  "$(swift build -c release --show-bin-path)/ProCRUD_ProCRUDCLI.bundle" \
  /usr/local/bin/ProCRUD_ProCRUDCLI.bundle
pro-crud skill install --force
```

Keep `pro-crud`, `ProCRUD_ProCRUDCore.bundle`, and
`ProCRUD_ProCRUDCLI.bundle` in the same directory. The executable resolves its
schema from the Core bundle and its documentation and skills from the CLI
bundle. When upgrading a manual installation, remove both old bundles before
copying the new ones so resources deleted by the release do not linger. The
commands above also remove the obsolete combined bundle used by earlier builds.

## Quick start

The main commands are:

| Command             | Purpose                                                    |
| ------------------- | ---------------------------------------------------------- |
| `create`            | Create presentations, themes, and playlists                |
| `dump`              | Inspect semantic document structure or protobuf JSON       |
| `edit`              | Perform structural, text, media, and JSON edits            |
| `expand` / `bundle` | Convert between archives and extracted documents           |
| `render`            | Produce images, PDF, or effective-rendering JSON           |
| `validate`          | Check document structure, rendering, and media integrity   |
| `docs`              | Print or export the bundled format and protobuf references |
| `skill install`     | Link the bundled agent skills into supported agents        |

Inspect a document as text or semantic JSON, or print its known-schema protobuf JSON:

```sh
pro-crud dump Welcome.pro
pro-crud dump Welcome.pro --format json
pro-crud dump Welcome.pro --format protobuf-json
```

Add `--path` to inspect one component. With text or semantic JSON output this
prints the component's canonical path, protobuf type, identity, child counts,
and visible text. With `--format protobuf-json`, it prints that selected
protobuf message instead:

```sh
pro-crud dump Welcome.pro --path '/cues[index=0]'
pro-crud dump Welcome.pro \
  --path '/cues[index=0]/actions[index=0]' \
  --format protobuf-json
```

Render every slide to PNG and PDF, or render selected slides only:

```sh
pro-crud render Welcome.probundle \
  --format png,pdf \
  --output Rendered \
  --replace

pro-crud render Welcome.pro --slide 1 --slide 3 --output Selected
```

Song arrangements are included in `dump` output. Render the presentation's
stored selection, the Master/native order, or one exact arrangement UUID:

```sh
pro-crud render Song.pro --arrangement selected --output Selected-Arrangement
pro-crud render Song.pro --arrangement native --output Master
pro-crud render Song.pro \
  --arrangement '9EF1E828-DC80-425B-86A3-23389BE0F9CD' \
  --output Service-Arrangement
```

Without `--arrangement`, selection precedence is the playlist item's
arrangement, the presentation's stored selected arrangement, then Master when
neither reference is present. An explicit `--arrangement` overrides all three.
`selected` requires the presentation to have a stored selection; `native`
always requests Master.

Render a presentation through a Theme template without changing the source:

```sh
pro-crud render Welcome.pro \
  --theme Series.proTheme \
  --template 'Lower Third' \
  --size 1920x1080 \
  --format png,pdf,json \
  --template-report template-resolution.json \
  --output Rendered
```

Add one or more `--slide` values to resolve and render only those one-based
slides. `--template-report` contains the same selected set. Template actions
are excluded from transient rendering unless `--include-template-actions` is
passed; enabling it appends fresh copies after each cue's existing actions.

Or resolve the alternate template selected by a persisted Look against its
configured audience-screen canvas:

```sh
pro-crud render Welcome.pro \
  --workspace '/path/to/UserWorkspace' \
  --look 'Stream Match' \
  --screen Projector \
  --output Stream
```

This static path requires an alternate template. It cannot reconstruct masks
or other runtime-only layers, does not separate persisted presentation
background/foreground switches, and never includes template actions.

Extract an archive and create a portable bundle:

```sh
pro-crud expand Welcome.probundle --output Welcome
pro-crud bundle Welcome.pro --output Welcome.probundle
```

Create a presentation with one blank slide:

```sh
pro-crud create presentation \
  --output Welcome.pro \
  --name "Welcome" \
  --size 1920x1080
```

Edit commands address nested content with component paths. For example, write
an edited copy of a presentation without replacing the input:

```sh
pro-crud edit rename Welcome.pro \
  --path '/cues[index=0]' \
  --name 'Opening' \
  --output Welcome-edited.pro
```

The semantic dump reports cue groups in Master/native order, including each
group's canonical path, UUID, name, color, hotkey, application-group metadata,
and ordered cue references. Cue-group and cue names need not be unique, so copy
the authoritative UUID paths from `dump --format json`:

```sh
pro-crud dump Song.pro --format json

pro-crud edit add-cue-group Song.pro \
  --name 'Tag' \
  --cue '/cues[uuid="CUE-UUID"]' \
  --color '#CC293D' \
  --after '/cue_groups[uuid="PREVIOUS-GROUP-UUID"]' \
  --output Song-grouped.pro
```

`add-cue-group` requires one or more repeated `--cue` paths or `--empty`.
Selected cues are transferred out of every current group, preserving exclusive
ownership and the repeated-option order; listing the same cue twice is rejected.
The new group is appended unless `--after GROUP_PATH` is supplied. Duplicate
and empty group names are valid; UUID paths remain authoritative.

Use `move-cue-to-group` for one ownership transfer. It appends by default,
accepts `--first`, or accepts `--after CUE_PATH` for a cue already in the
destination group:

```sh
pro-crud edit move-cue-to-group Song.pro \
  --path '/cues[uuid="CUE-UUID"]' \
  --group '/cue_groups[uuid="DESTINATION-GROUP-UUID"]' \
  --first \
  --output Song-regrouped.pro
```

`set-cue-group-cues --path GROUP_PATH` replaces a group's complete ordered
reference list using repeated `--cue` values or `--empty`. Its safe defaults
reject a cue owned by another group and reject any existing cue omitted from
the replacement; duplicate cue paths are rejected. `--transfer` explicitly
takes incoming cues from their current groups;
`--leave-omitted-ungrouped` explicitly leaves omissions at the end of Master
order. The latter is also required to empty a nonempty group.

Rename a cue group with generic `edit rename`, reorder it with generic
`edit move --after GROUP_PATH`, and use
`edit set-cue-group-color --path GROUP_PATH --color '#RRGGBB'` or `--clear`
for color. Set a hotkey with:

```sh
pro-crud edit set-cue-group-hotkey Song.pro \
  --path '/cue_groups[uuid="GROUP-UUID"]' \
  --code KEY_VALUE \
  --control-identifier CONTROL_ID \
  --output Song-hotkey.pro
```

`--code VALUE` accepts case-insensitive `ansiV`, `ansi-v`, `ansi_v`, canonical
`KEY_CODE_ANSI_V`, or bare `V` spellings, as well as a raw integer such as
`22`. Numeric future enum values are preserved. Use `ansi-1` for the digit key
because bare `1` means raw enum value 1. `--control-identifier ID` is optional
and is valid only with `--code`. Exactly one of `--code` or `--clear` is
required. Clearing writes a present-but-empty `rv.data.HotKey` message rather
than removing protobuf presence. Setting or clearing either color or hotkey, or
changing a linked group's name, detaches its stored application-group UUID and
name.

`edit duplicate-cue-group --path GROUP_PATH [--name NAME]` deep-copies the
group immediately after its source, generating fresh group, cue, action, and
slide identities. Each copied cue is named `<source name> Copy`, or `Slide Copy`
when its source name is empty. Existing arrangements are not changed. Without
`--name` the source label and application-group link are preserved; a different
name detaches the copy. Generic `edit duplicate` on a cue-group path performs
the same deep copy without a name override.

Structural output is command-specific: adding reports only the `Created` group;
renaming, moving, recoloring, changing a hotkey, or replacing membership
reports the `Affected` group; moving a cue between groups reports the `Affected`
cue; duplication reports the `Affected` source and `Created` copy; removal
reports the original canonical group path as `Removed`.

Removing a group is deliberately policy-driven:

```sh
pro-crud edit remove-cue-group Song.pro \
  --path '/cue_groups[uuid="OLD-GROUP-UUID"]' \
  --move-cues-to '/cue_groups[uuid="RETAINED-GROUP-UUID"]' \
  --remove-from-arrangements
```

Choose at most one cue policy: `--delete-cues`,
`--leave-cues-ungrouped`, or `--move-cues-to GROUP_PATH`. Without one, the
group must be empty. Arrangement references are rejected unless
`--remove-from-arrangements` removes every occurrence. The final cue group
cannot be removed, and cue deletion also refuses to remove all cues or cues
referenced by retained completion targets or the timeline. Generic
`edit remove` is therefore limited to an empty, arrangement-unreferenced cue
group.

Moving a cue group changes Master/native order but does not rewrite an
arrangement's explicit UUID sequence. Changing a group's cue membership changes
every arrangement occurrence of that group. Newly added or duplicated groups
are not inserted into existing arrangements, while removing a referenced group
requires the explicit arrangement policy above.

Create an arrangement by repeating `--group` in the intended service order.
Repeating a group path is meaningful and repeats that group's cues:

```sh
pro-crud edit add-arrangement Song.pro \
  --name 'Short Service' \
  --group '/cue_groups[name="Verse 1"]' \
  --group '/cue_groups[name=Chorus]' \
  --group '/cue_groups[name="Verse 2"]' \
  --group '/cue_groups[name=Chorus]' \
  --select \
  --output Song-arranged.pro
```

If `add-arrangement` receives neither `--group` nor `--empty`, it uses every
native cue group once. Use `--empty` for an intentionally empty arrangement.
Use `edit set-arrangement-groups --path ARRANGEMENT_PATH` to replace that
sequence. Supply repeated `--group` values, or `--empty` for a valid empty
arrangement. `edit select-arrangement --path ARRANGEMENT_PATH` changes the
stored selection, and `edit clear-selected-arrangement` clears that document
fallback. A playlist item can still supply its own selection. Arrangement paths
also work with the generic `rename`, `duplicate`, `remove`, and `move` edit
commands.

Apply a template to an existing cue, first inspecting the assignment without a
write:

```sh
pro-crud edit apply-template Welcome.pro \
  --path '/cues[index=0]' \
  --theme Series.proTheme \
  --template 'Lower Third' \
  --dry-run
```

Remove `--dry-run` to persist the result. Use
`--template-actions preserve|append|replace` to make template-action handling
explicit. `preserve` is the default and copies no template actions; `append`
adds fresh copies after existing actions; `replace` removes existing non-slide
actions while retaining the cue's presentation-slide action. The selected cue
must contain exactly one presentation-slide action.

Successfully resolved Theme media is copied beside a raw destination or into
an edited archive and rewritten to a portable relative URL. Media rooted at
`ROOT_CURRENT_RESOURCE` resolves from the Theme directory. `ROOT_SHOW` requires
a user-workspace context and is supported by persisted Look rendering. A
standalone `--theme` operation has no show root, but can still use a reachable
stored absolute URL or an unambiguous Theme-local asset; otherwise it reports
the media unresolved. Review template warnings before persisting because
unresolved assets are not copied, and their Theme-origin guard is not serialized
for a later independent load. A write also fails rather than reuse one nonempty
media UUID for differing files.

Validate document structure and rendering without a workspace:

```sh
pro-crud validate Welcome.pro
```

Add strict media-reference validation when a ProPresenter workspace is
available:

```sh
pro-crud validate Welcome.pro \
  --workspace '/path/to/ProPresenter/Workspace' \
  --strict-media
```

Run `pro-crud help <subcommand>` for the complete command surface. Editing
includes structural operations, text and media replacement, slide and action
creation, protobuf JSON patches, and atomic batch application.

Component path indices are zero-based and follow a collection's effective order
when it has one rather than protobuf storage order. Presentation cue paths use
the presentation's native cue-group order; a playlist's arrangement selection
is downstream and does not change those paths. Values passed to
`render --slide` are one-based in the effective native or arranged render
sequence.

## Bundled documentation and agent skills

`ProCRUDCore` carries the protobuf descriptor used by its schema-driven editing
logic. The CLI separately carries format documentation, protobuf sources, and
metadata, and exposes all of them alongside the version that understands them:

```sh
pro-crud docs format
pro-crud docs protobuf
```

It also includes two independent agent skills in the CLI resource bundle:

- `pro-crud` for document design, creation, inspection, editing, packaging, and
  rendering, including a grouped reusable Theme with 99 template variations.
- `propresenter-api` for the official HTTP API exposed by a running ProPresenter
  instance.

Install both skills for every detected supported agent, or select agents
explicitly:

```sh
pro-crud skill install
pro-crud skill install --agent codex --agent cursor
```

## License

`pro-crud` is available under the [MIT License](LICENSE).

The vendored ProPresenter Protocol Buffer definitions retain their upstream
[MIT license and attribution](Vendor/ProPresenter7Proto/LICENSE).
