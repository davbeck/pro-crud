# ProPresenter 22 document descriptors

`schema.pb` is a versioned FileDescriptorSet from ProPresenter 22 beta build
369098875's `Contents/Frameworks/ProCore.framework/ProCore`, inspected on macOS
27.0.1. It contains 56 document/configuration descriptor files and their captured
dependencies. It contains no workspace content, credentials, artwork or fonts.
The standard `google/protobuf/descriptor.proto` dependency of custom options is
provided by SwiftProtobuf/protoc rather than extracted from the application.

`provenance.json` records the source binary SHA-256, descriptor-set SHA-256, and
each captured descriptor's binary offset/length/hash. Extraction located embedded
FileDescriptorProto records from their name through the syntax field, validated
protobuf boundaries, and compared the repeated descriptor copies in ProCore.
The original investigation found 5,634 copies of 165 descriptors with no
structural variants. See `Internal/Research/Format/ProPresenter22CodeAudit.md`.
This subset starts at presentation, Theme, playlist, Workspace, library,
calendar, key mapping, timeline, CCLI, clear-group, label, recording, macro, prop,
playlist-template and preference
documents, then includes their captured import closure.

These descriptors are separate from `Vendor/ProPresenter7Proto` and its generated
Swift types. Native materialization uses a descriptor-driven binary adapter;
it does not replace the 21 decoder or deserialize native diagnostic JSON as a
protobuf message. Changed nested layouts, cardinality, keyed maps, atomic values
and trees remain explicit. A decoded field is not a promise of editable or
renderable behavior.

`Scripts/sync-protobuf-assets.sh` copies this pinned descriptor into the Core
resource bundle; `--check` verifies freshness alongside the retained legacy
schema. Never replace this file with descriptors from a different app build
without updating provenance, versioned adapters, and native acceptance evidence.
