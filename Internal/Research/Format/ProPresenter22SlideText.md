# Native 22 slide text editing

Collected October 15, 2026, using the authorized local development workspace,
ProPresenter 22 beta build **369098875** on macOS **27.0.1**. Cloud was skipped.
The existing native-exported 21 fixtures remain the regression baseline.

## Owned fixture and independent native edit

`Fixtures/ProPresenter22/Native/Text/` contains only the owned acceptance
Presentation, stream `bfa7b647-93ab-5ee6-b397-ec61b08bcfee`, with its retained
history. The selected cue is `2FABF989-5E73-4CCE-8139-33F50F483922`, slide action
`586CB32A-4D87-4524-A07D-B6F571B5B9D0`, and text element
`B9DEC841-620E-4A6B-876C-DF8BDF02A56C`. It is an 854×480 presentation with four
Master cues and a repeated group arrangement. The native text element uses
Helvetica Neue 42 and a 720.5625×391.1111 box at (66.71875, 44.4444).

`native-before` is the saved native blank text object. In the native **Reflow**
editor, replacing its fourth text area with `Native text acceptance — café 🎵`
and a second line changed only `text.rtf_data`, from 144 to 446 bytes.
`native-after` captures that independent native edit. The normal Editor canvas
was not accessible to keyboard input; Reflow's actual text area was used.
The official API has no slide-text authoring route and was not used to mutate it.

The actual native container chain is a cue map, movable action list, slide maps,
movable element list, text map, attributes map and movable custom-attribute list.
The **font is an atomic value map**, not a Loro map container.

## Production local operations

`workspace set-text` and version-1 `workspace apply` operation `set-text` select
an exact action UUID and an exact element UUID. Both use the existing
`DocumentEditor.setText/setRTF` semantics to calculate the replacement RTF and
font. The native adapter changes only RTF, clears old custom-range entries and,
when necessary, updates name/family/size/bold/italic in the existing atomic font
value while retaining other entries. It preserves all existing container IDs,
placements, actions, geometry, metadata and history. There is no JSON rebuild.

Plain text uses the element's default attributes. Matching plain text leaves
rich formatting and history untouched. An identical RTF replacement is also a
no-op. Actual changes to elements with delivery/element builds are rejected;
that native build graph has not yet been qualified for text replacement.

After quitting the native app and stopping the registered workspace helper,
the pinned harness passed preflight. The production plain-text command replaced
the fourth slide with `CLI text acceptance — café 🎵` and `Second line`.
Only the selected stream changed; one receipt was added and registry bytes
were unchanged. `cli-after` is the committed result. Native restart accepted
it **byte-identically**, including the stored version vector (`native-open`).
Reflow displayed the exact text. A subsequent native edit to `Native continued
text after CLI — café 🎵` and `Second line survives.` is retained as
`native-continued` and the independent File → Export → Presentation payload
`NativeReexport.pro`. Its history extends the CLI-authored state.

Selecting **Bold Italic** in the native text inspector then produced
`native-styled`. The native app retained its default Regular font metadata and
added three original-font ranges, including an Apple Color Emoji run. This
independent fixture exercises stale-range cleanup; it must not be synthesized
from a CLI-generated document.

`Replacement.rtf` is a separate AppKit-authored input with HelveticaNeue-BoldItalic
36, cyan text and an emoji. The production `--rtf` operation applied it to the
native-styled object. `cli-rich-after` contains the result, with the old ranges
removed and first-run default font updated. Exact RTF replay reported
`changed: false` and no receipts. Native restart again accepted the snapshot and
vector byte-for-byte (`native-rich-open`), and File → Export → Presentation
produced `RichNativeReexport.pro`. Native export preserves the text, first-run font and cyan styling, but
normalizes the RTF by introducing an explicit Apple Color Emoji fallback run.
It also derives paragraph alignment/tab stops and default fill from the RTF
and sets `is_superscript_standardized`. These are export transformations: the
saved native stream remains byte-identical after reopening. These experiments used the production
writer and its normal registration, stopped-writer, optimistic conflict and
atomic receipt checks.

## Rendering evidence and remaining limitation

`RichNativeSlide.png` is slide 4 from native **File → Export → Slide Images**,
**PNG (without slide background color)**, **Include Media Actions** enabled,
854×480. No reference image was recorded by the CLI or test framework. Native
export uses the four Master slides even when the repeated arrangement is
selected. Helvetica Neue and Apple Color Emoji resolve locally; the native
Presentation export introduces the explicit emoji fallback described above.

The native 22 unscaled-text layout now removes the legacy inset and uses
cap-height-centered baselines and font-derived line bodies for vertical
alignment. Both this middle-aligned export and the independent top-aligned
export have exactly matching occupied-pixel sets, including the emoji. See
[the alignment investigation](RenderingIssues/README.md#independent-native-22-alignment-probe).

The sRGB premultiplied RGBA comparison improved from **55,935 differing bytes**
to **96 bytes at 32 letter-edge pixels**, at the same 854×480 dimensions. The
remaining glyph antialiasing difference stays an explicit known issue in the
original exact comparison. Existing references, tolerances, and 21 rendering
behavior are unchanged. Native persistence and visual app acceptance do not
imply pixel-exact CLI text rendering in 22.

## Retained hashes (SHA-256)

| File | SHA-256 |
| --- | --- |
| `native-before.loro` | `6e7f52d22c66bd3dce73e4e40c93274916f20a1c0e642a29b88d911d4f5fc697` |
| `native-after.loro` | `f74c860b9792ddd77dcb015880858cff9a8853cf9bfec7c550d6622a9608ecc2` |
| `cli-after.loro` | `c2ce0c1ab683cc177c242e50a09ba9e2ee674110ff7995cb10a8151f20dfbbc4` |
| `native-styled.loro` | `60259ef81d38ed94df344a575baa3f23424fe573ce56ae9277efc6c16f829dc4` |
| `cli-rich-after.loro` | `73cef56fa55503193a2b956035aabff6016a883446e3039ffb479eec468b483c` |
| `RichNativeReexport.pro` | `fb6ed5a18502f15a1bce5db88ac999bcf67e6cfe3f979e36eac526e0d6e7fef2` |
| `RichNativeSlide.png` | `1c2a831f274296480a632878a39ef68b40c34da6af0564936b6e84696e6e9041` |

Tests cover independent native RTF agreement, unrelated-state retention,
update replay, native restart and continued editing, rich-text export normalization,
stale ranges, Unicode, no-ops, invalid RTF/IDs, delivery gating, strict manifest
fields and relative RTF files. Broader native text-delivery and animation edits
remain unfinished.

Full regression run: **395 core + 91 CLI + one harness test pass**, with the
eight existing known rendering issues and the new explicit native 22 layout
comparison (nine total). SwiftFormat and SwiftLint pass.
