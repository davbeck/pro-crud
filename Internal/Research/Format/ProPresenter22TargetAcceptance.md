# Creation-profile native delivery probe

October 14, 2026, macOS 27.0.1, ProPresenter **22 build 369098875**.
The exact build was verified in About ProPresenter. General Settings showed
active workspace **LSSS**, which resolved to exactly one registered local root,
`49c14fcc-d6b9-4c12-839e-a76c2d536358`. The user has authorized this instance as
a test host. No account settings, helper installations, or output routing changed.

Created two fresh 854×480 presentations using the new CLI: one with explicit
target 21, one with target 22. Both contain one cyan rectangle at
100,100,300,200. Bundled each with its requested profile, then imported through
File → Import → File into the existing MISC library, with No Playlist selected.
Their unique names are `ProCRUDTarget21Acceptance` and
`ProCRUDTarget22Acceptance`.

Both imports succeeded. In the native editor, changed the presentation's CCLI
title to `Native Acceptance 21` / `Native Acceptance 22` using keyboard input
and tabbing out of the inspector field. Native Presentation export to separate
folders preserved those edits; the CLI decoded both outputs and verified the
native song titles, one cue, new root UUIDs, and retained cue/action identities.
Unmodified native exports are checked in under `Fixtures/ProPresenter22/Interchange`.
Generated input bundles, an initial export, and diagnostics remain in ignored
`.build/pro22-native-acceptance/`.

An earlier AX setter changed a cue-name widget's displayed text but did not
commit the model; native export retained `Slide 1`. That attempted edit is not
counted as acceptance evidence. Similarly, Add Slide opened a Theme chooser;
it was canceled without inserting content. The subsequent keyboard-driven
CCLI edit is the verified native change.

The two generated presentations remain in MISC for review (15 items before,
17 afterward). Cleanup through the global Edit → Delete command reached a
library-deletion confirmation instead of the selected presentation; it was
canceled. No library or existing presentation was deleted. A later cleanup
must focus the exact presentation row and verify the named target and recovery
behavior before confirming deletion.

This establishes basic **21-profile → 22** and **22-profile → 22** delivery
plus continued native editing/re-export for this small media-free case.
It does not establish delivery into 21.4, app/helper restart persistence,
native CRDT editing by the CLI, rendering parity, new 22 features, or Cloud
behavior. No live Audience/Stage trigger was used and no new reference image
was substituted for the retained 21.4 rendering references.
