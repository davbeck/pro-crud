# ProPresenter Format Reference

This directory documents the ProPresenter document formats used by this package. It covers three areas:

- **Containers and library layout**: where documents live and how exports are packaged.
- **Persistent document structure**: the protobuf roots and field semantics that can be read, edited, and written.
- **Rendering behavior**: how stored presentation data maps to exported slide images.

## Documents

- [Top-level file formats](TopLevelFileFormats.md): export archives, workspace
  folders, protobuf roots, and portable paths.
- [Planning Center playlists](PlanningCenterPlaylists.md): connected plans,
  nested local links, visibility, supported edits, and service boundaries.
- [Presentation documents](PresentationDocuments.md): cues, arrangements,
  actions, elements, media references, and authoring requirements.
- [Text builds and Delivery](TextBuilds.md): product terminology, persisted
  build references, and inspection, editing, and rendering limits.
- [Theme documents](ThemeDocuments.md): template structure, application to
  existing and new slides, text styles, resolution, and per-screen Looks.
- [Rendering behavior](RenderingBehavior.md): coordinates, layering, text,
  scale behavior, line masks, video previews, and render commands.

## Scope And Compatibility

This is the public reference for `pro-crud` document workflows. It distinguishes
stored schema, ProPresenter behavior, and the tool's own editing and rendering
policies. Version-specific behavior is qualified on the relevant page; an
unspecified behavior is not a compatibility guarantee. Decoding a field does
not imply support for editing its semantics or reproducing its live output.

`pro-crud` reads and writes files. The official HTTP API controls a running
ProPresenter instance and is a separate interface.

## Primary Sources

- [greyshirtguy/ProPresenter7-Proto](https://github.com/greyshirtguy/ProPresenter7-Proto): reverse-engineered `.proto` definitions. The project README notes that ProPresenter 7 stores many documents and configuration files as Google Protocol Buffers.
- [cgarwood/propresenter-presentation-builder](https://github.com/cgarwood/propresenter-presentation-builder): an Electron/Vue project that decodes a template presentation, clones slide cues, and writes a new `.pro` file with `protobufjs`.
- [Renewed Vision ProPresenter support](https://support.renewedvision.com/hc/en-us/sections/360002412274-ProPresenter): official workflow documentation. These articles describe product workflows rather than binary formats.
- [ProPresenter OpenAPI](https://openapi.propresenter.com/): local HTTP API reference. It describes runtime control concepts that can be compared with persisted actions and configuration documents.

## Compatibility Rules

- Use generated protobuf types as the binary read/write layer for known fields.
- Preserve unknown protobuf fields during lossless round-trips. Real files can contain fields newer than the schema currently checked into a project.
- Treat parsing and rendering as separate systems. Protobuf decoding is mechanical; faithful slide rendering also needs text layout, font resolution, coordinate conversion, media drawing, action composition, and layer semantics.
- Prefer library-relative URLs and archive-local assets for portable documents, while preserving absolute URL fields when doing a lossless read/write of an existing file.
- Treat template resolution reports as part of the compatibility contract. The
  resolver implements the documented assignment, identity, geometry, and
  run-aware text model, while warning about unsupported scalar scaling, custom text
  metadata, actions, unknown-field references, and unavailable Look layers.
- A render with `--slide` resolves and validates only those selected slides.
  Template media keeps its own origin: `ROOT_CURRENT_RESOURCE` is Theme-relative,
  while `ROOT_SHOW` requires a user-workspace context such as persisted Look
  rendering. Successfully resolved assets are copied and rewritten to relative
  URLs when a template application is persisted.
