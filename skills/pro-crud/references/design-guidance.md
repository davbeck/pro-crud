# ProPresenter design guidance

Use this reference when creating or restyling audience-facing slides.

## Contents

- [Inspect the existing system first](#inspect-the-existing-system-first)
- [Principles and house standard](#principles-and-house-standard)
- [Screens, Looks, and source layers](#screens-looks-and-source-layers)
- [Typography](#typography)
- [Palette](#palette)
- [Layout and readability](#layout-and-readability)
- [Background selection and visual energy](#background-selection-and-visual-energy)
- [Content editing and accuracy](#content-editing-and-accuracy)
- [Announcement slides](#announcement-slides)
- [Teaching and sermon content](#teaching-and-sermon-content)
- [Playback, rehearsal, and visual silence](#playback-rehearsal-and-visual-silence)
- [Media organization](#media-organization)
- [Bundled Theme](#bundled-theme)
- [Authoring workflow](#authoring-workflow)
- [Preflight checklist](#preflight-checklist)
- [Common adaptations](#common-adaptations)

## Inspect the existing system first

Treat the current ProPresenter workspace as the starting design system. Before
choosing a font, template, background, or canvas:

1. Inspect configured Screens. Record the exact pixel dimensions of the main
   Audience screen and any auxiliary, lobby, stage, or stream destinations that
   need distinct content. In ProPresenter, use **Screens -> Configure Screens**
   to find these output names and dimensions.
2. Inspect the Looks used by the service. For each destination, note the enabled
   presentation, media, video-input, announcement, prop, message, and mask
   layers, plus any alternate Theme used to translate content. Review them under
   **Screens -> Edit Looks**.
3. Inspect existing Themes and representative recent songs, sermons,
   announcements, and playlists. Identify recurring margins, line counts,
   alignments, type families, weights, colors, panels, transitions, and editorial
   conventions.
4. Inspect the Media Bin and recent presentations before looking for new media.
   Look for church-specific graphics, logos, current sermon-series art, event
   identities, seasonal art, and backgrounds already associated with the set.
5. Identify fonts installed on the authoring and playback Macs and fonts already
   used successfully in the library.

Match established church and series conventions unless the user asks for a new
direction or the existing treatment fails readability. Prefer adapting a proven
local Theme to replacing it. Use the bundled ProCRUD Theme when the library has
no more suitable starting point.

The presentation canvas should exactly match the main Audience screen's pixel
dimensions. Matching only its aspect ratio is not enough: ProPresenter warns
when a presentation does not match the size of at least one configured screen.
Create separate screen-specific compositions when another destination has a
different aspect, crop, bezel arrangement, or reading distance.

## Principles and house standard

Readable, accurate, timely content is the primary job. Visual atmosphere should
support participation, comprehension, recall, or action without drawing
attention to its own effects. Remove clutter before adding decoration.

Consistency makes design disappear. Within a song, sermon, series, event, or
service section, keep the chosen typography, margins, alignment, capitalization,
punctuation, panel treatment, palette, and transition behavior stable. Preserve
useful standards week to week.

Record the house decisions that operators need to reproduce:

| Standard | Record and verify |
| --- | --- |
| Type | Font family and weight, size, case, tracking, and effective baseline spacing |
| Layout | Alignment, margins, maximum lines, and obstruction or subject zones |
| Contrast | Text/fill colors, panel opacity, shadow, and stroke treatment |
| Playback | Text timing, background transition, blank-slide behavior, and ending state |
| Output | Exact canvas size, crop or bezel gaps, projector/LED behavior, camera framing, and ambient light |

## Screens, Looks, and source layers

Choose the source layer before choosing a template:

| Content | Primary source | Template role | Required preview |
| --- | --- | --- | --- |
| Worship and full-screen teaching | Colorful motion or still background | Audience typography and graphic structure | Bright, dark, and busy still/motion states |
| Streaming or IMAG | Separately composed live camera input | Transparent overlay for compact lyrics, identity, scripture, or points | Subjects framed left, center, and right with varied exposure |
| Announcements | Event artwork, photo, or designed still | Information hierarchy and call to action | Every routed audience, stream, and lobby composition |

For worship and teaching, let the background carry atmosphere and color while
the template carries hierarchy. Prefer media with a quiet region behind type,
or choose a local contrast panel when the image is busy.

For streaming, the camera remains the primary visual. Keep slides transparent
except for intentional rules, strips, and panels. Do not add a full-canvas fill
to a camera-overlay template.

Inspect rather than assume each Look. A room output may retain presentation and
media while a stream output disables media, enables a camera input, and applies
an alternate Theme to the same content. Another Look may route announcements or
props differently. Preview the original audience composition and every relevant
alternate-template output, then test the actual live result when runtime layers
matter.

## Typography

Start with the church's existing typography. Confirm that every selected family
and weight is installed on all authoring and playback Macs, and inspect how it
already renders in ProPresenter.

- Preserve a readable font already used consistently by the church or series.
- If **CMG Sans** is installed, it is a strong choice for worship lyrics,
  teaching, and announcements.
- **Avenir Next** is the default in the bundled ProCRUD Theme and a useful
  fallback. It is not a required house font.
- Consider another installed family when it better matches the church's visual
  identity or language requirements.
- When the user wants a specific voice, recommend an appropriate
  [Google Fonts](https://fonts.google.com/) family and install the required
  weights on every playback computer. This is particularly useful for a unique
  announcement, event, series, or title treatment.

Use one family by default and no more than two in a presentation. A distinctive
display face can suit a short title or announcement headline; pair it with a
restrained, highly readable face for details. Long scripture, lyrics, and body
copy should not depend on a decorative face.

The bundled Theme uses these Avenir Next faces:

| Purpose | PostScript name |
| --- | --- |
| Body emphasis | `AvenirNext-Medium` |
| Lyrics and strong labels | `AvenirNext-DemiBold` |
| Titles and compact lower thirds | `AvenirNext-Bold` |
| Display titles | `AvenirNext-Heavy` |
| Expressive quotation emphasis | `AvenirNext-HeavyItalic` |

At a 1920x1080 reference size, 48-96 points is a useful lyric range. Scale the
starting point proportionally for the actual canvas, then choose one lyric size
by testing from the back of the room. Keep it throughout the song. Do not enlarge
a short line merely to fill empty space. Split content at a natural phrase or
choose a narrower readable face before shrinking below the venue-tested size.

Projected multiline text needs visibly open leading. Start near an effective
1.2 baseline-spacing multiple and judge the rendered distance rather than
copying a numeric value from another application. Use modest positive tracking
for lyrics and keep it stable within a song. Reserve dramatic tracking for short
labels and display phrases.

Sentence case is the lyric default. All caps can work for a short one- or
two-line refrain, title, or heading, but should not become a general editorial
policy.

For unboxed light text over media, use a subtle zero-offset black shadow or a
restrained dark stroke only when contrast testing requires it. Effects should
not be immediately noticeable. Avoid shadows inside opaque or translucent
panels.

## Palette

Begin with the church, series, event, and room-lighting palette. Keep color
systems simple: monochromatic, complementary, or one warm/cool family with one
dominant accent. Color associations vary by culture and context, so treat them
as prompts rather than fixed meanings.

The bundled Theme starts with warm near-white text (`#F7F4EC`), near-black ink
(`#111721`), aqua (`#57D3C2`), and amber (`#F5C451`). Adapt these colors when an
established local identity is available.

Keep lyrics light on dark media by default. On genuinely bright media, use dark
text or filled light text with a restrained dark stroke. Do not color lyrics
merely to match a background. Validate the palette on the real projector or LED
wall for hue shifts, blown highlights, crushed shadows, and ambient-light washout.

## Layout and readability

- Author at the exact main Audience-screen resolution. Redesign for a different
  aspect ratio rather than blindly stretching.
- Use 10-15% text margins as the normal 16:9 starting point; compositions may
  use more. Six percent is only a crop-safe floor, not a normal lyric margin.
- Use two or three lyric lines normally and four as a hard maximum. Camera/IMAG
  lyrics normally use one or two. Musical phrasing and complete thoughts outrank
  an arbitrary line count.
- Break content before font-down scaling makes one cue visibly smaller. Keep one
  venue-tested lyric size throughout a song.
- Centered horizontal and vertical alignment is the worship default. Preserve
  the chosen alignment throughout a song. Use left alignment for longer copy or
  when the media's focal area requires it.
- Use one primary hierarchy cue per slide: weight, size, position, or color.
  Combining all four usually creates noise.
- Preserve whitespace. Remove unnecessary text and graphics before tightening
  type or filling empty corners.
- Use a light-on-dark or dark-on-light panel when media is busy. About 50%
  opacity is a useful starting point; increase it only as contrast requires.
- Keep text away from screen seams, bezel gaps, room obstructions, camera
  subjects, faces, and primary gestures.
- For streaming, prefer the lower 20-30% or the side opposite the subject. Use a
  robust strip or panel when framing and exposure vary.
- Verify contrast against the darkest, brightest, and busiest expected media or
  camera states.
- Preserve semantic element names so template application can match content
  reliably.

## Background selection and visual energy

Choose media for the song, sermon, service, season, room, and community, not
merely because it is attractive. Lyrics remain the focal point. If a background
competes, choose a calmer crop or treatment when appropriate, or replace it.
Never force an unrelated visual into the presentation.

Use still backgrounds for low-motion moments, slower songs, traditional
contexts, or whenever movement adds nothing. Use motion intentionally and match
its speed to the music. Avoid persistent tunneling, rapid scrolling, flashes,
and movement that distracts or causes discomfort.

| Energy | Useful visual characteristics |
| --- | --- |
| Low | Dark/cool or monochromatic palette, still or slow movement, broad non-intersecting forms, low detail |
| Balanced | Controlled color contrast, quiet text zone, gentle direction, and limited forms |
| High | Brighter contrast, diagonal or intersecting direction, richer texture, and faster movement matched to the moment |

Use one selected background throughout a song, then choose a visually distinct
asset for every other song in the service. Reprises and medleys are intentional
exceptions. Keep the service coherent through related palette and energy rather
than repeating the same asset. Read
[`background-sourcing.md`](background-sourcing.md) for the local-first selection
and generation workflow.

## Content editing and accuracy

- Clean imported lyrics and scripture before styling. Remove accidental symbols,
  numbers, duplicate spaces, and inherited line breaks.
- Break lyrics by musical phrase and complete thought. Natural breaks often fall
  at punctuation, a conjunction, a rest, or a singer's breath. Listen to the
  song when phrasing is unclear.
- Recheck wrapping after changing font, weight, size, tracking, or canvas.
  Eliminate lone final words and rebalance isolated one-line cues.
- Follow the church's punctuation and capitalization policy consistently.
- Proofread spelling, homophones, apostrophes, omissions, repetitions, and
  verse/chorus order. Use a fresh human reviewer and, when possible, have the
  worship leader verify the final song and arrangement.
- Avoid projected operator directions such as `REPEAT 2X`, `MEN ONLY`, or
  `BRIDGE`, and omit unnecessary repeated lines.
- Do not add routine song-title slides unless leadership requests them. A hymn
  or songbook number is a practical exception. Keep required credits subordinate.

## Announcement slides

Use a dedicated announcement visual when an upcoming event or next step needs
attention and recognition. Inspect existing church, event, ministry, and series
artwork first. Reuse the same visual identity across the in-service slide,
pre-service loop, lobby display, web page, and social variants so people can
recognize the event later.

Establish a clear hierarchy:

1. Event or opportunity name.
2. One memorable visual idea.
3. Essential date, time, and location information.
4. One clear next step, such as register, volunteer, attend, or learn more.

An announcement accompanying a speaker can contain fewer details because the
speaker supplies context. An unattended pre-service or lobby loop must contain
enough information to act and remain visible long enough to read. Do not turn
the slide into a brochure; direct viewers to a short URL, information desk, app,
or registration page for secondary details.

Prefer a still composition with one focal image, generous whitespace, and
stable text. A distinctive installed face or suitable Google Font can give an
event a unique voice, but use a restrained information face for dates, location,
and the call to action. Keep the visual language related to the church while
allowing the event to be memorable.

When generating announcement artwork, create text-free key art at the exact
destination aspect and resolution with a planned quiet zone. Add event text,
logos, and details as editable ProPresenter elements. Create separate
screen-specific versions for audience, stream, lobby, portrait, or social
destinations instead of stretching or automatically cropping one master.

Use a QR code only when it is large, high-contrast, and tested from the intended
viewing distance; include a short readable alternative when practical. Verify
the event name, calendar date, day of week, time, location, registration status,
URL, QR destination, and call to action with a human reviewer.

Inspect the announcement layer and every relevant Look. Confirm the slide is
routed to the intended screens and that alternate templates preserve the event
hierarchy, artwork crop, and actionable details.

## Teaching and sermon content

Write the message first and design slides to support its natural flow. Spoken
content remains primary. Put only what aids comprehension, recall, or
note-taking on screen.

- **Titles:** include the full sermon title and optional subtitle. Distinguish
  the series from the current message. Show the title when or after the speaker
  introduces it rather than spoiling the reveal.
- **Scripture:** include the passage, reference, and translation. Keep the
  reference and translation secondary. Split long passages across cues rather
  than shrinking or crowding them, and hold each cue throughout the reading.
- **Points:** use brief, significant, memorable statements that still make
  sense out of context. Hold them long enough to copy.
- **Quotes:** include the quotation and attribution. A relevant image or author
  portrait can help, but the quotation remains primary.
- **Images:** use high-resolution, relevant photos or illustrations sparingly.
  Full-screen, framed, collage, and comparison layouts are valid when they
  explain the message rather than decorate it.

Keep one sermon visually coherent by duplicating established title, scripture,
point, quote, and image layouts and replacing content. A creative title face or
image treatment does not justify changing the body typography and spacing on
every cue.

## Playback, rehearsal, and visual silence

- Prepare early, know the set and service order, verify every media item, and
  rehearse the actual presentation with the worship team.
- As a starting point, show lyrics about two seconds before they are sung. On a
  fast song, advancing before the final word or two can keep the next phrase
  ready. Blank lyrics during a vocal gap longer than roughly three seconds.
- Reveal sermon scripture, points, or titles after the speaker begins them.
  Hold note-worthy content long enough to read or write.
- Use straight cuts or cross-dissolves unless another transition has a clear
  communicative purpose. Background dissolves can be slower than text; two to
  five seconds is a useful starting range.
- Use visual silence during communion, instrumentals, offering, prayer,
  reflection, or response when text would compete with the moment.
- For visual silence, use a blank content slide or cue with no text. Normally
  leave the previous background active so the moment does not introduce an
  unrelated visual change. Clear background, camera, or other layers only when
  the service transition and configured Look call for it.
- End in an intentional blank or clear state appropriate to the next service
  element. Never expose the cursor, desktop, application chrome, or playback
  tools.
- Maintain a rehearsed fallback for projector or LED, power, computer, storage,
  software, media, and operator failures.

## Media organization

Keep media findable and recoverable. Remove unusable duplicates, archive
outdated material, use logical names, and organize by semantic purpose with
aspect, resolution, and date where useful. Mirror the useful hierarchy in
ProPresenter and keep any temporary `New` inbox short-lived.

Assume media already available in the local library is usable. For newly
acquired assets, keep the provider or source name with the item so another
operator can find it again. Preserve corrected reusable songs, announcements,
and sermon layouts instead of rebuilding them each week.

## Bundled Theme

`assets/themes/ProCRUD Design System.proTheme` is a fallback design system with
four Theme documents and all 99 variations grouped like the CMG reference:

| Family and document path | Variations | Primary use |
| --- | ---: | --- |
| Classic Worship — `ProCRUD - Worship 1/Theme` | 24 | Restrained lyric arrangements and familiar alignment patterns over media |
| Creative Worship — `ProCRUD - Worship 2/Theme` | 27 | More expressive lyric hierarchy and graphic structure over media |
| Teaching — `ProCRUD - Teaching/Theme` | 24 | Titles, scripture, points, lists, quotes, and speaker information |
| Streaming — `ProCRUD - Streaming/Theme` | 24 | Transparent camera overlays, lower thirds, scripture, points, and identity |

Inspect the Theme with `pro-crud dump` to see the exact document paths and
template names. Because template names can repeat across documents, qualify the
selection:

```sh
pro-crud render INPUT.pro \
  --theme '<skill-directory>/assets/themes/ProCRUD Design System.proTheme' \
  --theme-document 'ProCRUD - Worship 1/Theme' \
  --template 'Medium' \
  --size WIDTHxHEIGHT \
  --template-report /tmp/template-report.json \
  --output /tmp/template-preview
```

The bundled typography uses Avenir Next. Prefer an established local Theme and
font system when available. Worship and teaching variations are intended to be
evaluated over actual colorful media; Streaming variations are intended to be
evaluated over the actual camera composition selected by the Look.

## Authoring workflow

1. Inspect the workspace, Screens, Looks, existing content, Themes, Media Bin,
   fonts, and church or series artwork.
2. Confirm the exact source text, communication goal, main Audience-screen
   dimensions, auxiliary destinations, obstruction zones, and subject zones.
3. Select an established local Theme or a document-qualified bundled template.
   For backgrounds, follow
   [`background-sourcing.md`](background-sourcing.md) before acquiring anything.
4. Render the real content transiently at the exact destination size and review
   the template report.
5. Review every relevant Look and alternate output.
6. Apply the template to a copied destination with `--dry-run` first, then write
   with `--output` after the assignments are sound.
7. Render every cue whose length or line count differs materially. Rehearse the
   final order, transitions, blank cues, background persistence, and live output.

For a new presentation, pass the actual main Audience-screen size:

```sh
pro-crud create presentation \
  --output OUTPUT.pro \
  --name 'Presentation Name' \
  --size WIDTHxHEIGHT \
  --theme '<skill-directory>/assets/themes/ProCRUD Design System.proTheme' \
  --theme-document 'ProCRUD - Worship 1/Theme' \
  --template 'Medium'
```

Use a slide element when an image is part of that individual slide's
composition. Use a background-media action when a still or motion should start
once and persist behind several cues. Do not repeat a motion element on every
lyric slide when that would restart its loop. A `.probundle` can include the
referenced background media in either workflow.

New template instances retain each element's base typography and appearance.
Use plain `set-text` for normal replacement and RTF only for intentional mixed
inline styling. Address named slots with semantic selectors rather than
positional indices.

## Preflight checklist

| Check | Pass condition |
| --- | --- |
| Context | Existing Themes, content, fonts, artwork, media, Screens, and Looks were inspected before introducing a new convention |
| Purpose | Every cue aids participation, comprehension, recall, note-taking, or action |
| Accuracy | Spelling, phrasing, order, scripture reference, event details, URL/QR, and editorial policy have human review |
| Type | Fonts and weights resolve on playback Macs; lyric size is stable within each song; no unintended font-down scaling |
| Layout | Canvas exactly matches the main Audience screen; margins, phrasing, line counts, seams, obstructions, and subject zones pass |
| Contrast | Darkest, brightest, and busiest still, motion, or camera states remain readable |
| Coherence | Palette, alignment, typography, and component language remain coherent through the song, sermon, series, or event |
| Media | Asset resolves, fits the canvas, matches the content and energy, and is distinct from backgrounds assigned to other songs |
| Looks | Original and alternate-template outputs preserve hierarchy, crop, layers, and intended transparency on every destination |
| Playback | Cue order, timing, blank-slide behavior, background persistence, transitions, and loops are rehearsed |
| Output | Back-row, projector/LED, crop, bezel, ambient-light, camera-framing, and destination-screen checks pass |

## Common adaptations

- **Custom palette:** follow existing church or series colors first; otherwise
  change accent and panel colors consistently across the selected family.
- **Non-16:9 output:** design at the destination's exact resolution and restore
  appropriate safe margins, text measure, and panel proportions.
- **Long scripture:** split passages across cues before compressing tracking or
  margins. Keep reference and translation visible and hold each cue through the
  reading.
- **Bilingual lyrics:** align corresponding phrases and use similar optical
  weight even when another installed family supplies fallback glyphs.
- **Live video:** preserve slide transparency and compose the camera separately.
  Keep text outside likely face and gesture zones, use a stable panel when
  exposure varies, and test several camera framings through the actual Look.
- **Image teaching slide:** use one purposeful full-screen or framed image, or a
  clear comparison. Use collages sparingly and keep captions subordinate.
- **Announcement:** reuse the event identity, but recompose hierarchy and crop
  for each output. Test unattended readability and every actionable link.
- **Visual silence:** blank the content while normally preserving the preceding
  background. Clear additional layers only when the transition requires it.
