# Versioned timeline and key-mapping wire compatibility

October 15, 2026. Sources are the separately pinned exact 21.4 descriptor set and
the descriptor set extracted from installed 22 beta build 369098875. The
historical generated Swift decoder remains unchanged.

The compatibility analyzer now selects explicit descriptor views for
TimedPlayback Sequence/SequenceItem and legacy CollectionElementType payloads.
A public protobuf-root overload allows configuration/runtime roots to receive
the same structured report as Presentation/Theme/playlist dependency traversal.
This is wire compatibility analysis, not native execution or runtime automation.

- Common KeyMapping target fields retain the same UUID field 1 and string name
  field 2 in both layouts. They require no UUID/name conversion and encode
  identically with the independent descriptors.
- The 21.4 mapping target can include recursive parent scope at field 3. A 21
  target preserves it. A 22 mapping's CollectionElementTypeKey cannot represent
  that scope, so target 22 now reports `key-mapping-parent-scope` rather than
  treating opaque preserved bytes as equivalent lookup behavior.
- One embedded timeline Presentation encodes identically in the singular 21.4
  field 3 and repeated 22 field 3. It is analyzed recursively without decoding
  through a singular generated type.
- Multiple field-3 Presentation payloads cannot be delivered as a 21 singular
  value without protobuf merging. Target 21 reports
  `multi-presentation-timeline`. Per-item Presentation UUID field 8 independently
  reports `timeline-presentation-reference` for 21. No flattening fallback is
  performed. Target 22 retains both known structures and every occurrence.
- Embedded Presentation/media/graph features are still recursively analyzed;
  recognizing the timeline shape does not qualify its dependencies.

Tests encode against both pinned descriptors, retain the historical decoder's
opaque payload bytes, check independent issue paths/source/target values, and
include an active native graph nested inside a timeline as a negative control.
Existing repeated-message/singular-merge tests remain intact. No new receiving-
app timeline or mapping execution claim is made; a 21 app is unavailable.
