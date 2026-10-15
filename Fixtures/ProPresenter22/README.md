# ProPresenter 22 fixtures

`Interchange/` contains native exports from macOS ProPresenter **22 beta,
build 369098875**, on macOS **27.0.1**, collected October 14, 2026. These are
independently authored test documents, not content from the private library.

- `NativePresentation.pro`: native Presentation export of the CLI-created
  ProCRUD22Probe, an 854×480 slide with a cyan rectangle. Native import assigned
  a new root UUID while retaining nested identities. Contains native 22 metadata.
- `MetadataFreeTheme/Theme`: unmodified payload extracted from the native Themes export of the independently authored
  Deep Look Theme. Its `Deep Look Theme/Theme` payload omits application metadata. The archive
  manifest is excluded because it contains private workspace locations.
- `EmptyPlaylist.proPlaylist`: native Playlist export of an empty standard
  presentation playlist, with Include media within presentations enabled.

The document payloads are unmodified native exports. Tests must not regenerate these with
DocumentFactory. Collection details are in
`Internal/Research/Format/ProPresenter22NativeExperiments.md`. These fixtures
qualify these interchange cases only; they do not qualify native workspace
writes, Cloud, animation, or connected playlist delivery.
