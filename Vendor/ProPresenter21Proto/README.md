# ProPresenter 21.4 schema baseline

`proto/` is the unmodified `autogen-proto/` directory from
[ProPresenter7-Proto revision 6931e91501c2245de77aa8b9974f9f78532d805c](https://github.com/greyshirtguy/ProPresenter7-Proto/tree/6931e91501c2245de77aa8b9974f9f78532d805c/autogen-proto),
whose commit identifies ProPresenter 21.4, build 352583705. `provenance.json`
records each source hash. These unofficial reverse-engineered definitions are
MIT licensed; see `LICENSE`.

`Scripts/sync-protobuf-assets.sh` builds the separate `Protobuf21/schema.pb`
resource from these 146 files. This baseline distinguishes fields already in
21.4 from changes first captured in 22. It is independent of the older retained
`Vendor/ProPresenter7Proto` model and the captured `ProPresenter22Proto` schema.

Do not replace the retained generated decoder with these definitions without
versioned adapters. In particular, 21.4 `TimedPlayback.Sequence.presentation=3`
is singular while 22 `presentations=3` is repeated. The older generated model
leaves this field opaque and preserves every occurrence. The KeyMapping common
UUID/name fields are wire compatible: field 2 is a string in both schemas.
21.4's recursive `CollectionElementType.parent_collection=3` is absent from the
22 `KeyMapping.CollectionElementTypeKey` layout; preserving its bytes does not
qualify its scope semantics in 22.
