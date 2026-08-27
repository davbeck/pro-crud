#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
proto_root="$repo_root/Vendor/ProPresenter7Proto/proto"
output_root="$repo_root/Sources/ProPresenterProto/Generated"
google_root="${PROTOBUF_INCLUDE:-/opt/homebrew/include}"

command -v protoc >/dev/null
command -v protoc-gen-swift >/dev/null
test -d "$google_root/google/protobuf"

rm -rf "$output_root"
mkdir -p "$output_root"
protos=()
while IFS= read -r proto; do
  protos+=("$proto")
done < <(find "$proto_root" -maxdepth 1 -name '*.proto' -print | sort)
protoc --swift_out="$output_root" --swift_opt=Visibility=Public -I"$proto_root" -I"$google_root" "${protos[@]}"
