# September 6, 2026: stale By Bullet Delivery

The user-provided `Sermon 2026-09-06.probundle` had four paragraphs on native
slide 9, with `revealFromIndex = 2`, child indexes 0 and 1, and both children
scheduled. Its initial state showed Physically, one advance had no visible
change, Culturally appeared later, and Spiritually never appeared (user report).
This graph is consistent with text replacement retaining a previous schedule;
the original authoring command history was not available.

Native ProPresenter 21.4 (352583705) experiments used the disposable library
duplicate `Sermon 2026-09-06-1`. Selecting Build From `2: Physically` produced
initial index 1 with three children 0–2 and all three scheduled. Build From
`1: Title` scheduled the parent before those children. Build From `3: Culturally`
retained all three children but scheduled only indexes 1 and 2. A separate
native text edit and Delivery mode reset checked blank paragraphs, a trailing
newline, and U+2028. Native base-slide extracts and provenance are in
`Fixtures/ProPresenter/TextDelivery`.

The new CLI repaired the original archive with `set-text-delivery
--initially-visible 1`. For native verification, a separately named copy was
imported as `ProCRUD Delivery Verification`, reusing existing media. The
Projector preview (configured for 3840×2160) showed heading only, then the
successive points, including Spiritually. The preview sometimes required a
layout refresh to repaint its completed animation; toggling the Media Bin
refreshed the final state without advancing a build. No renderer-generated
images were recorded as references.

The advertised `Syphon - 1` source returned no frames for either a stable
snapshot (45-second timeout) or a five-second recording. Verification therefore
used ProPresenter's own Projector preview, not an independent Syphon capture.

The original bundle was not modified. A repaired bundle is in ignored `dist/`.
The two native test presentations remain in Main Service Sections: the editor
reported their deletion as irreversible, so the cleanup dialog was cancelled.
The Media Bin was restored and no screen configurations were changed.
