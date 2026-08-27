ProPresenter is presentations software, primarily designed for use in churches. In many ways its functionality is similar to PowerPoint, Keynote and Google Slides, but it also supports many advanced features beyond those apps like a [re-usable library](https://support.renewedvision.com/hc/en-us/articles/360041344234-Building-your-Playlist-in-ProPresenter), [multiple screen outputs customized by looks and templates](https://support.renewedvision.com/hc/en-us/articles/360041407174-Using-Looks-to-Show-Different-Screen-Content-in-ProPresenter), automation control through things like [MIDI](https://support.renewedvision.com/hc/en-us/articles/1500000020301-Devices-MIDI-ProPresenter-Setup) and [remote control through local HTTP](https://openapi.propresenter.com/).

### Project and API scope

- `pro-crud` reads and writes ProPresenter document files; it does not implement or wrap the official ProPresenter HTTP API, which controls a running ProPresenter instance.
- The CLI embeds and installs two independent agent skills: `pro-crud` for document workflows and `propresenter-api` for the official API. They are included together because file preparation and live control are often used alongside each other.
- `.agents/skills/propresenter-computer-use` and `.agents/skills/release-pro-crud` are project-only contributor skills. Keep them outside `skills/` so they are not embedded or installed by the CLI.
- Keep the `propresenter-api` skill self-contained and grounded in official API documentation. It must not depend on or refer to `pro-crud` or this repository.

### Fixtures and rendering tests

One of the core ways that we validate that our logic matches ProPresenter behavior is with snapshot tests. While these types of tests are usually used as regression tests that render views, in this package the reference images are always images exported from ProPresenter.

- `Fixtures/` contains behavioral fixtures. `Fixtures/ProPresenter/README.md` defines the generated reference-bundle and export workflow. Reference PNG/JPG files are exports from ProPresenter, not arbitrary golden images.
- Do not update snapshot/reference images, loosen tolerances, or record snapshots just to make tests pass. Only update them when comparing against a fresh ProPresenter export, and document the ProPresenter version/source fixture.
- Rendering tests may depend on macOS/AppKit font behavior and locally available fonts. Investigate font differences before changing renderer logic.

### Shipped pro-crud design skill

- `skills/pro-crud` is a user-facing skill. Keep contributor workflow, generator rationale, reverse-engineering status, fixture provenance, test-scene descriptions, and release procedure in project-only `.agents/skills`, `AGENTS.md`, `Docs/`, generator sources, or tests rather than the shipped skill.
- Do not ship an example `.probundle`, background image, or background video with the design skill. The bundled `.proTheme` must remain independently authored and media-free. Do not copy CMG Theme binaries, screenshots, artwork, fonts, or handbook pages into shipped assets.
- `Sources/FixtureGenerator/DesignSystemFixture.swift` is the source of the bundled design Theme. Regenerate it with `swift run FixtureGenerator generate-design-system` and verify freshness with `swift run FixtureGenerator generate-design-system --check` after relevant changes.
- Keep four Theme documents with all 99 independently authored functional variations in these generated paths: `ProCRUD - Streaming/Theme` (24), `ProCRUD - Teaching/Theme` (24), `ProCRUD - Worship 1/Theme` for Classic Worship (24), and `ProCRUD - Worship 2/Theme` for Creative Worship (27). Test document names, ordering, counts, semantic text slots, and media absence.
- Use rectangle or other graphic-shape elements for panels, rules, frames, and decorative geometry. Do not use empty text boxes as graphics; reserve text elements for real editable content slots.
- Avenir Next is only the bundled Theme's default. Public guidance must first inspect installed fonts and existing library typography, may recommend CMG Sans when installed, and may recommend an appropriate Google Font for a specific or announcement voice.
- Public guidance should assume media already present in the user's local library is usable and that exported Themes and `.probundle` files are internal transfers. Do not add rights manifests, redistribution warnings, receipt tracking, or subscription revalidation to the shipped skill. This assumption does not permit this repository to redistribute third-party assets in the skill itself.
- Limit ProContent subscription detection to user confirmation or the documented account tier shown in ProPresenter Settings. Do not inspect credentials, session tokens, private account databases, or undocumented endpoints.

### Testing live ProPresenter output

On macOS, use [`snap-syphon`](https://github.com/davbeck/snap-syphon) to inspect the rendered output from a running ProPresenter instance. In ProPresenter, open **Screens → Configure Screens**, add a Syphon output at the intended resolution, and trigger the content under test. Discover the available source names and UUIDs before capturing:

```sh
snap-syphon list --json
```

Capture a stable frame by selecting the source name or UUID reported by `list`:

```sh
snap-syphon snapshot /tmp/propresenter-output.png \
  --source "<source name or UUID>" \
  --stable-frames 20 \
  --threshold 0.001 \
  --sample-rate 30 \
  --timeout 45
```

For transitions, animations, and other time-dependent behavior, record a short video:

```sh
snap-syphon record /tmp/propresenter-output.mov \
  --source "<source name or UUID>" \
  --duration 5 \
  --fps 30
```

Captures preserve the configured source resolution. Treat Syphon captures as diagnostic evidence; checked-in rendering references still follow the ProPresenter **Export → Slide Images** workflow documented in `Fixtures/ProPresenter/README.md`.

### Generated protobufs

- `Sources/ProPresenterProto/Generated/` is generated from `Vendor/ProPresenter7Proto/proto/`.
- Do not hand-edit generated `.pb.swift` files unless explicitly regenerating the protobuf layer.
- Preserve unknown protobuf fields when changing read/write behavior; ProPresenter files may contain fields newer than the checked-in schema.

### Domain notes

- Read `Docs/Format/README.md` and the relevant companion note before changing parser, renderer, bundle, playlist, or fixture behavior.
- `Docs/Format/Experiments.md` lists behavior that is not yet proven. Prefer adding a ProPresenter-exported fixture over guessing.

### Safety

- Before an experiment changes saved ProPresenter library data, check whether the user has explicitly identified the local instance as a development/test host or otherwise authorized library changes. If not, ask whether the local library may be changed. Until authorized, use copied/disposable documents and do not edit the library in place.

### Rules

- Before committing, make sure that swiftlint is passing and swiftformat has been run. If you suspect there are pre-existing lint warnings or formatting changes, stash your changes and create a dedicated cleanup commit before proceeding.
