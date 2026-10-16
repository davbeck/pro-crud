#!/usr/bin/env bash
set -euo pipefail

# Build the generator from the same resolved package as the protobuf runtime.
# Use its normal SwiftPM build directory, without requiring a global plugin.
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
swift package --package-path "$repo_root" resolve >&2
swift_protobuf_root="$repo_root/.build/checkouts/swift-protobuf"
swift build --package-path "$swift_protobuf_root" --product protoc-gen-swift >&2
swift_protobuf_bin="$(swift build --package-path "$swift_protobuf_root" --show-bin-path)"
printf '%s/protoc-gen-swift\n' "$swift_protobuf_bin"
