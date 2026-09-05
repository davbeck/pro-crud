# Presentation Rendering Evidence

Historical fixture notes moved from the public reference on September 5, 2026.

## Element Paint Order

Slide elements are stored front-to-back and painted in reverse stored order.
The focused `Reverse stored element paint order` fixture isolates this behavior.
Its stored `info` sequence is `[0, 2, 1]`, while ProPresenter paints source
indices `[2, 1, 0]`; that counterexample proves `info` is not the sorting key.

The meaning of `slide.elements[].info` remains unresolved. Preserve it as
compatibility metadata, but do not reorder elements from it.

## Presentation Background And Slide Background

Presentation-level background and slide-level background are separate. The focused `Transparent background` reference slide verifies whether untouched PNG pixels remain transparent when the generated document includes visible elements.

Writers should choose the field that matches ProPresenter's UI behavior for the intended operation and verify with an export when background parity matters. Renderers should preserve transparent untouched pixels unless a fixture proves that a stored background paints for that export workflow.

### Media Actions, Transitions, And Playback Markers

A cue's `rv.data.Action.MediaType` carries the media element, its layer type,
transition/effect selection, retrigger flag, and ordered `markers[]`. Each
marker has its own UUID, time, color, name, and nested actions. The file layer
preserves that graph and refreshes marker plus nested-action UUIDs when an
action is copied into a new slide or template result.

The [official Playback Markers workflow](https://support.renewedvision.com/hc/en-us/articles/7171761588371-How-to-use-Playback-Markers)
limits markers to video and audio **media actions**; they do not apply to image
media or media slide elements. A static image export selects one video
thumbnail and does not run media time, transitions, marker actions, transport
seeks, or marker data links. A focused native video/audio-action fixture is
still required before semantic marker inspection or editing commands are
exposed.


The `Playlists/PlaylistTemplates` raw file contains an
`rv.data.PlaylistTemplate` store. Each saved template has a name and ordered
`PlaylistItem` values, so it can preserve the headers, placeholders, and
recurring presentations described in the [official Playlist Templates
workflow](https://support.renewedvision.com/hc/en-us/articles/40377194830995-Creating-and-Using-Playlist-Templates-in-ProPresenter).

The protobuf is vendored and losslessly available to code that handles raw
messages, but `DocumentKind`, `DocumentLoader`, archive editing, and the CLI do
not yet treat this store as a first-class document. Do not misidentify it as a
regular `PlaylistDocument` or overwrite it with a playlist. Add a focused,
ProPresenter-authored store fixture before exposing inspect/edit commands; it
must cover headers, placeholders, and presentation items plus template
creation from the UI.


## Import Cache Note

The former `Docs/ProPresenter.md` recorded that ProPresenter 21.4 can show cached
renderings after replacing a presentation by importing a bundle with the same
internal `.pro` filename. It recommended using a unique name or deleting the
original and restarting ProPresenter before reimport. The public guide uses the
unique-name workflow; the deletion/restart workaround is retained here as
research context.
