# Font-table charset acceptance

Native oracle: ProPresenter 22 build 369098875 at `/Applications/ProPresenter.app`,
macOS 27.0.1 (26A434), 2026-11-08. The active disposable local workspace was
**ProCRUD Local Persistence Test**. Both uniquely named input decks were imported
using File → Import → File, then exported using File → Export → Slide Images,
PNG (without slide background color), Include Media Actions enabled. All PNGs
are unmodified 1920×1080 ProPresenter exports, not CLI renders. `CMGSans/Native.pro`
is the separate File → Export → Presentation re-export; its cue storage order
is normalized and differs from display order.

Each `Input.pro` is a media-free CLI-authored four-slide presentation:

1. Installed family Regular/Bold, explicit `\fcharset0`, family metadata.
2. Same RTF with only both `\fcharset0` controls removed; identical font metadata.
3. Charset-free RTF passed through `set-text`: the CMG Sans deck records the
   pre-fix Helvetica compatibility metadata; the Montserrat deck records
   Montserrat-Regular metadata.
4. Explicit Helvetica/Helvetica-Bold control.

The original generation used fresh CLI invocations for each edit. Slide 2 is
the controlled RTF-only pair and does not depend on slide 3's metadata control.

Within **each** family, native images 1, 2 and 3 have exactly identical decoded
RGBA bytes. Image 4 differs. ProPresenter therefore renders the requested family
without requiring the charset control, independently of this metadata control.

Before the discovery fix, rendering only slide 2 in a fresh CLI process resolved
CMG Sans to Helvetica; rendering slide 1 first registered the family and masked
the problem. After the fix, fresh slide-2 CLI processes resolve the two physical
Regular/Bold faces for both families. Every non-black glyph pixel matches the
native reference footprint. There remain RGB antialiasing differences at 22 CMG
Sans pixels and 33 Montserrat pixels (maximum channel delta 23); alpha is exact.
These are not treated as an exact full-color rendering match, and references or
existing tolerances have not been changed to hide them.

Fonts were installed in the standard user Fonts directory. Montserrat's two
static faces (version 8.000) were activated with the user's approval from their
existing downloaded files; no fonts are included in this fixture or shipped skill.
SHA-256 of the actual files:

| Face | SHA-256 |
| --- | --- |
| Montserrat-Regular | `c3fb0280e4339f6c70cea42b8b432c6fb17fde130fbb12e9209c7cdfa79d976f` |
| Montserrat-Bold | `98b1486810c2eccfaa17d4610a83c12794c0798ef5e9eb41aea038794292a187` |
| CMGSans-Regular | `7cf3f0cd3ac31817ccb47555b5369b78689d2f137996e3975dfda4a44bd8f2fd` |
| CMGSans-Bold | `f75612a7c3ae420b10f9fc5d1f8a7ceae98ba2d9542426300a5b3a852ee29f08` |

`FontCharsetNativeTests` checks the independent native pair and font-table
extraction everywhere; host-font rendering tests require these installed faces.
`RTFFontDiagnosticsTests` also covers braced and Cocoa flat font tables, charset
absence/order, missing fonts, and unchanged RTF bytes.

No direct native database writes, helper changes, app updates, screen changes,
or live-output triggers were used. The two acceptance decks remain in the test
library for inspection. Syphon discovery returned no configured sources; the
native rendering oracle here is Slide Images export.
