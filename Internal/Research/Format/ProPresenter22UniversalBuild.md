# Universal CLI qualification

October 15, 2026, macOS **27.0.1** on arm64. Checkpoints **468ddbb** and **a659c5f**.
This is local QA, not a published or notarized release.

`swift build -c release --arch arm64 --arch x86_64 --product pro-crud` succeeds
using the normal `.build` directory, including both Loro FFI slices. `lipo`
verifies **x86_64 and arm64** in the resulting universal binary.

The universal product passes the existing full CLI acceptance script, including
document editing, media packaging, all static output formats, embedded schema
resources and installed skills. Native inventory reads all **385** retained
streams with zero projection failures/issues; arrangement-reference inspection
finds the independently verified two links and zero uninspected streams.

Local ad-hoc signing with hardened runtime passes strict codesign verification;
the signed product still reads all 385 retained streams. The build's normal
resource bundles include the current, exact 21 baseline and native 22 descriptor
sets. The release script now explicitly requires the 21 descriptor resource as
well as the existing current/22 checks, covering the baseline used by every
versioned compatibility analysis.

The host cannot execute `/usr/bin/arch -x86_64 /usr/bin/true`: Rosetta is absent.
No installation or Intel host is required to continue local implementation.
Intel runtime coverage is a separate remaining qualification. Developer ID
signing, installer/notarization, and the complete transitive Rust license audit
remain release gates; ad-hoc signing does not satisfy those gates.

The a659c5f universal rebuild also passes strict local ad-hoc signature
verification, the full CLI acceptance script and all 385 retained native
projections. This includes the menu-map adapter and unknown-oneof diagnostics.

Checkpoint **153124d**, including group splitting and bounded native HLS
interchange, builds both architectures in 137.30 seconds. After local ad-hoc
hardened signing, strict codesign verification and full CLI/resource/skill
acceptance pass. An explicit `workspace inventory --projections` reports all
385 projections with **zero failures and zero issues**. Reference inspection
still reports exactly two links and zero uninspected streams. This verifies the
actual universal product, separately from the debug tests. The 727ede9 build
also completed; 153124d supersedes it for this qualification.
