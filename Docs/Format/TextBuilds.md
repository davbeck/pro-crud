# Text Builds And Delivery

ProPresenter uses several related animation concepts that should not be
collapsed into one file-format feature. A slide transition replaces one slide
with another. An object **Build In** or **Build Out** animates one slide object.
For a text object, **Delivery** can divide one Build In into separately advanced
text units. **Build Order** is the ordered schedule containing both ordinary
object builds and those text units.

This page describes ProPresenter's build model, its stored graph, and the limits
of `pro-crud` support. The persisted Delivery structure described here applies
to ProPresenter 21.4 (build 352583705); By Bullet paragraph indexing is supported for this version. Underline
segmentation is not established.

Product behavior is described in Renewed Vision's
[Transitions guide](https://support.renewedvision.com/hc/en-us/articles/360041342354-Using-Transitions-In-ProPresenter)
and [ProPresenter 7 user guide](https://files.renewedvision.com/propresenter/support/Pro7UserGuide.pdf).

## Product Model

| Product term | Scope | Behavior |
| --- | --- | --- |
| Slide transition | Whole slide | Controls how the incoming slide replaces the outgoing slide. It is not an object build. |
| Build In | One object | Introduces the object. An object can have at most one Build In. |
| Build Out | One object | Removes the object. An object can have at most one Build Out, after its Build In. |
| Delivery | Text Build In | Selects All at Once, By Bullet, or Underline behavior for the text. |
| Build Order | One slide | Orders object Build Ins, object Build Outs, and individual Delivery steps. |
| [Scrolling Text](https://support.renewedvision.com/hc/en-us/articles/4403013895059-Using-Scrolling-Text-in-ProPresenter) | One text object | Continuously moves text; it is a separate text-scroller feature, not Delivery. |

`reveal_type` is the schema name for Delivery. It should not be confused with
an effect whose display name happens to be “Reveal.”

### Text Delivery Modes

Renewed Vision documents three Delivery modes:

- **All at Once** builds the complete text object as one object.
- **By Bullet** delivers each carriage-return-separated line independently.
  Literal list or bullet styling is not required.
- **Underline** initially displays the non-underlined text and progressively
  reveals underlined portions, supporting fill-in-the-blank slides.

The format stores these as `NONE`, `BULLET`, and `UNDERLINE`, respectively.

### Start And Delay

The documented Build Order UI exposes these contextual start choices:

- **After Transition** is available for the first build and starts after the
  slide transition.
- **On Click** waits for the next click, Space, or Right Arrow.
- **With Build** starts with the preceding build and does not inherit that
  preceding build's delay.
- **After Build** starts after the preceding animation and its delay complete.
- **With Slide** is available for a sole or first Build In and enters with the
  slide transition.

A **Delay** postpones the selected item after its start condition fires. The
persistent enums are `ON_CLICK`, `WITH_PREVIOUS`, `AFTER_PREVIOUS`, and
`WITH_SLIDE`. The exact mapping of the contextual **After Transition** label
and drag-grouping changes to saved fields is not established. Negative-delay
handling is also unspecified here.

### Playback Rules

ProPresenter playback follows these rules:

- Triggering the slide starts only the steps whose start condition permits it.
- Each advance consumes the next on-click step and any steps grouped with it.
- ProPresenter shows the remaining build count on the slide thumbnail.
- Build progression does not run backward. Clearing and retriggering the slide
  restarts it, while triggering another slide skips unfinished steps.

[Themes may define object builds](https://support.renewedvision.com/hc/en-us/articles/11910559859603-Themes-in-ProPresenter).
Renewed Vision also states that object and text builds remain maintained when a
Theme or alternate Theme is applied in
[ProPresenter 7.7](https://www.renewedvision.com/blog/propresenter-7-7). The
[native PowerPoint importer](https://support.renewedvision.com/hc/en-us/articles/45377042213011-Importing-PowerPoint-files-Natively-within-ProPresenter)
preserves applicable builds and transitions but does not support every
PowerPoint animation, including emphasis animations. Those product-level
statements do not yet establish the exact graph-rewrite rules needed by this
package.

## Persistent Graph

The relevant protobuf fields are in
[`slide.proto`](../../Vendor/ProPresenter7Proto/proto/slide.proto):

```text
Slide
  element_build_order[] -> UUID references
  elements[]
    element.uuid
    build_in?
      uuid
      elementUUID
      start
      delayTime
      transition
    build_out?          # same Build shape
    reveal_type         # NONE, BULLET, UNDERLINE
    childBuilds[]
      uuid
      start
      delayTime
      index
    reveal_from_index
```

A [`Transition`](../../Vendor/ProPresenter7Proto/proto/effects.proto) stores a
duration, optional favorite UUID, and an `Effect`. Effects have their own
identity, display metadata, render ID, category, behavior description, and
typed variables. The effect graph should be treated as extensible data, not as
a closed list of transition names. Current official documentation does not
promise a stable exhaustive registry for ProPresenter 21.

Proto3 defaults are significant when inspecting JSON:

- omitted `start` means `ON_CLICK`;
- omitted delay and child index mean zero;
- omitted `reveal_type` means `NONE`;
- omitted `reveal_from_index` means zero; and
- an absent Build or Transition message is different from a present message
  whose scalar fields all have default values.

There is also a `SlideElementTextRenderInfo.Layer.text_build_index` field in
`proCore.proto`. `pro-crud` does not connect that value
to persisted authoring data, so it is not part of the supported authoring model.
`Build.start` and `ChildBuild.start` have the same four numeric cases, although
the checked-in schema declares them as separate nested enum types.

## Stored Build References

Ordinary object builds are scheduled by references from `element_build_order`
to `build_in` and `build_out` UUIDs. Build Ins and Build Outs can be interleaved.

ProPresenter 21.4 By Bullet documents can instead store a parent `build_in`
containing the transition, with separately scheduled `childBuilds` containing
no transition. In that structure, `element_build_order` references child UUIDs
and omits the parent Build In UUID. Do not infer a complete Delivery schedule
from the parent build alone.

Preserve these compatibility cases during lossless editing:

- A Build's `elementUUID` can differ from its containing element and fail to
  resolve within the document.
- `reveal_from_index` can remain nonzero when Delivery is `NONE` and no builds
  or children are active.
- Defined children need not all appear in the build order.
- A parent Build In need not appear in the order when its children do.

For By Bullet, nonempty hard-return-separated paragraphs are the text units.
Empty paragraphs and a trailing return do not add steps; a soft line break
(U+2028) stays in its paragraph. `reveal_from_index` is the number of units
initially visible. Child index zero introduces the second unit. There are
`N - 1` children for `N` units, including children for initially visible units.
The schedule includes children whose index is at least
`reveal_from_index - 1`. When the initial count is zero, the parent Build In
UUID precedes the children and introduces the first unit.

## `pro-crud` Support

The binary layer decodes and losslessly round-trips all known fields,
including unknown protobuf data. Graph copying regenerates element, Build, and
child-build UUIDs, then remaps known order and `elementUUID` references.

## Authoring By Bullet Delivery

Configure a text object using its canonical text path:

```sh
pro-crud edit set-text-delivery INPUT \
  --path '/cues[index=8]/actions[index=0]/slide/presentation/base_slide/elements[index=0]/element/text' \
  --initially-visible 1 \
  --output OUTPUT
```

`--initially-visible 1` leaves the heading visible and reveals each subsequent
nonempty paragraph on successive clicks. Zero initially hides the entire text
object. The count must be between zero and the number of nonempty paragraphs;
using the full count leaves all text visible with no scheduled Build In steps.
The operation retains an existing Build In transition, start condition, and
step delays. A new Build In uses a 0.3-second Dissolve with On Click steps.
Existing custom start conditions still apply; an automatic step does not become
On Click merely because it was retained.

Use `--clear` instead of `--initially-visible` to remove the text Build In,
Delivery children, and their schedule references. Build Out is retained.
Both forms are supported by `edit apply` using `command: "set-text-delivery"`
and the same option keys.

`set-text`, including RTF input, automatically rebuilds By Bullet children and
schedule references for the replacement text. It preserves the initially-visible
count, clamping it to the new unit count when text shrinks. Surviving children
retain UUIDs and timing; new children receive fresh UUIDs and On Click timing.
Obsolete child references are removed, and new steps are inserted next to their
siblings while preserving unrelated object builds and their order. The
operation preserves unknown fields on retained messages.

A text edit cannot infer a new initial visibility intent. Use
`set-text-delivery --initially-visible 1` explicitly when the heading should be
the only initially visible unit. This also repairs an inherited stale schedule.

Template resolution uses the template wrapper's Delivery settings and rebuilds
By Bullet children for assigned text. Empty template slots have no scheduled
text reveals; their initially-visible count becomes zero. Source wrapper builds
are not transferred. Underline and unknown Delivery modes remain preserved
without resegmentation; use native ProPresenter to edit those modes.

## Inspection And Validation

- `dump` reports Delivery mode, initial visibility, child indexes and counts,
  and the slide's ordered build UUIDs.
- Validation reports `builds.inconsistent-text-delivery` when By Bullet children
  or schedule membership do not match the current text. Custom step order and
  timing are retained, so this is a warning rather than a blanket rejection of
  native documents. Other active Delivery modes produce
  `builds.unverified-text-delivery`.
- Static rendering draws the stored, unanimated composition. It does not
  evaluate Build In, Build Out, Delivery, or Build Order state.

After authoring, verify initial visibility and every advance through the final
text unit in ProPresenter, particularly when using alternate Themes or custom
start conditions. A static render cannot verify click progression.
