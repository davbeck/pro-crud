# Background sourcing and generation

Use this reference when selecting, acquiring, assigning, or generating a
background for worship or teaching. Read
[`design-guidance.md`](design-guidance.md) first for the existing-library,
screen, Look, typography, layout, contrast, and cue-timing guidance.

## Contents

- [Inspect local media first](#inspect-local-media-first)
- [Source order](#source-order)
- [One visual identity per song](#one-visual-identity-per-song)
- [ProContent](#procontent)
- [Church Motion Graphics](#church-motion-graphics)
- [Unsplash](#unsplash)
- [Generate an original still](#generate-an-original-still)
- [Generate an original motion](#generate-an-original-motion)
- [Prompt recipe](#prompt-recipe)
- [Apply and verify](#apply-and-verify)

## Inspect local media first

Assume media already available in the user's local ProPresenter library is
usable. Inspect it before searching or generating anything:

1. The Media Bin registry at `Playlists/Media`.
2. Backgrounds referenced by relevant songs, sermons, announcements, and recent
   services under `Libraries`.
3. Usable source files under the workspace's `Media` directory.
4. Church, series, event, seasonal, and ministry artwork that establishes a
   visual convention for the current content.

Start with:

```sh
pro-crud dump '/path/to/UserWorkspace/Playlists/Media'
pro-crud dump '/path/to/UserWorkspace/Playlists/Media' --format json
rg --files '/path/to/UserWorkspace/Media'
```

Dump the relevant presentations as well. Prefer a suitable local asset that fits
the message, energy, selected template, exact Audience-screen dimensions, and
current service without duplicating another song's background.

When an asset exists in `Playlists/Media`, preserve its canonical media object
and UUID:

```sh
pro-crud edit set-media INPUT.pro \
  --path '/ACTUAL/MEDIA/COMPONENT/PATH' \
  --from-playlist '/path/to/UserWorkspace' \
  --playlist 'PLAYLIST NAME' \
  --item 'EXACT MEDIA ITEM NAME' \
  --output OUTPUT.pro
```

Use the actual component path reported by `dump`. If the candidate is only a
local file, `edit set-media --source FILE` creates a new media identity.

Choose attachment based on playback:

- Use a slide element when the still belongs to one slide's composition.
- Use a background-media action when a still or motion should begin once and
  persist across lyric cues.
- Do not repeat the same motion element on every lyric slide when that would
  restart its loop.

A `.probundle` can include referenced background media in either workflow.

## Source order

Search in this order:

1. Existing Media Bin items, presentations, workspace files, and church or
   series artwork.
2. ProContent available through the user's account, prioritizing Premium when
   that access is visible or confirmed.
3. CMG media available through the user's subscription, purchases, or free
   catalog.
4. An appropriate free Unsplash photograph when a still is suitable.
5. A newly generated original still or motion.
6. A simple restrained treatment when no media fits naturally.

Relevance and legibility outrank provider order. Choose by the content's message,
tempo, energy, palette, quiet-zone fit, room, and Look rather than provider
loyalty. Target the exact pixel size and aspect of the main Audience screen, not
a generic 1080p or 4K default.

## One visual identity per song

Use one selected background throughout a song for visual continuity. Do not use
that same visual for another song in the service or set. A deliberate reprise or
medley may share it when leadership intends that musical continuity. If a song
changes backgrounds by section, reserve all of those related variations for
that song.

Before assigning media, make a simple service inventory containing each song
and its selected item. Compare the canonical media UUID and resolved path where
available, and review thumbnails side by side. A copied, renamed, cropped, or
re-encoded version can still look like the same song identity even when its
technical identifier differs.

Maintain coherence across the service with related colors, visual energy, or
material while keeping each song's actual asset distinct. Avoid recent-service
reuse when the local library offers a strong alternative, but do not sacrifice
message fit or readability merely for novelty.

## ProContent

Use [ProContent](https://procontent.renewedvision.com/) for stills and motions.
Media already downloaded into the local workspace is immediately eligible for
selection.

When acquiring something new, inspect **ProPresenter Settings -> Account** or
use the user's confirmation to determine whether the signed-in ProContent
account has Free or Premium access. Prioritize the broader Premium catalog when
available. Otherwise search the Free catalog and the user's existing downloads.

Browse and download through ProPresenter's Media Bin so the item lands in a
named playlist at the required destination size, then select it with
`--from-playlist`.

Useful references:

- [Using ProContent inside ProPresenter](https://support.renewedvision.com/hc/en-us/articles/14648908292755-Using-ProContent-Inside-of-ProPresenter)
- [Browse ProContent](https://procontent.renewedvision.com/search)
- [Browse free ProContent](https://procontent.renewedvision.com/search?assets%5BrefinementList%5D%5Blicense_type%5D%5B0%5D=free)
- [ProContent plans](https://procontent.renewedvision.com/pricing)

## Church Motion Graphics

Use the CMG [motion-background](https://shop.churchmotiongraphics.com/library/motion-background)
and [still-background](https://shop.churchmotiongraphics.com/library/still-background)
catalogs when the user has access, and use the
[CMG free-media page](https://www.churchmotiongraphics.com/free-worship-media/)
for free options. CMG offers both still and motion backgrounds. TempoMatch can
help find motion by song and tempo, but still evaluate message, palette, energy,
quiet zone, screen size, and per-song uniqueness.

Download the selected resolution and add it to a clear Media Bin playlist before
assigning it. Keep the provider and item name in the local media organization so
another operator can find it again.

## Unsplash

Use [Unsplash](https://unsplash.com/) for free still photography when a natural
or photographic image supports the content. Choose an image under the
[Unsplash License](https://unsplash.com/license) and download enough resolution
to crop to the exact destination canvas without upscaling.

Prefer broad atmosphere, texture, landscape, architecture, or a simple focal
subject with a usable quiet zone. Avoid imagery whose faces, logos, signs,
artwork, or visual detail distract from the words. Record the image URL and
creator with the local item so it can be found again.

## Generate an original still

Generate a still when no existing or downloadable asset fits. Use the exact
pixel dimensions and aspect of the main Audience screen. If several screen
destinations need materially different crops, generate or recompose separate
versions.

Use these defaults unless the church has an established media standard:

- Opaque sRGB at the final output dimensions; do not upscale a smaller result.
- PNG for graphic or illustrative fields and high-quality JPEG for photographic
  material. Crop intentionally; never stretch.
- Abstract, atmospheric, or natural texture with broad forms, restrained
  contrast, and low-to-medium spatial detail.
- Two to four related hues with no bright hotspot behind text.
- Energy and palette derived from the specific song, sermon, or moment.
- No text, pseudo-text, numbers, logos, watermarks, interface elements, faces,
  hands, branded objects, or album-cover imitation unless the user explicitly
  requests and reviews a relevant subject.
- Several content-specific candidates, reviewed with the longest and most
  difficult real cue before selection.

Match the quiet zone to the selected template:

| Template geometry | Generation composition |
| --- | --- |
| Centered text | Keep the central 60% low-detail and luminance-stable; place interest in the outer thirds |
| Left-aligned text | Keep the left 60% quiet; place interest toward the right third |
| Right-aligned text | Keep the right 60% quiet; place interest toward the left third |
| Lower text or lower third | Keep the lower 30% quiet and stable across the width |
| Split or bilingual text | Keep the central 80% broadly uniform and avoid a strong center-line subject |

## Generate an original motion

Generate motion only with a tool that produces real video. If only a still-image
generator is available, create a still rather than simulating motion by default.

Use these defaults unless local media establishes another standard:

- Exact Audience-screen aspect and pixel dimensions, Rec.709, no audio, and a
  frame rate compatible with the existing media library; 30 fps is a practical
  default.
- A 20-30 second genuinely seamless loop with continuous position, velocity,
  exposure, and color across the boundary.
- Fixed camera and slow, continuous movement matched to the content.
- The selected template's quiet zone remains stable in every frame.
- No cuts, flashes, flicker, strobing, rapid acceleration, spins, tunnel motion,
  abrupt zoom, or high-contrast object crossing the text zone.
- A ProPresenter-compatible H.264 MP4 delivery file with `yuv420p` pixel format
  when no other local delivery standard is established.

Inspect representative dark, bright, and busy frames and the loop boundary.
Play two complete loops in ProPresenter. Reject motion whose busiest frame
breaks text contrast or whose restart is visible.

## Prompt recipe

Use this prompt shape for a generated still:

```text
Create an original full-bleed [ASPECT] worship background at [WIDTH]x[HEIGHT]
for [song or moment]: [low, balanced, or high] visual energy,
[palette/material], and [mood or brief metaphor]. Use broad soft forms and
subtle depth. Keep [template-specific text zone] low-detail,
luminance-stable, and free of focal subjects; place visual interest in
[outer or opposite area]. No text, letters, numbers, pseudo-glyphs, logos,
watermarks, people, faces, hands, branded objects, album-cover imitation,
hard borders, interface elements, bright hotspots, or dense high-frequency
texture. Opaque sRGB.
```

For true motion, append:

```text
Use slow continuous movement matched to [tempo or moment], a fixed camera, and
a 20-30 second seamless silent loop. Keep the text zone stable in every frame.
No cuts, flashes, flicker, strobing, abrupt acceleration, tunnel motion, abrupt
zoom, or objects crossing the text zone. [FRAME RATE] fps, Rec.709,
[WIDTH]x[HEIGHT].
```

Do not ask the generator to render lyrics or announcement copy. Use the words
only to derive mood, metaphor, palette, and energy; add editable text in
ProPresenter.

## Apply and verify

Before delivery:

1. Confirm the presentation canvas and media match the exact main Audience-screen
   dimensions and the relevant Looks.
2. Confirm every song has an assigned background and no different song uses the
   same or visually equivalent item.
3. Render every lyric cue over the actual still. For motion, test representative
   dark, bright, and busy frames and play two loops in ProPresenter.
4. Verify a persistent background starts at the intended song boundary, does not
   restart on every lyric cue, and changes intentionally at the next song.
5. Preview each relevant Look and alternate Theme on its destination Screen.
6. Run `pro-crud validate DOCUMENT --workspace WORKSPACE --strict-media` and
   investigate every identity, URL, dimension, registry, or missing-file warning.
7. Complete the back-row and live-output checks from `design-guidance.md`.
