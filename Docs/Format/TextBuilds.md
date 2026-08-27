# Text Builds And Delivery

ProPresenter uses several related animation concepts that should not be
collapsed into one file-format feature. A slide transition replaces one slide
with another. An object **Build In** or **Build Out** animates one slide object.
For a text object, **Delivery** can divide one Build In into separately advanced
text units. **Build Order** is the ordered schedule containing both ordinary
object builds and those text units.

This note separates official product behavior from persistent-format evidence.
It also defines the functionality that `pro-crud` should expose. The proposed
editing and rendering interfaces are not implemented yet.

## Evidence And Confidence

The behavior described below comes from three sources:

- **Documented** means Renewed Vision describes the behavior in the
  [Transitions support article](https://support.renewedvision.com/hc/en-us/articles/360041342354-Using-Transitions-In-ProPresenter)
  or the
  [ProPresenter 7 user guide](https://files.renewedvision.com/propresenter/support/Pro7UserGuide.pdf).
- **Observed** means a ProPresenter 21.4 build 352583705 document, saved by
  ProPresenter and decoded on August 16, 2026, contains the stated graph.
- **Inferred** means all inspected examples fit the interpretation, but a
  controlled UI-and-output experiment has not isolated it.

The checked-in behavioral fixtures currently contain no active build or text
Delivery graph. Native Delivery observations in this note therefore come from
a read-only scan of the authorized development workspace; an ordinary object
Build was also produced by a disposable native PowerPoint-import experiment.
They are useful implementation evidence, but small checked-in native fixtures
should replace them before authoring or rendering behavior is treated as
regression-tested.

## Product Model

| Product term | Scope | Behavior | Evidence |
| --- | --- | --- | --- |
| Slide transition | Whole slide | Controls how the incoming slide replaces the outgoing slide. It is not an object build. | Documented |
| Build In | One object | Introduces the object. An object can have at most one Build In. | Documented |
| Build Out | One object | Removes the object. An object can have at most one Build Out, after its Build In. | Documented |
| Delivery | Text Build In | Selects All at Once, By Bullet, or Underline behavior for the text. | Documented |
| Build Order | One slide | Orders object Build Ins, object Build Outs, and individual Delivery steps. | Documented for object builds; observed for Delivery steps |
| [Scrolling Text](https://support.renewedvision.com/hc/en-us/articles/4403013895059-Using-Scrolling-Text-in-ProPresenter) | One text object | Continuously moves text; it is a separate text-scroller feature, not Delivery. | Documented |

`reveal_type` is the schema name for Delivery. It should not be confused with
an effect whose display name happens to be “Reveal.”

### Text Delivery Modes

Renewed Vision documents three Delivery modes:

- **All at Once** builds the complete text object as one object.
- **By Bullet** delivers each carriage-return-separated line independently.
  Literal list or bullet styling is not required.
- **Underline** initially displays the non-underlined text and progressively
  reveals underlined portions, supporting fill-in-the-blank slides.

The format stores these as `NONE`, `BULLET`, and `UNDERLINE`. This is an example
where a semantic interface should use the product wording rather than expose
the protobuf enum names directly.

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
accepted UI range and saved-file handling of negative values still need a
controlled comparison. The persistent enum names are `ON_CLICK`, `WITH_PREVIOUS`,
`AFTER_PREVIOUS`, and `WITH_SLIDE`. `With Build` clearly corresponds to
`WITH_PREVIOUS`; `After Build` and the first-row `After Transition` appear to be
contextual labels for `AFTER_PREVIOUS`, but that label mapping still needs a
controlled saved-file comparison.

The user guide describes drag-grouping Build Order rows as changing the lower
row to **With Build**. The exact persistent rewrite performed by that grouping
still needs a controlled saved-file comparison.

### Playback Rules

Documented playback behavior matters to any future preview or timeline model:

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
`proCore.proto`. No current `pro-crud` path connects that runtime-looking value
to persisted authoring data, so it is not part of the model proposed here.
`Build.start` and `ChildBuild.start` have the same four numeric cases, although
the checked-in schema declares them as separate nested enum types.

## Native ProPresenter 21.4 Observations

Ordinary object builds use the straightforward graph: `element_build_order`
references the UUID of each `build_in` or `build_out`. Six inspected Theme
documents contain effect names Cut, Fade, Flip, and Wipe, plus On Click, With
Previous, After Previous, and nonzero delays. Build Ins and Build Outs can be
interleaved in the one slide schedule.

A controlled native PowerPoint import provides a second source of evidence. A
text-box Fade configured as a click effect in OOXML imported as an ordinary
Build In: the order referenced the Build UUID, `elementUUID` matched the text
element, the default/omitted start represented On Click, and the transition was
a ProPresenter Dissolve with the source animation's 0.5-second duration. It did
not create text Delivery children. This establishes one supported importer
mapping, not a general mapping for PowerPoint animation classes.

Text Delivery uses a different graph. In both inspected By Bullet examples:

- the element has a parent `build_in` containing the only stored transition;
- `childBuilds` contain the separately scheduled units and no transition;
- `element_build_order` references child-build UUIDs, not the parent Build In
  UUID.

The two native samples differ as follows:

| Sample | Text lines | `reveal_from_index` | Child indexes | Child indexes in build order |
| --- | ---: | ---: | --- | --- |
| A | 7 | 1 | 0–5 | 0–5 |
| B | 5 | 2 | 0–3 | 1–3 |

The samples support, but do not prove, this interpretation:

1. A By Bullet child index identifies a line after the initially visible first
   line, so an `N`-line value produces `N - 1` children.
2. `reveal_from_index` is the number of leading lines initially visible.
3. The ordered child range begins at `reveal_from_index - 1`.

Do not encode that formula until a controlled experiment has checked hard
returns, soft returns, blank lines, literal lists, and multiple initial lines.
No local native example establishes Underline segmentation.

Other compatibility observations constrain validation and cleanup:

- One genuine By Bullet Build In contains an `elementUUID` that does not match
  its containing element and no longer resolves within the document. A
  mismatch must initially be a warning, not an import error or automatic fix.
- Several ordinary text elements retain nonzero `reveal_from_index` values,
  including 1 and 2, while Delivery is `NONE` and no Build or children are
  active. This is dormant state that a lossless edit must preserve.
- One native sample omits a defined child from the order because it appears to
  be initially visible. A validator must not require every defined child to be
  scheduled.
- The text parent Build In is absent from the order in both native examples
  while child steps are present. That absence is not an orphan or incompleteness
  error.

## Current `pro-crud` Behavior

The binary layer already decodes and losslessly round-trips all known fields,
including unknown protobuf data. Graph copying regenerates element, Build, and
child-build UUIDs, then remaps known order and `elementUUID` references.

The supported semantic surface is much smaller:

- `dump` reports only the order UUIDs and aggregate Build In, Build Out, and
  child counts.
- Generic protobuf JSON patching can reach the raw fields, but it offers no
  graph invariants and is not safe build authoring.
- `set-text` rewrites the nested graphics RTF and base-font metadata, clears
  range-based custom text attributes, and preserves the containing
  slide-element wrapper. Existing child indexes and Delivery state therefore
  survive even if the new text has incompatible segmentation.
- Template resolution starts from the template slide wrapper. Assigned source
  text replaces the nested template text, so template Build and Delivery state
  survives while corresponding source wrapper state is discarded. Instantiating
  a new slide also copies the template state. The resolution report warns when
  either side has Build or Delivery state, but does not offer another precedence
  choice.
- Validation does not inspect build graphs.
- Static rendering ignores builds and draws the stored, unanimated composition:
  every non-hidden element eligible for normal painting is considered without
  evaluating Build In, Build Out, Delivery, or Build Order state.

This is good lossless transport, but it is not yet a supported build feature.

## Proposed Tool Surface

Build support should ship in stages. Inspection and warning-oriented validation
provide immediate value and create the evidence base for safe editing.

### 1. Resolved Inspection

Expand semantic dump JSON with a resolved slide timeline. Each entry should
include:

- its order index and UUID;
- owning element path, UUID, and name;
- kind: object Build In, object Build Out, or text Delivery step;
- direction, parent Build UUID, and child index where applicable;
- persisted start enum plus the contextual ProPresenter label when known;
- delay;
- transition duration, favorite UUID, effect UUID/name/render ID/category, and
  typed variables;
- Delivery mode and stored `reveal_from_index`;
- resolution status and warnings.

Also report unscheduled Build and child definitions separately. This is more
useful than a flat UUID array and avoids incorrectly calling native dormant or
initially-visible state invalid.

### 2. Warning-Oriented Validation

Add build diagnostics for:

- unresolved order UUIDs;
- duplicate definition UUIDs, order entries, or child indexes;
- a Build `elementUUID` that is empty, unresolved, or disagrees with its
  containing element;
- negative or non-finite durations and delays;
- a resolvable Build Out ordered before the same object's Build In;
- active Delivery children that cannot be associated with text units once
  segmentation is proven;
- unknown enum values or effect data that the semantic layer cannot interpret.

Diagnostics should preserve and report unknown values. They should not reject
the native exceptions listed above, require complete schedule coverage, repair
stale references automatically, or erase dormant scalar state.

### 3. Atomic Object-Build Editing

After checked-in native fixtures cover the start modes and order rules, expose
purpose-built operations to:

- set or clear one Build In or Build Out on an element;
- set its start and delay;
- insert, move, or group it in Build Order;
- copy a complete transition from another ProPresenter-authored build;
- remove every schedule reference atomically when a build is cleared.

Transition copying is the safest first authoring mechanism because effects are
open-ended typed graphs. Curated Cut and Dissolve constructors can follow once
their native encodings are fixture-backed. Do not make a hard-coded list of
transition names or render IDs the compatibility boundary.

A possible CLI shape is:

```sh
pro-crud edit set-build Talk.pro \
  --path '/cues[uuid="CUE"]/actions[uuid="SLIDE"]/slide/presentation/base_slide/elements[uuid="ELEMENT"]' \
  --direction in \
  --transition-from Source.pro \
  --transition-path '/cues[uuid="SOURCE"]/actions[uuid="SLIDE"]/slide/presentation/base_slide/elements[uuid="ELEMENT"]/build_in' \
  --start on-click \
  --delay 0 \
  --output Talk-built.pro
```

The exact command spelling is secondary to the invariants: create fresh UUIDs,
set the owning element reference, and update the schedule in one transaction.

### 4. Semantic Text Delivery

Once segmentation and `reveal_from_index` are proven, expose one operation that
sets Delivery atomically:

```sh
pro-crud edit set-text-delivery Talk.pro \
  --path '/cues[uuid="CUE"]/actions[uuid="SLIDE"]/slide/presentation/base_slide/elements[uuid="ELEMENT"]' \
  --mode by-bullet \
  --initial-units 1 \
  --output Talk-delivered.pro
```

The public choices should be `all-at-once`, `by-bullet`, and `underline`, with a
semantic count of initially visible units. The operation should generate or
remove the parent Build, children, UUIDs, indexes, and order entries together.
Advanced per-step timing should wait until native evidence proves which child
controls ProPresenter permits and how grouping is stored.

Raw child-array and `reveal_from_index` manipulation should remain an expert
escape hatch through generic patching, not the supported Delivery API.

Text replacement also needs an explicit policy when Delivery is active:

- `reject` if segmentation changes;
- `regenerate` the child graph using the semantic Delivery settings; or
- `preserve-raw` for a deliberate lossless expert edit.

Silently retaining a potentially stale graph should not be the long-term
default of the purpose-built command.

### 5. Explicit Template Policy

Template application now warns whenever the source or template has Build or
Delivery state. A future purpose-built operation should offer an explicit
policy:

- `template`: retain the template wrapper's Build and Delivery graph;
- `source`: transfer and remap source state onto assigned result elements;
- `clear`: remove Build and Delivery state from the result; or
- `reject`: stop when either side has Build or Delivery state.

The current behavior corresponds to `template`, but it should not become the
supported default until a native source/template matrix proves ProPresenter's
precedence and remapping behavior.

### 6. Build-State Rendering

After timeline and segmentation semantics are fixture-backed, static rendering
should retain `stored` for today's unanimated composition and add playback
states such as `initial`, `advance:N`, and `completed`, returning the resolved
timeline with the image. `advance:N` should represent an operator advance, not
a raw Build Order index, because **With Build** may group several ordered
entries into one advance.

Animated transition rendering and video export should come later. Correctly
simulating effect timing, overlapping With Build groups, slide transitions,
and Build Outs is a materially larger feature than selecting object visibility
at a stable step.

## Deliberate Non-Goals

- Do not wrap the official live HTTP API in `pro-crud`; this package edits
  files, while live control belongs to the separate ProPresenter API skill.
- Do not normalize stale `elementUUID` values or dormant reveal fields during
  unrelated edits.
- Do not claim that every effect can be rendered because its protobuf can be
  round-tripped.
- Do not infer text units from visual wrapping. By Bullet is documented around
  carriage returns, not rendered line wrapping.
- Do not make unchecked raw graph construction look like a supported workflow.

## Experiment Matrix

The smallest fixture set that can unlock editing and static build-state
rendering is:

1. **Ordinary object builds:** Build In, Build Out, and both; every start choice;
   zero and nonzero delay; Cut, Dissolve, and parameterized Wipe; reordered and
   grouped objects.
2. **By Bullet:** hard returns, soft returns, blank lines, literal and nested
   list formatting, wrapped lines, Unicode, and 0/1/2/all initially visible
   units.
3. **Underline:** one and several underlined runs, adjacent runs, mixed style
   boundaries, multiple paragraphs, and no underlined text.
4. **Lifecycle:** change text after Delivery, toggle modes, duplicate an
   element/slide/cue, copy across documents, reopen, export, and reimport.
5. **Themes:** built and unbuilt sources crossed with built, unbuilt, removed,
   unfilled, and mismatched template slots.
6. **Playback:** capture the initial state, every advance, grouped timing, the
   completed state, Build Out, clear/retrigger, reverse input, and slide
   replacement.
7. **Compatibility:** extend the established click-Fade PowerPoint import with
   supported and unsupported animation classes, plus disposable malformed
   copies containing orphan UUIDs, duplicate IDs/indexes, stale element
   references, out-of-range reveal indexes, and unknown enum/effect values.

Time-dependent validation should use Syphon video captures as diagnostic
evidence. Checked-in rendering references must still come from ProPresenter
**Export → Slide Images**, and those exports must not be assumed to encode a
particular runtime build state until a controlled experiment proves it.
