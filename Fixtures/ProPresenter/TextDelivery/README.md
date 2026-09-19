# Native By Bullet graphs

These protobuf-JSON `rv.data.Slide` extracts were saved by ProPresenter 21.4
(352583705) on macOS on September 6, 2026. They are behavioral fixtures, not
rendering reference images. The source was a disposable native duplicate of
`Sermon 2026-09-06`, slide 9. Only the native base slide was extracted; media
actions and the rest of the presentation are excluded.

- `zero.json`: Build From `1: Title`; parent Build In then children 0–2.
- `one.json`: Build From `2: Physically`; children 0–2, parent not scheduled.
- `two.json`: Build From `3: Culturally`; all children 0–2 remain defined,
  but only children 1–2 are scheduled.
- `boundaries.json`: native text replaced with
  `Heading\nFirst\n\nSecond\u2028soft\nLast\n`, then Delivery toggled from
  All At Once back to By Bullet. Four units, three children, initial count 2.
  Blank paragraphs and the trailing newline do not add units; U+2028 stays
  within the `Second` paragraph.

To refresh, reproduce these settings in the native editor, save, dump with
`--format protobuf-json`, and extract the affected `baseSlide` without
rewriting its fields. Do not regenerate these references from TextDelivery.
