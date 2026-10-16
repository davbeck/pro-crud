# ProPresenter7-Proto

The files in `proto/` are derived from the
[ProPresenter7-Proto](https://github.com/greyshirtguy/ProPresenter7-Proto)
project. They are unofficial, reverse-engineered Protocol Buffer definitions
for ProPresenter document and configuration data.

The upstream project distributes these definitions under the MIT License. See
[`LICENSE`](LICENSE) for its copyright and license notice.

ProPresenter is a trademark of Renewed Vision, LLC. These definitions are not
created, endorsed, or supported by Renewed Vision.

The compatibility view retains its historical Swift type names and older fields.
Verified 21.4 additions are reconciled against the separately pinned exact
baseline in `../ProPresenter21Proto`: ligature style, character size mode,
original font custom metadata, optional screen rendering state, and playlist
Presentation arrangement names (field 5). The old
nested `Graphics.Text.Attributes.Font` and 21.4's top-level `Font` have identical
six-field wire layouts; the compatibility view retains the nested type when
adding `original_font=12`. TimedPlayback field 3 remains opaque here so the
singular 21.4 decoder cannot merge repeated 22 presentations. These definitions
do not imply renderer or native-edit support for every decoded feature.
