# ProPresenter Format Notes

This directory documents the ProPresenter document formats used by this package. The goal is to separate three concerns:

- **Containers and library layout**: where documents live and how exports are packaged.
- **Persistent document structure**: the protobuf roots and field semantics that can be read, edited, and written.
- **Rendering behavior**: how stored presentation data maps to exported slide images.

## Documents

- `TopLevelFileFormats.md`: export archives, live workspace folders, raw protobuf file roots, and portable path semantics.
- `PlanningCenterPlaylists.md`: connected-plan workflow, nested playlist-item
  storage, the ProPresenter 21.4 Core Values observation, compatibility gaps,
  and safe editor boundaries.
- `PresentationDocuments.md`: `.pro` presentation structure, cue ordering, slide actions, text elements, media references, and minimal authoring requirements.
- `TextBuilds.md`: object Build In/Out, text Delivery modes, Build Order persistence, ProPresenter 21.4 observations, current gaps, and the proposed inspection/edit/render surface.
- `ThemeDocuments.md`: theme/template structure and ProPresenter 21.4 behavior for existing-slide application, new-slide creation, mixed text runs, element mismatches, resolution changes, and per-screen Looks.
- `RenderingBehavior.md`: observed rendering semantics for slide images, including coordinates, action layering, RTF text, scale behavior, line masks, stored element order, and video thumbnails.
- `Experiments.md`: remaining unknowns and proposed experiments for proving them.
- [`../../Fixtures/ProPresenter/README.md`](../../Fixtures/ProPresenter/README.md): the portable 480p rendering playlist, ProPresenter export workflow, and snapshot-reference installation.

## Primary Sources

- [greyshirtguy/ProPresenter7-Proto](https://github.com/greyshirtguy/ProPresenter7-Proto): reverse-engineered `.proto` definitions. The project README notes that ProPresenter 7 stores many documents and configuration files as Google Protocol Buffers.
- [cgarwood/propresenter-presentation-builder](https://github.com/cgarwood/propresenter-presentation-builder): an Electron/Vue project that decodes a template presentation, clones slide cues, and writes a new `.pro` file with `protobufjs`.
- [Renewed Vision ProPresenter support](https://support.renewedvision.com/hc/en-us/sections/360002412274-ProPresenter): official workflow documentation. These articles are useful for identifying features that need fixtures, even though they do not describe the binary formats.
- [ProPresenter OpenAPI](https://openapi.propresenter.com/): local HTTP API reference. It describes runtime control concepts that can be compared with persisted actions and configuration documents.

## Implementation Principles

- Use generated protobuf types as the binary read/write layer for known fields.
- Preserve unknown protobuf fields during lossless round-trips. Real files can contain fields newer than the schema currently checked into a project.
- Treat parsing and rendering as separate systems. Protobuf decoding is mechanical; faithful slide rendering also needs text layout, font resolution, coordinate conversion, media drawing, action composition, and layer semantics.
- Prefer library-relative URLs and archive-local assets for portable documents, while preserving absolute URL fields when doing a lossless read/write of an existing file.
- Validate behavior with ProPresenter exports whenever possible. Rendering claims should be backed by ProPresenter-generated output, not only by an independent renderer.
- Treat template resolution reports as part of the compatibility contract. The
  resolver implements the observed assignment, identity, geometry, and
  run-aware text model, while warning about unproven scalar fields, custom text
  metadata, actions, unknown-field references, and unavailable Look layers.
- A render with `--slide` resolves and validates only those selected slides.
  Template media keeps its own origin: `ROOT_CURRENT_RESOURCE` is Theme-relative,
  while `ROOT_SHOW` requires a user-workspace context such as persisted Look
  rendering. Successfully resolved assets are copied and rewritten to relative
  URLs when a template application is persisted.
